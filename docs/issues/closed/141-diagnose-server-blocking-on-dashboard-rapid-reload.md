---
ID: 141
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/SEC] /dashboard 連打リロード時におけるサーバーブロッキング・ハングアップのログ計測・原因特定および耐障害性強化 (ID: 141)

## 1. 概要 / Summary
`http://localhost:8000/dashboard`（または `/dashboard.html`）をブラウザで連続してリロード（F5連打 / Cmd+R連打）すると、ブラウザがローディング中（クルクル回転）のまま応答しなくなり、ページコンテンツや関連 API が読み込まれなくなる。

調査の結果、以下の二重のブロッキング要因が特定された：
1. **WSGI サーバーの単一スレッド同期性**:
   `src/web/gateway/app.py` の `run_web_server` はデフォルトの `wsgiref.simple_server.make_server`（シングルスレッド `WSGIServer`）を使用している。
2. **Server-Sent Events (SSE) による単一スレッドの長期専有**:
   `dashboard.html` はロード時に `new EventSource('/api/stream/top?interval=1.0')` を開き、サーバー側の `stream_top_metrics` ジェネレータが最大 3600 秒間ループし続ける。
   シングルスレッド環境下では、この SSE 接続が 1 本張られた時点で後続のすべてのリクエスト（リロード時の `/dashboard` GET リクエスト含む）がキューに積まれたままブロックされる。
3. **クライアント側のアンロード時クローズ漏れ**:
   `dashboard.html` に `beforeunload` / `pagehide` ハンドラーがなく、リロード時に古い SSE コネクションが明示的に破棄されないため、サーバー側で切断検知が遅延する。
4. **リクエスト開始・進行ログの欠如**:
   ログがリクエスト完了時のみ出力されるため、処理中のリクエストやブロッキング中のスレッドが可視化されていなかった。

本 Issue では、詳細なリクエスト受付・スレッド・ライフサイクルログを配備して原因の特定と可視化を完了し、`ThreadingWSGIServer` の導入とフロントエンドのアンロードクローズ処理を配備して、高頻度連打リロード時にも一切ハングアップしない堅牢なノンブロッキング耐障害性アーキテクチャを確立する。

### 再現手順 / Steps to Reproduce
1. `python3 src/web/server.py --port 8000` を起動。
2. ブラウザで `http://localhost:8000/dashboard` を開く。
3. ページ読み込み後、F5（Cmd+R）を 5〜10 回連続で連打リロードする。
4. ブラウザがローディング中のまま停止し、画面が表示されなくなる。

### 再現環境 / Environment
- OS / Env: Linux (Antigravity IDE 2.0 / Workspace Python 3.14.7)
- File: [src/web/gateway/app.py](../../src/web/gateway/app.py), [src/web/gateway/streaming.py](../../src/web/gateway/streaming.py), [src/web/gateway/logger.py](../../src/web/gateway/logger.py), [site/dashboard.html](../../site/dashboard.html)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/web/gateway/app.py](../../src/web/gateway/app.py)
  - `socketserver.ThreadingMixIn` を多重継承した `ThreadingWSGIServer` の定義および `run_web_server` への適用
  - `WSGIApplication.__call__` におけるリクエスト開始時ログ（`[GATEWAY-REQ-START]`）および完了時ログ（`[GATEWAY-REQ-DONE]`）のリアルタイム標準出力
  - 各ログ行へのスレッドID・スレッド名（`threading.current_thread().name`）の付与
  - PEP 3333 準拠の Hop-by-hop ヘッダーフィルタリング
- [x] [src/web/gateway/streaming.py](../../src/web/gateway/streaming.py)
  - `stream_top_metrics`、`stream_logs`、`stream_events` におけるストリーム開始時（`[SSE-OPEN]`）、Ping送信時、および切断検知時（`[SSE-CLOSE]`）の詳細ログ出力
  - クライアント切断時（`GeneratorExit`, `BrokenPipeError`, `ConnectionResetError`）の即時終了とリソース解放
- [x] [src/web/gateway/router.py](../../src/web/gateway/router.py)
  - `SSE_HEADERS` から Hop-by-hop ヘッダー `Connection: keep-alive` を除去
- [x] [site/dashboard.html](../../site/dashboard.html)
  - `beforeunload` および `pagehide` イベントによる `sseEventSource.close()` の確実な実行
- [x] [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md)
  - Section 11.6 に「Web Gateway マルチスレッド耐障害性 & SSE ライフサイクル管理」を追記
- [x] [tests/web/test_dashboard_rapid_reload.py](../../tests/web/test_dashboard_rapid_reload.py)
  - SSE ストリーミング稼働中における複数並列リクエストのノンブロッキング応答検証テスト

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

