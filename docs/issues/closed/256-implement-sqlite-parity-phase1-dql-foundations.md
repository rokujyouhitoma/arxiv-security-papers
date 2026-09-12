---
ID: 256
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] SQLite 完全互換化 Phase 1: DQL 基礎拡張 (DISTINCT, OFFSET, BETWEEN, IS NULL, LIKE ESCAPE, GLOB) の実装 (ID: 256)

## 1. 概要 / Summary
[DSN-05-01] SQLite 完全互換化ロードマップの Phase 1 として、Pure Python SQL Engine (`src/database/sql/`) における基本的な問い合わせ・絞り込み・ページネーション機能を SQLite 公式仕様に準拠して拡張する。
具体的には、結果行の重複排除を行う `DISTINCT` 句、Web API や UI ページネーションに不可欠な `OFFSET` 句、範囲条件検索を簡潔にする `BETWEEN a AND b` 演算子、欠損値・NULL値を厳密に判定する `IS [NOT] NULL` 述語、および特殊文字エスケープを含む `LIKE ... ESCAPE` / UNIXグロブ `GLOB` 演算子を実装する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様書: [[DSN-05-01] 6.1 Phase 1: DQL 基礎拡張](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md#61-phase-1-dql-基礎拡張ページネーション重複排除範囲検索)
- 上位アーキテクチャ: [[DSN-05] 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-05-database_engine_architecture.md)
- 準拠仕様: [SQLite Syntax Diagrams: select-stmt, expr](https://sqlite.org/syntax/select-stmt.html)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/sql/ast.py](../src/database/sql/ast.py): `SelectStatement` への `distinct: bool`, `offset: Optional[int]` 追加
- [ ] [src/database/sql/parser.py](../src/database/sql/parser.py): `DISTINCT`, `OFFSET`, `BETWEEN`, `IS [NOT] NULL`, `GLOB` パース処理の新設
- [ ] [src/database/sql/executor.py](../src/database/sql/executor.py): 重複排除ロジック、オフセットスライス、範囲/NULL/GLOB 評価器の追加
- [ ] [tests/database/sql/test_sql_engine.py](../tests/database/sql/test_sql_engine.py): Phase 1 単体テストケースの網羅
- [ ] [docs/issues/README.md](README.md): Issue 台帳の登録・追跡

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/256-implement-sqlite-parity-phase1-dql-foundations`

1. **AST 拡張 (`src/database/sql/ast.py`)**:
   - `SelectStatement` に `distinct: bool = False`, `offset: Optional[int] = None` を追加。
2. **Parser 拡張 (`src/database/sql/parser.py`)**:
   - `_extract_distinct_clause`: `SELECT DISTINCT ...` のフラグ抽出。
   - `_extract_limit_and_offset`: `LIMIT <n> OFFSET <m>` および `LIMIT <m>, <n>` の抽出。
   - `_parse_where_clause_item`: `BETWEEN <val1> AND <val2>`, `IS NULL`, `IS NOT NULL`, `LIKE ... ESCAPE '...'`, `GLOB '...'` の条件パース。
3. **Executor 拡張 (`src/database/sql/executor.py`)**:
   - `_eval_condition`: `BETWEEN`（境界値含む判定）、`IS_NULL`、`GLOB`（`fnmatch` 相当の純粋Python実装）の評価。
   - `_exec_select`: 射影後行のタプルハッシュ化による `distinct` 重複排除の適用、および `rows[offset:offset+limit]` スライス適用。
4. **セキュリティ & 品質規律**:
   - No-eval 原則遵守。Xenon CC Rank A ($\le 5$)、Mypy --strict 0 errors。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `SELECT DISTINCT category FROM papers` が重複のない一意な行リストを返却すること。
- [ ] `SELECT * FROM cti_cwes LIMIT 10 OFFSET 20` および `LIMIT 20, 10` が 21 件目から 10 行を正確に返却すること。
- [ ] `SELECT * FROM papers WHERE score BETWEEN 8.0 AND 10.0` が境界値を含むレコードを抽出すること。
- [ ] `SELECT * FROM cti_cwes WHERE top25_rank IS NULL` および `IS NOT NULL` が正常に機能すること。
- [ ] `tests/database/sql/test_sql_engine.py` に単体テストを追加し、既存テストを含む全テストが PASS すること。
- [ ] `make format`, `make static_analysis` (xenon CC Rank A <= 5, mypy --strict) が 100% PASS すること。
