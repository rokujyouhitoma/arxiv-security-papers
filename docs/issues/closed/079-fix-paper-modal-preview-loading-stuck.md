---
ID: 079
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG] 論文モーダルプレビューが「読み込み中... OKF ドキュメントを取得中...」のまま停止する不具合の修正 (ID: 079)

## 1. 概要 / Summary
Web 検索 UI（`http://localhost:8000/`）において、検索結果（例: `arXiv: 2502.16730`）の「👁️ プレビュー ↗」またはカード詳細をクリックした際、モーダルダイアログが「読み込み中... OKF ドキュメントを取得中...」のまま永久に停止し、Markdown 本文および関連トポロジーが表示されない事象が発生している。

### 再現手順 / Steps to Reproduce
1. `make run_web` または `make run_dashboard` を起動し、`http://localhost:8000/` にアクセスする。
2. 検索バーに `RapidPen` や `2502.16730` を入力して検索する。
3. 検索結果カードの「👁️ プレビュー ↗」またはタイトルをクリックしてモーダルを開く。
4. モーダル本文が「読み込み中... OKF ドキュメントを取得中...」のまま止まる。

### 再現環境 / Environment
- OS / Env: Linux / PEP 3333 WSGI Web Gateway
- Client: Vanilla JS (`site/app.js`, `site/index.html`)
- Server: `src/web/gateway/handlers.py`, `src/web/presentation/`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [site/app.js](site/app.js)
- [x] [src/web/gateway/handlers.py](src/web/gateway/handlers.py)
- [x] [tests/web/gateway/test_gateway.py](tests/web/gateway/test_gateway.py)
- [x] [tests/web/test_web_server.py](tests/web/test_web_server.py)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **API レスポンススキーマの不整合**:
   - `site/app.js` の `openPaperModal` 関数は、`/api/paper/<arxivId>` のレスポンスとして `data.content`（OKF Markdown 全文文字列）および `data.path` を期待している（`if (data.status === 'success' && data.content)`）。
   - しかし、`src/web/gateway/handlers.py` の `handle_paper` は `{"status": "success", "paper": paper}` を返しており、トップレベルに `content` を含めていないか、または `paper` ディクショナリ内に OKF Markdown 本文ファイル（`outputs/okf_papers/YYYY-MM-DD/<clean_id>.md`）の実コンテンツが含まれていない。
2. **OKF Markdown 本文のオンデマンド読み込み欠落**:
   - `handle_paper` 内でメタデータ（`_get_paper`）を取得した際、ディスク上の実ファイル（`paper.get("path")`）が存在する場合にその全文 `content` を読み込んでレスポンスに含める処理が欠落していた。
3. **フロントエンド側のフォールバック不足**:
   - `site/app.js` 側で `data.content` がなく `data.paper` のみの場合や、`/preview/<clean_id>` HTML エンドポイントへのフォールバック、エラー時の適切な通知が不足していた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: なし
* **恒久対策 (Permanent Fix)**:
  1. `src/web/gateway/handlers.py` の `handle_paper` を改修し、`_get_paper(clean_id)` から得られた `path` をもとに `outputs/okf_papers/` から OKF Markdown ファイル実体を安全に読み出し、`{"status": "success", "content": content, "path": rel_path, "paper": paper}` を返却する。
  2. `site/app.js` の `openPaperModal` を改修し、`data.content` または `data.paper` の双方に対応し、タイトル・要約・関連トポロジーを確実にレンダリングする。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/079-fix-paper-modal-preview-loading-stuck`

1. **`src/web/gateway/handlers.py` の改修**:
   - `handle_paper` において、`paper` オブジェクトから `path`（または `clean_id` による OKF ファイルパス解決）を特定。
   - ディスクから UTF-8 で OKF Markdown 本文を読み込み、トップレベル `content` キーとして JSON レスポンスに付与。
2. **`site/app.js` の改修**:
   - `data.content` または `data.paper.content` / `data.paper.summary` を安全にパース。
   - `window.MarkdownCompiler.compile(content)` を実行して即座に HTML 展開。
3. **単体テストの追加**:
   - `/api/paper/<clean_id>` が `content` と `path` を含んで 200 OK を返すことをテスト。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `/api/paper/2502.16730` が `content` を含む JSON を正常返却すること
- [x] `http://localhost:8000/` でカードまたはプレビューをクリックした際に即座にモーダル本文と Mermaid 図が表示されること
- [x] `make check`（フォーマット、静的解析、全単体テスト）が 100% PASS すること
- [x] Issue 台帳（`docs/issues/README.md`）が更新されること
