---
ID: 257
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] SQLite 完全互換化 Phase 2: DML 拡張 & 競合制御 (複数行 INSERT, INSERT SELECT, UPSERT, RETURNING) の実装 (ID: 257)

## 1. 概要 / Summary
[DSN-05-01] SQLite 完全互換化ロードマップの Phase 2 として、Pure Python SQL Engine (`src/database/sql/`) におけるデータ更新・挿入・競合制御機能を大幅に拡充する。
具体的には、バッチデータ投入を高速化する複数行 `INSERT INTO ... VALUES (...), (...)`、他テーブルや集計結果を直結する `INSERT INTO ... SELECT ...`、一意制約競合時の自律リカバリを実現する `ON CONFLICT(...) DO UPDATE / DO NOTHING` (UPSERT) および `REPLACE INTO`、変更結果行を直ちに取得できる `RETURNING` 句、および影響行数を制限する `DELETE / UPDATE ... ORDER BY ... LIMIT ...` を実装する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様書: [[DSN-05-01] 6.2 Phase 2: DML 拡張 & 競合制御](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md#62-phase-2-dml-拡張--競合制御一括挿入upsert変更行返却)
- 準拠仕様: [SQLite Syntax Diagrams: insert-stmt, update-stmt, delete-stmt, upsert-clause](https://sqlite.org/syntax/insert-stmt.html)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/sql/ast.py](../src/database/sql/ast.py): `InsertStatement`, `UpdateStatement`, `DeleteStatement` への UPSERT・RETURNING・複数行値フィールド追加
- [ ] [src/database/sql/parser.py](../src/database/sql/parser.py): `VALUES (...), (...)`, `SELECT` 挿入, `ON CONFLICT`, `RETURNING` 句パース新設
- [ ] [src/database/sql/executor.py](../src/database/sql/executor.py): 一括挿入ループ、ストレージ層 `upsert` 連動、RETURNING プロジェクション実装
- [ ] [tests/database/sql/test_sql_engine.py](../tests/database/sql/test_sql_engine.py): 複数行挿入、UPSERT、RETURNING 単体テスト追加
- [ ] [docs/issues/README.md](README.md): Issue 台帳の登録・追跡

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/257-implement-sqlite-parity-phase2-dml-upsert-returning`

1. **AST 拡張 (`src/database/sql/ast.py`)**:
   - `InsertStatement`: `rows_values: List[List[Any]]`, `select_stmt: Optional[SelectStatement]`, `upsert_clause: Optional[Dict[str, Any]]`, `returning_cols: List[str]` 追加。
   - `UpdateStatement`, `DeleteStatement`: `returning_cols: List[str]`, `order_by: Optional[str]`, `limit: Optional[int]` 追加。
2. **Parser 拡張 (`src/database/sql/parser.py`)**:
   - `VALUES` 句の後続タプルを安全にパース。
   - `ON CONFLICT (col) DO UPDATE SET ...` および `DO NOTHING` の抽出。
   - 末尾 `RETURNING col1, col2, ...` / `RETURNING *` の抽出。
3. **Executor 拡張 (`src/database/sql/executor.py`)**:
   - `_exec_insert`: 単一トランザクション内で複数行を一括挿入。既存キー競合時は `DO UPDATE` の代入式または `DO NOTHING` を適用。
   - 変更されたレコード辞書から `RETURNING` 列を射影して結果行として返却。
4. **セキュリティ & 品質規律**:
   - No-eval 原則遵守。Xenon CC Rank A ($\le 5$)、Mypy --strict 0 errors。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `INSERT INTO tbl (id, val) VALUES ('a', 1), ('b', 2), ('c', 3)` で 3 レコードが一括挿入されること。
- [ ] `INSERT INTO tbl (id, val) VALUES ('a', 10) ON CONFLICT(id) DO UPDATE SET val = 10` で既存レコードが正常に更新されること。
- [ ] `INSERT INTO tbl (id, val) VALUES ('a', 10) ON CONFLICT(id) DO NOTHING` でエラーなくスキップされること。
- [ ] `INSERT ... RETURNING *` および `UPDATE ... RETURNING id, val` が更新結果レコードを正確に返却すること。
- [ ] `tests/database/sql/test_sql_engine.py` に単体テストを追加し、既存テストを含む全テストが PASS すること。
- [ ] `make format`, `make static_analysis` (xenon CC Rank A <= 5, mypy --strict) が 100% PASS すること。
