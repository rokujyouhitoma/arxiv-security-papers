---
ID: 898
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Implement JIT Loop Merge Point and Guard Annotations (ID: 898)

## 1. 概要 / Summary
[[DSN-33-05]](../designs/DSN-33-05-ulisp_endogenous_meta_tracing_jit_architecture.md) 第 3 章および [[DSN-33-04]](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md) 第 6 章に基づき、評価器のループ先頭および動的分岐に対して極小注釈（`jit-merge-point!` および `jit-guard-type!`）を配置し、内因的メタトレーシング JIT とのシームレスな接続ポイントを確立する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-33-05] ULisp 内因的メタトレーシング JIT アーキテクチャ包括設計書 (第3章)](../designs/DSN-33-05-ulisp_endogenous_meta_tracing_jit_architecture.md)
  - [[DSN-33-04] ULisp 言語ワークベンチ設計書 (第6章 メタトレーシング JIT との協調)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/jit/core/annotations.scm](../../ulisp/jit/core/annotations.scm)
- [ ] [ulisp/jit/tracer/auto_instrument.scm](../../ulisp/jit/tracer/auto_instrument.scm)
- [ ] [ulisp/tests/test_jit_annotations.scm](../../ulisp/tests/test_jit_annotations.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/898-implement-jit-loop-merge-point-and-guard-annotations`

1. `jit-merge-point!` プリミティブを実装し、ループ識別子と現在の環境状態を JIT プロファイラへ通知。
2. `jit-guard-type!` プリミティブを実装し、動的型ガードおよびガード失敗時の脱出メタデータを記録。
3. `auto_instrument.scm` において、評価器の `case` 式や再帰ループに対して自動注釈を挿入するマクロトランスレータを実装。
4. 単体テスト `test_jit_annotations.scm` で注釈が正しく評価フックを起動することを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `jit-merge-point!` および `jit-guard-type!` が Pure Scheme で透過的に動作すること。
- [ ] JIT が無効な環境ではゼロオーバーヘッド（インライン消去）となること。
- [ ] `make -C ulisp test_jit_annotations` が PASS すること。
- [ ] `make py_compile && make static_analysis` が PASS すること。
