---
ID: 322
種別: Bug
優先度: High
ステータス: Closed (Completed)
完了日: 2026-09-17
---

# [BUG/SEC] Fix Supervisor SpiderWorker Dispatch Priority and Top Table Visibility (ID: 322)

## 1. 概要 / Summary
Web コンソールおよび CLI の `Live Supervisor Workers Top Table` において、Supervisor 管理下の `SpiderWorker`（および `WorkflowWorker`）が表示されず、従来の 6 プロセス（`search: 1`, `database: 3`, `web: 2`）のみが表示される不具合を根本解消した。

### 再現手順 / Steps to Reproduce
1. `config/supervisor.json` に `services` として `spider`（`worker_class: "spider"`）を定義。
2. Supervisor Arbiter 起動時または動作中に `outputs/supervisor/control.sock` 経由で `status` コマンドを発行、または Web コンソール (`/dashboard.html` / `index.html`) の Supervisor Top パネルを確認。
3. `spider` ワーカーがプロセス一覧・Top Table に存在しない、あるいは `_execute_child_spec` で `ServiceWorker` として分岐してしまい `hook_uri` 不在で異常終了する。

### 再現環境 / Environment
- OS / Env: Linux (Ubuntu 24.04 LTS / x86_64)
- File: `src/supervisor/arbiter.py`, `src/supervisor/workers/spider_worker.py`, `config/supervisor.json`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [arbiter.py](../../src/supervisor/arbiter.py) (`_execute_child_spec` における specialized worker ディスパッチ優先順位の是正)
- [x] [spider_worker.py](../../src/supervisor/workers/spider_worker.py) (Top Table / Watchdog 連携用ハートビートの type/role 属性整合性検証 & 遅延インポートによる循環参照解消)
- [x] [config/supervisor.json](../../config/supervisor.json) (`spider` / `workflow` ワーカー定義の反映検証)
- [x] [tests/supervisor/test_spider_worker.py](../../tests/supervisor/test_spider_worker.py) (Arbiter SpiderWorker spawn / dispatch 回帰テスト)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **ディスパッチ優先度の逆転 (Logic Flaw)**:
   `config/supervisor.json` の `"services"` 配下に `worker_class: "spider"` を設定した場合、`_build_service_spec()` により `spec.role = ServiceRole.STATEFUL_SERVICE` が設定される。しかし、`Arbiter._execute_child_spec()` では `if spec.worker_class == "service" or spec.role == ServiceRole.STATEFUL_SERVICE:` が最初に判定されていたため、`_dispatch_specialized_worker()`（`spider` / `queue`）に到達せず、`hook_uri` を持たない通常の `ServiceWorker` として初期化され即時クラッシュ・再起動ループに陥っていた。
2. **稼働中プロセスの未リロード (Operational Desync)**:
   Arbiter プロセスが `config/supervisor.json` の変更前に起動されており、動的リロードまたは再起動が実行されていなかったため、旧メモリ空間のプール構成（6プロセス）のまま監視が継続していた。
3. **モジュール循環インポート (Circular Import)**:
   `SpiderWorker` がトップレベルで `SpiderDaemonWorker` をインポートし、`SpiderExecutionStorage` が `database` パッケージをインポートしていたため、`database` -> `supervisor` -> `spider_worker` -> `spider.daemon.worker` 間で循環依存が発生していた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 手動で `SpiderDaemonWorker` を直接実行する。
* **恒久対策 (Permanent Fix)**:
  1. `src/supervisor/arbiter.py` の `_execute_child_spec()` において、`_dispatch_specialized_worker()` を `ServiceRole.STATEFUL_SERVICE` よりも優先して判定・実行するように修正した。
  2. `src/supervisor/workers/spider_worker.py` で `SpiderDaemonWorker` をローカル遅延インポートに変更し、循環依存を完全切断した。
  3. Supervisor デーモンを再起動し、`spider` (1) および `workflow` (1) を含む全 8 ワーカープロセスを正常起動し、Top Table に常駐反映させた。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/322-supervisor-spider-worker-dispatch`

1. **`src/supervisor/arbiter.py` の修正**:
   - `_execute_child_spec()` 内のディスパッチ順序を修正し、`self._dispatch_specialized_worker(spec, worker_id)` を第1優先で評価。
2. **`src/supervisor/workers/spider_worker.py` の循環依存解消**:
   - `SpiderDaemonWorker` のインポートを `SpiderWorker.__init__` 内での遅延インポートに変更。
3. **単体テスト作成 & 検証**:
   - `tests/supervisor/test_spider_worker.py` に `test_arbiter_execute_child_spec_spider_priority` を追加。
4. **Supervisor プロセス再起動と Top Table 検証**:
   - `python -m supervisor.cli start -D` で再起動し、`control.sock` を通じて 8 ワーカー全てが健全（`ALIVE` / `HEALTHY`）であることを確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `src/supervisor/arbiter.py` のディスパッチ分岐が修正され、`worker_class="spider"` が正しく `_run_spider_worker` で起動すること。
- [x] 単体テスト `test_spider_worker.py` が 100% PASS すること。
- [x] Supervisor Arbiter 管理下のプロセス一覧（`Live Supervisor Workers Top Table`）に `spider` ワーカーが `ALIVE / ● HEALTHY` として常駐表示されること。
- [x] コード品質ゲート（`xenon CC <= 5`, `mypy --strict 0 errors`, `make check_format`）が 100% PASS すること。
