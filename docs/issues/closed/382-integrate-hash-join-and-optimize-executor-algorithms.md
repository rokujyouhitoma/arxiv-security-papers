---
ID: 382
種別: Optimization
優先度: Medium
ステータス: Closed
---

# [OPT/ENH] SQLExecutor における Hash Join 統合および制約検査・式評価アルゴリズムの高速化 (ID: 382)

## 1. 概要 / Summary

PyNYTProf の計測結果から、クエリ実行エンジン（`SQLExecutor`）内部に以下のアルゴリズム的非効率性・ホットスポットが存在することが確認された：
1. **ナイーブな $O(N \times M)$ ネステッドループ結合**: `SQLExecutor._join_table_rows` は全件総当たりのネステッドループ結合（`_find_matching_join_rows`）を実行しており、テーブル行数が増加した際に計算量が $O(N \times M)$ に爆発する（1000件 x 500件の JOIN だけで 1 回あたり **1.35秒〜1.40秒** を消費）。
2. **PRIMARY KEY / UNIQUE 制約検査のリニアスキャン**: `_check_column_uniqueness` がテーブル全行のメタデータを走査し、`str(existing_val) == str(new_val)` で文字列変換比較しているため、バルクインサート時に $O(N^2)$ の無駄な走査が発生している。
3. **比較演算における不要な型変換往復**: `_eval_relational` で `_eval_numeric_rel(op, float(str(actual)), float(str(expected)))` のように、行評価ごとに値を文字列化してから float 変換する二重変換オーバーヘッド。
4. **列値抽出前のリテラル判定先行**: `_extract_field_value` が辞書参照を行う前に、正規表現ベースのリテラル抽出（`_extract_literal`）や複合式判定を毎行・毎列で試行している。

