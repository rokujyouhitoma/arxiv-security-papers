---
ID: 335
種別: Bug
優先度: High
ステータス: Closed (Completed)
---

# [BUG] スパイダー自動テストにおける本番DB汚染の解消（テストDB完全分離）と実行ログ台帳クリーンアップ (ID: 335)

## 1. 概要 / Summary
開発およびCIでの品質検証テスト（`make check` / `pytest tests/` 等）実行時、スパイダー実行ログ台帳のデータベース（`outputs/database/spider_execution.vdb`）に対してテスト由来のジョブレコード（`max_requests` 指定ジョブや未完了の `RUNNING` レコード）が直接書き込まれ、本番Webコンソール上の実行履歴が数分間隔で頻繁に更新・汚染される現象が発生した。
本Issueでは、スパイダーおよびスケジューラーの全テストケースにおいて一時ディレクトリ（`tempfile.TemporaryDirectory`）内の分離DBを確実に使用するよう改修し、本番DB（`outputs/database/spider_execution.vdb`）からテスト混入レコードをクリーンアップする。

### 再現手順 / Steps to Reproduce
1. `make check` または `pytest tests/workflow/test_spider_operator.py tests/spider/test_spider_db_persistence.py` を実行する。
2. `outputs/database/spider_execution.vdb` の中身（またはWebコンソールのスパイダー実行ログ台帳）を確認する。
3. `scheduled_arxiv_<timestamp>` や `scheduled_cwe_<timestamp>`、`max_requests` を含むテスト用レコードが本番DBに追記されている。

### 再現環境 / Environment
- OS / Env: Linux / Python 3.11
- File: `tests/workflow/test_spider_operator.py`, `tests/spider/test_spider_db_persistence.py`, `outputs/database/spider_execution.vdb`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [tests/workflow/test_spider_operator.py](../../tests/workflow/test_spider_operator.py) (テストDB分離)
- [x] [tests/spider/test_spider_db_persistence.py](../../tests/spider/test_spider_db_persistence.py) (WorkflowLifecycleHookテストのDB分離・モック整合)
- [x] [tests/spider/test_spider_daemon.py](../../tests/spider/test_spider_daemon.py) (SpiderDaemonWorkerテストのDB分離)
- [x] [tests/conftest.py](../../tests/conftest.py) (グローバルセッション分離フィクスチャ新設)
- [x] [src/workflow/operators/spider_operator.py](../../src/workflow/operators/spider_operator.py) (環境変数オーバーライド)
- [x] [src/workflow/scheduler.py](../../src/workflow/scheduler.py) (ストレージ/DBパス注入サポート)
- [x] [src/workflow/service.py](../../src/workflow/service.py) (ストレージ/DBパス注入サポート)
- [x] [src/spider/daemon/storage.py](../../src/spider/daemon/storage.py) (環境変数フォールバックサポート)
- [x] [outputs/database/spider_execution.vdb](../../outputs/database/spider_execution.vdb) (テストレコードのクリーンアップ)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **テストコードにおけるストレージ未指定とデフォルトパス依存**:
   - `SpiderTaskOperator` はデフォルトで `outputs/database/spider_execution.vdb` を参照する。
   - `test_spider_operator.py` の一部テスト（`test_direct_operator_execution`, `test_dag_workflow_integration`, `test_workflow_scheduler_with_spider_task`）において、一時DB（`tempfile`）の `storage` をインジェクトせずにオペレーターを初期化・実行していた。
2. **`WorkflowLifecycleHook` テストの分離漏れとモック不整合**:
   - `test_spider_db_persistence.py` の `TestWorkflowService.test_task_scheduling_logic` において、`WorkflowLifecycleHook` がデフォルト設定で初期化され、`outputs/database/spider_execution.vdb` をそのまま使用していた。
   - さらに、`mock_submit.return_value = CrawlResult(job_id="test", ...)` と固定IDを返していたため、`SpiderTaskOperator.execute` が生成・登録した `job_id` (`scheduled_<spider>_<timestamp>`) と不整合が発生し、DB上で `RUNNING` ステータスから完了（SUCCESS/FAILED）に更新されず滞留していた。
3. **`SpiderDaemonWorker` テストにおける `db_path` 未指定**:
   - `test_spider_daemon.py` の `TestSpiderDaemonWorker` において、`db_path` を渡さずに初期化していたため、実行されたジョブが本番DBに記録されていた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: なし（テストを実行するたびに本番DBが再汚染されるため、根本修正が必須）。
* **恒久対策 (Permanent Fix)**:
  1. `test_spider_operator.py` 内の全テストケースで一時ディレクトリの `SpiderExecutionStorage` を明示的に指定・隔離。
  2. `test_spider_db_persistence.py` において、一時ディレクトリのストレージを注入し、`mock_submit` の返却ジョブIDを呼び出し引数の `job.job_id` に動的連動。
  3. `test_spider_daemon.py` において、一時ディレクトリの `test_spider.vdb` を指定。
  4. `tests/conftest.py` を新設し、テストセッション全体で `SPIDER_EXECUTION_DB_PATH` 環境変数を一時ディレクトリへ向ける自動分離フィクスチャを標準配備（多層防御）。
  5. `outputs/database/spider_execution.vdb` からテスト由来のレコードを安全に全件クリーンアップ。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/335-isolate-spider-test-db-and-cleanup-execution-log`

1. **`tests/workflow/test_spider_operator.py` の改修**:
   - `setUp` / `tearDown` で一時ディレクトリ `tempfile.TemporaryDirectory` を作成し、テスト用の `test_spider_execution.vdb` を割り当てた `SpiderExecutionStorage` を生成。
   - 各テストケースにこの一時 `storage` を注入。
2. **`tests/spider/test_spider_db_persistence.py` の改修**:
   - `TestWorkflowService.test_task_scheduling_logic` において、一時ストレージを注入。
   - `mock_submit` の副作用関数（side_effect）で `job.job_id` をそのまま `CrawlResult(job_id=job.job_id, ...)` として返却。
3. **`src/` コア層の多層防御**:
   - `SpiderExecutionStorage` および `SpiderTaskOperator` で `SPIDER_EXECUTION_DB_PATH` 環境変数をサポート。
   - `WorkflowScheduler.register_spider_task` および `WorkflowService` / `WorkflowLifecycleHook` に `storage` / `db_path` 引数を新設。
4. **本番ログ台帳（`outputs/database/spider_execution.vdb`）のクリーンアップ**:
   - テスト由来の汚染レコードを削除し初期化。
5. **検証**:
   - 全122テストを実行し、実行後も本番DBのレコード数が 0 件のままであることを完全検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] すべてのスパイダー関連テストを実行しても、`outputs/database/spider_execution.vdb` のレコード数が一切増加・変更されないこと。
- [x] `TestWorkflowService` 内のモックがジョブID不整合を起こさず、正常に完了ステータスを処理すること。
- [x] 本番ログ台帳（`outputs/database/spider_execution.vdb`）からテスト起因の汚染レコードが除去されていること。
- [x] `make format`, `make static_analysis`, `make test` のトリプル品質ゲートが 100% PASS すること。
