---
ID: 170
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] dashboard.html からの 3 画面削除（Graph 単一画面化）および index.html との統一ヘッダー・相互リンク実装 (ID: 170)

## 1. 概要 / Summary

Issue 169 にて `dashboard.html` の 3 画面（Product & Analytics, System & Observability, Supervisor & Process Top）が `site/index.html`（Enterprise Cloud Console）へ完全移植されたことを受け、`site/dashboard.html` の責務を「Knowledge & CTI Graph 専用ワークスペース」へと純化する。

具体的には：
1. **3 画面およびタブバーの完全削除**:
   - `Product & Analytics` (`#viewProduct`)
   - `System & Observability` (`#viewSystem`)
   - `Supervisor & Process Top` (`#viewSupervisor`)
   - 上記を切り替えていたタブナビゲーション (`.tab-navigation`, `#tabBtnProduct`, `#tabBtnSystem`, `#tabBtnSupervisor`) を削除し、`🕸️ Knowledge & CTI Graph` (`#viewGraph`) 1画面のみを残す。
2. **`site/index.html` とのヘッダーデザイン統一**:
   - `dashboard.html` の旧式ヘッダー（高さ約80pxのテレメトリバー複合型）を、`index.html` と同一の 48px 固定エンタープライズヘッダー（`.console-header`、ブランドロゴ、グローバル検索バー、ステータスピル、ユーティリティアイコン）へと刷新する。
   - `site/style.css` を `<link rel="stylesheet" href="style.css">` で読み込み、Enterprise Design System (DSN-21) に完全準拠させる。
3. **相互遷移リンクの完全整備**:
   - `dashboard.html` ヘッダーから `index.html`（クラウドコンソール）へ即座に戻れる導線（`#portalSwitchBtn`: `🏠 クラウドコンソールへ ↗`）を配備。
   - `index.html` のヘッダーユーティリティ（`#portalSwitchBtn`）も `🕸️ ナレッジグラフ ↗` へとラベルとツールチップを整合させ、両画面間で直感的な相互往復を可能とする。

---

## 2. トレーサビリティ & 脅威モデリング / Traceability & Threat Modeling

### 2.1 関連ドキュメント
- 関連設計書: [DSN-21: Enterprise Design System & Unified Console](docs/designs/DSN-21-enterprise_design_system_and_unified_console.md)
- 先行 Issue: [Issue 169: Port Product, System, and Supervisor Views to index.html](docs/issues/closed/169-port-product-system-supervisor-views-to-index-console.md)
- ガバナンス規約: [.agents/AGENTS.md](.agents/AGENTS.md)

### 2.2 セキュリティ要件 & 脅威分析 (Threat Modeling)
1. **Zero External Dependencies の死守 (CWE-1395)**:
   - `site/dashboard.html` は一切の CDN や外部 `http/https` スクリプト・フォント・CSS を読み込まず、完全ローカル完結（Vanilla JS / CSS）を維持する。
2. **DOM XSS / オープンリダイレクトの防止 (CWE-79, CWE-601)**:
   - ヘッダー検索および画面間遷移は、相対パス (`/index.html`, `/dashboard.html`) のみに限定し、未検証の外部 URL へのリダイレクトを許容しない。
   - ヘッダー検索入力からグラフクエリへの連携時は、安全な内部クエリエクスプローラ (`executeGraphQuery`) を介して処理する。
3. **リソースリークの防止**:
   - 削除された旧 3 画面向けの不要な更新ループ（`supervisorWorkersTableBody`, `hopCanvas`, `walkVsFlatCanvas` 等）を停止し、不要な SSE / Polling 負荷をゼロにする。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [site/dashboard.html](site/dashboard.html):
  - 3 画面の HTML マークアップ (`#viewProduct`, `#viewSystem`, `#viewSupervisor`) およびタブナビゲーション (`.tab-navigation`) の削除。
  - `console-header` に準拠した統一ヘッダーの導入と相互リンク (`#portalSwitchBtn`) の配置。
  - `.graph-workspace` の高さを `calc(100vh - 48px - 36px)` へ最適化。
  - 不要となったタブ切り替えスクリプト等の整理と、グラフ単一画面としての安定化。
- [x] [site/index.html](site/index.html):
  - ヘッダー内 `#portalSwitchBtn` のラベルを `🕸️ ナレッジグラフ ↗`、タイトルを `CTI ナレッジグラフ専用画面へ移動` に更新し、相互リンクを完成。
- [x] [tests/web/test_dashboard_html.py](tests/web/test_dashboard_html.py):
  - `dashboard.html` における旧タブ削除の確認 (`viewProduct` 等が非存在であることのアサート)。
  - 統一ヘッダー要素 (`.console-header`, `#portalSwitchBtn`, `#globalSearchInput`, `#systemStatusBadge`) のアサーション追加。
  - 外部依存ゼロテスト (`test_dashboard_zero_external_dependencies`) の継続検証。
