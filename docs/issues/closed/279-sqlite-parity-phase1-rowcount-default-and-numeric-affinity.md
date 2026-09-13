---
ID: 279
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-09-13
---

# [DB/PARITY] SQLite 互換性向上 Phase 1: DDL rowcount=-1 準拠、DEFAULT 句自動補完、および数値比較アフィニティの実装 (ID: 279)

## 1. 概要 / Summary

`docs/audits/pure_python_db_vs_sqlite3_differential_report.md` における全79件の比較検証結果に基づき、Pure Python データベース (`src/database`) のネイティブ `sqlite3` に対する互換性を向上させた。
本 Issue（Phase 1）では、リスクが低く即効性の高い以下の項目を集中的に解消し、ベースライン 51.9% (41/79) の MATCH 率を **75.9% (60/79)** まで大幅に引き上げた。

1. **PEP 249 / SQLite 準拠の DDL `rowcount = -1` 化**:
   - `CREATE TABLE`, `CREATE VIEW`, `DROP TABLE` などの DDL 実行時、影響行数を決定できないため `-1` を返却する仕様に統一。
2. **`INSERT` 時の列定義 `DEFAULT` 句自動補完**:
   - 列名を省略した INSERT 実行時に、テーブルスキーマの `default` 値を評価・適用（`ColumnDef.default_value` 連動）。
3. **`BETWEEN` および比較演算子の数値型アフィニティ適用**:
   - 負数境界（`-20` など）を含む BETWEEN 構文の正規表現修正と数値型アフィニティの保証。
4. **Modulo (`%`) 演算子および文字列連結 (`||`) 演算子のサポート**:
   - C言語/SQLite互換の剰余演算と、パイプ文字列結合の完全サポート。

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/database/ipc/driver.py`](../../src/database/ipc/driver.py) — PEP 249 Cursor の `rowcount` 状態管理（非DMLで `-1` 返却）
- [x] [`src/database/sql/ast.py`](../../src/database/sql/ast.py) — `ColumnDef.default_value` 属性追加
- [x] [`src/database/sql/parser.py`](../../src/database/sql/parser.py) — `CREATE TABLE` カラム `DEFAULT` 抽出、負数対応 `BETWEEN` 正規表現
- [x] [`src/database/sql/executor.py`](../../src/database/sql/executor.py) — `_build_insert_row_dicts` でのデフォルト補完、`math.fmod` による `%` 演算、`||` 連結
- [x] [`tests/database/compatibility/test_sqlite3_differential.py`](../../tests/database/compatibility/test_sqlite3_differential.py) — Phase 1 差分回帰テストスイート追加
- [x] [`tests/database/sql/test_sql_compatibility_matrix.py`](../../tests/database/sql/test_sql_compatibility_matrix.py) — `CREATE TABLE` rowcount 期待値を `-1` に更新
- [x] [`scripts/compare_sqlite3_differential.py`](../../scripts/compare_sqlite3_differential.py) — 差分比較評価スクリプト
- [x] [`docs/audits/pure_python_db_vs_sqlite3_differential_report.md`](../../docs/audits/pure_python_db_vs_sqlite3_differential_report.md) — Section 6 Phase 1 改善前後レポート追加

## 3. 根本原因分析 (RCA) / Root Cause Analysis

1. **DDL rowcount**: `driver.py` が DDL 実行時に更新行数 `0` を返却していた。SQLite / PEP 249 は `-1` を返却する仕様。
2. **DEFAULT 補完**: `_build_insert_row_dicts()` が未指定列に対して `None` を無条件で補完しており、スキーマ定義の `default` プロパティを参照していなかった。
3. **数値アフィニティ**: `_parse_between_clause()` の正規表現が `[0-9\.]+` のみで負数符号 `-` を考慮していなかったため、`-20` がマッチせず WHERE 節ごと脱落していた。

## 4. 実施計画と実装手順 / Implementation Plan

- [x] `driver.py`: `_resolve_cursor_rowcount` を新設し、DML 以外で `rowcount = -1` を返却。
- [x] `ast.py` & `parser.py`: `ColumnDef` に `default_value` を追加し、`_parse_column_def` で抽出。
- [x] `parser.py`: `_parse_between_clause` および `_split_and_conditions` を `-?[0-9\.]+` に更新。
- [x] `executor.py`: `_apply_column_defaults` を追加し、INSERT 時に未指定列へデフォルト値を適用。`%` および `||` を実装。
- [x] `test_sqlite3_differential.py`: Phase 1 専用テストケースを追加（7テストすべて PASS）。
- [x] `make differential_audit`: 79件のクエリを再評価し、一致率が 51.9% -> 75.9% に向上したことを確認。
- [x] `docs/audits/pure_python_db_vs_sqlite3_differential_report.md`: Section 6 に Before/After 比較レポートを記録。

## 5. 完了定義 (Definition of Done)

- [x] `make differential_audit` で DDL テストケースおよび DEFAULT、BETWEEN テストケースが `MATCH` に転換すること。
- [x] 一致率 (MATCH) がベースライン (51.9%) から向上すること（75.9% へ +24.0% 向上）。
- [x] `make check_format` および `make static_analysis` (Xenon CC <= 4 Grade A, mypy --strict) に 100% 合格すること。
- [x] Before/After の計測結果が公式レポートとして記録されていること。
