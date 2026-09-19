---
ID: 338
種別: Refactor
優先度: High
ステータス: Open (In Progress)
---

# [REFACTOR] Webフロントエンド設計・アーキテクチャの刷新と yuzora frameworks の統合 (ID: 338)

## 1. 概要 / Summary

現在の Web フロントエンド（`site/app.js`、`site/index.html`、`site/dashboard.html`、`site/js/` 等）のコードおよびコンポーネント設計を見直し、モジュール性・保守性・イベント駆動設計・レンダリング性能を抜本的に改善する包括的リファクタリングを実施する。

本リポジトリのフロントエンド（`site/app.js`）は 1,800 行を超えるモノリシックな構造となっており、DOM イベントリスナー、グローバル状態、API 通信、グラフ描画（Canvas）、SSE リアルタイム通知、検索結果レンダリングが混在している。
これを解決するため、設計基盤として作者同一・ライセンス完全適合（MIT互換）の軽量フレームワーク群（`yuzora/src/js/frameworks/`：アニメーション、DOMユーティリティ、イベントハブ、サービスロケータ、パブリッシャー、ルーター、シーン管理、スケジューラ、タイミング同期機構）を `site/js/frameworks/` 配下に取り込み、Google Closure Compiler による最適化ビルドパイプラインに適合させつつ、疎結合なイベント駆動アーキテクチャへと段階的にリファクタリングする。

---

## 2. トレーサビリティ / Traceability

- 取り込み元リポジトリ: `https://github.com/rokujyouhitoma/yuzora/tree/main/src/js/frameworks` (作者同一、ライセンス不問・OSS適合承認済)
- 対象コンポーネント:
  - フロントエンドコア: `site/app.js`, `site/externs.js`, `site/index.html`, `site/dashboard.html`
  - 新規フレームワーク群: `site/js/frameworks/*.js` (9モジュール)
  - ビルドパイプライン: `Makefile` (`build_js`, `JS_SRCS`)
  - テストスイート: `tests/web/`
- 関連過去 Issue:
  - [Issue 326: Webコンソール初期化時におけるTDZ参照エラーの解消およびテレメトリ・検索パイプライン堅牢化](closed/326-fix-web-console-initialization-tdz-reference-errors-and-telemetry-sync.md)
  - [Issue 327: Webコンソール ナビゲーションリンクの統廃合および死にリンク・循環リダイレクトの根絶](closed/327-reorganize-index-navigation-links-and-eliminate-dead-links.md)
  - [Issue 216: モック実装排除と実稼働データバインディング](closed/216-eliminate-mock-implementations-and-bind-real-runtime-data.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### 3.1 新規導入フレームワーク (`site/js/frameworks/`)
- [x] [`site/js/frameworks/animation.js`](../../site/js/frameworks/animation.js) - `AnimationUtils` (CSS/JS 連動トランジション・アニメーション完了待機)
- [x] [`site/js/frameworks/dom-utils.js`](../../site/js/frameworks/dom-utils.js) - `DOMUtils` (`afterReflow`, `afterRender` 等のフレーム同期)
- [x] [`site/js/frameworks/event.js`](../../site/js/frameworks/event.js) - `AppEvent`, `AppEventTarget`, `ScopedEventTarget` (型安全イベントハブ)
- [x] [`site/js/frameworks/locator.js`](../../site/js/frameworks/locator.js) - `Locator` (Service Locator パターンによる DI / シングルトン管理)
- [x] [`site/js/frameworks/publisher.js`](../../site/js/frameworks/publisher.js) - `Publisher` (Pub/Sub パターンによる疎結合メッセージング)
- [x] [`site/js/frameworks/router.js`](../../site/js/frameworks/router.js) - `Router` (ハッシュ連動 SPA ルーティング)
- [x] [`site/js/frameworks/scene.js`](../../site/js/frameworks/scene.js) - `SceneManager` (タブ・ビュー遷移ライフサイクル管理)
- [x] [`site/js/frameworks/scheduler.js`](../../site/js/frameworks/scheduler.js) - `Scheduler` (優先度付きタスクキュー・アイドル時バックグラウンド実行)
- [x] [`site/js/frameworks/timing.js`](../../site/js/frameworks/timing.js) - `TimingUtils` (デバウンス・スロットル・フレームレート補間)

### 3.2 既存フロントエンド・ビルド基盤
- [ ] [`site/externs.js`](../../site/externs.js) - Closure Compiler 向けフレームワーク型・インターフェース・グローバルシンボル定義
- [ ] [`Makefile`](../../Makefile) - `JS_SRCS` へのフレームワーク群順序定義の追加と `build_js` ビルド検証
- [ ] [`site/app.js`](../../site/app.js) - `Locator`, `Publisher`, `TimingUtils`, `Router` 連携へのリファクタリング
- [ ] [`site/index.html`](../../site/index.html) - コンソール画面でのフレームワークロード・初期化
- [ ] [`site/dashboard.html`](../../site/dashboard.html) - ダッシュボード画面でのフレームワーク連携
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py) (新規) - フレームワーク統合およびバンドル整合性回帰テスト

