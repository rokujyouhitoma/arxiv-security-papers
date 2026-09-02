---
ID: 113
種別: Improvement / Observability
優先度: High
ステータス: Closed
---

# [FEAT/ENH] サービスワーカー(Search/Database)のIPCリクエスト計測連携およびTopモニタへのRPS(秒間スループット)表示機能の実装 (ID: 113)

## 1. 概要 / Summary
Supervisor 上で動作する各種プロセスプールのうち、ステートフルサービスワーカー（`search`、`database`）において、検索クエリやデータベーストランザクション等の IPC リクエストを正常に処理しているにもかかわらず、`supervisor top` 上の `REQ` カウントが増加しない事象を解決する。

また、`REQ`（累積リクエスト数）に加えて、現在のシステム負荷・秒間処理能力を一目で把握するための **「RPS（Requests Per Second / 秒間スループット）」表示機能** を Top モニタ（`SupervisorTopViewer`）および Web ダッシュボード（`/dashboard`）に追加する。

```
[現状の Top 監視画面]
  PID    TYPE       STATUS   HEALTH   REQ IDLE MEM (PSS)
  ──────────────────────────────────────────────────────────────────────────
  493004 search    ALIVE   HEALTHY 0        0.0s       1205.3 (1193.4) MB  <-- ⚠️ 検索実行後もREQが0
  493005 database  ALIVE   HEALTHY 0        0.0s       27.1 (13.4) MB      <-- ⚠️ DB処理後もREQが0
  493008 web       ALIVE   HEALTHY 13       0.0s       32.5 (19.1) MB
  493009 web       ALIVE   HEALTHY 4        0.0s       51.7 (38.3) MB

[改善後の目標画面]
  PID      TYPE       STATUS   HEALTH     REQ      RPS      IDLE     MEM (PSS)
  ────────────────────────────────────────────────────────────────────────────────
  493004   search     ALIVE    HEALTHY    2        0.5/s    12.4s    1205.3 (1193.4) MB  <-- ✨ 検索件数&RPSが反映
  493005   database   ALIVE    HEALTHY    6        1.2/s    0.0s     27.1 (13.4) MB      <-- ✨ DB件数&RPSが反映
  493008   web        ALIVE    HEALTHY    13       3.2/s    2.1s     32.5 (19.1) MB      <-- ✨ Web件数&RPSが反映
  493009   web        ALIVE    HEALTHY    4        0.0/s    15.0s    51.7 (38.3) MB
```

---

## 2. 根本原因と設計方針 (RCA & Architecture)

```
[Search/Database クライアント] ──> [Unix Domain Socket IPC]
                                          │
                                          ▼
                                   [Search/Database Service]
                                      (self.requests_handled += 1)
                                          │
                                          ▼
                                   [LifecycleHook.get_metrics()]
                                          │
                                          ▼
                                   [ManagedServiceWorker]
                                      (self.requests_handled = hook_reqs)
                                      (self.pulse())
                                          │
                                          ▼
                                   [heartbeat_{pid}.json]
                                          │
                                          ▼ (watchdog.sync_from_disk)
                                   [HeartbeatWatchdog / Arbiter]
                                          │
                                          ▼ (Δreq / Δt 計算)
                                   [SupervisorTopViewer (RPS)] / [/dashboard (RPS)]
```

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### サービス層 & ライフサイクルフック
- [x] [src/supervisor/contracts.py](../../src/supervisor/contracts.py):
  - `LifecycleHook` プロトコルおよび `DefaultLifecycleHook` に `get_metrics() -> Dict[str, Any]` メソッドを追加。
- [x] [src/search/server/service.py](../../src/search/server/service.py):
  - `SearchService` に `requests_handled: int = 0` を追加し、`_handle_client` / コマンド処理時にインクリメント。
  - `SearchLifecycleHook.get_metrics()` から `{"requests_handled": self.service.requests_handled}` を返却。
- [x] [src/database/ipc/service.py](../../src/database/ipc/service.py):
  - `DatabaseService` に `requests_handled: int = 0` を追加し、`_handle_connection` / IPC コマンド処理時にインクリメント。
  - `DatabaseLifecycleHook.get_metrics()` から `{"requests_handled": self.service.requests_handled}` を返却。
- [x] [src/supervisor/workers/service_worker.py](../../src/supervisor/workers/service_worker.py):
  - `ManagedServiceWorker.run()` のループ内で `hook.get_metrics()` を呼び出し、`self.requests_handled` を最新化して `self.pulse()` を実行。

### Supervisor Top モニタ & Dashboard RPS & IDLE 計算
- [x] [src/supervisor/top.py](../../src/supervisor/top.py):
  - 各ワーカーの前回観測時スナップショット（`last_req_count`, `last_sample_time`）を管理する `_prev_snapshots` 辞書を追加。
  - `_compute_worker_rps(pid, current_req, current_time)` ヘルパーを実装。
  - ANSI パディング後の文字幅ずれを解消し、テーブル表示を `PID TYPE STATUS HEALTH REQ RPS IDLE MEM (PSS)` に厳密整列。
- [x] [site/dashboard.html](../../site/dashboard.html):
  - Supervisor & Process Top タブに `RPS` 列を追加し、クライアント側差分スループットを動的表示。
- [x] [src/supervisor/heartbeat.py](../../src/supervisor/heartbeat.py):
  - `last_active_epoch` による各ワーカーのリクエストアクティビティ追跡を導入し、`IDLE` 時間を正確に計測。

### テスト
- [x] [tests/supervisor/test_service_worker.py](../../tests/supervisor/test_service_worker.py):
  - サービスワーカーのメトリクス取得および `requests_handled` 増分テスト。
- [x] [tests/supervisor/test_top.py](../../tests/supervisor/test_top.py):
  - RPS 計算とフォーマット出力、および列アライメントのテスト。
- [x] [tests/supervisor/test_heartbeat.py](../../tests/supervisor/test_heartbeat.py):
  - `idle_seconds` の増加とリクエスト処理時リセットのテスト。
- [x] [tests/web/test_dashboard_html.py](../../tests/web/test_dashboard_html.py):
  - `/dashboard` における RPS 表示と Supervisor テーブル要素の検証。

---

## 4. 完了条件 / Success Criteria (DoD)
- [x] 検索クエリ実行時に `search` ワーカーの `REQ` が正確にインクリメントされること。
- [x] DB クエリ実行時に `database` ワーカーの `REQ` が正確にインクリメントされること。
- [x] `supervisor top` 上に `RPS` 列が新設され、リクエスト処理中のワーカーに対してリアルタイムな秒間スループット（例: `5.0/s`）が表示されること。
- [x] `/dashboard` に `RPS` 列が表示され、秒間スループットがリアルタイムに可視化されること。
- [x] 全テストスイートが 100% PASS すること。
- [x] Xenon 循環的複雑度が全モジュールで **100% Rank A (CC $\le 5$)** を維持していること。
