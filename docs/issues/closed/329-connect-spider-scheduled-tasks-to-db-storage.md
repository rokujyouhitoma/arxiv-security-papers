---
ID: 329
種別: Bug
優先度: High
ステータス: Closed (Resolved)
---

# [BUG] スパイダー定期実行パス (SpiderTaskOperator) の DB 実行ログ永続化接続 (ID: 329)

## 1. 概要 / Summary
`src/workflow/operators/spider_operator.py` の `SpiderTaskOperator.execute()` において、スパイダー実行前後の DB 永続化（`SpiderExecutionStorage.record_start` / `record_finish`）が呼び出されておらず、手動トリガー（`handlers.py:handle_spider_trigger`）と異なり実行履歴やステータスが `spider_execution.vdb` に記録されない。
さらに、クロール実行パラメータの `persist_db` が `False` 固定となっており、OKF パイプラインでの DB 永続化フラグが有効化されない問題を解消した。

### 再現手順 / Steps to Reproduce
1. `WorkflowService` 経由または `Arbiter` スケジューラーから `SpiderTaskOperator` を実行する。
2. スパイダークロールログに `(DB persistence: False)` と出力される。
3. `outputs/database/spider_execution.vdb` の `spider_execution_web` テーブルを確認しても、該当実行のレコードが追加されない。

### 再現環境 / Environment
- OS / Env: Linux / Antigravity IDE
- File: `src/workflow/operators/spider_operator.py`, `src/spider/daemon/worker.py`, `src/workflow/scheduler.py`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [spider_operator.py](../../src/workflow/operators/spider_operator.py): `SpiderExecutionStorage` 連携、`job_id` 体系統一、`persist_db=True` 設定
- [x] [worker.py](../../src/spider/daemon/worker.py): `_execute_crawl` の `persist_db` パラメータデフォルト整合
- [x] [scheduler.py](../../src/workflow/scheduler.py): `_execute_task` での例外ロギング (`logger.exception`)
- [x] [test_spider_operator.py](../../tests/workflow/test_spider_operator.py): `record_start` / `record_finish` 呼び出しおよびパラメータ検証テスト

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `SpiderTaskOperator.execute()` は `SpiderDaemonClient.submit_job(job)` の呼び出しのみを行い、手動実行側（`handlers.py`）にある `SpiderExecutionStorage` の `record_start` / `record_finish` 呼び出しが実装されていなかった。
- `SpiderDaemonWorker._execute_crawl()` において `persist_db = bool(params.get("persist_db", False))` となっており、`SpiderTaskOperator` のパラメータで `persist_db=True` を渡していないため、デフォルトの `False` が適用されていた。
- `WorkflowScheduler._execute_task()` において例外が `except Exception: pass` 的に握りつぶされており、エラー発生時の追跡が不可能であった。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: Web UI から手動トリガーを実行して DB に履歴を反映させる。
* **恒久対策 (Permanent Fix)**:
  1. `SpiderTaskOperator` に `SpiderExecutionStorage` 連携を組み込み、実行開始時に `storage.record_start(job)`、正常完了時に `storage.record_finish(result)`、異常発生時に `storage.record_finish(failed_result)` を呼び出すように改修。
  2. `job_id` を手動実行と整合する命名規則（`scheduled_{spider_name}_{timestamp}`）で自動生成し、スパイダー名の正規化（`kev_cve` -> `cisa_kev`、`cve_nvd` -> `nvd_cve` 等）を導入。
  3. `job.params["persist_db"] = True` を設定し、OKF パイプラインでの DB 永続化を有効化。
  4. `WorkflowScheduler._execute_task` で `logger.exception` を追加し、例外スタックトレースを明示的にロギング。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/329-connect-spider-scheduled-tasks-to-db-storage`

1. **`SpiderTaskOperator` の改修 (`src/workflow/operators/spider_operator.py`)**:
   - `__init__` に `storage: Optional[SpiderExecutionStorage] = None` および `db_path: Optional[str] = None` を追加。
   - `_normalize_spider_name()` を導入し、スパイダー識別子を標準化。
   - `execute()` 内で `job_id = f"scheduled_{normalized_name}_{int(time.time())}"` を生成。
   - `merged_params["persist_db"] = True` をデフォルト設定。
   - `storage.record_start(job)` を実行。
   - `try-except` ブロックで `self.client.submit_job(job)` をラップし、成功時は `storage.record_finish(result)`、失敗時は `CrawlResult(job_id=job.job_id, spider_name=job.spider_name, success=False, error=str(exc))` を構築して `storage.record_finish(failed_res)` を呼び出した上で `raise`。

2. **`SpiderDaemonWorker` のデフォルト値調整 (`src/spider/daemon/worker.py`)**:
   - `_execute_crawl` の `persist_db` 取得時に、デフォルトを `True` に調整。

3. **`WorkflowScheduler` の例外ハンドリング強化 (`src/workflow/scheduler.py`)**:
   - `_execute_task` で例外発生時に `logger.exception("[WorkflowScheduler] Task '%s' execution failed: %s", task.task_id, exc)` を出力。

4. **単体・統合テストの追加 (`tests/workflow/test_spider_operator.py`)**:
   - `SpiderTaskOperator.execute()` が正常終了時に `record_start` と `record_finish(success=True)` を呼ぶことを検証。
   - 例外発生時に `record_finish(success=False)` が呼ばれ、例外が再送出されることを検証。
   - `persist_db=True` が `CrawlJob.params` に含まれることを検証。
   - 実ストレージ（一時 VDB）との結合テストを追加し、レコードが正常に永続化されることを検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `SpiderTaskOperator.execute()` 実行時に `SpiderExecutionStorage.record_start` および `record_finish` が確実に呼ばれること。
- [x] 例外発生時にも失敗ステータス（`success=False`、`error` 付き）で `record_finish` が呼ばれること。
- [x] クロールパラメータとして `persist_db=True` がスパイダーランナーに伝搬されること。
- [x] `WorkflowScheduler` がタスク例外時にスタックトレースをログ出力すること。
- [x] `tests/workflow/test_spider_operator.py` の新規テスト（全6件）がすべて PASS すること。
- [x] 全品質ゲート（`make check_format`、`make static_analysis`、`pytest`）が 100% PASS すること。
