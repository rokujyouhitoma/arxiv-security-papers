---
ID: 139
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] /dashboard tab=graph 画面における表示要素の重なり解消およびレイアウト再設計 (ID: 139)

## 1. 概要 / Summary
`http://localhost:8000/dashboard.html?tab=graph`（Knowledge & CTI Graph 専用画面）において、グラフ操作ツールバー（`mesh-toolbar`）、グラフクエリコンソール（`graph-query-console`）、クラスタ／CTI 凡例（`cluster-legend`）、およびノード詳細コールアウト（`node-callout`）がすべて Canvas 上に `position: absolute` で重ねて配置されており、相互に被って表示されるため、入力操作やノード・凡例の判読性が著しく低下している。

本 Issue では、複数の UI/UX スペシャリストによる合同討議（情報アーキテクト、ビジュアル／インタラクションデザイナー、デザインシステム設計者、データ可視化専門家）の合意に基づき、操作系・可視化系・インスペクタ系のレイアウト構造を根本から再設計し、要素の重複を完全に根絶して快適なナレッジグラフ探索環境を構築する。

---

## 2. 複数 UI/UX スペシャリスト合同討議録 (Multi-UI/UX Consensus)

### 2.1 参加メンバー
1. **UI/UX スペシャリスト A（情報アーキテクチャ・IA 担当）**
2. **UI/UX スペシャリスト B（ビジュアル & インタラクション担当）**
3. **UI/UX スペシャリスト C（デザインシステム & アクセシビリティ担当）**
4. **UI/UX スペシャリスト D（データ可視化 & グラフエルゴノミクス担当）**

### 2.2 討議内容と課題の特定
- **IA（スペシャリスト A）の指摘**:
  - 現状は Canvas コンテナ（`.canvas-container`）の内部にすべてのオーバーレイ要素が絶対座標（`position: absolute`）で重なり合っている。
  - `top: 52px` のクエリコンソールが画面左右（`left: 12px; right: 12px;`）いっぱいに広がる一方、凡例が `top: 14px; left: 14px;`、コールアウトが `top: 14px; right: 14px;` に配置されており、クエリバーの真裏や真上に重なって文字が読めず、クリック操作も阻害されている。
  - **解決策**: 「操作コントロール領域（上部）」と「キャンバス領域（中央）」と「インスペクタ／凡例領域（左右・下部）」の空間的責務を分離すべき。
- **ビジュアル・インタラクション（スペシャリスト B）の指摘**:
  - ノード詳細コールアウトが画面右上にフロート表示されると、クエリコンソールの検索ボタンやヘッダートグルボタンと干渉する。
  - **解決策**: ノードコールアウトは独立した **右側サイドドロワー（Side Inspector Pane）** として画面右端にドッキングするか、または右下にスマートに配置し、閉じるボタンおよびスクロール可能な詳細リストを提供する。
- **データ可視化（スペシャリスト D）の指摘**:
  - 凡例（Cluster Legend / CTI Legend）が画面上部に居座ることで、グラフ物理演算の中心付近が見えにくくなっている。
  - **解決策**: 凡例は **左下（Bottom-Left）** に移動し、さらに「凡例を折りたたむ / 展開する」トグル機能を持たせることで、グラフの可視面積を最大化する。
- **デザインシステム（スペシャリスト C）の指摘**:
  - クエリコンソールのプリセットボタン群が画面幅に応じて改行された際、Canvas 上に被さる面積が動的に変わる問題がある。
  - **解決策**: 上部の `mesh-toolbar` と `graph-query-console` を一体型の **「グラフ・コントロールデッキ（Graph Control Deck）」** としてフレックス・ドッキングし、その真下に Canvas を配置（または半透明オーバーレイの Z-Index とパディングを整理）する。

### 2.3 統合合意レイアウト（Approved Layout Blueprint）
```
+-----------------------------------------------------------------------------------+
| Top Header (Collapsible with 'H' shortcut)                                       |
+-----------------------------------------------------------------------------------+
| Tab Navigation: [🕸️ Graph] [📚 Product] [⚙️ System] [🕹️ Supervisor] [▲ ヘッダー隠す]|
+-----------------------------------------------------------------------------------+
| 🎛️ Graph Control Deck (Unified Top Toolbar & Query Console)                       |
|   Row 1: [Mode: Context / CTI] | [Filter: All/Paper/ATT&CK/CWE/Gaps] | [⛶ Fullscreen] |
|   Row 2: [Query Input: "gaps", "cwe: CWE-20"...] [🔍 探索] [✕ リセット]            |
|   Row 3: シナリオ: [🚨 Gaps] [🛡️ CWE-20] [🤖 AML.T0054] [Post-Quantum] [Badge: Ready] |
+-----------------------------------------------------------------+-----------------+
|                                                                 |                 |
| 🕸️ Knowledge Graph Canvas (Unobstructed Physical Force Layout)   | 📋 Node Detail  |
|                                                                 |    Inspector    |
|   - Nodes & Edges animate freely without UI interference       |    Side Pane    |
|                                                                 |                 |
|                                                                 | - Tag / Label   |
|                                                                 | - Title         |
| [Cluster / CTI Legend] (Bottom-Left, Collapsible)               | - Summary       |
|   [▼ 凡例表示/隠す] 🔵 Papers  🔴 ATT&CK  🟠 CWE  🟢 Mitigations | - Connections   |
|                                                                 | - [✕ 閉じる]    |
+-----------------------------------------------------------------+-----------------+
```

