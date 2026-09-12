---
ID: 275
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/DATABASE] SQLite 完全互換化: FTS5 全文検索仮想テーブル & MATCH 演算子の実装 (ID: 275)

## 1. 概要 / Summary
SQLite 公式仕様 ([sqlite.org/fts5.html](https://sqlite.org/fts5.html)) に準拠した全文検索仮想テーブルモジュール `fts5` および `MATCH` 述語を Pure Python SQL Engine (`src/database/sql/`) に実装する。
論文抄録やセキュリティアドバイザリの長文テキストに対して、BM25 スコアリング、接頭辞検索、フレーズ検索、および高速トークン転置インデックス検索を SQL クエリから透過的に利用可能にする。

---

## 2. トレーサビリティ / Traceability
- 準拠仕様: [SQLite FTS5 Extension](https://sqlite.org/fts5.html)
- 関連設計書:
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/storage/fts5_storage.py](../../src/database/storage/fts5_storage.py): `Fts5StorageEngine` の新設（転置インデックス & BM25 スコアラー）
- [ ] [src/database/sql/ast.py](../../src/database/sql/ast.py): `MATCH` 二項演算子のサポート
- [ ] [src/database/sql/parser.py](../../src/database/sql/parser.py): `col MATCH 'query'` 式のパース
- [ ] [src/database/sql/executor.py](../../src/database/sql/executor.py): `CREATE VIRTUAL TABLE tbl USING fts5(...)` マッピングおよび `MATCH` 述語評価・BM25 ランクソート
- [ ] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): 単体テスト追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/275-implement-sqlite-parity-fts5-virtual-table`

1. `CREATE VIRTUAL TABLE tbl USING fts5(col1, col2, tokenize='unicode61')` を既存のプラガブル仮想テーブル機構に登録。
2. 内部でトークナイザー（標準 ASCII / Unicode 空白・記号分割）および転置リスト（ポスティングリスト）を構築。
3. `WHERE tbl MATCH 'cyber attack'` クエリに対して転置インデックスで高速行特定し、BM25（Okapi BM25）アルゴリズムで関連度スコアを計算。
4. `bm25(tbl)` 補助関数または `ORDER BY rank` でのランキングソートをサポート。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `CREATE VIRTUAL TABLE fts_papers USING fts5(title, abstract)` が作成できること。
- [ ] `INSERT INTO fts_papers ...` で転置インデックスが自動更新されること。
- [ ] `SELECT * FROM fts_papers WHERE fts_papers MATCH 'zero trust'` で該当行がヒットすること。
- [ ] BM25 スコアまたは rank 順のソートが動作すること。
- [ ] `tests/database/sql/test_sql_engine.py` にテストを追加し PASS すること。
- [ ] `make format`, `make static_analysis` が PASS すること。
