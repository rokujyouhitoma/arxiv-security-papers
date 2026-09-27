---
ID: 400
種別: Bug
優先度: High
ステータス: Closed (Completed)
---

# [BUG/SEC] site/app.js における SceneCtor 未定義エラー (ReferenceError) の解消 (ID: 400)

## 1. 概要 / Summary
Web コンソール (`http://localhost:8000/`) アクセス時、および URL クエリパラメータ指定時 (`?tab=search#/search`) において、`site/app.js` の `createTabScene` 関数内で未宣言の変数 `SceneCtor` を参照してしまい、`Uncaught ReferenceError: SceneCtor is not defined` が発生してフロントエンドのタブ初期化・イベント購読・UI描画が完全に停止する不具合。

### 再現手順 / Steps to Reproduce
1. Web サーバーを起動する (`python3 -m src.web.gateway.server` または `make run_web`)。
2. ブラウザで `http://localhost:8000/?tab=search#/search` (または任意のタブ URL) を開く。
3. 開発者コンソール (Console) を確認すると、以下の例外がスローされ画面の初期化が停止する:
   ```text
   app.js:291 Uncaught ReferenceError: SceneCtor is not defined
       at createTabScene (app.js:291:32)
       at HTMLDocument.<anonymous> (app.js:307:44)
   ```

### 再現環境 / Environment
- OS / Env: Linux / Any Modern Web Browser (Chrome, Firefox, Safari)
- File: [site/app.js](../../../site/app.js) (Line 284-302)
- URL: `http://localhost:8000/?tab=search#/search`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [site/app.js](../../../site/app.js) - `createTabScene` 内で `SceneInterface` を直接実装する安全なクラス構造へ是正
- [x] [site/app-min.js](../../../site/app-min.js) - Closure Compiler (`scripts/compile_frontend.py`) によるバンドル成果物の再生成
- [x] [tests/web/test_js_syntax_and_contracts.py](../../../tests/web/test_js_syntax_and_contracts.py) - 未宣言識別子クラス継承の静的検証テスト追加
- [x] [tests/web/test_frontend_frameworks.py](../../../tests/web/test_frontend_frameworks.py) - `SceneDirector` & `TabScene` ライフサイクル Node.js 回帰テスト追加
- [x] [docs/issues/README.md](../README.md) - Issue 台帳のステータス管理

---

## 3. ガバナンス・専門エージェント多角的レビュー / Multi-Perspective Review

### Project Manager (PM)
- **優先度判断**: High。Web コンソール初回ロード時に JavaScript の実行が停止し、タブ切り替えや検索機能が動作しなくなる致命的リグレッションである。
- **目標**: 最小限の安全な変更で `SceneCtor` の未定義エラーを恒久解消し、ビルド・静的解析・テストの全品質ゲートを完全通過させる。

### Software Development (SWD)
- `createTabScene` において、外部の不確実なグローバル変数 `SceneCtor` への依存を排除し、`SceneInterface` を直接実装する軽量かつ堅牢な `class TabScene` を生成・返却する構造へリファクタリング。
- Closure Compiler の厳格型検査（strict=True）と 100% 互換性を保ち、ブラウザ実行時にも未定義例外が発生しない設計を確立。

### Software Quality Assurance Specialist (QA)
- Closure Compiler の externs 定義 (`site/externs.js`) とブラウザ実行時スコープの乖離を再発防止。
- Pure-Python テストスイート (`tests/web/test_js_syntax_and_contracts.py` および `tests/web/test_frontend_frameworks.py`) にて、`site/app.js` 内でクラス継承 (`extends <Identifier>`) される親クラス識別子がスコープ内で宣言・定義されていることを保証する回帰テストを追加。

### Application Specialist (APS)
- タブライフサイクル（Search, Trends, Product, System, Database, Spider, Supervisor, MCP）の SceneDirector 登録が正常に完遂し、ハッシュ遷移および `switchToTab` によるライフサイクルイベント（`enter` / `exit`）が正しく発火することを保証。

---

## 4. 根本原因分析 (RCA) / Root Cause Analysis

