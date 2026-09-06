---
ID: 195
種別: Feature / UIUX
優先度: High
ステータス: Closed
Created At: 2026-09-06T21:08:00+09:00
Closed At: 2026-09-06T21:18:50+09:00
---

# [FEAT/UIUX] データベース・ストレージ台帳の専用独立タブ化およびマルチデータベース（cti_catalog / analytics / graph）統合インスペクションの実装 (ID: 195)

## 1. 概要 / Summary

エンタープライズ統合コンソール（`site/index.html`）において、現在「📈 システム観測 & ライフサイクル運用 (`systemTab`)」内に同居しているデータベースKPIおよび物理ストレージ台帳テーブル（`databaseTablesTableBody`）を、専用の独立タブ **「🗄️ データベース & ストレージ管理 (`databaseTab` / `#/database`)」** へ分離・新設する。
また、従来の `arxiv_security_db` 単一DB表示を拡張し、リポジトリ内に実在する全4大データベース（`arxiv_security_db`, `cti_catalog_db`, `analytics_db`, `graph_db`）をシームレスに切り替えて、各DBのテーブル一覧・行数・ファイルサイズ・主キー/インデックス構造・SQLイントロスペクション結果を閲覧できる統合マルチデータベース・インスペクターを実装する。

これによって、`systemTab` はパイプライン監視、OBF 分散トレーシング、Traversal Matrix、SLA/SLO などの運用・可観測性（Ops/Observability）に特化した高認知的効率の画面となり、新設の `databaseTab` において複数データベースの構造や容量を包括的に可視化・監査可能とする。

---

## 2. トレーサビリティ / Traceability
- 設計書: [DSN-05 ゼロ依存 4層ベクトルデータベース & 分散合意・カオス耐性設計書](../designs/DSN-05-database_engine_architecture.md)
- 設計書: [DSN-20 外部セキュリティ知識データセット統合インジェスト・ローカルカタログ管理基盤設計仕様書](../designs/DSN-20-external_security_knowledge_ingestion_and_catalog_architecture.md)
- 設計書: [DSN-21 エンタープライズ統合デザインシステム ＆ クラウドコンソール UI 包括設計書](../designs/DSN-21-enterprise_design_system_and_unified_console.md)
- 関連実装: `src/web/gateway/handlers.py`, `site/index.html`, `site/app.js`

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (4大DBの包括的テーブル・サイズ・行数イントロスペクション)
- [x] [site/index.html](../../site/index.html) (systemTabからのDB分離、新設databaseTab、サイドバーナビゲーション、DB切替セレクタ)
- [x] [site/app.js](../../site/app.js) (TAB_CONFIG、ルーティング、マルチDB状態管理および動的テーブルレンダリング)
- [x] [site/app-min.js](../../site/app-min.js) (Google Closure Compiler 最適化 JS バンドル)
- [x] [tests/web/test_enterprise_console_ui.py](../../tests/web/test_enterprise_console_ui.py) (UIテスト拡充)
- [x] [docs/issues/README.md](README.md) (Issue 台帳更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/195-separate-database-explorer-tab-and-support-multi-database`

1. **バックエンド Multi-DB イントロスペクションの実装 (`src/web/gateway/handlers.py`)**:
   - `_introspect_cti_catalog_tables(workspace_dir)`: `outputs/database/catalog/cti_catalog.db` 内のテーブル（`cti_tactics`, `cti_techniques`, `cti_mitigations`, `cti_relationships`, `cti_techniques_fts`）の行数・ファイルサイズ・インデックス情報を取得。
   - `_introspect_analytics_db_tables(workspace_dir)`: `outputs/database/analytics/analytics.db` 内のテーブル（`threat_trends`, `strategic_kpis`, `metrics_history`, `latest_snapshot`, `papers`）の行数・ファイルサイズ情報を取得。
   - `_introspect_graph_db_tables(workspace_dir)`: `outputs/database/graph/graph.db` および `outputs/database/engine/*.vdb` からオントロジー/グラフ関連テーブル（`tbox_classes`, `tbox_properties`, `abox_vertices`, `abox_edges`, `claims_evidences` 等）のメタデータを取得。
   - `_introspect_database_metrics` を改修し、`databases` ディクショナリ（各DBのメタデータ・テーブルリスト・KPI）を包括返却。

2. **フロントエンド UI の再構築 (`site/index.html`)**:
   - `systemTab`: カード6（Database Performance & IOPS）および「Database Tables & Physical Storage Ledger」テーブルを撤去し、システム観測とパイプライン運用に集中。
   - サイドバー: 「システム運用 & 監査」内に `navDatabase` (`#/database`) を配置。
   - `databaseTab`:
     - 4大DB切替ピルボタングループ（`arxiv_security_db`, `cti_catalog_db`, `analytics_db`, `graph_db`）。
     - 選択中DBのステータスKPIカード（エンジン種別、ファイルパス、総容量、総レコード数、テーブル数、WAL状態）。
     - SQL イントロスペクション端末 (`SHOW DATABASES;`, `SHOW TABLES FROM <selected_db>;`)。
     - `databaseTablesTableBody` を配置し、選択されたDBのテーブル構造（テーブル名、カテゴリ、ストレージエンジン、行数、サイズ、PK/インデックス）を一覧表示。

3. **フロントエンド制御ロジックの実装 (`site/app.js`)**:
   - `TAB_CONFIG` に `databaseTab` を登録。
   - `handleRoute` で `#/database`, `tab=database`, `tab=db`, `tab=storage` を `databaseTab` にルーティング。
   - `updateDatabaseMetrics` において全DBデータを状態保持し、ピルボタンのクリックで表示対象DBを即時切り替えるイベントハンドラを実装。

4. **JSバンドルビルドと自動テスト (`make build_js`, `pytest`)**:
   - `make build_js` により `site/app-min.js` を生成。
   - `tests/web/test_enterprise_console_ui.py` に `navDatabase`, `databaseTab` の存在確認テストを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `site/index.html` に `databaseTab` およびサイドバー `navDatabase` が新設され、`systemTab` からDBテーブルが分離されていること。
- [x] `arxiv_security_db`, `cti_catalog_db`, `analytics_db`, `graph_db` の4大データベースがUI上で選択・切替可能であること。
- [x] 各データベースを選択した際、対応するテーブル群、行数、ファイルサイズ、PK/インデックス、SQLクエリが正しく表示されること。
- [x] `make build_js` が成功し、`site/app-min.js` が更新されること。
- [x] `tests/web/test_enterprise_console_ui.py` を含む関連テストが 100% PASS すること。
- [x] `make check_format` および `make static_analysis` がエラー0件で通過すること。
