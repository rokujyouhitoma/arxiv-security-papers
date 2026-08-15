# arxiv-security-papers ドキュメントポータル (Docs Portal)

本ポータルは、「`arxiv-security-papers`」プロジェクトに関するすべての仕様書、設計書、管理プロセス、および Issue 履歴を提供する総合ナビゲーションインデックスです。
ドキュメントの管理・分類方針は [[MNG-01] 文書管理台帳](processes/MNG-01-document_ledger.md) に準拠しています。

---

## 📚 ドキュメント構成一覧 (Document Catalog)

### 1. 管理・プロセス (Management & Governance)
- 📋 **[[MNG-01] 文書管理・ドキュメント台帳](processes/MNG-01-document_ledger.md)**
  - ドキュメント管理方針、分類プレフィックス（MNG, REQ, DSN, MCP, ISS）、採番ルール、および設計ドキュメントの分掌方針。

### 2. 要件定義 (Requirements)
- 📝 **[[REQ-01] システム要件定義書](requirements/REQ-01-system_requirements.md)**
  - arXiv `cs.CR` フェッチ (160日さかのぼり)、Google OKF v0.2 変換、5階層日本語サマリー、MCP/ベクトルDBの機能・非機能要件。

### 3. 設計仕様 (Architecture & Technical Design)
- 🏗️ **[[DSN-01] 基本設計書 (HLD)](designs/DSN-01-high_level_design.md)**
  - システム論理アーキテクチャ、データフロー（Mermaid図）、ディレクトリ構造、および各コンポーネントの全体構成。
- ⚙️ **[[DSN-02] 詳細設計書 (LLD)](designs/DSN-02-low_level_design.md)**
  - パイプライン (`src/arxiv_okf_fetcher.py`)、ベクトルエンジン (`src/vector_engine.py`)、および MCP サーバ (`src/mcp_server.py`) の関数仕様・アルゴリズム。

### 4. AI エージェント & MCP 連携 (AI & MCP Specification)
- 🔌 **[[MCP-01] MCP サーバ ＆ ベクトル DB 仕様書](mcp/MCP-01-mcp_server_specification.md)**
  - MCP JSON-RPC 2.0 サーバの 4 大ツール仕様、ベクトル DB スキーマ、およびセキュリティサンドボックス検証規則。

### 5. Issue 台帳 & 履歴 (Issues & Task Ledger)
- 🎯 **[[ISS-00] Issue 台帳 (Issue Ledger)](issues/README.md)**
  - 新機能・タスク・障害の追跡台帳および完了済み Issue アーカイブ (`docs/issues/closed/`)。
