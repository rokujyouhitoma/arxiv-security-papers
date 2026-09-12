---
ID: 259
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] SQLite 完全互換化 Phase 4: ビルトイン関数群 & CASE 式 (文字列・数学・制御・日付時刻・JSON・集約拡張) の実装 (ID: 259)

## 1. 概要 / Summary
[DSN-05-01] SQLite 完全互換化ロードマップの Phase 4 として、Pure Python SQL Engine (`src/database/sql/`) における式評価エンジンおよび組み込み関数群を本格実装する。
クエリ内での複雑なビジネスロジック・条件分岐を可能にする `CASE WHEN ... THEN ... ELSE ... END` 式、Core 文字列関数（`LENGTH`, `LOWER`, `UPPER`, `SUBSTR`, `TRIM`, `REPLACE`, `INSTR`）、Core 数学関数（`ABS`, `ROUND`, `CEIL`, `FLOOR`, `POWER`, `SQRT`, `RANDOM`）、Core 制御関数（`COALESCE`, `NULLIF`, `IIF`, `TYPEOF`）、日付時刻関数（`DATE`, `TIME`, `DATETIME`, `STRFTIME`, `UNIXEPOCH`）、JSON 操作関数（`JSON_EXTRACT`, `JSON_ARRAY`, `JSON_OBJECT`, `JSON_PATCH`）、および文字列集約関数（`GROUP_CONCAT` / `STRING_AGG`）を純粋 Python で安全に提供する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様書: [[DSN-05-01] 6.4 Phase 4: ビルトイン関数群 & 条件制御構文](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md#64-phase-4-ビルトイン関数群--条件制御構文式エンジンの成熟)
- 準拠仕様: [SQLite Core Functions](https://sqlite.org/lang_corefunc.html), [Date & Time Functions](https://sqlite.org/lang_datefunc.html), [JSON Functions](https://sqlite.org/json1.html)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/sql/functions.py](../src/database/sql/functions.py): [NEW] ビルトイン関数レジストリおよび純粋 Python 関数実装群
- [ ] [src/database/sql/parser.py](../src/database/sql/parser.py): `CASE WHEN` 構文および関数呼出式の字句・構文解析
- [ ] [src/database/sql/executor.py](../src/database/sql/executor.py): 式評価器（`_extract_field_value`）への関数呼出・CASE 評価統合
- [ ] [tests/database/sql/test_sql_engine.py](../tests/database/sql/test_sql_engine.py): 各種関数の計算・変換単体テスト
- [ ] [docs/issues/README.md](README.md): Issue 台帳の登録・追跡

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/259-implement-sqlite-parity-phase4-builtin-functions-and-case`

1. **新設モジュール (`src/database/sql/functions.py`)**:
   - プラガブルな関数レジストリ `BuiltinFunctionRegistry` を構築。
   - 文字列、数学、制御、日付時刻、JSON の各関数を純粋 Python のゼロ外部依存で実装。
   - `eval()` や `exec()` を一切排除した安全な関数呼出プロトコル。
2. **Parser 拡張 (`src/database/sql/parser.py`)**:
   - `CASE [expr] WHEN cond THEN res [ELSE default] END` 式のトークン抽出。
   - カンマ区切りの関数引数リストの再帰深度セーフなパース。
3. **Executor 拡張 (`src/database/sql/executor.py`)**:
   - `_extract_field_value`: カラム名、リテラル、算術演算、JSON演算子に加え、関数呼出（`func(args...)`）および CASE 式を透過的に評価。
   - 集約計算に `GROUP_CONCAT` を追加。
4. **セキュリティ & 品質規律**:
   - No-eval 原則遵守。Xenon CC Rank A ($\le 5$)、Mypy --strict 0 errors。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `SELECT CASE WHEN score >= 9 THEN 'High' ELSE 'Normal' END AS level FROM papers` が正常に分岐評価されること。
- [ ] `SELECT UPPER(title), LENGTH(description), COALESCE(status, 'Unknown') FROM cti_cwes` が正常動作すること。
- [ ] `SELECT DATE('now'), STRFTIME('%Y-%m', created_at) FROM cti_cwes` で日付変換が行われること。
- [ ] `SELECT JSON_EXTRACT(metadata, '$.category') FROM papers` で JSON フィールドが抽出されること。
- [ ] `SELECT category, GROUP_CONCAT(id, ', ') FROM papers GROUP BY category` で集約文字列が返却されること。
- [ ] `tests/database/sql/test_sql_engine.py` に単体テストを追加し、既存テストを含む全テストが PASS すること。
- [ ] `make format`, `make static_analysis` (xenon CC Rank A <= 5, mypy --strict) が 100% PASS すること。
