---
ID: 320
種別: Feature / Architecture
優先度: High
ステータス: Closed
---

# [FEAT] スパイダー自律定期実行・実行状態DB永続化およびWebコンソール監視UIの実装 (ID: 320)

## 1. 概要 / Summary
Supervisor 管理下で稼働する常駐クローラーデーモン（`SpiderWorker`）と定期タスクスケジューラ（`WorkflowScheduler`）を連携させ、外部セキュリティ脅威インテリジェンス・学術論文（arXiv, MITRE CWE, CISA KEV, NVD CVE）の自律定期収集（Scheduled Crawl）を実現する。
さらに、実行結果・ステータス（RUNNING / SUCCESS / FAILED / BACKOFF）、取得件数、HTTP統計、所要時間、次回実行予定を自作データベース（`outputs/database/`）の専用テーブルに永続化し、Web Gateway API（`/api/spiders/status`, `/api/spiders/history`）および Web コンソール（`site/index.html`）のグラスモーフィック監視パネルにリアルタイム表示する。

---

## 2. トレーサビリティ / Traceability
- リポジトリ内設計仕様書:
  - [DSN-06: 分散スパイダー & クローラー基盤](../designs/DSN-06-distributed_spider_and_crawler.md)
  - [DSN-11: ユニバーサルワークフローエンジン](../designs/DSN-11-universal_workflow_engine.md)
  - [DSN-12: プロセススーパーバイザー & アービター](../designs/DSN-12-process_supervisor_and_arbiter.md)
  - [DSN-21: エンタープライズデザインシステム & 統合コンソールUI](../designs/DSN-21-enterprise_design_system_and_unified_console.md)
- 関連 Issue:
  - [Issue 223: 常駐型 Spider Daemon / Spider Worker 実装](closed/223-implement-resident-spider-daemon-and-workflow-supervisor-integration.md)
  - [Issue 153: Supervisor 4x daily 自律バッチ運用](closed/153-implement-supervisor-4xdaily-cron-and-cti-backfill-reannotation.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/spider/daemon/storage.py](../../src/spider/daemon/storage.py) (DB 永続化ヘルパー)
- [x] [src/workflow/service.py](../../src/workflow/service.py) (Workflow/Scheduler サービスフック)
- [x] [config/supervisor.json](../../config/supervisor.json) (Supervisor サービス登録)
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (Spider Status/History API)
- [x] [src/web/gateway/app.py](../../src/web/gateway/app.py) (ルーティング追加)
- [x] [site/index.html](../../site/index.html) (Spider 監視パネル UI)
- [x] [site/app.js](../../site/app.js) (Spider ステータス取得・描画・手動トリガー)
- [x] [tests/spider/test_spider_db_persistence.py](../../tests/spider/test_spider_db_persistence.py) (DB 永続化テスト)
- [x] [tests/web/test_spider_status_api.py](../../tests/web/test_spider_status_api.py) (API & Gateway テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/320-scheduled-spider-db-ui`

1. **DB 永続化層（`src/spider/daemon/storage.py`）**:
   - `spider_execution_logs` テーブルの自動作成およびジョブ開始（INSERT）・終了（UPDATE）トランザクション。
2. **Supervisor & ワークフロー常駐サービス（`src/workflow/service.py`, `config/supervisor.json`）**:
   - `WorkflowLifecycleHook` を新設し、`WorkflowScheduler` を常駐待機ループとして管理。
   - arXiv (6hごと), CWE (24hごと), KEV/CVE (6hごと) の定期実行タスクを登録。
   - `config/supervisor.json` に `spider`（`SpiderWorker`）と `workflow`（`WorkflowService`）を追加。
3. **Web Gateway API（`src/web/gateway/`）**:
   - `GET /api/spiders/status`: 全スパイダーの最新稼働状態サマリー。
   - `GET /api/spiders/history`: 直近のクロール履歴ログ（最新 50 件）。
   - `POST /api/spiders/trigger`: 手動オンデマンド実行トリガー。
4. **Web コンソール UI（`site/index.html`, `site/app.js`）**:
   - 「システム運用 & 監査」にスパイダー監視パネル（ステータスバッジ、次回カウントダウン、履歴テーブル、手動実行ボタン）を配置。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `spider_execution_logs` テーブルに実行状態（開始・完了・件数・所要時間・エラー）が確実に永続化されること。
- [ ] Supervisor の `config/supervisor.json` で `spider` および `workflow` サービスが正常に管理・起動できること。
- [ ] Web Gateway API `/api/spiders/status` および `/api/spiders/history` が正常にレスポンスを返却すること。
- [ ] `site/index.html` にて各スパイダーの稼働状況・次回予定・履歴がリアルタイム表示されること。
- [ ] `make format`, `make static_analysis` (xenon Rank A, mypy strict), `make test` が 100% PASS すること。
