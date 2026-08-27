# arxiv-security-papers ドキュメントポータル (Docs Portal)

本ポータルは、「`arxiv-security-papers`」プロジェクトに関するすべての仕様書、設計書、管理プロセス、および Issue 履歴を提供する総合ナビゲーションインデックスです。
ドキュメントの管理・分類方針は [[MNG-01] 文書管理台帳](processes/MNG-01-document_ledger.md) に準拠しています。

---

## 📚 ドキュメント構成一覧 (Document Catalog)

### 1. 管理・プロセス (Management & Governance)
- 📋 **[[MNG-01] 文書管理・ドキュメント台帳](processes/MNG-01-document_ledger.md)**
  - ドキュメント管理方針、分類プレフィックス（MNG, REQ, DSN, MCP, ISS）、採番ルール、および設計ドキュメントの分掌方針。

### 2. 要件定義 ＆ 機能一覧 (Requirements & Features)
- 📝 **[[REQ-01] システム要求事項定義書 (WHAT / WHY)](requirements/REQ-01-system_requirements.md)**
  - システムの背景・事業目的 (WHY) および達成すべき機能・非機能要求事項 (WHAT)。
- 📋 **[[REQ-02] 主要機能一覧 (Master Feature List)](requirements/REQ-02-feature_list.md)**
  - 全主要機能 (F-01〜F-08) のマスター一覧、設計ページリンク、およびモジュール関係性マップ。

### 3. 設計仕様 (Architecture & Feature Designs)

#### 上位・横断設計
- 🏗️ **[[DSN-01] 全体高位アーキテクチャ設計書 (HLD)](designs/DSN-01-high_level_design.md)**
  - システム全体アーキテクチャ、7大サブシステム (spider / pipeline / database / search / security / mcp / web / orchestrator / supervisor)、要求事項追跡マトリクス (RTM)。
- ⚙️ **[[DSN-02] 全体低位アーキテクチャ設計書 (LLD / Common Protocols)](designs/DSN-02-low_level_design.md)**
  - Python モジュール仕様、関数シグネチャ、データ構造、共通プロトコル、ツール設定。

#### サブシステム個別設計 (1:1 パッケージ対応)
- 📦 **[[DSN-03] ETL データパイプライン設計書](designs/DSN-03-pipeline_architecture.md)**
  - `src/pipeline/` — arXiv / IACR / Advisory アダプター、pdftotext 高品質抽出、原本保存 (raw_data/)、Google OKF v0.2 変換、5階層サマリー自律生産。
- 📊 **[[DSN-04] 2層検索エンジン ＆ プラットフォーム設計書](designs/DSN-04-search_engine_and_platform.md)**
  - `src/search/` — Lucene パラダイム BM25 コアエンジン層 (engine/)、Solr パラダイム ManagedSchema プラットフォーム層 (platform/)、HNSW ベクトル RRF 融合 (vector/)。
  - 補足仕様: **[[DSN-04-01] ハイブリッド検索詳細仕様](designs/DSN-04-01-hybrid_search_specification.md)** — 5手法フュージョン検索アルゴリズム詳細設計。
- 🧠 **[[DSN-05] ゼロ依存 4層ベクトルデータベース ＆ 分散合意設計書](designs/DSN-05-database_engine_architecture.md)**
  - `src/database/` — 4KB SlottedPage、2Q Buffer Pool、WAL & ARIES 障害回復、B+Tree、LSM-Tree、PAX 列指向、CBO オプティマイザ、分散 Raft / Saga / 2PC / Consistent Hashing、PEP 249 DB-API 互換ドライバ。
- 🕷️ **[[DSN-06] ゼロ外部依存 分散 Web クローラー ＆ スパイダー基盤設計書](designs/DSN-06-distributed_spider_and_crawler.md)**
  - `src/spider/` — OPIC クロール順序付け、AutoThrottle レート制限、スケーラブル・ブルームフィルタ、SPA 状態復元。
