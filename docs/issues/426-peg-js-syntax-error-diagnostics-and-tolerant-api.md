---
ID: 426
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] JS 生成パーサーにおける PEGSyntaxError 診断情報拡充と parseWithDiagnostics API の実装 (ID: 426)

## 1. 概要 / Summary

検索窓のリアルタイム構文検証・オートコンプリート（Issue #420）や Mermaid 事前構文チェック（Issue #422）では、ユーザーのタイピング中に「構文が合致しているか」「どの文字位置で何が期待されていたか（`expectedTokens`）」「エラー箇所の行・列・スニペット」を例外（`throw`）による処理中断を伴わずに高速取得できる API が不可欠である。
しかし、現在の `JSCodeGenerator`（`src/core/structures/peg_compiler/codegen_js.py`）が提供するファサード API は例外を投げる `parse(text)` のみであり、`PEGSyntaxError` にも `expectedTokens` などの詳細診断コンテキストがアタッチされていない。

本 Issue では、`PEGSyntaxError` に `expectedTokens`、`offset`、`line`、`col`、`snippet` などの診断メタデータを正式に保持させるとともに、例外を発生させず診断結果オブジェクト `{ success: boolean, value: any, diagnostics: { errorMsg, offset, line, col, expectedTokens, snippet } | null }` を直接返す `parseWithDiagnostics(text)` API をパーサーファサードに標準配備する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第12.3節 耐障害構文解析 & 高度構文診断 Issue #306、第13節 Phase 6 JavaScript コードジェネレータ基盤)
- **関連 Issue**:
  - Issue #306: 耐障害構文解析 & 高度構文診断
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装
  - Issue #420: 検索窓における Lucene PEG リアルタイム構文検証・エラーハイライト・オートコンプリートの実装
  - Issue #422: Mermaid ダイアグラムのクライアント側事前構文検証およびフォールバックサニタイザーの実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### コンパイラ & ランタイム基盤
- [x] [`src/core/structures/peg_compiler/codegen_js.py`](../../src/core/structures/peg_compiler/codegen_js.py)
  - `PEGSyntaxError` コンストラクタ引数拡張（`expectedTokens`, `snippet`）
  - `ParseContext.prototype.getSnippet` ヘルパー追加
  - `Parser.prototype.parseWithDiagnostics` メソッドの実装
  - `Parser.prototype.parse` における `PEGSyntaxError` への詳細メタデータ引渡し
  - 生成パーサークラスファサードへの `parseWithDiagnostics` の配備

### テスト
- [x] [`tests/test_peg_compiler_js.py`](../../tests/test_peg_compiler_js.py)
  - 正常入力時の `parseWithDiagnostics`（`success: true, diagnostics: null`）検証
  - 不正構文入力時の `parseWithDiagnostics`（`success: false, diagnostics: { line, col, offset, expectedTokens, snippet }`）検証
  - 不正入力時の `parse` スロー例外 `err.expectedTokens`, `err.snippet` 検証

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/426-peg-js-syntax-error-diagnostics-and-tolerant-api`

### 4.1 `PEGSyntaxError` の機能拡充
- `function PEGSyntaxError(message, offset, line, col, expectedTokens, snippet)`
- `this.expectedTokens = expectedTokens || [];`
- `this.snippet = snippet || '';`

### 4.2 `ParseContext.prototype.getSnippet` の実装
- エラー位置の前後にマージン（例: 前後20文字）を持たせた該当テキストスライスを抽出。

### 4.3 `Parser.prototype.parseWithDiagnostics` の実装
- `parseWithDiagnostics(text)` は例外を一切スローしない。
- パース結果が成功かつ全文字消費（`res.nextPos === ctx.length`）の場合は `{ success: true, value: res.value, diagnostics: null }` を返却。
- パース失敗または未消費文字が存在する場合は `{ success: false, value: null, diagnostics: { errorMsg, offset, line, col, expectedTokens, snippet } }` を返却。

### 4.4 ファサードメソッドの出力
- `_emit_facade_methods` に `{class_name}.prototype.parseWithDiagnostics = function(text) { return this.rootParser.parseWithDiagnostics(text); };` を追加。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `PEGSyntaxError` に `expectedTokens`、`offset`、`line`、`col`、`snippet` が保持されること。
- [ ] `parseWithDiagnostics(text)` が例外を投げずに完全な診断オブジェクトを返すこと。
- [ ] 既存の `parse(text)` メソッドの動作に回帰がなく、スローされる例外にも診断情報が付与されること。
- [ ] Xenon Rank A、flake8、mypy --strict をクリアすること。
- [ ] 単体・回帰テストが 100% PASS すること。
