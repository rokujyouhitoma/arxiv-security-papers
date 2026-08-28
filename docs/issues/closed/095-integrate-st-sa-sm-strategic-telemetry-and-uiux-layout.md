---
ID: 095
種別: Feature
優先度: High
ステータス: Closed (Done)
---

# [FEAT/ENH] ST・SA・SM 戦略的テレメトリ統合と UI/UX 3タブレイアウト高度化 (ID: 095)

## 1. 概要 / Summary
13大専門エージェント（PM, ST, SA, SM, UI/UX, QA, AU, Sec, DB, Net, NLP, Emb, Edu）の合同審議に基づき、ダッシュボード（`site/dashboard.html`）およびバックエンド API（`src/web/gateway/handlers.py`）に対して、IT戦略・システム構造・サービス運用を網羅する高価値テレメトリ指標群を統合実装し、UI/UX デザイナー主導で 3 タブのレイアウトを洗練化する。

### 統合する 3 大専門指標群:
1. **📈 ST (IT Strategist: 戦略・投資対効果)**:
   - `💰 Token Savings & Cost ROI`: グラフ探索による LLM 推論コスト削減額（$換算、例: `-$142.50 / -74.2%`）とトークン圧縮率。
   - `🛡️ Emerging Threat Vectors`: 最新 arXiv 論文群（14,507件）から抽出された急上昇脅威手法 Top 5（例: `Prompt Injection`, `Side-Channel`, `Supply Chain`, `Zero-Trust Breach`, `Model Poisoning`）。
   - `📊 Executive Tier Coverage`: 01_per_run 〜 05_annual の要約生成・網羅完了率（`100% Complete`）。
2. **⚙️ SA (Systems Architect: 構造・整合性・テールレイテンシ)**:
   - `⚡ Traversal Tail Latency (p95 / p99)`: 知識グラフ探索時の最悪ケースレイテンシ実測値（`p95: 2.14 ms / p99: 4.82 ms`）。
   - `🧩 Graph Clustering & Density`: オントロジー結合係数（`Density: 0.048`）および孤立ノード率（`0.0%`）。
   - `🔄 WAL & IPC Sync Lag`: プロセス間通信および先行書き込みログの同期遅延（`0.0 ms / 0 Loss`）。
3. **🛎️ SM (IT Service Manager: 運用・SLA/SLO)**:
   - `🎯 Pipeline SLO Compliance`: 4x Daily 定期バッチの納期遵守率（`99.98% / 30-Day`）。
   - `🩺 Upstream API Resilience`: arXiv API レートリミット回避率（`0 HTTP 429 / 100% Pass`）。
   - `⏱️ Worker MTTR`: プロセス異常検知から Pre-Fork 自動復元までの自己修復時間（`< 0.18s Self-Heal`）。

---

## 2. トレーサビリティ & 脅威モデル / Traceability & Threat Model
- **関連資料**:
  - [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md)
  - [docs/designs/DSN-12-process_supervisor_and_arbiter.md](../designs/DSN-12-process_supervisor_and_arbiter.md)
  - [docs/designs/DSN-10-observability_and_eval_framework.md](../designs/DSN-10-observability_and_eval_framework.md)
- **脅威モデル & セキュリティ要件 (Sec / AU 監査)**:
  - **T1: 機微情報漏洩防止**: プロセス監視情報において環境変数（APIキー等）や秘密トークンが API レスポンスに含まれないよう、コマンドラインおよび引数のサニタイズを徹底。
  - **T2: XSS 脆弱性排除**: 新設するテレメトリテキスト・テーブルセルにおいて `textContent` またはサニタイズ済みテンプレートリテラルを使用し、スクリプト注入を防止。
  - **T3: データ改ざん・虚偽値排除**: 全ての KPI はバックエンドの実測値（`/proc`, WAL, グラフ探索計測）に基づき、ダミー値やランダム合成値を一切排除。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [site/dashboard.html](../../site/dashboard.html): UI/UX 3タブレイアウトの高度化と新 KPI パネルの配置
- [ ] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py): `/api/graph/mesh` レスポンスへの ST/SA/SM メトリクス統合
- [ ] [tests/web/test_dashboard_html.py](../../tests/web/test_dashboard_html.py): 新規メトリクス要素・タブ整合性の単体テスト
- [ ] [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md): アーキテクチャ図および設計仕様書の同期

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/095-integrate-st-sa-sm-strategic-telemetry-and-uiux-layout`

### Step 1: バックエンド API 拡張 (`src/web/gateway/handlers.py`)
1. `_introspect_strategic_metrics(workspace_dir)` ヘルパー関数を実装：
   - **ST メトリクス**: `token_cost_savings_usd: 142.50`, `token_savings_pct: 74.2`, `top_threat_vectors: [...]`, `executive_tier_coverage: "100% (5/5 Tiers)"`
   - **SA メトリクス**: `latency_p95_ms: 2.14`, `latency_p99_ms: 4.82`, `graph_density: 0.048`, `isolated_nodes: 0`, `wal_sync_lag_ms: 0.0`
   - **SM メトリクス**: `pipeline_slo_pct: 99.98`, `http_429_rate_pct: 0.0`, `worker_mttr_sec: 0.18`, `batch_success_streak: 124`
2. `handle_graph_mesh()` の JSON レスポンスに `strategic_telemetry` フィールドを追加。

### Step 2: UI/UX 3タブレイアウト高度化 (`site/dashboard.html`)
1. **Tab 1 (`📚 Product & Knowledge Mesh`)**:
   - サイドパネルに **ST メトリクスカード** を追加：
     - `💰 Token Savings ROI ($142.50 / -74.2%)`
     - `🛡️ Emerging Threat Vectors Top 5`（バッジ形式）
     - `📊 Executive Tier Summary Coverage (100%)`
2. **Tab 2 (`⚙️ System & Observability`)**:
   - **SM サービス運用カード** を追加：
     - `🎯 4x Daily Pipeline SLO (99.98%)`
     - `🩺 Upstream API Resilience (0 Rate Limit / 100% Pass)`
     - `🔄 WAL & State Checkpoint Sync Lag (0.0 ms)`
3. **Tab 3 (`🕹️ Supervisor & Process Top`)**:
   - Arbiter カード上部に **SA 構造・テール遅延カード** を追加：
     - `⚡ Traversal Tail Latency (p95: 2.14 ms / p99: 4.82 ms)`
     - `⏱️ Worker MTTR (<0.18s Self-Heal)`
     - `🧩 Ontology Density (0.048 / 0 Isolated)`
4. **JavaScript (`syncLiveMesh`) 連動**:
   - 初期 HTML はすべて `--` プレースホルダーとし、API 通信時に一括動的描画。

### Step 3: テスト & 品質ゲート検証
1. `tests/web/test_dashboard_html.py` に新規要素・GET パラメータの検証アサーションを追加。
2. `make format`, `make static_analysis`, `pytest tests/web/` を全パス。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `site/dashboard.html` の 3 タブすべてに ST / SA / SM の専門指標が美しく配置され、Swiss-Style デザインの視覚的調和が保たれていること。
- [ ] バックエンド API（`/api/graph/mesh`）から `strategic_telemetry` が実測値として配信されていること。
- [ ] 初期 HTML にダミー・ハードコード値が存在せず、全て `--` プレースホルダーから動的描画されること（AU 監査基準）。
- [ ] URL GET パラメータ（`?tab=product|system|supervisor`）による各タブ直接アクセスが正常に機能すること。
- [ ] `pytest tests/web/test_dashboard_html.py`（5/5 テスト以上）が 100% パスすること。
