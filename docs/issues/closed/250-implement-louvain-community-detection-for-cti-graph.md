---
ID: 250
種別: Feature
優先度: Medium
ステータス: Closed (2026-09-13)
担当エージェント: Software Development (SWD) / Information Security Specialist / Systems Architect
---

# [FEAT/CORE] CTI 脅威知識グラフにおける Louvain 法（モジュラリティ最適化）コミュニティ検出および攻撃キャンペーンクラスタリングの実装 (ID: 250)

## 1. 概要 / Summary

本 Issue では、CTI（Cyber Threat Intelligence）知識グラフ（脅威アクター、マルウェアファミリ、MITRE ATT&CK 手法、CWE/CVE、キャンペーン等）における攻撃キャンペーンクラスタや類似脅威グループを高精度に自動抽出・分類するため、モジュラリティ最大化（Modularity Optimization）に基づく **Pure-Python Louvain コミュニティ検出アルゴリズム** を `src/core/structures/community.py` に実装し、`src/graph/`（`PropertyGraphEngine` / `GraphTraversal`）へ統合する。

先行の Issue #247 で導入された `DisjointSet`（Union-Find）は「完全孤立した連結成分」の分離に有効である一方、現実の CTI 知識グラフは多くのエンティティが共通の脆弱性や標的国等を介して間接的に接続され、単一の巨大連結成分（Giant Component）を形成しやすい。そのため、エッジの重みや接続密度に基づいてグラフ内部の密結合サブグラフを分割・識別できるモジュラリティ最適化アルゴリズムが必要不可欠となる。

---

## 2. トレーサビリティ & セキュリティ脅威分析 / Traceability & STRIDE Threat Model

- **学術論文・仕様標準**:
  - V. D. Blondel, J.-L. Guillaume, R. Lambiotte, and E. Lefebvre, *"Fast unfolding of communities in large networks"*, Journal of Statistical Mechanics: Theory and Experiment, Vol. 2008, No. 10, P10008, 2008.
  - M. E. J. Newman and M. Girvan, *"Finding and evaluating community structure in networks"*, Physical Review E, 69(2), 026113, 2004.
- **関連設計書**:
  - [`docs/designs/DSN-14-graph_engineering_dashboard.md`](../../designs/DSN-14-graph_engineering_dashboard.md) (Graph Analytics & Subgraph Extraction)
  - [`docs/designs/DSN-18-property_graph_database_engine.md`](../../designs/DSN-18-property_graph_database_engine.md) (Graph Traversal & Graph Algorithms)
