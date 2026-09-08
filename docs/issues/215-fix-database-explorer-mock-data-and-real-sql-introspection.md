---
ID: 215
種別: Bug
優先度: High
ステータス: Open (In Progress)
---

# [BUG/SEC] データベース台帳 UI (#/database) における架空テーブル・モック表示の撤廃と実コンテナ・実SQLインスペクションへの刷新 (ID: 215)

## 1. 概要 / Summary

エンタープライズ統合コンソールのデータベース探索画面 (`http://localhost:8000/index.html#/database`) において、`graph_db` などのデータベース情報が実態と乖離しており、すでに廃止された旧ストレージ構成や実在しない架空のモックテーブルが表示されている問題が判明した。

さらに、画面上に表示されている `SHOW TABLES FROM graph_db;` や `SHOW DATABASES;` は、実際にデータベースエンジンに対して SQL クエリを実行した結果ではなく、バックエンドハンドラー側でハードコードされた固定文字列およびダミー配列をそのまま返却している偽装（モック）状態となっている。

Issue #214 において `src/database` に単一 `.vdb` マルチテーブルコンテナ (`OKFMTC01`) および Pure-Python PEP 249 (`connect()`) ドライバーが実装されたことを受け、Web Gateway のデータベースインスペクション処理を刷新し、実コンテナから動的にテーブルメタデータを取得・真に SQL クエリを実行する完全実態連動型アーキテクチャへと是正する。

### 再現手順 / Steps to Reproduce
1. Web サーバーを起動 (`python3 src/web/server.py`) し、ブラウザで `http://localhost:8000/index.html#/database` にアクセスする。
2. データベースセレクターで「🕸️ graph_db」を選択する。
3. テーブル一覧に、実コンテナ (`knowledge_graph.vdb`) に存在しない `tbox_classes`, `tbox_properties`, `reified_claims`, `evidences` などの架空テーブルと固定行数 (33, 50 等) が表示される。
4. SQLターミナル領域に `SHOW TABLES FROM graph_db;` が表示されているが、実際には SQL パーサー / エグゼキュータを呼び出さず、Python 辞書の固定モック値が返されている。

### 再現環境 / Environment
- OS / Env: Linux (Antigravity IDE / Antigravity 2.0)
- File: `src/web/gateway/handlers.py`, `src/database/sql/executor.py`, `site/app.js`, `outputs/database/knowledge_graph.vdb`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/sql/executor.py](../../src/database/sql/executor.py) (`_exec_show` における `SHOW DATABASES` の動的解決および `SHOW TABLES FROM <db>` のコンテナ連携ディスパッチ)
- [ ] [src/database/sql/parser.py](../../src/database/sql/parser.py) (`SHOW TABLES FROM <db>` 構文パースの検証・強化)
- [ ] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (`_introspect_graph_database`, `_introspect_graph_table_metrics`, `_resolve_graph_file_size`, `_collect_database_tables`, `_run_sql_introspection`)
- [ ] [site/app.js](../../site/app.js) (`renderDatabaseTab` におけるクエリ実行結果描画)
- [ ] [tests/database/test_show_statements.py](../../tests/database/test_show_statements.py) (新規: `SHOW DATABASES` および `SHOW TABLES FROM <db>` の単体テスト)
- [ ] [tests/web/test_database_real_introspection.py](../../tests/web/test_database_real_introspection.py) (新規: Web Gateway の実コンテナ・実SQLインスペクションテスト)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **初期プロトタイプ時代のハードコード残存**:
   - `_introspect_graph_database()` 内で、オントロジーやナレッジグラフの将来構想（TBox / Claims / Evidences）を示すために作成された初期モックテーブル配列 (`tbox_classes`, `tbox_properties`, `reified_claims`, `evidences`) がそのまま残存していた。
   - 実際にはナレッジグラフ（ABox / TBox 含む）の実体はすべて `knowledge_graph.vdb` 内の `vertices` テーブル（ノード種別 label で分類）および `edges` テーブルに格納されている。
2. **廃止された旧ストレージ構成への依存**:
   - `_resolve_graph_file_size()` にて、Issue #214 で統合・廃止された旧 `vertices.vdb` / `edges.vdb` へのフォールバックが残存していた。
3. **SQL インスペクションの未実装・固定辞書返却**:
   - `_introspect_graph_database()`, `_introspect_analytics_database()`, `_introspect_cti_catalog_db()` において、SQL エグゼキュータを経由せず、辞書リテラルで `"query": "SHOW TABLES FROM graph_db;"` 等を固定定義してダミー配列を返していた。
   - `SQLExecutor` 側も `SHOW DATABASES` で固定の `[{"Database": "default_db"}, {"Database": "main"}]` を返しており、`SHOW TABLES FROM <db>` で他データベースのコンテナを参照する機能が未実装だった。
4. **テーブルの混在・重複登録**:
   - `_collect_database_tables()` において、`arxiv_security_db` のテーブル台帳に `graph_db` のテーブル（`vertices`, `edges`）がそのまま `tables.extend(g_tables)` されており、データベース間の境界が曖昧になっていた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**:
  - なし（実コンテナと実SQL実行に即時改修可能）。
