---
ID: 074
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG] リクエスト未処理のアイドル状態継続後にワーカーが全滅・Arbiter が停止する (ID: 074)

## 1. 概要 / Summary

すべてのワーカープロセスで `REQ = 0`（リクエスト未処理）のまま IDLE が 15 秒以上継続した後、
ワーカーが全滅し Arbiter も停止する不具合が発生している。

ログの推移:
- 15:06:15〜15:07:15: 全ワーカーの `IDLE` が 13.2s → 16.0s と増加し続ける（REQ = 0 のまま）
- 15:07:15 → 15:07:15+: Arbiter が異常終了し `control.sock` が消滅
- 以降の `top --once` はすべて `control socket not found` エラー

正常なプロセスモデルでは、リクエストがなく IDLE が継続している状態はヘルス上問題なく、
ワーカーは次のリクエストを待機するのが正しい動作である。
ヘルスチェック機構の IDLE タイムアウト閾値が誤って短く設定されているか、
`SIGCHLD` ハンドラによるゾンビ回収の失敗が Arbiter を不安定にしている疑いがある。

### 再現手順 / Steps to Reproduce
1. `make run_supervisor` でスーパーバイザーを起動する（9 workers）
2. Web アクセスやリクエストを一切送らず、15〜20 秒以上放置する
3. `PYTHONPATH=src .venv/bin/python -m supervisor.cli top --once` を繰り返し実行する
4. IDLE 値が 15s を超えた直後に Arbiter がクラッシュし、control.sock が消滅することを確認する

### 再現環境 / Environment
- OS / Env: Linux (WSL2) / Python 3.14.7 / `.venv` 仮想環境
- File: `src/supervisor/arbiter.py`, `src/supervisor/heartbeat.py`
- ログ観測日時: 2026-08-23 15:05:55〜15:07:15（IDLE 15s 直後に Arbiter 死亡を確認）

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/supervisor/heartbeat.py`](../../src/supervisor/heartbeat.py) — IDLE タイムアウト判定・ヘルスチェックロジック
- [ ] [`src/supervisor/arbiter.py`](../../src/supervisor/arbiter.py) — `SIGCHLD` ハンドラ・ゾンビプロセス回収・メインループ終了条件
- [ ] [`src/supervisor/workers/`](../../src/supervisor/workers/) — ワーカーの IDLE 計測・自己終了ロジック
- [ ] [`src/supervisor/config.py`](../../src/supervisor/config.py) — `worker_timeout`（タイムアウト閾値）設定値

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

<!-- 調査によって判明した真の根本原因（5つの「なぜ」や仮説など）を詳細に記述します。 -->
**仮説 A（最有力）**: `heartbeat.py` の IDLE タイムアウト閾値（`worker_timeout`）がデフォルト値 15s
に設定されており、リクエスト未処理のワーカーを IDLE 超過と判定して SIGKILL を送っている。
Gunicorn の `timeout` は「リクエスト処理中の応答タイムアウト」であり、IDLE 状態には適用すべきでない。

**仮説 B**: `SIGCHLD` シグナルハンドラが複数の子プロセス終了を一括回収せず、シグナルの
"coalescing"（複数 SIGCHLD が 1 回のハンドラ呼び出しにマージ）によりゾンビが蓄積し、
ゾンビが Arbiter のプロセステーブルを圧迫して Arbiter 自体が異常終了している。

**仮説 C**: ワーカーが IDLE 超過で `sys.exit()` を呼んだ際に Arbiter が `SIGCHLD` を受け取り、
ワーカーを再起動しようとするが、再起動ループが失敗して Arbiter も道連れに停止している。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix

* **暫定対処 (Workaround)**: `src/supervisor/config.py` の `worker_timeout` 値を 3600（1時間）など
  十分に大きな値に変更して再起動する。または、IDLE 状態のワーカーをタイムアウト対象から除外する
  条件分岐を一時的に追加する。
* **恒久対策 (Permanent Fix)**:
  1. IDLE タイムアウト判定を「リクエスト処理中（`status == BUSY`）のみ」に限定し、IDLE 状態のワーカーはタイムアウト対象外とする
  2. `SIGCHLD` ハンドラ内で `os.waitpid(-1, os.WNOHANG)` をループ呼び出しし、蓄積したゾンビをすべて一括回収する
  3. ワーカー死亡時の再起動ロジックに上限（`max_worker_restarts`）と指数バックオフを導入し、無限再起動ループを防ぐ
  4. `config.py` に `idle_timeout`（アイドルタイムアウト、デフォルト無効）と `request_timeout`（リクエスト処理タイムアウト、デフォルト 30s）を分離する

---

## 5. 実装方針 / Implementation Plan

Target Branch: `fix/074-idle-worker-death-and-zombie-reaping`

1. `src/supervisor/heartbeat.py`: タイムアウト判定条件を `worker.status == WorkerStatus.BUSY and worker.idle_time > config.request_timeout` へ変更し、IDLE ワーカーを除外する
2. `src/supervisor/arbiter.py`: `_reap_workers()` メソッドを実装し、`SIGCHLD` ハンドラから呼び出す。`os.waitpid(-1, os.WNOHANG)` をゾンビが尽きるまでループする
3. `src/supervisor/config.py`: `request_timeout: int = 30` と `idle_timeout: Optional[int] = None`（無効）を定義・分離する
4. `tests/supervisor/test_heartbeat.py`: IDLE ワーカーがタイムアウトしないことを検証するテストを追加する
5. `tests/supervisor/test_arbiter.py`: ゾンビプロセス回収テストを追加する

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `make run_supervisor` 起動後、リクエストなしで 60 秒以上アイドル継続しても Arbiter・ワーカーが全滅しない
- [ ] IDLE タイムアウトとリクエスト処理タイムアウトが設定上分離されている
- [ ] ゾンビプロセスが蓄積せず、`ps aux | grep Z` でゾンビが 0 件であることが確認できる
- [ ] `make check` (format + static_analysis + test) が 100% PASS
- [ ] `tests/supervisor/test_heartbeat.py` と `tests/supervisor/test_arbiter.py` に新テストが追加・PASS
