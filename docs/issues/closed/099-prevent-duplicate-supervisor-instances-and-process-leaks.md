# Issue #099: Supervisor の多重起動完全防止およびプロセスリーク根絶

## 1. 概要 (Overview)
`python -m supervisor.cli restart --daemon` や `start --daemon` の実行時、古い世代の Arbiter や Worker プロセスが適切に終了待機・回収されずに残り続け、21 プロセスなど複数世代が多重稼働してしまうプロセスリーク（多重起動問題）が発生していた。
OS レベルの排他ファイルロック（`fcntl.flock`）、デフォルト PID ファイルの自動設定、`restart` 時の旧プロセス完全消滅待機ポーリング、および Linux `PR_SET_PDEATHSIG` による Worker 孤児化防止をコードレベルで実装し、多重起動とプロセス残留を根絶した。

---

## 2. 実装項目 (Implementation Items)
1. **`src/supervisor/config.py`**:
   - `pid_file`: デフォルトで `<workspace>/outputs/supervisor/arbiter.pid` を設定
   - `lock_file`: デフォルトで `<workspace>/outputs/supervisor/arbiter.lock` を設定
2. **`src/supervisor/arbiter.py`**:
   - `acquire_single_instance_lock()`: `fcntl.flock` によるノンブロッキング排他ロックの取得
   - `release_single_instance_lock()`: 排他ロックの安全な解放・ファイルクリーンアップ
   - `_check_existing_pid()`: PID ファイルとプロセスの生存確認を厳密化
   - `init_child_process()`: Linux `prctl(PR_SET_PDEATHSIG, SIGKILL)` を設定し親プロセス死亡時の道連れ終了を保証
   - 終了時のロック解放・PID ファイル・ソケットファイルの確実なクリーンアップ
3. **`src/supervisor/cli.py`**:
   - `_handle_restart`: 旧 Arbiter の終了要求（IPC/SIGTERM）後、プロセスが完全に OS 上から消滅するまでポーリング待機（最大5秒）。タイムアウト時は強制 SIGKILL を送信し、旧プロセスの完全終了を確認してから新 Arbiter を起動
4. **テストの追加**:
   - `tests/supervisor/test_singleton_lock.py` による排他ロックおよび重複起動ブロックの単体テスト

---

## 3. DoD (Definition of Done)
- [x] 排他ファイルロックにより、同一環境で 2 つ以上の Arbiter が起動できないこと
- [x] デフォルトで PID ファイルが管理され、明示的オプションなしでも正しく動作すること
- [x] `restart` 実行時に旧 Arbiter と全 Worker が完全に終了してから新インスタンスが起動すること
- [x] 全 73 件の単体テスト（`tests/supervisor/`）および品質ゲートが 100% PASS すること
