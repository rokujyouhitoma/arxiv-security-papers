---
ID: 418
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] マークダウン・ブロック構文解析 (MarkdownLexer) の PEG 化と頑健性向上 (ID: 418)

## 1. 概要 / Summary

Web フロントエンドのマークダウンコンパイラ（`site/js/lexer.js`）は、これまで単純な行単位の文字列判定と正規表現（`startsWith('```')`, `match(/^#{1,6}\s+/)`, `split('|')` など）でブロックトークナイズを行っていた。
このため、特に以下の課題が存在していた：
1. **テーブルセル内のパイプ保護欠落**: セル内のエスケープされたパイプ（`\|`）やインラインコードスパン内のパイプ（`` `|` ``）で列数が狂い、テーブルレイアウトが完全に崩壊する。
2. **リスト構文の限定性**: 番号付きリスト（`1. `, `2. `）や先頭インデントの対応が欠落している。
3. **ReDoS リスク**: 複雑な行正規表現による潜在的なバックトラッキングリスク。

本 Issue では、ブロック構文解析（FencedCodeBlock, Heading, Table, List, Blockquote, Paragraph, HR）のトークナイズ処理に PEG (Parsing Expression Grammar) コンビネータおよび構文規則を導入し、特にテーブル行パースにおいてエスケープパイプおよびインラインコードスパンを決定論的に保護する。これにより、Issue #417 で PEG 化された `evaluator.js`（インラインパーサー）と完全に整合する決定論的な 2 パス Markdown コンパイラを確立する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第13節 Phase 6: Web フロントエンド連携 ＆ JavaScript コードジェネレータ基盤仕様)
- **関連 Issue**:
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装
  - Issue #419: クライアントサイド CTI グラフクエリ DSL の AOT 生成とダッシュボード統合
  - Issue #420: 検索窓における Lucene PEG リアルタイム構文検証・エラーハイライト・オートコンプリートの実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### フロントエンド JavaScript
- [ ] [`site/js/lexer.js`](../../site/js/lexer.js)（PEG ベースのテーブル行・ブロックトークナイザー実装）
- [ ] [`site/js/parser.js`](../../site/js/parser.js)（AST 構築とノード階層構造の整合）
- [ ] [`site/js/markdown_compiler.js`](../../site/js/markdown_compiler.js)（パイプラインオーケストレーション）
- [ ] [`site/app-min.js`](../../site/app-min.js) & [`site/dashboard-min.js`](../../site/dashboard-min.js)（Closure Compiler ビルド成果物）

### テストスイート & ビルド
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py)（エスケープパイプを含むテーブル、番号付きリスト、ブロックパースの自動テスト追加）
- [ ] [`Makefile`](../../Makefile)（品質ゲート確認）

---

## 4. セキュリティ分析 (STRIDE Threat Model) と防御策

| 脅威分類 | 潜在的リスク | 防御策 |
| :---: | --- | --- |
| **Spoofing** | 不正な文字シーケンスによる別ブロック要素の偽装 | PEG の先頭一致・優先順序（Ordered Choice）により、コードブロック（最優先）、テーブル、見出し、リスト、パラグラフを厳格に順序付けて分類。 |
| **Tampering** | エスケープ文字やパイプによるテーブル構造の改ざん | セルパーサーにおいてエスケープシーケンス（`\|`）とコードスパン（`` `...` ``）を独立した PEG 規則で認識・保護し、列構造を厳密に維持。 |
| **Repudiation** | トークナイズ失敗時の不透明性 | 不正なテーブル行や不整合なブロックは安全に PARAGRAPH トークンへフォールバックし、パース例外によるレンダリング停止を防止。 |
| **Information Disclosure** | パース例外によるスタックトレースの漏洩 | 例外を捕捉し、安全なフォールバックトークン列を返却。 |
| **Denial of Service (ReDoS)** | ネストした記号や巨大テキストによるブラウザフリーズ | 正規表現バックトラッキングを排除し、Packrat PEG / 単一パス線形スキャンによる $O(N)$ パース時間を保証。 |
| **Elevation of Privilege** | 特権昇格 / HTML インジェクション | セルおよびブロックの生テキストを安全に保持し、後段の `evaluator.js` における HTML エスケープと連携。 |

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/418-markdown-block-lexer-peg-migration`

### 5.1 PEG テーブル行パーサーの実装 (`site/js/lexer.js`)
1. **PEG ランタイム連携**:
   - `window.Application.frameworks.peg`、`require('./frameworks/query-validator.js').peg`、または内蔵コンビネータにより、PEG 規則を構築。
2. **テーブルセル抽出の PEG 規則**:
   - `EscapedPipe <- '\\|'` → エスケープされたパイプとしてセル内に保持。
   - `CodeSpan <- '`' [^`\n]* '`'` → インラインコードスパン内のパイプは区切り文字とみなさない。
   - `CellText <- [^|`\\\n]+` → 通常文字の連続。
   - `CellItem <- EscapedPipe / CodeSpan / CellText / .`
   - `Cell <- CellItem*`
   - 行全体を `|` で区切りつつ各セルを正確に抽出。
3. **ヘッダー・セパレータ行判定**:
   - `| :---: | --- |` 等の境界区切り行を PEG で判定し、アライメント情報を正確に識別。

### 5.2 ブロック要素のトークナイズ拡充
1. **リストの拡張**:
   - 箇条書き（`- `, `* `, `+ `）に加え、番号付きリスト（`1. `, `2. ` 等）をサポート。
2. **Fenced Code Block & Mermaid**:
   - 言語指定（` ```mermaid `, ` ```python ` 等）の抽出とコード行の完全保持。
3. **見出し・引用・水平線**:
   - H1〜H6、`>` 引用、`---` / `***` 水平線の正確なトークナイズ。

### 5.3 テスト & ビルド検証
1. `tests/web/test_frontend_frameworks.py` にテーブルエスケープパイプ（`\|`）およびコード内パイプ（`` `a | b` ``）のパース検証テストを追加。
2. `make build_js`（Google Closure Compiler `strict=True`）による 0 エラーコンパイルの確認。
3. `make check`（フォーマット、静的解析、全テスト）の 100% PASS を確認。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `site/js/lexer.js` に PEG ベースのテーブル行パーサーが実装され、エスケープパイプ `\|` やインラインコード内のパイプを含むテーブルが正確にパースされること。
- [x] 番号付きリスト（`1. ` 等）を含むリストおよび FencedCodeBlock, Heading, Blockquote, HR が回帰なく動作すること。
- [x] `make build_js`（Google Closure Compiler）が 0 エラーで完了し、`site/app-min.js` および `site/dashboard-min.js` が正常に生成されること。
- [x] `tests/web/test_frontend_frameworks.py` の自動テストが全件 PASS すること。
- [x] Xenon Rank A、flake8、mypy --strict src を 100% パスすること。
