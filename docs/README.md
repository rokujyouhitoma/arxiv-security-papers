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
- 🏗️ **[[DSN-01] 基本設計書 (HLD)](designs/DSN-01-high_level_design.md)**
  - システム全体アーキテクチャ、4大ピラー、および要求事項追跡マトリクス (RTM)。
- ⚙️ **[[DSN-02] 詳細設計書 (LLD)](designs/DSN-02-low_level_design.md)**
  - Python/JS モジュール仕様、関数シグネチャ、データ構造、ツール設定。
- 📦 **[[DSN-03] 論文収集 ＆ OKF v0.2 変換設計](designs/DSN-03-paper_collector_and_okf_converter.md)**
  - F-01 (arXiv収集/PDF抽出/原本保存) および F-02 (Google OKF v0.2 変換) の個別機能設計。
- 📊 **[[DSN-04] 5階層エグゼクティブサマリー設計](designs/DSN-04-five_tier_executive_summaries.md)**
  - F-03 (01_per_run〜05_annual 5階層サマリー/完全日本語化/表形式/Mermaid) の個別機能設計。
- 🧠 **[[DSN-05] 5手法統合マルチエンジン検索設計](designs/DSN-05-multi_engine_hybrid_search.md)**
  - F-04 (Vector, BM25, Inverted, FM-Index, Recency 5手法フュージョン検索) の個別機能設計。
- 🔌 **[[DSN-06] MCP サーバ設計](designs/DSN-06-mcp_server_and_ai_integration.md)**
  - F-05 (MCP JSON-RPC 2.0 4大ツール/パス境界セキュリティガード) の個別機能設計。
- 🎨 **[[DSN-07] Web ポータル ＆ Markdown Compiler 設計](designs/DSN-07-web_portal_and_markdown_compiler.md)**
  - F-06 (Web UI), F-07 (Markdown Compiler Engine), F-08 (Closure Compiler) の個別機能設計。
- 🔍 **[[DSN-08] Lucene / Solr モジュラー検索アーキテクチャ設計](designs/DSN-08-lucene-solr-modular-architecture.md)**
  - 分離型トークナイザ/CharFilter、DocValues、PostingsList、ManagedSchema の詳細設計。
- 📈 **[[DSN-09] 可観測性 ＆ パフォーマンスプロファイリング設計](designs/DSN-09-observability-and-performance-profiling.md)**
  - リアルタイムクエリプロファイラ、メモリフットプリント追跡、メトリクスエクスポータ設計。
- 🎯 **[[DSN-10] 検索エンジン評価フレームワーク設計](designs/DSN-10-search-engine-evaluation-framework.md)**
  - NDCG@K, MRR@K, MAP, Precision/Recall 自動ベンチマークスイート設計。
- 🛡️ **[[DSN-11] リポジトリセキュリティ ＆ 脅威防御設計](designs/DSN-11-repository-security-and-threat-defense.md)**
  - AST セキュリティサンドボックス、RBAC エンジン、パス走査検証防御設計。
- 🌐 **[[DSN-12] MCP 戦略的エコシステム拡張設計](designs/DSN-12-mcp-strategic-ecosystem-expansion.md)**
  - 観測性・Tech Radar・脅威防御 MCP サーバー群およびセキュリティ堅牢化設計。
- ⚡ **[[DSN-13] SQLite Vector 互換アーキテクチャ設計](designs/DSN-13-sqlite-vector-architecture.md)**
  - PEP 249 DB-API 2.0、VFS、Pager、4KB Paged B+Tree、VDBE バイトコードエンジン設計。
- 🏛️ **[[DSN-14] 次世代データベースエンジン 包括的アーキテクチャ設計](designs/DSN-14-database_engine_architecture.md)**
  - Slotted Page、ディスク永続 WAL & ARIES リカバリ、MVCC / SS2PL、CoW / LMDB ゼロコピー、LSM-Tree & Bloom フィルタ、分散協調・合意（Raft/Paxos/PBFT）、厳格クォーラム & CRDT、2PC & Saga パターン。

### 4. AI エージェント & MCP 連携 (AI & MCP Specification)
- 🔌 **[[MCP-01] MCP サーバ ＆ ベクトル DB 仕様書](mcp/MCP-01-mcp_server_specification.md)**
  - MCP JSON-RPC 2.0 サーバの 4 大ツール仕様、ベクトル DB スキーマ、およびセキュリティサンドボックス検証規則。

### 5. Issue 台帳 & 履歴 (Issues & Task Ledger)
- 🎯 **[[ISS-00] Issue 台帳 (Issue Ledger)](issues/README.md)**
  - 新機能・タスク・障害の追跡台帳および完了済み Issue アーカイブ (`docs/issues/closed/`)。
