---
ID: 118
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Web GatewayにおけるSSE (Server-Sent Events) リアルタイム・プッシュストリーミング API & UI ダッシュボード連携 (ID: 118)

## 1. 概要 / Summary
Web Gateway (`src/web/gateway/`) において、従来のポーリング方式に代わり、低オーバーヘッドな **Server-Sent Events (SSE)** エンドポイント（`/api/stream/events`, `/api/stream/logs`, `/api/stream/top`）を実装し、UI ダッシュボード (`site/dashboard.html`) へワーカー稼働状況・RPS・最新構造化ログ・検索クエリをリアルタイムプッシュ配信する。

---

## 2. トレーサビリティ / Traceability
- [DSN-09: Web Gateway & プレゼンテーション](../../docs/designs/DSN-09-web_gateway_and_presentation.md)
- [DSN-12: プロセススーパーバイザー](../../docs/designs/DSN-12-process_supervisor_and_arbiter.md)
- [DSN-10: 可観測性フレームワーク](../../docs/designs/DSN-10-observability_and_eval_framework.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/web/gateway/app.py](../../src/web/gateway/app.py)
- [ ] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py)
- [ ] [src/web/gateway/router.py](../../src/web/gateway/router.py)
- [ ] [site/dashboard.html](../../site/dashboard.html)
- [ ] [tests/web/gateway/test_gateway.py](../../tests/web/gateway/test_gateway.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/118-implement-web-gateway-sse-realtime-streaming`

1. **WSGI Chunked / Streaming Response Adapter**: PEP 3333 準拠のジェネレータを用いた `text/event-stream` レスポンスビルダーの実装。
2. **IPC Heartbeat & Log Tail Pub/Sub**: Supervisor の `control.sock` や `outputs/logs/*.jsonl` の新着イベントを購読して SSE 形式で逐次フラッシュ。
3. **Frontend EventSource Client**: `site/dashboard.html` における `EventSource` 接続、自動再接続、および Canvas/テーブルのリアルタイム再描画。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `curl -N http://localhost:8000/api/stream/events` でリアルタイムイベントがストリーミングされること
- [ ] クライアント切断時にリソースリーク（ゴーストスレッド等）が発生しないこと
- [ ] 全品質ゲート（Xenon Rank A, Flake8, pytest）を 100% パスすること