---

## 4. 脅威モデル分析とセキュリティ要件 (Threat Model & Security Requirements)

1. **XSS / DOM インジェクションの防止 (CWE-79)**:
   - `Router` による URL ハッシュ値（`location.hash`）の取得・画面切り替え時、未検証の文字列を直接 `innerHTML` に展開することを禁止。
   - 既存の `escapeHtml` ユーティリティを必ず経由し、サニタイズを徹底。
2. **Prototype Pollution の防止 (CWE-1321)**:
   - `Locator` のインスタンス登録（`register` / `locate`）において、`__proto__` や `prototype` への不正なプロパティ汚染を遮断。
3. **DoS / イベントループ飽和の防止 (CWE-400)**:
   - `Publisher` の購読ハンドラ内で同一トピックを再帰的に `publish` することによるコールスタックオーバーフローやブラウザフリーズを防止。
   - `TimingUtils.debounce` / `throttle` による検索入力（キー入力）および Canvas リサイズイベントのレートリミットを適用。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `refactor/338-refactor-web-frontend-architecture-and-import-yuzora-frameworks`

### Step 1: Closure Compiler 向け型・インターフェース定義の追加 (`site/externs.js`)
- Google Closure Compiler が `SIMPLE_OPTIMIZATIONS` / `VERBOSE` モードでプロパティ名やメソッド名を安全に処理できるよう、以下のインターフェースおよびクラス定義を追加：
  ```javascript
  /** @interface */
  function YuzoraEventInterface() {}
  /** @type {string} */ YuzoraEventInterface.prototype.type;
  /** @type {*} */ YuzoraEventInterface.prototype.detail;
  /** @type {?Object} */ YuzoraEventInterface.prototype.target;

  /** @interface */
  function YuzoraEventTargetInterface() {}
  /** @param {string} type @param {function(!YuzoraEventInterface): void} listener */
  YuzoraEventTargetInterface.prototype.addEventListener = function(type, listener) {};
  /** @param {string} type @param {function(!YuzoraEventInterface): void} listener */
  YuzoraEventTargetInterface.prototype.removeEventListener = function(type, listener) {};
  /** @param {!YuzoraEventInterface} event */
  YuzoraEventTargetInterface.prototype.dispatchEvent = function(event) {};
  /** @param {string} scopePrefix @return {!YuzoraEventTargetInterface} */
  YuzoraEventTargetInterface.prototype.scoped = function(scopePrefix) {};

  /** @interface */
  function LocatorInterface() {}
  /** @param {?} Class @return {?} */
  LocatorInterface.prototype.resolve = function(Class) {};
  /** @param {?} Class @return {?} */
  LocatorInterface.prototype.locate = function(Class) {};
  /** @param {?} Class @param {!Object} instance */
  LocatorInterface.prototype.register = function(Class, instance) {};

  /** @interface */
  function PublisherInterface() {}
  /** @param {string} topic @param {function(*): void} callback */
  PublisherInterface.prototype.subscribe = function(topic, callback) {};
  /** @param {string} topic @param {function(*): void} callback */
  PublisherInterface.prototype.unsubscribe = function(topic, callback) {};
  /** @param {string} topic @param {*=} data */
  PublisherInterface.prototype.publish = function(topic, data) {};
  /** @param {string} topic @param {*=} data */
  PublisherInterface.prototype.publishAsync = function(topic, data) {};

  /** @interface */
  function RouterInterface() {}
  /** @type {?string} */ RouterInterface.prototype.currentHash;
  /** @param {string} pattern @param {!Function} callback */
  RouterInterface.prototype.register = function(pattern, callback) {};
  /** @param {string} hash @return {boolean} */
  RouterInterface.prototype.resolve = function(hash) {};
  RouterInterface.prototype.listen = function() {};
  /** @param {string} hash */
  RouterInterface.prototype.navigate = function(hash) {};
  ```
