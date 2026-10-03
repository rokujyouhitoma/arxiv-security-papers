---
ID: 426
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] JS 生成パーサーにおける PEGSyntaxError 診断情報拡充と parseWithDiagnostics API の実装 (ID: 426)

## 1. 概要 / Summary

検索窓のリアルタイム構文検証・オートコンプリート（Issue #420）や Mermaid 事前構文チェック（Issue #422）では、ユーザーのタイピング中に「構文が合致しているか」「どの文字位置で何が期待されていたか（`expectedTokens`）」「エラー箇所の行・列・スニペット」を例外（`throw`）による処理中断を伴わずに高速取得できる API が不可欠である。
しかし、現在の `JSCodeGenerator`（`src/core/structures/peg_compiler/codegen_js.py`）が提供するファサード API は例外を投げる `parse(text)` のみであり、`PEGSyntaxError` にも `expectedTokens` などの詳細診断コンテキストがアタッチされていない。

本 Issue では、`PEGSyntaxError` に `expectedTokens`、`farthestPos`、`snippet` などの診断メタデータを正式に保持させるとともに、例外を発生させず診断結果オブジェクト `{ success: boolean, value: any, diagnostics: { errorMsg, line, col, farthestPos, expectedTokens, snippet } }` を直接返す `parseWithDiagnostics(text)` API をパーサーファサードに標準配備する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [`docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第12.3節 耐障害構文解析 & 高度構文診断 Issue #306、第13節 Phase 6 JavaScript コードジェネレータ基盤)
- **関連 Issue**:
  - Issue #306: 耐障害構文解析 & 高度構文診断
  - Issue #417: WebフロントエンドJS向けPEGインラインパーサー換装およびPEG AOTコンパイラ JavaScriptコードジェネレータ基盤の実装
  - Issue #420: 検索窓における Lucene PEG リアルタイム構文検証・エラーハイライト・オートコンプリートの実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/core/structures/peg_compiler/codegen_js.py`](../../src/core/structures/peg_compiler/codegen_js.py)（`PEGSyntaxError` の拡張、`parseWithDiagnostics` ファサードメソッドの出力）
- [ ] [`tests/test_peg_compiler_js.py`](../../tests/test_peg_compiler_js.py)（診断 API の単体テスト）

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/426-peg-js-syntax-error-diagnostics-and-tolerant-api`

1. **`PEGSyntaxError` の機能拡充**:
   - `PEGSyntaxError(message, offset, line, col, expectedTokens, snippet)` にシグネチャを拡張。
2. **`parseWithDiagnostics` ファサードメソッドの実装**:
   - `ParseContext` の最大到達位置（`maxPos`）と `expectedTokens`、行桁スニペットを取得。
   - パース成功時は `{ success: true, value: res.value, diagnostics: null }`、失敗時は `{ success: false, value: null, diagnostics: { ... } }` を返却（例外をスローしない）。
3. **テスト検証**:
   - 故意に不正な入力を与えた際、期待されるトークン群とエラー位置が正確に構造化されて返されることを Node.js 上でテスト。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `PEGSyntaxError` に `expectedTokens`、`farthestPos`、`snippet` が保持されること。
- [ ] `parseWithDiagnostics(text)` が例外を投げずに完全な診断オブジェクトを返すこと。
- [ ] 既存の `parse(text)` メソッドの動作に回帰がないこと。
- [ ] Xenon Rank A、flake8、mypy --strict をクリアすること。
- [ ] 単体・回帰テストが 100% PASS すること。
