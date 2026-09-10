---
ID: 235
種別: Bug
優先度: High
ステータス: Closed (Completed)
---

# [BUG] dbshell の .schema におけるカラム定義省略 (...) の解消と _schemas 連携・スキーマ推論明記の実装 (ID: 235)

## 1. 概要 / Summary

`manage.py dbshell` において、`graph_db` やその他のマルチテーブルコンテナ（`.vdb`）にマウントされたテーブル（例: `edges`, `vertices`）に対し `.schema` メタコマンドを実行すると、カラム定義部分が `(...)` と省略されて出力される不具合が発生していた。

```sql
arxiv-sec-db [graph_db]> .schema edges
CREATE TABLE IF NOT EXISTS edges (
    ...
) USING binary_vdb LOCATION '/workspace/arxiv-security-papers/outputs/database/knowledge_graph.vdb';
CREATE INDEX idx_edges_vector ON edges (vector) USING HNSW;
```

### 再現手順 / Steps to Reproduce
1. `manage.py dbshell --database graph_db` を起動（または `.use graph_db` を実行）。
2. `.schema edges` または `.schema vertices` を実行。
3. `CREATE TABLE IF NOT EXISTS edges (...)` と出力され、実際のカラム（`id`, `src_id`, `dst_id`, `label`, `confidence`, `weight`, `properties` 等）が表示されない。

### 再現環境 / Environment
- OS / Env: Linux (Antigravity IDE)
- File: `src/cli/commands/dbshell.py`, `src/database/sql/executor.py`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/cli/commands/dbshell.py`](file:///workspace/arxiv-security-papers/src/cli/commands/dbshell.py):
  - `_mount_single_container_table` における固定 `(...)` の撤廃。
  - `_resolve_container_table_ddl` による `_schemas` テーブルルックアップとメタデータからの型推論機能の実装。
  - 推論されたスキーマに対する `-- Inferred from storage metadata` 注記コメントの付与。
- [x] [`tests/cli/test_manage_dbshell.py`](file:///workspace/arxiv-security-papers/tests/cli/test_manage_dbshell.py):
  - `.schema edges` や `cti_catalog_db` テーブル群で実際のカラム定義・型が出力され、かつ推論スキーマに `-- Inferred from storage metadata` 注記が付与されていることの検証テスト追加。

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

1. **`raw_sql` への `(...)` 文字列ハードコード**:
   - `src/cli/commands/dbshell.py:131` の `_mount_single_container_table` 関数において、コンテナ内テーブルをマウントする際、`raw_sql=f"CREATE TABLE IF NOT EXISTS {tname} (...) USING binary_vdb LOCATION '{file_path}'"` とリテラルで `(...)` が設定されていた。
2. **`TableCatalog.get_ddl()` の優先順位**:
   - `TableCatalog.get_ddl()` は `self.raw_sql` が存在する場合、その文字列を最優先で整形（`prettify_ddl`）して返却する。
   - その結果、`self.schema` に型定義が存在していても無視され、`raw_sql` 中の `...` がそのまま画面に出力されていた。
3. **`_schemas` テーブルおよびメタデータ推論の未活用**:
   - `cti_catalog.vdb` や `analytics.vdb` には `_schemas` テーブルとして保存された正式な `CREATE TABLE` DDL が存在するが、マウント時に読み取られていなかった。
   - `knowledge_graph.vdb` のように `_schemas` テーブルを持たないコンテナでも、`storage.metadata` にキー（例: `src_id`, `dst_id`, `label` 等）が存在するにもかかわらず、スキーマ推論を行っていなかった。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix

* **暫定対処 (Workaround)**: なし（`.schema` 出力時の文字列生成処理を変更する必要があるため）。
* **恒久対策 (Permanent Fix)**:
  1. **`_schemas` テーブルからの DDL 復元**:
     - コンテナ内に `_schemas` テーブルが存在する場合、保存されている正確な `CREATE TABLE` DDL を読み出して `catalog.raw_sql` に設定した。
  2. **メタデータからのスキーマ動的推論と推論であることの明記**:
     - `_schemas` が存在しないテーブル（例: `edges`, `vertices`）の場合、`storage.metadata[0]` のキーおよび値の Python 型からカラム名と SQL データ型（`VARCHAR`, `FLOAT`, `JSON` 等）を自動推論した。
     - **ユーザー要求事項**: 推論された DDL であることが一目で分かるよう、DDL 出力時（先頭行）に `-- Inferred from storage metadata` 注記を明記した。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `fix/235-resolve-dbshell-schema-ellipsis-and-support-inferred-ddl`

1. **`src/cli/commands/dbshell.py` の改修**:
   - `_lookup_container_schema_sql` ヘルパー関数を新設し、コンテナ内 `_schemas` から正式な DDL を検索。
   - `_infer_table_schema` および `_infer_value_sql_type` を新設し、メタデータ第1行から各カラムの型（`VARCHAR(64)`, `FLOAT`, `JSON` 等）を推論。
   - 推論スキーマの場合は先頭に `-- Inferred from storage metadata` を付与。
   - `_mount_single_container_table` で上記を組み合わせ、正確な DDL とスキーマを TableCatalog に設定。
2. **品質・複雑度ゲート遵守**:
   - Xenon CC <= 5 (Rank A) を厳格に遵守。
   - `mypy --strict` エラー 0 件を維持。
3. **テストの追加と検証**:
   - `tests/cli/test_manage_dbshell.py` に `test_dbshell_schema_no_ellipsis_and_inferred_notice` を追加。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `manage.py dbshell` で `.schema edges` や `.schema vertices` を実行した際、`...` で省略されず、実カラム（`id`, `src_id`, `dst_id`, `label` 等）が型付きでインデント表示されること。
- [x] スキーマが推論されたテーブルの DDL 出力には、推論によるものであること（`-- Inferred from storage metadata`）が明記されていること。
- [x] `_schemas` テーブルを持つコンテナ（`cti_catalog_db` 等）では、保存されている正式な DDL が正確に出力されること。
- [x] `make check_format`、`make static_analysis`（xenon CC <= 5, mypy --strict）が 100% PASS すること。
- [x] 全テスト（`make test`）が 100% PASS すること。
