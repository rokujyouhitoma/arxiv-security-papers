---
ID: 411
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] Web コンソールにおけるパイプラインリアルタイム進捗ストリーミング (SSE) とステータス可視化の実装 (ID: 411)

## 1. 概要 / Summary
Issue 410 および 412 により、パイプライン（`arxiv_okf_fetcher.py`）の Stage 1 (Ingestion) および Stage 2 (Transformation) における詳細なリアルタイム進捗ログが出力されるようになった。
本 Issue では、これらの進捗情報（ステージ名、完了件数、全体件数、進捗パーセンテージ、最新処理論文ID、ステータス、ログメッセージ）をスレッドセーフなイベントブロードキャスターを介して収集し、Web Gateway の Server-Sent Events (SSE) エンドポイント `/api/stream/pipeline` 経由でブラウザ画面にリアルタイム配信する。
これにより、Web UI 上でプログレスバーやライブステータスを即時確認可能にする。

---

## 2. 多角的エージェント検討 / Multi-Agent Review
- **Project Manager (PM)**:
  - ユーザーが Web コンソールからパイプライン進行状況をプログレスバーと現在フェーズで一目で把握できるようにする。
- **Systems Architect**:
  - SSE ストリーミングは既存の `src/web/gateway/streaming.py` 内の HSM（階層型状態遷移マシン）パターンに統合し、クライアント切断（`BrokenPipeError` 等）時もリソースリークを起こさない堅牢な設計とする。
- **Network Specialist**:
  - `Content-Type: text/event-stream`、`Cache-Control: no-cache`、`X-Accel-Buffering: no` の適切なヘッダー送出と定期的な Keep-Alive ハートビート（2秒間隔）を保証する。
- **Software Quality Assurance (QA)**:
  - パイプライン未起動時、パイプライン実行中、完了時、クライアント切断時のそれぞれの振る舞いを単体テストで網羅する。

---

## 3. トレーサビリティ / Traceability
- 関連資料:
  - [.agents/AGENTS.md](../../.agents/AGENTS.md) (Section 1: Systems Architect & Web Gateway Presentation Services)
  - [src/web/gateway/streaming.py](../../src/web/gateway/streaming.py)
  - [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py)
  - [src/web/gateway/app.py](../../src/web/gateway/app.py)
  - [src/pipeline/arxiv_okf_fetcher.py](../../src/pipeline/arxiv_okf_fetcher.py)
  - [docs/issues/closed/410-enhance-pipeline-pdf-ingestion-progress-logging.md](closed/410-enhance-pipeline-pdf-ingestion-progress-logging.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/pipeline/events.py](../../src/pipeline/events.py)
- [ ] [src/web/gateway/streaming.py](../../src/web/gateway/streaming.py)
- [ ] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py)
- [ ] [src/web/gateway/app.py](../../src/web/gateway/app.py)
- [ ] [src/pipeline/arxiv_okf_fetcher.py](../../src/pipeline/arxiv_okf_fetcher.py)
- [ ] [tests/web/test_gateway.py](../../tests/web/test_gateway.py)
- [ ] [docs/issues/README.md](README.md)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/411-web-console-pipeline-sse-streaming-and-progress-visualization`

1. **`PipelineEventBroadcaster` の新設 (`src/pipeline/events.py`)**:
   - シングルトン / スレッドセーフなキューベースのパブサブクラスを新設。
   - `emit(event_type, payload)` により、`stage_start`, `progress`, `stage_finish`, `pipeline_finish` を配信。
   - `subscribe() -> queue.Queue` で各 SSE ストリームワーカーにブロードキャスト。
   - 最新状態（`last_state`）を保持し、新規接続クライアントに即座に現行進捗を返答。

2. **`arxiv_okf_fetcher.py` との連携**:
   - `_execute_pdf_download_pool`、`_transform_and_save_okf`、`run_theme_pipeline` の各段階で `PipelineEventBroadcaster.get_instance().emit(...)` を呼び出す。

3. **SSE ジェネレータとエンドポイントの拡張**:
   - `src/web/gateway/streaming.py` に `stream_pipeline_events(interval=1.0)` を実装。
   - `src/web/gateway/handlers.py` に `handle_stream_pipeline` を追加。
   - `src/web/gateway/app.py` の `_route_stream_api` に `/api/stream/pipeline` をルーティング。

4. **テストの追加**:
   - `tests/web/test_gateway.py` に `/api/stream/pipeline` の接続、イベント配信、切断時のフォールバックを検証する単体テストを追加。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `src/pipeline/events.py` が実装され、スレッドセーフに進捗イベントを購読・配信できること。
- [x] `arxiv_okf_fetcher.py` の各ステージおよび進捗更新がブロードキャスター経由で発行されること。
- [x] Web Gateway の `/api/stream/pipeline` エンドポイント経由で SSE 形式の進捗データがストリーミングされること。
- [x] 単体テストが追加され、品質ゲート (`make format`, `make static_analysis`, `make test`) がすべて 100% PASS すること。
- [x] 全ドキュメント内の内部リンクが相対パスで正しく構成されていること。