- フレームワークの各クラスシンボル（`DOMUtils`, `TimingUtils`, `AppEvent`, `AppEventTarget`, `Publisher`, `Locator`, `Scheduler`, `SceneManager`, `Router`, `AnimationUtils`）を externs に宣言。

### Step 2: ビルドパイプラインの更新 (`Makefile`)
- `Makefile` の `JS_SRCS` 定義に依存関係順序で各モジュールを追加：
  ```makefile
  JS_SRCS = site/js/frameworks/dom-utils.js \
            site/js/frameworks/timing.js \
            site/js/frameworks/event.js \
            site/js/frameworks/publisher.js \
            site/js/frameworks/locator.js \
            site/js/frameworks/scheduler.js \
            site/js/frameworks/scene.js \
            site/js/frameworks/router.js \
            site/js/frameworks/animation.js \
            site/js/lexer.js \
            site/js/parser.js \
            site/js/evaluator.js \
            site/js/renderer.js \
            site/js/markdown_compiler.js \
            site/app.js
  ```
- `make build_js` を実行し、0 エラーで `site/app-min.js` が正常生成されることを確認。

### Step 3: `site/app.js` の疎結合化リファクタリング
- **Service Locator の導入**:
  - アプリケーション起動時に `const locator = new Locator();` を初期化。
  - グローバルなサービスインスタンス（状態管理オブジェクト、API クライアント、通知ハブ）を `locator.register(...)` で登録し、直接的なグローバル変数参照を解消。
- **Pub/Sub イベントハブの導入 (`Publisher`)**:
  - タブ切り替え（`tab:changed`）、検索実行（`search:query`）、SSE テレメトリ受信（`telemetry:updated`）、エクスポート実行（`export:requested`）を Pub/Sub トピックとして定義。
  - 各 UI コンポーネントが直接相手の DOM を操作するのではなく、イベント購読経由で状態を反映する構造へとリファクタリング。
- **デバウンス・スロットルの統合 (`TimingUtils`)**:
  - 検索入力フィールド（`#searchInput`）のインクリメンタル検索に `TimingUtils.debounce` を適用。
  - ウィンドウリサイズ時の Canvas 再描画処理に `TimingUtils.throttle` または `DOMUtils.afterReflow` を適用し、ジャンク（フレーム落ち）を解消。

### Step 4: 回帰テストスイートの追加 (`tests/web/test_frontend_frameworks.py`)
- Python 側のテストスイートとして以下を検証：
  - `site/js/frameworks/*.js` の全ファイル存在・非空性
  - `site/app-min.js` 内に各フレームワークのメソッド／クラスシンボルが含まれていること（バンドル整合性）
  - `site/externs.js` の構文整合性
  - 既存の 167 件の Web テストスイート（`tests/web/`）の全件通過

---

## 6. 完了条件 / Success Criteria (DoD)

1. [ ] `site/js/frameworks/` 配下に9つのフレームワークモジュールが正常に配置されていること。
2. [ ] `site/externs.js` に全フレームワーククラスおよびインターフェースが定義され、Closure Compiler で型警告・エラーが発生しないこと。
3. [ ] `Makefile` の `JS_SRCS` にフレームワーク群が正しく追加され、`make build_js` が 0 エラーでパスすること。
4. [ ] `site/app.js` において `Locator`, `Publisher`, `TimingUtils` が適切に活用され、コードの結合度が低減されていること。
5. [ ] 新規テストスイート `tests/web/test_frontend_frameworks.py` が追加され、全件 PASS すること。
6. [ ] 既存の 167 件の Web テストスイート（`pytest tests/web/`）がすべて PASS すること。
7. [ ] プロジェクトのトリプル品質ゲート（`make format`, `make static_analysis`, `make test`）および `make verify_quality` が 100% PASS すること。
