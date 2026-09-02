---
ID: 120
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/SEC] MCP ツールサンドボックスの初期引数 JSON 構文エラー修正 (ID: 120)

## 1. 概要 / Summary
Web ダッシュボード (`site/index.html`) の「MCP ツールサンドボックス」において、「引数 (JSON 形式):」の `<textarea id="mcpArgsInput">` 内にエスケープされた改行文字 `\n` がそのまま静的テキストとして埋め込まれていたため、初期状態で「⚡ MCP ツール呼び出し実行」を実行すると `JSON.parse` が失敗し、`エラー: Expected property name or '}' in JSON at position 1 (line 1 column 2)` が発生していた不具合を解消した。

### 再現手順 / Steps to Reproduce
1. Web サーバーを起動し、ブラウザで `http://localhost:8000` (または `site/index.html`) を開く。
2. 「⚡ MCP ツールサンドボックス」セクションまでスクロールする。
3. デフォルトで入力されている引数をそのままにして「⚡ MCP ツール呼び出し実行」ボタンをクリックする。
4. JSON-RPC レスポンス領域に `エラー: Expected property name or '}' in JSON at position 1 (line 1 column 2)` が表示され、MCP ツール呼び出しが失敗する。

### 再現環境 / Environment
- OS / Env: Linux / Web Browser
- File: [site/index.html](../../site/index.html), [site/app.js](../../site/app.js)

---

## 2. トレーサビリティ / Traceability
- [site/index.html](../../site/index.html): MCP Tool Sandbox UI
- [site/app.js](../../site/app.js): MCP Tool Invocation & Argument Parsing
- [tests/web/test_dashboard_html.py](../../tests/web/test_dashboard_html.py): HTML & UI Component Integrity Tests

---

## 3. 脅威分析・制約事項 / Threat Analysis & Operational Constraints
1. **クライアント側 JSON パース例外ハンドリング**:
   - *脅威*: ユーザーが不正な JSON を入力した場合に unhandled exception で UI がフリーズまたは不透明なエラーになる。
   - *緩和策*: `site/app.js` の `runMcpBtn` リスナー内で `JSON.parse` エラーを明示的にキャッチし、親切なエラーメッセージを表示。
2. **静的 HTML / JavaScript の完全 Pure 構成維持**:
   - *制約*: 外部 CDN やサードパーティ製ライブラリを一切導入せず、Pure HTML/JS のみで完結させる。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [site/index.html](../../site/index.html)
- [x] [site/app.js](../../site/app.js)
- [x] [tests/web/test_web_server.py](../../tests/web/test_web_server.py)

---

## 5. 根本原因分析 (RCA) / Root Cause Analysis
`site/index.html` の line 130 付近において、textarea の初期値が `<textarea id="mcpArgsInput" rows="4">{\n  "query": "ペンテスト自動化",\n  "top_k": 5\n}</textarea>` と定義されていた。HTML の `<textarea>` タグ内では `\n` はバックスラッシュと文字 'n' の 2 文字としてそのまま DOM の `.value` に渡される。そのためブラウザ側で `JSON.parse()` を実行すると `{` の直後に不正なエスケープ文字 `\` が存在すると解釈され、構文エラーが発生していた。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `fix/120-fix-mcp-sandbox-default-arguments-json-syntax-error`

1. **`site/index.html` の修正**:
   - `<textarea id="mcpArgsInput">` 内のエスケープ文字 `\n` を実際の複数行改行に修正し、静的 HTML から取得される初期値が Valid な JSON 文字列になるようにした。
2. **`site/app.js` の堅牢化**:
   - `runMcpBtn` クリックハンドラにおいて、`JSON.parse` 失敗時に `引数 (JSON) パースエラー: ${err.message}` とわかりやすく出力するようにエラーハンドリングを強化。
3. **自動テストの追加**:
   - `tests/web/test_web_server.py` に、`site/index.html` の `#mcpArgsInput` 初期値が `json.loads` で正常にパースできることを検証する `test_index_html_mcp_sandbox_default_json_validity` を追加。
4. **品質ゲート検証**:
   - `make format`, `make static_analysis`, `pytest` を実行し、100% パスを確認。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `site/index.html` の `#mcpArgsInput` の初期値が `json.loads()` で正常にパースできること
- [x] `site/index.html` をブラウザで開き初期値のまま「⚡ MCP ツール呼び出し実行」を押下した際にエラーなく JSON-RPC リクエストが送信・処理されること
- [x] 不正な JSON 入力時にも親切なエラーメッセージが画面に表示されること
- [x] 全品質ゲート（`make format`, `make static_analysis`, `make test`）が 100% PASS すること
