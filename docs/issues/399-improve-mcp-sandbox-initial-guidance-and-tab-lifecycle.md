---
ID: 399
種別: Bug
優先度: Medium
ステータス: Open (New)
---

# [BUG/SEC] MCP JSON-RPC サンドボックスの初期ガイダンス改善およびタブ遷移ライフサイクルの整備 (ID: 399)

## 1. 概要 / Summary

Web コンソールの「🔌 Model Context Protocol (MCP) JSON-RPC サンドボックス」（`#/mcp`）画面において、JSON-RPC レスポンス表示領域に常時 `{ "status": "idle" }` と表示されたままとなり、処理が停止している、あるいはツールが利用不可となっているように見えるユーザビリティ上の課題・不具合が発生している。

### 再現手順 / Steps to Reproduce

1. Web コンソール（`http://localhost:8000/`）を開く。
2. 左側サイドバーから「🔌 MCP ツールサンドボックス」（`#/mcp`）を選択する。
3. 画面下部の「JSON-RPC レスポンス:」領域に `{ "status": "idle" }` と表示されたままとなる。
4. 他のタブのように自動的なステータス取得や初回ガイドが行われず、実行前なのか異常停止しているのか判別しにくい。
5. また、デフォルトツール（`search_security_papers`）を実行しても、Issue 398 の影響により空結果（0件）が返却される。

### 再現環境 / Environment

- OS / Env: Browser / Web Gateway UI
- File: [site/index.html](../../site/index.html), [site/app.js](../../site/app.js)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [site/index.html](../../site/index.html)
- [ ] [site/app.js](../../site/app.js)
- [ ] [src/mcp/papers_server.py](../../src/mcp/papers_server.py)
- [ ] [tests/web/test_web_server.py](../../tests/web/test_web_server.py)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

1. **静的プレースースホルダーのミスリーディング**:
   - `site/index.html` (L309) の `<pre id="mcpOutput" class="code-block">{ "status": "idle" }</pre>` が静的に配置されており、実行待機中（未実行）であることを明示するガイダンスメッセージになっていない。
2. **タブ遷移時（SceneDirector）ライフサイクルの不在**:
   - 他のタブ（トレンド、データベース、システム観測、スパイダー等）では、`appSceneDirector.register(..., createTabScene(onEnter, onExit))` によりタブ遷移時に初期データのフェッチや初期化処理が自動実行される。
   - 一方で `mcpTab` は `createTabScene(null, null)` と登録されており、タブ表示時の初期化処理（ツールの稼働ステータス確認、またはガイダンス表示の最適化）が一切定義されていない。
3. **検索ツール連携の波及**:
   - サンドボックスのデフォルト選択ツールである `search_security_papers` が、Issue 398 のインデックスパス不整合の影響で `results: []`（0件）を返すため、ボタンを押しても成果物が得られない状態となっていた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix

* **暫定対処 (Workaround)**:
  「⚡ MCP ツール呼び出し実行」ボタンをクリックし、手動で JSON-RPC 呼び出しを行う。
* **恒久対策 (Permanent Fix)**:
  - `site/index.html` の初期表示を「待機中: 上記の MCP ツールと引数を確認し、『⚡ MCP ツール呼び出し実行』をクリックしてください。」などの明確なユーザーガイダンスに変更する。
  - `site/app.js` の `mcpTab` ライフサイクル（`createTabScene` の `onEnter`）において、MCP サーバーの稼働ヘルスチェックまたはツール一覧の初期ステータス反映をサポートする。
  - Issue 398 の解消と連動させ、デフォルトツール実行時に正常な論文検索結果が返却されることを担保する。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `fix/399-mcp-sandbox-guidance-and-lifecycle`

1. **UI プレースホルダーの刷新 (`site/index.html`)**:
   - `#mcpOutput` の初期コンテンツを、JSON-RPC の実行待機状態であることが一目で分かる案内メッセージに更新。
2. **タブライフサイクルの連携 (`site/app.js`)**:
   - `appSceneDirector.register('mcpTab', ...)` に `onEnter` ハンドラを追加。
   - タブ表示時に MCP エンドポイント（`/api/mcp`）の疎通状況やツール準備完了状態を表示するステータスバッジまたは初期表示を整備。
3. **E2E / 単体テストの追加**:
   - Web サーバーの `/api/mcp` ハンドラおよびフロントエンドの描画テストを検証。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] MCP サンドボックス画面を開いた際に、未実行状態であることが明確に把握できるガイダンスが表示されること。
- [ ] 「⚡ MCP ツール呼び出し実行」をクリックした際、`search_security_papers` などのツールが正常に実行され、有効な JSON-RPC レスポンスが整形表示されること。
- [ ] `mcpTab` へのタブ遷移時にエラーが発生せず、SceneDirector ライフサイクルが正常に動作すること。
- [ ] `make test` および `make static_analysis` が 100% PASS すること。
