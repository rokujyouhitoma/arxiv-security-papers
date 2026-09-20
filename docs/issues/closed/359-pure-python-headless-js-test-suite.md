---
ID: 359
種別: Test / Quality
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] 柱 4: Pure Python (`pytest`) によるフロントエンド JS 構文・契約・整合性ヘッドレステストの洗練 (ID: 359)

## 1. 概要 / Summary
Node.js ベースのテストフレームワーク（Jest, Vitest, Mocha, Jasmine 等）やブラウザ自動化ライブラリ（Playwright, Puppeteer）を一切導入せず、本プロジェクトの「Zero-Mock / Pure Python」思想を徹底維持したまま、`pytest` スイート下でフロントエンド JavaScript の構文整合性、API 契約、DOM 要素 ID バインディング、および名前空間整合性を包括的・超高速に検証するヘッドレステスト基盤を洗練・拡充する。

本 Issue は、フロントエンド刷新 4 本柱の最終フェーズ（柱 4）として、分割されたモジュール群（`site/js/frameworks/*.js`、`site/js/*.js`、`site/app.js`、`site/js/dashboard.js`）および HTML テンプレート（`site/index.html`、`site/dashboard.html`）に対する厳格な回帰防止ラチェットを確立する。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue (フロントエンド刷新 4本柱 & 基盤):
  - [355-refactor-namespace-from-yuzora-to-application.md](closed/355-refactor-namespace-from-yuzora-to-application.md) (名前空間 Application 統一)
  - [356-eliminate-inline-scripts-and-modularize-by-domain.md](closed/356-eliminate-inline-scripts-and-modularize-by-domain.md) (柱 1: インラインスクリプト全廃とドメイン別ファイル分離)
  - [357-pure-python-bundling-and-build-pipeline.md](closed/357-pure-python-bundling-and-build-pipeline.md) (柱 2: 純粋 Python 連結・ビルドパイプライン)
  - [358-standard-jsdoc-and-strict-static-analysis.md](closed/358-standard-jsdoc-and-strict-static-analysis.md) (柱 3: 標準 JSDoc 契約定義と Closure Compiler 厳格静的検査)
  - [216-eliminate-mock-implementations-and-bind-real-runtime-data.md](closed/216-eliminate-mock-implementations-and-bind-real-runtime-data.md) (Zero-Mock 契約検証)
  - [338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md](closed/338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md) (フロントエンドアーキテクチャ刷新)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [tests/web/test_js_syntax_and_contracts.py](../../tests/web/test_js_syntax_and_contracts.py) (新規作成: Pure Python JS 構文・名前空間・契約静的検証スイート)
- [ ] [tests/web/test_zero_mock_integrity.py](../../tests/web/test_zero_mock_integrity.py) (拡張: HTML-JS DOM ID バインディング完全性検証の統合)
- [ ] [tests/web/test_frontend_frameworks.py](../../tests/web/test_frontend_frameworks.py) (強化: Node.js 非依存フォールバック／Pure Python 契約検査の拡充)
- [ ] [site/index.html](../../site/index.html) (要素 ID 定義の検査対象)
- [ ] [site/dashboard.html](../../site/dashboard.html) (要素 ID 定義の検査対象)
- [ ] [site/app.js](../../site/app.js) (Console メインスクリプト)
- [ ] [site/js/dashboard.js](../../site/js/dashboard.js) (Dashboard メインスクリプト)
- [ ] [site/externs.js](../../site/externs.js) (Closure Compiler 外部インターフェース定義)
- [ ] [site/js/frameworks/](../../site/js/frameworks/) (全 19 フレームワークモジュール群)

---

## 4. 脅威モデルおよびセキュリティ要件 / Threat Model & Security Requirements
1. **DOM Clobbering / XSS 防御**:
   - `id="..."` の未定義参照やグローバルスコープ汚染は、悪意ある要素注入による DOM Clobbering や prototype 汚染の温床となる。
   - テストスイートにて `window` 直下の未宣言変数代入および非名前空間化されたグローバル変数の完全排除を保証する。
2. **ランタイム Null 参照例外（DoS / UI クラッシュ）の未然防止**:
   - `document.getElementById(...)` の戻り値が `null` となる ID 名の不整合（タイポや HTML 側での削除漏れ）は、ブラウザ側で `TypeError: Cannot read properties of null` を引き起こし、UI の完全停止（クラッシュ）を招く。
   - 静的ラチェットテストにより、JS が参照するすべての要素 ID が HTML 上に実在することをビルド・テスト時に 100% 保証する。
