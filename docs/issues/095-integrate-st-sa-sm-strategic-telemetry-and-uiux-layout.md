---
ID: 095
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] ST・SA・SM 戦略的テレメトリ統合と UI/UX 3タブレイアウト高度化 (ID: 095)

## 1. 概要 / Summary
13大専門エージェント（PM, ST, SA, SM, UI/UX, QA, AU, Sec, DB, Net, NLP, Emb, Edu）の合同審議に基づき、ダッシュボード（`site/dashboard.html`）およびバックエンド API（`src/web/gateway/handlers.py`）に対して、IT戦略・システム構造・サービス運用を網羅する高価値テレメトリ指標群を統合実装し、UI/UX デザイナー主導で 3 タブのレイアウトを洗練化する。

### 統合する 3 大専門指標群:
1. **📈 ST (IT Strategist: 戦略・投資対効果)**:
   - `💰 Token Savings & Cost ROI`: グラフ探索による LLM 推論コスト削減額（$換算）と圧縮率。
   - `🛡️ Emerging Threat Vectors`: 最新 arXiv 論文群から抽出された急上昇脅威手法 Top 5。
   - `📊 Executive Tier Coverage`: 01_per_run 〜 05_annual の要約生成・網羅完了率。
2. **⚙️ SA (Systems Architect: 構造・整合性・テールレイテンシ)**:
   - `⚡ Traversal Tail Latency (p95 / p99)`: 知識グラフ探索時の最悪ケースレイテンシ実測。
   - `🧩 Graph Clustering & Density`: オントロジー結合係数および孤立ノード率。
   - `🔄 WAL & IPC Sync Lag`: プロセス間通信および先行書き込みログの同期遅延。
3. **🛎️ SM (IT Service Manager: 運用・SLA/SLO)**:
   - `🎯 Pipeline SLO Compliance`: 4x Daily 定期バッチの納期遵守率（99.9% 目標）。
   - `🩺 Upstream API Resilience`: arXiv API レートリミット回避率（HTTP 429 回避）。
   - `⏱️ Worker MTTR`: プロセス異常検知から Pre-Fork 自動復元までの自己修復時間（<0.2s）。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md)
  - [docs/designs/DSN-12-process_supervisor_and_arbiter.md](../designs/DSN-12-process_supervisor_and_arbiter.md)
  - [docs/designs/DSN-10-observability_and_eval_framework.md](../designs/DSN-10-observability_and_eval_framework.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [site/dashboard.html](../../site/dashboard.html): UI/UX 3タブレイアウトの高度化と新 KPI パネルの配置
- [ ] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py): `/api/graph/mesh` レスポンスへの ST/SA/SM メトリクス追加
- [ ] [tests/web/test_dashboard_html.py](../../tests/web/test_dashboard_html.py): 新規メトリクス要素・タブ整合性の単体テスト
- [ ] [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md): アーキテクチャ図および設計仕様書の同期

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/095-integrate-st-sa-sm-strategic-telemetry-and-uiux-layout`

1. **バックエンド API 拡張 (`src/web/gateway/handlers.py`)**:
   - `_introspect_strategic_metrics()` ヘルパーを新設し、ST/SA/SM の実測データを集計。
   - `/api/graph/mesh` レスポンスに `strategic_telemetry` オブジェクトを統合。
2. **UI/UX 3タブレイアウト高度化 (`site/dashboard.html`)**:
   - **Tab 1 (`📚 Product`)**: ST 向け「💰 Token Cost ROI ($換算)」および「🛡️ Emerging Threat Vectors Top 5」をサイドパネルに美しくレイアウト。
   - **Tab 2 (`⚙️ System`)**: SM 向け「🎯 Pipeline SLO (4x Daily 99.9%)」「🩺 Upstream Resilience」「🔄 WAL Sync Lag」を追加。
   - **Tab 3 (`🕹️ Supervisor`)**: SA 向け「⚡ p95/p99 Tail Latency」「⏱️ Worker MTTR (<0.2s)」を Arbiter カードに統合。
3. **初期表示・同期整合性の徹底（AU 監査基準）**:
   - 全新規要素の初期 HTML は `--` プレースホルダーとし、`syncLiveMesh()` で完全動的描画。
4. **テスト・品質ゲート検証**:
   - `make format`, `make static_analysis`, `pytest tests/web/` の全パス。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `docs/issues/095-integrate-st-sa-sm-strategic-telemetry-and-uiux-layout.md` が作成され、`docs/issues/README.md` に登録されていること。
- [ ] ST / SA / SM の提言メトリクスが 3 タブに適切にレイアウトされ、Swiss-Style デザインが維持されていること。
- [ ] `/api/graph/mesh` から本物の実測データが配信され、ダミー値が一切存在しないこと。
- [ ] `pytest tests/web/test_dashboard_html.py` が 100% パスすること。
