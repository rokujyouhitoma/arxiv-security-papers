---
ID: 673
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] グローバルアトミック Task ID (TID) 自動採番機構の導入と手動指定衝突の防止 (ID: 673)

## 1. 概要 / Summary
現在の Synapse ランタイムにおいて、タスク生成プリミティブ `make-task-context`（`channel.scm`）および `make-budgeted-task`（`preempt.scm`）はプログラマが手動で固定整数 ID を渡す設計となっており、複数モジュールや並行ワーカーによるタスク生成時に ID が衝突・重複する危険性が極めて高い。
グローバルアトミックな Task ID 採番器（`*task-next-id*`）を導入し、引数なし `(make-task-context)` および `(spawn-task thunk)` で一意な TID が自動割り当てされる堅牢な基盤を確立する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-37 ホスト・カーネル分離型 階層 CSP/アクター並行処理基盤](docs/designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- 関連 Issue:
  - [Issue #633 (第一級 P2P チャネル・TaskContext)](docs/issues/closed/633-implement-synapse-first-class-p2p-channel.md)
  - [Issue #635 (M:N ワークスティーリングスケジューラ)](docs/issues/closed/635-implement-synapse-work-stealing-scheduler.md)
  - [Issue #666 (タスク間リンク・モニタ)](docs/issues/666-implement-synapse-task-links-and-monitors.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/channel.scm](ulisp/runtime/concurrency/channel.scm)
- [ ] [ulisp/runtime/concurrency/preempt.scm](ulisp/runtime/concurrency/preempt.scm)
- [ ] [ulisp/runtime/concurrency/scheduler.scm](ulisp/runtime/concurrency/scheduler.scm)
- [ ] [tests/concurrency/test_channel.scm](tests/concurrency/test_channel.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/673-global-atomic-task-id-allocator`

1. グローバルアトミックカウンタ `*task-next-id*`（初期値 1）の定義と高速採番手続き `(allocate-task-id!)` の実装。
2. `make-task-context` の引数オーバーロード拡張:
   - `()`: 自動採番された TID で新規タスク生成。
   - `(epoch)`: 自動採番された TID と指定 Epoch で新規タスク生成。
   - `(tid ...)`: 既存テスト互換のための明示的 ID 指定（後方互換性を維持）。
3. `preempt.scm` の `make-budgeted-task` においても、ID 省略時に自動でユニーク TID を付与するオーバーロードの追加。
4. `scheduler-spawn!` において手続き（thunk）を受け取った際、内部で自動採番された `task-context` を安全にバインド。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 引数なし `(make-task-context)` で呼び出した際、常にグローバルに重複のない一意な TID が割り当てられること。
- [ ] 100,000 並行タスク生成時にも TID の衝突やオーバーフローが一切発生しないこと。
- [ ] 既存の全テストケースが修正なしで後方互換パスすること。

