# Issue #300: CTI ナレッジグラフ クエリ DSL への AOT PEG 事前コンパイラ実戦投入と動的ビルダー完全撤廃

## 1. 基本情報
- **Issue ID**: `#300`
- **タイトル**: CTI ナレッジグラフ クエリ DSL への AOT PEG 事前コンパイラ実戦投入と動的ビルダー完全撤廃
- **ステータス**: `RESOLVED`
- **作成日**: 2026-09-16
- **完了日**: 2026-09-16
- **担当エージェント**: Systems Architect (SA) / Software Development (SWD) / Application Specialist (APS)
- **関連設計書**: [`DSN-25`](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (Phase 2), [`DSN-18`](../designs/DSN-18-property_graph_database_engine.md)
- **ブランチ名**: `feat/300-deploy-aot-peg-graph-query-parser`

---

## 2. 目的と背景
`src/graph/query_dsl.py` は現在、インポート時またはインスタンス化時に動的 PEG コンビネータ（`Lit`, `Reg`, `Seq`, `OneOrMore`, `Opt`）を Python オブジェクトとして組み立てており、初期化オーバーヘッドおよび構文定義の分散が生じている。

本課題では、オントロジー（`turtle.peg`）、検索クエリ（`search_query.peg`）に続き、CTI ナレッジグラフ クエリ DSL を **[`grammars/graph_query.peg`](../../grammars/graph_query.peg)** として宣言的に分離・AOT コンパイルし、ゼロオーバーヘッド・完全型安全な静的パーサーへ全面換装する。

---

## 3. 実装要件
1. **文法定義の宣言的分離 (`grammars/graph_query.peg`)**:
   - Bryan Ford POPL '04 論文仕様（`<-`, `[...]`, `.`）に完全準拠。
   - Cypher 風パスクエリ（単一/複数ホップ、エッジラベル、括弧ノード、ラベル指定）の定義。
   - 複合フィルタクエリ（`community:0 AND label:ThreatActor`）の定義。
   - セマンティックアクションにより `GraphDSLQuery` AST ノードを生成。
2. **AOT 静的コード自動生成 (`src/graph/generated_graph_query_parser.py`)**:
   - `tools/peg_compiler/compile_peg.py` により決定論的に生成。
3. **`src/graph/query_dsl.py` の改修と動的ビルダー完全撤廃**:
   - `_build_node_parser`, `_build_edge_parser`, `_build_path_parser`, `_build_filter_parser`, `_build_graph_dsl_grammar` 等を撤廃。
   - `GraphQueryDSLParser` から AOT パーサー `GraphQueryParser` への委譲。
4. **ビルドパイプライン統合**:
   - `Makefile` の `compile_grammars` ターゲットに追加。
5. **ベンチマークと互換性検証**:
   - `tests/graph/test_graph_benchmark.py` を新設。
   - 既存全単体テスト（`tests/graph/test_graph_query_dsl.py`）の 100% 互換動作。

---

## 4. 完了条件 (Definition of Done)
- [x] `grammars/graph_query.peg` が Bryan Ford POPL '04 準拠で定義されていること。
- [x] `src/graph/generated_graph_query_parser.py` が決定論的に生成され、Git 管理されていること。
- [x] `src/graph/query_dsl.py` 内の動的コンビネータ構築が完全撤廃され、委譲型になっていること。
- [x] `Makefile` に `grammars/graph_query.peg` のコンパイルが追加されていること。
- [x] `tests/graph/test_graph_benchmark.py` が作成され、全テストが PASS すること。
- [x] トリプル品質ゲート（`make check_format`, `make static_analysis` (xenon Grade A $CC \le 4$, mypy --strict), `make test`）を 100% PASS すること。
- [x] DSN-25 設計書が更新されていること。
