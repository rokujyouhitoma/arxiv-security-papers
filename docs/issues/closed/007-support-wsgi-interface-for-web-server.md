---
ID: 007
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
完了日: 2026-08-16
---

# [FEAT/ENH] Web サーバーの PEP 3333 WSGI インターフェース対応 (ID: 007)

## 1. 概要 / Summary

現在の Web 検索サーバー (`src/web_server.py`) は、標準ライブラリの `http.server.HTTPServer` および `SimpleHTTPRequestHandler` を継承して構築されていました。
本 Issue では、Python 標準の Web サーバー共通規格である **PEP 3333 (WSGI: Web Server Gateway Interface v1.0.1)** に完全準拠した WSGI アプリケーション callable (`application(environ, start_response)`) を設計・実装しました。

これにより、Gunicorn, uWSGI, `wsgiref`, AWS Lambda (Mangum/WSGI adapter), Google Cloud Run 等の本番 WSGI アプリケーションサーバーやマルチワーカーコンテナ環境への容易なデプロイ・水平スケールが可能になりました。
また、開発・スタンドアロン実行用として `wsgiref.simple_server` によるローカル起動 (`make run_web`) もシームレスにサポートしています。

---

## 2. トレーサビリティ / Traceability

- **要求仕様書**: [[REQ-02] 主要機能一覧 (F-06 Web 検索ポータル)](../requirements/REQ-02-feature_list.md)
- **要求事項定義**: [[REQ-01] システム要求事項定義書 (NFR-01, NFR-02)](../requirements/REQ-01-system_requirements.md)
- **基本設計書**: [[DSN-01] 基本設計書 (4.2 ポータル ＆ UI)](../designs/DSN-01-high_level_design.md)
- **詳細設計書**: [[DSN-07] Web ポータル ＆ Markdown Compiler 設計書](../designs/DSN-07-web_portal_and_markdown_compiler.md)
- **モジュール仕様**: [[DSN-02] 詳細設計書 (4.2 src/web_server.py)](../designs/DSN-02-low_level_design.md)
- **標準仕様**: PEP 3333 (Python Web Server Gateway Interface v1.0.1)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/web_server.py](../../src/web_server.py)
  - PEP 3333 準拠の `application(environ, start_response)` エントリポイント実装
  - `WSGIApplication` クラスによる REST API ルーティング (`/api/search`, `/api/paper/`, `/api/trends`, `/api/stats`, `/api/mcp`)
  - `site/` 配下の静的アセット配信（MIME タイプ自動解決、CORS ヘッダー付与、SPA フォールバック）
  - パストラバーサル脆弱性防御ガード (`is_safe_workspace_path` / `os.path.commonpath`) 統合
  - `wsgiref.simple_server` によるスタンドアロン起動関数 (`run_web_server`)
  - `app = application` のグローバルエクスポート (Gunicorn / uWSGI 連携用)
- [x] [src/mcp_server.py](../../src/mcp_server.py)
  - `--http` オプションによる HTTP/WSGI サーバー起動サポート
- [x] [tests/test_web_server.py](../../tests/test_web_server.py)
  - WSGI `environ` / `start_response` モックを用いた各エンドポイントの包括的テスト (12 テスト)
  - GET/POST/OPTIONS リクエストのステータスコード・ヘッダー・レスポンスボディ検証
  - パストラバーサル (`../`) 攻撃の防御テスト
  - 不正 JSON POST リクエストのエラーハンドリング検証
- [x] [Makefile](../../Makefile)
  - `make run_web` 実行時の WSGI サーバー起動確認
- [x] [docs/designs/DSN-07-web_portal_and_markdown_compiler.md](../designs/DSN-07-web_portal_and_markdown_compiler.md)
  - WSGI アーキテクチャ構成図および Gunicorn 連携例の追記
- [x] [docs/issues/README.md](README.md)
  - Issue 007 のステータス更新 (`Closed`)

---

