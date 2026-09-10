---
ID: 233
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] dbshell における Active Database Scope 切替 (--database / .use) と仮想テーブル・ストレージ種別の識別明示化 (ID: 233)

## 1. 概要 / Summary

現在 `python3 manage.py dbshell` はデフォルトで仮想テーブル群（`okf_papers`, `processed_papers`, `raw_papers`）をマウントした単一統合セッションとして起動するが、Web UI で提供されている「Active Database Scope」（`arxiv_security_db`, `cti_catalog_db`, `analytics_db`, `graph_db`）の切り替えや各データベースの個別操作が直接行えない。
また、`.tables` や `manage.py tables` の出力において、どのテーブルがファイル連動仮想テーブル（Virtual Table: Markdown / JSON）であり、どれがバイナリ物理テーブル（Physical Table: MultiTable VDB）やインメモリテーブルであるかが一目で判別しにくい。

本 Issue では以下を実現する：
1. **Active Database Scope 切替**:
   - `python3 manage.py dbshell --database <name>`（または `-d <name>`）オプションによる特定データベーススコープ接続のサポート。
   - `dbshell` 内での `.databases` メタコマンドによるデータベース一覧表示、`.use <name>` メタコマンドおよび `USE <name>;` SQL 文による動的コンテキスト切替。
   - `cti_catalog_db`、`analytics_db`、`graph_db`（`MultiTableVectorStorage` コンテナ）内の実テーブル（`cti_techniques`, `cisa_kev`, `threat_trends`, `vertices`, `edges` 等）の透過的マウントとクエリ実行。
2. **テーブル種別・仮想テーブルの識別明示化**:
   - `.tables` および `manage.py tables` のテーブル一覧表示に `Table Type`（例: `Virtual (Markdown)`, `Virtual (JSON)`, `Physical (VDB)`, `In-Memory` 等）列を追加し、ストレージの性質を明確に区別。

---

## 2. トレーサビリティ / Traceability

- 設計書: `docs/designs/DSN-24-unified_management_cli_and_interactive_database_shell.md`
- 設計書: `docs/designs/DSN-05-database_engine_architecture.md` (Section 21 Multi-Storage & DDL)
- 関連Issue: Issue #195, Issue #214, Issue #218, Issue #230, Issue #231, Issue #232
- ガバナンス規約: `.agents/AGENTS.md` (6. Raw Data Preservation & Idempotency Rules)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/cli/commands/dbshell.py`](file:///workspace/arxiv-security-papers/src/cli/commands/dbshell.py): `--database` 引数、`.databases` / `.use` メタコマンド、および MultiTable VDB マウントの実装
- [x] [`src/cli/commands/tables.py`](file:///workspace/arxiv-security-papers/src/cli/commands/tables.py): テーブル一覧への `Table Type` (Virtual / Physical / Memory) の識別表示追加
- [x] [`src/database/sql/executor.py`](file:///workspace/arxiv-security-papers/src/database/sql/executor.py): `USE <database>` 構文および `TableCatalog` への `table_type` メタデータ保持
- [x] [`src/database/storage/factory.py`](file:///workspace/arxiv-security-papers/src/database/storage/factory.py): `MultiTableVectorStorage` 自動認識またはフラグ判定の整理
- [x] [`tests/cli/test_manage_dbshell.py`](file:///workspace/arxiv-security-papers/tests/cli/test_manage_dbshell.py): データベース切替およびテーブル種別表示の単体テスト追加

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/233-support-multi-database-switching-and-virtual-table-type-introspection`

1. **`StorageEngineFactory` の自動判別強化 (`src/database/storage/factory.py`)**:
   - `_create_binary_vdb`: 指定された `location` が存在し、先頭8バイトが `b"OKFMTC01"`（`SUPERBLOCK_MAGIC`）の場合は、単一テーブル `VectorStorage` ではなく `MultiTableVectorStorage(loc)` を自動返却または適切なエラー回避を実施。

