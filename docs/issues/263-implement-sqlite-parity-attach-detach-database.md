---
ID: 263
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT/DATABASE] SQLite 完全互換化: ATTACH / DETACH DATABASE 構文による動的マルチスキーママウントの実装 (ID: 263)

## 1. 概要 / Summary
SQLite 公式仕様 ([sqlite.org/lang_attach.html](https://sqlite.org/lang_attach.html), [sqlite.org/lang_detach.html](https://sqlite.org/lang_detach.html)) に準拠した `ATTACH DATABASE` および `DETACH DATABASE` 構文を Pure Python SQL Engine (`src/database/sql/`) に実装する。
現在、データベースのスコープ切替は CLI / dbshell の `--database` や `.use` コマンドで提供されているが、標準 SQL 構文としての `ATTACH DATABASE 'file_or_dir' AS schema_name` をサポートすることで、SQL クエリ内部から動的に外部 DB コンテナをマウントし、`SELECT * FROM main.tbl JOIN aux.tbl ON ...` のようなスキーマ修飾子を用いた透過的なクロスデータベース走査およびデータ連携を実現する。
さらに `DETACH DATABASE schema_name` による動的アンマウント、および `PRAGMA database_list` へのリアルタイム反映を保証する。

---

## 2. トレーサビリティ / Traceability
- 準拠仕様: 
  - [SQLite ATTACH DATABASE](https://sqlite.org/lang_attach.html)
  - [SQLite DETACH DATABASE](https://sqlite.org/lang_detach.html)
- 関連設計書: 
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/sql/ast.py](../../src/database/sql/ast.py): `AttachStatement`, `DetachStatement` AST クラスの追加
- [ ] [src/database/sql/parser.py](../../src/database/sql/parser.py): `ATTACH [DATABASE] 'filename' AS schema_name`, `DETACH [DATABASE] schema_name` パース処理
- [ ] [src/database/sql/executor.py](../../src/database/sql/executor.py): `_exec_attach`, `_exec_detach` ハンドラ、スキーマプレフィックス名前解決
- [ ] [src/database/settings.py](../../src/database/settings.py): 動的スキーマ登録・ライフサイクル管理連携
- [ ] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): ATTACH/DETACH およびスキーマ間クエリの単体テスト
- [ ] [docs/issues/README.md](../README.md): Issue 台帳の登録・追跡

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/263-implement-sqlite-parity-attach-detach-database`

1. **AST & Parser 実装**:
   - `AttachStatement(SQLStatement)`（`filename: str`, `schema_name: str`）を追加。
   - `DetachStatement(SQLStatement)`（`schema_name: str`）を追加。
   - `parser.py` に `_parse_attach`, `_parse_detach` を実装。
2. **動的スキーマ管理 (`src/database/sql/executor.py`)**:
   - `SQLExecutor` に `_attached_databases: Dict[str, DatabaseScope]` を保持。
   - テーブル参照（`TableRef`）の名前解決時に `schema_name.table_name` が指定された場合、対象のスキーマスコープからテーブルを解決。
   - `PRAGMA database_list` の出力に `main`, `temp` に加えてアタッチされた全スキーマを含める。
3. **DETACH 制御**:
   - `DETACH DATABASE schema_name` で対象スコープを解放（`main`, `temp` のデタッチはエラーとする SQLite 互換仕様）。
4. **品質規律**:
   - No-eval 原則厳守、Xenon CC Rank A ($\le 5$)、Mypy strict 0 errors。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `ATTACH DATABASE 'path' AS aux;` で外部スキーマがマウントできること。
- [ ] `SELECT * FROM main.t1 JOIN aux.t2 ON ...` でクロススキーマ JOIN が実行できること。
- [ ] `PRAGMA database_list` でアタッチされたスキーマが表示されること。
- [ ] `DETACH DATABASE aux;` でアンマウントされ、以後の参照でエラーとなること。
- [ ] `tests/database/sql/test_sql_engine.py` に単体テストを追加し、既存テストを含む全テストが PASS すること。
- [ ] `make format`, `make static_analysis` (xenon CC Rank A <= 5, mypy --strict) が 100% PASS すること。
