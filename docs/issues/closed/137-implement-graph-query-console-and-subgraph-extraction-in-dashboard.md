---
ID: 137
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] /dashboard Product タブにおける CTI グラフクエリ・コンソールおよびサブグラフ抽出・ハイライト機能の実装 (ID: 137)

## 1. 概要 / Summary
`/dashboard` の Product タブ（可視化キャンバス画面）において、全14,616頂点・1,449エッジの巨大な CTI ナレッジグラフ（`PropertyGraphEngine`）から、特定の脅威シナリオ、脆弱性波及影響（Blast Radius / Multi-hop Impact）、研究空白地帯（Research Gaps）、およびキーワード連鎖経路をインタラクティブに抽出・可視化するための「グラフクエリ・コンソール（Graph Query Console）」およびサブグラフ抽出エンジンを実装する。

---

## 2. トレーサビリティ / Traceability
- [DSN-14: Graph Engineering Dashboard (Section 11)](../../designs/DSN-14-graph_engineering_dashboard.md)
- [DSN-09: Web Gateway & Presentation (Section 7)](../../designs/DSN-09-web_gateway_and_presentation.md)
- [Issue 135: arXivセキュリティ論文・MITRE ATT&CK・CWEナレッジグラフデータ基盤および /dashboard インタラクティブグラフ可視化の実装](closed/135-implement-paper-attck-cwe-knowledge-graph-and-dashboard-visualization.md)
- [Issue 136: Context Meshにおけるエンティティ名寄せ（Entity Resolution）・重複排除（Deduplication）と論文横断グラフ結合の実装](closed/136-implement-context-mesh-entity-resolution-and-deduplication.md)

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Modeling & Mitigations)
- **T-137-01: クエリ入力経由のインジェクション・ReDoS攻撃 (CWE-20 / CWE-400)**
  - *脅威*: ユーザが入力するクエリ文字列に過度なワイルドカードや正規表現メタ文字が含まれることによる CPU 枯渇・サービス停止。
  - *対策*: クエリパーサーは厳格なトークン分割（プレフィックス判定: `gaps`, `cwe:`, `ego:`, `match:`, `path:`）と英数字ハイフン正規化を用い、未検証の動的 eval / regex コンパイルを完全排除。クエリ長は128文字に制限。
- **T-137-02: 巨大サブグラフ返却によるブラウザ Canvas クラッシュ (DoS)**
  - *脅威*: 大量ノードを一度に Canvas に流し込むことによるフレームレート低下（< 15 FPS）。
  - *対策*: サブグラフ抽出件数を `limit` パラメータで最大 100 ノードに制限し、バックエンド側で上限を厳格クランプ。
- **T-137-03: DOM / HTML XSS (CWE-79)**
  - *脅威*: クエリ結果バッジやノードツールチップに悪意あるスクリプトが混入する。
  - *対策*: `escapeHtml` ユーティリティにより全動的テキストをサニタイズ。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/graph/engine.py` (`PropertyGraphEngine.execute_graph_query` メソッドの追加)
- [x] `src/web/gateway/handlers.py` (`handle_graph_query` REST エンドポイントハンドラの実装)
- [x] `src/web/gateway/app.py` (`/api/graph/query` ルーティング登録)
- [x] `site/dashboard.html` (クエリバー、クイックプリセットボタン、サブグラフ連動描画スクリプト)
- [x] `tests/graph/test_graph_query.py` (クエリ実行エンジン単体テスト)
- [x] `tests/web/test_dashboard_graph_query.py` (REST API & UI 結合テスト)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/137-implement-graph-query-console-and-subgraph-extraction`

1. **グラフクエリパーサー・実行エンジンの実装 (`src/graph/engine.py`)**:
   - `execute_graph_query(query: str, limit: int = 50) -> Dict[str, Any]`:
     - `gaps`: `get_research_gaps()` を呼び出し、未対策の技術ノード群とその周辺を抽出。
     - `cwe:<cwe_id>`: `get_cwe_impact(cwe_id)` を呼び出し、多段階波及影響サブグラフを抽出。
     - `ego:<node_id> [hops]`: `get_neighborhood(node_id, max_hops)` で ego-network を抽出。
     - `match:<term>`: ノードプロパティ（タイトル・名前・説明）のキーワード部分一致ノードと隣接エッジを抽出。
     - `path:<src>-><dst>`: `src` から `dst` への最短到達経路（BFS）を抽出。
2. **REST API Gateway ハンドラの実装 (`src/web/gateway/handlers.py`)**:
   - `GET /api/graph/query?q=<query_string>&limit=50`:
     - クエリパース、上限クランプ（1〜100）、JSON レスポンス生成。
3. **UI / Dashboard Canvas 連動の実装 (`site/dashboard.html`)**:
   - Product タブのグラフ上部にスタイリッシュな Glassmorphic クエリコンソールを配置。
   - 4 つのクイックプリセットボタン:
     - `[ 🚨 Research Gaps ]` (q='gaps')
     - `[ 🛡️ CWE-20 Impact ]` (q='cwe: CWE-20')
     - `[ 🤖 Prompt Injection Ego ]` (q='ego: AttackTechnique:AML.T0054 2')
     - `[ 🔐 Post-Quantum Crypto ]` (q='match: quantum')
     - `[ 🔄 Reset All ]` (全表示へリセット)
   - クエリ実行時に Canvas 上のノード・エッジを置換し、物理シミュレーションを再初期化。
4. **テスト・品質検証**:
   - 単体テスト・統合テスト作成、`make check_format`、`make static_analysis` (Xenon Rank A, Mypy Strict)。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `PropertyGraphEngine.execute_graph_query` が `gaps`, `cwe:`, `ego:`, `match:`, `path:` クエリを正しくパースしてサブグラフを返却すること
- [x] `GET /api/graph/query` エンドポイントが正常に動作し、パラメータクランプおよびエラーハンドリングが機能すること
- [x] `site/dashboard.html` の Product タブにクエリバーとプリセットボタンが設置され、クエリ結果が Canvas 上にシームレスに再描画されること
- [x] 全品質ゲート（Xenon Rank A, Flake8 0 errors, Mypy Strict 0 errors, pytest 100% PASS）を充足すること
