---
ID: 237
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG] Web UI における cti_catalog_db および analytics_db のテーブル構成・行数・サイズ不整合の解消と実 VDB イントロスペクションへの刷新 (ID: 237)

## 1. 概要 / Summary

Web UI（ダッシュボードの Database Tables & Physical Storage Ledger）において、`cti_catalog_db` および `analytics_db` を選択した際に表示されるテーブル一覧、テーブル数、行数、ファイルサイズが、CLI（`dbshell` の `SHOW TABLES FROM <db>;`）および実ストレージ（`MultiTableVectorStorage`）の数値と乖離している不具合を解消する。

```text
【cti_catalog_db の乖離】
CLI: 5 テーブル / 2,685 行
- cisa_kev_vulnerabilities: 6 行, 3,175 B
- cti_mitigations: 44 行, 101,940 B
- cti_relationships: 1,923 行, 175,611 B
- cti_tactics: 15 行, 10,629 B
- cti_techniques: 697 行, 1,249,718 B

UI (修正前): 6 テーブル / 3,376 行
- cti_tactics: 15 行, 75.4 KB
- cti_techniques: 697 行, 527.6 KB
- cti_mitigations: 44 行, 150.8 KB
- cti_relationships: 1,923 行, 452.3 KB
- cisa_kev_vulnerabilities: 0 行 (※本来6件存在するが0件表示)
- cti_techniques_fts: 697 行 (※現在の VDB には存在しない過去の SQLite FTS テーブルが混入)

【analytics_db の乖離】
CLI: 5 テーブル / 26 行
- latest_snapshot: 1 行, 395 B
- metrics_history: 6 行, 6,336 B
- papers: 0 行, 34 B
- strategic_kpis: 13 行, 2,442 B
- threat_trends: 6 行, 1,210 B

UI (修正前): 4 テーブル / 26 行
- threat_trends: 6 行, 3.0 KB
- strategic_kpis: 13 行, 3.0 KB
- metrics_history: 6 行, 4.2 KB
- latest_snapshot: 1 行, 1.8 KB
(※ papers テーブルが欠落し、各テーブルサイズが固定比率で按分)
```

### 再現手順 / Steps to Reproduce
1. `manage.py dbshell` を起動し、`SHOW TABLES FROM cti_catalog_db;` および `SHOW TABLES FROM analytics_db;` を実行。
2. Web UI（`http://localhost:8000/#/database`）で `cti_catalog_db` および `analytics_db` を選択。
3. テーブル数（6 vs 5、4 vs 5）、行数、サイズが一致しないことを確認。

### 再現環境 / Environment
- OS / Env: Linux (Antigravity IDE)
- File: `src/domain/security/cti/storage.py`, `src/analytics/storage.py`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/domain/security/cti/storage.py`](file:///workspace/arxiv-security-papers/src/domain/security/cti/storage.py):
  - `_build_cti_table_descriptors` および `get_introspection_metadata` を改修し、実 `cti_catalog.vdb`（`MultiTableVectorStorage`）から正確な行数・サイズを取得する。
  - レガシーな `cti_techniques_fts` を排除し、5 テーブル（`cisa_kev_vulnerabilities`, `cti_mitigations`, `cti_relationships`, `cti_tactics`, `cti_techniques`）に統一。
- [ ] [`src/analytics/storage.py`](file:///workspace/arxiv-security-papers/src/analytics/storage.py):
  - `_build_analytics_table_descriptors` および `get_introspection_metadata` を改修し、実 `analytics.vdb`（`MultiTableVectorStorage`）から正確な行数・サイズを取得する。
  - 欠落していた `papers` テーブルを追加し、5 テーブル（`latest_snapshot`, `metrics_history`, `papers`, `strategic_kpis`, `threat_trends`）に統一。
- [ ] [`tests/web/test_database_real_introspection.py`](file:///workspace/arxiv-security-papers/tests/web/test_database_real_introspection.py):
  - `cti_catalog_db` と `analytics_db` のテーブル構成・行数・サイズが CLI と完全一致することを検証するテストの追加。

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

1. **過去の SQLite 時代のロジック残存**:
   - `CTICatalogStorage.get_introspection_metadata` および `AnalyticsStorage.get_introspection_metadata` が、`get_sqlite_table_counts` や過去の SQLite FTS テーブル定義（`cti_techniques_fts`）を呼び出していた。
   - `cti_catalog.vdb` は現在純粋バイナリの `MultiTableVectorStorage` であるため、SQLite クエリでは `cisa_kev_vulnerabilities` がカウントできず 0 件となっていた。
2. **テーブルサイズの手動按分**:
   - ファイルサイズに固定パーセンテージ（例: `int(file_size * 0.05)`）を掛けるレガシー按分ロジックが残り、実テーブルのバイトサイズ（`storage.to_bytes()`）と乖離していた。
3. **`settings.py` 定義との同期漏れ**:
   - `settings.py` の `analytics_db` には `papers` テーブルが定義されているにもかかわらず、`AnalyticsStorage` 側の記述子リストから脱落していた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix

* **暫定対処 (Workaround)**: なし。
* **恒久対策 (Permanent Fix)**:
  1. **実 VDB コンテナからの動的イントロスペクション**:
     - `_introspect_cti_vdb_metrics` および `_introspect_analytics_vdb_metrics` を実装し、`MultiTableVectorStorage` から各テーブルの `metadata` 長（行数）および `to_bytes()` 長（バイトサイズ）を正確に取得。
  2. **テーブル仕様の完全統一**:
     - `cti_catalog_db` は 5 テーブル（`cisa_kev_vulnerabilities`, `cti_mitigations`, `cti_relationships`, `cti_tactics`, `cti_techniques`）。
     - `analytics_db` は 5 テーブル（`latest_snapshot`, `metrics_history`, `papers`, `strategic_kpis`, `threat_trends`）。
  3. **自動テストによる完全一致検証**:
     - `test_cti_catalog_tables_reconciliation` および `test_analytics_tables_reconciliation` により、CLI と Web UI の完全一致を自動担保。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `fix/237-reconcile-cti-catalog-and-analytics-db-tables-with-live-vdb`

1. `src/domain/security/cti/storage.py` の改修。
2. `src/analytics/storage.py` の改修。
3. `tests/web/test_database_real_introspection.py` へのテスト追加。
4. 品質ゲート（Xenon Rank A、`mypy --strict`、pytest）の検証。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `SHOW TABLES FROM cti_catalog_db;` と Web UI の `cti_catalog_db` テーブル一覧（5 テーブル）・行数（2,685 行）・サイズが完全一致すること。
- [x] `SHOW TABLES FROM analytics_db;` と Web UI の `analytics_db` テーブル一覧（5 テーブル）・行数（26 行）・サイズが完全一致すること。
- [x] `cti_techniques_fts` が排除され、`cisa_kev_vulnerabilities` が 6 件と正確に表示されること。
- [x] `papers` テーブル（0 行, 34 B）が `analytics_db` に表示されること。
- [x] すべての自動テストが PASS し、Xenon Rank A、`mypy --strict` 0 エラーであること。
