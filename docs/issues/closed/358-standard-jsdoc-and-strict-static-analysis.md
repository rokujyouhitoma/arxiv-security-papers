---
ID: 358
種別: Quality
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] 柱 3: TypeScript 不要の「標準 JSDoc 契約定義と Closure Compiler 厳格静的検査」整備 (ID: 358)

## 1. 概要 / Summary
TypeScript やそのコンパイラツールチェーン（`tsc`）に依存することなく、ブラウザでそのまま解釈・実行可能な Pure JavaScript の透明性を保ちながら、標準の JSDoc アノテーションと Google Closure Compiler の厳格型検査（`--warning_level=VERBOSE`, `--jscomp_error=checkTypes`, `--jscomp_error=checkVars`）を活用して、エンタープライズ級の型安全性と契約駆動開発を確立する。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue:
  - [355-refactor-namespace-from-yuzora-to-application.md](closed/355-refactor-namespace-from-yuzora-to-application.md)
  - [356-eliminate-inline-scripts-and-modularize-by-domain.md](closed/356-eliminate-inline-scripts-and-modularize-by-domain.md)
  - [357-pure-python-bundling-and-build-pipeline.md](closed/357-pure-python-bundling-and-build-pipeline.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [site/externs.js](../site/externs.js) (外部インターフェース・型契約の網羅)
- [x] [site/app.js](../site/app.js) (SceneCtor 型定義および JSDoc アノテーション修正)
- [x] [site/js/dashboard.js](../site/js/dashboard.js) (引数型、Node.prototype.contains 引数キャスト、オプショナル引数 JSDoc)
- [x] [scripts/compile_frontend.py](../scripts/compile_frontend.py) (厳格静的検査の自動化)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/358-strict-jsdoc-static-analysis`

1. **`site/externs.js` の型契約拡充**:
   - `toggleGraphControlDeck(forceState=)`、`toggleDashboardHeader(forceState=)` のオプショナル引数宣言。
   - `SceneCtor` / `SceneInterface` の型定義。
   - Telemetry 行オブジェクト（`SpiderTaskRecord`, `SpiderHistoryResponse`, `TelemetryRunRecord`, `LifecycleTelemetry`, `GraphTelemetry` 等）の型定義。
2. **`site/app.js` & `site/js/dashboard.js` の JSDoc アノテーション修正**:
   - `SceneCtor` 継承時の JSDoc 型アノテーションの正常化（`@extends {SceneCtor}`, `@override`）。
   - `e.target` が `Node` / `Element` であることの型ガード / キャスト。
3. **静的検査パイプラインの検証**:
   - `scripts/compile_frontend.py` 経由での Closure Compiler VERBOSE コンパイルがエラー 0 件であることを確認。
   - 既存全 175 件の Web テストが PASS することを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 主要な関数・クラスに標準 JSDoc 型アノテーションが 100% 付与されていること。
- [x] Google Closure Compiler の厳格型検査モードが 0 Errors で通過すること。
- [x] TypeScript 関連の npm 依存を 1 つも追加せずに型安全性が証明されること。
- [x] 既存の全テストスイートが 100% PASS すること。

