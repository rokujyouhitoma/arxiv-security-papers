---
ID: 138
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] /dashboard における専用 Knowledge & CTI Graph 画面（tab=graph）の独立実装およびヘッダー折りたたみ機能 (ID: 138)

## 1. 概要 / Summary
現在、`/dashboard.html?tab=product`（Product & Knowledge Mesh）内に同居しているナレッジグラフ可視化キャンバス（HTML5 Canvas 2D 物理演算エンジン、Context Mesh / CTI Graph、グラフクエリコンソール、凡例、ノード詳細コールアウト）を、専用の独立タブ **`tab=graph`（🕸️ Knowledge & CTI Graph）** として分離・新設する。

さらに、Graph 画面において広大なナレッジネットワークを快適に探索・分析できるよう、上部テレメトリヘッダーを折りたたみ／隠蔽して画面垂直領域を極限まで最大化（`calc(100vh - 42px)`）できる **「ヘッダー折りたたみ機能（Toggle Header / Immersive Full-Height Mode）」** を新設する。

本改修は **Systems Architect (SA)** と **UI/UX & Documentation Designer (UIUX)** の主導のもと、以下の設計目標を達成する：
1. **SA 主導（アーキテクチャ・責務分離 & ルーティング・描画ライフサイクル基盤）**:
   - `tab=graph`（広域ナレッジグラフ探索・クエリ実行環境）と `tab=product`（論文インサイト・ROI/脅威分析メトリクス環境）の画面責務を明確に分離。
   - URL GET パラメータ `?tab=graph` による直接アクセス、ブラウザ履歴（`history.replaceState`）、`popstate` イベント連動、およびタブ表示時の Canvas 寸法再計算（`resizeCanvas`）同期ライフサイクルの確立。
   - 非アクティブ時の物理演算・描画ループ抑制による省電力・CPU負荷削減、およびゼロ幅・ゼロ高ガードによるレンダリング破損防止。
   - ヘッダー隠蔽トグル状態の管理、動的 Canvas リサイズ同期、および `localStorage` を用いた表示設定の永続化。
2. **UIUX 主導（スイススタイル・レトロデザイン & 没入型空間最大化）**:
   - グローバルナビゲーションに「🕸️ Knowledge & CTI Graph」タブを新設し、4タブ構成（Graph / Product / System / Supervisor）へと昇華。
   - `tab=graph` において画面領域を最大限に活用した没入型フルワイドキャンバス（通常時 `calc(100vh - 122px)`、ヘッダー隠蔽時 `calc(100vh - 42px)`）。
   - スイススタイルに馴染むヘッダー折りたたみトグルボタン（`#btnToggleHeader`）およびキーボードショートカット（`H` キー）の実装。
   - Glassmorphic なクエリコンソール、操作性・視認性の高いフロート凡例・コールアウトの配置。
   - グラフが独立した後の `tab=product` のレイアウトを再構成し、セキュリティインサイト・ROI分析パネルに加え、Graph画面へのシームレスなCTA（Call to Action）リンクカードを配置。

---

## 2. トレーサビリティ / Traceability
- [DSN-14: Graph Engineering Dashboard & Live Loop Observability (Section 1, 5, 6, 11)](../designs/DSN-14-graph_engineering_dashboard.md)
- [DSN-09: Web Gateway & Presentation](../designs/DSN-09-web_gateway_and_presentation.md)
- [Issue 095: ST・SA・SM 戦略的テレメトリ統合と UI/UX 3タブレイアウト高度化](closed/095-integrate-st-sa-sm-strategic-telemetry-and-uiux-layout.md)
- [Issue 135: arXivセキュリティ論文・MITRE ATT&CK・CWEナレッジグラフデータ基盤および /dashboard インタラクティブグラフ可視化の実装](closed/135-implement-paper-attck-cwe-knowledge-graph-and-dashboard-visualization.md)
- [Issue 137: /dashboard Product タブにおける CTI グラフクエリ・コンソールおよびサブグラフ抽出・ハイライト機能の実装](closed/137-implement-graph-query-console-and-subgraph-extraction-in-dashboard.md)

---

## 3. SA / UIUX 共同主導アーキテクチャ設計