- 🔒 **[[DSN-07] 共通セキュリティ基盤・AST ガード ＆ RBAC エンジン設計書](designs/DSN-07-security_guard_and_rbac.md)**
  - `src/security/` — ゼロトラスト AST セキュリティサンドボックス、RBAC エンジン、パス走査検証防御。
- 🔌 **[[DSN-08] MCP 戦略的エコシステム設計書](designs/DSN-08-mcp_strategic_ecosystem.md)**
  - `src/mcp/` — 論文インテリジェンス (papers_server)、技術動向レーダー (tech_radar_server)、脅威防御・パッチ (threat_defense_server)、可観測性プロファイラ (observability_server) の 4 大 JSON-RPC 2.0 サーバー。
- 🌐 **[[DSN-09] API Gateway ＆ UI プレゼンテーション設計書](designs/DSN-09-web_gateway_and_presentation.md)**
  - `src/web/` — PEP 3333 準拠 WSGI Gateway、REST API、Glassmorphism Web 検索 UI、動的 HTML Markdown プレビュー層。
- 📈 **[[DSN-10] 可観測性 (Observability) ＆ 情報検索評価 (IR Eval) 設計書](designs/DSN-10-observability_and_eval_framework.md)**
  - 横断的基盤 — リアルタイムクエリプロファイラ、NDCG@K / MRR@K / MAP 自動ベンチマーク、メトリクスエクスポータ。
- 🎯 **[[DSN-11] 普遍的自律型インテリジェンス・ライフサイクル・オーケストレーション包括設計書](designs/DSN-11-intelligence_orchestration_engine.md)**
  - `src/orchestrator/` — 計画 (PIR 策定) → 収集 → 処理 → 分析・生産 → 配布 → 評価 (NDCG/MAP) の 6 大フェーズ閉ループ自律駆動、ナレッジギャップ自己適応。
- ⚙️ **[[DSN-12] 汎用プロセススーパーバイザー ＆ 調停基盤設計書](designs/DSN-12-process_supervisor_and_arbiter.md)**
  - `src/supervisor/` — Gunicorn スタイル Pre-fork ワーカーモデル、Erlang/OTP Supervisor ツリー、Systemd 依存関係順序制御、動的スケーリング、自己回復・ハートビート監視。
- 🚀 **[[DSN-16] 次世代セキュリティ・ナレッジプラットフォーム包括設計提言書](designs/DSN-16-nextgen_security_knowledge_platform_proposal.md)**
  - 多段階 LLM 要約、MITRE ATT&CK / TTPs マッピング、Caldera プレイブック生成、MCP / マルチチャネル配信、プロンプトインジェクション防護、CI/CD ゼロトラスト分離。

### 4. ユーザーマニュアル ＆ AI エージェント連携 (Manuals & AI Integration)
- 📖 **[[USR-01] ユーザーマニュアル ＆ AI コーディングエージェント連携ガイド](manuals/USR-01-user_manual.md)**
  - クイックスタート手順、論文収集コマンド（ETL / バックフィル / 定期自動実行）、4 大 MCP サーバー連携・ツール利用法、Web ポータル起動、トラブルシューティング。
- 🔌 **[[MCP-01] MCP サーバ ＆ ベクトル DB 仕様書](mcp/MCP-01-mcp_server_specification.md)**
  - MCP JSON-RPC 2.0 サーバの 4 大ツール仕様、ベクトル DB スキーマ、およびセキュリティサンドボックス検証規則。

### 5. Issue 台帳 ＆ 履歴 (Issues & Task Ledger)
- 🎯 **[[ISS-00] Issue 台帳 (Issue Ledger)](issues/README.md)**
  - 新機能・タスク・障害の追跡台帳および完了済み Issue アーカイブ (`docs/issues/closed/` — Issue 001〜070 全70件完了)。

