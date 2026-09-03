---
ID: 135
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] arXivセキュリティ論文・MITRE ATT&CK・CWEナレッジグラフデータ基盤および /dashboard インタラクティブグラフ可視化の実装 (ID: 135)

## 1. 概要 / Summary
外部依存（NetworkX, Kuzu, Neo4j, Pydantic, 外部LLM等）を一切排除したゼロ外部依存方針（Standard Library Only）のもと、本リポジトリで収集・管理する 14,000 件超の arXiv 論文データ（`:Paper`）と MITRE ATT&CK（`:AttackTechnique`）、CWE（`:CWE`）を接続するプロパティナレッジグラフ基盤を内製 `PropertyGraphEngine`（`src/graph/`）上に構築・永続化する。
さらに、構築されたナレッジグラフを `/dashboard`（`site/dashboard.html`）の HTML5 2D Canvas 力学モデル上にリアルタイムでインタラクティブ可視化（ノード種別フィルタリング、2-Hop 近傍展開、研究ギャップハイライト）し、Web ゲートウェイ（`src/web/`）の API エンドポイント（`/api/graph/cti-mesh`）とシームレスに連携させる。

---

## 2. トレーサビリティ / Traceability
- [[MNG-02] MITRE ATT&CK & CWE 統合ナレッジグラフ対応台帳](../processes/MNG-02-mitre_attack_cwe_ledger.md)
- [[REQ-03] プロジェクトユースケース台帳 (UC-RES-02, UC-OPS-01, UC-DEV-02, UC-NCO-04, UC-NCO-06, UC-NCO-13)](../requirements/REQ-03-use_case_ledger.md)
- [DSN-14: Graph Engineering Dashboard (Section 11)](../../docs/designs/DSN-14-graph_engineering_dashboard.md)
- [DSN-17: セキュリティ知識オントロジー (Section 10)](../../docs/designs/DSN-17-security_knowledge_ontology.md)
- [DSN-18: ゼロ侵襲型 Property Graph Database Engine (Section 8)](../../docs/designs/DSN-18-property_graph_database_engine.md)
- [DSN-09: Web Gateway & Presentation](../../docs/designs/DSN-09-web_gateway_and_presentation.md)
- [Issue 128: PRIMUS 知見に基づく CWE/CVSS/ATT&CK 精密マッピングエンジン](closed/128-implement-primus-cti-rcm-vsp-ate-precision-mapping-engine.md)
- [Issue 129: 論文引用ネットワークと CTI ナレッジグラフを統合したマルチホップ GraphRAG パイプライン](closed/129-implement-citation-network-cti-graphrag-pipeline.md)

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Modeling & Mitigations)
- **T-135-01: グラフ多段探索における循環参照・再帰爆発 (DoS)**
  - *脅威*: 閉路（Cycles）や密結合サブグラフの探索時に無限ループや再帰スタックオーバーフローが発生し、API ワーカーがハングアップする。
  - *対策*: `visited` セットによる訪問済み頂点の厳格管理、および探索最大深さ（`max_depth=3`）と最大展開ノード数（`limit=500`）の強制制約を適用。
- **T-135-02: Web Gateway API (`/api/graph/cti-mesh`) での巨大ペイロード過負荷**
  - *脅威*: 全 14,000 件の論文ノードを一括シリアライズすることでメモリ逼迫および通信遅延が発生する。
  - *対策*: クエリパラメータ（`?limit=100&tier=silver&include_gaps=true`）によるページネーションとフィルタリングをサポートし、デフォルトで重要度の高い上位サブグラフに制限。
- **T-135-03: ダッシュボード UI での DOM-based XSS**
  - *脅威*: 悪意ある論文タイトルや概要テキストが Canvas ツールチップおよび詳細カードに注入され、XSS が成立する。
  - *対策*: DOM 描画時に `escapeHtml` ユーティリティを通じ、生 HTML の `innerHTML` 直接代入を完全禁止。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/graph/structures.py` (Paper, AttackTechnique, CWE ノードおよびリレーション構造体定義・バリデーション)
- [x] `src/graph/engine.py` (ナレッジグラフの永続化、逆方向 CSR 隣接インデックス、多段走査ヘルパー)
- [x] `src/ontology/taxonomy.py` (ATT&CK / CWE / ATLAS マスターデータ辞書および正規化)
- [x] `src/ontology/extractor.py` (OKF 論文からの ATT&CK / CWE ハイブリッド抽出・エッジ生成)
- [x] `scripts/seed_ontologies.py` (CWE Top 25 / ATT&CK Enterprise & ATLAS マスターシードスクリプト)
- [x] `src/ontology/seeder.py` (オントロジーマスター定義および PropertyGraphEngine シードエンジン)
- [x] `src/web/gateway/handlers.py` (`/api/graph/cti-mesh` REST エンドポイント追加)
- [x] `site/dashboard.html` (Canvas 2D 力学演算、配色トークン、2-Hop展開、研究ギャップ点滅表示)
- [x] `tests/graph/test_cti_graph.py` (グラフ構築・シード・多段走査・ギャップ抽出単体テスト)
- [x] `tests/web/test_dashboard_cti_graph.py` (Web Gateway `/api/graph/cti-mesh` ハンドラー統合テスト)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/135-implement-paper-attck-cwe-knowledge-graph-and-dashboard-visualization`

