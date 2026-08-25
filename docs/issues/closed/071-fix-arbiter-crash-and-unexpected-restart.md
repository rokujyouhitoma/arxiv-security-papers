---
ID: 071
種別: Bug
優先度: High
ステータス: Closed
完了日: 2026-08-26
---

# [BUG] Arbiter（親プロセス）の突然死・クラッシュおよび予期しない PID 変化 (ID: 071)

## 1. 概要 / Summary

`make run_supervisor` 実行後、Arbiter（親プロセス）が約 30〜92 秒でクラッシュする不具合が発生していた。
ログでは 15:07:15 の直後に `control.sock` が消滅し、その後のすべての `supervisor.cli top` コマンドが
`[ERROR] Failed to retrieve status: Supervisor control socket not found` を返すようになっていた。

また、ログ序盤でも Arbiter の PID が `16352`（15:05:55 時点）から `16407`（15:06:15 時点）へ変化しており、
この時点で既にクラッシュと自動再起動が 1 回発生していた兆候があった。

### 再現手順 / Steps to Reproduce
1. `make run_supervisor` でスーパーバイザーを起動する（9 workers）
2. 別ターミナルで `PYTHONPATH=src .venv/bin/python -m supervisor.cli top --once` を繰り返し実行する
3. 約 30 秒後（`config.timeout = 30.0`）に全ワーカーが SIGKILL され Arbiter が孤立・停止する
4. `top --once` が `control socket not found` エラーを返すようになる

### 再現環境 / Environment
- OS / Env: Linux (WSL2) / Python 3.14.7 / `.venv` 仮想環境
- File: `src/supervisor/arbiter.py`, `src/supervisor/heartbeat.py`
- ログ観測日時: 2026-08-23 15:05:55〜15:07:15（約92秒で Arbiter 死亡、初回は約20秒で死亡）

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/supervisor/arbiter.py`](../../../src/supervisor/arbiter.py)
  - `check_hung_workers()` (L272-284): 誤タイムアウト判定・DB ワーカー再起動欠落
  - `spawn_worker()` (L156-205): `pulse_callback=None` でワーカーを生成している
  - `start()` (L380-407): メインループの例外保護が不完全
- [x] [`src/supervisor/heartbeat.py`](../../../src/supervisor/heartbeat.py)
  - `get_hung_workers()` (L73-82): IDLE ワーカーをリクエスト処理中と同一条件でタイムアウト判定
- [x] [`src/supervisor/config.py`](../../../src/supervisor/config.py)
  - `timeout: float = 30.0` (L56): hung 判定と request タイムアウトが同一値
- [x] [`src/supervisor/workers/base.py`](../../../src/supervisor/workers/base.py)
  - `pulse()` (L66-80): `pulse_callback=None` の場合に Arbiter へのハートビートが届かない
- [x] [`tests/supervisor/test_arbiter.py`](../../../tests/supervisor/test_arbiter.py)
  - クラッシュ回復・ソケットクリーンアップテストを追加する

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

コードを精読した結果、以下の **2 つの根本原因** を特定した。

### 根本原因 A（最重要）: `pulse_callback=None` によりハートビートが Arbiter に届かない

`arbiter.py` の `spawn_worker()` は、子プロセス fork 後に `worker_cls(...)` インスタンスを生成するが、
`pulse_callback` 引数を渡していない（`None` のまま）。

```python
# arbiter.py L195-202
web_inst = worker_cls(
    worker_id=worker_id,
    config=self.config,
    server_socket=self.server_socket,
    app_target=self.wsgi_app,
    # pulse_callback は渡されていない → None
)
web_inst.pid = pid
self.web_workers[pid] = web_inst
self.watchdog.register_worker(pid, self.config.worker_class)
```

一方、`check_hung_workers()` は `watchdog.get_hung_workers(config.timeout)` を呼ぶ。
`timeout = 30.0` の場合、ワーカーが `register_worker()` 後 30 秒間ハートビートを更新しないと
`hung` 判定され、SIGKILL が送られる。

```python
# arbiter.py L272-284
def check_hung_workers(self) -> None:
    hung_pids = self.watchdog.get_hung_workers(self.config.timeout)
    for pid in hung_pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
        self.watchdog.remove_worker(pid)
        self.web_workers.pop(pid, None)
        self.db_workers.pop(pid, None)
        if self.running:
            self.spawn_worker("web")  # ← DB ワーカーが SIGKILL されても web しか再起動しない
