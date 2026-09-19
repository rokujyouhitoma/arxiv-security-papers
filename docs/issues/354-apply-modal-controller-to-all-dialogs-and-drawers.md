---
ID: 354
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] `ModalController`: 全モーダル・ドロワー要素のアクセシブル制御とフォーカストラップ統一 (ID: 354)

## 1. 概要 / Summary
現在、`site/app.js` では論文詳細モーダル (`paperModal`) のみに `site/js/frameworks/modal.js` の `ModalController` が部分適用されている。
`site/index.html` に存在するヘルプモーダル (`helpModal`)、通知オーバーレイ、および `site/dashboard.html` の右側ノード詳細インスペクタードロワー (`nodeDrawer`) など、他のダイアログ・オーバーレイにも `ModalController` を適用し、フォーカストラップ、Escape キーでの閉鎖、ARIA 属性 (`aria-modal`, `aria-hidden`) を統一する。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue:
  - [341-implement-accessible-modal-controller.md](closed/341-implement-accessible-modal-controller.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [site/index.html](../site/index.html) (モーダル要素の ARIA マークアップ)
- [ ] [site/app.js](../site/app.js) (`helpModal` 等のコントローラー初期化)
- [ ] [site/dashboard.html](../site/dashboard.html) (`nodeDrawer` のコントローラー適用)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/354-apply-modal-controller-to-all-dialogs`

1. `site/index.html` の各種モーダル（ヘルプ、通知等）を `ModalController` でインスタンス化。
2. `site/dashboard.html` のノード詳細ドロワーを `ModalController` で制御（開閉アニメーション・オーバーレイ管理）。
3. キーボードナビゲーション（Tab によるトラップ、Escape での復帰）の動作確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] すべてのモーダル・ドロワーで Escape キーおよびバックドロップクリックによる安全な閉鎖ができること。
- [ ] モーダル開放時にフォーカスがモーダル内部にトラップされ、閉じると元の要素に復帰すること。
- [ ] Closure Compiler によるコンパイルがエラー 0 件であること。
