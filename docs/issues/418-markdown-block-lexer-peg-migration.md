---
ID: 418
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] マークダウン・ブロック構文解析 (MarkdownLexer) の PEG 化と頑健性向上 (ID: 418)

## 1. 概要 / Summary

Web フロントエンドのマークダウンコンパイラ（`site/js/lexer.js`）は、現在行単位の文字列判定と正規表現（`startsWith('```')`, `match(/^#{1,6}\s+/)`, `split('|')` など）でトークナイズを行っている。
特にテーブルセル内のエスケープされたパイプ（`\|`）やインラインコード内のパイプ（`` `|` ``）で列数が狂う問題、複数行引用やリストのネスト構造が欠落する問題が存在する。

本 Issue では、ブロック構文解析（FencedCodeBlock, Heading, Table, List, Blockquote, Paragraph, HR）を PEG 文法（または PEG コンビネータ）を用いて再構築し、Issue #417 で PEG 化された `evaluator.js`（インラインパーサー）と完全に整合する決定論的な 2 パス Markdown コンパイラを確立する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第13節 Phase 6: Web フロントエンド連携 ＆ JavaScript コードジェネレータ基盤仕様)
- **関連 Issue**:
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`site/js/lexer.js`](../../site/js/lexer.js)（ブロックパーサーの PEG コンビネータ刷新）
- [ ] [`site/js/parser.js`](../../site/js/parser.js)（AST 構築とノード階層構造の整合）
- [ ] [`site/js/markdown_compiler.js`](../../site/js/markdown_compiler.js)（パイプラインオーケストレーション）
- [ ] [`site/app-min.js`](../../site/app-min.js)（Closure Compiler ビルド成果物）
- [ ] [`site/dashboard-min.js`](../../site/dashboard-min.js)（Closure Compiler ビルド成果物）
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py)（ブロックパース単体・回帰テスト）

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/418-markdown-block-lexer-peg-migration`

1. **テーブルパーサーの PEG 化**:
   - 行を行単位でパースする際、セル境界パイプ（`|`）とエスケープ（`\|`）、コードスパン保護を厳密に区別する PEG 規則を導入。
2. **ブロック要素の宣言的トークナイズ**:
   - FencedCodeBlock（Mermaid 含む）、見出し（H1〜H6）、水平線（HR）、引用（Blockquote）、リスト（UL/OL）、段落（Paragraph）を PEG 規則で構造化。
3. **AST 構築 (`parser.js`) の連携**:
   - トークンストリームから階層型 AST を生成する処理の型定義・整合性を担保。
4. **テスト作成 & ビルド**:
   - `tests/web/test_frontend_frameworks.py` にエスケープパイプを含むテーブル、ネスト引用のテストケースを追加。
   - `make build_js` で Closure Compiler 最適化ビルドを実行。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `site/js/lexer.js` が PEG コンビネータベースで動作し、エスケープパイプ `\|` やインラインコードを含むテーブルが正確にパースされること。
- [ ] 見出し、コードブロック、リスト、引用、段落のパースが回帰なく動作すること。
- [ ] `make build_js` が 0 エラーで完了し、`app-min.js` および `dashboard-min.js` に正常にバンドルされること。
- [ ] `tests/web/test_frontend_frameworks.py` のテストがすべて PASS すること。
