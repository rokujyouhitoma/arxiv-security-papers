---
ID: 077
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] Implement Supervisor Daemon Mode and Background Process Execution (ID: 077)

## 1. 概要 / Summary
現状、`PYTHONPATH=src .venv/bin/python -m supervisor.cli -c config/supervisor.json start` を実行するとフォアグラウンドで Arbiter プロセスのループが実行され、ターミナル／シェルを専有（ブロック）してしまう。
Gunicorn や Nginx などの標準的なプロセスマネージャーと同様に、`-D` / `--daemon` オプション（および `--log-file` オプション）を導入し、POSIX Double-Fork によるデーモン化処理（`os.fork() x2`, `setsid()`, 標準入出力のログファイルリダイレクト、PIDファイル出力）を実装する。
これにより、シェルを即座に解放してバックグラウンドで Supervisor を起動可能にし、起動後の状態確認や停止は既存の IPC コマンド（`top`, `status`, `reload`, `stop`）で完全制御できるようにする。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [DSN-01: System High-Level Design](../../docs/designs/DSN-01-system-high-level-design.md)
  - [src/supervisor/arbiter.py](../../src/supervisor/arbiter.py)
  - [src/supervisor/cli.py](../../src/supervisor/cli.py)
  - [src/supervisor/config.py](../../src/supervisor/config.py)
  - [config/supervisor.json](../../config/supervisor.json)

---

## 3. セキュリティと脅威モデル分析 / Security & Threat Model
- **ファイルディスクリプタの適切な継承制御**:
  - `daemonize()` 実行時、不要なファイルディスクリプタのリークを防止し、標準入力（`sys.stdin`）を `/dev/null` に接続して意図しないブロックを回避。
  - 標準出力・標準エラー出力は指定された `--log-file`（または `outputs/supervisor.log`）に安全にリダイレクト。
- **PID ファイルの競合・二重起動防止**:
  - PID ファイル（`outputs/supervisor.pid`）を書き出す際、既存の PID が生きていないか `os.kill(existing_pid, 0)` で検証。生きていれば二重起動をエラー終了させてポート／ソケット競合を防御。
- **IPC コントロールソケットの保護**:
  - デーモン起動後も Unix Domain Socket（`outputs/supervisor.sock`）の権限（パーミッション）を維持し、ローカルユーザー権限外からの不正アクセスを抑止。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/supervisor/config.py](../../src/supervisor/config.py): `daemon: bool`, `log_file: Optional[str]`, `pid_file: Optional[str]` 設定フィールドの追加とバリデーション