1. **ステップ 1: オントロジーマスターシードの実装 (`scripts/seed_ontologies.py`, `src/ontology/seeder.py`)**:
   - `MNG-02` 台帳に定義された ATT&CK（Enterprise & ATLAS）および CWE（Top 25 + 低レイヤ・暗号・AI）のマスター定義を辞書化。
   - `PropertyGraphEngine` に対し、一意キー（`AttackTechnique:Txxxx`, `Vulnerability:CWE-xxx`）で Vertex を UPSERT。
   - CWE 階層（`CWE-Class` $\rightarrow$ `CWE-Base`）および ATT&CK $\leftrightarrow$ CWE 標準因果リレーション（`[:EXPLOITS]` / `[:LEVERAGES]`）を Edge としてシード。
2. **ステップ 2: 論文ハイブリッド抽出とグラフ結合 (`src/ontology/extractor.py`)**:
   - OKF Markdown / JSON メタデータから、正規表現（Gold Tier: $\ge 0.90$）およびセマンティック類似度（Silver Tier: $\ge 0.70$）で ATT&CK/CWE を抽出。
   - `PropertyGraphEngine` に `:Paper` 頂点を追加し、`EXPLOITS`, `MITIGATES`, `DISCLOSES` エッジを生成・永続化（`outputs/database/graph.db`）。
3. **ステップ 3: 多段波及探索 ＆ 研究ギャップ検出メソッド (`src/graph/engine.py`)**:
   - `get_cwe_impact(cwe_id, max_depth=2)`: CWE 起点の波及攻撃手法および実証論文の抽出。
   - `get_research_gaps()`: 次数 0（接続 `:Paper` が 0 件）の孤立 ATT&CK / CWE ノード一覧を高速抽出。
4. **ステップ 4: Web ゲートウェイ API の追加 (`src/web/gateway/handlers.py`)**:
   - `/api/graph/cti-mesh` を追加。クエリパラメータ `limit`, `focus_node`, `tier` に対応し、ノード一覧（ID, label, type, properties）とエッジ一覧（src, dst, label, weight, tier）を JSON 形式で配信。
5. **ステップ 5: `/dashboard` Canvas 2D インタラクティブ可視化 (`site/dashboard.html`)**:
   - 配色トークン（`:Paper`: Blue `#3B82F6`, `:AttackTechnique`: Crimson `#EF4444`, `:CWE`: Amber `#F59E0B`）を反映。
   - ノード種別トグルボタン（論文表示/非表示、ATT&CK表示/非表示、CWE表示/非表示）を追加。
   - ノードクリックによる「2-Hop 近傍展開」とフローティング詳細カード描画。
   - 「研究ギャップ強調」ボタンにより、孤立ノードをゴールド枠線パルス（Pulsing Gold Border）で強調。
6. **ステップ 6: 単体テスト・統合テストと品質ゲート検証**:
   - `tests/graph/test_cti_graph.py` および `tests/web/test_dashboard_cti_graph.py` を作成。
   - `make format`, `make static_analysis` (Xenon Rank A, Mypy Strict), `pytest` 100% PASS。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 外部依存ゼロ（標準ライブラリのみ）で ATT&CK / CWE マスターデータおよび論文リレーションが `PropertyGraphEngine` に登録・永続化されること
- [x] `scripts/seed_ontologies.py` により初期ノード（ATT&CK, CWE）と因果エッジが正常にシードできること
- [x] `/api/graph/cti-mesh` が適切な JSON サブグラフ（nodes, edges, stats, research_gaps）を返却すること
- [x] `/dashboard` を開いた際、Paper-ATT&CK-CWE の力学モデルグラフが Canvas 2D 上に 60 FPS で滑らかに描画されること
- [x] ノード種別フィルタリング、2-Hop 近傍展開、および研究ギャップ強調表示が完全に機能すること
- [x] 全品質ゲート（Xenon Rank A, Flake8 0 errors, Mypy Strict 0 errors, pytest 100% PASS）を充足すること
