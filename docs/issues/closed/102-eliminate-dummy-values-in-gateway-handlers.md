---
ID: 102
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-08-28
---

# [FEAT/ENH] Eliminate All Dummy & Hardcoded Fallback Values in Gateway Handlers (ID: 102)

## 1. 概要 / Summary
`src/web/gateway/handlers.py` 内に存在していたすべてのダミー値、固定フォールバック値、ハードコードされたメトリクス（OBFスパン固定内訳、IOPS/キャッシュヒット率の固定値、検索プロファイルの固定レイテンシ `1.0ms`、テレメトリの固定値 `1.84ms` / `74.2%`、論文不在時の固定モックグラフなど）を完全に排除し、実際のストレージ・ログ・トレースファイル・測定ベンチマークから100%動的に導出・集計する高信頼性アーキテクチャへ刷新しました。

---

## 2. トレーサビリティ / Traceability
- **Governance & Rules**:
  - [AGENTS.md](../../.agents/AGENTS.md) (Section 2 & 6: 0 synthetic or guessed worker metrics, Real Data Storage)
- **Design Architecture**:
  - [DSN-01 High-Level Architecture Design](../designs/DSN-01-high_level_design.md) (Section 4: Gateway Layer)
  - [DSN-14 Graph Engineering Dashboard](../designs/DSN-14-graph-engineering-dashboard.md) (Section 3: Real-Time Telemetry Contracts)
  - [DSN-15 OpenTelemetry Observability](../designs/DSN-15-opentelemetry-observability.md) (Section 2: W3C Trace Context & Spans)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) - ダミー値の全廃、実測計測・集計ロジックの実装
- [x] [src/observability/trace.py](../../src/observability/trace.py) - OTLP スパン属性・分類仕様の整合
- [x] [src/analytics/aggregator.py](../../src/analytics/aggregator.py) - アナリティクス集計フォールバックのクリーン化
- [x] [site/dashboard.html](../../site/dashboard.html) - 動的データ受信時のゼロ値・未測定フォールバック表示確認
- [x] [tests/web/gateway/test_gateway.py](../../tests/web/gateway/test_gateway.py) - 実測値・動的集計のユニットテスト
- [x] [tests/web/test_dashboard_html.py](../../tests/web/test_dashboard_html.py) - ダッシュボード統合テスト

---

## 4. ダミー値箇所の詳細インベントリと是正仕様

### 1. `_introspect_live_loop_and_obf_state` (L244–L322)
* **対象ダミー値**:
  * `latest_cycle = "cycle_20260828_003354"` (固定デフォルト)
  * `proc_count = 14507`, `spans_count = 2840` (固定デフォルト)
  * `obf_data`: `llm_spans=1240`, `retriever_spans=820`, `tool_spans=540`, `pipeline_spans=240`, `latest_traceparent="00-8b673ec2...-01"`, `status="HTTP 200 / 0 Loss"`
* **是正仕様**:
  * `outputs/logs/otlp_traces.jsonl` の各行をパースし、スパン名または属性（`span_name` や `attributes`）から `llm_spans` (llm.*), `retriever_spans` (retriever.* / search.*), `tool_spans` (tool.* / mcp.*), `pipeline_spans` (pipeline.* / wal.*) をリアルタイムに累積カウント。
  * ファイルが存在しない場合は `proc_count = 0`, `spans_count = 0`, 各内訳 `0` を返却。
  * `latest_cycle` は WAL チェックポイントファイルが存在しない場合 `"cycle_initial"` を返却。

### 2. `_introspect_strategic_metrics` (L380–L422)
* **対象ダミー値**:
  * `token_cost_savings_usd: 101.5`, `token_savings_pct: "-74.2%"`, `executive_tier_coverage: "100.0% (5/5 Tiers, 650 docs)"`
  * `latency_p95_ms: 74.82`, `latency_p99_ms: 96.69`, `graph_density: 0.048`, `isolated_nodes_pct: 0.0`, `worker_mttr: "<0.18s Self-Heal"`
  * `pipeline_slo_pct: 99.98`, `worker_mttr_sec: 0.18`, `batch_success_streak: 124`, `uptime_target: "99.9% 4x Daily SLA"`
* **是正仕様**:
  * `AnalyticsStorage.load_latest_metrics()` が None の場合は `AnalyticsAggregator.aggregate_all()` を実行し、それでもデータが得られない場合は固定ダミー値ではなく実数 `0.0` / `[]` / `"0.0%"` を設定。
  * `batch_success_streak` は実際のログファイル (`outputs/logs/pipeline.log` / `checkpoint.json`) の連続成功回数を算出。

