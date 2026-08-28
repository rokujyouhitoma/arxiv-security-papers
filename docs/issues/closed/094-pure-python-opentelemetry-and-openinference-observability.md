---
ID: 094
種別: Feature
優先度: Critical
ステータス: Closed (Completed)
完了日: 2026-08-28
---

# [FEATURE] ゼロ外部依存 (Pure Python) エンドツーエンド OpenTelemetry & OpenInference 分散オブザーバビリティ基盤の実装 (ID: 094)

## 1. 概要 / Summary
外部パッケージ（`opentelemetry-*`, `openinference-*`, `requests` 等）を一切使用せず、Python 3.14+ 標準ライブラリのみで **W3C Trace Context (traceparent) 伝播**、**OpenTelemetry OTLP/HTTP JSON エクスポーター**、**OpenInference 規格準拠の GenAI セマンティックコンベンション**、および **短命 (Ephemeral) プロセス向け atexit/signal 確定フラッシュ機構** を備えたエンドツーエンド分散トレーシング基盤を `src/observability/` に実装した。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-01: 全体高位アーキテクチャ設計書](../designs/DSN-01-high_level_design.md)
  - [DSN-02: 全体低位アーキテクチャ設計書](../designs/DSN-02-low_level_design.md)
  - [DSN-10: 可観測性 (Observability) & 情報検索評価 (IR Eval) 設計書](../designs/DSN-10-observability_and_eval_framework.md)
  - [DSN-11: 閉ループ・ドメインインテリジェンス & 汎用ワークフロー包括設計書](../designs/DSN-11-intelligence_orchestration_engine.md)
  - [DSN-16: 次世代セキュリティ・ナレッジプラットフォーム包括的設計提言書](../designs/DSN-16-nextgen_security_knowledge_platform_proposal.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [docs/designs/DSN-10-observability_and_eval_framework.md](../../docs/designs/DSN-10-observability_and_eval_framework.md)
- [x] [src/observability/__init__.py](../../src/observability/__init__.py)
- [x] [src/observability/trace.py](../../src/observability/trace.py)
- [x] [src/observability/propagation.py](../../src/observability/propagation.py)
- [x] [src/observability/export.py](../../src/observability/export.py)
- [x] [src/observability/openinference.py](../../src/observability/openinference.py)
- [x] [src/pipeline/arxiv_okf_fetcher.py](../../src/pipeline/arxiv_okf_fetcher.py)
- [x] [src/intelligence/engine.py](../../src/intelligence/engine.py)
- [x] [.github/workflows/paper_ingestion.yml](../../.github/workflows/paper_ingestion.yml)
- [x] [tests/observability/test_tracing.py](../../tests/observability/test_tracing.py)
- [x] [tests/observability/test_propagation.py](../../tests/observability/test_propagation.py)
- [x] [tests/observability/test_openinference.py](../../tests/observability/test_openinference.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/094-pure-python-opentelemetry-and-openinference-observability`

1. **W3C Trace Context 伝播層 (`src/observability/propagation.py`)**:
   - `00-{trace_id:32hex}-{span_id:16hex}-{trace_flags:2hex}` の正規表現解析と生成。
   - `extract_w3c_traceparent(carrier_or_env)` / `inject_w3c_traceparent(carrier, span)`。
2. **コアトレーシングエンジン (`src/observability/trace.py`)**:
   - `Span`, `SpanContext`, `Tracer`, `TracerProvider`, `StatusCode`, `Status` を標準ライブラリ（`dataclasses`, `time`, `contextlib`, `uuid`）で実装。
   - コンテキストマネージャ `tracer.start_as_current_span(name, context=None)` によるスレッドセーフなスパンネスト。
3. **OTLP JSON エクスポーター & ライフサイクル管理 (`src/observability/export.py`)**:
   - OTLP/HTTP `v1/traces` JSON スキーマシリアライザ（`urllib.request` 使用）。
   - `BatchSpanProcessor` / `SimpleSpanProcessor`。
   - `atexit.register()` および `signal.signal(SIGTERM/SIGINT)` によるブロッキング強制フラッシュ（Telemetry Loss 防御）。
4. **OpenInference GenAI セマンティックコンベンション (`src/observability/openinference.py`)**:
   - `OpenInferenceSpanKind` (LLM, EMBEDDING, RETRIEVER, TOOL, CHAIN, AGENT)。
   - `record_llm_call(span, model, prompt_tokens, completion_tokens, messages)` 等の型安全ヘルパー。
5. **パイプライン & インテリジェンス層統合**:
   - `arxiv_okf_fetcher.py` および `intelligence/engine.py` でルートスパン／子スパンを記録。
6. **品質ゲート検証**:
   - `make check_format`, `make static_analysis`, `make test` を 100% PASS。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 外部パッケージを一切追加せず（`requirements.txt` 変更なし）、標準ライブラリのみで動作すること
- [x] W3C `TRACEPARENT` 環境変数が親スパンとして正しく抽出・伝播されること
- [x] OpenTelemetry OTLP JSON (v1/traces) 形式での出力・エクスポートが可能であること
- [x] OpenInference 規格（`openinference.span.kind`, `llm.*`）に準拠した属性が付与されること
- [x] プロセス終了時（`atexit`, `SIGTERM`）にテレメトリの消失なく強制フラッシュされること
- [x] 全テストおよび `make check_format`, `make static_analysis`, `make test` が 100% PASS すること

