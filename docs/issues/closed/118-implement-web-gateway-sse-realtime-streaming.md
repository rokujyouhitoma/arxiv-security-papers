---
ID: 118
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] Web GatewayにおけるSSE (Server-Sent Events) リアルタイム・プッシュストリーミング API & UI ダッシュボード連携 (ID: 118)

## 1. 概要 / Summary
Web Gateway (`src/web/gateway/`) において、従来の定周期短インターバル・ポーリング方式（Pull型）に代わり、低オーバーヘッドかつ標準的な **Server-Sent Events (SSE)** エンドポイント（`/api/stream/top`, `/api/stream/logs`, `/api/stream/events`）を実装する。
これにより、UI ダッシュボード (`site/dashboard.html`) へワーカー稼働状況・RPS・PSS メモリフットプリント・最新構造化ログ・パイプラインタスク進捗をリアルタイム（Push型）で高効率にストリーミング配信し、通信トラフィックとサーバー負荷を劇的に低減させる。

### 目的 / Objectives
1. **WSGI PEP 3333 準拠 SSE ストリーミング基盤の確立**:
   - `Content-Type: text/event-stream`, `Cache-Control: no-cache`, `Connection: keep-alive`, `X-Accel-Buffering: no` ヘッダーを付与し、チャンク化されたジェネレータイテレータによるストリーミングレスポンスを生成。
   - クライアント切断 (`GeneratorExit` / Socket Broken Pipe) を安全にハンドリングし、ゴーストスレッドやファイル記述子リークを完全防止。
2. **リアルタイム監視エンドポイントの実装**:
   - `GET /api/stream/top`: Supervisor Arbiter / HeartbeatWatchdog から取得したワーカー稼働状態・RPS・メモリ使用量 (PSS/RSS) を 1 秒間隔でプッシュ配信。
   - `GET /api/stream/logs`: `outputs/logs/` の最新構造化 JSON ログレコードをリアルタイムテイル配信。
   - `GET /api/stream/events`: パイプライン実行状態、論文フェッチ・OKF 生成イベント等のシステム通知をプッシュ配信。
3. **`site/dashboard.html` における Live Stream モード統合**:
   - `EventSource` API による自動接続・切断時バックオフ再接続・Live インジケーター表示。
   - ストリーミングデータ受信による Canvas チャートおよびプロセス Top テーブルのゼロフリッカー更新。

---

## 2. トレーサビリティ / Traceability
- [src/web/gateway/streaming.py](../../src/web/gateway/streaming.py): SSE イベントフォーマッタおよびジェネレータアダプター
- [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py): SSE エンドポイントハンドラ (`handle_stream_top`, `handle_stream_logs`, `handle_stream_events`)
- [src/web/gateway/router.py](../../src/web/gateway/router.py): `/api/stream/*` ルーティング登録
- [src/web/gateway/app.py](../../src/web/gateway/app.py): WSGI ストリーミングレスポンス送出
- [site/dashboard.html](../../site/dashboard.html): UI EventSource クライアント & リアルタイム描画連携
- [tests/web/gateway/test_gateway.py](../../tests/web/gateway/test_gateway.py): SSE エンドポイントの WSGI イテレータ単体テスト
- [tests/web/test_dashboard_html.py](../../tests/web/test_dashboard_html.py): ダッシュボード HTML/JS の EventSource 連携テスト
- [tests/web/test_web_server.py](../../tests/web/test_web_server.py): Gateway 統合テスト

---

## 3. 脅威分析・制約事項 / Threat Analysis & Operational Constraints
1. **長寿命接続によるリソース枯渇・ファイル記述子枯渇 (CWE-400 / Slowloris / Resource Exhaustion)**:
   - *脅威*: クライアントが切断したにもかかわらずサーバー側ジェネレータがループし続け、スレッドや FD が枯渇する。
   - *緩和策*: イテレータの各ループで例外検知 (`GeneratorExit`, `BrokenPipeError`, `ConnectionResetError`) を行い、クリーンアップ処理を `finally` ブロックで確実に実行。最大ストリーミング継続時間（例: 3600秒）で安全に切断・再接続を促す。
