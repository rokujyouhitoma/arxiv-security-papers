---
ID: 882
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT] 部分評価後の残余関数における Contification 保証の検証 (ID: 882)

## 1. 概要 / Summary
DSN-33-03 §5.4 に基づき、部分評価で生成された相互再帰・自己再帰する残余関数群が、Pass 100（`100_contify`）および LIR バックエンドにおいて確実に単一の平坦なループ（`%cont-fun`, `%cont-call`, 基本ブロックローカルジャンプ）へ融合され、クロージャ割り当て（Heap Allocation）および C スタックを消費しないことを静的アサーションおよび単体テストで保証・検証する。

---

## 2. トレーサビリティ / Traceability
- 関連個別仕様書:
  - [DSN-33-03 §5.4 (残余関数の Contification 保証条件)](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#54-残余関数の-contification-保証条件相互末尾再帰の単一ループ融合制約)
  - [DSN-33-01 §5.2 (Contification Picopass)](docs/designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
- 関連 Issue:
  - #877 (特殊化メモ化エンジンと Widening)
  - #879 (ステージ多相部分評価 Nanopass stage-poly-lower の実装)
  - #880 (Pass Manager への Nanopass 文法完全消去アサーションの組み込み)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/verifier.scm](ulisp/compiler/verifier.scm) - 残余関数 Contification 保証チェッカー `verify-residual-contification-guarantees`
- [x] [ulisp/tests/test_residual_contification.scm](ulisp/tests/test_residual_contification.scm) - 相互再帰・ループ融合・アロケーションゼロ検証テスト
- [x] [ulisp/Makefile](ulisp/Makefile) - `test_residual_contification` ターゲット追加
- [x] [docs/issues/README.md](docs/issues/README.md) - 台帳ステータス更新

---

## 4. 詳細設計と実装方針 / Implementation Plan
Target Branch: `feat/882-verify-residual-function-contification-guarantees`

### 4.1 Contification 保証検証 `verify-residual-contification-guarantees`
1. **共通末尾継続（Common Tail Continuation）の検証**:
   - 残余関数の呼び出しサイトがすべて末尾位置（Tail Position）にあることを確認。
2. **呼び出しサイトの閉包性（Closed Call Graph）**:
   - 残余関数名が非呼び出し位置（First-Class Value）として脱出（Escape）していないことを確認。
3. **Pass 100 Contify パイプライン連携**:
   - `contify-expr` を適用した結果、`%cont-fun` / `%cont-call` へ 100% 変換され、`lambda` による動的クロージャ割り当てが消滅していることを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 相互再帰および自己再帰する残余関数群が、エスケープせず末尾呼び出しのみである場合に Contification 保証を 100% パスすること。
- [x] 第一級値としてエスケープする関数に対しては正しく不適合（`#f`）を返すこと。
- [x] `make -C ulisp test_residual_contification` が 0件エラー PASS すること。
- [x] `make py_compile && make static_analysis` が PASS すること。
