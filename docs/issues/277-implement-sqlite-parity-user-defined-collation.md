---
ID: 277
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT/DATABASE] SQLite 完全互換化: ユーザー定義照合順序 (User-Defined Collation) 登録機構の実装 (ID: 277)

## 1. 概要 / Summary
SQLite C/Python API 仕様 ([sqlite.org/c3ref/create_collation.html](https://sqlite.org/c3ref/create_collation.html)) に準拠したユーザー定義照合順序（User-Defined Collation）の登録インターフェースを Pure Python SQL Engine (`src/database/sql/`) に実装する。
Python コールバック関数を用いて任意の言語・ロケール・ドメイン特化の文字列比較関数をエンジンへ動的登録可能にし、`COLLATE custom_collation` での柔軟なソートおよびグループ化を可能にする。

---

## 2. トレーサビリティ / Traceability
- 準拠仕様: [SQLite create_collation](https://sqlite.org/c3ref/create_collation.html)
- 関連設計書:
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/sql/executor.py](../../src/database/sql/executor.py): `SQLExecutor.create_collation(name, callback)` API の追加
- [ ] [src/database/sql/functions.py](../../src/database/sql/functions.py): 照合順序レジストリの管理
- [ ] [src/database/sql/driver.py](../../src/database/sql/driver.py): PEP 249 / sqlite3 互換接続オブジェクトへの `create_collation` メソッド公開
- [ ] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): 単体テスト追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/277-implement-sqlite-parity-user-defined-collation`

1. `SQLExecutor` に `self.collations: Dict[str, Callable[[str, str], int]]` レジストリを設ける。
2. コールバック仕様: `def cmp(str1, str2) -> int`（負: str1 < str2, 0: 等しい, 正: str1 > str2）。
3. Python 標準の `create_collation` API と完全同一シグネチャを提供。
4. クエリ実行時の比較演算・ソートキー生成において、登録済みカスタム照合関数を呼び出す。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `executor.create_collation("reverse", lambda a, b: (a > b) - (a < b))` のようにカスタム照合順序を登録できること。
- [ ] `SELECT * FROM tbl ORDER BY name COLLATE reverse` で登録関数に従ってソートされること。
- [ ] PEP 249 / `sqlite3` クライアントブリッジ経由でも登録・利用可能なこと。
- [ ] `tests/database/sql/test_sql_engine.py` にテストを追加し PASS すること。
- [ ] `make format`, `make static_analysis` が PASS すること。
