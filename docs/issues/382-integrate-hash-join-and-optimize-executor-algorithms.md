---
ID: 382
種別: Optimization
優先度: Medium
ステータス: Open (New)
---

# [OPT/ENH] SQLExecutor における Hash Join 統合および制約検査・式評価アルゴリズムの高速化 (ID: 382)

## 1. 概要 / Summary

PyNYTProf の計測結果から、クエリ実行エンジン（`SQLExecutor`）内部に以下のアルゴリズム的非効率性・ホットスポットが存在することが確認された：
1. **ナイーブな $O(N \times M)$ ネステッドループ結合**: `src/database/engine/volcano.py` に `HashJoinIterator` が実装されているにもかかわらず、`SQLExecutor._join_table_rows` は全件総当たりのネステッドループ結合（`_find_matching_join_rows`）を実行しており、テーブル行数が増加した際に計算量が爆発する。
2. **PRIMARY KEY / UNIQUE 制約検査のリニアスキャン**: `_check_column_uniqueness` がテーブル全行のメタデータを走査し、`str(existing_val) == str(new_val)` で文字列変換比較しているため、バルクインサート時に $O(N^2)$ の無駄な走査が発生している。
3. **比較演算における不要な型変換往復**: `_eval_relational` で `_eval_numeric_rel(op, float(str(actual)), float(str(expected)))` のように、行評価ごとに値を文字列化してから float 変換する二重変換オーバーヘッド。
4. **列値抽出前のリテラル判定先行**: `_extract_field_value` が辞書参照を行う前に、正規表現ベースのリテラル抽出（`_extract_literal`）や複合式判定を毎行・毎列で試行している。

本 Issue では、等価結合への Hash Join の統合、インデックスまたは集合型を用いた一意制約の $O(1)$ 検証、および型変換・列抽出パスの最適化を実施する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - `docs/designs/DSN-05-database_engine_architecture.md` (Volcano Execution Engine & Joins)
  - `outputs/profiling/html/index.html` (PyNYTProf プロファイル計測レポート)
  - `src/database/engine/volcano.py` (`HashJoinIterator`, `VolcanoIterator`)
  - `src/database/sql/executor.py` (`_join_table_rows`, `_check_column_uniqueness`, `_eval_relational`, `_extract_field_value`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/database/sql/executor.py`](file:///workspace/arxiv-security-papers/src/database/sql/executor.py) (`_join_table_rows`, `_check_column_uniqueness`, `_eval_relational`, `_extract_field_value`)
- [ ] [`src/database/engine/volcano.py`](file:///workspace/arxiv-security-papers/src/database/engine/volcano.py) (`HashJoinIterator`)
- [ ] [`tests/database/sql/test_multi_engine_join.py`](file:///workspace/arxiv-security-papers/tests/database/sql/test_multi_engine_join.py)
- [ ] [`tests/database/compatibility/test_us04_joins_subqueries_and_cte.py`](file:///workspace/arxiv-security-papers/tests/database/compatibility/test_us04_joins_subqueries_and_cte.py)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `opt/382-hash-join-and-executor-optimizations`

1. **Hash Join 統合**:
   - `ON left.col = right.col` の単純等価結合条件を検出し、ビルド側テーブルのハッシュマップ（`Dict[val, List[row]]`）を構築してプローブする Hash Join を適用。
2. **PRIMARY KEY / UNIQUE 制約の最適化**:
   - テーブルカタログに一意制約列の `Set`（または `BPlusTree`）を保持し、線形全件スキャンを排除して $O(1)$ で一意性をチェック。
3. **比較演算（`_eval_relational`）の高速化**:
   - 両オペランドが `int` / `float` の場合は直接数値比較を行い、文字列化（`str()`）や例外ハンドリングをバイパス。
4. **列値抽出（`_extract_field_value`）のショートサーキット**:
   - 式が単純な識別子（単語英数字・ドットのみ）かつレコードのキーに存在する場合は、即座に辞書参照を行ってリテラル正規表現評価をスキップ。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 等価結合（INNER JOIN / LEFT JOIN）において Hash Join がディスパッチされ、大規模結合のレイテンシが大幅に削減されること。
- [ ] 大量行の INSERT において UNIQUE 制約検査の計算量が $O(N)$ に抑えられること。
- [ ] WHERE 句評価における `str()` / `float()` 往復型変換が排除されていること。
- [ ] 既存のすべての JOIN、CTE、Subquery、UNIQUE 制約テストが 100% PASS すること。
- [ ] `make py_compile`, `make format`, `make static_analysis` が PASS すること。
