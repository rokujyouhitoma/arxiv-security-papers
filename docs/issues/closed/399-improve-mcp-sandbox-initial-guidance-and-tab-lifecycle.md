---
ID: 399
種別: Bug
優先度: Medium
ステータス: Closed (Completed)
---

# [BUG/SEC] MCP JSON-RPC サンドボックスの初期ガイダンス改善およびタブ遷移ライフサイクルの整備 (ID: 399)

## 1. 概要 / Summary

Web コンソールの「🔌 Model Context Protocol (MCP) JSON-RPC サンドボックス」（`#/mcp`）画面において、JSON-RPC レスポンス表示領域（`<pre id="mcpOutput">`）に常時 `{ "status": "idle" }` と表示されたままとなり、処理が停止しているのか、あるいはツールが利用不可となっているのかが判別しにくいユーザビリティ上の課題・不具合が発生していた。

さらに、他のタブ（Search, Trends, Spider, Supervisor）で実装されている `SceneDirector` によるタブ遷移ライフサイクル（`enter` / `exit`）が `mcpTab` では `createTabScene(null, null)` と登録されており、タブ表示時の初期化処理（ステータス同期、初期ガイダンスの表示、実行状態に応じたバッジ更新）が一切整備されていなかった。

### 再現手順 / Steps to Reproduce

1. Web コンソール（`http://localhost:8000/`）を開く。
2. 左側サイドバーから「🔌 MCP ツールサンドボックス」（`#/mcp`）を選択する。
3. 画面下部の「JSON-RPC レスポンス:」領域に `{ "status": "idle" }` と静的に表示されたままとなる。
4. 他のタブのように自動的な初期化やガイダンス更新が行われず、実行待機中なのか停止しているのかが判別しづらい。
5. ツール実行中やパースエラー発生時にも視覚的な状態ステータスバッジが存在せず、プレーンテキストの切り替えのみに留まっていた。

### 再現環境 / Environment

- OS / Env: Browser / Web Gateway UI
- Target Files:
  - [site/index.html](../../../site/index.html) (Line 276-312)
  - [site/app.js](../../../site/app.js) (Line 167-171, Line 337, Line 1084-1140)
  - [site/app-min.js](../../../site/app-min.js)
  - [tests/web/test_web_server.py](../../../tests/web/test_web_server.py)
  - [tests/web/test_frontend_frameworks.py](../../../tests/web/test_frontend_frameworks.py)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [site/index.html](../../../site/index.html) - `#mcpOutput` の初期表示ガイダンス改善および `#mcpStatusBadge` ステータス表示要素の追加
- [x] [site/app.js](../../../site/app.js) - `mcpTab` の `SceneDirector` ライフサイクル（`onEnter`）登録、状態管理（`ready`, `running`, `success`, `error`）、バッジ更新ロジックの実装
- [x] [site/app-min.js](../../../site/app-min.js) - Closure Compiler (`scripts/compile_frontend.py`) によるバンドル成果物の再生成
- [x] [tests/web/test_web_server.py](../../../tests/web/test_web_server.py) - `#mcpOutput` の初期 JSON 構文およびガイダンス内容の妥当性テスト追加
- [x] [tests/web/test_frontend_frameworks.py](../../../tests/web/test_frontend_frameworks.py) - `mcpTab` の `SceneDirector` ライフサイクル登録および `onEnter` 実行に関する Node.js / 静的テストの強化
- [x] [docs/issues/README.md](../README.md) - Issue 台帳のステータス管理（`Closed (Completed)`）

---

## 3. ガバナンス・専門エージェント多角的レビュー / Multi-Perspective Review

### Project Manager (PM)
- **優先度判断**: Medium。Issue 398（セマンティック RAG 検索復旧）および Issue 400（`SceneCtor` 未定義エラー解消）の完了に伴い、残存するフロントエンドサンドボックスのユーザビリティおよびライフサイクル不整合を速やかに解消し、リリース品質へと引き上げた。
- **方針**: 静的 HTML と動的 JS 双方で一貫性を持たせ、初回アクセス時およびタブ再訪問時の挙動を明確化。

### UI/UX & Documentation Designer
- **視覚的ガイダンスの明確化**: 単なる `{ "status": "idle" }` はシステムフリーズと誤認されやすい。有効な JSON 形式（`{ "status": "ready", "message": "...", "hint": "..." }`）を維持しつつ、ユーザーが次に取るべきアクション（ツール選択、引数確認、実行ボタンクリック）を明示。
- **ステータスバッジの導入**: レスポンス見出し横に現在のサンドボックス状態（`🟢 待機中 (Ready)`, `⚡ 実行中 (Running)`, `✅ 完了 (Success)`, `❌ 引数エラー / 実行失敗 (Error)`）を示すインジケーターバッジを配置し、視認性を飛躍的に向上。

### Information Security Specialist
- **DOM XSS 防止**: JSON-RPC レスポンスおよびエラーメッセージを DOM に出力する際は、常に `element.textContent` を利用し、悪意あるレスポンスや入力によるスクリプト注入（Cross-Site Scripting）を確実に防止。
- **入力サニタイズと検証**: `mcpArgsInput` の JSON パースエラー時に詳細を安全にエスケープして表示し、不正なオブジェクト構造がバックエンドに送信される前にクライアント側で確実にガード。

