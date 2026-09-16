# Issue #302: SQL 全構文解析層（DQL / DML / DDL）の包括的 AOT Packrat PEG 化

## 1. 基本情報
- **Issue ID**: `#302`
- **タイトル**: SQL 全構文解析層（DQL / DML / DDL）の包括的 AOT Packrat PEG 化
- **ステータス**: `CLOSED`
- **作成日**: 2026-09-16
- **完了日**: 2026-09-16
- **担当エージェント**: Systems Architect (SA) / Database Specialist (DB) / Software Development (SWD) / QA Specialist (QA)
- **関連設計書**: [`DSN-25`](../../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (Phase 2), [`DSN-05`](../../designs/DSN-05-database_engine_architecture.md)
- **ブランチ名**: `feat/302-deploy-aot-peg-to-all-sql-subsystems`

---

## 2. 目的と背景
SQL 式パーサー（Issue #301）の AOT PEG 化完了に続き、自作 RDBMS のクエリ解析層の残り 3 大サブシステム（DQL, DML, DDL）を一括して事前コンパイル型 (AOT Packrat PEG) へ換装する。
これにより、動的コンビネータ構築コスト（実行時オブジェクト生成）をデータベース全域から完全排除し、0ms 起動・超高速クエリ解析・完全型安全・宣言的文法管理を確立する。

---

## 3. 実装フェーズと要件
1. **Phase 1: DQL パーサーの AOT PEG 化**:
   - `grammars/sql_dql.peg` 策定（Bryan Ford POPL '04 準拠）。
   - `src/database/sql/generated_sql_dql_parser.py` 自動生成。
   - `src/database/sql/dql_parser.py` の委譲接続と動的コード撤廃。
2. **Phase 2: DML パーサーの AOT PEG 化**:
   - `grammars/sql_dml.peg` 策定（INSERT, UPDATE, DELETE, UPSERT, RETURNING）。
   - `src/database/sql/generated_sql_dml_parser.py` 自動生成。
   - `src/database/sql/dml_parser.py` の委譲接続と動的コード撤廃。
3. **Phase 3: DDL パーサーの AOT PEG 化**:
   - `grammars/sql_ddl.peg` 策定（CREATE, DROP, ALTER, INDEX, VIEW, TRIGGER, VIRTUAL TABLE）。
   - `src/database/sql/generated_sql_ddl_parser.py` 自動生成。
   - `src/database/sql/ddl_parser.py` の委譲接続と動的コード撤廃。
4. **Phase 4: ビルド・ベンチマーク・ドキュメント統合**:
   - `Makefile` の `compile_grammars` ターゲット更新。
   - `tests/database/test_sql_subsystems_benchmark.py` 新設。
   - `docs/designs/DSN-25` へのセクション 7.5 追記。
   - データベース全テストおよび品質ゲート検証。

---

## 4. 完了条件 (Definition of Done)
- [x] `grammars/sql_dql.peg`, `sql_dml.peg`, `sql_ddl.peg` が完全定義されていること。
- [x] `generated_sql_dql_parser.py`, `generated_sql_dml_parser.py`, `generated_sql_ddl_parser.py` が決定論的に生成されていること。
- [x] `dql_parser.py`, `dml_parser.py`, `ddl_parser.py` が AOT パーサーへ委譲され、動的ビルダーが撤廃されていること。
- [x] `Makefile` の `compile_grammars` に 3 文法が登録されていること。
- [x] `tests/database/test_sql_subsystems_benchmark.py` が新設され、起動 0ms およびスループット要件を満たすこと。
- [x] 既存の全単体テスト（`test_sql_dql_peg.py`, `test_sql_dml_peg.py`, `test_sql_ddl_peg.py`）および DB 全 426 テストが 100% PASS すること。
- [x] トリプル品質ゲート（`make check_format`, `make static_analysis` (xenon Grade A $CC \le 4$, mypy --strict)）を 100% PASS すること。