- [x] [src/supervisor/cli.py](../../src/supervisor/cli.py): `-D` / `--daemon`, `--log-file` 引数の追加とデーモン起動ハンドリング
- [x] [src/supervisor/arbiter.py](../../src/supervisor/arbiter.py): デーモン化メソッド（`daemonize()`）の実装と PID 更新・ログリダイレクト
- [x] [config/supervisor.json](../../config/supervisor.json): `daemon`, `log_file`, `pid_file` 設定サンプルの追加
- [x] [config/supervisor.sample.json](../../config/supervisor.sample.json): サンプル設定更新
- [x] [config/supervisor.sample.toml](../../config/supervisor.sample.toml): TOML 設定更新
- [x] [config/supervisor.sample.py](../../config/supervisor.sample.py): Python 設定更新
- [x] [Makefile](../../Makefile): `make run_supervisor_daemon` または `make start_supervisor` ターゲットの追加
- [x] [tests/supervisor/test_cli.py](../../tests/supervisor/test_cli.py): デーモンオプションパースと起動テスト
- [x] [tests/supervisor/test_config.py](../../tests/supervisor/test_config.py): デーモン設定のパース・バリデーションテスト
- [x] [tests/supervisor/test_arbiter.py](../../tests/supervisor/test_arbiter.py): `daemonize()` の単体テスト（モック検証）

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/077-implement-supervisor-daemon-mode-and-background-execution`

### Step 1: `SupervisorConfig` の拡張 (`src/supervisor/config.py`)
1. 設定項目に `daemon: bool = False`, `log_file: Optional[str] = "outputs/supervisor.log"`, `pid_file: Optional[str] = "outputs/supervisor.pid"` を追加。
2. `from_dict`, `from_json`, `from_toml`, `from_pyfile` の各ローダーで設定値をロード・バリデーション。

### Step 2: `supervisor.cli` の引数パーサー拡張 (`src/supervisor/cli.py`)
1. `start` サブコマンドに以下の引数を追加：
   - `-D`, `--daemon`: デーモンモード（バックグラウンド実行）フラグ
   - `--log-file`: ログファイル出力先パス
   - `--pid`, `--pid-file`: PID ファイル出力先パス
2. CLI 引数の指定値で `config.daemon`, `config.log_file`, `config.pid_file` をオーバーライド。
3. `cmd_start` 内で `if config.daemon: arbiter.daemonize()` を実行してから `arbiter.start()` を呼び出す。

### Step 3: `Arbiter.daemonize()` の実装 (`src/supervisor/arbiter.py`)
1. **Double-Forking アルゴリズム**:
   ```python
   def daemonize(self) -> None:
       # 1st Fork: 親プロセスを終了し、子プロセスを孤立化（init/systemdへ養子縁組）
       pid = os.fork()
       if pid > 0:
           sys.exit(0)
       
       # Session Leader 化（制御端末からデタッチ）
       os.setsid()
       os.umask(0)
       
       # 2nd Fork: セッションリーダーを終了し、孫プロセスが端末を再取得できないようにする
       pid = os.fork()
       if pid > 0:
           sys.exit(0)
       
       # self.pid を新しい孫プロセスの PID に更新
       self.pid = os.getpid()
       
       # 標準入出力のリダイレクト
       self._redirect_standard_streams()
   ```
2. **標準入出力のリダイレクト (`_redirect_standard_streams`)**:
   - `sys.stdin` を `/dev/null` に接続。
   - `sys.stdout` と `sys.stderr` を `config.log_file`（指定がなければ `/dev/null`）にリダイレクト（`os.dup2` または `open(..., 'a')`）。
3. **二重起動防止チェック**:
   - `_write_pid_file()` の前に既存 PID の死活監視を行い、稼働中の場合は `RuntimeError("Supervisor is already running with PID ...")` で保護。

### Step 4: テストスイートの拡充と品質ゲート検証
1. `tests/supervisor/test_cli.py`: `-D` オプション付きの `start` コマンドパースと `daemonize` 呼び出しのモックテスト。
2. `tests/supervisor/test_config.py`: `daemon`, `log_file`, `pid_file` の各フォーマットパーステスト。
3. `tests/supervisor/test_arbiter.py`: `daemonize()` 内の `fork`, `setsid`, `dup2` の挙動テスト。
4. 全体品質ゲート: `make format`, `make check_format`, `make static_analysis` (0 エラー), `pytest tests/supervisor/` の完全合格。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `PYTHONPATH=src .venv/bin/python -m supervisor.cli -c config/supervisor.json start -D` を実行すると即座にシェルが返ってくること
- [x] デーモン起動後、`PYTHONPATH=src .venv/bin/python -m supervisor.cli status` および `top` で正常稼働が確認できること
- [x] `PYTHONPATH=src .venv/bin/python -m supervisor.cli stop` で親・子プロセスがクリーンに停止し、PID ファイル・ソケットが片付けられること
- [x] ログが `config.log_file`（`outputs/supervisor/supervisor.log`）に正常に出力されること
- [x] 既存 PID が生存している場合の二重起動防止ガードが機能すること
- [x] `make format`, `make check_format`, `make static_analysis` (0 エラー) および `pytest tests/supervisor/` が 100% PASS すること
