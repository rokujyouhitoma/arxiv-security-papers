---
ID: 666
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Synapse タスク間双方向リンク (link)・単方向監視 (monitor) およびチャネル毒化防止機構の実装 (ID: 666)

## 1. 概要 / Summary
Erlang/OTP の耐障害性（Fault Tolerance）モデルを参考に、uLisp 並行処理基盤（Synapse Concurrency Runtime, DSN-37）へタスク間の双方向監視（`task-link!`）および単方向監視（`task-monitor`）プリミティブを導入する。
また、通信相手タスクがクラッシュした際に、待機中タスクが `channel-recv!` / `channel-send!` で永久デッドロックすることを防ぐチャネル毒化（Poisoning / Auto-Close）機構を確立する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-37 ホスト・カーネル分離型 階層 CSP/アクター並行処理基盤](docs/designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- 関連 Issue:
  - [Issue #633 (線形所有権移譲チャネル)](docs/issues/closed/633-implement-synapse-first-class-p2p-channel.md)
  - [Issue #635 (M:N ワークスティーリングスケジューラ)](docs/issues/closed/635-implement-synapse-work-stealing-scheduler.md)
  - [Issue #642 (世代管理型投機タスク破棄・世代ゲート)](docs/issues/closed/642-implement-synapse-epoch-fencing-distributed-rollback.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/channel.scm](ulisp/runtime/concurrency/channel.scm)
- [ ] [ulisp/runtime/concurrency/context.scm](ulisp/runtime/concurrency/context.scm)
- [ ] [ulisp/runtime/concurrency/scheduler.scm](ulisp/runtime/concurrency/scheduler.scm)
- [ ] [ulisp/runtime/concurrency/links.scm](ulisp/runtime/concurrency/links.scm)（新規作成予定）
- [ ] [tests/test_synapse_links_monitors.py](tests/test_synapse_links_monitors.py)（新規作成予定）

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/666-synapse-links-and-monitors`

1. `<task-context>` 構造体への監視メタデータ（`links-box`, `monitors-box`, `trap-exit-box`）の追加。
2. `(task-link! task-a task-b)` による双方向リンク登録およびタスク死亡時の `EXIT` シグナル連鎖伝播アルゴリズムの実装。
3. `(task-monitor observer-task target-task)` による単方向監視登録とダウン通知（`'(DOWN <ref> <target-id> <reason>)`）のチャネル注入。
4. チャネル送受信待機中タスクの対向タスク死亡検知と、チャネルステータス `CHANNEL_POISONED` へのアトミック遷移および安全な脱出の保証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `task-link!` で結ばれたタスクの一方がクラッシュした際、`trap-exit` されていないリンク先タスクが確実に道連れ終了すること。
- [ ] `task-monitor` により、監視対象タスクの終了理由が監視元チャネルへ通知されること。
- [ ] チャネル待機中に相手がクラッシュした場合にデッドロックせず即座に脱出・エラー処理されること。
- [ ] 既存の 10 万並行マイクロタスク性能へのオーバーヘッドが軽微（10%未満）であること。

