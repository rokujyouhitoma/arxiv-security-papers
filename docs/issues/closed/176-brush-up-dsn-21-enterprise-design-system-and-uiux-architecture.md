---
ID: 176
種別: Documentation / UIUX / Architecture
優先度: High
ステータス: Closed
---

# [DOC/UIUX] DSN-21 (エンタープライズ統合デザインシステム ＆ クラウドコンソール UI 包括設計書) の直近作業および UI/UX 全観点からの包括的ブラッシュアップ (ID: 176)

## 1. 概要 / Summary

本 Issue は、ユーザーからの「UI/UX には強いこだわりをもって、製品を作りこんでほしい。UI/UX はユーザーの利便性や印象にきわめて重大な影響を及ぼすためである。UIUX と PM ST SA QA は DSN-21 を直近の作業やあらゆる観点からブラッシュアップせよ」という強力な要請と方針に基づき、**UI/UX & Documentation Designer エージェントが主査・リード**を務め、**Project Manager (PM)**、**IT Strategist (ST)**、**Systems Architect (SA)**、**Software Quality Assurance Specialist (QA)** が集結して実施する包括的設計書ブラッシュアップタスクである。

包括設計書 **[DSN-21 (エンタープライズ統合デザインシステム ＆ クラウドコンソール UI 包括設計書)](../designs/DSN-21-enterprise_design_system_and_unified_console.md)** は、Issue 167 で策定されたが、その後に進行した以下の直近作業群（Issue 167〜175）における膨大な実装・知見・UI/UX 精緻化成果を包含しきれていなかった。本 Issue により、最新の実装実態と最先端のエンタープライズ UI/UX 哲学を完全に融合した、業界最高水準の設計標準書へと昇華させる。

### 直近作業（Issues 167〜175）からの反映対象事項
1. **CTI ナレッジグラフ専用ワークスペース (dashboard.html) の UI/UX アーキテクチャ標準化**:
   - Viewport 100vh 収束モデル（`overflow: hidden; height: 100vh;`）による画面枠外はみ出し・二重スクロールの完全解消（Issue 174, 175）。
   - 固定フッター（Pinned Viewport Footer: 36px）の常時表示化と同期テレメトリ・クイックアクション統合（Issue 175）。
   - CTI 凡例（Cluster Legend: `#contextLegend` / `#ctiLegend`）の左上（Top-Left）フローティングオーバーレイ再配置（Issue 175）。
   - Canvas ズームインジケーター（100% 基準倍率バッジ）および多機能ズームコントロールオーバーレイ（`+`, `−`, `⟲`、キーボードホットキー `+`, `-`, `0`）（Issue 175）。
   - コントロールデッキ折りたたみトグル（`#btnToggleControlDeck`, `D` キー）による Canvas 描画面積の最大化（Issue 174）。
   - ヘッダー折りたたみトグル（`header.header-hidden`, `H` キー）による `calc(100vh - 36px)` 没入型フルスクリーン Canvas（Issue 170）。
2. **多方向グラスモルフィック・チップヒント（CSS Pure Tooltip）体系の標準化**:
   - JavaScript イベントリスナーおよび DOM 増殖ゼロの Pure CSS `data-tooltip` 設計（Issue 166, 175）。
   - 多方向配置仕様（`data-tooltip-pos="top"` / `"bottom"` / `"right"` / `"left"`）および画面端クリッピング保護アラインメント（`data-tooltip-align="left"` / `"right"`）。
   - スイススタイル・ダークグラスモルフィズム（`backdrop-filter: blur(16px);`、微細ホワイト透過ボーダー、多層ドロップシャドウ）。
3. **6大機能タブの Single-Page Portal (index.html) への統合・移植アーキテクチャ**:
   - Issue 169 で実施された Product & ROI (Tab 4)、System & Observability (Tab 5)、Supervisor & Process Top (Tab 6) の完全統合と、単一ヘッダー・デザインシステム統一（Issue 170）。
4. **統一操作ガイド・ヘルプドロワー体系**:
   - 右スライド式グラスモルフィック・ドロワー（`#helpDrawer`）によるキーボードショートカット一覧・操作ガイダンスの一元提供（Issue 168, 171）。
5. **UI/UX 哲学・認知負荷軽減・アクセシビリティの深化**:
   - W3C WCAG 2.1 AAA 準拠のコントラスト比検証、フォントレンダリング、タッチ/クリックの微細フィードバック（Haptic transitions）、ステータスカラーバー心理学。

---

## 2. トレーサビリティ / Traceability

- **対象設計書**: 
  - [docs/designs/DSN-21-enterprise_design_system_and_unified_console.md](../designs/DSN-21-enterprise_design_system_and_unified_console.md)
