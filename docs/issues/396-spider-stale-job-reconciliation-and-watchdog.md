---
ID: 396
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG/FEAT] 停止・異常終了した孤立スパイダージョブの定期検知および状態修復（Reconciler / Janitor）の実装 (ID: 396)

## 1. 概要 / Summary
サーバー再起動、プロセス強制終了（SIGKILL/SIGTERM/デプロイ等）、またはタイムアウト時に、データベース（`spider_execution_logs`）上に `status = 'RUNNING'` のまま取り残されるゾンビ/孤立ジョブを検知・修復する機構が存在しない問題を解消する。
常駐デーモン（`SpiderDaemonWorker`）の起動時、および `WorkflowLifecycleHook.on_flush()` の定期実行時（Watchdog）において、一定時間更新のない `RUNNING` ジョブを自動的に検出し、`status = 'INTERRUPTED'` または `FAILED (timeout/aborted)` へ安全に遷移・修復（Reconciliation）する機能を実装する。

### 再現手順 / Steps to Reproduce
1. 手動または定期タスクでスパイダー（例: `nvd_cve` や `cwe`）を実行する（DB レコードが `status = 'RUNNING'` となる）。
2. クロール処理の実行途中でサーバープロセスを Ctrl-C または `kill -9` で強制終了する。
3. サーバーを再起動して `site/index.html` または `storage.get_status_summary()` / `list_history()` を確認する。
4. 既に実行スレッド・プロセスが存在しないにもかかわらず、該当ジョブが永久に `RUNNING`（`finished_at = NULL`）として残り続ける。

### 再現環境 / Environment
- OS / Env: Linux x86_64 / Spider Execution DB (`spider_execution.vdb`)
- File: `src/spider/daemon/storage.py`, `src/workflow/service.py`, `src/supervisor/workers/spider_worker.py`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/spider/daemon/storage.py](../../src/spider/daemon/storage.py) (`reconcile_stale_jobs` メソッドおよびタイムアウト超過ジョブの修復クエリ)
- [ ] [src/workflow/service.py](../../src/workflow/service.py) (`WorkflowLifecycleHook.setup` および `on_flush` 内での定期 Reconciler 呼出)
- [ ] [src/supervisor/workers/spider_worker.py](../../src/supervisor/workers/spider_worker.py) (ワーカースタートアップ時の孤立ジョブ初期化)
- [ ] [tests/spider/test_spider_storage.py](../../tests/spider/test_spider_storage.py) (孤立ジョブ修復機能のユニットテスト)
- [ ] [tests/workflow/test_spider_operator.py](../../tests/workflow/test_spider_operator.py) (定期 Watchdog テスト)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **プロセス終了時の DB 未更新**:
   - `storage.record_finish(result)` は Python の通常実行フローの末尾でのみ同期呼び出しされる。
   - プロセスの強制終了、OOM Killer、または予期せぬクラッシュが発生した場合、`record_finish` が実行される機会がなく、DB 上のステータスは `RUNNING` のまま不変となる。
2. **起動時・定期監視時のステータス整合性チェックの欠如**:
   - デーモンやスケジューラが起動する際、過去の未完了セッションを検査するコードが一切存在しなかった。
   - 結果として過去数日〜数週間前の `RUNNING` レコードが蓄積し、UI 上で「現在も複数ジョブが実行中である」と誤認させる原因となっていた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 手動で `UPDATE spider_execution_logs SET status = 'FAILED', error_message = 'Manual cleanup' WHERE status = 'RUNNING'` を実行して DB をクリーンアップ。
* **恒久対策 (Permanent Fix)**:
  1. `SpiderExecutionStorage` に `reconcile_stale_jobs(timeout_seconds: float = 7200.0) -> int` メソッドを実装。
  2. 開始から指定時間（デフォルト 2 時間）以上経過した `RUNNING` レコード、およびデーモン起動時に直前プロセスが残した孤立 `RUNNING` レコードを自動的に `INTERRUPTED` または `FAILED`（`error_message = "Process aborted or timed out"`）へ更新。
  3. `WorkflowService` の初期化時（`setup`）および定期 `on_flush`（Supervisor の周期ティック）において、この Reconciler を自動実行。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/396-spider-stale-job-reconciliation-and-watchdog`

1. **Storage 層への Reconcile ロジック追加**:
   - `src/spider/daemon/storage.py` に `reconcile_stale_jobs` を追加。
   - 指定タイムアウト（スパイダー毎の推奨タイムアウト: arxiv: 30分, cwe: 1時間, cve: 3時間など）を超過した `RUNNING` レコードを抽出し、`finished_at = now`, `status = 'INTERRUPTED'` または `'FAILED'` に一括更新。
2. **デーモン・サービス起動時の自動実行組み込み**:
   - `src/workflow/service.py` の `WorkflowService.__init__` または `register_default_spider_tasks` 実行時に `self.storage.reconcile_stale_jobs()` を実行。
   - `WorkflowLifecycleHook.on_flush()` 内で、前回のクリーンアップから一定間隔（例: 10分毎）で定期修復を実行。
3. **Web API 連携**:
   - `/api/spiders/status` 取得時にも、必要に応じて最新の稼働状態が実態と乖離しないよう安全にクエリ。
4. **テスト作成と品質検証**:
   - 意図的に古いタイムスタンプで `RUNNING` を作成したテストケースを用意し、正しく `INTERRUPTED` に遷移することを検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] タイムアウトを超過した過去の `RUNNING` ジョブが、デーモン起動時または定期実行時に自動で `INTERRUPTED` / `FAILED` に修復されること。
- [ ] 既存の `spider_execution.vdb` に残存している過去の孤立 `RUNNING` レコード（09-19, 09-24 等）が綺麗に解消されること。
- [ ] `make test` および `make static_analysis` (Xenon A, Mypy strict) が全て PASS すること。
