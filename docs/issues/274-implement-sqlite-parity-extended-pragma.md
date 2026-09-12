---
ID: 274
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT/DATABASE] SQLite 完全互換化: 拡張 PRAGMA (table_xinfo, user_version) の実装 (ID: 274)

## 1. 概要 / Summary
SQLite 公式仕様 ([sqlite.org/pragma.html](https://sqlite.org/pragma.html)) に準拠した拡張 PRAGMA コマンド（`PRAGMA table_xinfo(tbl)`, `PRAGMA user_version`, `PRAGMA user_version = N`, `PRAGMA foreign_key_list(tbl)`）を Pure Python SQL Engine (`src/database/sql/`) に実装する。
生成列や非表示列のメタデータ照会、外部キーリレーションのリスト化、およびスキーママイグレーションツールのバージョン管理をネイティブサポートする。

---

## 2. トレーサビリティ / Traceability
- 準拠仕様: [SQLite PRAGMA Statements](https://sqlite.org/pragma.html)
- 関連設計書:
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/sql/ast.py](../../src/database/sql/ast.py): `PragmaStatement` に引数・代入値の拡張をサポート
- [ ] [src/database/sql/parser.py](../../src/database/sql/parser.py): `PRAGMA user_version = N` 等の代入パース実装
- [ ] [src/database/sql/executor.py](../../src/database/sql/executor.py): `table_xinfo`, `user_version`, `foreign_key_list` の実行結果生成
- [ ] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): 単体テスト追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/274-implement-sqlite-parity-extended-pragma`

1. `PRAGMA name = value` 形式の代入構文パーサーを追加。
2. `PRAGMA user_version` の読み書き用メタデータスロットをカタログに新設。
3. `PRAGMA table_xinfo(tbl)` で通常の `table_info` に加え `hidden` カラム（0:通常, 1:Hidden, 2:Virtual, 3:Stored）を出力。
4. `PRAGMA foreign_key_list(tbl)` でテーブル内の外部キー定義を SQLite 標準形式の行セットとして返却。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `PRAGMA user_version = 42` で設定後、`PRAGMA user_version` で 42 が取得できること。
- [ ] `PRAGMA table_xinfo(tbl)` で生成列の `hidden` 属性が正しく返ること。
- [ ] `PRAGMA foreign_key_list(tbl)` で外部キー参照先テーブル・カラム一覧が返ること。
- [ ] `tests/database/sql/test_sql_engine.py` にテストを追加し PASS すること。
- [ ] `make format`, `make static_analysis` が PASS すること。
