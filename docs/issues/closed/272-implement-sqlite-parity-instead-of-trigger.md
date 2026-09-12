---
ID: 272
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/DATABASE] SQLite 完全互換化: VIEW 向け INSTEAD OF トリガーの実装 (ID: 272)

## 1. 概要 / Summary
SQLite 公式仕様 ([sqlite.org/lang_createtrigger.html](https://sqlite.org/lang_createtrigger.html)) に準拠した `INSTEAD OF` トリガーを Pure Python SQL Engine (`src/database/sql/`) に実装する。
通常は直接更新できない `VIEW`（ビュー）に対して `INSERT`, `UPDATE`, `DELETE` が実行された際、ビュー自体への直接変更（または読み取り専用エラー）の代わりに、事前に定義された `INSTEAD OF` トリガー本体の DML を実行して基底テーブルへ変更を透過的に転送できるようにする。
これにより、複雑な結合ビューや集約ビューに対する透過的更新インターフェース（Updatable Views）を実現する。

構文例:
```sql
CREATE VIEW v_user_profiles AS
  SELECT u.id, u.username, p.bio FROM users u JOIN profiles p ON u.id = p.user_id;

CREATE TRIGGER trig_ins_v_user_profiles
INSTEAD OF INSERT ON v_user_profiles
BEGIN
  INSERT INTO users (id, username) VALUES (NEW.id, NEW.username);
  INSERT INTO profiles (user_id, bio) VALUES (NEW.id, NEW.bio);
END;
```

---

## 2. セキュリティ & アーキテクチャ脅威分析 (STRIDE / No-eval 原則)
- **再帰・無限ループ防止 (DoS 防御)**:
  - トリガー内部で同一ビューに対する DML が呼ばれた場合の無限再帰を検出・制限（最大深度ガードまたは再帰検出）。
- **SQL インジェクション防御 (Tampering 防御)**:
  - `NEW.` / `OLD.` プレースホルダー置換において、安全なリテラル文字列クォーティングおよびエスケープを実施。悪意ある入力値による SQL インジェクションを無害化。
- **権限昇格防止 (Elevation of Privilege 防御)**:
  - `INSTEAD OF` トリガー実行時、実行元のロール（`effective_role`）に基づき基底テーブルへの DML 操作権限（INSERT, UPDATE, DELETE）を適切に継承・検証。
- **複雑度統制 (Cyclomatic Complexity)**:
  - VIEW 判定ヘルパー、INSTEAD OF トリガー探索・発火ハンドラーを独立関数として切り出し、全関数で Xenon Rank A ($\le 5$) を厳格順守。

---

## 3. トレーサビリティ / Traceability
- 準拠仕様: [SQLite CREATE TRIGGER (INSTEAD OF)](https://sqlite.org/lang_createtrigger.html)
- 関連設計書:
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [src/database/sql/ast.py](../../src/database/sql/ast.py):
  - `CreateTriggerStatement`: `timing: str = "AFTER"` (BEFORE, AFTER, INSTEAD OF) の定義確認
- [src/database/sql/parser.py](../../src/database/sql/parser.py):
  - `_parse_create_trigger_stmt`: `INSTEAD OF` の正規表現マッチおよび正規化
- [src/database/sql/executor.py](../../src/database/sql/executor.py):
  - `_exec_create_trigger`: テーブル存在チェックまたは VIEW 存在チェックの整合性
  - `_find_instead_of_trigger(table_name, event)`: ビューに対する `INSTEAD OF` トリガーの取得
  - `_exec_insert`: `stmt.table_name` が VIEW の場合に `INSTEAD OF INSERT` トリガーを探索・発火して早期リターン
  - `_exec_update`: `stmt.table_name` が VIEW の場合に `INSTEAD OF UPDATE` トリガーを探索・発火して早期リターン
  - `_exec_delete`: `stmt.table_name` が VIEW の場合に `INSTEAD OF DELETE` トリガーを探索・発火して早期リターン
- [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py):
  - `test_instead_of_trigger_lifecycle`: VIEW に対する INSTEAD OF INSERT / UPDATE / DELETE の完全なライフサイクル検証

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/272-implement-sqlite-parity-instead-of-trigger`

1. **エグゼキューター拡張 (`src/database/sql/executor.py`)**:
   - `_find_instead_of_trigger(table_name: str, event: str) -> Optional[CreateTriggerStatement]`:
     指定された `table_name` (VIEW) かつ `event` (INSERT/UPDATE/DELETE) に合致する `INSTEAD OF` トリガーを検索。
   - `_exec_insert_instead_of_view`:
     `stmt.table_name` が `self.views` に存在する場合、`_find_instead_of_trigger(stmt.table_name, "INSERT")` を取得。存在しなければ `cannot modify view '{stmt.table_name}'` エラーを送出。存在すれば行辞書を構築し、各行に対して `_fire_single_trigger(trig, r, effective_role)` を実行して結果を返却。
   - `_exec_update_instead_of_view`:
     `stmt.table_name` が `self.views` に存在する場合、`_find_instead_of_trigger(stmt.table_name, "UPDATE")` を取得。ビューから WHERE 句にマッチする行を SELECT 照会し、各マッチ行について `old_rec` と `new_rec`（更新代入後）をマージしたコンテキストでトリガーを発火。
   - `_exec_delete_instead_of_view`:
     `stmt.table_name` が `self.views` に存在する場合、`_find_instead_of_trigger(stmt.table_name, "DELETE")` を取得。ビューから WHERE 句にマッチする行を照会し、各行について `_fire_single_trigger(trig, old_rec, effective_role)` を実行。
2. **テーブル/ビューディスパッチの統合**:
   - `_exec_insert`, `_exec_update`, `_exec_delete` の冒頭で `if stmt.table_name in self.views:` を評価し、VIEW 向けハンドラーへ即時ディスパッチ。
3. **テスト & 品質ゲート検証**:
   - `test_instead_of_trigger_lifecycle` を追加。VIEW への INSERT / UPDATE / DELETE で基底テーブルが正しく更新されることを検証。
   - `make format`, `make static_analysis`, `pytest` を実行し、Rank A ($\le 5$)、型エラー0件を確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `CREATE TRIGGER ... INSTEAD OF INSERT ON view_name` が構文エラーなく登録できること。
- [x] VIEW に対して `INSERT INTO view_name ...` を実行した際、基底テーブルへ連動して行が挿入されること。
- [x] `INSTEAD OF UPDATE ON view_name` により、VIEW 経由での条件付き UPDATE が基底テーブルに反映されること。
- [x] `INSTEAD OF DELETE ON view_name` により、VIEW 経由での DELETE が基底テーブルの対象行を連動削除すること。
- [x] `INSTEAD OF` トリガーのない VIEW への DML は従来通り `cannot modify view` エラーとなること。
- [x] `tests/database/sql/test_sql_engine.py` に単体・結合テストを追加し PASS すること。
- [x] `make format`, `make static_analysis` (Rank A, mypy --strict) が PASS すること。
