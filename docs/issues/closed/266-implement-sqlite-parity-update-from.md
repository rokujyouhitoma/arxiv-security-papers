---
ID: 266
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/DATABASE] SQLite 完全互換化: UPDATE ... FROM (Join Update) 構文の実装 (ID: 266)

## 1. 概要 / Summary
SQLite 3.33.0+ 仕様 ([sqlite.org/lang_update.html](https://sqlite.org/lang_update.html)) に準拠した `UPDATE ... FROM` 構文を Pure Python SQL Engine (`src/database/sql/`) に実装する。
他テーブルと結合しながら対象テーブルの行を一括更新できるようにし、複雑な相関サブクエリなしでの複数テーブル連動更新を可能にする。

構文例:
```sql
UPDATE employees
SET salary = employees.salary * bonuses.multiplier
FROM bonuses
WHERE employees.department_id = bonuses.department_id;

UPDATE t1
SET val = t2.new_val
FROM t2
JOIN t3 ON t2.id = t3.t2_id
WHERE t1.id = t3.t1_id;
```

---

## 2. セキュリティ & アーキテクチャ脅威分析 (STRIDE / No-eval 原則)
- **入力サニタイズ / 権限検証**:
  - 更新対象テーブルには `UPDATE` 権限、`FROM` および `JOIN` 対象テーブルには `SELECT` 権限を個別に `AccessController.enforce_permission` で強制する。
- **No-eval 原則**:
  - `SET` 式や `ON` / `WHERE` 条件の評価において Python の `eval()` / `exec()` を一切使用せず、既存の AST 評価ルーチン `_extract_field_value` および `_matches_where_clause` を利用する。
- **循環的複雑度**:
  - Xenon Rank A ($\le 5$) を厳格順守するため、FROM句パース処理、結合行スキャン、代入評価ロジックを小関数に分離する。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [src/database/sql/ast.py](../../src/database/sql/ast.py):
  - `UpdateStatement` に `from_table: Optional[TableRef] = None`、`joins: List[JoinClause] = field(default_factory=list)`、および `raw_assignments: Dict[str, str] = field(default_factory=dict)` を追加
- [src/database/sql/parser.py](../../src/database/sql/parser.py):
  - `_parse_update`: `SET` 句の後に続く `FROM table_ref [JOIN ...]` を抽出し、`_parse_from_and_joins` を用いてパース
  - `_parse_set_assignments_raw`: 右辺を式文字列（raw_expr）および初期静的パース値の両方で保持するよう拡張
- [src/database/sql/executor.py](../../src/database/sql/executor.py):
  - `_exec_update`: `from_table` が指定されている場合、対象テーブルの各行に対して FROM / JOIN テーブル行を結合（プレフィックス付き結合コンテキスト生成）し、`WHERE` 条件に合致した結合レコードから `_extract_field_value` を評価して更新
  - 権限検証（更新対象への `UPDATE` + 参照テーブルへの `SELECT`）
- [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py):
  - `UPDATE ... FROM` の単体テスト・結合更新テスト・権限チェック・RETURNING 連携テストを追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/266-implement-sqlite-parity-update-from`

1. **AST 拡張 (`src/database/sql/ast.py`)**:
   - `UpdateStatement` に `from_table: Optional[TableRef] = None`, `joins: List[JoinClause] = field(default_factory=list)`, `raw_assignments: Dict[str, str] = field(default_factory=dict)` を定義。
2. **パーサー拡張 (`src/database/sql/parser.py`)**:
   - `_parse_update` において、`clean_sql, where_raw = self._extract_where_clause(clean_sql)` で WHERE 句を抽出。
   - `clean_sql` から `UPDATE <target> SET <assignments> [FROM <from_clause>]` の構造を検出。
   - `FROM` 句が存在する場合、`_parse_from_and_joins` を呼び出して `from_table` と `joins` を抽出。
   - assignments はキーと式のマッピング（`raw_assignments`）として抽出し、静的値パース結果とともに保持。
3. **エグゼキューター拡張 (`src/database/sql/executor.py`)**:
   - `stmt.from_table` が存在する場合：
     - `stmt.from_table.name` および全 `join.table.name` に対する `SELECT` 権限をチェック。
     - 対象テーブルの行と `from_table` / `joins` の行を結合（既存の `_query_knn_or_scan`, `_prefix_record`, `_match_join_row` を活用）。
     - 結合結果レコードのコンテキスト上で `stmt.where_clauses` を評価。
     - 一致した行に対し、`stmt.raw_assignments` の各式を `_extract_field_value(merged_record, expr)` で動的評価して代入。
     - BEFORE/AFTER トリガー発火、RETURNING 句のプロジェクションを適用。
4. **テスト & 品質検証**:
   - 単体テスト追加、`make format`, `make static_analysis` (xenon A, mypy strict) を PASS させる。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `UPDATE t1 SET c1 = t2.v FROM t2 WHERE t1.id = t2.id` が正しく実行され、値が更新されること。
- [x] `JOIN` を含む `UPDATE t1 SET val = t2.val FROM t2 JOIN t3 ON t2.id = t3.t2_id WHERE t1.id = t3.t1_id` が動作すること。
- [x] `UPDATE ... FROM` において `FROM` 側テーブルへの `SELECT` 権限がない場合に権限エラーとなること。
- [x] `RETURNING` 句およびトリガー発火との連携が正常に動作すること。
- [x] `tests/database/sql/test_sql_engine.py` に検証テストを追加し PASS すること。
- [x] `make format`, `make static_analysis` (Rank A, mypy --strict) が PASS すること。
