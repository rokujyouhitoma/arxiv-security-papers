---
ID: 034
種別: Feature / Architecture
優先度: Low
ステータス: Closed (Completed)
---

# [FEAT/ENH] Web サーバーの API Gateway 化と UI プレゼンテーション層の完全分離（`src/gateway/` / `src/presentation/`） (ID: 034)

## 1. 概要 / Summary

現在 `src/web/web_server.py` は、PEP 3333 準拠の WSGI アプリケーションとして、HTTP ルーティング、REST API、JSON-RPC プロキシ、静的ファイル配信、および動的 HTML プレビュー / Markdown コンパイルを包括して処理しています。

本 Issue では、ネットワーク・プロトコル制御層（**`src/gateway/`**）と、UI テンプレート生成・動的プレゼンテーション層（**`src/presentation/`**）を完全分離し、ヘッドレスな API サーバー構成および UI コンポーネントのテスト容易性を向上させます。

```
src/
├── gateway/          # PEP 3333 WSGI ルーター, JSON-RPC / REST ハンドラ, CORS, ミドルウェア
└── presentation/     # 動的 HTML プレビュー, Markdown Compiler, SVG/Mermaid レンダラー, Web Components
```

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [DSN-04-markdown-compiler-engine.md](../designs/DSN-04-markdown-compiler-engine.md)
  - [DSN-07-wsgi-web-server.md](../designs/DSN-07-wsgi-web-server.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] `src/gateway/` (WSGI エントリポイント、URL ルーター、ミドルウェア、API ハンドラ)
- [ ] `src/presentation/` (HTML テンプレートエンジン、Markdown レンダラー、UI アセット管理)
- [ ] [src/web/web_server.py](../../src/web/web_server.py) (ファサード化 / 移行)
- [ ] `tests/gateway/`, `tests/presentation/` (単体テストの分離)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/034-split-gateway-and-presentation`

1. **`src/gateway/` の構築**:
   - HTTP リクエスト/レスポンス処理、ルーティングテーブル、エラーハンドリングミドルウェアを独立化。
2. **`src/presentation/` の構築**:
   - HTML プレビュー生成、Markdown Compiler 連携、バッジ・タグ・Mermaid レンダリングを UI プレゼンテーション層として純化。HTTP サーバーなしで HTML レンダリングの単体テストを可能にする。
3. **後方互換エントリポイント**:
   - `python src/web_server.py` および `from web.web_server import application` の動作を維持。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `src/gateway/` と `src/presentation/` への責務分離が完了していること
- [ ] UI レンダラーが HTTP リクエスト/ソケットなしで高速に単体テストできること
- [ ] 既存の Web 検索 UI、プレビュー画面、REST/JSON-RPC API の全機能が正常稼働すること
- [ ] `make test`, `make static_analysis` がエラー 0 件で通過すること