- [x] [tests/web/test_dashboard_graph_tab.py](tests/web/test_dashboard_graph_tab.py):
  - グラフ単一画面化に伴う要素検証テストの改定。
- [x] [docs/issues/README.md](docs/issues/README.md):
  - Issue 170 の進捗状況およびクローズ追跡。

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/170-unify-dashboard-header-with-index-and-retain-graph-only`

### フェーズ 1: マークアップ再編 & 統一ヘッダー導入
1. **`site/dashboard.html` ヘッダー刷新**:
   - `<link rel="stylesheet" href="style.css">` を `<head>` に追加。
   - 旧 `<header id="dashboardHeader">` および `<nav class="tab-navigation">` を削除。
   - `index.html` と共通の `<header class="console-header" id="dashboardHeader">` を配置：
     - Brand: `🛡️ arXiv Security Intelligence | Knowledge & CTI Graph Engine`
     - Center Search: `#globalSearchInput` (グラフクエリ `executeGraphHeaderSearch` と連携)
     - Utilities: `#portalSwitchBtn` (相互リンク: `🏠 クラウドコンソールへ ↗`), `#btnToggleHeader` (ヘッダー隠す/表示), `#btnOpenGraphHelpHeader` (ガイド), `#systemStatusBadge` (正常稼働中)
2. **3 画面の削除**:
   - `#viewProduct`, `#viewSystem`, `#viewSupervisor` のマークアップブロックを一括削除。
   - `#viewGraph` を唯一のメインワークスペースとして保持。
3. **ワークスペースレイアウト調整**:
   - `.graph-workspace` の CSS を `height: calc(100vh - 48px - 36px)`（ヘッダー非表示時は `calc(100vh - 36px)`）に更新し、キャンバス領域を画面いっぱいに拡張。

### フェーズ 2: 相互リンクと JavaScript クリーンアップ
1. **`site/index.html` の相互リンク整備**:
   - ヘッダー内の `#portalSwitchBtn` のテキストを `🕸️ ナレッジグラフ ↗` に更新。
2. **`site/dashboard.html` JavaScript 調整**:
   - ヘッダー検索入力からグラフクエリを実行する `window.executeGraphHeaderSearch(query)` を実装。
   - レガシー互換用の `switchDashboardTab(tabName)` は、`product`/`system`/`supervisor` が渡された場合に `/index.html#/<tab>` へスマートリダイレクトする安全ロジックへ更新。
   - 削除された 3 画面用 DOM 更新処理（`supervisorWorkersTableBody`, `hopCanvas` 等）のエラー回避と安全化。

### フェーズ 3: テスト改定 & 品質ゲート検証
1. **テストスイート更新**:
   - `tests/web/test_dashboard_html.py` の `test_dashboard_mandatory_elements_and_canvas` を、単一グラフ画面・統一ヘッダー仕様に合わせてアサーションを改定。
   - `tests/web/test_dashboard_graph_tab.py` の `test_dashboard_mandatory_graph_tab_elements` を整理。
2. **品質ゲート triple-check**:
   - `make format` / `make check_format`
   - `make static_analysis` (Radon / Xenon Rank A, Mypy strict)
   - `.venv/bin/pytest tests/web/`
   - `make build_js`

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `http://localhost:8000/dashboard.html` にアクセスした際、`🕸️ Knowledge & CTI Graph` のみが表示され、Product / System / Supervisor のタブおよびコンテンツが存在しないこと。
- [x] `site/dashboard.html` のヘッダーが `site/index.html` と同一の Azure/AWS 調エンタープライズヘッダー（48px 固定、ブランド、検索、相互リンク、ステータスピル）となっていること。
- [x] `dashboard.html` のヘッダーから `index.html` へのリンク（`🏠 クラウドコンソールへ ↗`）が存在し、クリックで正しく遷移できること。
- [x] `index.html` のヘッダーから `dashboard.html` へのリンク（`🕸️ ナレッジグラフ ↗`）が存在し、クリックで正しく遷移できること。
- [x] 既存の CTI ナレッジグラフ機能（物理シミュレーション、ATT&CK/CWEフィルタ、リサーチギャップ探索、確信度フィルタ、ノード詳細ドロワー）が 100% 正常動作すること。
- [x] 外部ネットワーク依存（CDN / 外部 script / 外部 CSS）が 0 件であること (`test_dashboard_zero_external_dependencies` PASS)。
- [x] すべての自動テストおよび静的解析 (`make check_format`, `make static_analysis`, `pytest tests/web/`) が 100% PASS すること。
