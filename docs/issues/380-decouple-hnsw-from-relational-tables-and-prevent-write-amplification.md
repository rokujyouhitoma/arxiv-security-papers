---
ID: 380
種別: Refactor
優先度: High
ステータス: Open (New)
---

# [REFACTOR] リレーショナルテーブルと VectorStorage / HNSW の密結合解消および書き込み増幅 (Write Amplification) の防止 (ID: 380)

## 1. 概要 / Summary

PyNYTProf のプロファイリングにより、以下の重大な設計上の問題が判明した：
1. `TableCatalog.__init__` において、通常の純粋リレーショナルテーブル（例: `CREATE TABLE departments (...)`）であっても強制的に `HNSWIndex(dim=128)` が自動インスタンス化されている。
2. INSERT 時にリレーショナルデータに対してダミーのゼロベクトル埋め込み計算と HNSW 登録が毎回実行されている。
3. `SQLExecutor._persist_deleted_state` において、行削除（DELETE）が発生するたびに HNSW インデックス全体を破棄し、`build_from_storage(new_vecs)` によりゼロから全件再構築（Full Rebuild）している（`_exec_delete` で 15.6 秒消費した主因）。
4. `VectorStorage.append()` が差分追記ではなく、全レコードのデシリアライズ、一時ファイルへの全件再パック、JSON 再エンコード、およびファイル置換を行うため、$O(N^2)$ の書き込み増幅（Write Amplification）が発生している。

本 Issue では、テーブルカタログにおけるベクトルインデックスのオプショナル化、リレーショナルテーブル挿入時の HNSW 回避、DELETE 時のフルリビルド抑止、およびストレージ追記処理の是正を実施する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - `docs/designs/DSN-05-database_engine_architecture.md` (Relational vs Vector Catalog Design)
  - `outputs/profiling/html/index.html` (PyNYTProf プロファイル計測レポート)
  - `src/database/sql/executor.py` (`TableCatalog`, `_insert_vector_row`, `_persist_deleted_state`)
  - `src/database/storage/storage.py` (`VectorStorage.append_batch`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/database/sql/executor.py`](file:///workspace/arxiv-security-papers/src/database/sql/executor.py) (`TableCatalog.__init__`, `_insert_or_upsert_row`, `_insert_vector_row`, `_persist_deleted_state`)
- [ ] [`src/database/storage/storage.py`](file:///workspace/arxiv-security-papers/src/database/storage/storage.py) (`VectorStorage.append`, `append_batch`)
- [ ] [`tests/database/compatibility/test_us02_crud_and_dynamic_typing.py`](file:///workspace/arxiv-security-papers/tests/database/compatibility/test_us02_crud_and_dynamic_typing.py)
- [ ] [`scripts/compare_sqlite3_differential.py`](file:///workspace/arxiv-security-papers/scripts/compare_sqlite3_differential.py)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/380-decouple-hnsw-from-relational-tables`

1. `TableCatalog.__init__` において、テーブルスキーマに `VECTOR` 型列または明示的なベクトル検索指定がない場合、`self.index = None` とする。
2. `_insert_or_upsert_row` において、ベクトル列を含まないテーブルではダミーベクトル計算および `table.index.add_item` をスキップする。
3. `_persist_deleted_state` において、HNSW インデックスが存在する場合のみ差分削除（Tombstone または HNSW ノード無効化）を適用し、インデックス全体の破棄・全件再構築を撤廃する。
4. `VectorStorage` の追記パスにおける全体ファイル再生成の改善またはリレーショナルデータの不要な VectorStorage 依存の緩和。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 通常の SQL テーブル（非ベクトルテーブル）に対して HNSWIndex が自動生成されないこと。
- [ ] 非ベクトルテーブルへの INSERT / DELETE 時に HNSW 登録・再構築コードが一切実行されないこと。
- [ ] DELETE 実行時のレイテンシが大幅に削減されること（PyNYTProf 計測で検証）。
- [ ] 既存の 75 ケースの SQLite 差分テストおよび CRUD テストが 100% 成功すること。
- [ ] `make check_format` および `make static_analysis` が PASS すること。