- **関連 Issue 群**:
  - [167-implement-enterprise-cloud-console-ui-and-design-system-unification.md](closed/167-implement-enterprise-cloud-console-ui-and-design-system-unification.md) (エンタープライズ統合コンソール基盤)
  - [168-fix-server-blocking-on-sse-streaming-and-enhance-observability.md](closed/168-fix-server-blocking-on-sse-streaming-and-enhance-observability.md) (可観測性・WSGI 安定化)
  - [169-port-product-system-supervisor-views-to-index-console.md](closed/169-port-product-system-supervisor-views-to-index-console.md) (3画面の index.html への統合移植)
  - [170-unify-dashboard-header-with-index-and-retain-graph-only.md](closed/170-unify-dashboard-header-with-index-and-retain-graph-only.md) (ヘッダー統一 & Graph 単一化)
  - [171-unify-index-help-guide-drawer-design-with-dashboard.md](closed/171-unify-index-help-guide-drawer-design-with-dashboard.md) (ヘルプドロワー統一)
  - [172-fix-sse-saturation-blocking-web-workers.md](closed/172-fix-sse-saturation-blocking-web-workers.md) (通信安定化)
  - [173-expand-1hop-incident-edges-in-graph-query.md](closed/173-expand-1hop-incident-edges-in-graph-query.md) (1-Hop エッジ自動展開)
  - [174-enable-canvas-scrolling-and-fix-clipping-in-dashboard.md](closed/174-enable-canvas-scrolling-and-fix-clipping-in-dashboard.md) (Canvas 見切れ解消・デッキ表示切替)
  - [175-relocate-legend-pin-footer-and-add-zoom-controls-in-dashboard.md](closed/175-relocate-legend-pin-footer-and-add-zoom-controls-in-dashboard.md) (凡例左上配置・固定フッター・ズームコントローラー・チップヒント)
- **関連設計書**:
  - [DSN-09: Web Gateway & Presentation](../designs/DSN-09-web_gateway_and_presentation.md)
  - [DSN-14: Graph Engineering Dashboard](../designs/DSN-14-graph_engineering_dashboard.md)
  - [DSN-01: High-Level Architecture](../designs/DSN-01-high_level_design.md)
- **統治規約**:
  - `AGENTS.md` (PM 主導・全 13 専門エージェント多角レビュー原則)

---

## 3. 多角専門エージェント審議録 (PM / UI / ST / SA / QA)

| エージェント | 専門領域と注力論点 | 設計書へのブラッシュアップ反映内容 |
| :--- | :--- | :--- |
| **UI/UX & Documentation Designer (主査)** | **美意識、認知的快適性、マイクロインタラクション、情報密度設計** | ・Swiss Warm Palette とグラスモルフィズムの幾何学的融合の厳密定義。<br>・Pure CSS 多方向チップヒント（`[data-tooltip-pos="top|bottom|right|left"]`）の仕様・CSS 定義明文化。<br>・凡例の左上配置、固定フッター（36px）、ズーム操作 HUD（100% バッジ ＋ ステップボタン ＋ ショートカット）の視線誘導モデルと Mermaid 構成図の追加。<br>・操作時の微細トランジション（`active: translateY(1px)`）とフォント階層（Inter / Outfit / Monospace）の徹底標準化。 |
| **IT Strategist (ST)** | **アナリストの思考速度（Velocity）、意思決定支援（TTI: Time-to-Insight）、2層型ペルソナ設計** | ・経営幹部/CISO（ROI・トレンド・総論）と技術アナリスト/インシデントレスポンダー（CTI グラフ・1-Hop 探索・原本検証）の Dual-Tier 画面導線体系の明文化。<br>・ポータル（`index.html`）とグラフ探査（`dashboard.html`）の相互ディープリンクとコンテキスト保持モデルの定義。 |
| **Systems Architect (SA)** | **Pure Web アーキテクチャ、レンダリング負荷最小化、クライアント・サーバー境界** | ・Vanilla JS ＋ Canvas 2D ＋ Pure CSS による「ゼロ外部 CDN・ゼロ npm 依存」原則の厳格規定。<br>・Viewport 100vh コンテインメント（`overflow: hidden; height: 100vh;`）と CSS Flexbox 伸縮アーキテクチャの数理的・構造的説明。<br>・DOM 増殖を防ぐ擬似要素（`::before`, `::after`）によるツールチップ描画のパフォーマンス優位性（ゼロ GC、ゼロ再計算）。 |
| **Software QA Specialist (QA)** | **品質管理ゲート、DOM 回帰テスト、アクセシビリティ（WCAG 2.1）検証基準** | ・DOM 要素 ID / クラス名 / `data-tooltip` 属性 / ARIA 属性の網羅的テスト検証マトリクスの策定。<br>・キーボードショートカット網羅性（`/`, `Ctrl+K`, `?`, `Escape`, `H`, `D`, `+`, `-`, `0`）の自動テスト仕様。<br>・Xenon / Radon / Flake8 / Mypy 厳格品質ゲートとの完全整合性保証。 |
| **Project Manager (PM)** | **ガバナンス、バージョンライフサイクル、DoD 判定** | ・文書ステータスを `APPROVED` から `PRODUCTION-VALIDATED & VERIFIED` へ昇格。<br>・Issue 167〜175 の開発軌跡と成果物の完全なトレーサビリティの確保。 |

