---
ID: 667
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Erlang/OTP 型スーパービジョンツリー (Supervision Tree) と再起動戦略 (one-for-one / all / rest) の実装 (ID: 667)

## 1. 概要 / Summary
Erlang/OTP の中核アーキテクチャであるスーパービジョンツリー（Supervision Tree）を uLisp Synapse 並行基盤上に設計・実装する。
タスクの階層的監視木構造を導入し、子タスク障害発生時の自動再起動戦略（`one-for-one`, `one-for-all`, `rest-for-one`）と、短時間の頻繁なクラッシュ（Flapping / Crash Loop）を検知して上位層へエスカレーションする再起動頻度制限（MaxRestarts / MaxTime）機構を提供する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-37 ホスト・カーネル分離型 階層 CSP/アクター並行処理基盤](docs/designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- 関連 Issue:
  - [Issue #666 (タスク間リンク・モニタ)](docs/issues/666-implement-synapse-task-links-and-monitors.md)
  - [Issue #630 (独立バンプアリーナ)](docs/issues/closed/630-implement-synapse-task-independent-bump-arena.md)
  - [Issue #635 (M:N ワークスティーリングスケジューラ)](docs/issues/closed/635-implement-synapse-work-stealing-scheduler.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/supervisor.scm](ulisp/runtime/concurrency/supervisor.scm)（新規作成予定）
- [ ] [ulisp/runtime/concurrency/scheduler.scm](ulisp/runtime/concurrency/scheduler.scm)
- [ ] [tests/test_synapse_supervisor.py](tests/test_synapse_supervisor.py)（新規作成予定）

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/667-synapse-supervision-tree`

1. `<supervisor-spec>` および `<child-spec>` レコード定義（`id`, `start-fn`, `restart-type`, `shutdown-timeout` 等）。
2. 再起動戦略の実装:
   - `one-for-one`: クラッシュした特定子タスクのみを新品のアリーナで再生成。
   - `one-for-all`: 密結合グループにおいて、1タスクの死で配下の全子タスクを停止・再起動。
   - `rest-for-one`: 起動順序に依存関係がある場合、障害タスク以降の子タスクのみを順次再起動。
3. 再起動頻度トラッカー（スライディング時間窓内の再起動回数監視）と、限界突破時のスーパーバイザ自身のアボート＆親へのエスカレーション。
4. `define-supervisor` マクロの提供による直感的な宣言的 DSL 記法の実現。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `one-for-one`, `one-for-all`, `rest-for-one` の各再起動戦略がユニットテストで完全に意図通り動作すること。
- [ ] Crash Loop 発生時に設定した MaxRestarts / TimeWindow 閾値で安全に停止・上位エスカレーションすること。
- [ ] 子タスク再起動時に旧アリーナが完全に解放され、メモリリークが一切発生しないこと。