### 3.1 SA 視点（システム・ルーティング・データフロー & 描画ライフサイクル）
1. **タブナビゲーションとルーティングの拡張**:
   - `window.switchDashboardTab(tabName, updateUrl)` において、`graph`, `cti`, `mesh`, `knowledge` の各エイリアスを `graph` として一元正規化。
   - URL クエリパラメータ `?tab=graph` を正式な第1級パラメータとしてサポート。ブラウザ履歴（`history.replaceState`）と連動し、ページリロードなしにURLバーを更新。
   - `popstate` イベントリスナーにより、ブラウザの「戻る」「進む」ナビゲーション時にも即座にタブDOMとCanvasが同期切り替えされることを保証。
2. **ヘッダー折りたたみ制御と Canvas リサイズ同期**:
   - `<header id="dashboardHeader">` に対し、クラス `.header-hidden` を付与することで高さ 0 または `display: none` に安全に遷移。
   - トグル関数 `window.toggleDashboardHeader(forceState)`:
     - ヘッダーのクラス切替（`dashboardHeader.classList.toggle('header-hidden', forceState)`）。
     - トグルボタンのアイコン・文言更新（`⛶ ヘッダー隠す` / `▼ ヘッダー表示`）。
     - トグル完了直後に `requestAnimationFrame` および `setTimeout(resizeCanvas, 30)` を呼び出し、Canvas のピクセルバッファと座標系を新領域に同期拡大。
     - ユーザーの開閉選択状態を `localStorage.setItem('dashboard_header_hidden', isHidden)` に永続化し、リロード時にも好みの表示状態を維持。
3. **Canvas 描画ライフサイクルとゼロガード**:
   - 非表示タブ（`display: none`）状態では親要素の `clientWidth` / `clientHeight` が 0 となるため、安易なリサイズ呼び出しはノード座標系を原点（0,0）に潰してしまうリスクがある。
   - `resizeCanvas()` 内に `if (width <= 0 || height <= 0) return;` のゼロガードを実装。
   - `activeTab === 'graph'` に切り替わった直後、`requestAnimationFrame` または `setTimeout(resizeCanvas, 50)` でコンテナの正しい矩形を取得し、Canvas バッファ寸法（`devicePixelRatio` 考慮）とビュー変換行列を再計算。
   - `isGraphActive` フラグを管理し、`tab=graph` 以外のタブ表示中は Canvas の重い描画ループ（`stepPhysics()` / `render()`）をアイドリング（低頻度またはスキップ）させてブラウザの CPU/GPU 負荷と電力消費を最小化。
4. **Product タブからのディープリンク連動 (Cross-Tab Deep Linking)**:
   - `tab=product` 内の分析カード（Emerging Threat Vectors や Research Gaps サマリー等）に「🕸️ グラフで探索」ボタンを配置。
   - ボタンクリック時に `window.switchDashboardTab('graph')` を実行し、オプションでクエリ（例: `cwe: CWE-20` や `gaps`）を自動入力・即時実行する連携インターフェース `openGraphWithQuery(query)` を提供。

### 3.2 UIUX 視点（レイアウト・エルゴノミクス・デザインシステム）
1. **4タブ・ナビゲーションバーの再定義**:
   - タブ配置順序と視覚アイコン（スイススタイル・レトロデザイン準拠）：
     - `🕸️ Knowledge & CTI Graph` (`#tabBtnGraph`): ナレッジグラフ＆脅威関係性探索
     - `📚 Product & Analytics` (`#tabBtnProduct`): 論文動向・投資対効果・脅威ベクトル分析
     - `⚙️ System & Observability` (`#tabBtnSystem`): パイプライン進行・OBF分散トレーシング
     - `🕹️ Supervisor & Process Top` (`#tabBtnSupervisor`): プロセス監視・ワーカー自動管理
   - ナビゲーションバー右端に「ヘッダー折りたたみボタン（`#btnToggleHeader`）」をスマートに配置（ホバーツールチップ「ヘッダーを隠す / 表示 (Shortcut: H)」付き）。
