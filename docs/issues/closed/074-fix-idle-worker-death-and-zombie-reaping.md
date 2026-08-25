---
ID: 074
種別: Bug / Architecture Refactor
優先度: High
ステータス: Closed
---

# [BUG] アイドル状態継続後のワーカー誤判定・ヘルスチェック誤表示およびゾンビプロセス回収不備の根絶 (ID: 074)

## 1. 概要 / Summary

スーパーバイザー起動後、Web リクエストを一切送信しないアイドル状態（`REQ = 0`）が 15〜30 秒以上継続した際に、
以下の複合的な安定性課題が発生していた：

1. **Top モニターでの誤った UNHEALTHY 判定**:
   - `HeartbeatWatchdog.get_all_statuses()` において、`is_healthy = (idle_seconds <= timeout)` と単純計算されていたため、
     リクエスト待機中の正常なワーカーが 30 秒経過後に `UNHEALTHY`（黄色）と誤判定・誤表示される。
2. **リクエスト処理中フラグ (`is_handling_request`) の未通知**:
   - `SyncWorker`, `GthreadWorker`, `AsyncWorker` でリクエスト処理の開始・終了時に Arbiter への状態通知（`is_handling_request`）が明示されておらず、
     ハング検出用ウォッチドッグがワーカーの真の動作状態（待機中 vs リクエスト実行中）を正確に把握できていなかった。
3. **アイドル継続時のタイムアウトとリクエスト処理タイムアウトの混同**:
   - Gunicorn 等の標準的な Pre-fork モデルでは、アイドル状態のワーカーは無期限に待機するのが正常な動作であり、
     タイムアウト（`request_timeout`）はリクエストを処理中のまま応答が途絶えたハングワーカーにのみ適用されるべきである。
4. **子プロセス終了時（SIGCHLD）の安全な回収とフラッピング防止**:
   - ワーカー異常終了時に Arbiter が即時再起動する際、連続クラッシュ時のレート制限（バックオフ）が欠落しており、
     万一の異常時に CPU 高負荷やゾンビ蓄積を招くリスクがあった。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/supervisor/heartbeat.py`](../../src/supervisor/heartbeat.py)
  - `HeartbeatWatchdog.is_healthy()` および `get_all_statuses()`: アイドル状態（`is_handling_request=False`）のワーカーは `is_healthy=True` を維持
  - リクエスト処理中（`is_handling_request=True`）のまま `request_timeout` を超過したワーカーのみを `is_healthy=False` かつ `hung` 候補として抽出
- [x] [`src/supervisor/workers/sync_worker.py`](../../src/supervisor/workers/sync_worker.py)
  - `SyncWorker.handle_client()`: リクエスト開始時に `pulse({"is_handling_request": True})`、完了時に `pulse({"is_handling_request": False})` を発行
- [x] [`src/supervisor/workers/gthread_worker.py`](../../src/supervisor/workers/gthread_worker.py)
  - `GthreadWorker`: スレッドプールでのリクエスト処理中にアクティブなスレッド数を追跡し、`is_handling_request` を正確に更新
- [x] [`src/supervisor/workers/async_worker.py`](../../src/supervisor/workers/async_worker.py)
  - `AsyncWorker`: 非同期リクエスト処理時の状態遷移通知
- [x] [`src/supervisor/arbiter.py`](../../src/supervisor/arbiter.py)
  - `handle_sigchld()`: `os.waitpid(-1, os.WNOHANG)` によるゾンビプロセスの完全一括回収
  - ワーカー再起動フラッピング防止（短時間での急激なクラッシュ・再起動ループに対する安全ガード）
- [x] [`src/supervisor/config.py`](../../src/supervisor/config.py)
  - `request_timeout: float = 30.0` (リクエスト処理中の最大許容時間) と `idle_timeout: float = 0.0` (0.0 = 無期限待機) の明示的な責務分離
- [x] [`tests/supervisor/test_heartbeat.py`](../../tests/supervisor/test_heartbeat.py)
  - アイドルワーカーが 60 秒以上経過しても `is_healthy=True` であり、hung 判定されないことの検証
- [x] [`tests/supervisor/test_arbiter.py`](../../tests/supervisor/test_arbiter.py)
  - ゾンビプロセス回収およびアイドル継続テストの拡充

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

```
[クライアント接続なし (IDLE 継続)]
       ↓
[ワーカーは accept() 待ちで pulse() を定期送信]
       ├── しかし requests_handled = 0 のまま idle_seconds が 15s → 30s と増加
       ↓
[HeartbeatWatchdog.get_all_statuses() の不備]
       ├── idle_seconds <= timeout を無条件適用していたため、正常な待機ワーカーを UNHEALTHY と誤判定
       ↓
