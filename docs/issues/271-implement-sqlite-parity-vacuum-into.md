---
ID: 271
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/DATABASE] SQLite 完全互換化: VACUUM INTO 'filename' オンラインバックアップの実装 (ID: 271)

## 1. 概要 / Summary
SQLite 3.27.0+ 仕様 ([sqlite.org/lang_vacuum.html#vacuuminto](https://sqlite.org/lang_vacuum.html#vacuuminto)) に準拠した `VACUUM INTO 'filename'` 構文を Pure Python SQL Engine (`src/database/sql/`) に実装する。
稼働中のアクティブデータベースを排他ロックすることなく、指定されたターゲットファイルパスへ一貫性のあるクリーンなスナップショット（コンパクション済み完全コピー）を出力できるようにする。

---

## 2. トレーサビリティ / Traceability
- 準拠仕様: [SQLite VACUUM INTO](https://sqlite.org/lang_vacuum.html#vacuuminto)
- 関連設計書:
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/sql/ast.py](../../src/database/sql/ast.py): `VacuumStatement` に `into_file: Optional[str]` を追加
- [ ] [src/database/sql/parser.py](../../src/database/sql/parser.py): `VACUUM [tbl] INTO 'path'` のパース実装
- [ ] [src/database/sql/executor.py](../../src/database/sql/executor.py): スナップショット生成およびターゲットファイルへのアトミック書き出し
- [ ] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): 単体テスト追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/271-implement-sqlite-parity-vacuum-into`

1. AST に `into_file` 属性を追加。
2. `parser.py` で `VACUUM [tbl] INTO '...'` の正規表現パターンを認識。
3. エグゼキューターで、対象テーブル（または全テーブル）の現在の最新スナップショットを複製し、新しいストレージインスタンスを一時作成して `into_file` のパスへフラッシュ。
4. ターゲットファイルが既に存在する場合は上書きエラー（またはアトミック置換）の整合性を確保。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `VACUUM INTO 'backup.db'` が正常に実行され、ターゲットパスに完全なバックアップが生成されること。
- [ ] バックアップファイルから別の SQLExecutor / DB セッションで全データが正常に照会できること。
- [ ] 元データベースの運用が中断されず、整合性が維持されること。
- [ ] `tests/database/sql/test_sql_engine.py` にテストを追加し PASS すること。
- [ ] `make format`, `make static_analysis` が PASS すること。
