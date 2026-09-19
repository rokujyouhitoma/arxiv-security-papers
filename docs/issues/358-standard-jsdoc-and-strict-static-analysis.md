---
ID: 358
種別: Quality
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 柱 3: TypeScript 不要の「標準 JSDoc 契約定義と Closure Compiler 厳格静的検査」整備 (ID: 358)

## 1. 概要 / Summary
TypeScript やそのコンパイラツールチェーン（`tsc`）に依存することなく、ブラウザでそのまま解釈・実行可能な Pure JavaScript の透明性を保ちながら、標準の JSDoc アノテーションと Google Closure Compiler の厳格型検査（`--warning_level=VERBOSE`, `--check_types`）を活用して、エンタープライズ級の型安全性と契約駆動開発を確立する。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue:
  - [355-refactor-namespace-from-yuzora-to-application.md](355-refactor-namespace-from-yuzora-to-application.md)
  - [357-pure-python-bundling-and-build-pipeline.md](357-pure-python-bundling-and-build-pipeline.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [site/externs.js](../site/externs.js) (外部インターフェース・型契約の網羅)
- [ ] [site/js/frameworks/*.js](../site/js/frameworks/) (JSDoc アノテーションの精緻化)
- [ ] [site/js/console/](../site/js/console/) (新モジュールの JSDoc 定義)
- [ ] [site/js/dashboard/](../site/js/dashboard/) (新モジュールの JSDoc 定義)
- [ ] [scripts/compile_frontend.py](../scripts/compile_frontend.py) (厳格型チェックフラグの有効化)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/358-strict-jsdoc-static-analysis`

1. **JSDoc によるインターフェース・データ型定義の標準化**:
   - `@typedef`, `@param`, `@return`, `@constructor`, `@struct` などの標準タグを徹底。
   - 戻り値の Nullable/Non-nullable（`?` vs `!`）を明確化し、実行時 Null 安全性を担保。
2. **`site/externs.js` の包括的整備**:
   - `window.Application` 以下の全モジュール、メソッド、およびブラウザ Web API（Fetch API, SSE, DOM）の型契約を externs として完全網羅。
3. **Closure Compiler 厳格検査の自動化**:
   - `scripts/compile_frontend.py` において型不一致（Type Mismatch）、未定義プロパティアクセス、引数過不足をエラーとして検知するチェックモードを追加。
   - Makefile の `make check` / `make static_analysis` ターゲットに組み込み。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 主要な関数・クラスに標準 JSDoc 型アノテーションが 100% 付与されていること。
- [ ] Google Closure Compiler の厳格型検査モードが 0 Errors で通過すること。
- [ ] TypeScript 関連の npm 依存を 1 つも追加せずに型安全性が証明されること。
- [ ] 既存の全テストスイートが 100% PASS すること。
