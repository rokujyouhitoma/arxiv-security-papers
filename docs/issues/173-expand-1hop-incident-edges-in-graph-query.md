---
ID: 173
種別: Bug
優先度: High
ステータス: Open (In Progress)
---

# [BUG] CTI グラフクエリにおける 1-Hop 隣接エンティティおよびインシデントエッジの自動展開（Paper 単体検索時のエッジ消失バグ解消） (ID: 173)

## 1. 概要 / Summary
`dashboard.html` の CTI グラフ探索コンソール（`graphQueryInput`）において `match: Paper:` や `Paper:` などのクエリを実行した際、該当する論文ノード群は抽出されるものの、接続しているはずのエッジ（`EXPLOITS`、`DEMONSTRATES`、`TARGETS`、`PROPOSES` 等）が 1 本も表示されず、すべての Paper ノードが次数 0（エッジなし）の孤立ノードとして描画される。

DSN-17（Security Knowledge Ontology）および DSN-07 の設計において、Paper ノードは異種エンティティ（CWE、AttackTechnique、Technology、DefenseMethod）とエッジ結合されているが、クエリエンジン（`PropertyGraphEngine._query_match`）が「誘導部分グラフ（Induced Subgraph：始点と終点の双方がマッチ集合に含まれるエッジのみを抽出）」を採用しているため、接続先エンティティが検索条件に含まれない場合にエッジが全件除外されてしまう。

本 Issue では、クエリにマッチした頂点に対し、直接接続されている 1-Hop 先の隣接ノードおよび関連エッジ（Incident Edges）を自動展開して返却・可視化するようクエリエンジン（`PropertyGraphEngine`）およびサブグラフ生成ロジックを改善し、エッジ消失バグを根本解決する。

### 再現手順 / Steps to Reproduce
1. ブラウザで `/dashboard.html` を開き、上部モードで `🛡️ CTI Graph (ATT&CK / CWE)` を選択する。
2. CTI Graph Query 入力欄に `match: Paper:`（または `Paper:`）を入力し、`[🔍 探索 (Execute)]` を押す。
3. キャンバス上に論文ノードが表示されるが、接続エッジが 0 本（`0 リンク`）となり、全ノードが孤立状態で表示される。

### 再現環境 / Environment
- OS / Env: Linux / Web Browser (Chrome, Firefox, Safari)
- File: [src/graph/engine.py](file:///workspace/arxiv-security-papers/src/graph/engine.py), [src/web/gateway/handlers.py](file:///workspace/arxiv-security-papers/src/web/gateway/handlers.py), [site/dashboard.html](file:///workspace/arxiv-security-papers/site/dashboard.html)

---

## 2. トレーサビリティ / Traceability
- [DSN-14: Graph Engineering Dashboard (Section 11)](../../designs/DSN-14-graph_engineering_dashboard.md)
- [DSN-17: Security Knowledge Ontology & Graph Reasoning Engine](../../designs/DSN-17-security-knowledge-ontology-and-graph-reasoning-engine.md)
- [DSN-07: Graph Engine Architecture](../../designs/DSN-07-graph-engine-architecture.md)
- [Issue 137: /dashboard Product タブにおける CTI グラフクエリ・コンソールおよびサブグラフ抽出・ハイライト機能の実装](closed/137-implement-graph-query-console-and-subgraph-extraction-in-dashboard.md)
- [Issue 164: /dashboard tab=graph におけるエッジ確信度＆推論ルール絞り込みフィルタとエビデンス表示の実装](closed/164-integrate-edge-confidence-rule-and-evidence-in-graph-tab.md)
- [Issue 166: /dashboard tab=graph における Glassmorphic ツールチップ・操作ガイド基盤の実装](closed/166-implement-glassmorphic-tooltips-and-graph-uiux-guide.md)

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Modeling & Mitigations)
- **T-173-01: 巨大ハブノード展開によるメモリ枯渇および Canvas クラッシュ (CWE-400 / DoS)**
  - *脅威*: 検索に一致した頂点が多数の次数を持つハブノード（例: 広範な攻撃手法や基底脆弱性）である場合、1-hop 展開によって数千本のエッジと頂点が一度に返却され、ブラウザの Canvas 物理シミュレーションが停止（フリーズ）またはクラッシュする。
  - *対策*: 
    1. シードノードあたりの最大取得エッジ数（`max_neighbors_per_seed = 20`）を設定。
    2. サブグラフ全体の返却エッジ総数を上限クランプ（`max_edges = min(limit * 3, 200)`）。
    3. 全体返却ノード総数を上限クランプ（`max_nodes = 150`）。
