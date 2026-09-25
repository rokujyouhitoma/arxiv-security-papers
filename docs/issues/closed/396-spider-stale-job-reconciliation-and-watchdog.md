---
ID: 396
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/FEAT] 停止・異常終了した孤立スパイダージョブの定期検知および状態修復（Reconciler / Janitor）の実装 (ID: 396)

## 1. 概要 / Summary
サーバー再起動、プロセス強制終了（SIGKILL/SIGTERM/デプロイ等）、またはタイムアウト時に、データベース（`spider_execution_logs`）上に `status = 'RUNNING'` のまま取り残されるゾンビ/孤立ジョブを検知・修復する機構が存在しない問題を解消する。
常駐デーモン（`SpiderDaemonWorker`）の起動時、`handle_spider_status` API 呼出時、および `WorkflowLifecycleHook.on_flush()` の定期実行時（Watchdog）において、一定時間（デフォルト2時間）更新のない `RUNNING` ジョブを自動的に検出し、`status = 'INTERRUPTED'`（`finished_at = now`, `error_message = 'Process aborted or timed out'`）へ安全に遷移・修復（Reconciliation）する機能を実装する。

### 再現手順 / Steps to Reproduce
1. 手動または定期タスクでスパイダー（例: `nvd_cve` や `cwe`）を実行する（DB レコードが `status = 'RUNNING'` となる）。
2. クロール処理の実行途中でサーバープロセスを Ctrl-C または `kill -9` で強制終了する。
3. サーバーを再起動して `site/index.html` または `storage.get_status_summary()` / `list_history()` を確認する。
4. 既に実行スレッド・プロセスが存在しないにもかかわらず、該当ジョブが永久に `RUNNING`（`finished_at = NULL`）として残り続ける。

### 再現環境 / Environment
- OS / Env: Linux x86_64 / Spider Execution DB (`spider_execution.vdb`)
- File: `src/spider/daemon/storage.py`, `src/workflow/service.py`, `src/web/gateway/handlers.py`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/spider/daemon/storage.py](../../../src/spider/daemon/storage.py) (`reconcile_stale_jobs` メソッドおよびタイムアウト超過ジョブの修復クエリ)
- [x] [src/workflow/service.py](../../../src/workflow/service.py) (`WorkflowLifecycleHook.setup` および `on_flush` 内での定期 Reconciler 呼出)
- [x] [src/web/gateway/handlers.py](../../../src/web/gateway/handlers.py) (`handle_spider_status` 内での自動整合性修復呼出)
- [x] [tests/spider/test_spider_daemon.py](../../../tests/spider/test_spider_daemon.py) (孤立ジョブ修復機能のユニットテスト)
- [x] [tests/web/test_web_server.py](../../../tests/web/test_web_server.py) (API 連携テスト)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **プロセス終了時の DB 未更新**:
   - `storage.record_finish(result)` は Python の通常実行フローの末尾でのみ同期呼び出しされる。
   - プロセスの強制終了、OOM Killer、または予期せぬクラッシュが発生した場合、`record_finish` が実行される機会がなく、DB 上のステータスは `RUNNING` のまま不変となる。
2. **起動時・定期監視時のステータス整合性チェックの欠如**:
   - デーモンやスケジューラが起動する際、過去の未完了セッションを検査するコードが一切存在しなかった。
   - 結果として過去数日〜数週間前の `RUNNING` レコードが蓄積し、UI 上で「現在も複数ジョブが実行中である」と誤認させる原因となっていた。

---

## 4. セキュリティ・信頼性分析 (Reliability & Integrity)
- **影響**: ゾンビジョブの残存により、排他ロック（Issue #395）が永久に解除されず、該当スパイダーの次回実行がブロックされ続ける危険性がある。
- **解決方針**:
  - `reconcile_stale_jobs(timeout_seconds=7200.0)` により、タイムアウトを超過した `RUNNING` ジョブを検知して確実に `INTERRUPTED` へ自動修復するフェイルセーフを構築。

---

## 5. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 手動で `UPDATE spider_execution_logs SET status = 'FAILED', error_message = 'Manual cleanup' WHERE status = 'RUNNING'` を実行して DB をクリーンアップ。
* **恒久対策 (Permanent Fix)**:
  1. `SpiderExecutionStorage` に `reconcile_stale_jobs(timeout_seconds: float = 7200.0) -> int` メソッドを実装。
  2. 開始から指定時間（デフォルト 2 時間）以上経過した `RUNNING` レコードを自動的に `INTERRUPTED`（`error_message = "Process aborted or timed out"`）へ更新。
  3. `WorkflowService` の初期化時（`setup`）、定期 `on_flush`、および `handle_spider_status` API 呼出時に、この Reconciler を自動実行。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `fix/396-spider-stale-job-reconciliation-and-watchdog`

1. **Storage 層への Reconcile ロジック追加**:
   - `src/spider/daemon/storage.py` に以下を実装（Xenon Rank A, CC <= 3 を順守）：
     - `_find_stale_jobs(conn: Connection, timeout_seconds: float, now_dt: datetime.datetime) -> List[Tuple[str, float]]`
     - `_update_stale_job(cur: Any, job_id: str, elapsed: float, now_iso: str) -> None`
     - `reconcile_stale_jobs(timeout_seconds: float = 7200.0) -> int`
2. **デーモン・サービス起動時および定期監視の組み込み**:
   - `src/workflow/service.py` の `WorkflowService.__init__` でストレージ初期化時に `reconcile_stale_jobs()` を呼出。
   - `WorkflowLifecycleHook.on_flush()` で 300 秒（5分）以上の間隔で定期的に `reconcile_stale_jobs()` を呼出。
3. **Gateway API 連携**:
   - `src/web/gateway/handlers.py` の `handle_spider_status` でステータス返却前に `storage.reconcile_stale_jobs()` を呼び出し、UI に常に実態と合致したステータスを返却。
4. **既存 DB の孤立レコードクリーンアップ**:
   - 既存の `outputs/database/spider_execution.vdb` に残存する過去の `RUNNING` レコード（09-19, 09-24 等）を一掃。
5. **テスト作成と品質検証**:
   - `tests/spider/test_spider_daemon.py` に `TestSpiderStaleJobReconciliation` を追加。
   - `make test` および `make static_analysis` (Xenon A, Mypy strict) をパスすること。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] タイムアウトを超過した過去の `RUNNING` ジョブが、デーモン起動時・定期実行時・ステータス取得時に自動で `INTERRUPTED` に修復されること。
- [x] 既存の `spider_execution.vdb` に残存している過去の孤立 `RUNNING` レコードが修復され、正しく完了ステータスになること。
- [x] 全ての新規・変更関数の循環的複雑度が CC <= 3 (Xenon Rank A) であること。
- [x] `tests/spider/` および `tests/web/` のテストが全件 PASS すること。
- [x] `make static_analysis` (Xenon A, Mypy strict) をパスすること。