2. **専用 `tab=graph` ワークスペースの空間設計**:
   - 通常時: `height: calc(100vh - 122px);`
   - ヘッダー隠蔽時: `height: calc(100vh - 42px);`（画面のほぼ全域がグラフ探索領域に変化）
   - 上部ツールバー（`mesh-toolbar`）:
     - グラフモード切替（Context Mesh / 🛡️ CTI Graph）
     - CTI エンティティフィルター（All / Papers / ATT&CK / CWE / Defense）
     - Research Gaps ハイライトボタン
     - ヘッダー隠蔽トグルクイックボタン（`#btnToggleHeaderQuick`）
   - 上部クエリコンソール（`graph-query-console`）:
     - 透過度 92% の Glassmorphism パネル。クエリ入力フィールド、探索・クリアボタン、ワンクリックシナリオプリセット群。
   - 四隅のフロートオーバーレイ:
     - 左上: クラスタ分類凡例（Context / CTI）
     - 右上: 探索結果バッジ、サブグラフ統計（ノード数・エッジ数）
     - 右下: ノード詳細コールアウトカード（クリック時に展開、ノード名・種別・概要・接続エッジ一覧表示）
3. **`tab=product` ワークスペースの再構成**:
   - 巨大キャンバスの移設に伴い、Product タブはセキュリティインテリジェンス・メトリクスを一覧できる洗練されたダッシュボードとして再設計。
   - 最上部に「🕸️ Knowledge & CTI Graph 探索ワークスペースへ」の Glassmorphic な CTA 誘導バナーカードを配置。ワンクリックで `tab=graph` の ATT&CK/CWE 全体グラフまたは Research Gaps にジャンプ可能。
   - その下部に 4 大分析パネルを整理して配置：
     1. Hop Budget Distribution (ヒストグラム Canvas)
     2. Edge Ledger (リレーショントラフィック一覧)
     3. Token Savings & Cost ROI (時系列 Canvas & ROI 指標)
     4. Emerging Threat Vectors (上位 5 脅威 & カバレッジ)

---

## 4. 脅威モデリングとセキュリティ要件 (Threat Modeling & Mitigations)
- **T-138-01: タブパラメータによる DOM Clobbering / XSS (CWE-79)**
  - *脅威*: URL `?tab=<malicious>` パラメータから直接 `document.getElementById` 等を悪用した DOM 操作やスクリプト注入のリスク。
  - *対策*: タブ名は厳格なホワイトリスト（`graph`, `product`, `system`, `supervisor`）でのみ判定。未知のパラメータは安全にデフォルトタブ（`graph` または `product`）にフォールバック。
- **T-138-02: Canvas リサイズ時の無限再帰・メモリリーク (DoS)**
  - *脅威*: 高速なタブ切り替えや非表示時のゼロサイズ取得により、Canvas バッファ再生成の無限ループや例外が発生する。
  - *対策*: `width <= 0 || height <= 0` 時の早期リターン（Early Exit）と、リサイズ処理のデバウンス制御。
- **T-138-03: クロスタブ連携時のクエリインジェクション (CWE-20)**
  - *脅威*: `openGraphWithQuery` 経由で悪意ある文字列が渡される。
  - *対策*: クエリ文字列は Issue 137 で確立した安全なトークンバリデーション（`gaps`, `cwe:`, `ego:`, `match:`, `path:` の厳格パース、128文字上限）を通過させる。
- **T-138-04: ヘッダー開閉連打によるレイアウトスラッシング・リソース枯渇 (DoS)**
  - *脅威*: ユーザや自動スクリプトによるヘッダートグルの高速連打で Canvas バッファ再生成がスパイクする。
  - *対策*: リサイズ呼び出しを `requestAnimationFrame` でバウンディングし、同一フレーム内の重複再描画を抑止。

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [site/dashboard.html](../../site/dashboard.html)
  - `<header id="dashboardHeader">`: ID付与、`.header-hidden` スタイルクラス対応
  - `<nav class="tab-navigation">`: `tabBtnGraph` ボタン追加、ヘッダー隠蔽トグルボタン（`#btnToggleHeader`）追加、4タブレイアウト調整
  - DOM 構造: `<div id="viewGraph" class="tab-view active">` 新設、`canvas-container` および凡例・コールアウト・クエリコンソール・クイックヘッダートグルの移設
  - `<div id="viewProduct" class="tab-view">`: グラフ Canvas 移設後のレイアウト最適化、CTA 導線カード追加
  - CSS スタイル: `.graph-workspace`, `.product-workspace`, `.graph-cta-banner`, `.header-hidden` 等の追加
  - JavaScript: `switchDashboardTab`, `toggleDashboardHeader`, `resizeCanvas` ゼロガード、`isGraphActive` 描画制御、ショートカットキー `H` リスナー、`openGraphWithQuery` 関数追加
