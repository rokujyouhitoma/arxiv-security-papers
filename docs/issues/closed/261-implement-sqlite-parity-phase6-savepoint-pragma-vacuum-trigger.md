---
ID: 261
種別: Feature
優先度: Low
ステータス: Closed
---

# [FEAT] SQLite 完全互換化 Phase 6: トランザクション拡張 & メタデータ・トリガー (SAVEPOINT, PRAGMA, VACUUM, TRIGGER) の実装 (ID: 261)

## 1. 概要 / Summary
[DSN-05-01] SQLite 完全互換化ロードマップの最終段階 Phase 6 として、Pure Python SQL Engine (`src/database/sql/`) におけるエンタープライズ堅牢化および運用管理構文を実装する。
具体的には、ネスト可能なトランザクション制御境界を提供する `SAVEPOINT` / `RELEASE SAVEPOINT` / `ROLLBACK TO SAVEPOINT`、SQLite 互換のメタデータ照会を実現する `PRAGMA` 構文（`table_info`, `index_list`, `database_list` 等）、物理ストレージの空き領域回収・コンパクションを実行する `VACUUM`、およびデータ更新前後にフックして自動処理・整合性検査・監査証跡を記録する `CREATE TRIGGER` / `DROP TRIGGER` をサポートする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様書: [[DSN-05-01] 6.6 Phase 6: トランザクション拡張 & メタデータ・トリガー](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md#66-phase-6-トランザクション拡張--メタデータトリガーエンタープライズ堅牢化)
- 準拠仕様: [SQLite Savepoints](https://sqlite.org/lang_savepoint.html), [SQLite PRAGMA](https://sqlite.org/pragma.html), [SQLite Triggers](https://sqlite.org/lang_createtrigger.html), [SQLite VACUUM](https://sqlite.org/lang_vacuum.html)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/database/sql/ast.py](../../src/database/sql/ast.py): `SavepointStatement`, `PragmaStatement`, `VacuumStatement`, `CreateTriggerStatement`, `DropTriggerStatement` 追加
- [x] [src/database/sql/parser.py](../../src/database/sql/parser.py): 各構文パーサーの新設
- [x] [src/database/sql/transaction.py](../../src/database/sql/transaction.py): スタック型セーブポイント管理の実装
- [x] [src/database/sql/executor.py](../../src/database/sql/executor.py): PRAGMA ハンドラ、VACUUM 実行、トリガーフック発火パイプライン
- [x] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): SAVEPOINT, PRAGMA, VACUUM, TRIGGER 単体テスト
- [x] [docs/issues/README.md](../README.md): Issue 台帳の登録・追跡

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/261-implement-sqlite-parity-phase6-savepoint-pragma-vacuum-trigger`

1. **AST & Transaction 拡張 (`src/database/sql/transaction.py`)**:
   - `TransactionManager` にセーブポイントスタック（`_savepoints: List[Tuple[str, int, Dict[str, Any]]]`）を新設。
   - `SAVEPOINT <name>` でチェックポイント作成、`ROLLBACK TO <name>` でその時点までのミューテーション巻き戻し、`RELEASE <name>` で確定。
2. **PRAGMA 実装 (`src/database/sql/executor.py`)**:
   - `PRAGMA table_info(tbl)`: テーブルスキーマ（cid, name, type, notnull, dflt_value, pk）を SQLite 互換の列定義辞書で返却。
   - `PRAGMA index_list(tbl)`, `PRAGMA database_list` の対応。
3. **VACUUM 実装 (`src/database/sql/executor.py`)**:
   - 各ストレージエンジン（`VectorStorage`, `JsonTableStorage`, `CsvTableStorage`）の `compact()` または再書き込み API を呼び出し、不要レコードを物理削除。
4. **Trigger 実装 (`src/database/sql/executor.py`)**:
   - `INSERT / UPDATE / DELETE` 実行の前後で、登録されたトリガーステートメントをトランザクション内でカスケード実行。
5. **セキュリティ & 品質規律**:
   - No-eval 原則遵守。Xenon CC Rank A ($\le 5$)、Mypy --strict 0 errors。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `SAVEPOINT sp1` 後に変更を行い、`ROLLBACK TO sp1` でその変更のみが安全に取り消されること。
- [x] `PRAGMA table_info(cti_cwes)` で標準的なカラム情報テーブルが返却されること。
- [x] `VACUUM` 実行によりテーブルの物理サイズがコンパクションされること。
- [x] `CREATE TRIGGER` で登録したトリガーが DML 実行時に自動発火すること。
- [x] `tests/database/sql/test_sql_engine.py` に単体テストを追加し、既存テストを含む全テストが PASS すること。
- [x] `make format`, `make static_analysis` (xenon CC Rank A <= 5, mypy --strict) が 100% PASS すること。