### Application Specialist (APS)
- **JSON-RPC 2.0 / レガシー API 互換性の維持**: Web Gateway の `/api/mcp` は `{"name": "...", "arguments": {...}}`（レガシー形式）と JSON-RPC 2.0 形式の双方を処理可能。サンドボックス UI は引数構造を各ツール選択時に自動補完し、初心者でも直ちにテスト実行できる UX を提供。

### Systems Architect
- **アーキテクチャ一貫性**: `SceneDirector` / `TabScene` のアーキテクチャ規約に厳格に従い、各タブは独立したライフサイクルフック（`enter`, `exit`）を持つこと。`mcpTab` だけが `createTabScene(null, null)` のまま放置されていたアーキテクチャ的負債を完全に解消。

### Software Development (SWD)
- **Closure Compiler 厳格型適合**: `site/app.js` への変更は Google Closure Compiler（`scripts/compile_frontend.py`）の型検査（`--jscomp_error=checkTypes`）を 100% 通過し、JSDoc 型アノテーションを完全整備。
- **状態保持**: タブを一度離れて再度戻った際、既に実行済みの結果がある場合はそれを破棄せず保持し、未実行の場合のみ準備完了ガイダンスを維持。

### Software Quality Assurance Specialist (QA)
- **回帰テスト保証**: `tests/web/test_web_server.py` の `test_index_html_mcp_sandbox_default_json_validity` および `test_index_html_mcp_output_and_badge_guidance` を拡充し、`site/index.html` の初期 JSON がパース可能かつ期待通りのキーを持つことを機械的に検証。

---

## 4. 脅威分析とセキュリティ要件 (Threat Model & Security Requirements)

1. **脅威アクター**:
   - 悪意あるユーザーまたは細工された URL/引数によるクライアント側スクリプト実行（Client-side Script Injection）。
2. **脅威シナリオ**:
   - MCP ツールの実行結果に HTML タグやスクリプトタグが含まれる場合、それを `innerHTML` で直接画面描画すると DOM-based XSS が成立する。
3. **セキュリティ要件**:
   - レスポンス出力・エラー出力は一切 `innerHTML` を使わず、必ず `element.textContent` に代入すること。
   - `JSON.parse` の例外処理を行い、不正な入力がバックエンドへ無制御に流れることを阻止すること。

---

## 5. 根本原因分析 (RCA) / Root Cause Analysis

1. **静的プレースホルダーのミスリーディング**:
   - `site/index.html` (Line 309) に `<pre id="mcpOutput" class="code-block">{ "status": "idle" }</pre>` が静的に記述されていた。
   - `"idle"` という単語のみでは、ツールが利用不可・停止中・実行完了後のいずれであるかが伝わらなかった。
2. **SceneDirector ライフサイクルの不在**:
   - `site/app.js` (Line 337) で `appSceneDirector.register('mcpTab', createTabScene(null, null));` と登録されていた。
   - `searchTab`（検索窓フォーカス）、`trendsTab`（初期データ取得）、`spiderTab`（ポーリング開始/停止）、`supervisorTab`（テレメトリ同期）とは異なり、`mcpTab` には `onEnter` / `onExit` フックが一切設定されていなかった。
3. **状態管理と視覚フィードバックの欠如**:
   - サンドボックスが「未実行（待機中）」「実行中」「実行完了」「エラー」のどの状態にあるかを示すステータスバッジがなく、`<pre>` タグ内のテキストのみに依存していた。

---

## 6. 暫定対処と恒久対策 / Workaround & Permanent Fix

* **暫定対処 (Workaround)**:
  「⚡ MCP ツール呼び出し実行」ボタンをクリックし、手動でツールを実行してレスポンスを更新する。
* **恒久対策 (Permanent Fix)**:
  1. **UI プレースホルダーの刷新 (`site/index.html`)**:
     - `#mcpOutput` の初期コンテンツを、JSON-RPC の実行待機状態と操作方法が一目で把握できる構造化 JSON ガイダンス（`status: "ready"`）に改修。
     - レスポンス見出し横に `#mcpStatusBadge`（`🟢 待機中 (Ready)`）を追加。
  2. **タブライフサイクルの整備 (`site/app.js`)**:
     - `appSceneDirector.register('mcpTab', createTabScene(onEnter, onExit))` にて、タブ遷移時に実行状態に応じたガイダンス同期・バッジ更新を行うハンドラを実装。
     - 実行中、成功時、エラー時の各状態で `#mcpStatusBadge` と `#mcpOutput` を整合性高く更新。
  3. **自動テストの追加とバンドル更新**:
     - `tests/web/test_web_server.py` および `tests/web/test_frontend_frameworks.py` にテストケースを追加。
     - `make build_js` で `site/app-min.js` を再生成。

---

## 7. 実装方針 / Implementation Plan

Target Branch: `fix/399-mcp-sandbox-guidance-and-lifecycle`

