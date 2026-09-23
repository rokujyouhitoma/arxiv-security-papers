---
ID: 380
種別: Refactor
優先度: High
ステータス: Closed
---

# [REFACTOR] リレーショナルテーブルと VectorStorage / HNSW の密結合解消および書き込み増幅 (Write Amplification) の防止 (ID: 380)

## 1. 概要 / Summary

PyNYTProf のプロファイリングおよび定量ベンチマークにより、以下の重大な設計上の問題が判明した：
1. `TableCatalog.__init__` において、通常の純粋リレーショナルテーブル（例: `CREATE TABLE departments (...)`）であっても強制的に `HNSWIndex(dim=128)` が自動インスタンス化されている。
2. INSERT 時にリレーショナルデータに対してダミーのゼロベクトル埋め込み計算と HNSW 登録が毎回実行されている。
3. `SQLExecutor._persist_deleted_state` において、行削除（DELETE）が発生するたびに HNSW インデックス全体を破棄し、`build_from_storage(new_vecs)` によりゼロから全件再構築（Full Rebuild）している（`_exec_delete` で多大な時間を浪費する主因）。
4. `VectorStorage.append()` が差分追記ではなく、全レコードのデシリアライズ、メモリバッファ/一時ファイルへの全件再パック、JSON 再エンコード、およびファイル置換を行うため、$O(N^2)$ の書き込み増幅（Write Amplification）が発生している。

本 Issue では、テーブルカタログにおけるベクトルインデックスのオプショナル化（非ベクトルテーブルでは `self.index = None`）、リレーショナルテーブル挿入時の HNSW 回避、DELETE 時のフルリビルド抑止、およびストレージ追記処理の是正を実施した。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - `docs/designs/DSN-05-database_engine_architecture.md` (Relational vs Vector Catalog Design)
  - `outputs/profiling/html/index.html` (PyNYTProf プロファイル計測レポート)
  - `src/database/sql/executor.py` (`TableCatalog`, `_insert_vector_row`, `_prepare_insert_vector`, `_persist_deleted_state`, `_ensure_table_vector_index`)
  - `src/database/storage/storage.py` (`VectorStorage.append`, `append_batch`, `_append_memory_batch`, `_append_memory_single`, `_sync_memory_buffer`)
  - `scripts/benchmark_relational_crud.py` (定量ベンチマーク測定)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/database/sql/executor.py`](file:///workspace/arxiv-security-papers/src/database/sql/executor.py) (`TableCatalog.__init__`, `_resolve_table_index`, `_insert_vector_row`, `_persist_deleted_state`)
- [x] [`src/database/storage/storage.py`](file:///workspace/arxiv-security-papers/src/database/storage/storage.py) (`VectorStorage.append`, `append_batch`, メモリ書き込み増幅抑制)
- [x] [`scripts/benchmark_relational_crud.py`](file:///workspace/arxiv-security-papers/scripts/benchmark_relational_crud.py) (定量ベンチマーク測定)
- [x] [`tests/database/compatibility/test_us02_crud_and_dynamic_typing.py`](file:///workspace/arxiv-security-papers/tests/database/compatibility/test_us02_crud_and_dynamic_typing.py)
- [x] [`scripts/compare_sqlite3_differential.py`](file:///workspace/arxiv-security-papers/scripts/compare_sqlite3_differential.py)

---

## 4. 実装方針と計測結果 / Implementation & Benchmark Results

Target Branch: `refactor/380-decouple-hnsw-from-relational-tables`

### 4.1. 修正前 (Baseline) vs 修正後 (Optimized) 計測値 (500 rows, :memory:)

| 指標 (Metric) | Baseline (修正前) | Optimized (修正後) | 改善率 / 倍率 |
| :--- | :--- | :--- | :--- |
| **Insert 500件 所要時間** | 1.9348 s | **0.1517 s** | **12.75倍 高速化** (所要時間 92.2% 削減) |
| **Insert スループット** | 258.43 rows/s | **3,296.89 rows/s** | **+1175.7% 向上** |
| **Insert 平均レイテンシ** | 3.8695 ms/row | **0.3033 ms/row** | **92.2% 短縮** |
| **Delete 250件 所要時間** | 0.6496 s | **0.0037 s** | **175.5倍 高速化** (99.4% 短縮) |

### 4.2. コア最適化の成果
1. **`TableCatalog` の HNSW オプショナル化**:
   - `_resolve_table_index` により、非ベクトルテーブルでは `table.index = None` を実現。無駄な HNSWIndex インスタンス化を完全排除。
2. **`_insert_vector_row` におけるダミー計算バイパス**:
   - 非ベクトルテーブルへの INSERT 時、ゼロベクトル生成を高速化し、HNSW 登録をスキップ。
3. **`_persist_deleted_state` における HNSW フルリビルド廃止**:
   - 非ベクトルテーブルの DELETE 時、HNSW 再構築処理を完全にスキップ。Delete 所要時間が 0.65s から 0.0037s へ劇的に改善。
4. **`VectorStorage` メモリ追記の $O(1)$ 化**:
   - `_append_memory_batch` / `_append_memory_single` および `_memory_buffer_dirty` による遅延同期を導入。$O(N^2)$ の再シリアライズ書き込み増幅を完全に排除。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] 通常の SQL テーブル（非ベクトルテーブル）に対して HNSWIndex が自動生成されない（`table.index is None`）こと。
- [x] 非ベクトルテーブルへの INSERT / DELETE 時に HNSW 登録・再構築コードが一切実行されないこと。
- [x] 修正後ベンチマークにおいて、INSERT スループットおよび DELETE 実行速度が大幅に改善すること（定量的に記録）。
- [x] 既存の 75 ケースの SQLite 差分テストおよび CRUD テストが 100% PASS すること。
- [x] `make check_format` および `make static_analysis` の品質ゲートをすべて通過すること。
- [x] コード内に `# noqa: E402` などの警告抑制コメントを含めないこと。

