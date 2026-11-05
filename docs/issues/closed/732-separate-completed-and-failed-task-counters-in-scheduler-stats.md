---
ID: 732
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] スケジューラ統計における正常完了タスク数と異常終了 (パニック) タスク数の分離計上 (ID: 732)

## 1. 概要 / Summary
従来の `scheduler.scm` では、統計情報管理ベクタが `tasks-spawned` と `tasks-completed` の 2 項目しか保持しておらず、タスクがパニックや例外により異常終了（Let-It-Crash）した場合であっても、正常完了と同様に `completed` カウンタがインクリメントされていた（設計項目 A8）。
本改修では、スケジューラ統計を「生成総数 (spawned)」「正常完了数 (completed)」「異常終了・パニック数 (failed)」の 3 系統に分離し、タスク境界が返却するタグ（`(cons 'ok ...)` vs `(cons 'panic ...)`）に基づき正確に分別計上するアーキテクチャを確立した。

---

## 2. トレーサビリティ / Traceability
- **DSN-37**:
  - Section 7.2: ワークスティーリングスケジューラメトリクスと統計監視
  - Section 8.4: フェイルファスト障害分離とエラーメトリクス可観測性
- **関連 Issue**:
  - [Issue #668: Concurrency Let-It-Crash Semantics](../closed/668-concurrency-let-it-crash-semantics.md)
  - [Issue #734: Unify Task Context Representation](../closed/734-unify-four-task-representations-into-single-task-context.md)

---

## 3. セキュリティ考慮事項・脅威分析 / Security & Threat Analysis
- **CWE-391 (Unchecked Error Condition / Masked Fault Observability)**:
  - 障害タスクが正常完了と同じ統計カウンタに混入すると、高負荷時や攻撃シナリオ（DoS によるパニック誘発）において、システムの障害発生率やクラッシュループの予兆を外部モニタリング（Prometheus / OpenTelemetry 連携）が検知できなくなる。
  - **対策**: スケジューラ実行完了記録ルーチン `%scheduler-run-and-record!` において、タスク境界実行結果のペア先頭タグを厳密に判別し、`'panic`（および未補足例外）発生時は専用の `tasks-failed` アトミックカウンタをインクリメントする。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm): `stats` ベクタ構造の 3 スロット拡張、`scheduler-tasks-failed` アクセサ追加、`scheduler-stats` 出力拡張
- [x] [panic.scm](../../ulisp/runtime/concurrency/panic.scm): タスク境界戻り値タグ整合
- [x] [test_scheduler.scm](../../tests/concurrency/test_scheduler.scm): 正常タスク・パニックタスク混在バッチ実行時の分離カウント検証

---

## 5. 根本原因分析 (RCA) / Root Cause Analysis
- 初期実装段階でスケジューラ統計が簡易的なタスク消化数（ジョブ終了フラグ）のみを追跡する仕様となっていたため、Phase 6 で導入された Let-It-Crash タスク境界の障害結果（`'panic` レコード）と統計記録の連携が欠落していた。

---

## 6. 実装方針と恒久対策 / Implementation Plan
Target Branch: `feat/732-separate-completed-and-failed-scheduler-stats`

1. `<work-stealing-scheduler>` の `stats` フィールド（ベクタ長 3）を定義:
   - Index 0: `spawned` (make-atomic-box 0)
   - Index 1: `completed` (make-atomic-box 0)
   - Index 2: `failed` (make-atomic-box 0)
2. アクセサ `(scheduler-tasks-failed sched)` を追加し、`(scheduler-stats sched)` の連想リストに `(tasks-failed . N)` を追加。
3. `%scheduler-run-and-record!` 内で、タスク実行結果が `(and (pair? res) (eq? (car res) 'ok))` の場合は `completed` を加算、それ以外（`'panic` 等）は `failed` を加算。
4. 全タスク消化完了判定ロジックを `(= spawned (+ completed failed))` に更新。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] 正常終了タスクとパニック終了タスクがそれぞれ `scheduler-tasks-completed` と `scheduler-tasks-failed` に独立して正確に計上されること。
- [x] `(scheduler-stats sched)` の alist に `tasks-spawned`, `tasks-completed`, `tasks-failed` が出力されること。
- [x] `make -C ulisp test_scheduler` (164 passed) が 100% PASS すること。