### 3. `_introspect_database_metrics` (L435–L746)
* **対象ダミー値**:
  * `vec_ratio = 0.40`
  * `read_iops = 4850`, `bench_latencies = [0.18, 0.22, 0.35, 0.42, 0.85]`
  * `"buffer_pool_hit_rate": "99.4%"`, `"vector_cache_hit_rate": "99.8%"`
  * `"wal_flush_rate_kb_s": round(42.0 * 2.5, 1)`, `"wal_sync_lag_ms": 0.12`
  * `"active_transactions": 1`, `"tps": int(read_iops * 0.12)`
* **是正仕様**:
  * `PropertyGraphEngine` が未初期化の場合は `read_iops = 0`, `bench_latencies = []` とし、実測可能な場合のみ micro-benchmark を実行。
  * WAL フラッシュレートおよび Sync Lag は `outputs/wal/` 内の最新ファイルのタイムスタンプ差分とファイルサイズから動的計算。
  * キャッシュヒット率は実プロファイラ (`Profiler` / `BufferPool`) の統計から取得（未計測時は `"N/A"` / `0.0%`）。

### 4. `handle_search` (L802–864)
* **対象ダミー値**:
  * `mode == "vector"` / `mode == "rrf"` 時に `profile = {"total_ms": 1.0}` を固定設定。
* **是正仕様**:
  * 検索関数の呼出前後に `t0 = time.perf_counter()`, `t1 = time.perf_counter()` を行い、`profile["total_ms"] = round((t1 - t0) * 1000.0, 3)` で高精度実測値を格納。

### 5. `handle_graph_mesh` (L1030–1102)
* **対象ダミー値**:
  * `"latency_ms": 1.84`
  * `"token_savings_pct": 74.2`
  * `"active_pipeline_stage": "RESOLVE"`
  * `_walks_per_min` フォールバック `412`
* **是正仕様**:
  * `latency_ms` はグラフメッシュ構築処理の `time.perf_counter()` 実測時間を代入。
  * `token_savings_pct` は `strategic_data["st_strategist"]["token_savings_pct"]` から動的抽出。
  * `active_pipeline_stage` は `phase_status` のアクティブフェーズ（例: `COLLECTION`, `PROCESSING` 等）を動的に設定。

### 6. `_build_canonical_mesh_fallback` (L147–241)
* **対象ダミー値**:
  * ハードコードされた論文5本 (`canonical_papers`)
* **是正仕様**:
  * ハードコードリストを撤廃。論文が 0 件の場合は空リスト `nodes = []`, `edges = []` を返すか、`processed_papers.json` から最新の論文エントリを取得して動的構築。

### 7. `_generate_fallback_paper_content` (L925–943)
* **対象ダミー値**:
  * 合成 Markdown テンプレート生成
* **是正仕様**:
  * ファイル実体が存在しない場合は 404 エラーを返し、無根拠な合成ドキュメントの生成を廃止。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/102-eliminate-dummy-values-in-gateway-handlers`

1. **Helper 関数の新設・刷新 (`src/web/gateway/handlers.py`)**:
   - `_parse_and_aggregate_otlp_traces(workspace_dir: str)`: OTLP JSONL トレースから実スパン種別・合計数を集計
   - `_compute_real_wal_metrics(workspace_dir: str)`: WAL 実ファイル群からスループットと同期ラグを算出
2. **`handle_search` レイテンシ実測化**:
   - `mode == "vector"`, `mode == "rrf"`, `mode == "hybrid"` 全モードで `perf_counter` による実時間計測を適用
3. **`_introspect_database_metrics` の実数化**:
   - ハードコード文字列（`"99.4%"`, `"0.12"` 等）を実測値・動的フォーマットに変更
4. **`handle_graph_mesh` テレメトリの動的バインド**:
   - レイテンシ・トークン削減率・パイプラインステージの実値バインド
5. **テスト作成と品質ゲート検証**:
   - `tests/web/gateway/test_gateway.py` にダミー値不在検証テストを追加
   - `make format` & `make check` (100% PASS) を検証

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `src/web/gateway/handlers.py` 内にハードコードされたダミーメトリクス・固定スパン数が 0 件であること
- [x] 検索 API (`/api/search`) の `profile.total_ms` が実測時間であること
- [x] `/api/graph/mesh` の `telemetry`, `obf_telemetry`, `database_metrics` が実ファイル・実メモリから取得されること
- [x] 論文 0 件時にハードコードされたモック論文リストを出力しないこと
- [x] 全テスト（`tests/web/gateway/test_gateway.py`, `tests/web/test_dashboard_html.py` 等）が 100% PASS すること
- [x] `make check` の静的解析・品質ゲートがすべて PASS すること
