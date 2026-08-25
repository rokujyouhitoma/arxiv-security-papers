---
ID: 072
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG] `scale` コマンド実行時に DB ワーカーが巻き添えで停止・消滅する (ID: 072)

## 1. 概要 / Summary

`supervisor.cli scale -w 2` を実行して Web ワーカー数を 9→2 に縮小したところ、
Web ワーカーだけでなく `database` ワーカー（DB プロセス）も一緒に停止・消滅した。

ログの変化:
- **scale 前**: `Workers: Web: 9/9, DB: 1`（`database` PID 16552 が ALIVE HEALTHY）
- **scale 後**: `Workers: Web: 2/2, DB: 0`（`database` プロセスが完全消滅）

`database` ワーカーはウェブリクエストと無関係な永続サービスプロセスであり、
Web ワーカーのプール縮小操作に巻き込まれて停止されるべきではない。
Web ワーカーのスケーリングロジックと DB ワーカーの管理が分離できていないことが根本原因と考えられる。

### 再現手順 / Steps to Reproduce
1. `make run_supervisor` でスーパーバイザーを起動する（Web: 9, DB: 1）
2. `PYTHONPATH=src .venv/bin/python -m supervisor.cli top --once` で Web: 9/9, DB: 1 を確認する
3. `PYTHONPATH=src .venv/bin/python -m supervisor.cli scale -w 2` を実行する
4. `PYTHONPATH=src .venv/bin/python -m supervisor.cli top --once` で DB: 0 になっていることを確認する

### 再現環境 / Environment
- OS / Env: Linux (WSL2) / Python 3.14.7 / `.venv` 仮想環境
- File: `src/supervisor/arbiter.py`, `src/supervisor/control.py`
- ログ観測日時: 2026-08-23 15:06:18〜15:07:08（scale 実行後に DB 消滅を確認）

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/supervisor/arbiter.py`](../../src/supervisor/arbiter.py) — `scale` IPC コマンドの受信・処理ロジック、ワーカー縮小処理
- [ ] [`src/supervisor/control.py`](../../src/supervisor/control.py) — `scale` コマンドの IPC ペイロード定義・送受信
- [ ] [`src/supervisor/workers/`](../../src/supervisor/workers/) — ワーカー種別（`sync` / `database`）の分離管理
- [ ] [`src/supervisor/contracts.py`](../../src/supervisor/contracts.py) — ワーカー種別定義・型定義

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

<!-- 調査によって判明した真の根本原因（5つの「なぜ」や仮説など）を詳細に記述します。 -->
**仮説 A**: `scale` コマンドの実装が、全ワーカーリストを `target_workers` 数になるよう
一律に SIGQUIT / SIGTERM を送っており、`database` 種別を特別扱いするロジックが存在しない。

**仮説 B**: Arbiter の内部ワーカー管理がリスト（`list[WorkerProcess]`）の単純な末尾削除で
実装されており、`type == "database"` のプロセスをスキップするフィルタリングがない。

**仮説 C**: `scale` の `-w` パラメータが "Web ワーカー数" ではなく "全ワーカー数" として
解釈されており、`database` ワーカーを含む全体を 2 に切り詰めている。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix

* **暫定対処 (Workaround)**: `scale` コマンドを使用しない。ワーカー数の変更が必要な場合は
  `stop` → `start` で再起動する。
* **恒久対策 (Permanent Fix)**:
  1. Arbiter のワーカー管理を `web_workers: list[WorkerProcess]` と `service_workers: list[WorkerProcess]`（database 等）に明確に分離する
  2. `scale -w N` は `web_workers` のみを対象とし、`service_workers` には一切シグナルを送らない
  3. `scale` コマンドのレスポンスに `web_workers` と `service_workers` の件数を明示する

---

## 5. 実装方針 / Implementation Plan

Target Branch: `fix/072-scale-command-kills-db-worker`

1. `src/supervisor/arbiter.py`: `_handle_scale(target_workers)` メソッド内のワーカー選択ロジックを
   `[w for w in self.workers if w.worker_type == "sync"]` でフィルタリングし、`database` 種別を除外する
2. `src/supervisor/contracts.py`: `WorkerType` Enum に `WEB = "sync"` と `DATABASE = "database"` を定義し、型安全を確保する
3. `src/supervisor/cli.py`: `scale -w N` のヘルプ文を「Web ワーカー数のみを変更（DB ワーカーは非影響）」と明記する
4. `tests/supervisor/test_arbiter.py`: scale 実行後も DB ワーカーが維持されることを検証するテストを追加する

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `scale -w 2` 実行後、`top --once` で `DB: 1` が維持されている
- [ ] Web ワーカー数のみが指定値に変更される
- [ ] `make check` (format + static_analysis + test) が 100% PASS
- [ ] `tests/supervisor/test_arbiter.py` に scale 分離テストが追加・PASS
