---
ID: 763
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 030_desugar.scm (desugar-all) の手動コピー約190行の撤去と fuse-rules による自動融合への完全置換 (DSN-33-01 T4.2) (ID: 763)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 1.1 節、第 6.2 節、第 9.2 節 タスク **T4.2** に基づき、`ulisp/frontend/030_desugar.scm` の `desugar-all` パス（L286-476）に手動でコピー＆ペーストされていた約190行のパターンマッチ節と重複ヘルパー関数を撤去し、Issue #762 で定義した `026`〜`029` の Picopass 群を `(fuse-rules ...)` で自動融合する宣言的定義へと完全に置き換える。

これにより、「単体テスト用の `026`〜`029`」と「本番パイプライン用の `030`」の間で発生していた二重管理を根絶し、1回の $O(1)$ Head-Tag ディスパッチ走査に統合する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 1.1 節, 第 4.2 節, 第 6.2 節, 第 9.2 節 タスク **T4.2**)
- 依存関係:
  - 先行 Issue: [Issue #759 (T3.1: fuse-rules と O(1) ディスパッチ)](759-implement-fuse-rules-and-head-tag-o1-dispatch.md), [Issue #760 (T3.2: 局所再適用と extends 整合性検査)](760-implement-local-redispatch-and-extends-eliminates-validation.md), [Issue #762 (T4.1: 026〜029 の Picopass 化)](762-migrate-desugar-passes-026-to-029-to-picopass.md)
  - 後続 Issue: [Issue #764 (T4.3: Verifier の attopass 化)](764-migrate-verifier-to-attopass-and-eliminate-triple-traversal.md), [Issue #765 (T5.1: ルール依存関係 DAG 自動構築)](765-implement-rule-dependency-dag-and-femtopass-cache-invalidation.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm)
- [ ] [ulisp/frontend/026_desugar_constructors.scm](../../ulisp/frontend/026_desugar_constructors.scm)
- [ ] [ulisp/frontend/027_desugar_conditionals.scm](../../ulisp/frontend/027_desugar_conditionals.scm)
- [ ] [ulisp/frontend/028_desugar_bindings.scm](../../ulisp/frontend/028_desugar_bindings.scm)
- [ ] [ulisp/frontend/029_desugar_dynamic.scm](../../ulisp/frontend/029_desugar_dynamic.scm)
- [ ] [ulisp/tests/passes/test_030_desugar.scm](../../ulisp/tests/passes/test_030_desugar.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/763-replace-desugar-030-with-fuse-rules`

1. **重複ヘルパー関数の整理**:
   - `030_desugar.scm` の前半（L10-280）に置かれていた Constructors / Dynamic 系の補助関数群を、対応する `026_desugar_constructors.scm` および `029_desugar_dynamic.scm` へ適切に集約し、`030_desugar.scm` を純粋な Nanopass Fusion オーケストレータとする。
2. **`desugar-all` の `(fuse-rules ...)` 化**:
   - `(define-pass desugar-all : L_src (ir) -> L_core () (entry Expr) (fuse-rules ...))` として、`026`〜`029` の全 Picopass / Attopass を束ねる。
   - `nanopass-verify-fusion-coverage` により、`L_src` から `L_core` で除去される全構文が100%カバーされていることを自動検証する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `030_desugar.scm` から手動コピーされたパターンマッチ節が完全に消去され、`(fuse-rules ...)` による宣言的融合に置き換わっていること。
- [ ] `test_030_desugar.scm` およびセルフホスティング Stage 1〜3 のコンパイル結果が移行前と完全一致すること。