[ウォッチドッグの hung 判定との乖離]
       ├── get_hung_workers() は is_handling_request ガードを持つが、ワーカー側から is_handling_request が送信されていない
       └── 結果として、真のハング（リクエスト処理がスタック）と正常な待機（IDLE）の境界が曖昧になっていた
```

### 根本原因の要約
1. **状態フラグ未通知**: `SyncWorker` 等のワーカーがリクエスト処理中である旨（`is_handling_request: True`）を Arbiter のウォッチドッグに通知していなかった。
2. **ヘルス計算式の誤り**: `meta["is_healthy"] = meta["idle_seconds"] <= self.timeout` と記述されていたため、リクエストが来ないだけで `top` モニターで `UNHEALTHY` 表示に陥っていた。

---

## 4. 解決策と設計方針 / Solution Architecture

### 設計方針 1: 状態駆動型ヘルス＆ハング検出モデル
- **IDLE 状態 (`is_handling_request = False`)**:
  - ワーカープロセスが生きており（`ALIVE`）、定期パルスを受信していれば、`idle_seconds` がどれだけ大きくなっても `is_healthy = True`。
  - `get_hung_workers()` からは完全に除外。
- **BUSY / REQUEST 状態 (`is_handling_request = True`)**:
  - リクエスト処理開始時にタイムスタンプを記録。
  - `now - request_start_time > request_timeout`（デフォルト 30s）となった場合のみ `is_healthy = False` となり、ウォッチドッグにより hung プロセスとして SIGKILL 対象となる。

### 設計方針 2: `SIGCHLD` ゾンビ回収の完全ノンブロッキング化
- `os.waitpid(-1, os.WNOHANG)` を `pid <= 0` または `ECHILD` になるまで確実にループ実行し、同一シグナルで集約（coalesce）された複数の終了プロセスを単一のシグナルハンドラ内で漏れなく回収。

### 設計方針 3: ワーカーフラッピング防止機構 (Flapping Guard)
- ワーカーが起動直後にクラッシュ（1秒以内に連続終了）した場合、Arbiter が `time.sleep(0.5)` 程度のバックオフを挟んで再起動し、リソース枯渇やログ爆発を防ぐ。

---

## 5. 実装計画 / Implementation Plan

Target Branch: `fix/074-fix-idle-worker-death-and-zombie-reaping`

1. **`src/supervisor/heartbeat.py` の改修**:
   - `get_worker_status()` および `get_all_statuses()` での `is_healthy` 算出ロジックを修正：
     - リクエスト処理中（`is_handling_request == True`）の場合: `(now - last_request_start) <= timeout`
     - アイドル待機中の場合: プロセスがパルスを送信しており生存していれば `True`
2. **`src/supervisor/workers/sync_worker.py` & `gthread_worker.py` の改修**:
   - `handle_client()` の前後に `pulse({"is_handling_request": True, "request_start": time.monotonic()})` と `pulse({"is_handling_request": False})` を追加
3. **`src/supervisor/workers/async_worker.py` の改修**:
   - 非同期ストリーム処理時の `is_handling_request` 状態同期
4. **`src/supervisor/arbiter.py` の堅牢化**:
   - `handle_sigchld()` のゾンビ回収ロジックの安全性向上
5. **テストスイートの拡充**:
   - `tests/supervisor/test_heartbeat.py`: アイドル継続（60秒超）時の健全性維持テスト
   - `tests/supervisor/test_arbiter.py`: リクエスト中ハングのみがキルされ、アイドルワーカーが生き続けることの総合テスト
   - `tests/supervisor/test_top.py`: アイドル状態のワーカーが Top 画面で `HEALTHY`（緑色）と表示されることのテスト

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `make run_supervisor` 起動後、リクエストなしで 60 秒以上アイドル継続しても Arbiter および全ワーカー（web, database, search）が健全（HEALTHY）を維持する
- [x] `supervisor.cli top --once` で、アイドル状態の全ワーカーが `STATUS=ALIVE`, `HEALTH=HEALTHY` と緑色で正常表示される
- [x] リクエスト処理中に設定時間（`request_timeout`）を超えてハングしたワーカーのみが正確に検出・再起動される
- [x] ゾンビプロセスが蓄積せず、`os.waitpid(-1, os.WNOHANG)` で完全回収される
- [x] `make check` (format + static_analysis + test) が 100% PASS
- [x] `tests/supervisor/test_heartbeat.py`, `tests/supervisor/test_arbiter.py`, `tests/supervisor/test_top.py` がすべて PASS