---

## 4. 実装計画・対象ファイル (Target Files & Action Items)

- [x] **[MODIFY]** `docs/designs/DSN-21-enterprise_design_system_and_unified_console.md`
  - 全体体系目次の再構成（全 8 章＋付録への拡充）。
  - 第 1 章: 背景・ミッション・直近の発展経緯（Issues 167〜175）の反映。
  - 第 2 章: Warm Swiss Enterprise Design Tokens の拡張（Elevation, Shadows, Motion, Tooltips, Glassmorphism）。
  - 第 3 章: グローバルコンソールシェルおよびワークスペースアーキテクチャ（Viewport 100vh 収束、Pinned 36px フッター、ヘッダー/デッキ折りたたみ機構、フッター `.compliance-badge` 構造化）。
  - 第 4 章: CTI ナレッジグラフ専用ワークスペース（画面左上段ズーム HUD コントローラー `top: 14px`、直下 CTI 凡例パネル垂直スタック `top: 54px`、キャンバスパン/ズーム、インスペクター）。
  - 第 5 章: メインコンテンツ標準 6 大コンポーネント設計（ページヘッダー、バナー、KPI カード、インラインフィルタ、リソーステーブル、ヘルプドロワー）。
  - 第 6 章: Pure CSS 多方向チップヒント & マイクロインタラクション仕様（top/bottom/right/left, 三角矢印, トランジション, エッジクリッピング保護）。
  - 第 7 章: Single-Pane of Glass 統合ルーティング & 6 大タブ情報設計（Search, Trends, Graph, ROI, Observability, Supervisor）。
  - 第 8 章: セキュリティ・アクセシビリティ（WCAG 2.1 AAA/AA）・品質管理ゲート & 回帰テストマトリクス。
  - 付録: 全キーボードショートカット一覧・DOM 要素 ID カタログ。
- [x] **[MODIFY]** `site/dashboard.html`
  - ズーム操作 HUD（`.canvas-zoom-controls`）を画面左上段（`top: 14px; left: 14px;`）へ配置。
  - CTI 凡例パネル（`.cluster-legend`）をズーム HUD の直下（`top: 54px; left: 14px;`）へ垂直スタック配置。
  - ズーム HUD のツールチップ展開方向を下方（`data-tooltip-pos="bottom"`）へ、凡例要素を右方（`data-tooltip-pos="right"`）へ設定し視覚干渉を排除。
  - グローバルフッター固定表示の flexbox `min-height: 0` / `overflow: hidden` クリップ修正。
  - フッター「ISO 32000-1 / Google OKF v0.2 Compliant」の押しつぶれを `.compliance-badge` で完全解消。
- [x] **[MODIFY]** `tests/web/test_dashboard_graph_tab.py`
  - 画面左上スタック配置（`top: 14px;` / `top: 54px;` / `left: 14px;`）および `.compliance-badge` の自動回帰テスト追加。
- [x] **[MODIFY]** `docs/issues/README.md`
  - Issue 176 の台帳登録。
- [x] **[VERIFY]** 品質ゲート検証:
  - Markdown 相対リンク検証（`file:///` 等の絶対パス検出ゼロ）。
  - `make check_format` (Flake8, Black, isort).
  - `make static_analysis` (Radon, Xenon, Mypy).
  - `make test` (全 25+ テスト PASS).

---

## 5. 完了条件 (Definition of Done: DoD)

1. `DSN-21-enterprise_design_system_and_unified_console.md` が直近の作業（Issues 167〜175）の実装成果を 100% 網羅し、UI/UX・SA・ST・QA・PM の全視点から大幅にブラッシュアップされていること。
2. 充実した Mermaid アーキテクチャ図（コンソール構造、ズーム・凡例レイアウト、ツールチップ幾何学、Single-Page ルーティング）が含まれていること。
3. すべての内部リンクが完全な相対パスであり、`AGENTS.md` の統治ルールに 100% 適合していること。
4. プロジェクトの全品質管理ゲート（`make check_format`, `make static_analysis`, `make test`）が 100% PASS すること。