- **T-173-02: 閉路・自己参照エッジ探索による無限ループ・スタックオーバーフロー (CWE-674)**
  - *脅威*: 相互接続された知識グラフ構造において、隣接ノード収集時に再帰や循環参照が発生し、プロセスがハングアップする。
  - *対策*: 展開処理は BFS 1-Hop のみとし、訪問済みノード集合（`visited_ids: Set[str]`）および処理済みエッジ識別子集合（`seen_edge_keys: Set[Tuple[str, str, str]]`）による非再帰的インメモリ探索を徹底する。
- **T-173-03: クエリ文字列インジェクション・不正正規表現 ReDoS (CWE-20 / CWE-1333)**
  - *脅威*: ユーザ入力クエリに不正なメタ文字を混入させ、正規表現エンジンのバックトラックを誘発する。
  - *対策*: `PropertyGraphEngine._is_vertex_match` は純粋な部分文字列マッチ（`in` 演算子）を用い、正規表現 `re` の動的コンパイルを排除。
- **T-173-04: Pure-Python & ゼロ外部依存の堅持**
  - *要件*: 追加ライブラリ（NetworkX 等）を一切使用せず、Python 3.12+ 標準ライブラリのみで完結させる。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/graph/engine.py](file:///workspace/arxiv-security-papers/src/graph/engine.py)
  - `_is_vertex_match`: `v.label` のマッチング判定を追加。
  - `_collect_incident_edges` / `_expand_1hop_incident_subgraph`: シード集合から 1-Hop 先の隣接頂点とエッジを有界収集するヘルパーの新設または拡張。
  - `_query_match`: 単純な `_collect_induced_edges` 呼び出しから 1-Hop 有界展開サブグラフ収集への刷新。
  - `_query_gaps`: インシデントエッジの接続先頂点（neighbor）が `nodes` に含まれずダングリングとなる不整合の解消。
  - `execute_graph_query`: `nodes_raw[:limit]` による不用意な隣接ノード切り捨て（ダングリングエッジ生成）の防止と、シード一致件数（`match_count`）の正確な返却。
- [ ] [src/web/gateway/handlers.py](file:///workspace/arxiv-security-papers/src/web/gateway/handlers.py)
  - `/api/graph/query` における `limit` のパースと、レスポンス JSON スキーマ（`mesh.nodes`, `mesh.edges`, `match_count`）の整合性確認。
- [ ] [site/dashboard.html](file:///workspace/arxiv-security-papers/site/dashboard.html)
  - `graphQueryResultBadge` の表示確認（シード一致数とエッジ数の明瞭な表示）。
  - ノード・エッジ受信時のフィルタ（`applyCtiFilter`）におけるダングリングエッジ除外ガードの動作確認。
- [ ] [tests/graph/test_graph_query.py](file:///workspace/arxiv-security-papers/tests/graph/test_graph_query.py)
  - `match: Paper:`, `match: injection`, `gaps` 等における 1-Hop 隣接ノード展開およびエッジ保持の単体テスト追加。
- [ ] [tests/web/test_dashboard_graph_query.py](file:///workspace/arxiv-security-papers/tests/web/test_dashboard_graph_query.py)
  - REST API 経由での Paper 検索時にエッジおよび接続先エンティティ（AttackTechnique, CWE 等）が正しく返却される結合テスト追加。
- [ ] [tests/web/test_dashboard_graph_tab.py](file:///workspace/arxiv-security-papers/tests/web/test_dashboard_graph_tab.py)
  - UI 側の描画整合性・バッジ表示仕様の回帰テスト。

---

## 5. 根本原因分析 (RCA) / Root Cause Analysis
1. **異種オントロジー構造と「誘導部分グラフ (Induced Subgraph)」のミスマッチ**:
   - DSN-17 オントロジーにおいて、知識グラフは異種ノード（Paper, AttackTechnique, CWE, DefenseMechanism）間の関係性（2部グラフまたは多部グラフ的構造）として定義されている。
   - Paper 同士は直接接続されず、Paper は AttackTechnique や CWE とのみ接続する。
   - 現在の `_query_match` は `_collect_induced_edges(matched_ids)` を呼び出している。これは「始点と終点の**双方が `matched_ids` に含まれるエッジ**のみを抽出」する。
   - `match: Paper:` や `match: 論文タイトル` で検索すると、`matched_ids` には Paper ノードしか含まれない。そのため、AttackTechnique や CWE へ伸びるエッジは「終点が `matched_ids` に存在しない」と判定され、すべて破棄（0件）されていた。
2. **`_is_vertex_match` における `v.label` 照合の欠落**:
   - `_query_match` の docstring には `"Matches vertices by ID, label, name, or title keyword."` と明記されているが、実装コード（L846-853）では `v.id`, `v.properties["name"]`, `v.properties["title"]` のみを照合しており、`v.label` が照合対象から漏れていた。
   - このため、`v.id` にラベル文字列が含まれない頂点に対して `match: AttackTechnique` 等を指定した場合に不整合が生じる潜在バグが存在した。
3. **`_query_gaps` におけるダングリングエッジの発生とフロントエンド破棄**:
   - `_query_gaps`（L793）では `self._collect_vertices(gap_ids), self._collect_incident_edges(gap_ids, limit * 2)` を返している。
   - しかし、`nodes` には `gap_ids` しか含めず、インシデントエッジの対向先頂点を `nodes` に含めていなかった。
   - `dashboard.html` の `applyCtiFilter` は「`e.source` と `e.target` の双方が `activeNodeIds` に存在すること」を必須としているため、対向頂点のないエッジはフロントエンド側で全件破棄されていた。
4. **`execute_graph_query` の無条件スライスによるダングリングエッジ誘発**:
   - `execute_graph_query`（L948）において `"nodes": [self._format_cti_node(v, gap_id_set) for v in nodes_raw[:limit]]` と記述されており、`nodes_raw` が後段で一律に切り詰められていた。
   - 仮に探索側で対向先頂点を集めても、`limit` で切断されるとエッジの終点頂点のみが欠落し、ダングリングエッジ化してフロントエンドで破棄されるリスクがあった。

---

## 6. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 
  - `ego: <PaperID> 1` クエリを使用する（特定ノード 1 件であれば ego 展開されるが、一覧検索や複数論文の横断探索には使えないため抜本策とはならない）。
* **恒久対策 (Permanent Fix)**: 
  - `PropertyGraphEngine` に安全な 1-Hop 有界展開ロジック（`_expand_1hop_incident_subgraph`）を導入。
  - `_query_match` において、一致したシード頂点（Seed Vertices）から 1-Hop のインシデントエッジおよびその対向先エンティティ頂点（1-Hop Neighbors）を収集し、頂点とエッジの整合性を担保して返却する。
  - `_is_vertex_match` に `v.label` 判定を追加。
  - `_query_gaps` においても対向先頂点を `nodes` に含めるよう整合化。
  - `execute_graph_query` の `match_count` は直接マッチしたシード頂点数を正しく表現し、`nodes` はダングリングを生じさせない形で完全返却する。

---

## 7. 実装方針 / Implementation Plan
Target Branch: `fix/173-expand-1hop-incident-edges-in-graph-query`

1. **`_is_vertex_match` の完全化 (`src/graph/engine.py`)**:
   - `term_low in v.label.lower()` を追加し、ID / Label / Name / Title のすべてがマッチ対象となるよう修正。
2. **有界 1-Hop サブグラフ展開ヘルパーの実装 (`src/graph/engine.py`)**:
   - `_expand_1hop_incident_subgraph(seed_ids: Set[str], max_edges: int = 150, max_neighbors_per_seed: int = 20) -> Tuple[List[Vertex], List[Edge]]`:
     - `seed_ids` に含まれる各頂点について `self.get_both_edges(sid)` を取得。
     - 各シードについて最大 `max_neighbors_per_seed` 本、全体で `max_edges` 本までのエッジを重複なく収集。
     - 収集された各エッジの対向先ノード ID（`neighbor_id = edge.dst_id if edge.src_id == sid else edge.src_id`）を記録。
     - 全返却頂点集合 `result_node_ids = seed_ids | neighbor_ids` を構築。
     - 全エッジは両端頂点が必ず `result_node_ids` に含まれるため、ダングリングエッジがゼロとなる。
3. **`_query_match` および `_query_gaps` のリファクタリング (`src/graph/engine.py`)**:
   - `_query_match`:
     - シードマッチ頂点 `matched_ids` を `limit` 件収集。
     - `_expand_1hop_incident_subgraph(matched_ids, max_edges=min(limit * 3, 200))` を呼び出し、展開された頂点群とインシデントエッジ群を返却。
   - `_query_gaps`:
     - 同様にギャップノード群から 1-Hop 隣接頂点とエッジを展開し、対向頂点が欠落しないように修正。
4. **`execute_graph_query` のレスポンス整合性向上 (`src/graph/engine.py`)**:
   - `match_count` にはシード一致件数（クエリ条件に直接合致したノード数）を格納。
   - `nodes` は展開後の頂点群をそのまま出力（多重スライスによるダングリングエッジ生成を撤廃）。
5. **テストコードの拡充**:
   - `tests/graph/test_graph_query.py`:
     - `test_query_match_paper_expands_1hop_edges`: `match: Paper:` または特定 Paper を検索した際、エッジおよび対向する `AttackTechnique` や `CWE` ノードが一緒に返却され、エッジ数が > 0 であることを検証。
     - `test_query_gaps_includes_neighbor_nodes`: `gaps` クエリで返却される全エッジの両端ノードが `res["nodes"]` に必ず存在することを検証。
     - `test_query_match_by_label`: `match: Paper` や `match: AttackTechnique` で正しくノードが抽出されることを検証。
   - `tests/web/test_dashboard_graph_query.py`:
     - REST API `/api/graph/query?q=match:Paper&limit=20` を実行し、エッジ数が > 0 でダングリングが存在しないことを検証。
6. **品質ゲート検証**:
   - `make check_format`, `make static_analysis` (Flake8, Radon, Xenon Rank A, Mypy Strict), `make test` を実行し、全件 PASS を確認。

---

## 8. 完了条件 / Success Criteria (DoD)
- [ ] `match: Paper:` や `Paper:` などの Paper 検索クエリにおいて、接続する 1-Hop 隣接エンティティ（AttackTechnique, CWE 等）およびインシデントエッジが自動展開されて返却されること
- [ ] 返却されるすべてのエッジの `source` および `target` が `res["nodes"]` 内に必ず存在し、ダングリングエッジが 0 件であること
- [ ] `dashboard.html` の Canvas 上で Paper 検索時にエッジが正しく描画され、孤立ノード化しないこと
- [ ] `gaps` クエリにおいてもエッジ対向頂点がノード一覧に含まれ、フロントエンドでエッジが除外されないこと
- [ ] `_is_vertex_match` が `v.label` による部分一致判定を正しく行うこと
- [ ] ハブノード展開時にも上限クランプ（シードあたり20件、全体150〜200エッジ）が機能し、DoS耐性が保たれること
- [ ] 新規単体テスト・結合テストが追加され、100% PASS すること
- [ ] `make verify_quality`（フォーマット、静的解析 Xenon Rank A、Mypy、全テスト）が 100% PASS すること
