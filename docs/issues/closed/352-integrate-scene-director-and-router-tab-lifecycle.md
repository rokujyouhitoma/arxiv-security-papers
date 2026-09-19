---
ID: 352
種別: Refactor
優先度: Medium
ステータス: Closed (Completed)
完了日: 2026-09-19
---

# [FEAT/ENH] `SceneDirector` & `Router`: タブナビゲーションのライフサイクルガバナンスと URL ディープリンク同期 (ID: 352)

## 1. 概要 / Summary
`site/app.js` のタブ切り替え処理 (`switchToTab`) は、現在手動のクラス付け替えおよび分岐条件によるタイマー開始/停止 (`startSpiderAutoPolling`, `stopSpiderAutoPolling`) で行われており、タブ離脱時のリソース破棄漏れリスクが存在する。
これを `site/js/frameworks/scene.js` の `SceneDirector` / `Scene` に置き換えてライフサイクル (`enter`, `exit`, `render`) を宣言的に管理し、併せて `site/js/frameworks/router.js` の `Router` で URL Hash / クエリ履歴と完全に同期させる。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue:
  - [338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md](closed/338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [site/app.js](../site/app.js) (`switchToTab`, `handleRoute`, `TAB_CONFIG`)
- [ ] [site/index.html](../site/index.html) (ナビゲーションリンク、タブコンテナ)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/352-integrate-scene-director-and-router`

1. **`Scene` の定義**:
   - `SearchScene`, `TrendsScene`, `ProductScene`, `SystemScene`, `DatabaseScene`, `SpiderScene` を定義。
   - `SpiderScene.prototype.enter` でポーリング開始、`SpiderScene.prototype.exit` で確実にタイマー停止を保証。
   - `TrendsScene.prototype.enter` でデータ取得・チャートレンダリング。
2. **`SceneDirector` による統括**:
   - `appSceneDirector` に全シーンを登録し、`transitionTo(sceneId, params)` で遷移。
3. **`Router` のバインド**:
   - `router.addRoute('/papers', ...)`、`router.addRoute('/trends', ...)` 等を登録。
   - ブラウザの「進む」「戻る」ボタン (`popstate`) とタブ遷移の完全同期。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] タブの切り替えが `SceneDirector` 経由で行われ、離脱時にタイマーやリスナーが確実に解放されること。
- [ ] URL Hash / SearchParams の変更が `Router` で双方向同期されること。
- [ ] 既存の全回帰テスト (`pytest tests/web/`) が 100% PASS すること。
