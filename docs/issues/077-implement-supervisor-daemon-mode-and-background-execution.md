---
ID: 077
種別: Feature
優先度: High
ステータス: Open (New)
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

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/supervisor/cli.py](../../src/supervisor/cli.py): `-D` / `--daemon`, `--log-file` 引数の追加とデーモン分岐
- [ ] [src/supervisor/config.py](../../src/supervisor/config.py): `daemon: bool`, `log_file: Optional[str]` 設定フィールドの追加とバリデーション
- [ ] [src/supervisor/arbiter.py](../../src/supervisor/arbiter.py): デーモン化メソッド（`daemonize()`）の実装と標準入出力切り離し
- [ ] [config/supervisor.json](../../config/supervisor.json): `daemon`, `log_file` サンプル設定追加
- [ ] [config/supervisor.sample.json](../../config/supervisor.sample.json): `daemon`, `log_file` 設定追加
- [ ] [config/supervisor.sample.toml](../../config/supervisor.sample.toml): TOML 設定追加
- [ ] [config/supervisor.sample.py](../../config/supervisor.sample.py): Python 設定追加
- [ ] [Makefile](../../Makefile): `make start_supervisor_daemon` または `make run_supervisor_daemon` ターゲットの追加
- [ ] [tests/supervisor/test_cli.py](../../tests/supervisor/test_cli.py): デーモンオプションパースと起動テスト
- [ ] [tests/supervisor/test_config.py](../../tests/supervisor/test_config.py): デーモン設定のパース・バリデーションテスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/077-implement-supervisor-daemon-mode-and-background-execution`

1. **`SupervisorConfig` にデーモン設定フィールドを追加**:
   - `daemon: bool = False`
   - `log_file: Optional[str] = None`
   - `pid_file: Optional[str] = None`
2. **`supervisor.cli` の引数パーサー拡張**:
   - `start_parser.add_argument("-D", "--daemon", action="store_true", help="Daemonize the supervisor process (run in background)")`
   - `start_parser.add_argument("--log-file", type=str, default=None, help="Log file destination when running in daemon mode")`
3. **`Arbiter.daemonize()` の実装**:
   - 標準的な POSIX double-forking 処理
   - 1st fork & `os.setsid()` でセッションリーダー化
   - 2nd fork で端末からの完全なデタッチ
   - `os.umask(0)`
   - `sys.stdin`, `sys.stdout`, `sys.stderr` を `--log-file`（または `/dev/null`）へリダイレクト
   - PID ファイルの書き込み
4. **テストスイートの拡充と品質ゲート検証**:
   - `tests/supervisor/test_cli.py` および `test_config.py` にデーモン化関連テストを追加
   - `make format`, `make check_format`, `make static_analysis`, `make test` の通過を確認

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `PYTHONPATH=src .venv/bin/python -m supervisor.cli -c config/supervisor.json start -D` を実行すると即座にシェルが返ってくること
- [ ] デーモン起動後、`PYTHONPATH=src .venv/bin/python -m supervisor.cli status` および `top` で正常稼働が確認できること
- [ ] `PYTHONPATH=src .venv/bin/python -m supervisor.cli stop` で親・子プロセスがクリーンに停止すること
- [ ] ログが `--log-file`（または設定ファイルで指定したファイル）に正常に出力されること
- [ ] `make format`, `make check_format`, `make static_analysis` (0 エラー) および `pytest tests/supervisor/` が 100% PASS すること
