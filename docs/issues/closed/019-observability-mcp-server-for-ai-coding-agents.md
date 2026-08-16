---
ID: 019
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] AIコーディングエージェント向け可観測性（Observability）特化型 MCP サーバーの実装 (ID: 019)

## 1. 概要 / Summary
基本設計書 [DSN-01](../../designs/DSN-01-high_level_design.md) および統合方針設計書 [DSN-09](../../designs/DSN-09-observability-and-performance-profiling.md) に基づき、AIコーディングエージェント（Antigravity等）が「計測（Observe）→ 分析（Analyze）→ 改善（Optimize）→ ベンチマーク検証（Verify）」の自律改善ループを実行できる **「可観測性特化型 MCP サーバー」**（`src/observability_mcp_server.py`）を構築しました。

---

## 2. トレーサビリティ / Traceability
- **設計規約**: [AGENTS.md](../../../.agents/AGENTS.md) (PM主導・品質ゲート準拠)
- **設計書**: [DSN-01-high_level_design.md](../../designs/DSN-01-high_level_design.md), [DSN-09-observability-and-performance-profiling.md](../../designs/DSN-09-observability-and-performance-profiling.md)
- **関連Issue**: [018-standard-library-observability-and-profiling-framework.md](018-standard-library-observability-and-profiling-framework.md), [015-enrich-mcp-server-for-coding-agents-with-resources-prompts-and-security-tools.md](015-enrich-mcp-server-for-coding-agents-with-resources-prompts-and-security-tools.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/observability_mcp_server.py](../../../src/observability_mcp_server.py)
- [x] [src/search/utils/profiler.py](../../../src/search/utils/profiler.py)
- [x] [Makefile](../../../Makefile)
- [x] [tests/test_observability_mcp_server.py](../../../tests/test_observability_mcp_server.py)
- [x] [docs/issues/README.md](../README.md)
- [x] [docs/designs/DSN-09-observability-and-performance-profiling.md](../../designs/DSN-09-observability-and-performance-profiling.md)

---

## 4. 実装成果 / Implementation Results
Target Branch: `feat/019-observability-mcp-server-for-ai-coding-agents`

1. **`src/observability_mcp_server.py` の実装**:
   - 5大ツールの提供:
     - `profile_code_performance`: cProfile + pstats による関数ボトルネック解析
     - `track_memory_allocations`: tracemalloc による行別メモリ割り当て・ピークメモリ追跡
     - `benchmark_alternatives`: timeit による複数実装コードの比較と最速判定（Speedup比）
     - `inspect_bytecode`: dis によるバイトコード命令数・逆アセンブル構造解析
     - `get_system_metrics`: 検索エンジン・キャッシュの稼働メトリクス
   - **AST セキュリティガード**: `ast.parse()` で危険なシステムコールやモジュールインポート（`subprocess`, `os.system` 等）を事前検査・遮断。
   - リソース (`observability://metrics/search_engine`, `observability://schema/profiler`) およびプロンプト (`optimize_bottleneck_prompt`) の提供。
2. **`Makefile` ターゲット追加**:
   - `run_observability_mcp`: 可観測性 MCP サーバー起動ターゲット。
3. **単体テスト**:
   - `tests/test_observability_mcp_server.py`（全8テスト・0.05s で 100% PASS）。
4. **設計書の統合**:
   - `DSN-09` と `DSN-10` を一元化し、自律改善ループの仕様を DSN-09 に完全統合。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] JSON-RPC 2.0 MCP サーバーが 5 大ツール、リソース、プロンプトを提供すること
- [x] AST セキュリティガードにより不正コード実行が阻止されること
- [x] 単体テストが 100% PASS すること (8/8 passed in 0.05s)
- [x] DSN-09 に設計が統合され、一元管理されていること