- [x] [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md)
  - 4 タブ構成（Graph, Product, System, Supervisor）およびヘッダー隠蔽モード仕様の追記
  - URL クエリパラメータ仕様（`?tab=graph`）の更新
- [x] [tests/web/test_dashboard_graph_tab.py](../../tests/web/test_dashboard_graph_tab.py)
  - 新規テストファイル: `tab=graph` 関連の DOM 要素検証、ヘッダー隠蔽トグル機構、4タブ切替スクリプト整合性、URL パラメータ正規化、および WSGI ゲートウェイ結合テスト

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/138-create-dedicated-graph-tab-in-dashboard`

1. **HTML 構造の分離・最適化 (`site/dashboard.html`)**:
   - `<header>` に `id="dashboardHeader"` を付与。
   - ナビゲーションバーに以下のように 4 タブおよびヘッダートグルボタンを配置：
     ```html
     <nav class="tab-navigation">
       <div class="tab-group">
         <button class="tab-btn active" id="tabBtnGraph" onclick="switchDashboardTab('graph')">
           🕸️ Knowledge &amp; CTI Graph
         </button>
         <button class="tab-btn" id="tabBtnProduct" onclick="switchDashboardTab('product')">
           📚 Product &amp; Analytics
         </button>
         <button class="tab-btn" id="tabBtnSystem" onclick="switchDashboardTab('system')">
           ⚙️ System &amp; Observability
         </button>
         <button class="tab-btn" id="tabBtnSupervisor" onclick="switchDashboardTab('supervisor')">
           🕹️ Supervisor &amp; Process Top
         </button>
       </div>
       <div class="tab-actions">
         <button class="btn-tool-header" id="btnToggleHeader" onclick="toggleDashboardHeader()" title="ヘッダーを折りたたむ / 表示する (キーボード: H)">
           ▲ ヘッダー隠す
         </button>
       </div>
     </nav>
     ```
   - `<div id="viewGraph" class="tab-view active">` を新設し、その中に `.graph-workspace` を定義。`canvas-container`（ツールバー、クエリコンソール、Canvas、凡例、ノードコールアウト）を丸ごと配置。
   - `<div id="viewProduct" class="tab-view">` 内は、ヘッダー直下に `.graph-cta-banner`（Graph への誘導カード）を新設し、その下に 4 大分析カード（Hop Budget, Edge Ledger, Token Savings, Threat Vectors）を整理配置。

2. **CSS スタイル定義 (`site/dashboard.html`)**:
   - ヘッダー隠蔽アニメーション・スタイル：
     ```css
     header.header-hidden {
       display: none; /* または max-height: 0; padding: 0; overflow: hidden; opacity: 0; */
     }
     ```
   - `.graph-workspace` のスタイル定義（`flex: 1; height: calc(100vh - 122px); min-height: 520px; display: flex; flex-direction: column;`）。
   - ヘッダー非表示時の高さをサポート（`header.header-hidden ~ #viewGraph .graph-workspace { height: calc(100vh - 42px); }`）。
   - `.graph-workspace .canvas-container { flex: 1; height: 100%; border-bottom: none; }` により、画面縦幅いっぱいのキャンバスを実現。
   - `.graph-cta-banner` の Glassmorphic スタイルとボタン装飾（スイススタイル・レトロデザイン統一）。

3. **JavaScript ルーティング & ライフサイクル制御 (`site/dashboard.html`)**:
   - `toggleDashboardHeader(forceState)`:
     ```javascript
     window.toggleDashboardHeader = function(forceState) {
       const header = document.getElementById('dashboardHeader');
       const btn = document.getElementById('btnToggleHeader');
       if (!header) return;
       const isHidden = (typeof forceState === 'boolean') ? forceState : !header.classList.contains('header-hidden');
       header.classList.toggle('header-hidden', isHidden);
       if (btn) {
         btn.innerHTML = isHidden ? '▼ ヘッダー表示' : '▲ ヘッダー隠す';
         btn.title = isHidden ? 'ヘッダーを表示する (H)' : 'ヘッダーを隠す (H)';
       }
       try { localStorage.setItem('dashboard_header_hidden', isHidden ? '1' : '0'); } catch(e) {}
       setTimeout(resizeCanvas, 40);
     };
     ```
   - キーボードイベント（`H` または `h` 押下時に入力フィールド外であれば `toggleDashboardHeader()` を発火）。
   - `switchDashboardTab`:
     ```javascript
     const normTab = (tabName || 'graph').toLowerCase().trim();
     const activeTab = (normTab === 'product' || normTab === 'analytics') ? 'product' :
                       (normTab === 'system' || normTab === 'observability' || normTab === 'pipeline') ? 'system' :
                       (normTab === 'supervisor' || normTab === 'top' || normTab === 'process') ? 'supervisor' : 'graph';
     ```
   - 4 つの View（`viewGraph`, `viewProduct`, `viewSystem`, `viewSupervisor`）および 4 つの Tab ボタンのクラス切り替え。
   - `if (activeTab === 'graph') { isGraphActive = true; setTimeout(resizeCanvas, 50); } else { isGraphActive = false; }`
   - `resizeCanvas`: `if (width <= 0 || height <= 0) return;` のゼロガード追加。
   - `openGraphWithQuery(query)` 関数の新設（Product タブからのディープリンク呼び出し用）。

