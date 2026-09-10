---
ID: 234
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] settings.py によるデータベース定義の一元管理 (SSOT) と SQL イントロスペクション・Web UI 乖離の解消 (ID: 234)

## 1. 概要 / Summary

現在、`manage.py dbshell` におけるデータベーススコープ・テーブル定義（`okf_papers`, `processed_papers`, `raw_papers` や `cti_catalog.vdb` 等）と、Web UI ゲートウェイ（`src/web/gateway/handlers.py`）におけるテーブル台帳・スキャン定義（`paper_metadata`, `papers_vector`, `search_inverted_index`, `analytics_metrics` 等）がそれぞれ個別にハードコードされており、以下の課題が生じていた：

1. **信頼できる唯一の情報源（SSOT）の欠如**:
   - どのデータベースが存在し、どのテーブルがどのストレージエンジン・ファイルパスにマウントされているかが一元化されておらず、CLI と Web UI 間で表示テーブルや件数に不整合が発生していた。
2. **`SHOW TABLES FROM <database>` の不整合**:
   - `SQLExecutor` における `SHOW TABLES FROM ...` 構文の解釈が、外部のバイナリ `.vdb` ファイルのみを対象とし、マウント済み仮想テーブル（Virtual Tables: Markdown / Text / JSON）を認識しないため、`SHOW TABLES FROM arxiv_security_db;` が `(0 rows)` になっていた。
3. **Web UI のモック風表現**:
   - Web UI の `SHOW TABLES FROM arxiv_security_db; → 4 tables` という表示は、実際に SQL エンジンを実行した結果ではなく、バックエンドファイル群を独自スキャンして合成したサマリーであった。

本 Issue では、Django の `settings.DATABASES` パターンに倣い、`src/settings.py` を新設してデータベース定義を一元化し、`SQLExecutor`、CLI（`dbshell` / `tables`）、および Web ゲートウェイをすべて設定駆動（Settings-driven）へと統合・刷新した。

---

## 2. トレーサビリティ / Traceability

- 設計書: `docs/designs/DSN-24-unified_management_cli_and_interactive_database_shell.md`
- 設計書: `docs/designs/DSN-05-database_engine_architecture.md` (Section 21 Multi-Storage & DDL)
- 関連Issue: Issue #216, Issue #217, Issue #218, Issue #229, Issue #230, Issue #231, Issue #232, Issue #233
- ガバナンス規約: `.agents/AGENTS.md` (1. Governance & PM-Led Multi-Agent Framework, 6. Raw Data Preservation & Idempotency Rules)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/settings.py`](../../../src/settings.py): 新設。`BASE_DIR`、`DATABASES` 辞書定義、およびヘルパー関数（`get_database_scopes`, `get_table_scope_from_settings`, `get_table_type_from_settings` 等）の実装
- [x] [`src/cli/commands/dbshell.py`](../../../src/cli/commands/dbshell.py): ハードコードされた `DATABASE_SCOPES` やパス結合を撤廃し、`settings.DATABASES` を参照するように移行
- [x] [`src/cli/commands/tables.py`](../../../src/cli/commands/tables.py): `settings.DATABASES` を参照してテーブル一覧とスコープ・種別を表示
- [x] [`src/database/sql/executor.py`](../../../src/database/sql/executor.py): `SHOW TABLES FROM <database>` の実行時に、マウント済みテーブルカタログおよび `settings.DATABASES` からスコープに該当するテーブル（仮想テーブル含む）を正確に返却
- [x] [`src/web/gateway/handlers.py`](../../../src/web/gateway/handlers.py): `_resolve_application_databases` 等を `settings.DATABASES` 準拠に統一し、実 SQL エンジン経由でテーブル台帳を取得
- [x] [`tests/cli/test_manage_dbshell.py`](../../../tests/cli/test_manage_dbshell.py): `settings.DATABASES` 連携および `SHOW TABLES FROM <db>` の検証テスト追加
- [x] [`tests/database/test_show_statements.py`](../../../tests/database/test_show_statements.py): 仮想テーブルを含むスコープでの `SHOW TABLES FROM ...` テスト追加

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/234-unify-database-declarations-in-settings-and-reconcile-introspection`

1. **`src/settings.py` の新設**:
   - `BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))`
   - `DATABASES` 辞書定義:
     - `default`: In-Memory (`:memory:`)
     - `arxiv_security_db`: `okf_papers` (Virtual Markdown), `processed_papers` (Virtual JSON), `raw_papers` (Virtual Text)
     - `cti_catalog_db`: MultiTable VDB (`outputs/database/catalog/cti_catalog.vdb`)
     - `graph_db`: MultiTable VDB (`outputs/database/knowledge_graph.vdb`)
     - `analytics_db`: MultiTable VDB (`outputs/database/analytics/analytics.vdb`)
   - ヘルパー関数: `get_database_scopes()`, `get_table_scope_from_settings(tname)`, `get_table_type_from_settings(tname)` を提供。

2. **`src/cli/commands/dbshell.py` & `tables.py` の設定駆動化**:
   - `settings.py` から `DATABASES` をインポートし、ハードコード定義を置換。
   - `_mount_scope_tables`: `settings.DATABASES` の設定に基づいてテーブルを宣言的にマウント。

3. **`src/database/sql/executor.py` の `SHOW TABLES FROM <db>` 改善**:
   - `_resolve_show_table_rows`: 指定された `stmt.from_database` がある場合、まずマウント済みの `self.tables` から該当スコープのテーブルをフィルタリング。
   - `SHOW TABLES FROM arxiv_security_db;` が実行された際に `okf_papers`, `processed_papers`, `raw_papers` の実テーブル行が返るように改修。

4. **Web UI ゲートウェイの整合 (`src/web/gateway/handlers.py`)**:
   - ゲートウェイのテーブル台帳集計において、`dbshell` と同一の `SQLExecutor` / `settings.DATABASES` を活用し、実際の SQL イントロスペクション結果と完全一致させた。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `src/settings.py` が新設され、全データベースおよび仮想テーブルの仕様が宣言的に一元定義されていること。
- [x] `manage.py dbshell` で `SHOW TABLES FROM arxiv_security_db;` を実行した際、`okf_papers`, `processed_papers`, `raw_papers` が返却されること（0 rows にならないこと）。
- [x] `manage.py dbshell` の `.tables` と Web UI の表示内容が同じテーブル定義・メタデータに基づいていること。
- [x] `make check_format`、`make static_analysis` (xenon CC <= 5, mypy --strict) がエラー 0 件で通過すること。
- [x] 既存のテストおよび新規追加テストが 100% PASS すること。