1. **未宣言識別子へのアクセス (Unbound Identifier Reference)**:
   [site/app.js](../../../site/app.js) において、以下のコードが存在していた:
   ```javascript
   const createTabScene = (onEnter, onExit) => {
     if (resolveFramework('Scene')) {
       /**
        * @extends {SceneCtor}
        */
       class TabScene extends SceneCtor {
         enter(data) { if (onEnter) onEnter(data); }
         exit() { if (onExit) onExit(); }
       }
       return new TabScene();
     }
     return /** @type {!SceneInterface} */ ({ enter: onEnter || (() => {}), exit: onExit || (() => {}) });
   };
   ```
   ここで `class TabScene extends SceneCtor` において、スコープ内に一切宣言されていない変数 `SceneCtor` を直接参照していた。

2. **Closure Compiler Externs とブラウザ実行時スコープの乖離**:
   Issue 358 において Closure Compiler の JSDoc 型チェック（`@extends {SceneCtor}`）を通すため、`site/externs.js` に `function SceneCtor() {}` が externs として定義された。
   Closure Compiler はコンパイル時に externs をグローバル変数とみなすためコンパイルエラーを検出できず、そのまま `site/app-min.js` を生成した。
   しかしブラウザ実行時（開発版 `app.js`、本番版 `app-min.js` 双方）には `SceneCtor` という名前のグローバル変数は存在しない。そのため、`DOMContentLoaded` 直後の初期化時に即座に `ReferenceError` がスローされ、全処理が中断していた。

---

## 5. 暫定対処と恒久対策 / Workaround & Permanent Fix

* **暫定対処 (Workaround)**: なし（即時恒久対応を実施）。
* **恒久対策 (Permanent Fix)**:
  1. [site/app.js](../../../site/app.js) の `createTabScene` において、未宣言の `SceneCtor` 継承を廃止し、`SceneInterface` に準拠した `class TabScene`（`enter(data)` および `exit()` を実装）を直接インスタンス化して返却する。
  2. `python3 scripts/compile_frontend.py` (`make build_js`) を実行し、バンドル成果物 [site/app-min.js](../../../site/app-min.js) を再コンパイル・同期する。
  3. [tests/web/test_js_syntax_and_contracts.py](../../../tests/web/test_js_syntax_and_contracts.py) および [tests/web/test_frontend_frameworks.py](../../../tests/web/test_frontend_frameworks.py) に回帰防止テストを追加し、スコープ未宣言クラス継承の自動検出および SceneDirector 登録の完全性を担保する。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `fix/400-fix-scenector-reference-error`

1. **`site/app.js` の `createTabScene` 修正**:
   - `createTabScene` 内で `SceneInterface` を実装する `TabScene` クラスを定義。
   - 不安定な `SceneCtor` 参照を完全除去。
2. **フロントエンド成果物の再ビルド**:
   - `python3 scripts/compile_frontend.py` を実行。
   - Google Closure Compiler による厳格コンパイル（strict=True）を通過させ、`site/app-min.js` を正常出力。
3. **回帰テストスイートの拡充**:
   - `tests/web/test_js_syntax_and_contracts.py` に `test_no_unbound_class_extends_and_scenector_hygiene` を追加。
   - `tests/web/test_frontend_frameworks.py` に `test_scene_and_tab_scene_lifecycle` を追加。
4. **品質ゲートの全パス検証**:
   - `make check_format` (PASS)
   - `make static_analysis` (PASS)
   - `make py_compile` (PASS)
   - `make build_js` (PASS)

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] [site/app.js](../../../site/app.js) において `SceneCtor` の未宣言参照が完全に除去され、`TabScene` が安全にインスタンス化されること。
- [x] ブラウザコンソールで `http://localhost:8000/?tab=search#/search` およびトップページにアクセスした際、`Uncaught ReferenceError: SceneCtor is not defined` がスローされず、全タブが正常初期化されること。
- [x] `scripts/compile_frontend.py` (`make build_js`) によるコンパイルがエラー・警告 0 件で成功し、[site/app-min.js](../../../site/app-min.js) が最新状態に更新されること。
- [x] [tests/web/test_js_syntax_and_contracts.py](../../../tests/web/test_js_syntax_and_contracts.py) および [tests/web/test_frontend_frameworks.py](../../../tests/web/test_frontend_frameworks.py) に回帰テストが追加され、pytest が 100% PASS すること。
- [x] `make check_format` および `make static_analysis` (radon, xenon, flake8, black, isort, mypy) が 0 エラーで合格すること。
- [x] [docs/issues/README.md](../README.md) のステータスが `Closed` に更新され、アーカイブされること。

