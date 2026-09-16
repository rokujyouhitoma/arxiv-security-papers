---
ID: 309
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] SQL TCL / DCL / Admin / Utility 構文解析層の包括的 AOT Packrat PEG 化 (ID: 309)

## 1. 概要 / Summary
現在、SQL パーサーのうち DQL (SELECT)、DML (INSERT/UPDATE/DELETE)、DDL (CREATE/ALTER/DROP) は AOT Packrat PEG 化（Issue #302）が完了しているが、TCL (BEGIN, COMMIT, ROLLBACK, SAVEPOINT)、DCL (GRANT, REVOKE)、Admin/Utility (PRAGMA, VACUUM, ANALYZE, ATTACH, DETACH, EXPLAIN, SHOW) を担当する `src/database/sql/admin_parser.py` は、依然として実行時の動的 PEG コンビネータ（`Seq()`, `Choice()`）ビルダーのまま残存している。
これにより起動オーバーヘッド（パーサーオブジェクト構築コスト）やメモリ消費が発生している。
本タスクでは `grammars/sql_admin.peg` を新規作成し、DSN-25 Phase 2 仕様に準拠した AOT 事前生成パーサーへ完全換装することで、SQL サブシステム全体のパーサー 100% AOT 化を完遂する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [`DSN-25`](../../designs/DSN-25-pure_python_packrat_peg_parser_engine.md), [`DSN-05`](../../designs/DSN-05-database_layer.md)
- 関連 Issue: [#302](302-deploy-aot-peg-to-all-sql-subsystems.md), [#301](301-deploy-aot-peg-sql-expression-parser.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `grammars/sql_admin.peg` (新規: TCL / DCL / Admin / Utility 文法定義)
- [x] `src/database/sql/generated_sql_admin_parser.py` (新規: AOT 生成パーサー)
- [x] `src/database/sql/admin_parser.py` (動的ビルダー撤廃・AOT 移譲ファサード化)
- [x] `src/database/sql/parser.py` (総合 SQL ディスパッチャの統合確認)
- [x] `Makefile` (`compile_grammars` ターゲット更新)
- [x] `tests/database/test_sql_admin_peg.py` (新規テストスイート)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/309-deploy-aot-peg-sql-admin-and-tcl-parser`

1. **`grammars/sql_admin.peg` の文法定義**:
   - TCL: BEGIN [DEFERRED|IMMEDIATE|EXCLUSIVE] [TRANSACTION], COMMIT, ROLLBACK [TO SAVEPOINT?], SAVEPOINT name, RELEASE [SAVEPOINT?] name
   - DCL: GRANT privs ON table TO user, REVOKE privs ON table FROM user
   - Admin/Utility:
     - PRAGMA [schema.]name [= val | (val)]
     - VACUUM [schema] [INTO file]
     - ANALYZE [schema | schema.table]
     - ATTACH [DATABASE] expr AS schema
     - DETACH [DATABASE] schema
     - EXPLAIN [QUERY PLAN] stmt
     - SHOW TABLES / COLUMNS / ...
   - セマンティックアクションにより typed AST オブジェクトを直接生成。
2. **AOT コンパイラ実行と Makefile 統合**:
   - `Makefile` の `compile_grammars` ターゲットに `sql_admin.peg` を追加し、`generated_sql_admin_parser.py` を事前生成。
3. **`admin_parser.py` のリファクタリング**:
   - 動的コンビネータ構築ロジック（約300行）を撤廃し、`generated_sql_admin_parser.py` を呼び出す軽量ファサードへ換装（0ms 初期化）。
4. **品質検証**:
   - `tests/database/` の全テスト PASS、`make check_format`, `xenon` ($CC \le 4$), `mypy --strict` の完全クリア。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `grammars/sql_admin.peg` が定義され、`make compile_grammars` で AOT Python コードが生成されること。
- [x] TCL, DCL, Admin, Utility の全構文が AOT パーサーで 100% 互換動作すること。
- [x] `admin_parser.py` 内の動的コンビネータ構築ロジックが撤廃され、パーサーの初期化コストが 0ms になること。
- [x] 全ての新規・更新コードが循環的複雑度 $CC \le 4$（Xenon Grade A）および `mypy --strict` をクリアすること。
- [x] 単体テストが全件 PASS すること。
