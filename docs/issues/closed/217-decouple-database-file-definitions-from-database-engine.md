---
ID: 217
種別: Refactor
優先度: High
ステータス: Closed
---

# [REFACTOR/ARCH] src/database からの具体的データベース指定・ファイルパス結合の完全排除と利用側一元定義（DI）の確立 (ID: 217)

## 1. 概要 / Summary

Clean Architecture および責務分離（Separation of Concerns: SoC）、依存性逆転の原則（Dependency Inversion Principle: DIP）に基づき、`src/database` はドメイン知識を持たない汎用独立データベースライブラリ（Pure-Python B-Tree, WAL, Pager, SQL Parser/Executor, PEP 249 Driver）として設計されなければならない。

従来のコードベースでは、初期プロトタイプ開発時の経緯から、`src/database/` の内部に特定のアプリケーションドメイン依存（例: テーブル名 `"papers"` の固定値、特定スキーマ定義の暗黙生成など）が一部残存していた。

具体的には：
1. `src/database/sql/executor.py` の `_init_default_tables` において、`default_storage` 受領時にテーブル名が `"papers"` に固定されている。
2. `src/database/compat/sqlite_engine.py` において、`_init_papers_schema` がハードコードされており、`get_sqlite_connection` の `init_schema=True` 呼び出し時にドメイン固有の `papers` テーブル定義が強制生成される。
3. `src/database/compat/sqlite_bridge.py` の同期関数群において、デフォルト引数として `"papers"` がハードコードされている。

`src/database` 内に利用する各データベースファイル（例: `papers.vdb`, `knowledge_graph.vdb`, `analytics.vdb` 等）や具体的配置パス（例: `outputs/database/...`）、ドメインテーブル名（`papers`）を指定・固定してはならない。これらは `src/database` を利用する側のコード（`src/web/gateway/`, `src/pipeline/`, `src/analytics/`, CLI 等）において定義・解決し、`src/database` には依存性注入（Dependency Injection: DI）として渡すことが求められる。

本 Issue では、`src/database` 内に残存するいかなるドメインDB指定・固定スキーマも完全に排除・抽象化し、利用側におけるデータベースファイル一覧の一元定義（`_resolve_application_databases` 等）および DI インターフェースを確立・標準化する。

---

## 2. トレーサビリティ / Traceability

- **関連設計書**:
  - [docs/designs/DSN-05-database_engine_architecture.md](../designs/DSN-05-database_engine_architecture.md) (次世代データベースエンジン包括的アーキテクチャ設計書)
- **関連 Issue**:
  - [docs/issues/closed/212-support-in-memory-database-mode.md](closed/212-support-in-memory-database-mode.md) (インメモリ `:memory:` モードの完全サポート)
  - [docs/issues/closed/214-implement-single-vdb-multi-table-container.md](closed/214-implement-single-vdb-multi-table-container.md) (単一 `.vdb` マルチテーブルコンテナ OKFMTC01 実装)
  - [docs/issues/215-fix-database-explorer-mock-data-and-real-sql-introspection.md](215-fix-database-explorer-mock-data-and-real-sql-introspection.md) (データベース台帳の実SQLインスペクション刷新)
  - [docs/issues/216-eliminate-mock-implementations-and-bind-real-runtime-data.md](216-eliminate-mock-implementations-and-bind-real-runtime-data.md) (実ランタイムデータバインド)
- **準拠規約**:
  - Clean Architecture / DIP (Dependency Inversion Principle)
  - PEP 249 (Python Database API Specification v2.0)
  - CWE-22 (Path Traversal 防止), CWE-89 (SQL / Identifier Injection 防止)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/database/sql/executor.py](../../src/database/sql/executor.py) (`SQLExecutor` からの `"papers"` 固定テーブル名の排除、`default_table_name` パラメータ追加、`known_databases` DI の完全分離と識別子検証)
- [x] [src/database/compat/sqlite_engine.py](../../src/database/compat/sqlite_engine.py) (`_init_papers_schema` の汎用化・外部注入化 `_init_default_table_schema`、`schema_sql` / `table_name` DI パラメータの追加、`sync_to_vector_storage` / `sync_from_vector_storage` の汎用化)
- [x] [src/database/compat/sqlite_bridge.py](../../src/database/compat/sqlite_bridge.py) (`sync_sqlite_to_vector_storage` におけるデフォルトテーブル名の DI パラメータ化)
- [x] [src/database/cow/engine.py](../../src/database/cow/engine.py) (`CoWEngine` のパス完全 DI・ドメイン中立性の検査と型アノテーション担保)
- [x] [src/database/ipc/client.py](../../src/database/ipc/client.py) (`DatabaseClient` の `storage_path` / `socket_path` の利用側明示指定とインメモリ安全性の確認)
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (利用側での `_resolve_application_databases(workspace_dir)` 一元定義の確立と `SQLExecutor(known_databases=...)` への透過的注入)
- [x] [docs/designs/DSN-05-database_engine_architecture.md](../designs/DSN-05-database_engine_architecture.md) (第20章「データベースエンジンと利用側の責務分離およびファイルパス DI ガイドライン」の新設)
- [x] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py) (DI パラメータ `default_table_name="papers"` またはカタログ明示登録への追従)
- [x] [tests/database/test_database_100_percent_coverage.py](../../tests/database/test_database_100_percent_coverage.py) (DI 化された `get_sqlite_connection` のスキーマ注入・テーブル名指定テスト拡充)

