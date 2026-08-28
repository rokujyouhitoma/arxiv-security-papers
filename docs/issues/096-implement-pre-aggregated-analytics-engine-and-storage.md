---
ID: 096
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 事前バッチ集計エンジン (Pre-Aggregated Analytics Engine) および高速アナリティクスストレージの実装 (ID: 096)

## 1. 概要 / Summary
Web ゲートウェイ（`src/web/gateway/handlers.py`）におけるオンデマンド・ファイル走査（オンザフライ正規表現集計）の構造的ボトルネックを解消するため、4x Daily 定期バッチおよび Supervisor バックグラウンドサービスと連携する「**事前バッチ集計エンジン（Pre-Aggregated Analytics Engine）**」と「**高速アナリティクス永続ストレージ（専用 DB / Snapshot Storage）**」を実装する。

これにより、論文数が十万件規模にスケールした場合でも、Web API（`/api/graph/mesh` 等）はディスク上の事前集計済みデータを $O(1)$ で高速読み出し、**1ms 未満の超低遅延応答（Zero-Scan Serving）** を恒久的に保証する。

---

## 2. トレーサビリティ & 脅威モデル / Traceability & Threat Model
- **関連資料**:
  - [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md)
  - [docs/designs/DSN-12-process_supervisor_and_arbiter.md](../designs/DSN-12-process_supervisor_and_arbiter.md)
  - [docs/designs/DSN-10-observability_and_eval_framework.md](../designs/DSN-10-observability_and_eval_framework.md)
- **脅威モデル & セキュリティ要件 (Sec / AU 監査)**:
  - **T1: アトミック更新による不整合防止**: 集計データの書き込み時（アトミックな一時ファイル rename や WAL チェックポイント連携）に、読み取りプロセスが中途半端なデータを読み込まないよう保護。
  - **T2: パストラバーサル・任意ファイル書き込み排除**: アナリティクス保存先ディレクトリ（`outputs/analytics/`）を workspace ルート内に厳密に限定。
  - **T3: データ信頼性・追跡可能性 (Provenance)**: 集計メタデータに実行タイムスタンプ（JST / UTC）、集計対象論文件数、ハッシュ値を付与。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/analytics/aggregator.py](../../src/analytics/aggregator.py) [NEW]: 事前バッチ集計エンジン（脅威動向・時系列増減率・ROI・グラフ指標）
- [ ] [src/analytics/storage.py](../../src/analytics/storage.py) [NEW]: 高速アナリティクスストレージ（JSON Snapshot / 専用 DB インターフェース）
- [ ] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py): 事前集計ストレージからの $O(1)$ 高速リードへの切り替え
- [ ] [src/supervisor/contracts.py](../../src/supervisor/contracts.py) / [src/supervisor/config.py](../../src/supervisor/config.py): アナリティクス定期集計ワーカーの定義
- [ ] [tests/analytics/test_aggregator.py](../../tests/analytics/test_aggregator.py) [NEW]: 集計エンジンとストレージの単体テスト
- [ ] [tests/web/test_dashboard_html.py](../../tests/web/test_dashboard_html.py): API レイテンシとレスポンス整合性検証

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/096-implement-pre-aggregated-analytics-engine-and-storage`

1. **アナリティクスモジュール (`src/analytics/`) の新設**:
   - `AnalyticsAggregator`: 全 OKF 論文、5階層サマリー、OTLP トレースログ、WAL を一括バッチ走査し、最新の統計・脅威トレンド（増減率含む）を事前算出。
   - `AnalyticsStorage`: `outputs/analytics/latest_metrics.json`（および永続 DB テーブル）へアトミック書き込み・高速読み出し。
2. **Web ゲートウェイ (`src/web/gateway/handlers.py`) の $O(1)$ 化**:
   - リクエストハンドラ内の重いファイル走査・Regex 処理を全廃。
   - `AnalyticsStorage.load_latest_metrics()` による $O(1)$ メモリマップ / 高速パースへ移行。
3. **定期実行 & CLI 連携**:
   - `python -m analytics.cli aggregate` または `make aggregate_analytics` コマンドの新設。
   - 4x Daily パイプラインおよび Supervisor のバックグラウンドワーカーで自動定期更新。
4. **テスト・品質ゲート検証**:
   - `pytest tests/analytics/`, `pytest tests/web/`, `make format`, `make static_analysis` の全パス。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `src/analytics/` に集計エンジンとストレージが実装され、単体テストが完備されていること。
- [ ] `/api/graph/mesh` のリクエスト処理時にファイル全量走査が発生せず、レイテンシが 1ms 未満に短縮されること。
- [ ] `outputs/analytics/latest_metrics.json` に実測データがアトミックに保存・更新されること。
- [ ] `make check` / `make verify_quality` が 100% PASS すること。
