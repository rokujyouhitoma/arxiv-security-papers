---
ID: 422
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Mermaid ダイアグラムのクライアント側事前構文検証およびフォールバックサニタイザーの実装 (ID: 422)

## 1. 概要 / Summary

Web コンソールおよびマークダウンビューア（`site/js/markdown_compiler.js`）では、レポートや論文サマリー内の Mermaid コードブロック（マインドマップ、フローチャート等）をレンダリングする際、コードをそのまま `mermaid.run()` に渡している。
このため、コード内に構文エラー（不正なノード名、エスケープされていない特殊文字、インデント不整合等）が含まれる場合、Mermaid エンジンが致命的な描画例外をスローし、画面上に巨大な赤文字の構文エラーブロックが表示され、ユーザー体験を損ねてしまう（Issue #415 での課題）。

本 Issue では、主要な Mermaid ダイアグラム構文（特に `mindmap`, `graph`, `flowchart`）に対する軽量な PEG 事前検証パーサー（Pre-validator / Sanitizer）を実装する。レンダリング直前に構文の健全性を判定し、不正な構文を安全にサニタイズ（エスケープ補正）、または親切なフォールバック表示（安全なプレビューとコード表示）を行う仕組みを構築する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第13節 Phase 6: Web フロントエンド連携 ＆ JavaScript コードジェネレータ基盤仕様)
- **関連 Issue**:
  - Issue #415: Mermaid mindmap 構文エラーの解消とトレンド分析マインドマップ描画の正常化
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`site/js/markdown_compiler.js`](../../site/js/markdown_compiler.js)（`renderMermaid` 前段での構文事前チェックとサニタイズ）
- [ ] [`site/js/frameworks/mermaid-validator.js`](../../site/js/frameworks/mermaid-validator.js)（新規作成: Mermaid 軽量 PEG バリデーター）
- [ ] [`site/app-min.js`](../../site/app-min.js)（Closure Compiler ビルド成果物）
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py)（Mermaid 事前検証およびサニタイズテスト）

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/422-mermaid-diagram-pre-validation-and-sanitizer`

1. **Mermaid サブセット PEG 文法の定義**:
   - `mindmap`: ルートノード、インデント階層、ノードラベル（`(...)`, `[...]`, `((...))`）。
   - `graph` / `flowchart`: ディレクティブ（`TD`, `LR` 等）、ノード定義、接続エッジ（`-->`, `---`, `-.->`）。
2. **`mermaid-validator.js` の実装**:
   - PEG コンビネータを用いて、入力テキストが Mermaid 仕様に適合しているかを高速判定。
   - ラベル内の危険文字（未クォートの括弧や特殊文字）の自動クォート補正を行うサニタイザー。
3. **`markdown_compiler.js` への統合**:
   - `renderMermaid()` 実行前に `MermaidValidator.validate(code)` を呼び出し、エラー時はサニタイズ補正を試行。補正不能な場合はクラッシュせず、洗練された警告付きコードブロックとしてフォールバック表示。
4. **テスト & ビルド**:
   - 壊れた構文および正常構文の双方に対する回帰テストを追加し、`make build_js` を実行。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] Mermaid コードブロックに対する軽量 PEG バリデーター `site/js/frameworks/mermaid-validator.js` が実装されること。
- [ ] 不正構文を含む Mermaid コードが与えられた場合でも、画面上に巨大な赤文字エラーが出ず、サニタイズまたは安全なフォールバック表示が行われること。
- [ ] 正常なマインドマップおよびフローチャートが回帰なく美しく描画されること。
- [ ] `make build_js` が 0 エラーで完了すること。
- [ ] 自動テストが 100% PASS すること。
