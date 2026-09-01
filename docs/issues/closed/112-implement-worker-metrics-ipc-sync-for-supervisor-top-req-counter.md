---
ID: 112
種別: Improvement / Observability
優先度: Medium
ステータス: Closed (Completed)
完了日: 2026-09-02
---

# [FEAT/ENH] Supervisorワーカーのプロセス間メトリクス同期機構の実装とTopモニタREQ(リクエスト件数)リアルタイム表示の修正 (ID: 112)

## 1. 概要 / Summary
Supervisor のプロセス監視トップ（`supervisor top` / `SupervisorTopViewer`）において、稼働中の Web ワーカーおよびサービスワーカーがリクエストを処理しているにもかかわらず、`REQ` 列（処理リクエスト件数）が常に `0` のまま更新されない事象を解決した。

根本原因であったマルチプロセス環境下（`os.fork()`）でのメトリクス孤立を解消するため、各ワーカーが `pulse()` 実行時に `outputs/supervisor/heartbeat_{pid}.json` へアトミックにメトリクスをフラッシュし、親プロセス（Arbiter）の `HeartbeatWatchdog` がディスクから自動同期する **「ファイルベースのプロセス間ハートビート同期機構」** を実装した。

---

## 2. 成果と実機検証 (Results & Verification)

### Supervisor Top 実測確認

```
[改善前]
  PID    TYPE       STATUS   HEALTH   REQ IDLE MEM (PSS)
  ──────────────────────────────────────────────────────────────────────────
  484883 web       ALIVE   HEALTHY 0        30.4s      32.5 (19.0) MB  <-- ⚠️ REQが0のまま
  484884 web       ALIVE   HEALTHY 0        30.4s      52.8 (39.4) MB  <-- ⚠️ REQが0のまま

[改善後 (実測値)]
  PID    TYPE       STATUS   HEALTH   REQ IDLE MEM (PSS)
  ──────────────────────────────────────────────────────────────────────────
  493004 search    ALIVE   HEALTHY 0        0.0s       1205.3 (1193.4) MB
  493005 database  ALIVE   HEALTHY 0        0.0s       27.1 (13.4) MB
  493006 database  ALIVE   HEALTHY 0        0.0s       27.1 (13.5) MB
  493007 database  ALIVE   HEALTHY 0        0.0s       27.1 (13.4) MB
  493008 web       ALIVE   HEALTHY 13       0.0s       32.5 (19.1) MB  <-- ✅ リアルタイム反映 (13件)
  493009 web       ALIVE   HEALTHY 4        0.0s       51.7 (38.3) MB  <-- ✅ リアルタイム反映 (4件)
```

---

## 3. 主な変更点 / Key Implementations

1. **[BaseWorker (src/supervisor/workers/base.py)](../../src/supervisor/workers/base.py)**:
   - `_write_heartbeat_file` および `_cleanup_heartbeat_file` を追加。
   - `pulse()` 呼び出し時に `outputs/supervisor/heartbeat_{pid}.json` へ `requests_handled`, `uptime`, `last_seen_epoch`, `is_handling_request` をアトミックに書き込み。
   - ワーカー `close()` 時に状態ファイルを自動クリーンアップ。
2. **[HeartbeatWatchdog (src/supervisor/heartbeat.py)](../../src/supervisor/heartbeat.py)**:
   - `sync_from_disk(base_dir)` メソッドを追加し、`get_worker_status()` および `get_all_statuses()` 呼び出し時に追跡対象ワーカーのハートビートファイルを自動走査してメモリテーブル（`_worker_meta`）を最新化。
   - ワーカー登録解除（`remove_worker`）時に状態ファイルを安全に削除。
3. **[Arbiter (src/supervisor/arbiter.py)](../../src/supervisor/arbiter.py)**:
   - `HeartbeatWatchdog` 初期化時に `base_dir=outputs/supervisor/` を渡すように設定。
4. **[テストスイート (tests/supervisor/test_heartbeat.py)](../../tests/supervisor/test_heartbeat.py)**:
   - `test_heartbeat_sync_from_disk` を追加し、ファイル経由のメトリクス同期・クリーンアップを検証。

---

## 4. 完了条件の達成状況 / DoD Verification
- [x] Web ワーカーまたはサービスワーカーがリクエストを処理した際、`supervisor top` の `REQ` 列がリアルタイムにインクリメントされること。
- [x] マルチプロセス（`os.fork()`）環境下で低オーバーヘッド（0.1ms 未満）でメトリクスが親プロセスへ同期されること。
- [x] ワーカー終了時に `heartbeat_{pid}.json` が適切にクリーンアップされること。
- [x] 全テストスイートが 100% PASS すること（Supervisor 関連 74/74 PASSED）。
- [x] Xenon 循環的複雑度が全モジュールで **100% Rank A (CC $\le 5$)** を維持していること。
