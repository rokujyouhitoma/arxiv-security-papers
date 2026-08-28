---
ID: 096
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] 事前バッチ集計エンジン (Pre-Aggregated Analytics Engine) および高速アナリティクスストレージの実装 (ID: 096)

## 1. 概要 / Summary
Web ゲートウェイ（`src/web/gateway/handlers.py`）におけるオンデマンド・ファイル走査（オンザフライ正規表現集計）の構造的ボトルネックを解消するため、4x Daily 定期バッチおよび Supervisor バックグラウンドサービスと連携する「**事前バッチ集計エンジン（Pre-Aggregated Analytics Engine）**」と「**ゼロ外部依存型 高速アナリティクス永続ストレージ（`outputs/analytics/` & 専用 DB）**」を実装する。

これにより、論文数が十万件規模にスケールした場合でも、Web API（`/api/graph/mesh` 等）はディスク上の事前集計済みデータを $O(1)$ で高速読み出し、**1ms 未満の超低遅延応答（Zero-Scan Serving）** を恒久的に保証する。

---

## 2. トレーサビリティ & 脅威モデル / Traceability & Threat Model
- **関連資料**:
  - [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md)
  - [docs/designs/DSN-12-process_supervisor_and_arbiter.md](../designs/DSN-12-process_supervisor_and_arbiter.md)
  - [docs/designs/DSN-10-observability_and_eval_framework.md](../designs/DSN-10-observability_and_eval_framework.md)
  - [docs/designs/DSN-17-security_knowledge_ontology_and_graph_database_engine.md](../designs/DSN-17-security_knowledge_ontology_and_graph_database_engine.md)
- **脅威モデル & セキュリティ要件 (Sec / AU 監査)**:
  - **T1: アトミック更新による不整合防止**: 集計データの書き込み時（アトミックな一時ファイル rename や WAL チェックポイント連携）に、読み取りプロセスが中途半端なデータを読み込まないよう保護。
  - **T2: パストラバーサル・任意ファイル書き込み排除**: アナリティクス保存先ディレクトリ（`outputs/analytics/`）を workspace ルート内に厳密に限定。
  - **T3: データ信頼性・追跡可能性 (Provenance)**: 集計メタデータに実行タイムスタンプ（JST / UTC）、集計対象論文件数、ハッシュ値を付与。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/analytics/aggregator.py](../../src/analytics/aggregator.py) [NEW]: 事前バッチ集計エンジン（脅威動向・時系列増減率・ROI・グラフ指標）
- [ ] [src/analytics/storage.py](../../src/analytics/storage.py) [NEW]: 高速アナリティクスストレージ（JSON Snapshot / 専用 SQLite 自己完結マイグレーション付き DB インターフェース）
- [ ] [src/analytics/cli.py](../../src/analytics/cli.py) [NEW]: バッチ集計 CLI コマンド (`python -m analytics.cli aggregate`)
- [ ] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py): 事前集計ストレージからの $O(1)$ 高速リードへの切り替え
- [ ] [tests/analytics/test_aggregator.py](../../tests/analytics/test_aggregator.py) [NEW]: 集計エンジンとストレージの単体テスト
- [ ] [tests/web/test_dashboard_html.py](../../tests/web/test_dashboard_html.py): API レイテンシとレスポンス整合性検証

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/096-implement-pre-aggregated-analytics-engine-and-storage`

### Step 1: アナリティクスストレージ (`src/analytics/storage.py`) の実装
1. `AnalyticsStorage` クラスの作成:
   - `outputs/analytics/latest_metrics.json` へのアトミック書き込み（`tempfile` 書き込み $\rightarrow$ `os.replace`）および $O(1)$ 高速リード。
   - `outputs/analytics/analytics.db`（SQLite）への時系列履歴記録と、Pure Python 自己完結型自動マイグレーション機構（`PRAGMA user_version` / `CREATE TABLE IF NOT EXISTS`）。

### Step 2: 事前バッチ集計エンジン (`src/analytics/aggregator.py`) の実装
1. `AnalyticsAggregator` クラスの作成:
   - 全 OKF 論文メタデータ、5階層サマリー（01〜05）、OTLP トレースログ、WAL 状態を一括スキャン。
   - 脅威ベクトル Top 5（実出現数および前後半タイムライン比較による実測増減率 %）、トークン削減 ROI、Tail Latency、パイプライン SLO を事前計算。
   - 計算結果を `AnalyticsStorage` に永続化。

### Step 3: Web ゲートウェイ (`src/web/gateway/handlers.py`) の $O(1)$ 最適化
1. `_introspect_strategic_metrics()` をリファクタリング:
   - リクエスト時のオンザフライ全ファイル走査・正規表現マッチングを全廃。
   - `AnalyticsStorage.load_latest_metrics()` を呼び出し、$1\text{ms}$ 未満で即時応答。
   - ストレージが存在しない場合の安全なフォールバックを維持。

### Step 4: CLI 連携 & 4x Daily バッチ統合
1. `src/analytics/cli.py` に `aggregate` サブコマンドを追加。
2. `make aggregate_analytics` ターゲットを Makefile に追加。

### Step 5: テスト & 品質ゲート検証
1. `tests/analytics/test_aggregator.py` で集計結果の正確性、アトミック性、マイグレーション動作を検証。
2. `make format`, `make static_analysis` (flake8/mypy), `pytest tests/analytics/ tests/web/` を全パス。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `src/analytics/` に集計エンジンとストレージが実装され、単体テストが完備されていること。
- [ ] `/api/graph/mesh` のリクエスト処理時にファイル全量走査が発生せず、レイテンシが 1ms 未満に短縮されること。
- [ ] `outputs/analytics/latest_metrics.json` に実測データがアトミックに保存・更新されること。
- [ ] `make check` / `make verify_quality` が 100% PASS すること。
