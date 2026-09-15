# Issue #301: SQL 式（Expression）パーサーの段階的 AOT PEG 化と並行検証基盤の確立

## 1. 基本情報
- **Issue ID**: `#301`
- **タイトル**: SQL 式（Expression）パーサーの段階的 AOT PEG 化と並行検証基盤の確立
- **ステータス**: `IN_PROGRESS`
- **作成日**: 2026-09-16
- **担当エージェント**: Systems Architect (SA) / Database Specialist (DB) / Software Development (SWD) / QA Specialist (QA)
- **関連設計書**: [`DSN-25`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (Phase 2), [`DSN-05`](../designs/DSN-05-database_engine_architecture.md)
- **ブランチ名**: `feat/301-deploy-aot-peg-sql-expression-parser`

---

## 2. 目的と背景
`src/database/sql/expr_parser.py` は自作 RDBMS 最深部の SQL 式構文解析エンジンであり、四則演算・論理演算・関数呼び出し・CASE式・サブクエリ・各種述語を動的 PEG コンビネータで解析している。
データベース全 401 テストおよび DQL/DML/DDL サブシステムへの影響を完全に局所化・安全管理するため、3 段階の並行検証アプローチ（Step 1: 文法策定と並行検証 $\to$ Step 2: 委譲接続 $\to$ Step 3: クリーンアップ）により安全に AOT 化を推進する。

---

## 3. 実装要件 (Step 1)
1. **文法定義の宣言的策定 (`grammars/sql_expr.peg`)**:
   - Bryan Ford POPL '04 論文仕様（`<-`, `[...]`, `.`）に完全準拠。
   - リテラル（数値、シングル/ダブル引用符文字列、`TRUE`/`FALSE`/`NULL`）、列参照（`col`, `tbl.col`, `col->>'path'`）。
   - 算術演算子（`+`, `-`, `*`, `/`, `%`）の優先順位制御、単項演算子（`+`, `-`, `NOT`, `EXISTS`）。
   - 比較演算子（`=`, `!=`, `<>`, `<`, `<=`, `>`, `>=`）および特殊述語（`IS [NOT] NULL`, `[NOT] BETWEEN`, `[NOT] LIKE/GLOB/MATCH`, `[NOT] IN`）。
   - 論理演算子（`AND`, `OR`）、括弧ネスト式、関数呼び出し（`COUNT(*)`, `DISTINCT`）、CASE 式、`COLLATE`。
   - セマンティックアクションにより `SQLExpr` AST ノードを生成。
2. **AOT 静的コード自動生成 (`src/database/sql/generated_sql_expr_parser.py`)**:
   - `tools/peg_compiler/compile_peg.py` により決定論的に生成。
3. **並行検証テスト (`tests/database/test_sql_expr_aot.py`)**:
   - 既存コードを一切変更せず、既存の全 21 式テストケースにおいて AOT パーサーが既存 AST と 100% 同一の `to_sql()` / `to_legacy_dict()` を出力することを検証。

---

## 4. 完了条件 (Definition of Done for Step 1)
- [ ] `grammars/sql_expr.peg` が Bryan Ford POPL '04 準拠で定義されていること。
- [ ] `src/database/sql/generated_sql_expr_parser.py` が決定論的に生成されていること。
- [ ] `tests/database/test_sql_expr_aot.py` が作成され、既存 21 式テストの AST 完全一致が 100% PASS すること。
- [ ] 既存の `src/database/sql/expr_parser.py` および全 401 テストが無傷で PASS すること。
- [ ] トリプル品質ゲート（`make check_format`, `make static_analysis` (xenon Grade A $CC \le 4$, mypy --strict)）を 100% PASS すること。