```

`heartbeat.py` の `get_hung_workers()` は IDLE 状態（リクエスト未処理）のワーカーも含めて
単純に `(now - last_pulse) > timeout` で判定するため、リクエストが来ていないだけのワーカーが
30 秒後に全員 hung 判定を受ける。

### 根本原因 B: `spawn_worker()` の Parent 側インスタンス生成は参照用メタデータのみ

`spawn_worker()` の Parent 側（Arbiter 側）で生成される `web_inst` / `db_inst` は
実際の子プロセスでは **ない**（fork 後に Arbiter が保持するメタデータインスタンス）。
このインスタンスの `pulse_callback` を設定しても子プロセスのハートビートには影響しない。
子プロセス側でハートビートを Arbiter に送る仕組み（共有メモリ、ファイル、signal 等）が
実装されていない。

### PID 変化の説明

`make run_supervisor` の Makefile ターゲットは `PYTHONPATH=src ${VENV_PYTHON} -m supervisor.cli start $(ARGS)`
をバックグラウンドで起動している（ログ `[3] 16394`）。初回 Arbiter（PID 16352 付近）が
`check_hung_workers` で全ワーカーを SIGKILL した後に `spawn_worker` の `os.fork()` で例外が発生するか、
または `shutdown()` 後に再度起動されたことで PID が変化している。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix

* **暫定対処 (Workaround)**:
  `src/supervisor/config.py` の `timeout` を十分大きな値（例: `3600.0`）に変更して
  `make run_supervisor` を再実行する。クラッシュ後は `rm -f outputs/supervisor/control.sock` を実行する。

* **恒久対策 (Permanent Fix)**:
  1. **hung 判定をリクエスト処理中のみに限定する**: `get_hung_workers()` に
     `worker_status == "BUSY"` フィルタを追加し、IDLE ワーカーは hung 対象外とする
  2. **`config.timeout` を `request_timeout` と `idle_timeout` に分離する**: IDLE のまま
     終了させたいケースとリクエスト処理タイムアウトを明確に分ける
  3. **Arbiter メインループに `BaseException` ガードを追加する**: クラッシュ時のスタックトレースをログ出力し、`control.sock` を確実にクリーンアップする
  4. **`ControlServer` に `atexit` 登録を追加**: 異常終了時でもソケットファイルを自動削除

---

## 5. 実装方針 / Implementation Plan

Target Branch: `fix/071-arbiter-crash-and-restart`

### Step 1: `src/supervisor/heartbeat.py` — IDLE ワーカーを hung 判定から除外する

`get_hung_workers()` に `worker_meta` の `status` フィールドを確認するロジックを追加する。
IDLE（`requests_handling == False`）なワーカーは hung 対象外とする。

```python
# heartbeat.py: get_hung_workers() の変更
def get_hung_workers(self, timeout: Optional[float] = None) -> List[int]:
    t_limit = timeout if timeout is not None else self.timeout
    now = time.monotonic()
    hung: List[int] = []
    with self._lock:
        for pid, last_pulse in self._heartbeats.items():
            meta = self._worker_meta.get(pid, {})
            # IDLE ワーカー（リクエスト非処理中）は hung 対象外
            if not meta.get("is_handling_request", False):
                continue
            if (now - last_pulse) > t_limit:
                hung.append(pid)
    return hung
```

### Step 2: `src/supervisor/arbiter.py` — メインループに `BaseException` ガードを追加する

```python
# arbiter.py: start() の変更
def start(self) -> None:
    """Main lifecycle entrypoint starting the Supervisor cluster."""
    self.running = True
    self.init_signals()
    self.init_server_socket()
    self.load_wsgi_app()
    self._write_pid_file()
    self._start_control_server()

    if self.config.manage_database:
        for _ in range(self.config.db_worker_count):
            self.spawn_worker("db")

    self.adjust_worker_pool()

    try:
        while self.running:
            self._handle_queued_signals()
            if not self.running:
                break
            self.handle_sigchld()
            self.check_hung_workers()
            time.sleep(0.5)
    except BaseException as exc:
        import logging
        import traceback
        logging.critical(
            "[Arbiter] Unexpected crash in main loop: %s\n%s",
            exc, traceback.format_exc()
        )
    finally:
        self.shutdown()
```

### Step 3: `src/supervisor/control.py` — `atexit` でソケットを確実に削除する

```python
# control.py: ControlServer.start() に atexit 登録を追加
import atexit

def start(self) -> None:
    ...
    self._running = True
    atexit.register(self._atexit_cleanup)
    self._thread = threading.Thread(target=self._listen_loop, daemon=True)
    self._thread.start()

def _atexit_cleanup(self) -> None:
    """Ensures socket file is removed even on abnormal exit."""
    if os.path.exists(self.socket_path):
        try:
            os.unlink(self.socket_path)
        except OSError:
            pass
```

### Step 4: `src/supervisor/config.py` — タイムアウトを分離する

```python
# config.py: SupervisorConfig に request_timeout を追加
@dataclasses.dataclass
class SupervisorConfig:
    ...
    timeout: float = 30.0          # 既存: ワーカーヘルスチェック全般
    request_timeout: float = 30.0  # 追加: リクエスト処理タイムアウト（hung 判定に使用）
    idle_timeout: float = 0.0      # 追加: 0.0 = IDLE タイムアウト無効（デフォルト）
    ...
```

`check_hung_workers()` で `self.config.request_timeout` を使用するよう変更する。

### Step 5: `tests/supervisor/test_arbiter.py` — クラッシュ回復テストを追加する

```python
def test_arbiter_main_loop_exception_cleanup(tmp_path, caplog) -> None:
    """Arbiter メインループで予期せぬ例外が発生しても control.sock が削除され critical ログが出力されることを確認する。"""
    ...

def test_idle_workers_not_hung(tmp_path) -> None:
    """IDLE 状態のワーカーが hung 判定されないことを確認する。"""
    ...

def test_arbiter_control_sock_removed_on_shutdown(tmp_path) -> None:
    """Arbiter shutdown() 後に control.sock が削除されることを確認する。"""
    ...
```

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `make run_supervisor` 起動後、リクエストなしで 60 秒以上アイドル継続しても Arbiter・ワーカーが全滅しない
- [x] Arbiter メインループで例外が発生した場合に `logging.critical` でスタックトレースが出力される
- [x] Arbiter クラッシュ時・正常終了時に `outputs/supervisor/control.sock` が自動削除される
- [x] `config.request_timeout` と `config.idle_timeout` が独立した設定値として存在する
- [x] `heartbeat.py` の `get_hung_workers()` が IDLE ワーカーを hung 判定しない
- [x] `make check` (format + static_analysis + test) が 100% PASS
- [x] `tests/supervisor/test_arbiter.py` に以下のテストが追加・PASS:
  - `test_arbiter_main_loop_exception_cleanup`
  - `test_idle_workers_not_hung`
  - `test_arbiter_control_sock_removed_on_shutdown`
