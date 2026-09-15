# Issue #301: SQL 式（Expression）パーサーの段階的 AOT PEG 化と並行検証基盤の確立

## 1. 基本情報
- **Issue ID**: `#301`
- **タイトル**: SQL 式（Expression）パーサーの段階的 AOT PEG 化と並行検証基盤の確立
- **ステータス**: `CLOSED`
- **作成日**: 2026-09-16
- **完了日**: 2026-09-16
- **担当エージェント**: Systems Architect (SA) / Database Specialist (DB) / Software Development (SWD) / QA Specialist (QA)
- **関連設計書**: [`DSN-25`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (Phase 2), [`DSN-05`](../designs/DSN-05-database_engine_architecture.md)
- **ブランチ名**: `feat/301-deploy-aot-peg-sql-expression-parser`

---

## 2. 目的と背景
`src/database/sql/expr_parser.py` は自作 RDBMS 最深部の SQL 式構文解析エンジンであり、四則演算・論理演算・関数呼び出し・CASE式・サブクエリ・各種述語を動的 PEG コンビネータで解析していた。
データベース全 420 テストおよび DQL/DML/DDL サブシステムへの影響を完全に局所化・安全管理するため、3 段階の並行検証アプローチ（Step 1: 文法策定と並行検証 $\to$ Step 2: 委譲接続 $\to$ Step 3: クリーンアップ & 本番化）により安全に AOT 化を完遂した。

---

## 3. 実装フェーズと成果

### Step 1: 文法策定と並行検証 (Shadow Testing)
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
   - 既存の全 21 式テストケースにおいて AOT パーサーが既存 AST と 100% 同一の `to_sql()` / `to_legacy_dict()` を出力することを実証。

### Step 2: 委譲接続 (Delegation)
1. `src/database/sql/expr_parser.py` の `SQLExpressionParser` および `parse_sql_expr` を AOT パーサー `SQLExprParser` への委譲実装に切り替え。
2. データベース全 416 テストの 100% PASS を実証。

### Step 3: クリーンアップ & 本番化 (Cleanup & Productionization)
1. `Makefile` の `compile_grammars` ターゲットに `grammars/sql_expr.peg` を追加。
2. `expr_parser.py` から 350 行超の旧動的コンビネータビルダー関数群を完全撤廃し、821 行から 469 行へスリム化（43% 削減）。
3. パフォーマンステスト `tests/database/test_sql_expr_benchmark.py` を新設し、初期化 0ms・1,000 件パース 1.0 秒未満を実証。
4. `docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md` にセクション 7.4 を追記。

---

## 4. 完了条件 (Definition of Done)
- [x] `grammars/sql_expr.peg` が Bryan Ford POPL '04 準拠で定義されていること。
- [x] `src/database/sql/generated_sql_expr_parser.py` が決定論的に生成されていること。
- [x] `tests/database/test_sql_expr_aot.py` が作成され、全 21 式テストの AST 完全一致が 100% PASS すること。
- [x] `src/database/sql/expr_parser.py` が AOT パーサーへ委譲され、旧動的コードが整理されていること。
- [x] `Makefile` の `compile_grammars` に `sql_expr.peg` が登録されていること。
- [x] `tests/database/test_sql_expr_benchmark.py` が新設され、性能要件を満たすこと。
- [x] データベース全 420 テストが 100% PASS すること。
- [x] トリプル品質ゲート（`make check_format`, `make static_analysis` (xenon Grade A $CC \le 4$, mypy --strict)）を 100% PASS すること。

