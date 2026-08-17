---
ID: 025
種別: Feature / Observability
優先度: High
ステータス: Closed (Completed)
完了日: 2026-08-17
---

# [FEAT/OBS] MCP および検索エンジンにおける処理速度・メモリ可観測性の統合とログダンプ・計測基盤の実装 (ID: 025)

## 1. 概要 / Summary
機能設計書 [DSN-09](../../designs/DSN-09-observability-and-performance-profiling.md) および **PM / SA / IT Specialist (Observability)** の合意方針に基づき、**MCP サーバー群（`src/mcp/`）** および **検索エンジン（`src/search/`）** の双方において、リクエスト・クエリ処理時の **処理速度（Wall-Clock / CPU時間）** と **メモリ消費（Peak Memory / Memory Delta / RSS）** を高精度かつゼロ依存でリアルタイム計測・可観測化し、構造化ログ（`outputs/logs/mcp_perf_log.jsonl`, `outputs/logs/search_perf_log.jsonl`, `outputs/logs/query_log.jsonl`）へ自動ダンプして計測・分析可能にする統合可観測性基盤を構築しました。

---

## 2. トレーサビリティ / Traceability
- **設計規約**: [AGENTS.md](../../../.agents/AGENTS.md) (PM / SA / IT Service Manager)
- **設計書**: [DSN-09-observability-and-performance-profiling.md](../../designs/DSN-09-observability-and-performance-profiling.md), [DSN-10-search-engine-evaluation-framework.md](../../designs/DSN-10-search-engine-evaluation-framework.md), [DSN-12-mcp-strategic-ecosystem-expansion.md](../../designs/DSN-12-mcp-strategic-ecosystem-expansion.md)
- **関連Issue**: [018-standard-library-observability-and-profiling-framework.md](018-standard-library-observability-and-profiling-framework.md), [019-observability-mcp-server-for-ai-coding-agents.md](019-observability-mcp-server-for-ai-coding-agents.md), [024-consolidate-mcp-servers-into-src-mcp.md](024-consolidate-mcp-servers-into-src-mcp.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/mcp/base.py](../../../src/mcp/base.py) (MCP 共通トランスポートにおける tracemalloc / time 統合計測とログダンプ)
- [x] [src/search/utils/profiler.py](../../../src/search/utils/profiler.py) (ゼロ依存プロファイラ・メモリトラッカーの拡張)
- [x] [src/search/vector_engine.py](../../../src/search/vector_engine.py) (検索パイプライン各ステージのメモリ・速度計測とログダンプ)
- [x] [src/search/server/handler/select_handler.py](../../../src/search/server/handler/select_handler.py) (Lucene/Solr ハンドラにおける計測とプロファイル付与)
- [x] [src/mcp/observability_server.py](../../../src/mcp/observability_server.py) (ログダンプ・メモリメトリクス取得ツールの統合)
- [x] [src/web_server.py](../../../src/web_server.py) (Web クエリログのメモリ拡張)
- [x] [tests/test_observability_mcp_server.py](../../../tests/test_observability_mcp_server.py) (MCP & 検索エンジン可観測性の自動テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/025-performance-and-memory-observability`

1. **MCP トランスポート層の計測強化 (`src/mcp/base.py`)**:
   - `run_mcp_server` の `tools/call`, `prompts/get`, `resources/read` 実行時に `tracemalloc` と `time.perf_counter` / `time.process_time` を活用し、各ハンドラの実行時間（`execution_ms`, `cpu_ms`）およびメモリ消費（`peak_memory_kb`, `memory_delta_kb`）を計測。
   - `log_mcp_performance` を拡張し、`outputs/logs/mcp_perf_log.jsonl` に完全な速度・メモリプロファイルをダンプ。
2. **検索エンジンの計測・ダンプ強化 (`src/search/vector_engine.py`, `select_handler.py`)**:
   - `search_with_profile` および `SelectHandler.handle_select` にて、トークナイズ・候補絞り込み・BM25/ハイブリッドスコアリング・ハイライト生成の各フェーズにおける所要時間（ms）に加え、メモリピーク・増分（KB）を `ExecutionProfiler` で計測。
   - 構造化プロファイルログを `outputs/logs/search_perf_log.jsonl` / `query_log.jsonl` に自動出力。
3. **Observability MCP サーバーの機能拡張 (`src/mcp/observability_server.py`)**:
   - `get_system_metrics` にメモリ消費推移や最新ログ集計（平均レスポンスタイム、P95レイテンシ、ピークメモリ）を含める。
   - ログダンプ確認用ツール `get_performance_logs` / `dump_performance_metrics` を提供。
4. **テストスイートの拡充**:
   - 速度・メモリ計測の正確性、ログファイルへの JSONL 出力、およびデータ整合性をアサートする単体テストを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] MCP サーバー全ツール実行時に処理速度（ms）とメモリ（KB）が計測され、`outputs/logs/mcp_perf_log.jsonl` にダンプされること。
- [x] 検索エンジン実行時にフェーズ別処理速度とメモリが計測され、`outputs/logs/search_perf_log.jsonl` / `query_log.jsonl` にダンプされること。
- [x] Observability MCP サーバー経由でメトリクスとログが取得・可観測化できること。
- [x] 静的型解析 `mypy` 0 エラー、`flake8` 0 警告、全テスト PASS (82/82 100% PASS)。
