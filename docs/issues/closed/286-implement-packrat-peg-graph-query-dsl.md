---
ID: 286
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] CTI ナレッジグラフ向け Packrat PEG パスクエリ DSL の実装 (DSN-25 / DSN-18 連携) (ID: 286)

## 1. 概要 / Summary
設計仕様書 [DSN-25](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第5.3節) および [DSN-18](../designs/DSN-18-property_graph_database_engine.md) に基づき、現在 `src/graph/engine.py` で `split("->")` や `startswith()` によるアドホックな文字列分割で行われているグラフクエリ解析を刷新し、Packrat PEG エンジン (`src/core/structures/peg.py`) を用いた高度な **CTI グラフパスクエリ DSL (`src/graph/query_dsl.py`)** を新規実装した。
Cypher 風の多段パスマッチング（例: `APT29 -> [USES] -> Malware -> [EXPLOITS] -> CWE-79`、ホップ数 `[..3]`、エッジラベル指定）および複合フィルタ条件（`community:0 AND label:ThreatActor`）をゼロ外部依存で厳密に構文解析・コンパイルし、グラフエンジン実行パイプラインへ統合完了。

---

## 2. トレーサビリティ / Traceability
- 設計書: [DSN-25-pure_python_packrat_peg_parser_engine.md](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第5.3節)
- 設計書: [DSN-18-property_graph_database_engine.md](../designs/DSN-18-property_graph_database_engine.md)
- 前提成果物: [src/core/structures/peg.py](../../src/core/structures/peg.py) (Issue 284)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/graph/query_dsl.py](../../src/graph/query_dsl.py) (新規: CTI グラフパスクエリ PEG DSL エンジン)
- [x] [src/graph/engine.py](../../src/graph/engine.py) (`_dispatch_graph_query` の DSL 統合)
- [x] [src/graph/__init__.py](../../src/graph/__init__.py) (公開エクスポートの更新)
- [x] [tests/graph/test_graph_query_dsl.py](../../tests/graph/test_graph_query_dsl.py) (新規: DSL 構文解析・パスマッチング・フィルタ実行の包括的テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/286-packrat-peg-graph-query-dsl`

1. **AST / クエリ中間表現の定義 (`src/graph/query_dsl.py`)**:
   - `NodePattern`: `alias: Optional[str]`, `label: Optional[str]`, `node_id: Optional[str]`, `properties: Dict[str, Any]`
   - `EdgePattern`: `label: Optional[str]`, `min_hops: int = 1`, `max_hops: int = 1`, `direction: str = "out"` ("out", "in", "both")
   - `PathPattern`: `elements: List[Union[NodePattern, EdgePattern]]`
   - `GraphFilterQuery`: `conditions: List[Dict[str, Any]]`, `logical_op: str = "AND"`
2. **PEG 文法定義 (`GraphQueryDSLParser`)**:
   - `PathExpr = NodePat (OptWS EdgePat OptWS NodePat)*`
   - `NodePat = "(" OptWS (Ident? (":" Ident)? (OptWS PropBlock)?) OptWS ")" / Ident`
   - `EdgePat = "->" / "<-" / "--" / "-[" OptWS (":"? Ident)? (OptWS "*" [0-9]+ (".." [0-9]+)?)? OptWS "]->" / "<-[" ... "]-"`
   - `FilterExpr = FilterTerm (OptWS ("AND" / "OR") OptWS FilterTerm)*`
3. **グラフエンジン実行連携 (`src/graph/engine.py`)**:
   - `execute_dsl_query(dsl_query_str, limit)`: パス式またはフィルタ式をパースし、既存の BFS / DFS / トラバーサルアルゴリズム（`_find_bfs_path`, `detect_communities` 等）を呼び出して誘導部分グラフ（`nodes`, `edges`, `stats`）を返却。
4. **品質ゲート遵守**:
   - 全関数 Xenon CC Rank A (<= 4)、`mypy --strict` エラー 0 件。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `src/graph/query_dsl.py` に PEG ベースのグラフ DSL パーサーが実装されていること
- [x] 多段パスマッチング（`A -> [USES] -> B -> [EXPLOITS] -> C` や `A -> B`）が正しくパースされ、対応ノード・エッジが抽出されること
- [x] 複合条件フィルタ（`community:0 AND label:ThreatActor`）が正しくパース・抽出されること
- [x] `src/graph/engine.py` の `execute_graph_query` から DSL クエリがシームレスに実行できること
- [x] `tests/graph/test_graph_query_dsl.py` が 100% PASS すること
- [x] `make check_format` および `make static_analysis` が 100% PASS すること
