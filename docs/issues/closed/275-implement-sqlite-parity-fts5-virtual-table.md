---
ID: 275
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/DATABASE] SQLite 完全互換化: FTS5 全文検索仮想テーブル & MATCH 演算子の実装 (ID: 275)

## 1. 概要 / Summary
SQLite 公式仕様 ([sqlite.org/fts5.html](https://sqlite.org/fts5.html)) に準拠した全文検索仮想テーブルモジュール `fts5` および `MATCH` 述語を Pure Python SQL Engine (`src/database/sql/`) に実装する。
論文抄録やセキュリティアドバイザリの長文テキストに対して、BM25 スコアリング、接頭辞検索、フレーズ検索、および高速トークン転置インデックス検索を SQL クエリから透過的に利用可能にする。

---

## 2. トレーサビリティ & セキュリティ脅威分析 / Traceability & Threat Model
- 準拠仕様: [SQLite FTS5 Extension](https://sqlite.org/fts5.html)
- 関連設計書:
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)
- セキュリティ脅威分析 (STRIDE):
  - **Tampering / Injection**: `MATCH` 式に入力されるクエリ文字列のセキュアな字句解析。Python `eval()` / `exec()` の完全排除 (No-eval 原則)。
  - **Denial of Service (ReDoS)**: トークン分割正規表現における指数関数的バックトラックの排除。線形 $O(N)$ トークン抽出。
  - **Information Disclosure**: テーブル別権限管理 (`AccessController`) との完全連動。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/database/storage/fts5_storage.py](../../src/database/storage/fts5_storage.py): `Fts5StorageEngine` の新設（トークナイザー, 転置インデックス & Okapi BM25 スコアラー）
- [x] [src/database/storage/factory.py](../../src/database/storage/factory.py): `fts5` エンジンの `StorageEngineFactory` 登録
- [x] [src/database/sql/ast.py](../../src/database/sql/ast.py): `MATCH` 二項演算子・仮想テーブルメタデータのサポート
- [x] [src/database/sql/parser.py](../../src/database/sql/parser.py): `col MATCH 'query'` / `tbl MATCH 'query'` 式のパース、および FTS5 モジュール引数解析
- [x] [src/database/sql/executor.py](../../src/database/sql/executor.py): `CREATE VIRTUAL TABLE tbl USING fts5(...)` マッピングおよび `MATCH` 述語評価・`rank` / `bm25(tbl)` 仮想列スコアリング
- [x] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): 単体テスト追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/275-implement-sqlite-parity-fts5-virtual-table`

1. **`src/database/storage/fts5_storage.py` (新規作成)**:
   - `Fts5Tokenizer`: `unicode61` (英数字・日本語Unicode対応、小文字化、記号分割) および `ascii` モード。
   - `Fts5StorageEngine`:
     - メモリ内およびファイル保存可能な転置インデックス（`term -> {row_id: tf}`）。
     - 文書長マップ（`doc_lens: Dict[int, int]`）および平均文書長（`avg_dl`）。
     - Okapi BM25 アルゴリズム ($k_1 = 1.2, b = 0.75$):
       $$\text{BM25}(D, Q) = \sum_{q \in Q} \text{IDF}(q) \cdot \frac{f(q, D) \cdot (k_1 + 1)}{f(q, D) + k_1 \cdot (1 - b + b \cdot \frac{|D|}{\text{avgdl}})}$$
       $$\text{IDF}(q) = \ln\left(1 + \frac{N - n(q) + 0.5}{n(q) + 0.5}\right)$$
     - 共通ストレージインターフェース (`metadata`, `append`, `upsert`, `delete_indices`, `columns`, `schema`)。
     - `match_query(query: str, target_column: Optional[str] = None) -> List[Tuple[int, float]]`: クエリに一致する行インデックスとスコアのリスト返却。
2. **`src/database/storage/factory.py`**:
   - `StorageEngineFactory` に `fts5` を登録。
3. **`src/database/sql/parser.py`**:
   - `_parse_match_clause` を `_WHERE_PARSERS` に追加。`field MATCH 'query'` を構文木に反映。
   - `_parse_create_virtual_table` で `fts5(col1, col2, ...)` のカラム定義を抽出。
4. **`src/database/sql/executor.py`**:
   - `_parse_virtual_module_args` において、`fts5` モジュールの場合の位置指定引数をカラム名リストとして保持。
   - `_evaluate_single_condition` で `op == "MATCH"` を検出し、`table.storage.match_query(...)` または行単位トークン一致で判定。
   - `rank` 仮想列の生成: `MATCH` 実行時に各行の BM25 スコア（負値: SQLite FTS5 標準仕様に従いスコアが高いほどより小さい負数、または `ORDER BY rank` で上位ソート可能）および `bm25(...)` 関数値の自動補完。
5. **テスト & 品質検証**:
   - `tests/database/sql/test_sql_engine.py` に FTS5 仮想テーブル作成、INSERT、MATCH 検索、AND 条件組み合わせ、`ORDER BY rank` のテストケースを追加。
   - `make format`, `make static_analysis` (xenon A <= 5, mypy strict) をクリア。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `CREATE VIRTUAL TABLE fts_papers USING fts5(title, abstract)` が作成できること。
- [x] `INSERT INTO fts_papers ...` で転置インデックスが自動更新されること。
- [x] `SELECT * FROM fts_papers WHERE fts_papers MATCH 'zero trust'` で該当行がヒットすること。
- [x] `SELECT * FROM fts_papers WHERE title MATCH 'zero'` で特定列検索がヒットすること。
- [x] BM25 スコアまたは `ORDER BY rank` 順のソートが動作すること。
- [x] `tests/database/sql/test_sql_engine.py` にテストを追加し PASS すること。
- [x] `make format`, `make static_analysis` (xenon A, mypy --strict) が 100% PASS すること。

