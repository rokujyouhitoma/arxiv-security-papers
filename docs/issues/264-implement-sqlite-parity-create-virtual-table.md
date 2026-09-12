---
ID: 264
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT/DATABASE] SQLite 完全互換化: CREATE VIRTUAL TABLE 構文によるプラガブルストレージ DDL マッピングの実装 (ID: 264)

## 1. 概要 / Summary
SQLite 公式仕様 ([sqlite.org/lang_createvtab.html](https://sqlite.org/lang_createvtab.html)) に準拠した `CREATE VIRTUAL TABLE` 構文を Pure Python SQL Engine (`src/database/sql/`) に実装する。
現在、CSV (`CsvTableStorage`)、プレーンテキスト (`PlainTextStorage`)、ベクトルストレージ (`VectorStorage`) などのストレージエンジンは内部ファクトリ経由で静的にバインドされているが、SQL DDL 構文としての `CREATE VIRTUAL TABLE [IF NOT EXISTS] tbl_name USING module_name(args...)` をサポートすることで、ユーザーや外部クライアントが SQL コマンドから動的に任意のストレージエンジンを仮想テーブルとして登録できるようにする。
これにより、SQLite の仮想テーブル拡張モジュール（FTS5, R-Tree, CSV 等）と同様のエクスペリエンスを Pure Python SQL Engine 上で提供する。

---

## 2. トレーサビリティ / Traceability
- 準拠仕様: [SQLite CREATE VIRTUAL TABLE](https://sqlite.org/lang_createvtab.html)
- 関連設計書: 
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/sql/ast.py](../../src/database/sql/ast.py): `CreateVirtualTableStatement` AST クラスの追加
- [ ] [src/database/sql/parser.py](../../src/database/sql/parser.py): `CREATE VIRTUAL TABLE ... USING module(args)` のパース処理
- [ ] [src/database/sql/executor.py](../../src/database/sql/executor.py): `_exec_create_virtual_table` ハンドラおよび `PluggableStorageFactory` 呼び出し
- [ ] [src/database/storage/factory.py](../../src/database/storage/factory.py): モジュール名に基づくストレージインスタンス化引数のバインド
- [ ] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): CREATE VIRTUAL TABLE 単体テスト
- [ ] [docs/issues/README.md](../README.md): Issue 台帳の登録・追跡

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/264-implement-sqlite-parity-create-virtual-table`

1. **AST & Parser 実装**:
   - `CreateVirtualTableStatement(SQLStatement)`（`table_name: str`, `module_name: str`, `module_args: List[str]`, `if_not_exists: bool`）を追加。
   - `parser.py` に `_parse_create_virtual_table` を実装し、モジュール名および括弧内引数をトークナイズ。
2. **ストレージファクトリ連携 (`src/database/sql/executor.py`)**:
   - サポートするモジュール: `csv`, `vector`, `text`, `json`。
   - 引数を解析して対応するストレージエンジン（例: `CsvTableStorage(path=...)` や `VectorStorage(...)`）を初期化し、テーブルカタログに登録。
3. **DQL / DML 透過アクセス**:
   - 生成された仮想テーブルに対して `SELECT`, `INSERT`, `UPDATE`, `DELETE` が標準テーブルと同様に実行可能であることを保証。
4. **品質規律**:
   - No-eval 原則厳守、Xenon CC Rank A ($\le 5$)、Mypy strict 0 errors。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `CREATE VIRTUAL TABLE v_csv USING csv(path='...')` でテーブルが作成され、データ照会ができること。
- [ ] `CREATE VIRTUAL TABLE IF NOT EXISTS` が重複作成時にエラーとならないこと。
- [ ] 作成された仮想テーブルに対して `DROP TABLE` が正常に機能すること。
- [ ] `tests/database/sql/test_sql_engine.py` に単体テストを追加し、既存テストを含む全テストが PASS すること。
- [ ] `make format`, `make static_analysis` (xenon CC Rank A <= 5, mypy --strict) が 100% PASS すること。
