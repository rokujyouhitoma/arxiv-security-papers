---
ID: 135
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] arXivセキュリティ論文・MITRE ATT&CK・CWEナレッジグラフデータ基盤および /dashboard インタラクティブグラフ可視化の実装 (ID: 135)

## 1. 概要 / Summary
外部依存（NetworkX, Kuzu, Neo4j, Pydantic, 外部LLM等）を一切排除したゼロ外部依存方針のもと、本リポジトリで収集・管理する 14,000 件超の arXiv 論文データ（`:Paper`）と MITRE ATT&CK（`:AttackTechnique`）、CWE（`:CWE`）を接続するプロパティナレッジグラフ基盤を内製 `PropertyGraphEngine`（`src/graph/`）上に構築・永続化する。
さらに、構築されたナレッジグラフを `/dashboard`（`site/dashboard.html`）の HTML5 2D Canvas 力学モデル上にリアルタイムでインタラクティブ可視化（ノード種別フィルタリング、2-Hop 近傍展開、研究ギャップハイライト）し、Web ゲートウェイ（`src/web/`）の API エンドポイント（`/api/graph/cti-mesh`）とシームレスに連携させる。

---

## 2. トレーサビリティ / Traceability
- [DSN-14: Graph Engineering Dashboard (Section 11)](../../docs/designs/DSN-14-graph_engineering_dashboard.md)
- [DSN-17: セキュリティ知識オントロジー (Section 10)](../../docs/designs/DSN-17-security_knowledge_ontology.md)
- [DSN-18: ゼロ侵襲型 Property Graph Database Engine (Section 8)](../../docs/designs/DSN-18-property_graph_database_engine.md)
- [DSN-09: Web Gateway & Presentation](../../docs/designs/DSN-09-web_gateway_and_presentation.md)
- [Issue 128: PRIMUS 知見に基づく CWE/CVSS/ATT&CK 精密マッピングエンジン](128-implement-primus-cti-rcm-vsp-ate-precision-mapping-engine.md)
- [Issue 129: 論文引用ネットワークと CTI ナレッジグラフを統合したマルチホップ GraphRAG パイプライン](129-implement-citation-network-cti-graphrag-pipeline.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/graph/engine.py` (ナレッジグラフの永続化および隣接リスト走査)
- [ ] `src/graph/structures.py` (Paper, AttackTechnique, CWE ノードおよびリレーション構造体)
- [ ] `src/ontology/taxonomy.py` (ATT&CK / CWE マスターデータ辞書)
- [ ] `src/ontology/extractor.py` (論文メタデータからの ATT&CK / CWE ハイブリッド抽出)
- [ ] `scripts/seed_ontologies.py` (ATT&CK / CWE マスターデータシードスクリプト)
- [ ] `src/web/gateway/handlers.py` (`/api/graph/cti-mesh` エンドポイント追加)
- [ ] `site/dashboard.html` (2D Canvas 力学モデル描画、配色トークン、2-Hop展開、ギャップ表示)
- [ ] `tests/graph/test_cti_graph.py` (グラフ構築・走査・シード単体テスト)
- [ ] `tests/web/test_dashboard_cti_graph.py` (ダッシュボード API & Canvas 可視化検証)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/135-implement-paper-attck-cwe-knowledge-graph-and-dashboard-visualization`

1. **グラフデータモデリングとシードスクリプトの実装 (`Task 1 & 2`)**:
   - `src/graph/structures.py` と `src/ontology/schema.py` を統合し、`:Paper`, `:AttackTechnique`, `:CWE` の一意性制約付きノード生成を確立。
   - `scripts/seed_ontologies.py` を新設し、CWE Top 25 および ATT&CK 核心テクニックの初期マスターノード・階層エッジを `PropertyGraphEngine` に一括投入。
2. **論文エンティティ・リレーション抽出・結合 (`Task 3`)**:
   - `src/ontology/extractor.py` にて正規表現抽出（`CWE-xxx`, `Txxxx`）とセマンティック類似度マッピングを組み合わせ、OKF 論文から `EXPLOITS`, `MITIGATES`, `DISCLOSES` リレーションを自動生成してグラフにマージ（UPSERT）。
3. **特化クエリエンジンの実装 (`Task 4`)**:
   - CWE $\rightarrow$ ATT&CK $\rightarrow$ Paper の多段波及探索、および被接続論文次数が 0 の研究ギャップ抽出メソッドを実装。
4. **`/dashboard` インタラクティブ可視化と Web Gateway 統合 (`Dashboard Integration`)**:
   - `src/web/gateway/handlers.py` に `/api/graph/cti-mesh` を追加。
   - `site/dashboard.html` の Canvas 2D 物理演算エンジンを拡張し、Blue (:Paper) / Crimson (:AttackTechnique) / Amber (:CWE) の配色トークンと 2-Hop 近傍展開、研究ギャップ点滅モードを配備。
5. **品質ゲート検証**:
   - `make format`, `make static_analysis` (Xenon Rank A, Mypy Strict), `pytest` 100% PASS。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 外部依存ゼロ（標準ライブラリのみ）で ATT&CK / CWE マスターデータおよび論文リレーションが `PropertyGraphEngine` に登録・永続化されること
- [ ] `scripts/seed_ontologies.py` により初期ノードと階層エッジが正常に投入できること
- [ ] `/dashboard` をブラウザで開いた際、Paper-ATT&CK-CWE の力学モデルグラフが Canvas 2D 上に描画されること
- [ ] ノード種別フィルタリングおよびノードクリックによる 2-Hop 近傍展開がスムーズに動作すること
- [ ] 研究ギャップ（論文が未接続の ATT&CK/CWE）が視覚的に識別可能であること
- [ ] 全品質ゲート（Xenon Rank A, Flake8, Mypy Strict, pytest）を 100% パスすること
