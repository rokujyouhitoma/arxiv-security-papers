---
ID: 354
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] `ModalController`: 全モーダル・ドロワー要素のアクセシブル制御とフォーカストラップ統一 (ID: 354)

## 1. 概要 / Summary
現在、`site/app.js` では論文詳細モーダル (`paperModal`) のみに `site/js/frameworks/modal.js` の `ModalController` が部分適用されていた。
`site/index.html` に存在するコンソールヘルプドロワー (`consoleHelpDrawer` / `consoleHelpOverlay`)、および `site/dashboard.html` のグラフ操作ヘルプドロワー (`graphHelpDrawer` / `graphHelpOverlay`)、ノード詳細インスペクター等にも `ModalController` を全面適用し、フォーカストラップ、Escape キーでの閉鎖、ARIA 属性 (`aria-modal`, `aria-hidden`) を統一した。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue:
  - [341-implement-accessible-modal-controller.md](closed/341-implement-accessible-modal-controller.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [site/index.html](../../site/index.html) (モーダル・ドロワー要素の ARIA マークアップ)
- [x] [site/app.js](../../site/app.js) (`consoleHelpDrawer`, `paperModal` の `ModalController` 統合)
- [x] [site/dashboard.html](../../site/dashboard.html) (`graphHelpDrawer` の `ModalController` 適用)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/354-apply-modal-controller-to-all-dialogs`

1. **`site/app.js`**:
   - `helpDrawerModal = new ModalController(consoleHelpDrawer, { closeOnOverlayClick: true, overlaySelector: '#consoleHelpOverlay' })` を初期化。
   - `window.toggleConsoleHelpDrawer` / `window.closeConsoleHelpDrawer` をコントローラーに委譲しつつ、既存グローバル関数のフォールバックシグネチャを完全維持。
   - `paperModal` の閉鎖ロジック (`closeFullscreenModal`) も `appPaperModal.close()` に委譲。
2. **`site/dashboard.html`**:
   - `graphHelpModal = new ModalController(graphHelpDrawer, { closeOnOverlayClick: true, overlaySelector: '#graphHelpOverlay' })` を初期化。
   - `window.toggleGraphHelpDrawer` / `window.closeGraphHelpDrawer` をコントローラーに委譲。
3. **アクセシビリティ検証**:
   - Closure Compiler 静的解析 0 エラー確認。
   - Web 統合テスト 175 件 100% PASS。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] すべてのモーダル・ドロワーで Escape キーおよびバックドロップクリックによる安全な閉鎖ができること。
- [x] モーダル開放時にフォーカスがモーダル内部にトラップされ、閉じると元の要素に復帰すること。
- [x] 回帰テスト全件 PASS、Closure Compiler コンパイル 0 エラー。
