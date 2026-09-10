---
ID: 236
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG] Web UI (データベース台帳) における arxiv_security_db の旧式合成テーブル廃止と settings.py / SQLExecutor への完全統一およびセレクトボックス化 (ID: 236)

## 1. 概要 / Summary

現在、Web UI（ダッシュボードの Database Tables & Physical Storage Ledger）において、`arxiv_security_db` を選択した際に表示されるテーブル群（`paper_metadata`, `papers_vector`, `search_inverted_index`, `analytics_metrics` の 4 テーブル）と、CLI（`dbshell`）で `SHOW TABLES FROM arxiv_security_db;` を実行した際の結果（`okf_papers`, `processed_papers`, `raw_papers` の 3 テーブル）との間で、テーブル名、テーブル数（4 vs 3）、件数、ファイルサイズが完全に乖離していた。

```text
【CLI (dbshell) の実行結果】
arxiv-sec-db> SHOW TABLES FROM arxiv_security_db;
+------------------+-------+------------+
| Table            | Rows  | Size_bytes |
+------------------+-------+------------+
| okf_papers       | 14681 | 20480      |
| processed_papers | 14681 | 3418351    |
| raw_papers       | 29245 | 20480      |
+------------------+-------+------------+
3 rows in set

【Web UI (ダッシュボード) の表示 - 修正前】
Database: arxiv_security_db
Tables: 4 Tables
Total Rows: 44,243 Rows
Total Size: 179.77 MB
- paper_metadata (14,739件, 6.89 MB)
- papers_vector (14,739件, 64.77 MB)
- search_inverted_index (14,739件, 108.11 MB)
- analytics_metrics (26件, 118 B)
```

本 Issue ではユーザー合意の「方針 A（`settings.py` への完全統一）」を採用し、Web UI ゲートウェイ（`src/web/gateway/handlers.py`）に残存する旧来の独自スキャン・手作業合成ロジック（`_collect_database_tables` 等）を完全撤廃し、CLI と全く同じ `settings.DATABASES` および `SQLExecutor` 経由で `arxiv_security_db` の実テーブル台帳を取得・表示するように刷新した。
さらに、`cti_catalog_db`, `analytics_db`, `graph_db` についても `settings.py` の定義に基づく表示に統一し、Web UI においてデータベースを直感的に切り替えられるセレクトボックス（`#selectDbScope`）を新設してピルボタンと双方向連動させた。

### 再現手順 / Steps to Reproduce
1. `manage.py dbshell` を起動し、`SHOW TABLES FROM arxiv_security_db;` を実行（3テーブル表示）。
2. Web UI（`http://localhost:8000/#/database`）を開き、`arxiv_security_db` のテーブル台帳を確認（4テーブル表示）。
3. テーブル名・件数・サイズが一致しないことを確認。

### 再現環境 / Environment
- OS / Env: Linux (Antigravity IDE)
- File: `src/web/gateway/handlers.py`, `src/settings.py`, `site/index.html`, `site/app.js`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/web/gateway/handlers.py`](file:///workspace/arxiv-security-papers/src/web/gateway/handlers.py):
  - `_collect_database_tables`、`_introspect_paper_table_metrics`、`_introspect_vector_and_search_metrics`、`_introspect_analytics_metrics` 等のレガシー手動合成ロジックを撤廃。
  - `_introspect_okf_papers_table`、`_introspect_processed_papers_table`、`_introspect_raw_papers_table` を新設し、`settings.DATABASES["arxiv_security_db"]` の仮想テーブル定義に完全統一。
  - `analytics_metrics` の `arxiv_security_db` への誤混入を排除（`analytics_db` 側のみで扱う）。
  - `arxiv_db_info` のカテゴリ、ストレージエンジン、ファイルパス定義を更新。
- [x] [`site/index.html`](file:///workspace/arxiv-security-papers/site/index.html):
  - データベース選択 UI として `<select id="selectDbScope">` を新設。
  - ピルボタン（`databaseSelectorPills`）のテキストを `settings.py` に合わせて統一。
- [x] [`site/app.js`](file:///workspace/arxiv-security-papers/site/app.js) / [`site/app-min.js`](file:///workspace/arxiv-security-papers/site/app-min.js):
  - `selectDbScope` の change イベントリスナーを追加し、データベース切り替えを実装。
  - `renderDatabaseTab` において、ピルクリック時にもセレクトボックスの表示が即座に同期する双方向バインディングを実装。
- [x] [`tests/web/test_database_real_introspection.py`](file:///workspace/arxiv-security-papers/tests/web/test_database_real_introspection.py):
  - Web UI イントロスペクションで `arxiv_security_db` に `okf_papers`, `processed_papers`, `raw_papers` が返され、CLI の出力と完全一致することを検証するテストの更新。
- [x] [`tests/web/test_enterprise_console_ui.py`](file:///workspace/arxiv-security-papers/tests/web/test_enterprise_console_ui.py):
  - `site/index.html` の `selectDbScope` ドロップダウンおよび `site/app.js` のハンドラー存在を検証するテストアサーションを追加。

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

1. **二重管理の残存**:
   - Issue #234 で `src/settings.py` を新設して CLI (`dbshell`) 側は設定駆動に統合したが、Web UI の `_introspect_database_metrics` 内部では依然として過去の `_collect_database_tables` が呼ばれていた。
2. **架空・合成テーブルの存在**:
   - `_introspect_vector_and_search_metrics` は、検索インデックス実体（`outputs/vector_db/index.json`）のファイルサイズを按分して `papers_vector` と `search_inverted_index` という見せかけのテーブルを合成していた。
3. **他データベース所属テーブルの混入**:
   - `_introspect_analytics_metrics` は、本来 `analytics_db`（`analytics.vdb`）に属するテレメトリデータを `arxiv_security_db` の配下に合成混入させていた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix

* **暫定対処 (Workaround)**: なし。
* **恒久対策 (Permanent Fix)**:
  1. **Web UI ゲートウェイの SSOT 準拠化**:
     - `_introspect_database_metrics` を改修し、`arxiv_security_db` のテーブル一覧を `settings.DATABASES["arxiv_security_db"]` に基づき直接構築。
  2. **テーブル一覧・件数・サイズの完全一致**:
     - Web UI で表示されるテーブルを `okf_papers`, `processed_papers`, `raw_papers` の 3 テーブルとし、行数およびサイズを `dbshell` と 100% 一致させた。
  3. **セレクトボックス新設とピル連携**:
     - ユーザー要件に基づき、`<select id="selectDbScope">` を設置し、ピルと完全に双方向同期する直感的なDB選択体験を提供。
  4. **レガシー合成関数のクリーンアップ**:
     - 未使用となった手動按分・合成関数（`_introspect_vector_and_search_metrics` 等）を安全に撤廃。

---

## 5. 完了の定義 (Definition of Done: DoD)

- [x] `SHOW TABLES FROM arxiv_security_db;` と Web UI の `arxiv_security_db` テーブル一覧が一致（3 テーブル: `okf_papers`, `processed_papers`, `raw_papers`）。
- [x] `paper_metadata`、`papers_vector`、`search_inverted_index`、`analytics_metrics` が `arxiv_security_db` から完全に排除されていること。
- [x] Web UI (`site/index.html` / `site/app.js`) に `<select id="selectDbScope">` が実装され、ピルと連動してDB切り替えが可能であること。
- [x] `tests/web/test_database_real_introspection.py` および `tests/web/test_enterprise_console_ui.py` が PASS すること。
- [x] Xenon Rank A (CC <= 5)、`mypy --strict` 0 エラーを達成していること。
