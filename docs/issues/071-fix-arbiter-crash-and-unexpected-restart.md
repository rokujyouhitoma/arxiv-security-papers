---
ID: 071
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG] Arbiter（親プロセス）の突然死・クラッシュおよび予期しない PID 変化 (ID: 071)

## 1. 概要 / Summary

`make run_supervisor` 実行後、Arbiter（親プロセス）が異常終了・クラッシュする不具合が発生している。
ログでは 15:07:15 の直後に `control.sock` が消滅し、その後のすべての `supervisor.cli top` コマンドが
`[ERROR] Failed to retrieve status: Supervisor control socket not found` を返すようになった。

また、ログ序盤でも Arbiter の PID が `16352`（15:05:55 時点）から `16407`（15:06:15 時点）へ変化しており、
この時点で既にクラッシュと自動再起動が 1 回発生していた兆候がある。Arbiter は本来クラッシュしても
自動再起動するように設計されていないため、予期しない再起動はシグナルハンドラや例外処理の不備を示す。

### 再現手順 / Steps to Reproduce
1. `make run_supervisor` でスーパーバイザーを起動する（9 workers）
2. 別ターミナルで `PYTHONPATH=src .venv/bin/python -m supervisor.cli top --once` を繰り返し実行する
3. 約 1〜2 分後（アイドル継続後）に Arbiter が無音でクラッシュし、control.sock が消滅する
4. `top --once` が `control socket not found` エラーを返すようになる

### 再現環境 / Environment
- OS / Env: Linux (WSL2) / Python 3.14.7 / `.venv` 仮想環境
- File: `src/supervisor/arbiter.py`, `src/supervisor/control.py`
- ログ観測日時: 2026-08-23 15:05:55〜15:07:15（約92秒で Arbiter 死亡）

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/supervisor/arbiter.py`](../../src/supervisor/arbiter.py) — Arbiter メインループ・シグナルハンドラ・例外処理
- [ ] [`src/supervisor/control.py`](../../src/supervisor/control.py) — Unix ドメインソケット (control.sock) 管理・クリーンアップ処理
- [ ] [`src/supervisor/heartbeat.py`](../../src/supervisor/heartbeat.py) — ハートビート監視ループ・タイムアウト処理
- [ ] [`src/supervisor/workers/`](../../src/supervisor/workers/) — ワーカー管理・ゾンビ回収ロジック
- [ ] `outputs/supervisor/control.sock` — ソケットファイル（クラッシュ時に残留・消滅する問題）

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

<!-- 調査によって判明した真の根本原因（5つの「なぜ」や仮説など）を詳細に記述します。 -->
**仮説 A**: Arbiter のメインループが捕捉されない例外（`Exception` サブクラス外の `BaseException`、
`KeyboardInterrupt`、`SystemExit` 等）を受け取りクラッシュしている。

**仮説 B**: アイドル状態（REQ=0、IDLE 15s+）が続いたときのゾンビプロセス回収 (`os.waitpid`) または
`SIGCHLD` ハンドラが無限ループや再帰シグナル配送を起こし、Arbiter が不正状態へ陥っている。

**仮説 C**: `control.sock` のクリーンアップが Arbiter 終了時に正しく行われず、次回起動時に
`Address already in use` で再起動に失敗している（PID 変化の説明）。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix

* **暫定対処 (Workaround)**: クラッシュ後は `rm -f outputs/supervisor/control.sock` を手動実行してから
  `make run_supervisor` を再実行する。
* **恒久対策 (Permanent Fix)**:
  1. Arbiter メインループを `try/except BaseException` で保護し、クラッシュ時のスタックトレースをログ出力する
  2. `atexit` / `signal.signal(SIGTERM, ...)` ハンドラで `control.sock` を確実にクリーンアップする
  3. `SIGCHLD` ハンドラを `SA_RESTART` フラグ付きで登録し、シグナル競合を防ぐ
  4. Arbiter 自身を外部 watchdog（systemd/cron）で再起動するのではなく、内部 self-restart 機構（fork + exec）を実装する

---

## 5. 実装方針 / Implementation Plan

Target Branch: `fix/071-arbiter-crash-and-restart`

1. `src/supervisor/arbiter.py`: メインループ全体を `try/except BaseException as exc` で囲み、例外発生時に `logging.critical` でトレースバック出力 + `control.sock` 削除を実施
2. `src/supervisor/control.py`: `atexit.register(_cleanup_socket)` および `signal.signal(SIGTERM, _graceful_stop)` を登録し、異常終了時も必ずソケットを削除する
3. `src/supervisor/arbiter.py`: `SIGCHLD` ハンドラ内の `os.waitpid(-1, os.WNOHANG)` をループ化し、複数のゾンビを一括回収する
4. `tests/supervisor/test_arbiter.py`: Arbiter クラッシュ時の sock クリーンアップテストを追加する

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `make run_supervisor` 起動後、5分間アイドル継続しても Arbiter がクラッシュしない
- [ ] Arbiter クラッシュ時に `outputs/supervisor/control.sock` が自動削除される
- [ ] `make check` (format + static_analysis + test) が 100% PASS
- [ ] `tests/supervisor/test_arbiter.py` にクラッシュ回復テストが追加・PASS