- **先行 Issue**:
  - [Issue #247: Disjoint Set (Union-Find) の共通コア実装](247-implement-disjoint-set-union-find-for-graph-clustering.md)
  - [Issue #147: Largest Connected Component Filter in Graph Tab](147-implement-largest-connected-component-filter-in-graph-tab.md)
- **セキュリティ脅威分析 (STRIDE)**:
  - **Denial of Service (DoS / リソース枯渇・無限ループ)**:
    - *脅威*: 悪意ある循環エッジや超高密度グラフ（Dense Multi-Clique）による Louvain 最適化ループの未収束、またはゼロ除算（$m = 0$ のエッジなしグラフ）による例外クラッシュ。
    - *対策*: パスごとの最大反復回数（`max_iter_per_pass=50`）、メタグラフ縮約の最大深度（`max_passes=20`）、およびモジュラリティ最小改善閾値（$\epsilon = 10^{-7}$）による強制収束制御。$m = 0$（孤立頂点のみ）の場合のゼロ除算安全ガード（各頂点を単独コミュニティとして即時返却）。
  - **Tampering (非決定論的クラスタリング・データ不整合)**:
    - *脅威*: Python 内部ハッシュシードや辞書反復順序の揺らぎによる、同一グラフに対するコミュニティ分割結果の実行時差異。
    - *対策*: タイブレーク（同点利得時）の頂点 ID ソート順評価、およびシード値（`seed: Optional[int]`）指定による決定論的・再現可能なコミュニティ検出保証。
  - **Information Disclosure (状態汚染・情報漏洩)**:
    - *対策*: コミュニティ検出インスタンス内部に実行時状態を残さず、`detect()` 呼び出しごとに独立したローカル状態を生成・初期化（ステートレス設計）。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/core/structures/community.py`](../../../src/core/structures/community.py) (新規: Pure-Python Louvain コミュニティ検出・モジュラリティ計算エンジン)
- [x] [`src/core/structures/__init__.py`](../../../src/core/structures/__init__.py): `LouvainCommunityDetector`, `detect_louvain_communities` の公開エクスポート
- [x] [`src/graph/traversal.py`](../../../src/graph/traversal.py): `detect_threat_communities()` 関数の追加および `GraphTraversal.detect_communities()` メソッドの追加
- [x] [`src/graph/engine.py`](../../../src/graph/engine.py): `PropertyGraphEngine.detect_communities()` および `community:<id>` グラフクエリフィルタの統合
- [x] [`src/graph/__init__.py`](../../../src/graph/__init__.py): `detect_threat_communities` のエクスポート追加
- [x] [`tests/core/test_community.py`](../../../tests/core/test_community.py) (新規: コミュニティ検出単体テスト、Zachary's Karate Club、Clique分離、解像度パラメータ検証)
- [x] [`tests/graph/test_community_detection.py`](../../../tests/graph/test_community_detection.py) (新規: CTI グラフ統合テスト、攻撃キャンペーンクラスタリング、クエリ実行検証)

---

## 4. 技術仕様 & アルゴリズム詳細 / Technical Specification

### 4.1 Newman-Girvan モジュラリティ $Q$ の定義
ノード数 $N$, エッジ総重み $m = \frac{1}{2} \sum_{i,j} A_{ij}$ の重み付き無向グラフにおいて、コミュニティ分割 $C = \{c_1, \dots, c_N\}$ のモジュラリティ $Q$ は以下で定義される：
$$Q = \frac{1}{2m} \sum_{i,j} \left[ A_{ij} - \gamma \frac{k_i k_j}{2m} \right] \delta(c_i, c_j)$$
ここで：
- $A_{ij}$: ノード $i, j$ 間のエッジ重み（無向化: $A_{ij} = A_{ji}$）
- $k_i = \sum_j A_{ij}$: ノード $i$ の重み付き次数（Degree）
- $\gamma > 0$: 解像度パラメータ（Resolution Parameter, デフォルト 1.0）
- $\delta(c_i, c_j)$: ノード $i$ と $j$ が同一コミュニティに属していれば 1, 異なれば 0

### 4.2 ノード移動に伴う局所モジュラリティ利得 $\Delta Q$
孤立したノード $i$ をコミュニティ $C$ へ移動した際のモジュラリティ変化量 $\Delta Q$ は以下の差分式で $O(1)$ 計算可能：
$$\Delta Q(i \to C) = \frac{k_{i, in}}{2m} - \gamma \frac{\Sigma_{tot} \cdot k_i}{2m^2}$$
- $k_{i, in} = \sum_{j \in C} A_{ij}$: ノード $i$ からコミュニティ $C$ 内のノード群への接続重み合計
- $\Sigma_{tot} = \sum_{j \in C} k_j$: コミュニティ $C$ 内の全ノードの次数合計（ノード $i$ を除く）

### 4.3 Louvain 法の 2 段階反復プロセス (Two-Phase Iteration)
1. **フェーズ 1 (Local Moving)**:
   - 各ノード $i$ を独立した初期コミュニティ $c_i = i$ に割り当てる。
   - 全ノードを反復走査し、ノード $i$ を現在のコミュニティから一時的に除外。
   - ノード $i$ の隣接ノードが属する各コミュニティ $C_{cand}$ への移動利得 $\Delta Q(i \to C_{cand})$ を計算。
   - 最大利得 $\max \Delta Q > \epsilon$ となるコミュニティへノード $i$ を移動（利得が正でなければ元のコミュニティへ維持）。
   - コミュニティの再割当てによる利得合計が $\epsilon$ 以下になるまでノード走査を反復。
2. **フェーズ 2 (Aggregation / Meta-Graph)**:
   - フェーズ 1 で得られた各コミュニティを 1 つの「メタ頂点（Super-node）」として縮約。
   - コミュニティ間のエッジ重みの和をメタエッジの重みとし、コミュニティ内部のエッジ重みの和をメタ頂点の自己ループ（Self-loop）とする。
   - メタグラフに対してフェーズ 1 を再帰的に適用。
3. **終了判定**:
   - 縮約後のパスでモジュラリティが改善しなくなった場合、または `max_passes` に達した場合に終了。
   - 各階層の縮約マッピングを元グラフの頂点 ID へ展開（Flatten）して最終的なコミュニティ ID（0 から連番）を確定。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/250-implement-louvain-community-detection-for-cti-graph`

1. **`src/core/structures/community.py` の実装**:
   - `LouvainCommunityDetector` クラスの設計:
     - `detect(adj: Dict[str, Dict[str, float]], resolution: float = 1.0, seed: Optional[int] = None) -> Dict[str, int]`
     - `modularity(adj: Dict[str, Dict[str, float]], partition: Dict[str, int], resolution: float = 1.0) -> float`
     - ヘルパー関数: `detect_louvain_communities(nodes: Iterable[str], edges: Iterable[Tuple[str, str, float]], resolution: float = 1.0) -> Dict[str, int]`
   - Xenon Grade A（各関数 CC <= 4）を満たすように `_one_level_optimize()`, `_build_meta_graph()`, `_renumber_communities()` 等に責務を分離。
   - ゼロ除算・空グラフ・単一頂点・自己ループの境界値ハンドリング。

2. **`src/core/structures/__init__.py` の更新**:
   - `LouvainCommunityDetector`, `detect_louvain_communities` を `__all__` に追加。

3. **`src/graph/traversal.py` への統合**:
   - `detect_threat_communities(engine: PropertyGraphEngine, edge_labels: Optional[List[str]] = None, weight_property: Optional[str] = None, resolution: float = 1.0) -> Dict[str, int]` を追加。
   - `GraphTraversal.detect_communities(resolution: float = 1.0) -> Dict[str, int]` メソッドを追加。

4. **`src/graph/engine.py` への統合**:
   - `PropertyGraphEngine.detect_communities(edge_labels: Optional[List[str]] = None, resolution: float = 1.0) -> Dict[str, int]` メソッドを追加。
   - `_format_cti_node()` において、コミュニティ情報が存在する場合は `"community": comm_id` 属性を付加可能にする。
   - `_dispatch_structured_query` に `community:<id>` 構文を追加し、特定コミュニティに属する頂点および誘導サブグラフの抽出をサポート。

5. **`src/graph/__init__.py` の更新**:
   - `detect_threat_communities` をエクスポート。

6. **テストスイートの作成**:
   - [`tests/core/test_community.py`](../../../tests/core/test_community.py):
     - 空グラフ・孤立頂点・自己ループの境界値。
     - 2 つの完全グラフ $K_5$ が 1 本のブリッジで接続されたトポロジーで正確に 2 コミュニティに分割されることの検証。
     - Zachary's Karate Club グラフ（34 ノード）におけるモジュラリティ $Q > 0.35$ の達成と分割妥当性の検証。
     - 解像度パラメータ $\gamma$ によるクラスタ粒度（高解像度で細分化、低解像度で大統合）の検証。
     - 決定論的シードによる結果再現性の検証。
   - [`tests/graph/test_community_detection.py`](../../../tests/graph/test_community_detection.py):
     - `PropertyGraphEngine` 上に構築した CTI 知識グラフ（脅威アクター、マルウェア、CWE、Technique）に対するコミュニティ検出テスト。
     - `execute_graph_query("community:0")` によるコミュニティ別サブグラフ抽出テスト。
     - 既存 `tests/graph/` および `tests/core/test_disjoint_set.py` の全 PASS 確認。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `src/core/structures/community.py` にゼロ外部依存で Louvain 法コミュニティ検出およびモジュラリティ計算が実装されていること。
- [x] `src/core/structures/__init__.py` から `LouvainCommunityDetector` および `detect_louvain_communities` がインポート可能であること。
- [x] `src/graph/traversal.py` および `src/graph/engine.py` からコミュニティ検出 API が利用可能であること。
- [x] `execute_graph_query("community:<id>")` でコミュニティ単位のサブグラフが Canvas 向けに正しく返却されること。
- [x] 新規テスト `tests/core/test_community.py` および `tests/graph/test_community_detection.py` を含む全テストが PASS すること。
- [x] `make check_format` および `make static_analysis` (xenon Grade A, mypy strict, flake8) がエラー 0 件で通過すること。

---

## 7. 検証手順 / Verification Procedure

1. **単体テスト・結合テスト実行**:
   ```bash
   .venv/bin/pytest tests/core/test_community.py tests/graph/test_community_detection.py -v
   .venv/bin/pytest tests/core/ tests/graph/ -v
   ```
2. **静的解析・型チェック・フォーマット検証**:
   ```bash
   make check_format
   make static_analysis
   ```