---

## 3. トレーサビリティ / Traceability
- [DSN-14: Graph Engineering Dashboard & Live Loop Observability (Section 5, 6, 11)](../designs/DSN-14-graph_engineering_dashboard.md)
- [Issue 135: arXivセキュリティ論文・MITRE ATT&CK・CWEナレッジグラフデータ基盤および /dashboard インタラクティブグラフ可視化の実装](closed/135-implement-paper-attck-cwe-knowledge-graph-and-dashboard-visualization.md)
- [Issue 137: /dashboard Product タブにおける CTI グラフクエリ・コンソールおよびサブグラフ抽出・ハイライト機能の実装](closed/137-implement-graph-query-console-and-subgraph-extraction-in-dashboard.md)
- [Issue 138: /dashboard における専用 Knowledge & CTI Graph 画面（tab=graph）の独立実装およびヘッダー折りたたみ機能](closed/138-create-dedicated-graph-tab-in-dashboard.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [site/dashboard.html](../../site/dashboard.html)
  - CSS スタイル:
    - `.graph-workspace` のフレックス構造（Deck + Main Area）の再定義
    - `.graph-control-deck`: ツールバーとクエリコンソールの統合スタック化
    - `.cluster-legend`: `top: 14px` から `bottom: 14px; left: 14px;` への移設、折りたたみ機能用スタイル
    - `.node-callout`: 右上フロートから右側ドッキング式インスペクタパネル（Side Inspector Pane）への昇華
    - Z-Index 体系の整理（Canvas: 1, Legend: 10, Deck: 20, Inspector: 30）
  - HTML 構造:
    - `viewGraph` 内の DOM 要素の並び替えとレイアウトコンテナの整理
    - 凡例の折りたたみトグルボタン（`#btnToggleLegendContext`, `#btnToggleLegendCti`）の追加
    - インスペクタパネルの構造最適化（タイトル、メタデータ、接続エッジの可読性向上）
  - JavaScript ロジック:
    - `toggleLegend()` 関数の実装
    - ノードクリック時のコールアウト展開と Canvas リサイズ連携
- [x] [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md)
  - Section 5 & 6 における新レイアウト（Control Deck, Bottom-Left Legend, Side Inspector Pane）のドキュメント追記
- [x] [tests/web/test_dashboard_graph_tab.py](../../tests/web/test_dashboard_graph_tab.py)
  - 新レイアウト（Control Deck、移動した凡例、インスペクタパネル、トグル機能）に対するテストケース追加

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/139-redesign-graph-tab-layout-and-fix-overlapping`

1. **コントロールデッキの統合（Top Control Deck）**:
   - `mesh-toolbar` と `graph-query-console` を上部の独立ブロック `.graph-control-deck` にまとめ、Canvas 上への被りを解消。
   - スイススタイル・レトロデザイン（`border-bottom: 2px solid var(--border-dark); background: var(--bg-panel);`）で統一。
2. **凡例の左下配置 & 折りたたみトグル（Bottom-Left Collapsible Legend）**:
   - `contextLegend` および `ctiLegend` を Canvas 左下にフロート配置（`bottom: 14px; left: 14px;`）。
   - クリック可能な `#btnToggleLegendContext`, `#btnToggleLegendCti`（`▲ 展開 / ▼ 格納`）を配備し、必要な時だけ展開できるようにする。
3. **右側インスペクタパネル（Side Inspector Pane）**:
   - ノード選択時の `node-callout` を、キャンバス右端にエレガントにオーバーレイ（またはドッキング）するインスペクタパネルとして刷新（`top: 0; right: 0; height: 100%; width: 340px;`）。
   - クエリコンソールとの衝突を完全に解消し、縦スクロールで長文アブストラクトや多数の接続エッジを快適に閲覧可能にする。
4. **テスト作成 & 品質検証**:
   - 要素重複の排除と新レイアウト構造を検証する単体テストを追加。
   - `make py_compile`, `make static_analysis`, `make test` の通過。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `http://localhost:8000/dashboard.html?tab=graph` において、ツールバー、クエリコンソール、凡例、ノードコールアウトが相互に重ならず、明確に整理されたレイアウトで表示されること。
- [x] クエリコンソールおよびツールバーが上部コントロールデッキとして一体化され、入力フィールドやプリセットボタンが容易に操作できること。
- [x] 凡例が左下に配置され、折りたたみ／展開トグルによってキャンバスの視界を妨げないこと。
- [x] ノードクリック時に開くノード詳細が右側のインスペクタパネルとして整理され、上部操作系と一切被らないこと。
- [x] ウィンドウリサイズ時およびヘッダー折りたたみ時（`H` キー）にもレイアウト崩れが生じず、Canvas が正しく再描画されること。
- [x] 新規テストを含む全テストスイートが 100% PASS すること。
- [x] `make py_compile` および `make static_analysis` が 0 エラーであること。
- [x] 相対パスリンクチェックにおいて違反が 0 件であること。
