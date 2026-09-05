---
ID: 169
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] dashboard.html の 3 画面 (Product / System / Supervisor) の index.html への移植統合および Graph 画面の独立維持 (ID: 169)

## 1. 概要 / Summary

ユーザーの要望および統合コンソール包括設計（`DSN-21`）に基づき、現在 `site/dashboard.html` 上に実装されている以下の 3 つの機能タブを、Azure/AWS 調のエンタープライズ統合コンソールである `site/index.html` へ完全移植する：
1. **`http://localhost:8000/dashboard.html?tab=product` (プロダクト分析 & ROI)**
   - Hop Budget 分布ヒストグラム (`hopCanvas`)
   - Edge Ledger (トラフィック) (`edgeLedgerList`)
   - Token Savings & コスト ROI (`walkVsFlatCanvas`, `valTokenRoi`)
   - 急上昇脅威ベクトル Top 5 (`threatVectorsList`, `valSummaryCoverage`)
   - CTI ナレッジグラフ専用画面への案内 CTA バナー
2. **`http://localhost:8000/dashboard.html?tab=system` (システム観測 & パイプライン)**
   - パイプラインステップ進捗バー (`[1] CHUNK -> [2] EXTRACT -> ...`)
   - OBF 分散トレーシングテレメトリ (OTel / OpenInference, Traceparent, LLM/Retriever/Tool spans)
   - Active Loop & サイクルモニター (Intelligence DAG 4x Daily フェーズ進捗)
   - Traversal Matrix (100 Walks live dots & 自己修復メトリクス)
   - Dead-End & プルーニングレジャー (Cyclic Cuts & コンテキストバジェット制約)
   - サービス運用 & SLO/SLA (SM) (バッチSLO, Upstream 429 耐障害性, WAL 同期遅延)
   - データベースパフォーマンス & IOPS (`valDbIops`, `valDbLatency`, `valDbCacheHit`)
   - データベーステーブル & 物理ストレージレジャー一覧 (`databaseTablesTableBody`, SQL クエリ実行結果)
3. **`http://localhost:8000/dashboard.html?tab=supervisor` (プロセス監視 / Supervisor Top)**
   - Arbiter プロセス KPI (PID, 稼働時間, メモリ RSS, 状態)
   - ワーカープール状態 (`default_pool` active/target)
   - IPC 制御チャネル状態
   - アーキテクチャ & レイテンシ (SA) (p95/p99 テールレイテンシ, MTTR, グラフ密度)
   - Live Supervisor Workers Top テーブル (`supervisorWorkersTableBody`, リアルタイム SSE `/api/stream/top` またはポーリング)

また、ユーザー指定により：
- **`http://localhost:8000/dashboard.html?tab=graph`** は `dashboard.html` 側に残し、高負荷キャンバス物理演算に特化した専用ワークスペースとして維持する。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [site/index.html](file:///workspace/arxiv-security-papers/site/index.html):
  - 左サイドバーに `プロダクト分析 & ROI`、`システム観測 & パイプライン`、`プロセス監視 (Supervisor Top)` を追加。
  - メインコンテンツエリアに `productTab`, `systemTab`, `supervisorTab` の HTML セクションを追加。
- [x] [site/app.js](file:///workspace/arxiv-security-papers/site/app.js):
  - タブ切り替え（`switchToTab`）および URL クエリパラメータ（`?tab=product|system|supervisor`）/ ハッシュ（`#/product|#/system|#/supervisor`）の双方向同期。
  - `/api/graph/mesh` からのテレメトリ定周期取得および各パネルへの反映（Hop Histogram, Walk ROI, Traversal Matrix, Database Tables）。
  - `/api/stream/top` を利用したリアルタイム Supervisor Top ワーカーテーブルの更新（SSE 再接続 & 切断クリーンアップ）。
- [x] [site/style.css](file:///workspace/arxiv-security-papers/site/style.css):
  - 移植されたパネル用スタイル（`metric-card`, `pipeline-bar`, `traversal-matrix`, `bar-chart-row`, `graph-cta-banner` 等）を Warm Swiss Enterprise トークンに統合。
- [x] [site/dashboard.html](file:///workspace/arxiv-security-papers/site/dashboard.html):
  - `tab=graph` をデフォルト表示とし、ヘッダーに `index.html` の各タブへのナビゲーションリンクを配置。
- [x] [tests/web/test_enterprise_console_ui.py](file:///workspace/arxiv-security-papers/tests/web/test_enterprise_console_ui.py):
  - `index.html` における 3 大移植タブおよび各コンポーネント、ナビゲーションの存在・動作自動テストを追加。

---

## 3. 実装方針 / Implementation Plan

Target Branch: `feat/169-port-product-system-supervisor-views-to-index-console`

1. **フェーズ1: `site/index.html` への HTML 構造移植**:
   - サイドバーメニューに 3 項目を追加（`#navProduct`, `#navSystem`, `#navSupervisor`）。
   - メインコンテンツエリアに `<section id="productTab">`, `<section id="systemTab">`, `<section id="supervisorTab">` を追加。
2. **フェーズ2: `site/style.css` へのコンポーネントスタイル追加**:
   - `dashboard.html` のパネル・バー・マトリクススタイルを `style.css` に抽出し、Warm Swiss トークン変数で統一。
3. **フェーズ3: `site/app.js` へのロジック移植**:
   - URL パラメータ・ハッシュルーターの拡張。
   - テレメトリ同期関数、Canvas 描画関数、テーブルレンダラー、SSE ストリームリスナーの配備。
4. **フェーズ4: `site/dashboard.html` の連携維持**:
   - `tab=graph` 専用キャンバスとしての安定動作確認。
5. **フェーズ5: 自動テストと品質ゲート検証**:
   - DOM 構造およびルーティングの自動テスト追加。
   - `make check_format`, `make static_analysis`, `pytest tests/web/` の全パス。

---

## 4. 完了条件 / Success Criteria (DoD)

- [x] `http://localhost:8000/?tab=product`（または `index.html?tab=product` / `#/product`）でプロダクト分析画面が表示され、Hop Histogram や ROI 等が描画されること。
- [x] `http://localhost:8000/?tab=system`（または `index.html?tab=system` / `#/system`）でシステム観測画面が表示され、パイプライン進捗、DBレジャー、OBFテレメトリが表示されること。
- [x] `http://localhost:8000/?tab=supervisor`（または `index.html?tab=supervisor` / `#/supervisor`）でプロセス監視テーブルが表示され、リアルタイム SSE / ポーリングで更新されること。
- [x] `http://localhost:8000/dashboard.html?tab=graph` で CTI ナレッジグラフ画面が独立維持され正常動作すること。
- [x] `site/index.html` のサイドバーから各タブへシームレスに遷移でき、ブラウザの URL 履歴が更新されること。
- [x] 外部ライブラリを追加せず（Vanilla JS / CSS）、Zero-XSS アーキテクチャを維持すること。
- [x] `make check_format`, `make static_analysis`, `pytest tests/web/` の全品質ゲートを 100% PASS すること。