### ステップ 1: UI テンプレート改修 (`site/index.html`)
- `#mcpOutput` の初期コンテンツを以下のように更新（有効な JSON 形式を維持）:
  ```html
  <div class="mcp-output-wrapper" style="margin-top: 20px;">
    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
      <h3 style="font-size: 13px; font-weight: 700; margin: 0;">JSON-RPC レスポンス:</h3>
      <span id="mcpStatusBadge" class="card-tag" style="background: rgba(56, 189, 248, 0.2); color: #0284c7; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: bold;">🟢 待機中 (Ready)</span>
    </div>
    <pre id="mcpOutput" class="code-block">{
    "status": "ready",
    "message": "MCP JSON-RPC サンドボックスは利用可能です。",
    "hint": "上記のツール名と引数(JSON)を確認し、「⚡ MCP ツール呼び出し実行」をクリックしてください。"
  }</pre>
  </div>
  ```

### ステップ 2: タブライフサイクルと状態管理の実装 (`site/app.js`)
- `mcpTab` ライフサイクル管理関数 `initMcpSandboxTab()` を定義:
  ```javascript
  let mcpSandboxExecuted = false;

  /**
   * @param {string} status
   * @param {string} label
   */
  function updateMcpStatusBadge(status, label) {
    if (!mcpStatusBadge) return;
    mcpStatusBadge.textContent = label;
    if (status === 'ready') {
      mcpStatusBadge.style.background = 'rgba(56, 189, 248, 0.2)';
      mcpStatusBadge.style.color = '#0284c7';
    } else if (status === 'running') {
      mcpStatusBadge.style.background = 'rgba(234, 179, 8, 0.2)';
      mcpStatusBadge.style.color = '#b45309';
    } else if (status === 'success') {
      mcpStatusBadge.style.background = 'rgba(34, 197, 94, 0.2)';
      mcpStatusBadge.style.color = '#15803d';
    } else if (status === 'error') {
      mcpStatusBadge.style.background = 'rgba(239, 68, 68, 0.2)';
      mcpStatusBadge.style.color = '#b91c1c';
    }
  }

  function syncMcpSandboxState() {
    if (!mcpSandboxExecuted) {
      updateMcpStatusBadge('ready', '🟢 待機中 (Ready)');
    }
  }
  ```
- `appSceneDirector.register('mcpTab', ...)` を改修:
  ```javascript
  appSceneDirector.register('mcpTab', createTabScene(() => {
    DOMUtils.afterReflow(() => {
      syncMcpSandboxState();
    });
  }, null));
  ```
- `runMcpBtn` クリックイベント処理で状態遷移（running → success / error）と `updateMcpStatusBadge` を連動。

### ステップ 3: フロントエンドバンドル再生成 (`site/app-min.js`)
- `python3 scripts/compile_frontend.py`（または `make build_js`）を実行し、厳格型検査をパスして `site/app-min.js` を生成。

### ステップ 4: テスト拡充
- `tests/web/test_web_server.py`:
  - `test_index_html_mcp_sandbox_default_json_validity` にて、`mcpOutput` の初期 JSON がパース可能であり、`status == "ready"` を含むことを検証。
  - `#mcpStatusBadge` 要素が `site/index.html` に存在することを検証。
- `tests/web/test_frontend_frameworks.py`:
  - `mcpTab` が `createTabScene(null, null)` ではなく有効な `onEnter` フックを持って登録されていることを静的/動的に検証。

### ステップ 5: 品質ゲート検証
- `make check_format`
- `make static_analysis`
- `pytest tests/web/test_web_server.py tests/web/test_frontend_frameworks.py`
- 全体テスト `make test`

---

## 8. 完了条件 / Success Criteria (DoD)

- [x] **初期表示ガイダンス**: Web コンソールで「🔌 MCP ツールサンドボックス」（`#/mcp`）を開いた際、`#mcpOutput` に有効な JSON 形式で `status: "ready"` と明確な日本語操作案内が表示されること。
- [x] **ステータスバッジの導入**: `#mcpStatusBadge` が新設され、待機中（Ready）、実行中（Running）、成功（Success）、エラー（Error）の各状態が色分けされて明瞭に可視化されること。
- [x] **SceneDirector ライフサイクル統合**: `mcpTab` が `appSceneDirector` のライフサイクル（`enter`）に統合され、タブ遷移時にエラーなく状態同期が実行されること。
- [x] **XSS 防止と入力安全性**: 出力レンダリングに `textContent` が使用され、JSON パースエラーや不正入力時も画面が破綻せず安全なエラーバッジと案内が表示されること。
- [x] **バンドル同期**: `site/app-min.js` が Closure Compiler でエラーなくビルドされ、差分が最新コードと同期されていること。
- [x] **自動テスト 100% PASS**: `tests/web/test_web_server.py` および `tests/web/test_frontend_frameworks.py` の追加テストを含め、`make test` および `make static_analysis` が完全通過すること。
- [x] **Issue 台帳同期**: [docs/issues/README.md](../README.md) のステータスが `Closed (Completed)` に更新されていること。
