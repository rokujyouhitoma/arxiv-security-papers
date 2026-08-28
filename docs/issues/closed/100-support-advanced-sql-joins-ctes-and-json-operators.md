# Issue #100: src/database における高度な SQL 機能 (JOIN, WITH RECURSIVE, JSON 演算子, テーブルエイリアス) のサポート

## 1. 概要 (Overview)
自作の Pure Python ベクトルデータベースエンジン（`src/database/`）において、単一テーブルの CRUD / ベクトル検索に加え、グラフ走査や関連エンティティの多段階推論を SQL で直接実行可能にするため、以下の高度な SQL 機能をサポートする。

1. **`JOIN` 句**: `INNER JOIN`, `LEFT JOIN`, および多重 JOIN のサポート
2. **再帰共通テーブル式 (`WITH RECURSIVE`)**: 階層・木構造・グラフ走査を反復評価する CTE のサポート
3. **JSON 抽出演算子**: `->` (JSON 値抽出) および `->>` (文字列アンクォート抽出) のサポート
4. **テーブルエイリアス & 列エイリアス**: `table AS alias`, `p.column`, `expr AS alias` の修飾サポート

- **ステータス**: 完了 (Closed)
- **完了日**: 2026-08-28
- **担当**: Database Specialist & Systems Architect Agent

---

## 2. 実装計画 (Implementation Plan)
1. **`src/database/sql/ast.py`**:
   - `JoinClause`, `TableRef`, `ColumnRef`, `CTEDefinition` の AST ノード定義
   - `SelectStatement` の拡張
2. **`src/database/sql/parser.py`**:
   - `WITH [RECURSIVE]`、`JOIN ... ON ...`、`UNION [ALL]`、`->>`、エイリアス記法のパース処理実装
3. **`src/database/sql/executor.py`**:
   - ネステッドループ / ハッシュ結合による多重 JOIN 実行エンジン
   - 作業テーブルを用いた再帰 CTE (`WITH RECURSIVE`) 反復実行エンジン
   - JSON 抽出ヘルパーおよびエイリアス射影の実装
4. **テスト作成**:
   - `tests/database/sql/test_advanced_sql.py` による網羅的単体テスト

---

## 3. DoD (Definition of Done)
- [ ] 3ホップ以上の多重 JOIN クエリが正しく結合され、意図した行を返すこと
- [ ] `WITH RECURSIVE` を用いた深さ制限付きグラフ走査クエリが正しく実行されること
- [ ] `properties->>'field'` による JSON フィールド抽出と WHERE 条件・SELECT 射影が機能すること
- [ ] 既存の `tests/database/` 全テストスイート（単一テーブル、HNSW、WAL、BTree）が 100% 回帰パスすること
