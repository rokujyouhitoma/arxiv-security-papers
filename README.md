# 🛡️ arXiv Security Papers Intelligence & Search Ecosystem

[![Python](https://img.shields.io/badge/Python-3.14.7-blue.svg?logo=python&logoColor=white)](https://www.python.org/)
[![Google OKF](https://img.shields.io/badge/Google_OKF-v0.2_Compliant-success.svg)](docs/designs/DSN-03-pipeline_architecture.md)
[![MCP](https://img.shields.io/badge/Model_Context_Protocol-JSON--RPC_2.0-purple.svg)](src/mcp/)
[![Architecture](https://img.shields.io/badge/Search_Engine-2--Tier_Lucene%2FSolr_Paradigm-orange.svg)](src/search/)
[![Database](https://img.shields.io/badge/Vector_DB-4--Tier_SQLite_Compatible_%26_Distributed-blueviolet.svg)](src/database/)
[![Orchestration](https://img.shields.io/badge/Orchestrator-Universal_Intelligence_Cycle-green.svg)](docs/designs/DSN-11-intelligence_orchestration_engine.md)
[![Supervisor](https://img.shields.io/badge/Supervisor-Gunicorn_Style_PreFork-teal.svg)](docs/designs/DSN-12-process_supervisor_and_arbiter.md)
[![Quality Gate](https://img.shields.io/badge/Quality_Gate-100%25_PASS-brightgreen.svg)](Makefile)

arXiv のコンピュータサイエンス・暗号・セキュリティ分野（`cs.CR`）をはじめとする学術・脅威論文データを完全自動で収集・全文抽出・構造化し、**Google Open Knowledge Format (OKF) v0.2** 準拠のナレッジベース構築、**5階層エグゼクティブサマリー** 自律生産、**2層分離検索エンジン基盤**（Apache Lucene / Solr パラダイム）、**純粋 Python 製 4層ベクトルデータベース**、**AI コーディングエージェント向け戦略的 MCP サーバー群**、**自律型閉ループ・インテリジェンス・ライフサイクル・オーケストレーター**、および **Gunicorn スタイル汎用プロセススーパーバイザー** を提供する統合インテリジェンスプラットフォームです。

---

## 📑 目次 (Table of Contents)

1. [主要機能 (Key Features)](#-主要機能-key-features)
2. [システム全体アーキテクチャ (System Architecture)](#-システム全体アーキテクチャ-system-architecture)
3. [普遍的自律型インテリジェンス・ライフサイクル (Intelligence Lifecycle)](#-普遍的自律型インテリジェンスライフサイクル-intelligence-lifecycle)
4. [9大クリーンサブシステム構造 (Core Subsystems)](#-9大クリーンサブシステム構造-core-subsystems)
5. [包括的設計書体系 (Design Specifications: DSN-01 〜 DSN-12)](#-包括的設計書体系-design-specifications-dsn-01--dsn-12)
6. [クイックスタート (Quick Start)](#-クイックスタート-quick-start)
7. [Makefile コマンド一覧 (Command Reference)](#-makefile-コマンド一覧-command-reference)
8. [ディレクトリ構成 (Directory Structure)](#-ディレクトリ構成-directory-structure)
9. [品質管理とガバナンス (Governance & Quality Gates)](#-品質管理とガバナンス-governance--quality-gates)

---

## 🚀 主要機能 (Key Features)

- **普遍的自律型インテリジェンス・オーケストレーション (DSN-11)**:
  - 計画（PIR策定）$\rightarrow$ 収集 $\rightarrow$ 処理 $\rightarrow$ 分析・生産 $\rightarrow$ 配布 $\rightarrow$ 評価（NDCG/MAP）の 6 大フェーズを自律閉ループで駆動し、未充足トピックギャップを次期収集へ自己適応。
- **Gunicorn スタイル汎用プロセススーパーバイザー (`src/supervisor/` / DSN-12)**:
  - Pre-fork ワーカーモデル、Erlang/OTP Supervisor ツリー、Systemd 依存関係順序制御、動的スケーリング、POSIX シグナル管理、ハートビート自己回復、および `top` リアルタイムモニタリング CLI。
- **分散クローラー & スパイダー基盤 (`src/spider/` / DSN-06)**:
  - OPIC クロール順序付け、AutoThrottle レート制限、スケーラブル・ブルームフィルタ、SPA 状態復元。
- **マルチテーマ ETL パイプライン (`src/pipeline/` / DSN-03)**:
  - arXiv / IACR / Advisory アダプター、`pdftotext` 高品質抽出、原本（PDF/TXT/JSON）の完全保存（`outputs/raw_data/`）。
- **Google OKF v0.2 準拠ナレッジ化 & 5階層サマリー (`src/pipeline/` / DSN-03)**:
  - YAML フロントマター付き OKF ドキュメント（`outputs/okf_papers/`）および MITRE ATT&CK / CWE / STRIDE 脅威タグ自動付与。
  - 完全日本語 5 階層サマリー（`01_per_run` 実行時、`02_daily` 日次、`03_monthly` 月次、`04_quarterly` 四半期、`05_annual` 通期）。
- **ゼロ依存 4層ベクトルデータベース (`src/database/` / DSN-05)**:
  - 4KB SlottedPage, 2Q Buffer Pool, WAL & ARIES 障害回復, B+Tree, LSM-Tree, PAX 列指向, CBO オプティマイザ, 分散 Raft / Saga / 2PC / Consistent Hashing, PEP 249 DB-API 互換ドライバ。
- **2層分離エンタープライズ検索基盤 (`src/search/` / DSN-04)**:
  - コアエンジン層（Lucene パラダイム: BM25, AST クエリ, VByte 圧縮）とプラットフォーム層（Solr パラダイム: ManagedSchema, Elevation, Facet, LRU Cache, Highlighter）の完全分離、および HNSW ベクトル RRF 融合。
- **AI エージェント向け戦略的 MCP サーバー群 (`src/mcp/` / DSN-08)**:
  - 論文インテリジェンス（`papers_server`）、技術動向レーダー（`tech_radar_server`）、脅威防御・パッチ（`threat_defense_server`）、可観測性プロファイラ（`observability_server`）の 4 大 JSON-RPC 2.0 サーバー。
- **WSGI REST API Gateway & UI プレゼンテーション (`src/web/` / DSN-09)**:
  - PEP 3333 準拠のゼロ外部依存 WSGI Gateway と、動的 HTML Markdown プレビュー層。

---

## 🏛 システム全体アーキテクチャ (System Architecture)

```mermaid
graph TD
    subgraph Sources["外部情報ソース"]
        ArXiv["arXiv API / RSS"]
        IACR["IACR ePrint"]
        CVE["JVN / NVD Feed"]
    end

    subgraph OrchestratorHub["Universal Intelligence Orchestrator (DSN-11)"]
        PIR["1. PIR要件ディスパッチャ"]
        DAG["DAG ワークフロー & Saga"]
        Feedback["6. フィードバック & IR評価"]
    end

    subgraph SupervisorHub["Process Supervisor & Arbiter (DSN-12)"]
        Arbiter["Arbiter (Master)"]
        Workers["Pre-fork Workers"]
        Heartbeat["Heartbeat & Self-Heal"]
    end

    subgraph CorePlatform["arxiv-security-papers Platform (src/)"]
        Spider["2. 分散クローラー (src/spider/)"]
        Pipeline["3. ETLパイプライン (src/pipeline/)"]
        Database["4. データベースエンジン (src/database/)"]
        Search["4. 2層検索基盤 (src/search/)"]
        Security["共通セキュリティガード (src/security/)"]
        MCP["5. MCPサーバー群 (src/mcp/)"]
        Web["5. Web Gateway (src/web/)"]
    end

    subgraph Users["利用者 & クライアント"]
        AI["AI エージェント / Claude Desktop"]
        Browser["Web ブラウザ / アナリスト"]
    end

    PIR --> DAG
    DAG --> Spider
    Sources --> Spider
    Spider --> Pipeline
    Pipeline --> Database
    Pipeline --> Search
    Security -. ゼロトラスト防御 .-> CorePlatform
    Database <--> Search
    Search --> MCP
    Database --> MCP
    Search --> Web
    Database --> Web
    MCP <--> AI
    Web <--> Browser
    MCP -. 利用ログ・クエリ .-> Feedback
    Web -. アクセスログ .-> Feedback
    Feedback -- "適応型フィードバック (PIR再調整)" --> PIR
    Arbiter --> Workers
    Heartbeat -. 監視・再起動 .-> Workers
    OrchestratorHub --> SupervisorHub
```

---

## 🔄 普遍的自律型インテリジェンス・ライフサイクル (Intelligence Lifecycle)

```mermaid
sequenceDiagram
    autonumber
    actor Orch as Intelligence Orchestrator (DSN-11)
    participant S as 収集: Spider (src/spider)
    participant P as 処理: Pipeline (src/pipeline)
    participant D as 分析: Database (src/database)
    participant E as 分析: Search (src/search)
    participant M as 配布: MCP (src/mcp)
    participant W as 配布: Web (src/web)
    participant Eval as 評価: Evaluator (DSN-10/11)

    Note over Orch: 【Phase 1: 計画】PIR策定 & OPICクロールポリシー配分
    Orch->>S: 【Phase 2: 収集】優先度付きフェッチ指令
    S->>S: AutoThrottle & Bloom重複排除
    S-->>P: 【Phase 3: 処理】生データ/PDF/メタデータ
    P->>P: PDFテキスト抽出 & OKF v0.2 構造化
    P->>D: 【Phase 4: 分析】SlottedPage & WAL コミット
    P->>E: 転置インデックス & HNSWベクトル更新
    P->>P: 5階層サマリー自律生産 (01〜05)
    Orch->>M: 【Phase 5: 配布】MCP サーバー同期
    Orch->>W: Web Gateway API 公開
    M-->>Eval: クエリテレメトリ
    W-->>Eval: 検索アクセスログ
    Note over Eval: 【Phase 6: 評価】NDCG@K算出 & ナレッジギャップ検知
    Eval-->>Orch: 適応型フィードバック (PIR重み更新)
    Note over Orch: 次期サイクル (Phase 1) へ自律自己進化
```

---

## 📚 包括的設計書体系 (Design Specifications: DSN-01 〜 DSN-12)

| DSN 番号 | 設計書ファイル | 対応パッケージ (`src/`) | 領域 / サブシステム |
| :---: | :--- | :--- | :--- |
| **DSN-01** | [DSN-01-high_level_design.md](docs/designs/DSN-01-high_level_design.md) | システム全体 | 全体高位アーキテクチャ設計書 (HLD) |
| **DSN-02** | [DSN-02-low_level_design.md](docs/designs/DSN-02-low_level_design.md) | システム全体 | 全体低位アーキテクチャ設計書 (LLD / Common Protocols) |
| **DSN-03** | [DSN-03-pipeline_architecture.md](docs/designs/DSN-03-pipeline_architecture.md) | `src/pipeline/` | ETL データパイプライン設計書 (`ingestion`, `transformer`, `reporter`) |
| **DSN-04** | [DSN-04-search_engine_and_platform.md](docs/designs/DSN-04-search_engine_and_platform.md) | `src/search/` | 2層検索エンジン & プラットフォーム設計書 (`engine`, `platform`, `vector`) |
| **DSN-04-01** | [DSN-04-01-hybrid_search_specification.md](docs/designs/DSN-04-01-hybrid_search_specification.md) | `src/search/` | ハイブリッド検索 5手法フュージョン詳細仕様書 |
| **DSN-05** | [DSN-05-database_engine_architecture.md](docs/designs/DSN-05-database_engine_architecture.md) | `src/database/` | ゼロ依存 4層ベクトルデータベース & 分散合意設計書 |
| **DSN-06** | [DSN-06-distributed_spider_and_crawler.md](docs/designs/DSN-06-distributed_spider_and_crawler.md) | `src/spider/` | ゼロ外部依存 分散 Web クローラー & スパイダー基盤設計書 |
| **DSN-07** | [DSN-07-security_guard_and_rbac.md](docs/designs/DSN-07-security_guard_and_rbac.md) | `src/security/` | 共通セキュリティ基盤・AST ガード & RBAC エンジン設計書 |
| **DSN-08** | [DSN-08-mcp_strategic_ecosystem.md](docs/designs/DSN-08-mcp_strategic_ecosystem.md) | `src/mcp/` | Model Context Protocol (MCP) 戦略的エコシステム設計書 |
| **DSN-09** | [DSN-09-web_gateway_and_presentation.md](docs/designs/DSN-09-web_gateway_and_presentation.md) | `src/web/` | API Gateway & UI プレゼンテーション設計書 (`gateway`, `presentation`) |
| **DSN-10** | [DSN-10-observability_and_eval_framework.md](docs/designs/DSN-10-observability_and_eval_framework.md) | 横断的基盤 | 可観測性 (Observability) & 情報検索評価 (IR Eval) 設計書 |
| **DSN-11** | [DSN-11-intelligence_orchestration_engine.md](docs/designs/DSN-11-intelligence_orchestration_engine.md) | `src/orchestrator/` | 普遍的自律型インテリジェンス・ライフサイクル・オーケストレーション包括設計書 |
| **DSN-12** | [DSN-12-process_supervisor_and_arbiter.md](docs/designs/DSN-12-process_supervisor_and_arbiter.md) | `src/supervisor/` | 汎用プロセススーパーバイザー & 調停基盤設計書 |

---

## ⚡ クイックスタート (Quick Start)

### 1. 開発環境のセットアップ
```bash
make setup
```

### 2. インテリジェンスパイプラインの実行 (論文取得・OKF変換・5層サマリー)
```bash
make run
# 実体: src/orchestrator/cli.py cycle
```

### 3. Web API Gateway & 検索ポータルの起動
```bash
make run_web
# ブラウザで http://localhost:8000 にアクセス
```

### 4. MCP サーバーの起動 (Claude Desktop / AI エージェント連携)
```bash
# 論文インテリジェンス MCP サーバー
make run_mcp_server

# 可観測性・プロファイリング特化 MCP サーバー
make run_observability_mcp

# 技術動向レーダー MCP サーバー
make run_tech_radar_mcp

# 脅威防御・パッチ MCP サーバー
make run_threat_defense_mcp
```

### 5. プロセススーパーバイザーの起動 & 監視
```bash
# Gunicorn スタイル Pre-fork プロセス監視起動
make run_supervisor

# ライブステータス確認 (IPC Unix ドメインソケット)
make status_supervisor

# top リアルタイムモニタリングダッシュボード
make top_supervisor
```

### 6. インテリジェンス・オーケストレーターの直接実行
```bash
# 1回限りの 6フェーズ自律サイクル
make orchestrate

# 継続デーモンモード
make orchestrate_daemon
```

---

## 🛠 Makefile コマンド一覧 (Command Reference)

```bash
## セットアップ & 品質ゲート
make setup              ## 仮想環境の構築と依存パッケージのインストール
make format             ## ruff / isort / black によるコードフォーマット
make check_format       ## フォーマット検査 (変更なし)
make static_analysis    ## radon, xenon, mypy --strict 静的解析
make test               ## pytest テストスイート実行 (fast)
make test_slow          ## slow マークテスト実行 (E2E シナリオ)
make check              ## format, static_analysis, test を一括実行 (品質ゲート)
make verify_quality     ## format, static_analysis, test, build_js を一括実行 (厳格品質ゲート)

## パイプライン & 検索
make run                ## Universal Intelligence Orchestrator 6フェーズ自律サイクル実行
make pipeline           ## ETL パイプライン (arXiv 論文取得・OKF変換・サマリー生成) を直接実行
make build_vector_db    ## セマンティックベクトルインデックス構築 / 再構築
make rag_query Q="..."  ## セマンティック RAG 検索クエリ実行
make eval_search        ## 検索品質ベンチマーク (Precision@K, Recall@K, MAP, MRR, NDCG)

## Web & MCP サーバー
make run_web            ## WSGI Web サーバー & REST API 起動 (http://localhost:8000)
make run_mcp_server           ## 論文インテリジェンス MCP サーバー起動
make run_observability_mcp    ## 可観測性プロファイラ MCP サーバー起動
make run_tech_radar_mcp       ## 技術動向レーダー MCP サーバー起動
make run_threat_defense_mcp   ## 脅威防御・パッチ MCP サーバー起動

## プロセススーパーバイザー
make run_supervisor     ## Gunicorn スタイル Pre-fork プロセス監視起動
make status_supervisor  ## ライブプロセスステータス確認
make top_supervisor     ## top リアルタイムモニタリングダッシュボード

## オーケストレーター
make orchestrate        ## 普遍的インテリジェンス・オーケストレーター 6フェーズサイクル実行
make orchestrate_daemon ## オーケストレーター 継続デーモンモード起動

## ビルド
make build_js           ## Google Closure Compiler による JS バンドルビルド
```

---

## 📁 ディレクトリ構成 (Directory Structure)

```text
.
├── .agents/                    # 13エージェント規約 (AGENTS.md) & スキル群
├── docs/
│   ├── designs/                # 12大包括設計書体系 (DSN-01 〜 DSN-12)
│   ├── issues/                 # Issue 台帳 & クローズ済み履歴 (closed/ — 001〜070)
│   ├── mcp/                    # MCP サーバ仕様書 (MCP-01)
│   ├── processes/              # 文書管理台帳 (MNG-01)
│   └── requirements/           # 要件定義書 (REQ-01〜REQ-02)
├── outputs/
│   ├── raw_data/               # 原本データ (YYYY-MM-DD/<id>.pdf, .txt, _meta.json)
│   ├── okf_papers/             # Google OKF v0.2 Markdown (YYYY-MM-DD/<id>.md)
│   ├── executive_summaries/    # 5階層サマリー (01_per_run 〜 05_annual)
│   ├── vector_db/              # 検索エンジンインデックス (index.json)
│   ├── database/               # データベースエンジン永続化データ
│   ├── evaluations/            # IR 評価結果 & ベンチマークレポート
│   ├── logs/                   # パイプライン実行ログ
│   ├── supervisor/             # プロセススーパーバイザー状態・ソケット
│   ├── index.md                # OKF 論文統合インデックス
│   └── log.md                  # パイプライン実行履歴ログ
├── src/
│   ├── spider/                 # ゼロ依存 分散クローラー (DSN-06)
│   ├── pipeline/               # ETL パイプライン (ingestion, transformer, reporter) (DSN-03)
│   ├── database/               # 純粋 Python 4層ベクトル DB (DSN-05)
│   ├── search/                 # 2層検索基盤 (engine, platform, vector) (DSN-04)
│   ├── security/               # 共通セキュリティ・AST ガード & RBAC (DSN-07)
│   ├── mcp/                    # 戦略的 MCP サーバー群 (DSN-08)
│   ├── web/                    # API Gateway & UI プレゼンテーション (DSN-09)
│   ├── orchestrator/           # 普遍的インテリジェンス・オーケストレーター (DSN-11)
│   │   ├── pir/                # Priority Intelligence Requirements 管理
│   │   ├── harvest/            # 収集フェーズ制御
│   │   ├── processing/         # 処理フェーズ制御
│   │   ├── analysis/           # 分析フェーズ制御
│   │   ├── dissemination/      # 配布フェーズ制御
│   │   ├── feedback/           # フィードバック & IR 評価
│   │   ├── workflow/           # DAG ワークフロー & Saga
│   │   ├── engine.py           # オーケストレーションエンジン本体
│   │   └── cli.py              # CLI エントリポイント (cycle / daemon)
│   └── supervisor/             # 汎用プロセススーパーバイザー & 調停基盤 (DSN-12)
│       ├── workers/            # ワーカー種別 (Sync / Gthread / Async)
│       ├── arbiter.py          # マスタープロセス調停器
│       ├── control.py          # シグナル & IPC 制御
│       ├── heartbeat.py        # ハートビート & 自己回復
│       ├── top.py              # リアルタイムモニタリング
│       └── cli.py              # CLI エントリポイント (start / status / top)
├── tests/                      # 包括的テストスイート (1:1 ミラーリング)
│   ├── spider/                 # クローラーテスト
│   ├── pipeline/               # パイプラインテスト
│   ├── database/               # データベーステスト (scenarios/ 含む)
│   ├── search/                 # 2層検索エンジンテスト
│   ├── security/               # セキュリティ・AST テスト
│   ├── mcp/                    # MCP サーバーテスト
│   ├── web/                    # Web Gateway テスト
│   ├── orchestrator/           # オーケストレーターテスト
│   └── supervisor/             # スーパーバイザーテスト
├── config/                     # パイプライン設定ファイル群
├── templates/                  # サマリーレンダリングテンプレート
├── site/                       # Web UI 静的ファイル (HTML / CSS / JS)
├── tools/                      # 開発補助ツール (Closure Compiler 等)
├── Makefile                    # ビルド & 運用自動化ターゲット
├── pyproject.toml              # プロジェクトメタデータ & ツール設定
└── README.md                   # 本ドキュメント
```

---

## 🔒 品質管理とガバナンス (Governance & Quality Gates)

本プロジェクトは **13専門エージェント・マルチエージェントガバナンス ([AGENTS.md](.agents/AGENTS.md))** の下、厳格な品質管理基準（DoD）を適用して開発・運用されています。

1. **トリプル品質ゲート (Triple Quality Gates)**:
   - 全コード変更は `make check` (`make format`, `make static_analysis`, `make test`) を 100% 通過する必要があります。
2. **Issue 駆動開発**:
   - すべての機能追加・改善は [docs/issues/](docs/issues/) の Issue 台帳で管理され、DoD 達成後に [docs/issues/closed/](docs/issues/closed/) へアーカイブされます（Issue 001〜070 全70件完了）。
3. **相対パス厳守**:
   - リポジトリ内の全 Markdown ドキュメントにおいて実効絶対パスリンクは完全 0 件に保たれ、高い移植性と完全なトレーサビリティが保証されています。

---

## 📄 ライセンス (License)

This project is licensed under the Apache 2.0 License - see the LICENSE file for details.
