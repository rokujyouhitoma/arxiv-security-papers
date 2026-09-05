---
ID: 171
種別: Feature
優先度: High
ステータス: Closed (Done)
---

# [FEAT/ENH] Unify index.html Help Guide Drawer with dashboard.html Design & Interaction (ID: 171)

## 1. 概要 / Summary
`site/dashboard.html` で実装されている「Graph 操作ガイド & 用語解説」の出し方（右側スライドインドロワー、半透明ブラーオーバーレイ、ESC/?キー操作、✕ボタン）および洗練されたグラスモーフィズムデザインを元にして、`site/index.html`（エンタープライズクラウドコンソール）の「❓ ガイド」機能を統一実装する。

現在 `site/index.html` のヘッダーには `#helpModalBtn`（「❓ ガイド」）が存在するが、ドロワーやオーバーレイが未実装である。本改修により、ダッシュボードと同様に一貫したエンタープライズ級のUI/UX体験を提供し、コンソールの基本操作、キーボードショートカット、各ビュー（Product, System, Supervisor）の役割、検索機能（Ctrl+K）、ナレッジグラフとの連携方法を網羅した「📖 エンタープライズコンソール 操作ガイド & 機能解説」ドロワーを提供する。

---

## 2. トレーサビリティ / Traceability
- **ユーザー要求**: UIUX index.htmlのガイドは、dashboard.htmlの「Graph 操作ガイド & 用語解説」の出し方、デザインを元にして、統一してください。
- **先行 Issue**:
  - Issue 166: `implement-glassmorphic-tooltips-and-graph-uiux-guide` (dashboard.htmlのドロワー実装)
  - Issue 167: `implement-enterprise-cloud-console-ui-and-design-system-unification`
  - Issue 169: `port-product-system-supervisor-views-to-index-console`
  - Issue 170: `unify-dashboard-header-with-index-and-retain-graph-only`
- **デザインシステム要件**:
  - ゼロ外部依存（Pure CSS / Pure JavaScript、CDN不使用）
  - ダークグラスモーフィズム（`rgba(15, 23, 42, 0.95)`, `backdrop-filter: blur(24px)`, `box-shadow: -12px 0 40px rgba(0, 0, 0, 0.6)`）
  - 右側からのスムーズなスライドインアニメーション（`cubic-bezier(0.16, 1, 0.3, 1)`）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [site/index.html](file:///workspace/arxiv-security-papers/site/index.html):
  - `.help-overlay`, `.help-drawer`, `.drawer-header`, `.btn-drawer-close`, `.drawer-content`, `.guide-section`, `.guide-table` の CSS 定義
  - `#consoleHelpOverlay`, `#consoleHelpDrawer` の HTML 構造の追加
  - ヘッダー `#helpModalBtn` へのクリックハンドラバインド (`onclick="toggleConsoleHelpDrawer()"`)
  - ドロワー制御 JS 関数 (`window.toggleConsoleHelpDrawer`, `window.closeConsoleHelpDrawer`) の実装
  - キーボードショートカット (`?`, `Escape`) リスナーの実装
- [x] [tests/web/test_enterprise_console_ui.py](file:///workspace/arxiv-security-papers/tests/web/test_enterprise_console_ui.py):
  - ガイドドロワー、オーバーレイ、セクション構造、キーボード操作、トグル関数のテストアサーション追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/171-unify-index-help-guide-drawer`

1. **CSS 設計 (`site/index.html`)**:
   - `dashboard.html` の `.graph-help-overlay`, `.graph-help-drawer`, `.drawer-header`, `.btn-drawer-close`, `.drawer-content`, `.guide-section`, `.guide-table` のスタイルを `index.html` に適用（または共用可能な汎用クラス `.help-overlay`, `.help-drawer` として定義）。
   - z-index は既存のヘッダーやモーダルと整合（`z-index: 10001`, `10002`）。
2. **HTML 構造の追加 (`site/index.html`)**:
   - `body` 末尾にオーバーレイとドロワー要素を配置：
     - `#consoleHelpOverlay` (`.help-overlay`)
     - `#consoleHelpDrawer` (`.help-drawer`)
       - `.drawer-header`: アイコン + `<h3>📖 エンタープライズコンソール 操作ガイド & 機能解説</h3>` + `btn-drawer-close` (✕)
       - `.drawer-content`:
         - Section 1: 🎮 基本マウス & キーボードショートカット (`Ctrl+K`, `?`, `Esc`, `1-4` タブ切り替え等)
         - Section 2: 🏢 コンソールの主要ワークスペース (Product & Analytics, System & Observability, Supervisor & Process Top)
         - Section 3: 🕸️ ナレッジグラフ連携 (CTI Graph, ATT&CK, CWE)
         - Section 4: 🛡️ データ保全・トレーサビリティ & OKF v0.2 仕様
3. **JavaScript インタラクションの実装**:
   - `window.toggleConsoleHelpDrawer = function()`: ドロワーとオーバーレイの `.active` クラスをトグル。
   - `window.closeConsoleHelpDrawer = function()`: クラスを削除して確実に閉じる。
   - `#helpModalBtn` に `onclick="toggleConsoleHelpDrawer()"` を付与。
   - `keydown` イベントリスナーで `Escape` によるクローズ、`?` (または `Shift+/`) によるトグルを実装（入力フォーム非フォーカス時）。
4. **テストスイート拡充 & 品質ゲート検証**:
   - `tests/web/test_enterprise_console_ui.py` にテストケースを追加。
   - `make check_format` および `make static_analysis` の検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `site/index.html` に `dashboard.html` と同一のデザイン・出し方のヘルプドロワー (`#consoleHelpDrawer`, `#consoleHelpOverlay`) が実装されていること。
- [x] ヘッダーの `❓ ガイド` ボタンをクリックすると、右側からドロワーがスライドイン表示されること。
- [x] ドロワー右上の「✕」ボタン、背景オーバーレイクリック、または `Escape` キーでドロワーが閉じること。
- [x] テキスト入力中を除き、`?` キーでドロワーを開閉できること。
- [x] ガイド内容がエンタープライズコンソールの各機能・ショートカット・ナレッジグラフ連携を正確に解説していること。
- [x] 外部依存（CDN等）がゼロであること。
- [x] `tests/web/test_enterprise_console_ui.py` を含むテストが全件 PASS すること。
- [x] `make check_format` および `make static_analysis` がエラー0件で合格すること。