2. **マルチデータベーススコープ定義とマウント基盤 (`src/cli/commands/dbshell.py`)**:
   - `DATABASE_SCOPES` 定義辞書を導入：
     - `all`: 全テーブルマウント
     - `arxiv_security_db`: `outputs/okf_papers` (Virtual Markdown), `outputs/raw_data` (Virtual Text), `papers_catalog.json` (Virtual JSON), `pipeline_state.jsonl` (Virtual JSONL)
     - `cti_catalog_db`: `outputs/database/catalog/cti_catalog.vdb` (Physical VDB: `cti_techniques`, `cisa_kev_vulnerabilities`, `cti_mitigations`, `cti_relationships`, `cti_tactics`)
     - `graph_db`: `outputs/database/knowledge_graph.vdb` (Physical VDB: `vertices`, `edges`)
     - `analytics_db`: `outputs/database/analytics/analytics.vdb` (Physical VDB: `threat_trends`, `strategic_kpis`, `metrics_history`, `latest_snapshot`)
   - `_mount_multitable_vdb(engine: SQLExecutor, file_path: str, db_scope: str)` ヘルパーを新設し、コンテナ内の全実テーブルを `SQLExecutor` に自動バインド（`_schemas` 内部管理テーブルは除外）。
   - テーブルカタログに `database_scope` および `table_type` メタデータを付与。

3. **テーブル種別判別ロジックの導入**:
   - ヘルパー関数 `_detect_table_type(catalog: TableCatalog) -> str` を新設：
     - `FileBackedPlainTextStorage` で patterns に `*.md` 含む -> `"Virtual (Markdown)"`
     - `FileBackedPlainTextStorage` で patterns に `*.txt` 含む -> `"Virtual (Text)"`
     - `JsonTableStorage` -> `"Virtual (JSON)"`
     - `JsonLinesStorage` -> `"Virtual (JSONL)"`
     - `VectorStorage` または `MultiTableVectorStorage` かつファイルパスあり -> `"Physical (VDB)"`
     - `VectorStorage` (メモリ) -> `"In-Memory"`

4. **CLI オプション & REPL メタコマンドの実装**:
   - `dbshell` および `tables` コマンドに `-d`, `--database` オプション（choices: `all`, `arxiv_security_db`, `cti_catalog_db`, `analytics_db`, `graph_db`, default: `all`）を追加。
   - `dbshell` REPL に `.databases` メタコマンド（利用可能スコープ一覧と現在のアクティブ表示）を追加。
   - `dbshell` REPL に `.use <scope>` メタコマンドおよび `USE <scope>;` SQL 文ハンドラを追加し、プロンプトに `arxiv-sec-db [cti_catalog_db]> ` のようにアクティブスコープを表示。
   - `.tables` および `manage.py tables` のヘッダーを `["Table Name", "Database Scope", "Table Type", "Storage Engine", "Row Count"]` に拡張。

5. **品質ゲートとテスト拡充**:
   - `tests/cli/test_manage_dbshell.py` に：
     - `--database <scope>` による起動時フィルタテスト
     - `.databases` および `.use` による動的コンテキスト切替テスト
     - `Table Type` (Virtual vs Physical vs In-Memory) の表示検証テスト
   - `make check_format`, `make static_analysis` (xenon Rank A, mypy --strict) 100% 準拠。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `python3 manage.py tables` で `Table Name`, `Database Scope`, `Table Type`, `Storage Engine`, `Row Count` が明瞭に表示されること。
- [ ] `okf_papers` / `raw_papers` が `Virtual (Markdown)` / `Virtual (Text)`、`processed_papers` が `Virtual (JSON)`、`cti_techniques` / `vertices` が `Physical (VDB)` として識別されること。
- [ ] `python3 manage.py dbshell -d cti_catalog_db` で CTI スコープのみを対象にして対話シェルやワンライナーが起動できること。
- [ ] `dbshell` 内で `.databases` を実行すると 4 大データベースと現在のアクティブスコープが表示されること。
- [ ] `dbshell` 内で `.use graph_db` または `USE graph_db;` を実行するとプロンプトとテーブルコンテキストが切り替わり、`SELECT COUNT(*) FROM vertices;` 等が実行できること。
- [ ] `make check_format` および `make static_analysis` (xenon Rank A, mypy --strict) がエラー 0 件で通過すること。
- [ ] 全単体テストが 100% PASS すること。
