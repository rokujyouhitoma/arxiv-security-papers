---
ID: 003
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] MCP サーバおよび VectorDB をバックエンドとしたモダン Web 検索 UI の構築 (ID: 003)

## 1. 概要 / Summary
`arxiv-security-papers` の 14,000 件以上の全論文ナレッジ、ハイブリッド VectorDB 検索エンジン、および MCP サーバをブラウザ上で可視化・体験可能にするリッチ Glassmorphic Web UI および API サーバーを構築します。

---

## 2. トレーサビリティ / Traceability
- **UI/UX 設計方針**: Web Application Development Standards (Dark mode, Glassmorphism, Micro-animations)
- **仕様書**: `docs/mcp/MCP-01-mcp_server_specification.md`, `docs/requirements/REQ-01-system_requirements.md`
- **設計書**: `docs/designs/DSN-01-high_level_design.md`, `docs/designs/DSN-02-low_level_design.md`

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [`src/web_server.py`](../../src/web_server.py): 静的ファイル配信 ＆ JSON/MCP API サーバー
- [x] [`site/index.html`](../../site/index.html): HTML5 セマンティックWebアプリケーション画面
- [x] [`site/style.css`](../../site/style.css): Glassmorphism ダークモードスタイルシステム
- [x] [`site/app.js`](../../site/app.js): フロントエンド検索・モーダル・Mermaid・MCP サンドボックスロジック
- [x] [`tests/test_web_server.py`](../../tests/test_web_server.py): Web API サーバー単体テスト
- [x] [`Makefile`](../../Makefile): `run_web` ターゲット追加

---

## 4. 実装方針 / Implementation Plan (UI/UX / SA / ST / PM 指導)
Target Branch: `feat/003-implement-web-search-ui-and-mcp-backend`

1. **`src/web_server.py` の開発**:
   - `http.server.HTTPServer` と `SimpleHTTPRequestHandler` を拡張し、`site/` ディレクトリのファイル配信および `/api/search`, `/api/paper/<id>`, `/api/trends`, `/api/mcp` API ハンドラを実装。
2. **`site/` Web UI アプリケーション構築**:
   - ダークモード＋グラスモフィズム（`backdrop-filter: blur`）による洗練されたカードデザイン。
   - 論文検索タブ、トレンド＆Mermaid図タブ、MCP ツールデバッグタブの 3 大ナビゲーション構成。
3. **単体テストと動作検証**:
   - `tests/test_web_server.py` を作成し、`make py_compile` および `make test` を実行。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `src/web_server.py` が構文エラー 0 件で正常動作すること。
- [x] `site/` 配下の静的 Web ファイル群が正常配信されること。
- [x] Web 上からリアルタイム検索、OKF プレビュー、Mermaid レンダリング、MCP ツール実行が可能なこと。
- [x] `make py_compile` および `make test` が 100% PASS すること。
