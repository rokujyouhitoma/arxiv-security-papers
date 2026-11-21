---
ID: 900
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Implement JIT Trace Optimizer and Guard-Failure Deopt Trampoline (ID: 900)

## 1. 概要 / Summary
[[DSN-33-05]](../designs/DSN-33-05-ulisp_endogenous_meta_tracing_jit_architecture.md) 第 5 章に基づき、記録された JIT トレースに対する冗長ガード除去（Guard Elimination）、仮想化オブジェクトの割り当て除去（Allocation Removal）、およびガード失敗時のスタック復元（Deoptimization / OSR Trampoline）を実装する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-33-05] ULisp 内因的メタトレーシング JIT アーキテクチャ包括設計書 (第5章 最適化とガード除去)](../designs/DSN-33-05-ulisp_endogenous_meta_tracing_jit_architecture.md)
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/jit/optimizer/pe.scm](../../ulisp/jit/optimizer/pe.scm)
- [ ] [ulisp/jit/optimizer/virtuals.scm](../../ulisp/jit/optimizer/virtuals.scm)
- [ ] [ulisp/jit/runtime/deopt.scm](../../ulisp/jit/runtime/deopt.scm)
- [ ] [ulisp/tests/test_jit_optimizer.scm](../../ulisp/tests/test_jit_optimizer.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/900-implement-jit-trace-optimizer-and-guard-failure-deopt-trampoline`

1. トレース内の連続する同種型ガードを検知し、先行ガードの支配下にある冗長ガードを削除する Guard Elimination パスを実装。
2. トレース内で生成・破棄されるタプルや一時環境オブジェクトをスカラーレジスタへ昇格する Virtualization オプティマイザを実装。
3. ガード失敗時に JIT コンパイル済み機械語のレジスタ状態からインタプリタのフレーム環境を再構成し、安全にインタプリタへ復帰する Deopt トランポリンを実装。
4. 単体テスト `test_jit_optimizer.scm` でガード除去率と脱出安全性を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] ループ不変なガードおよび同一変数の重複ガードが 100% 除去されること。
- [ ] ガード失敗時に正しい変数状態を保ってインタプリタ実行へフォールバックできること。
- [ ] `make -C ulisp test_jit_optimizer` が PASS すること。
- [ ] `make py_compile && make static_analysis` が PASS すること。