## 4. 脅威モデル ＆ セキュリティ検証 (Threat Model & Security Mitigations)

| 脅威項目 (Threat) | 攻撃ベクター | 緩和策・セキュリティ制御 (Mitigations) |
| :--- | :--- | :--- |
| **パストラバーサル (CWE-22)** | `GET /../../etc/passwd` や URL エンコードされた相対パスによるシステムファイル漏洩 | `os.path.abspath` と `os.path.commonpath` による `SITE_DIR` 境界チェックを実施。境界外アクセスは `403 Forbidden` または `404 Not Found` を返却。 |
| **巨大ペイロード DoS (CWE-400)** | 不正に大きな `Content-Length` を送信しメモリ枯渇を引き起こす | `CONTENT_LENGTH` の上限チェック (1MB制限) を設け、超過時は `413 Payload Too Large` を返却。 |
| **CORS 不正アクセス (CWE-942)** | 外部オリジンからの CSRF / 不正 API 実行 | OPTIONS プリフライト対応および適切な CORS ヘッダー (`Access-Control-Allow-Origin: *`, `Access-Control-Allow-Headers: Content-Type`) を付与。 |
| **不正 JSON ペイロード例外 (CWE-754)** | 不正構文 JSON による 500 サーバークラッシュ | `json.loads` 例外捕捉と `400 Bad Request` 構造化エラーレスポンスの返却。 |

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/007-support-wsgi-interface`

```mermaid
graph TD
    Client[Web Browser / MCP Client / Gunicorn] -->|HTTP Request| WSGIServer[WSGI Server: wsgiref / Gunicorn / uWSGI]
    WSGIServer -->|environ, start_response| App[application: WSGI Handler]
    
    subgraph Routing & Security Guard
        App --> SecurityCheck{Safe Path Check?}
        SecurityCheck -->|Unsafe Path| Res403[403 Forbidden / 404]
        SecurityCheck -->|Safe Path| Dispatcher{Route Dispatcher}
    end

    Dispatcher -->|GET /api/search| SearchHandler[VECTOR_ENGINE.search_with_profile]
    Dispatcher -->|GET /api/paper/*| PaperHandler[mcp_server.handle_get_paper_summary]
    Dispatcher -->|GET /api/trends| TrendsHandler[mcp_server.handle_get_latest_trends]
    Dispatcher -->|GET /api/stats| StatsHandler[System Stats JSON]
    Dispatcher -->|POST /api/mcp| MCPHandler[mcp_server.dispatch_tool]
    Dispatcher -->|OPTIONS *| CORSHandler[200 OK + CORS Headers]
    Dispatcher -->|GET /* Static| StaticHandler[Static File Streaming from site/]

    SearchHandler --> JSONResponse[JSON Response + CORS]
    PaperHandler --> JSONResponse
    TrendsHandler --> JSONResponse
    StatsHandler --> JSONResponse
    MCPHandler --> JSONResponse
    CORSHandler --> EndResponse[start_response -> Iterator[bytes]]
    JSONResponse --> EndResponse
    StaticHandler --> EndResponse
```

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `src/web_server.py` に PEP 3333 準拠の `application(environ, start_response)` および `app = application` がエクスポートされていること。
- [x] Gunicorn や `wsgiref.simple_server.make_server` から直接起動・サーブ可能であること。
- [x] 静的ファイル配信および全 REST API (`/api/search`, `/api/paper/`, `/api/trends`, `/api/stats`, `/api/mcp`) が正常に動作すること。
- [x] パストラバーサル (`../`) や不正 JSON に対する堅牢なエラーハンドリングが実装されていること。
- [x] `tests/test_web_server.py` に WSGI 単体テストが追加され、全テストが 100% PASS すること。
- [x] `make verify_quality` (format, static_analysis, test, build_js) がエラー・警告 0 件で通過すること。
- [x] `docs/designs/DSN-07-web_portal_and_markdown_compiler.md` に WSGI 仕様が文書化されていること。
