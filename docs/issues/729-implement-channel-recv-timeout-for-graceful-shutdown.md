---
ID: 729
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] チャネル受信 (channel-recv!) へのタイムアウト機構の追加と Graceful Shutdown 待機への統合 (ID: 729)

## 1. 概要 / Summary
現在、`channel-recv!` にはタイムアウト付きの版が存在せず、メッセージが来ない場合に無期限に待機するかノンブロッキングの `channel-try-recv!` で即座に返るかの二択になっている（項目 C6）。Supervisor の Graceful Shutdown の待ち時間制御などに必要なため、`channel-recv` にタイムアウト付きの版を追加する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Section 4.3.1, Section 8.4.3)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [channel.scm](../../ulisp/runtime/concurrency/channel.scm)
- [ ] [futex.scm](../../ulisp/runtime/concurrency/futex.scm)
- [ ] [supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm)
- [ ] [test_channel.scm](../../tests/concurrency/test_channel.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/729-channel-recv-timeout`

1. `channel.scm` にタイムアウト付きの受信手続き（`channel-recv-timeout!` または `channel-recv!` のオプション引数）を追加する。
2. 指定ミリ秒経過してもメッセージが到着しない場合、waiter エントリを CAS でキャンセル（`'timed-out`）し、タイムアウト結果を返す。
3. Supervisor の shutdown 待ち時間制御から利用できるように接続する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] タイムアウト付き `channel-recv` が指定時間内にメッセージを受信すればその値を返し、期限切れ時はタイムアウト値を返して waiter キューにゴミを残さないこと。
- [ ] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