2. **バッファリングによるレイテンシ遅延**:
   - *脅威*: プロキシ（Nginx / Envoy / Reverse Proxy）が SSE チャンクをバッファリングし、リアルタイム性が失われる。
   - *緩和策*: `X-Accel-Buffering: no` ヘッダーを送信し、15秒周期のキープアライブ Ping (`: ping\n\n` または `event: ping\ndata: {}\n\n`) を送出。
3. **クロスサイト・スクリプティング (CWE-79 / XSS) & MIME スニッフィング**:
   - *脅威*: ストリーミングされたログやイベントデータにスクリプトが含まれていた場合の不正実行。
   - *緩和策*: `Content-Type: text/event-stream; charset=utf-8` を厳格に指定し、フロントエンド側で `textContent` または `JSON.parse` による安全なエスケープ処理を強制。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/web/gateway/streaming.py](../../src/web/gateway/streaming.py)
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py)
- [x] [src/web/gateway/router.py](../../src/web/gateway/router.py)
- [x] [src/web/gateway/app.py](../../src/web/gateway/app.py)
- [x] [site/dashboard.html](../../site/dashboard.html)
- [x] [tests/web/gateway/test_gateway.py](../../tests/web/gateway/test_gateway.py)
- [x] [tests/web/test_dashboard_html.py](../../tests/web/test_dashboard_html.py)
- [x] [tests/web/test_web_server.py](../../tests/web/test_web_server.py)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/118-implement-web-gateway-sse-realtime-streaming`

1. **`src/web/gateway/streaming.py` の新設**:
   - `format_sse_event(data: Any, event: Optional[str] = None, event_id: Optional[str] = None, retry_ms: Optional[int] = None) -> bytes`: SSE 仕様準拠のバイト列フォーマッタ。
   - `sse_stream_generator(...)`: キープアライブ Ping、インターバル待機、最大寿命タイマーを内包した安全なストリーム生成ジェネレータ。
2. **`src/web/gateway/handlers.py` & `router.py` の拡張**:
   - `handle_stream_top(request: Request) -> Response`: `SupervisorTopViewer` / `HeartbeatWatchdog` からの最新プロセス状態を 1.0s 間隔でストリーミング。
   - `handle_stream_logs(request: Request) -> Response`: 最新のログレコードをストリーミング。
   - `handle_stream_events(request: Request) -> Response`: 総合システムイベントをストリーミング。
   - `GatewayRouter` に `/api/stream/top`, `/api/stream/logs`, `/api/stream/events` を登録。
3. **`site/dashboard.html` の EventSource 連携**:
   - EventSource 管理クラス / スクリプトを追加し、Live ストリーム受信時に Top モニタとチャートをスムーズに更新。
   - 接続ステータスバッジ（🟢 LIVE / 🟡 RECONNECTING / ⚪ POLLING）を追加。
4. **自動テストの追加と品質ゲート検証**:
   - `tests/web/gateway/test_gateway.py`: WSGI 環境における SSE イテレータのヘッダー・データ出力・切断クリーンアップの単体テスト。
   - `tests/web/test_dashboard_html.py`: EventSource 定義と UI バインディングの検証。
   - `make format`, `make static_analysis` (Xenon Rank A, Mypy Strict), `pytest` 100% PASS。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `GET /api/stream/top`, `GET /api/stream/logs`, `GET /api/stream/events` が `text/event-stream` で正常にストリーミングレスポンスを返却すること
- [x] 15 秒間隔のキープアライブ Ping (`event: ping`) が送信され、プロキシやブラウザのタイムアウトが防止されること
- [x] クライアント切断時にジェネレータが安全に終了し、メモリ・FD リークが発生しないこと
- [x] `site/dashboard.html` において Live Stream モードでリアルタイムにメトリクスが更新されること
- [x] 全ユニットテスト・統合テストおよび品質ゲート（`make format`, `make static_analysis` / Xenon Rank A, Mypy Strict）が 100% PASS すること

