---
ID: 341
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] ModalController: アクセシブル・モーダル＆ドロワー制御コンポーネントの実装 (ID: 341)

## 1. 概要 / Summary

現在 `site/app.js` 内で個別の DOM クラス操作（`.classList.add('active')` 等）によって分散制御されているモーダルダイアログ（論文詳細モーダル、設定モーダル、DBインスペクターモーダル等）およびサイドドロワーの開閉制御を、WAI-ARIA 仕様に完全準拠した共通コンポーネント `ModalController` として `site/js/frameworks/modal.js` に集約・実装する。

フォーカストラップ（Tab キー循環）、`Escape` キー押下による即時クローズ、背景オーバーレイクリック時の挙動、スクロールロック（`body` の overflow 制御）、および `AnimationUtils` と連携したフェード・スライドアニメーションの完全同期を提供する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-27: モジュール型 Web フロントエンド・フレームワーク ＆ クライアントアーキテクチャ設計仕様書](../designs/DSN-27-modular_frontend_framework_and_client_architecture.md) (セクション 5.3, 8)
  - [DSN-21: エンタープライズ統合デザインシステム ＆ クラウドコンソール UI 包括設計書](../designs/DSN-21-enterprise_design_system_and_unified_console.md)
- 関連 Issue:
  - [Issue 338: Webフロントエンド設計・アーキテクチャの刷新と yuzora frameworks の統合](closed/338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`site/js/frameworks/modal.js`](../../site/js/frameworks/modal.js) (新規)
- [ ] [`site/externs.js`](../../site/externs.js) (`ModalControllerInterface` 型定義追加)
- [ ] [`Makefile`](../../Makefile) (`JS_SRCS` 登録、`build_js` 検証)
- [ ] [`site/app.js`](../../site/app.js) (モーダル表示箇所の `ModalController` 移行)
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py) (テストケース追加)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/341-implement-accessible-modal-controller`

1. **`ModalController` クラスの設計と実装**:
   - `constructor(modalElement, options = {})`
   - メソッド: `open(contentPayload)`, `close()`, `isOpen()`, `setContent(htmlOrNode)`
   - WAI-ARIA 属性制御: `aria-modal="true"`, `role="dialog"`, `aria-hidden` の適切な切り替え
   - フォーカストラップ機構（最初と最後のフォーカス可能要素間での Tab ループ）
   - `AnimationUtils.waitForAnimation()` による閉幕アニメーション完了後の DOM 非表示化
2. **Closure Compiler 適合**:
   - `site/externs.js` に `ModalController` の型定義を追加
3. **`site/app.js` のリファクタリング**:
   - 各画面のモーダル（論文詳細、設定、エビデンス表示等）をインスタンス化して一元管理

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `site/js/frameworks/modal.js` が実装され、JSDoc 型アノテーションが付与されていること
- [ ] `site/externs.js` に `ModalController` の型定義が追加され、`make build_js` で警告 0 件であること
- [ ] フォーカストラップおよび `Escape` キーでの閉じる動作が正常に行われること
- [ ] 開閉時に `aria-hidden` および `body` のスクロールロックが適切に制御されること
- [ ] `tests/web/test_frontend_frameworks.py` にテストが追加され `pytest tests/web/` が 100% PASS すること
- [ ] `make verify_quality` が完全通過すること
