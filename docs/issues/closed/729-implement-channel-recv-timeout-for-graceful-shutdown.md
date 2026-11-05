---
ID: 729
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] チャネル受信 (channel-recv!) へのタイムアウト機構の追加と Graceful Shutdown 待機への統合 (ID: 729)

## 1. 概要 / Summary
現在、`channel-recv!` にはタイムアウト付きの版が存在せず、メッセージが来ない場合に無期限に待機するかノンブロッキングの `channel-try-recv!` で即座に返るかの二択になっている（項目 C6）。Supervisor の Graceful Shutdown の待ち時間制御などに必要なため、`channel-recv` にタイムアウト付きの版（`channel-recv-timeout!`）を追加し、Supervisor の子タスク停止（`%stop-child-instance!`）と統合する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Section 4.3.1, Section 8.4.3)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [channel.scm](../../../ulisp/runtime/concurrency/channel.scm)
- [x] [channel.sld](../../../ulisp/lib/ulisp/concurrency/channel.sld)
- [x] [supervisor.scm](../../../ulisp/runtime/concurrency/supervisor.scm)
- [x] [test_channel.scm](../../../tests/concurrency/test_channel.scm)
- [x] [test_supervisor.scm](../../../tests/concurrency/test_supervisor.scm)

---

## 4. 根本原因分析 (RCA) / Root Cause Analysis
- `channel.scm` の受信 API が即時ポーリング（`channel-try-recv!` / `channel-try-recv-with-status!`）と無期限サスペンド（`channel-recv!`）のみで構成されており、単調増加クロックに基づくデッドライン付き待機およびタイムアウト時の `<channel-waiter>` 状態キャンセル機構が未実装であったため。
- また `supervisor.scm` の `%stop-child-instance!` が `child-spec-shutdown-strategy`（`'brutal_kill`、正の整数ミリ秒タイムアウト、`'infinity`）を参照せず常に即座に強制終了していたため。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/729-channel-recv-timeout`

1. `ulisp/runtime/concurrency/channel.scm`（および `channel.sld`）に `channel-recv-timeout!` `(channel-recv-timeout! ch timeout-ms [receiver-task])` を追加する：
   - まずノンブロッキング受信（`channel-try-recv-with-status!`）を試み、メッセージ到着または closed/poisoned であれば即座に `(cons #t val)` / `(cons #f 'closed)` / `(cons #f 'poisoned)` を返す。
   - 空であり `timeout-ms > 0` の場合、`<channel-waiter>` を `recv-wait-queue` に登録したうえで `sys-clock-gettime-monotonic` に基づくデッドラインまで待機し、到着すれば `(cons #t val)` を返す。
   - 期限切れ時は `<channel-waiter>` の `state-box` を CAS で `'waiting` から `'timed-out` へ遷移させてキャンセル（万一直前に sender が `'claimed` していた場合は handoff された値を回収）し、タスクの状態を `'ready` に戻して `(cons #f 'timeout)` を返す。また `%pop-live-waiter!` は `'waiting` 以外の waiter を自動でスキップするためキューにゴミが残らない。
2. `ulisp/runtime/concurrency/supervisor.scm` の `%stop-child-instance!` で `child-spec-shutdown-strategy` を参照し、正の整数ミリ秒 `timeout-ms` が指定されている場合は一時通知チャネルへのモニターと `'shutdown` 通知を送って `channel-recv-timeout!` で最大 `timeout-ms` 待機し、タイムアウトした場合に `synapse-cleanup-task-resources!` で強制終了する Graceful Shutdown フローを実装する。
3. `tests/concurrency/test_channel.scm` と `tests/concurrency/test_supervisor.scm` に単体・結合テストを追加する。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] タイムアウト付き `channel-recv-timeout!` が指定時間内にメッセージを受信すれば `(cons #t val)` を返し、期限切れ時は `(cons #f 'timeout)` を返して waiter キューにゴミを残さないこと。
- [x] Supervisor の Graceful Shutdown が `child-spec-shutdown-strategy` のタイムアウト設定に従って動作すること。
- [x] `make -C ulisp test_channel test_supervisor test_concurrency_ci lint_sexpr` がすべて PASS すること。