---

## 4. 現状分析とアーキテクチャ課題 (As-Is vs To-Be)

| 評価項目 | 現状 (As-Is) | あるべき姿 (To-Be) | 改善の技術的効果 |
| :--- | :--- | :--- | :--- |
| **SQLExecutor デフォルトテーブル** | `_init_default_tables` 内で `table_name = "papers"` が直書きされており、論文ドメイン以外の汎用DBとして再利用できない。 | `default_table_name: Optional[str] = None`（未指定時は `"main"` または `"records"`）を引数化。呼び出し元がドメイン名を注入する。 | 汎用 SQL エンジンとしての完全なポータビリティを確立。 |
| **SQLite 互換エンジン初期化** | `_init_papers_schema` がハードコードされており、`init_schema=True` で常に `papers` テーブルが強制生成される。 | `schema_sql: Optional[str] = None`, `table_name: str = "records"` を引数化。カスタム DDL を注入可能にする。 | グラフDB・CTI・メトリクス等の異種スキーマ接続時に不要なテーブルが作成されない。 |
| **マルチDB探索 (`known_databases`)** | `SQLExecutor` は `known_databases` を受け取れるが、ドキュメントや規約が未定義で利用側の責務境界が曖昧。 | 利用側（`src/web/gateway/handlers.py`）に `_resolve_application_databases` を一元配置し、DI 引数としてのみ渡す規約を確立。 | レイヤー分離の徹底。`src/database` は呼び出し元から与えられたマッピングのみを忠実に処理する。 |
| **パス・識別子セキュリティ** | 外部注入される DB 名やパスに対するホワイトリスト/境界チェックの体系的規約が未整理。 | DB 名の SQL 識別子正規表現チェック (`^[a-zA-Z_][a-zA-Z0-9_]*$`) および Magic Bytes 検証、ワークスペース境界チェックの徹底。 | CWE-22 (Path Traversal), CWE-89 (SQL/Identifier Injection) の根本遮断。 |

---

## 5. 脅威分析とセキュリティ要件 (STRIDE Threat Model & Mitigations)

外部からデータベースパスおよび名前が注入される（DI）構造への移行に伴い、以下の脅威モデルを策定し防御策を実装する。

| 脅威分類 (STRIDE) | 潜在リスク (Threat Vector) | CWE | 対策仕様 (Mitigation Specification) |
| :--- | :--- | :--- | :--- |
| **Tampering / Information Disclosure** | 不正な外部パス注入によるパストラバーサル・システム重要ファイル読み出し | CWE-22 | `_load_external_db_tables` において、ファイル実体ヘッダの Magic Bytes（`OKFMTC01` または VectorStorage フォーマット）検証を行い、非DBバイナリ・テキストファイル（`/etc/passwd` 等）を即時遮断する。また、ワークスペース外パスへのアクセスを制限。 |
| **Tampering / Injection** | `SHOW TABLES FROM <db>` における悪意あるデータベース名注入による SQL パーサー誤動作・インジェクション | CWE-89 | 注入されるデータベース名 `db_name` に対し、英数字およびアンダースコアのみを許容する厳格な正規表現バリデーション（`^[a-zA-Z_][a-zA-Z0-9_]*$`）を実施。 |
| **Denial of Service (DoS)** | 悪意のある大量の外部 DB パス登録や巨大ファイル指定によるリソース枯渇 | CWE-400 | `known_databases` の登録可能上限数（例: 最大 64 個）を設け、実ファイルのインスペクションはオンデマンド（遅延実行）かつタイムアウト制約下で実行。 |
| **Elevation of Privilege** | 読み取り専用コンテキストでの未認可 DDL/DML 実行 | CWE-285 | `SQLExecutor` の `role` に基づく RBAC アクセスコントロール（`viewer` ロールでの更新抑止）を全外部 DB 参照時にも透過適用。 |

---

## 6. 実装方針 / Implementation Plan

Target Branch: `refactor/217-decouple-database-file-definitions-from-database-engine`

### Step 1: `src/database/sql/executor.py` のテーブル名 DI 化と識別子保護
1. `SQLExecutor.__init__` に `default_table_name: Optional[str] = None` パラメータを追加。
2. `_init_default_tables` を改修：
   ```python
   def _init_default_tables(
       self,
       catalog: Optional[TableCatalog],
       default_storage: Optional[VectorStorage],
       default_index: Optional[HNSWIndex],
       default_table_name: Optional[str] = None,
   ) -> None:
       if catalog is not None:
           self.tables[catalog.name] = catalog
       elif default_storage:
           tbl_name = default_table_name or "main"
           self.tables[tbl_name] = TableCatalog(
               name=tbl_name,
               storage=default_storage,
               index=default_index or HNSWIndex(dim=default_storage.dim),
           )
   ```
