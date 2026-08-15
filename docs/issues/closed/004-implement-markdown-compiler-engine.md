---
ID: 004
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] Lexer, Parser, AST, Evaluator, Renderer による Markdown Compiler Engine の構築 (ID: 004)

## 1. 概要 / Summary
Web UI においてエグゼクティブサマリーおよび OKF 論文のマークダウンがプレーンテキストとして露出していた問題を解消するため、クライアントサイドにおける Lexer/Tokenizer, Parser, AST, Evaluator, Renderer 5層構成の Markdown Compiler Engine を実装し、見出し・テーブル表・Mermaidダイアグラムのグラフィカル描画を実現します。

---

## 2. トレーサビリティ / Traceability
- **設計書**: `docs/designs/DSN-01-high_level_design.md`, `docs/designs/DSN-02-low_level_design.md`
- **コンパイラ仕様**: Lexer ➔ Parser ➔ AST ➔ Evaluator ➔ HTML/Mermaid Renderer

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [`site/markdown_compiler.js`](../../site/markdown_compiler.js): Markdown Compiler Engine 本体
- [x] [`site/index.html`](../../site/index.html): スクリプトタグ読み込み追加
- [x] [`site/style.css`](../../site/style.css): テーブル、見出し、Mermaid コンテナ用のCSSデザイン
- [x] [`site/app.js`](../../site/app.js): トレンド表示および OKF モーダルへのコンパイラ統合

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/004-implement-markdown-compiler-engine`

1. **`site/markdown_compiler.js` の開発**:
   - `Lexer`: マークダウン文字列のトークナイズ。
   - `Parser`: 抽象構文木 (AST) 構築。
   - `Evaluator`: AST インライン装飾および Mermaid ID 解決。
   - `Renderer`: DOM HTML 変換および `mermaid.run()` 非同期描画。
2. **UI 組み込み ＆ テスト**:
   - `site/app.js` の `fetchTrends` および `openPaperModal` に `MarkdownCompiler.compile()` を適用。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] サマリー内のテーブルが綺麗な Glassmorphism `<table>` として表示されること。
- [x] Mermaid コードブロックがインタラクティブなダイアグラム図としてブラウザ描画されること。
- [x] `make py_compile` および `make test` が 100% PASS すること。
