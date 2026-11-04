---
ID: 722
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] x86-64 Linux における Supervisor 配下の子タスク異常終了隔離と自動再起動の CI 結合テスト追加 (ID: 722)

## 1. 概要 / Summary
x86-64 Linux の CI および結合テストとして、Supervisor の配下で子タスクに `(car '())` を実行させてクラッシュさせ、無関係な並行タスクが正常に完了すること、およびクラッシュした子タスクが Supervisor によって自動で再起動することを確認するエンドツーエンド結合テストを実装する（A2・B4・B6・C7 の受け入れ条件）。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Section 8.4)
- 依存関係: Issue #719 (A1), Issue #720 (A2), Issue #721 (A3)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [Makefile](../../../ulisp/Makefile)
- [x] [supervisor.scm](../../../ulisp/runtime/concurrency/supervisor.scm)
- [x] [eval_adapter.scm](../../../ulisp/runtime/concurrency/eval_adapter.scm)
- [x] [test_supervisor.scm](../../../tests/concurrency/test_supervisor.scm)
- [x] [concurrency_harness.scm](../../../tests/concurrency/concurrency_harness.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/722-synapse-ci-fault-isolation-integration-test`

1. `supervisor.scm` に `supervisor-poll-down-signals!`（または `supervisor-task` の handoff / mailbox に届いた `(DOWN ref process tid reason)` 通知を検知して `supervisor-handle-child-down!` を呼び出す仕組み）を接続し、スケジューラ上でクラッシュした子タスクからの `DOWN` 通知で自動再起動が発火するようにする。
2. `test_supervisor.scm`（Group 7）および `concurrency_harness.scm`（Scenario 4e）に、Supervisor 配下に1回目の起動で `(car '())` を実行してクラッシュし2回目（再起動後）に正常完了する子タスクと、独立して計算を行う無関係な並行タスクをスケジューラ上で同時に走らせるエンドツーエンド結合テストを作成する。
3. 無関係なタスクがクラッシュに巻き込まれず完了すること、クラッシュした子タスクの初回タスクが `'terminated` になりエフェメラルアリーナが O(1) リセットされること、および子タスクが新しい TID で自動再起動されて処理完了することを検証するアサーションを実装する。
4. x86-64 Linux の CI ターゲット（`ulisp/Makefile` の `test_concurrency_ci`）に `test_supervisor` と `test_let_it_crash` を統合し、A2・B4・B6・C7 の受け入れ条件として自動実行する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] Supervisor 配下で子タスクに `(car '())` を実行させた際、無関係なタスクが正常完了し、子が自動再起動することが x86-64 Linux CI テスト（`test_supervisor` および `test_concurrency_ci`）で検証されること。
- [x] `make -C ulisp test_supervisor test_concurrency_ci lint_sexpr` がすべて PASS すること。

