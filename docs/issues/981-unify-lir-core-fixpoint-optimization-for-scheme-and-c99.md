---
ID: 981
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT/ENH] L_lir_core 不動点最適化ループ（mem2reg・branch-fusion・peephole）の Scheme / C99 共通化 (ID: 981)

## 1. 概要 / Summary

現在、`pass-132-c99-mem2reg` → `pass-128-lir-branch-fusion` → `pass-133-lir-peephole` を反復実行する不動点最適化ループ `run-c99-o2-fixpoint-pipeline`（[pass_manager.scm](../../ulisp/compiler/pass_manager.scm)）は C99 フロントエンドの `-O2` 専用となっており、Scheme 側のパイプラインでは同様の不動点最適化ループが共有されていない。

`L_lir_core` 上の汎用最適化パスを Scheme（`pass-131-lower-managed-dialect` 完了後）と C99（`lower_to_lir` 完了後）の双方で共通利用する不動点最適化枠組みを構築し、今後追加予定のミドルエンド最適化アルゴリズムを両フロントエンドへ統一的に適用できる前提を整える。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [pass_manager.scm](../../ulisp/compiler/pass_manager.scm)
  - [979-tighten-lir-language-compatibility-and-reconcile-lir-dialects.md](closed/979-tighten-lir-language-compatibility-and-reconcile-lir-dialects.md)
  - [966-separate-mir-ssa-and-machine-lir-for-unified-middle-end.md](966-separate-mir-ssa-and-machine-lir-for-unified-middle-end.md)
  - [973-implement-ssa-sccp-gvn-adce-and-decompose-lir-peephole.md](973-implement-ssa-sccp-gvn-adce-and-decompose-lir-peephole.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [pass_manager.scm](../../ulisp/compiler/pass_manager.scm)
- [ ] [compiler.scm](../../ulisp/compiler.scm)
- [ ] [132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm)
- [ ] [128_lir_branch_fusion.scm](../../ulisp/lir/128_lir_branch_fusion.scm)
- [ ] [133_lir_peephole.scm](../../ulisp/lir/133_lir_peephole.scm)
- [ ] [test_pass_manager.scm](../../ulisp/tests/test_pass_manager.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/981-unify-lir-core-fixpoint-optimization`

1. C99 `-O2` 専用の `run-c99-o2-fixpoint-pipeline` を分析し、`L_lir_core` 汎用パス（`pass-128-lir-branch-fusion`、`pass-133-lir-peephole`、および Scheme LIR 互換範囲でのスカラ昇格 / `mem2reg`）を共通化した `run-lir-core-fixpoint-pipeline` を設計する。
2. Scheme `-O2` パイプラインの `Pass 131` 以降および C99 `-O2` パイプライン双方から共通不動点ループを呼び出せるように統合する（詳細は `polish-issue` にて精緻化）。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `L_lir_core` 共通の不動点最適化パイプラインが Scheme・C99 双方の `-O2` 経路から利用可能になっていること。
- [ ] パス連続性・言語互換性検証（Issue #979）および既存 Scheme / C99 / 3-Stage ブートストラップテストが PASS すること（詳細ゲートは `polish-issue` 時に確定）。