* **恒久対策 (Permanent Fix)**:
  1. `_introspect_graph_database()` から実在しない架空テーブル（`tbox_classes` 等）のモック定義を完全削除し、実コンテナの `vertices` と `edges` のみを表示する。
  2. 廃止された旧 `vertices.vdb` / `edges.vdb` のコード・フォールバックを完全排除し、Issue #214 で標準化された `outputs/database/knowledge_graph.vdb` (`OKFMTC01`) の実コンテナを直接インスペクションする。
  3. `SQLExecutor` において、`SHOW DATABASES` で実在する登録DB（`arxiv_security_db`, `cti_catalog_db`, `analytics_db`, `graph_db`）を返却し、`SHOW TABLES FROM <database>` をサポートして対象データベースの実テーブルメタデータを動的返却可能にする。
  4. Web Gateway において、実際に `SQLExecutor` または PEP 249 `database.connect()` を呼び出して `SHOW TABLES FROM graph_db;` などのクエリを実行し、本物の実行ステータス、レイテンシ、テーブル一覧を UI に返却する。
  5. `_collect_database_tables()` を整理し、`arxiv_security_db` と `graph_db` のテーブル重複を解消する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/215-fix-database-explorer-mock-data-and-real-sql-introspection`

### Step 1: `src/database/sql/executor.py` のマルチDB & SHOW 文動的解決
1. `SQLExecutor` に `known_databases: Dict[str, str]`（DB名からファイルパスへのマッピング）を登録可能にする。
   - デフォルトで `arxiv_security_db`, `cti_catalog_db`, `analytics_db`, `graph_db` のパスを解決。
2. `_exec_show(stmt)` の実装：
   - `SHOW DATABASES`: `self.known_databases` または実在するDB一覧（`arxiv_security_db`, `cti_catalog_db`, `analytics_db`, `graph_db`）を動的構築して返却。
   - `SHOW TABLES [FROM <db>]`:
     - `stmt.from_database` が None の場合: 現在の `self.tables` を返却。
     - `stmt.from_database` が指定された場合:
       - 対象DBのファイルパスから `MultiTableVectorStorage` または `VectorStorage` をロード。
       - 含まれる実テーブル一覧、行数、サイズを `_build_show_table_row` 形式で動的生成して返却。

### Step 2: `src/web/gateway/handlers.py` のインスペクション刷新
1. `_resolve_graph_file_size()`:
   - 旧 `vertices.vdb`, `edges.vdb` のフォールバックコードを完全削除。
   - `outputs/database/knowledge_graph.vdb` の存在とファイルサイズのみを評価。
2. `_introspect_graph_database()`:
   - 架空のモックテーブル定義（`tbox_classes`, `tbox_properties`, `reified_claims`, `evidences`）を全撤去。
   - `knowledge_graph.vdb` の実コンテナから `vertices` と `edges` の正確な行数・バイトサイズを取得。
   - `SQLExecutor.execute("SHOW TABLES FROM graph_db;")` を実際に実行し、クエリ実行時間（ミリ秒）および本物の実行結果を `sql_introspection` に格納。
3. `_collect_database_tables()`:
   - `arxiv_security_db` のスコープを文書・ベクトル・FTSに限定（`paper_metadata`, `paper_vectors`, `fts_bm25_tokens`）。
   - `graph_db` のテーブル（`vertices`, `edges`）との混在・重複を解消。

### Step 3: 他データベース (`cti_catalog_db`, `analytics_db`) の実クエリ化
1. `_introspect_cti_catalog_db()` および `_introspect_analytics_database()`:
   - `SHOW TABLES FROM cti_catalog_db;`, `SHOW TABLES FROM analytics_db;` も `SQLExecutor` 経由で実クエリを実行し、動的インスペクションデータとしてバインド。

### Step 4: UI (`site/app.js`) の表示整合性確認
1. フロントエンドで `SHOW TABLES FROM <db>` の実クエリ結果およびテーブル台帳が崩れず正しくレンダリングされることを確認。

### Step 5: テスト作成 & 品質ゲート検証
1. `tests/database/test_show_statements.py`:
   - `SHOW DATABASES` の動的返却検証。
   - `SHOW TABLES FROM graph_db;` の実コンテナ連携テスト。
2. `tests/web/test_database_real_introspection.py`:
   - `/api/v1/database/metrics` のレスポンスにモックテーブル（`tbox_classes` 等）が含まれないことの検証。
   - `sql_introspection` のステータスが `ok` であり、実測レイテンシが記録されていることの検証。
3. `make check_format` および `make static_analysis` (CC <= 5 / Xenon Grade A) をパス。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `http://localhost:8000/index.html#/database` で表示されるデータベース一覧およびテーブル一覧が、ディスク上の実ファイルおよび `OKFMTC01` コンテナ実態と 100% 一致していること。
- [ ] `graph_db` において実在しない架空テーブル（`tbox_classes`, `tbox_properties`, `reified_claims`, `evidences`）が完全排除され、実在する `vertices`, `edges` の実データのみが表示されること。
- [ ] `SHOW TABLES FROM graph_db;`, `SHOW TABLES FROM arxiv_security_db;`, `SHOW DATABASES;` が実際に `SQLExecutor` / PEP 249 ドライバー経由で実行され、リアルな実行結果が返却されること（モックの排除）。
- [ ] 旧 `vertices.vdb`, `edges.vdb` へのフォールバックが完全撤廃されていること。
- [ ] `make check_format`, `make static_analysis` (Radon/Xenon CC <= 5) が 100% PASS すること。