3. **Strict Mode 強制による危険な構文の抑止**:
   - `'use strict';` を全モジュールで強制し、暗黙のグローバル生成、`with` 構文、重複引数名などの危険な JavaScript イディオムを静的に拒絶する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/359-pure-python-headless-js-test-suite`

### 5.1 新規テストスイート `tests/web/test_js_syntax_and_contracts.py` の実装
1. **Strict Mode 宣言の全網羅検査 (`test_all_js_files_declare_use_strict`)**:
   - `site/app.js`、`site/js/dashboard.js`、`site/js/*.js`、`site/js/frameworks/*.js` の全 JS ファイルを走査。
   - ファイル冒頭またはトップレベル IIFE の先頭で `'use strict';` が宣言されていることを検証。
2. **グローバルスコープ汚染防止と名前空間整合性検査 (`test_no_unscoped_globals_and_namespace_compliance`)**:
   - IIFE 外での未カプセル化な `var`, `let`, `const`, `function` 宣言を検出し、グローバル `window` 汚染を遮断。
   - フレームワーク全 19 モジュールが `window.Application` または `Application.frameworks` に統制されてエクスポートされていることを検証。
3. **構文バランス・構造的衛生検査 (`test_js_structural_syntax_hygiene`)**:
   - 中括弧 `{}`、角括弧 `[]`、丸括弧 `()` のネストバランス検証。
   - クローズされていない文字列リテラルやバッククォートの検知。
   - 残存禁止キーワード（`debugger;`、`alert(`、バンドル連結を破壊する ES モジュール構文 `export default` 等）の排除検証。
4. **JSDoc / Externs 契約整合性検査 (`test_externs_and_implementation_contracts`)**:
   - `site/externs.js` に宣言された公開クラス・インターフェースメソッドが、実装モジュール側（`site/js/frameworks/`）に同名メソッドとして漏れなく存在することを静的に検証。
5. **バンドル定義整合性検査 (`test_build_manifest_file_existence`)**:
   - `scripts/compile_frontend.py` の `APP_SRCS` および `DASHBOARD_SRCS` に記載された全ファイルが実在し、空でないことを検証。

### 5.2 HTML-JS DOM 要素 ID バインディング整合性検証 (`test_zero_mock_integrity.py` 拡張)
1. **静的 ID 抽出エンジンの構築**:
   - `site/index.html` および `site/dashboard.html` から `id="([a-zA-Z0-9_\-]+)"` を自動抽出して集合化。
2. **JS 側参照 ID の抽出と突合 (`test_html_element_ids_binding_integrity`)**:
   - `site/app.js` から `getElementById('...')`, `querySelector('#...')` 等で参照される ID を抽出。
   - `site/index.html` の ID 集合と突合し、タイポや未定義 ID を 0 件としてアサート。
   - `site/js/dashboard.js` から参照される ID を抽出し、`site/dashboard.html` の ID 集合と突合。
   - 動的生成 ID（例: `tab-pane-${id}`, `node-${id}`）については明示的なプレフィックス／ホワイトリストで管理。

### 5.3 `test_frontend_frameworks.py` のヘッドレス堅牢化
1. **Node.js 非依存フォールバック契約検証**:
   - 現在 `shutil.which("node")` で Node.js 未検出時にスキップ（return）されているテストに対し、Pure Python による静的遷移ルール・ステートノードトポロジー検証を付加。
   - Node.js が存在しない Pure Python CI 環境でも、HSM やアルゴリズムの整合性テストがスキップされずに 100% PASS する耐障害性を確保。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 新規テストファイル `tests/web/test_js_syntax_and_contracts.py` が追加され、すべての JS ソースに対する構文・Strict Mode・名前空間・契約検査が実装されていること。
- [x] `tests/web/test_zero_mock_integrity.py` に HTML-JS 間 DOM ID バインディング完全性検証テストが追加され、不整合 ID が 0 件であること。
- [x] `tests/web/test_frontend_frameworks.py` が Node.js 非依存で確実な静的契約検証を実施できること。
- [x] 外部 Node.js / npm ライブラリやブラウザ自動化依存を一切追加せず、Pure Python (`pytest`) のみでミリ秒単位で高速実行されること。
- [x] `make test` および `make check`（フォーマット・静的解析・テスト）が 100% PASS すること。
