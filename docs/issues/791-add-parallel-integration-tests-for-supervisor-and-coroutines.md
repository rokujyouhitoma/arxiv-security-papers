---
ID: 791
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 並行スケジューラ (scheduler-run-parallel!) 上での Supervisor・コルーチン・同時子異常終了の結合テスト整備 (ID: 791)

## 1. 概要 / Summary
Synapse 並行性ランタイムおよび Supervisor の結合テスト範囲を拡充し、マルチ OS スレッド環境（`scheduler-run-parallel!`）における Supervisor、コルーチン型子タスク、および複数子タスクの同時異常終了（カオスシナリオ）の統合動作を検証するテストスイートを構築する。

現状、CI で実行されている Supervisor のテストは単一スレッドの `scheduler-run!` に留まっており、OS スレッドワーカー間でのワークスチールや競合、コルーチン型の子タスクを `yield` させた後にクラッシュさせた場合の監視・復旧動作が自動テストでカバーされていない。また、harness 側には DOWN の受け取りや再 spawn を手動で行う古いテストコードが残存しているため、これらを整理・自動化する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: Issues #722 - #746 (Synapse 並行性ランタイムおよび Supervisor 仕様)
- DSN-37 Section 5, 7.3, 14.4

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [test_supervisor_input.scm](../../ulisp/build/test_supervisor_input.scm)
- [ ] [test_multithread_scheduler_input.scm](../../ulisp/build/test_multithread_scheduler_input.scm)
- [ ] [supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm)
- [ ] [scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/791-parallel-supervisor-coroutine-integration-tests`

1. `test_multithread_scheduler_input.scm` または独立した結合テストランナーに、`scheduler-run-parallel!` を用いた Supervisor テストグループを追加。
2. テストケース 1: マルチワーカー上で 10 個以上の子タスクがほぼ同時にクラッシュ（panic / memory fault）した際に、Supervisor が競合なく全 DOWN を受け取り再起動できるかを検証。
3. テストケース 2: コルーチン型子タスクが `yield` して中断している状態で、外部シグナルまたは異常終了が発生した場合に、リソースがリークせず安全に回収・再起動されるかを検証。
4. テストハーネス内に残存する手動 spawn / 手動 DOWN 処理を完全撤去し、ランタイムの自動ディスパッチ機構を介した検証へ統一。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `scheduler-run-parallel!`（4 ワーカー以上）環境下で、Supervisor の一括障害復旧テストが安定して PASS すること。
- [ ] コルーチン型子タスクの中断状態からの強制停止および再起動テストが PASS すること。
- [ ] レースコンディションやデッドロックが検出されず、CI 回帰テストに組み込まれていること。

