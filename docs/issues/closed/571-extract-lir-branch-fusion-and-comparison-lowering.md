---
ID: 571
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] LIR パスからの条件分岐・比較融合 (Branch Fusion) ロジックの独立モジュール分離 (ID: 571)

## 1. 概要 / Summary
`ulisp/passes/130_lir.scm` (76KB / 1,799行) に組み込まれている比較演算と条件分岐の融合最適化（Branch Fusion / Flag Fusion: `lir-compile-fused-cmp`, `lir-compile-fused-cmp-cond`, `lir-cmp-false-cc`, `extract-fused-cmp-int` 等）を、独立したモジュールまたは Nanopass 前段パス `ulisp/passes/128_lir_branch_fusion.scm`（または LIR サブパス）として抽出・分離する。
これにより、130_lir.scm の巨大コードフットプリントを削減し、中間表現における制御フロー最適化の独立したテスト・検証を可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様書:
  - [DSN-33 (ULisp アーキテクチャ包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [LIR 命令セット仕様書](../ulisp/docs/lir_specification.md)
  - Issue #545 (ULisp AOT x86における条件分岐融合によるブール値実体化の完全排除)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/128_lir_branch_fusion.scm](../../ulisp/passes/128_lir_branch_fusion.scm)
- [x] [ulisp/passes/130_lir.scm](../../ulisp/passes/130_lir.scm)
- [x] [ulisp/Makefile](../../ulisp/Makefile)
- [x] [ulisp/tests/passes/test_branch_fusion.scm](../../ulisp/tests/passes/test_branch_fusion.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/571-extract-lir-branch-fusion-and-comparison-lowering`

1. `130_lir.scm` 内の Branch Fusion 関連ヘルパーおよび比較融合ロジックを抽出。
2. `ulisp/passes/128_lir_branch_fusion.scm` を新設し、関数を再配置。
3. `ulisp/Makefile` の `PASSES_LIB` に追加し、`test_branch_fusion` を含む全テストで整合性を検証。
4. LIR 生成全体の命令セット整合性を維持しつつ、130_lir.scm の肥大化を解消。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] Branch Fusion ロジックが `128_lir_branch_fusion.scm` に独立して配置されていること。
- [x] `130_lir.scm` がスリム化され、責務が明確化されていること。
- [x] `make test_branch_fusion` および `make test` が PASS すること。