### 3.1 5つのなぜ（5 Whys）
1. **なぜブラウザが読み込まれなくなるのか？**
   $\rightarrow$ Web サーバーからの HTTP レスポンス（`/dashboard` や静的ファイル）が返らず、タイムアウトまたは待機状態になるため。
2. **なぜ Web サーバーがレスポンスを返さないのか？**
   $\rightarrow$ サーバーが既存のリクエスト処理に拘束されており、新規リクエストのソケット受付またはディスパッチがブロックされているため。
3. **なぜサーバーが拘束されているのか？**
   $\rightarrow$ `dashboard.html` が開く `/api/stream/top?interval=1.0`（SSE）のジェネレータが 3,600 秒間のループでスレッドを専有し続けているため。
4. **なぜ SSE の 1 接続で他のリクエストが止まるのか？**
   $\rightarrow$ `wsgiref.simple_server.make_server` がデフォルトで**シングルスレッド**で動作しており、並列処理機構を持たないため。
5. **なぜリロードを繰り返すと悪化するのか？**
   $\rightarrow$ `SSE_HEADERS` 内の Hop-by-hop `Connection: keep-alive` による WSGI 500 エラーでのクライアント無限再接続ストーム、およびアンロードクローズ漏れによるソケット残存が重なったため。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix

* **暫定対処 (Workaround)**:
  - リクエスト開始時（`[GATEWAY-REQ-START]`）と完了時（`[GATEWAY-REQ-DONE]`）にスレッド名付きで標準出力に即時フラッシュログを出力し、どのスレッドが何のパスを処理中であるかを完全に可視化する。
* **恒久対策 (Permanent Fix)**:
  1. **マルチスレッド WSGI サーバー (`ThreadingWSGIServer`) の導入**:
     `socketserver.ThreadingMixIn` を組み込み、リクエストごとにワーカースレッド（`daemon_threads = True`）を生成。SSE が実行中でも別スレッドで `/dashboard` がミリ秒で即座に応答する。
  2. **PEP 3333 準拠 Hop-by-Hop ヘッダー排除**:
     `router.py` および `app.py` から `Connection: keep-alive` 等を除去し、500 エラー再接続ストームを完全に防止。
  3. **SSE ストリーミングの切断即時検知とログ化**:
     ジェネレータ内で `GeneratorExit` や `BrokenPipeError` を捕捉し、`[SSE-CLOSE]` ログを出力してループを即座に `return` 終了。
  4. **フロントエンドでのアンロード切断**:
     `dashboard.html` の `beforeunload` / `pagehide` で `sseEventSource.close()` を明示的に呼び出し、リロードと同時にサーバー側へ切断通知を届ける。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/141-diagnose-server-blocking-on-dashboard-rapid-reload`

1. **マルチスレッド WSGI サーバーの実装 (`src/web/gateway/app.py`)**:
   `socketserver.ThreadingMixIn` と `wsgiref.simple_server.WSGIServer` を統合した `ThreadingWSGIServer` を配備。
2. **リアルタイム診断ログの配備 (`src/web/gateway/app.py`, `streaming.py`)**:
   リクエスト開始・完了・SSE接続/切断ログの標準出力。
3. **フロントエンドのアンロード時クローズ処理 (`site/dashboard.html`)**:
   `beforeunload` および `pagehide` イベントリスナーを追加し、`sseEventSource.close()` を実行。
4. **並列リクエスト単体テストの追加 (`tests/web/test_dashboard_rapid_reload.py`)**:
   `ThreadingWSGIServer` による並列ノンブロッキング高速応答を自動検証。
5. **品質ゲート実行**:
   `make format`, `make static_analysis`, `pytest` をパス。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `http://localhost:8000/dashboard` を連続リロード（F5連打）しても、ブロッキングやフリーズが発生せず、常に瞬時に 200 OK で表示されること。
- [x] リクエスト開始時（`[GATEWAY-REQ-START]`）および完了時（`[GATEWAY-REQ-DONE]`）にスレッド名とレイテンシを含む診断ログがリアルタイムに出力されること。
- [x] SSE ストリーミング接続の開始（`[SSE-OPEN]`）と切断（`[SSE-CLOSE]`）が明確にログ記録され、クライアント切断時にスレッドが即座に解放されること。
- [x] `site/dashboard.html` のアンロード時に `EventSource` が明示的にクローズされること。
- [x] 新規作成した並列リロード検証テスト (`tests/web/test_dashboard_rapid_reload.py`) を含む全テストスイートが 100% PASS すること。
- [x] `make static_analysis`（Xenon Grade A, Mypy `--strict` 368 source files）が 0 エラーであること。
- [x] 相対パスリンクチェックにおいて違反が 0 件であること。
