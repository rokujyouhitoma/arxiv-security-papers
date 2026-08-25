---
ID: 072
種別: Bug / Architecture Refactor
優先度: High
ステータス: Closed
---

# [BUG] `scale` コマンド実行時に DB ワーカーが巻き添えで停止・消滅する問題の修正および Web/DB プール分離管理 (ID: 072)

## 1. 概要 / Summary

`supervisor.cli scale -w 2` を実行して Web ワーカー数を縮小した際、Web ワーカーだけでなく `database` ワーカー（DB プロセス）も巻き添えで停止・消滅する不具合が発生していた。

根本的な原因として、Web ワーカーと DB ワーカーのプロセスライフサイクル・スケーリングロジックがラベル（Role / Label）単位で完全分離されておらず、単一の全体ワーカーカウントとして扱われていたことが判明した。

本改修では、**Web と DB をラベル（`web` / `database`）単位で完全に分離して独立管理・スケールできるアーキテクチャ** を導入し、デフォルト構成を **Web: 2（最小冗長Web構成）、DB: 3（分散DB合意・クォーラムの最小構成）** とし、単一ノード構成（Web 1, DB 1）や組み込み構成への柔軟なスケーリングを可能にする。

### 再現手順 / Steps to Reproduce
1. `make run_supervisor` でスーパーバイザーを起動する（Web: 2, DB: 3）
2. `PYTHONPATH=src .venv/bin/python -m supervisor.cli top --once` で Web: 2/2, DB: 3 を確認する
3. `PYTHONPATH=src .venv/bin/python -m supervisor.cli scale -w 4 --label web` を実行する
4. `top --once` で Web: 4/4, DB: 3（DB が一切影響を受けず維持される）ことを確認する
5. `PYTHONPATH=src .venv/bin/python -m supervisor.cli scale -w 1 --label db` を実行する
6. `top --once` で Web: 4/4, DB: 1（DB のみが指定数に縮小される）ことを確認する

### 再現環境 / Environment
- OS / Env: Linux (WSL2) / Python 3.14.7 / `.venv` 仮想環境
- File: `src/supervisor/arbiter.py`, `src/supervisor/config.py`, `src/supervisor/control.py`, `src/supervisor/cli.py`, `src/supervisor/contracts.py`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/supervisor/config.py`](../../src/supervisor/config.py)
  - デフォルト値の更新: `workers: int = 2` (Web), `db_worker_count: int = 3` (最小分散DB構成)
  - `PoolConfig` / `ServiceConfig` の分離とバリデーション
- [x] [`src/supervisor/arbiter.py`](../../src/supervisor/arbiter.py)
  - `handle_control_command()`: `scale` コマンドで `label` (`web` / `db`) 別の独立スケーリングディスパッチ
  - `adjust_worker_pool()`: Web ワーカー専用のスケール制御
  - `adjust_db_worker_pool()`: DB ワーカー専用のスケール制御
- [x] [`src/supervisor/control.py`](../../src/supervisor/control.py)
  - `ControlClient.scale_workers(count, label="web")`: ラベル指定サポート
- [x] [`src/supervisor/cli.py`](../../src/supervisor/cli.py)
  - `scale` サブコマンドに `--label` / `--type` / `-l` (choices: `["web", "database", "db"]`, default: `"web"`) を追加
- [x] [`src/supervisor/contracts.py`](../../src/supervisor/contracts.py)
  - `WorkerLabel` enum を定義し型安全性を確保
- [x] [`tests/supervisor/test_arbiter.py`](../../tests/supervisor/test_arbiter.py)
  - Web スケール時に DB が維持されること、DB スケール時に Web が維持されることの検証テスト追加
- [x] [`tests/supervisor/test_cli.py`](../../tests/supervisor/test_cli.py)
  - CLI `scale --label db` 等の引数解析・ディスパッチテスト追加

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

1. **プロセスプールの非分離**:
   Arbiter 内部で `scale` コマンドが全ワーカー数 (`self.config.workers`) の更新のみを行い、`web` と `database` の分離されたスケーリングハンドラが存在しなかった。
2. **デフォルト構成の不均衡**:
   従来のデフォルトワーカー数算出 `(2 * cpu_count) + 1` は過度なプロセス数（9プロセス）を生成し、かつ DB ワーカー数が `1` であったため、分散合意（Raft/Quorum 最小3ノード）の要件と乖離していた。
3. **IPC ペイロードのターゲット種別欠落**:
   `scale` IPC コマンドにスケーリング対象の `label` / `type` を指定するパラメータがなく、暗黙的に Web ワーカーのみを想定していたため、他ロールとの協調管理が破綻していた。

---

## 4. 恒久対策 / Permanent Fix

1. **Web/DB ラベル別スケーリングの完全分離**:
   - `scale` コマンドに `label` 引数を導入（デフォルト: `web`）。
   - `label="web"` の場合は `adjust_worker_pool()` のみを実行し、`db_workers` には一切シグナルを送信しない。
   - `label="db"` / `label="database"` の場合は `adjust_db_worker_pool()` を実行し、`web_workers` には一切シグナルを送信しない。
2. **最小構成の適正化**:
   - Web ワーカーデフォルト: `2` (最小冗長構成)
   - DB ワーカーデフォルト: `3` (最小分散DBクォーラム構成)
   - 単一ノード（Web: 1, DB: 1）やカスタム構成への動的縮小・拡大を完全サポート。
3. **IPC & CLI インターフェース拡張**:
   - `supervisor.cli scale -w N --label web`
   - `supervisor.cli scale -w M --label db`

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `src/supervisor/config.py` のデフォルトが Web: 2, DB: 3 に設定されている
- [x] `supervisor.cli scale -w 1 --label web` 実行後、DB ワーカー数が維持される
- [x] `supervisor.cli scale -w 1 --label db` 実行後、Web ワーカー数が維持される
- [x] `tests/supervisor/test_arbiter.py` に Web/DB 分離スケーリングテストが追加され PASS
- [x] `tests/supervisor/test_cli.py` に `--label` オプションのテストが追加され PASS
- [x] `make check` (format + static_analysis + test) が 100% PASS
