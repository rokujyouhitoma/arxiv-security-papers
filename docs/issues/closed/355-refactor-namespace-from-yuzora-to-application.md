---
ID: 355
種別: Refactor
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] 名前空間の汎用化: 他プロジェクト名 `yuzora` から汎用的な `Application` への刷新 (ID: 355)

## 1. 概要 / Summary
現在、フロントエンドの基盤フレームワークモジュール（`site/js/frameworks/`）および各画面スクリプト（`site/app.js`, `site/dashboard.html`）では、名前空間として `window.yuzora` および `window.yuzora.frameworks` が使用されていた。
しかし「yuzora」は別プロジェクトの名称であるため、特定の外部プロジェクトに依存しない汎用的な名称 `Application`（およびショートハンド `App`）へ統一改称・刷新した。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue:
  - [338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md](closed/338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md)
  - [349-integrate-apiclient-and-arc-cache-across-frontend.md](closed/349-integrate-apiclient-and-arc-cache-across-frontend.md)
  - [354-apply-modal-controller-to-all-dialogs-and-drawers.md](closed/354-apply-modal-controller-to-all-dialogs-and-drawers.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [site/js/frameworks/*.js](../../site/js/frameworks/) (全19フレームワークモジュールの export 定義)
- [x] [site/externs.js](../../site/externs.js) (Closure Compiler 向け extern 定義)
- [x] [site/app.js](../../site/app.js) (`window['yuzora']` 参照箇所)
- [x] [site/dashboard.html](../../site/dashboard.html) (`window['yuzora']` 参照箇所)
- [x] [tests/web/test_frontend_frameworks.py](../../tests/web/test_frontend_frameworks.py) (名前空間アサーション)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/355-refactor-namespace-to-application`

1. **名前空間の改称**:
   - `window.yuzora` を `window.Application`（および `window.App = window.Application`）に置き換え。
   - `Application.frameworks` (または `Application.core`) に各クラスをバインド。
   - 移行期間の安全策として、万一の下位互換用エイリアス (`window.yuzora = window.Application`) を一時的に許容しつつ、コードベース内は `Application` に完全置換。
2. **`site/externs.js` の型定義更新**:
   - `var yuzora = {};` を `var Application = {};` に更新。
3. **リグレッション検証**:
   - Web 統合テスト 175 件全件 PASS、Closure Compiler コンパイル 0 エラーの確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 全フレームワークモジュールが `window.Application` / `Application.frameworks` 下に配置されていること。
- [x] `site/app.js` および `site/dashboard.html` から `yuzora` への直接依存が解消されていること。
- [x] Closure Compiler によるコンパイルが 0 Warnings, 0 Errors で完了すること。
- [x] 全 175 件の Web 統合テストが 100% PASS すること。