4. **テスト作成 (`tests/web/test_dashboard_graph_tab.py`)**:
   - `test_dashboard_graph_tab_elements`: `tabBtnGraph`, `viewGraph`, `graph-workspace`, `graph-cta-banner`, `dashboardHeader`, `btnToggleHeader` の存在検証。
   - `test_dashboard_header_toggle_functionality`: `toggleDashboardHeader` の関数定義、`.header-hidden` CSS クラス定義、ショートカットキー連動スクリプトの検証。
   - `test_dashboard_tab_switching_routing_logic`: `switchDashboardTab` の正規化ロジック（`graph`, `product`, `system`, `supervisor`）のコード整合性検証。
   - `test_dashboard_graph_tab_http_response`: WSGIApplication 経由で `/dashboard.html?tab=graph` へのアクセスが 200 OK で返却されることの検証。
   - 既存の `test_dashboard_html.py` および `test_dashboard_cti_graph.py` の回帰検証。

5. **設計書更新 (`docs/designs/DSN-14-graph_engineering_dashboard.md`)**:
   - Section 11 および概要部における 4 タブ構成（`tab=graph` 独立）およびヘッダー折りたたみ仕様の記述更新。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `site/dashboard.html` のナビゲーションバーに「🕸️ Knowledge & CTI Graph」タブが追加され、4タブ構成（Graph / Product / System / Supervisor）として機能すること。
- [x] `http://localhost:8000/dashboard.html?tab=graph`（または `?tab=cti`, `?tab=mesh`）にアクセスした際、直接 Graph 画面がアクティブ状態で正しく描画・表示されること。
- [x] `tab=graph` において、ヘッダー・ナビバー以外の画面垂直領域全体を活用したフルハイトキャンバスが表示され、クエリコンソール・ツールバー・凡例・ノード詳細コールアウトが破綻なく操作できること。
- [x] **ヘッダー隠蔽機能**: ナビゲーションバーの「▲ ヘッダー隠す / ▼ ヘッダー表示」ボタン（および `H` キー）で上部テレメトリヘッダーを安全に折りたたみ／展開でき、ヘッダー非表示時に Canvas が画面上端近くまで拡大（縦幅約80px拡張）すること。
- [x] ヘッダー開閉時およびタブ切り替え時に Canvas のリサイズ（`resizeCanvas`）が自動実行され、表示が崩れないこと。
- [x] `tab=product` は Product Analytics（Hop Budget, Edge Ledger, Token Savings, Emerging Threat Vectors 等）に特化したレイアウトとなり、Graph 画面への CTA リンクが正しく機能すること。
- [x] タブ切り替え時に URL クエリパラメータ（`?tab=graph|product|system|supervisor`）が履歴とともに正しく更新されること。
- [x] ブラウザの「戻る」「進む」操作（`popstate`）でタブ表示が正しく同期されること。
- [x] タブ非表示時に Canvas 物理演算・描画が無駄に暴走せず、`tab=graph` 表示時に安全にリサイズ（ゼロガード動作）されること。
- [x] 新規テスト `tests/web/test_dashboard_graph_tab.py` を含む全テストが PASS すること。
- [x] `make py_compile` および `make static_analysis` が 0 エラーで完了すること。
- [x] 設計書 `docs/designs/DSN-14-graph_engineering_dashboard.md` に 4 タブ構成およびヘッダー隠蔽機能の更新が反映されること。
