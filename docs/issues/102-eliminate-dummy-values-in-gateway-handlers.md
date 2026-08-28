---
ID: 102
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Eliminate All Dummy & Hardcoded Fallback Values in Gateway Handlers (ID: 102)

## 1. 概要 / Summary
`src/web/gateway/handlers.py` 内に散在しているダミー値、固定フォールバック値、ハードコードされたメトリクス（OBFスパン固定値、IOPS/キャッシュヒット率の固定値、検索プロファイルの固定レイテンシ `1.0ms`、テレメトリの固定値 `1.84ms` / `74.2%` など）をすべて排除し、実際のストレージ・ログ・トレースファイル・測定ベンチマークから100%動的に導出・集計する実装へ刷新します。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [AGENTS.md](../../.agents/AGENTS.md) (Section 2 & 6: 0 synthetic or guessed worker metrics, Real Data Storage)
  - [DSN-01 High-Level Architecture Design](../designs/DSN-01-high_level_design.md)
  - [DSN-14 Graph Engineering Dashboard](../designs/DSN-14-graph-engineering-dashboard.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py)
- [ ] [src/observability/trace.py](../../src/observability/trace.py)
- [ ] [src/analytics/aggregator.py](../../src/analytics/aggregator.py)
- [ ] [tests/web/gateway/test_gateway.py](../../tests/web/gateway/test_gateway.py)
- [ ] [tests/web/test_dashboard_html.py](../../tests/web/test_dashboard_html.py)

---

## 4. ダミー値箇所の詳細インベントリ / Dummy Values Inventory

### 1. `_introspect_live_loop_and_obf_state` (Lines 244–322)
- **現状のダミー値**:
  - `latest_cycle = "cycle_20260828_003354"` (固定デフォルト)
  - `proc_count = 14507`, `spans_count = 2840` (固定デフォルト)
  - `obf_data`: `llm_spans=1240`, `retriever_spans=820`, `tool_spans=540`, `pipeline_spans=240`, `latest_traceparent="00-8b673ec2...-01"`
- **是正方針**:
  - `outputs/logs/otlp_traces.jsonl` を走査し、各スパンの `attributes` やスパン名から実LLM/Retriever/Tool/Pipelineスパン数を動的カウント。
  - トレースファイルが存在しない場合は 0 を返し、実ログに基づく。

### 2. `_introspect_strategic_metrics` (Lines 380–422)
- **現状のダミー値**:
  - `token_cost_savings_usd: 101.5`, `token_savings_pct: "-74.2%"`, `executive_tier_coverage: "100.0% (5/5 Tiers, 650 docs)"`
  - `latency_p95_ms: 74.82`, `latency_p99_ms: 96.69`, `graph_density: 0.048`
  - `batch_success_streak: 124`, `worker_mttr: "<0.18s Self-Heal"`
- **是正方針**:
  - `AnalyticsStorage` / `AnalyticsAggregator` からの実算出値のみを使用。データ不在時は実測算出または 0/測定不能表示。

### 3. `_introspect_database_metrics` (Lines 435–746)
- **現状のダミー値**:
  - `read_iops = 4850`, `bench_latencies = [0.18, 0.22, 0.35, 0.42, 0.85]` (未初期化時)
  - `buffer_pool_hit_rate = "99.4%"`, `vector_cache_hit_rate = "99.8%"`
  - `wal_flush_rate_kb_s = 42.0 * 2.5`, `wal_sync_lag_ms = 0.12`
  - `active_transactions = 1`, `tps = int(read_iops * 0.12)`
- **是正方針**:
  - BufferPool インスタンスまたは実際の WAL ファイルサイズ・更新時刻差分からリアルタイム算出。

### 4. `handle_search` (Lines 802–864)
- **現状のダミー値**:
  - `mode == "vector"` / `mode == "rrf"` 時に `profile = {"total_ms": 1.0}` を固定設定。
- **是正方針**:
  - `time.perf_counter()` による検索実行時間の正確な計測値を `profile["total_ms"]` に代入。

### 5. `handle_graph_mesh` (Lines 1030–1102)
- **現状のダミー値**:
  - `"latency_ms": 1.84`
  - `"token_savings_pct": 74.2`
  - `"active_pipeline_stage": "RESOLVE"`
  - `_walks_per_min` フォールバック `412`
- **是正方針**:
  - 実際のグラフ走査レイテンシ、実算出トークン削減率、DAGチェックポイントの実ステージ名を代入。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/102-eliminate-dummy-values-in-gateway-handlers`

1. `otlp_traces.jsonl` の実スパン種別（`llm`, `retriever`, `tool`, `pipeline`）集計関数の実装
2. `handle_search` での実際のミリ秒計測 (`time.perf_counter()`) の適用
3. `handle_graph_mesh` における全テレメトリフィールドの実測定値バインド
4. `_introspect_database_metrics` の WAL・バッファプール実測値連携
5. 単体テストおよびダッシュボード UI テストの更新・検証

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `src/web/gateway/handlers.py` 内にハードコードされたダミーメトリクス・固定スパン数が 0 件であること
- [ ] 検索 API (`/api/search`) の `profile.total_ms` が実測時間であること
- [ ] `/api/graph/mesh` の `telemetry`, `obf_telemetry`, `database_metrics` が実ファイル・実メモリから取得されること
- [ ] 全テスト（`tests/web/gateway/test_gateway.py`, `tests/web/test_dashboard_html.py` 等）が 100% PASS すること
- [ ] `make check` の静的解析がエラー 0 件であること
