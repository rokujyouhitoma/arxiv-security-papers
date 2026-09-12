---
ID: 260
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT] SQLite 完全互換化 Phase 5: 高度な集合演算 & サブクエリ・ウィンドウ関数 (INTERSECT, EXCEPT, Subqueries, Window Functions) の実装 (ID: 260)

## 1. 概要 / Summary
[DSN-05-01] SQLite 完全互換化ロードマップの Phase 5 として、Pure Python SQL Engine (`src/database/sql/`) における高度なリレーショナル代数および OLAP 分析機能を実装する。
具体的には、結果セット間の共通部分を抽出する `INTERSECT`、差集合を算出する `EXCEPT`、条件式内で柔軟な集合判定や相関集計を可能にするサブクエリ（`IN (SELECT ...)`, `EXISTS (SELECT ...)`, スカラーサブクエリ）、および移動集計・順位付け・前後行参照を実現するウィンドウ関数（`OVER (PARTITION BY ... ORDER BY ...)`: `ROW_NUMBER`, `RANK`, `DENSE_RANK`, `NTILE`, `LAG`, `LEAD`, `FIRST_VALUE`, `LAST_VALUE`）をサポートする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様書: [[DSN-05-01] 6.5 Phase 5: 高度な集合演算 & サブクエリ](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md#65-phase-5-高度な集合演算--サブクエリolapリレーショナル代数)
- 準拠仕様: [SQLite Window Functions](https://sqlite.org/windowfunctions.html), [Compound SELECT](https://sqlite.org/syntax/select-stmt.html)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/sql/ast.py](../src/database/sql/ast.py): 集合演算型（`INTERSECT`, `EXCEPT`）、サブクエリノード、ウィンドウ関数定義（`WindowSpec`）追加
- [ ] [src/database/sql/parser.py](../src/database/sql/parser.py): `INTERSECT`, `EXCEPT`, ネストした SELECT サブクエリ、`OVER (...)` 句パース
- [ ] [src/database/sql/executor.py](../src/database/sql/executor.py): 集合演算エンジン、相関サブクエリ評価、パーティション順序付け & ウィンドウフレーム計算
- [ ] [tests/database/sql/test_sql_engine.py](../tests/database/sql/test_sql_engine.py): 集合演算、サブクエリ、ウィンドウ関数単体テスト
- [ ] [docs/issues/README.md](README.md): Issue 台帳の登録・追跡

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/260-implement-sqlite-parity-phase5-set-subquery-window-functions`

1. **AST 拡張 (`src/database/sql/ast.py`)**:
   - `SelectStatement` に `intersect: Optional[SelectStatement]`, `except_all: Optional[SelectStatement]`, `windows: Dict[str, WindowSpec]` を追加。
   - `WindowSpec`: `partition_by: List[str]`, `order_by: Optional[str]`, `order_desc: bool`, `frame: Optional[str]`。
2. **Parser 拡張 (`src/database/sql/parser.py`)**:
   - トップレベル結合演算子に `INTERSECT` / `EXCEPT` を追加。
   - `WHERE col IN (SELECT ...)` や `WHERE EXISTS (SELECT ...)` のサブ SELECT 抽出。
   - `func() OVER (PARTITION BY ... ORDER BY ...)` 構文の抽出。
3. **Executor 拡張 (`src/database/sql/executor.py`)**:
   - 集合演算: 左辺・右辺の結果行リストから重複のない積集合（INTERSECT）および差集合（EXCEPT）を計算。
   - サブクエリ評価: 外側クエリの行ごとに内側クエリを実行（またはハッシュ事前結合）。
   - ウィンドウ計算: `partition_by` で行をグルーピングし、各グループ内でソート後、順位（`RANK`, `DENSE_RANK`）や累積値を付与。
4. **セキュリティ & 品質規律**:
   - No-eval 原則遵守。Xenon CC Rank A ($\le 5$)、Mypy --strict 0 errors。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `SELECT id FROM tbl1 INTERSECT SELECT id FROM tbl2` が共通 ID のみを返却すること。
- [ ] `SELECT id FROM tbl1 EXCEPT SELECT id FROM tbl2` が差集合を正しく返却すること。
- [ ] `SELECT * FROM papers WHERE id IN (SELECT paper_id FROM authors WHERE author_name = 'Alice')` が正常動作すること。
- [ ] `SELECT id, category, ROW_NUMBER() OVER (PARTITION BY category ORDER BY score DESC) AS rank FROM papers` でグループ別連番が付与されること。
- [ ] `tests/database/sql/test_sql_engine.py` に単体テストを追加し、既存テストを含む全テストが PASS すること。
- [ ] `make format`, `make static_analysis` (xenon CC Rank A <= 5, mypy --strict) が 100% PASS すること。