本 Issue では、等価結合への Hash Join の統合（$O(N + M)$ 化）、テーブルカタログでのインデックス/集合型キャッシュを用いた一意制約の $O(1)$ 検証、および型変換・比較演算パスの最適化を実施した。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - `docs/designs/DSN-05-database_engine_architecture.md` (Volcano Execution Engine & Joins)
  - `outputs/profiling/html/index.html` (PyNYTProf プロファイル計測レポート)
  - `src/database/engine/volcano.py` (`HashJoinIterator`, `VolcanoIterator`)
  - `src/database/sql/executor.py` (`_join_table_rows`, `_check_column_uniqueness`, `_eval_relational`, `_extract_field_value`)
  - `scripts/benchmark_executor_ops.py` (定量ベンチマーク測定スクリプト)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/database/sql/executor.py`](file:///workspace/arxiv-security-papers/src/database/sql/executor.py) (`_join_table_rows`, `_check_column_uniqueness`, `_eval_relational`, `_extract_field_value`)
- [x] [`scripts/benchmark_executor_ops.py`](file:///workspace/arxiv-security-papers/scripts/benchmark_executor_ops.py) (ベンチマークスクリプト)
- [x] [`tests/database/sql/test_multi_engine_join.py`](file:///workspace/arxiv-security-papers/tests/database/sql/test_multi_engine_join.py)
- [x] [`tests/database/test_pep249_interface.py`](file:///workspace/arxiv-security-papers/tests/database/test_pep249_interface.py)
- [x] [`scripts/compare_sqlite3_differential.py`](file:///workspace/arxiv-security-papers/scripts/compare_sqlite3_differential.py)

---

## 4. 実装方針と計測値 / Implementation Plan & Benchmark Results

Target Branch: `opt/382-hash-join-and-executor-optimizations`

### 4.1. 修正前・修正後の性能比較 (1000 orders x 500 customers, 1500 unique rows)

| 測定項目 | 修正前 (Baseline) | 修正後 (Optimized) | 改善率 / 倍率 |
| :--- | :--- | :--- | :--- |
| **INNER JOIN (1000 x 500)** | 1.3491 秒 (0.74 qps) | **0.0079 秒 (125.92 qps)** | **約 170.8 倍 高速化 (99.4% 短縮)** |
| **LEFT JOIN (1000 x 500)** | 1.4026 秒 (0.71 qps) | **0.0076 秒 (131.05 qps)** | **約 184.6 倍 高速化 (99.5% 短縮)** |
| **UNIQUE INSERT (1500 rows)** | 0.3431 秒 (4,372.1 rows/s) | **0.0239 秒 (62,774.9 rows/s)** | **約 14.3 倍 高速化 (93.0% 短縮)** |
| **REL FILTER (1500 rows)** | 0.0069 秒 (144.24 qps) | **0.0067 秒 (148.43 qps)** | 高速維持・微増 |

### 4.2. 詳細実装内容

1. **Hash Join の統合 ([`executor.py`](file:///workspace/arxiv-security-papers/src/database/sql/executor.py))**:
   - `_find_equi_join_keys` により、JOIN の ON 条件から等価結合キーのペア（ビルド側・プローブ側）と残余条件を抽出。
   - `_is_hash_joinable` 条件（INNER / LEFT JOIN、行が存在し等価キーが存在）を満たす場合、`_try_hash_join` -> `_execute_hash_join` を実行。
   - ビルド側（右テーブルの結合プレフィックス行）を `_build_hash_bucket` でハッシュバケット（`defaultdict(list)`）化。
   - プローブ側（左行）を走査して `_probe_hash_bucket_row` で $O(1)$ バケット参照し、残余条件を判定。
   - 等価結合キーがない場合や OR 条件を含む複雑な結合条件は、安全に既存のネステッドループ（`_nested_loop_join`）へフォールバック。
2. **PRIMARY KEY / UNIQUE 制約のインデックス化・$O(1)$ 化 ([`executor.py`](file:///workspace/arxiv-security-papers/src/database/sql/executor.py))**:
   - `TableCatalog` に `unique_val_sets: Dict[str, Set[str]]` を保持させ、`get_unique_set()` で既存行から遅延初期化。
   - `_check_column_uniqueness` において $O(N)$ 線形走査を廃止し、`val_str in unique_set` の $O(1)$ 判定へ刷新。
   - `_apply_insert_loop` での挿入成功時に `table.record_inserted_unique_values(col, val_str)` で即時セットに追加。
   - UPDATE / DELETE / DROP / ROLLBACK 時に `invalidate_unique_sets()` でキャッシュ整合性を担保。
3. **比較演算（`_eval_relational`）の高速化 ([`executor.py`](file:///workspace/arxiv-security-papers/src/database/sql/executor.py))**:
   - `isinstance(actual, (int, float))` かつ `isinstance(expected, (int, float))`（かつ `bool` 除外）の場合、`str()` 変換と `float()` 変換を経由せず直接 `_eval_numeric_fast` を実行。
   - `isinstance(actual, str)` かつ `isinstance(expected, str)` の場合、直接文字列比較を実行。
   - 型の不一致や変換が必要な場合のみ `_eval_relational_fallback` へ移行。
4. **Xenon ランク A (CC <= 5) & Strict Quality Gates の遵守**:
   - 各ヘルパー関数の循環的複雑度を 5 以下（ランク A）に抑え、`make format`, `make check_format`, `make static_analysis` (xenon A, mypy strict, flake8) を 100% パス。
   - `# noqa: E402` などの警告抑制コメントは一切使用せず厳格遵守。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] 等価結合（INNER JOIN / LEFT JOIN）において Hash Join が動作し、所要時間がベースライン（1.35s〜1.40s）から大幅短縮（目標: 0.1s 未満、10倍以上高速化 -> **実測: 170〜184倍高速化**）すること。
- [x] 大量行の INSERT において UNIQUE 制約検査が高速化（$O(1)$ ルックアップ -> **実測: 14.3倍高速化**）されること。
- [x] WHERE 句評価における不要な `str()` / `float()` 往復型変換が排除され、数値・文字列比較が高速化すること。
- [x] 既存のすべてのテスト（446件）および SQLite 差分テスト（75ケース）が 100% PASS すること。
- [x] `make py_compile`, `make format`, `make check_format`, `make static_analysis` がすべて PASS すること。
- [x] コード内に `# noqa: E402` などの警告抑制コメントを含めないこと。