3. `register_database(name: str, path: str)` において、`name` の SQL 識別子バリデーション（`re.match(r"^[a-zA-Z_][a-zA-Z0-9_]*$", name)`）を実施。

### Step 2: `src/database/compat/sqlite_engine.py` & `sqlite_bridge.py` の汎用化
1. `_init_papers_schema` を `_init_default_table_schema` にリファクタリング。
   - `schema_sql: Optional[str] = None` が渡された場合はその DDL を実行。
   - 未指定時は汎用的なベクトル格納スキーマ（デフォルトテーブル名 `table_name: str = "items"` または引数指定）を作成。
2. `get_sqlite_connection` のシグネチャを拡張：
   ```python
   def get_sqlite_connection(
       db_path: str = ":memory:",
       storage: Optional[VectorStorage] = None,
       init_schema: bool = True,
       read_only: bool = False,
       enable_wal: bool = False,
       timeout: float = 5.0,
       table_name: str = "records",
       schema_sql: Optional[str] = None,
   ) -> sqlite3.Connection:
   ```
3. `sync_to_vector_storage` および `sync_from_vector_storage` のデフォルト引数を汎用化、`sqlite_bridge.py` も同様に追従。

### Step 3: `src/web/gateway/handlers.py` での一元定義（DI ソース）確認
1. `_resolve_application_databases(workspace_dir: str) -> Dict[str, str]` が Web Gateway における唯一の DB 定義元であることを確認。
2. `SQLExecutor(known_databases=app_dbs)` への注入が漏れなく行われていることを静的検証。

### Step 4: 設計ドキュメント `docs/designs/DSN-05-database_engine_architecture.md` の改訂
1. 第20章「データベースエンジンと利用側の責務分離およびファイルパス DI（Dependency Injection）ガイドライン」を新設。
2. レイヤー構成図（Mermaid）を追加：
   - 上位レイヤー（Web Gateway / Pipeline / Analytics）: ドメイン DB パス・スキーマ定義・DI ソース
   - 下位レイヤー（`src/database/`）: 純粋エンジン・抽象化インターフェース・DI シンク
3. STRIDE セキュリティ要件と識別子バリデーション規則を明文化。

### Step 5: テストコードの改修と網羅的検証
1. `tests/database/sql/test_sql_engine.py`: `default_table_name="papers"` を明示注入するか、汎用テーブル名でのクエリに整合させる。
2. `tests/database/test_database_100_percent_coverage.py`: `get_sqlite_connection` のカスタム `schema_sql` および `table_name` DI 機能の単体テストを追加。
3. `tests/database/test_show_statements.py`: 不正な DB 識別子の拒絶テスト、Magic Bytes 不正ファイルの安全なスキップテストを追加。

### Step 6: 品質ゲート実行
1. `make check_format` によるフォーマット検証。
2. `make static_analysis` (flake8, radon CC A, xenon Grade A, mypy strict) を実行し 0 errors を達成。
3. `make test` を実行し全テスト PASS を確認。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] **ドメインパス・テーブル名固定の完全排除**:
  - `src/database/` 直下および配下の全ソースコードに、`outputs/database/` や特定の `.vdb` ファイルパスの直書きが 0 件であること。
  - `src/database/sql/` および `src/database/compat/` 内で特定の `"papers"` 文字列がハードコードされず、すべて呼び出し側からの DI 引数（または `"main"` / `"records"` 汎用デフォルト）として処理されていること。
- [x] **セキュリティバリデーション (CWE-22 / CWE-89 / CWE-400)**:
  - 外部注入される DB 名に対する SQL 識別子正規表現チェックが実装され、単体テストで検証されていること。
  - 外部 DB インスペクション時の Magic Bytes チェックにより、非DBファイルの誤読・漏洩が防止されていること。
- [x] **利用側一元定義の徹底**:
  - `src/web/gateway/handlers.py` の `_resolve_application_databases` が一元的に機能し、DI パターンで `SQLExecutor` に渡されていること。
- [x] **設計書への明文化**:
  - [docs/designs/DSN-05-database_engine_architecture.md](../designs/DSN-05-database_engine_architecture.md) に第20章（責務分離と DI ガイドライン、Mermaid 図、STRIDE 対策）が追記されていること。
- [x] **品質ゲート 100% PASS**:
  - `make check_format` が警告なく PASS すること。
  - `make static_analysis` (radon 複雑度 A, xenon Rank A, mypy strict, flake8) が 100% PASS すること。
  - 全ユニットテスト（`make test`）が 100% PASS すること。
- [x] **相対リンク遵守**:
  - 全 Markdown ドキュメント内の内部リンクが相対パス（`file:///` や絶対パス不使用）で統一されていること。
