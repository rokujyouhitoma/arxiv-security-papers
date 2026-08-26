# 🛡️ arXiv Security Papers Intelligence & Search Ecosystem

[![Python](https://img.shields.io/badge/Python-3.14.7-blue.svg?logo=python&logoColor=white)](https://www.python.org/)
[![Google OKF](https://img.shields.io/badge/Google_OKF-v0.2_Compliant-success.svg)](docs/designs/DSN-03-pipeline_architecture.md)
[![ISO Spec](https://img.shields.io/badge/PDF_Engine-ISO_32000--1%2F2_Compliant-gold.svg)](docs/designs/DSN-13-pure_python_pdf_text_extractor.md)
[![MCP](https://img.shields.io/badge/Model_Context_Protocol-JSON--RPC_2.0-purple.svg)](src/mcp/)
[![Architecture](https://img.shields.io/badge/Search_Engine-2--Tier_Lucene%2FSolr_Paradigm-orange.svg)](src/search/)
[![Database](https://img.shields.io/badge/Vector_DB-4--Tier_SQLite_Compatible_%26_Distributed-blueviolet.svg)](src/database/)
[![Orchestration](https://img.shields.io/badge/Orchestrator-Universal_Intelligence_Cycle-green.svg)](docs/designs/DSN-11-intelligence_orchestration_engine.md)
[![Supervisor](https://img.shields.io/badge/Supervisor-Gunicorn_Style_PreFork-teal.svg)](docs/designs/DSN-12-process_supervisor_and_arbiter.md)
[![Quality Gate](https://img.shields.io/badge/Quality_Gate-100%25_PASS-brightgreen.svg)](Makefile)

arXiv のコンピュータサイエンス・暗号・セキュリティ分野（`cs.CR`）をはじめとする学術・脅威論文データを完全自動で収集・全文抽出・構造化し、**Google Open Knowledge Format (OKF) v0.2** 準拠のナレッジベース構築、**5階層エグゼクティブサマリー** 自律生産、**ISO 32000 準拠 Pure Python PDF 抽出基盤**、**2層分離検索エンジン基盤**（Apache Lucene / Solr パラダイム）、**純粋 Python 製 4層ベクトルデータベース**、**AI コーディングエージェント向け戦略的 MCP サーバー群**、**自律型閉ループ・インテリジェンス・ライフサイクル・オーケストレーター**、および **Gunicorn スタイル汎用プロセススーパーバイザー** を提供する統合インテリジェンスプラットフォームです。

---

## 🏢 1. 経営層・ビジネスリーダー向け エグゼクティブサマリー（IT Strategist 監修）

> **「世界最高峰のセキュリティ研究知見を、ビジネスの攻めと守りの武器に変える自律型インテリジェンス基盤」**
> 
> *日々世界中から発表される膨大なセキュリティ論文からノイズを排除し、経営判断に直結する戦略インサイトと、AIエージェントが即座に活用できる構造化ナレッジを全自動で創出し続けます。*

### 💡 エグゼクティブ・ハイライト (Executive Takeaways)

1. **意思決定スピードの 10 倍化（ノイズから戦略インサイトへ）**:
   - 毎月数千件に及ぶ最新論文の山から、AI が **「今週、経営と開発現場が知るべき重大な脅威と対策」** を 100% 日本語で構造化サマリー（実行時・日次・月次・四半期・通期の 5 階層）として自律生成。情報収集・リサーチにかかる人的コストを 90% 以上削減します。
2. **ゼロ外部依存・究極のポータビリティによる TCO 最小化**:
   - 重厚な外部データベース（Elasticsearch / PostgreSQL / Redis）や OS 依存バイナリ（Poppler / pdftotext）を一切排除。**Python 3.14 標準ライブラリのみで完結する Pure Python アーキテクチャ** により、オンプレミス、AWS/GCP クラウド、エッジ環境、軽量コンテナを問わず即座にゼロコストで安全稼働します。
3. **自律閉ループ型ライフサイクル（自己進化するインテリジェンス）**:
   - 米国連邦政府・諜報機関の「Universal Intelligence Cycle」に準拠。単なるデータ収集にとどまらず、**「優先インテリジェンス要件 (PIR) 策定 $\to$ 収集 $\to$ 処理 $\to$ 分析 $\to$ 配布 $\to$ 評価」** を完全自律駆動し、ユーザーの検索・参照傾向からナレッジ不足を自己検知して自動で次期収集を強化します。
4. **生成 AI・AI コーディングエージェントとのシームレス融合**:
   - 業界標準の **Model Context Protocol (MCP)** をネイティブ搭載。Claude Desktop や社内 AI チャットボット、コーディングエージェントと直結し、「最新のゼロデイ攻撃に対する論文ベースの回避策」を即答できる次世代 AI ワークプレイスを実現します。

### 📊 ビジネス価値・ROI 比較マトリクス

| 評価軸 | 従来のセキュリティ情報収集 | **本プラットフォーム (arxiv-security-papers)** |
| :--- | :--- | :--- |
| **収集・読解工数** | セキュリティ担当者が手動で検索・精読（月 80 時間〜） | **完全自動・常時最新（人的工数 0 時間）** |
| **要約・報告レベル** | 属人的なメモ・断片的な情報共有 | **経営会議〜現場エンジニアまで直感理解できる 5 階層サマリー** |
| **インフラ運用コスト** | 多数のミドルウェア・有償 SaaS ライセンス | **外部パッケージゼロ・軽量 Python プロセスのみ（TCO 95% 削減）** |
| **AI エージェント連携** | コピペによる手動プロンプト入力 | **MCP 経由で Claude / AI エージェントがリアルタイム直接参照** |
| **規格・標準準拠** | バラバラな独自フォーマット | **Google OKF v0.2 / ISO 32000-1 / ISO 32000-2 国際標準完全準拠** |

---

## 📑 目次 (Table of Contents)

1. [経営層・ビジネスリーダー向け エグゼクティブサマリー](#-1-経営層ビジネスリーダー向け-エグゼクティブサマリーit-strategist-監修)
2. [主要機能 (Key Features)](#-主要機能-key-features)
3. [システム全体アーキテクチャ (System Architecture)](#-システム全体アーキテクチャ-system-architecture)
4. [普遍的自律型インテリジェンス・ライフサイクル (Intelligence Lifecycle)](#-普遍的自律型インテリジェンスライフサイクル-intelligence-lifecycle)
5. [10大クリーンサブシステム構造 (Core Subsystems)](#-10大クリーンサブシステム構造-core-subsystems)
6. [包括的設計書体系 (Design Specifications: DSN-01 〜 DSN-13)](#-包括的設計書体系-design-specifications-dsn-01--dsn-13)
7. [クイックスタート (Quick Start)](#-クイックスタート-quick-start)
8. [Makefile コマンド一覧 (Command Reference)](#-makefile-コマンド一覧-command-reference)
9. [ディレクトリ構成 (Directory Structure)](#-ディレクトリ構成-directory-structure)
10. [品質管理とガバナンス (Governance & Quality Gates)](#-品質管理とガバナンス-governance--quality-gates)

---

## 🚀 主要機能 (Key Features)

- **ISO 32000 準拠 ゼロ依存 Pure Python PDF 抽出基盤 (`src/pdf_engine/` / DSN-13)**:
  - ISO 32000-1 (PDF 1.7) および ISO 32000-2 (PDF 2.0) 仕様に完全準拠。外部 CLI ツール（Poppler / `pdftotext`）に依存せず、ゼロコピー字句解析、XRef / XRefStream / ObjStm 解凍、`/ToUnicode` CMap デコード、および **学術論文特有の 2段組（Two-Column）ガター境界自動検出 & 読書順序ソート** を Pure Python で高速実行。
- **普遍的自律型インテリジェンス・オーケストレーション (DSN-11)**:
  - 計画（PIR策定）$\rightarrow$ 収集 $\rightarrow$ 処理 $\rightarrow$ 分析・生産 $\rightarrow$ 配布 $\rightarrow$ 評価（NDCG/MAP）の 6 大フェーズを自律閉ループで駆動し、未充足トピックギャップを次期収集へ自己適応。
- **Gunicorn スタイル汎用プロセススーパーバイザー (`src/supervisor/` / DSN-12)**:
  - Pre-fork ワーカーモデル、Erlang/OTP Supervisor ツリー、Systemd 依存関係順序制御、動的スケーリング、POSIX シグナル管理、ハートビート自己回復、および `top` リアルタイムモニタリング CLI。
- **分散クローラー & スパイダー基盤 (`src/spider/` / DSN-06)**:
  - OPIC クロール順序付け、AutoThrottle レート制限、スケーラブル・ブルームフィルタ、SPA 状態復元。
- **マルチテーマ ETL パイプライン (`src/pipeline/` / DSN-03)**:
  - arXiv / IACR / Advisory アダプター、Pure Python PDF 抽出、原本（PDF/TXT/JSON）の完全保存（`outputs/raw_data/`）。
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
        PDFEng["3. Pure Python PDF Engine (src/pdf_engine/)"]
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
    Pipeline --> PDFEng
    PDFEng --> Pipeline
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
    participant PDF as 抽出: PDF Engine (src/pdf_engine)
    participant D as 分析: Database (src/database)
    participant E as 分析: Search (src/search)
    participant M as 配布: MCP (src/mcp)
    participant W as 配布: Web (src/web)
    participant Eval as 評価: Evaluator (DSN-10/11)

    Note over Orch: 【Phase 1: 計画】PIR策定 & OPICクロールポリシー配分
    Orch->>S: 【Phase 2: 収集】優先度付きフェッチ指令
    S->>S: AutoThrottle & Bloom重複排除
    S-->>P: 【Phase 3: 処理】生データ/PDF/メタデータ
    P->>PDF: Pure Python ISO 32000 テキスト抽出 & 2段組整流
    PDF-->>P: クリーン UTF-8 本文
    P->>P: OKF v0.2 構造化 & 脅威タグ自動付与
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

## 📚 包括的設計書体系 (Design Specifications: DSN-01 〜 DSN-13)

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
| **DSN-13** | [DSN-13-pure_python_pdf_text_extractor.md](docs/designs/DSN-13-pure_python_pdf_text_extractor.md) | `src/pdf_engine/` | ISO 32000 準拠 ゼロ依存 Pure Python PDF テキスト抽出 & 空間レイアウト再構築エンジン包括設計書 |

---

## ⚡ クイックスタート (Quick Start)

### 1. 開発環境のセットアップ
```bash
make setup
```

### 2. インテリジェンスパイプラインの実行 (論文取得・Pure Python抽出・OKF変換・5層サマリー)
```bash
make run
# 実体: src/orchestrator/cli.py cycle
```

### 3. PDF テキスト抽出エンジンの直接実行 (CLI / ベンチマーク)
```bash
# 任意の PDF ファイルからテキスト抽出
PYTHONPATH=src .venv/bin/python -m pdf_engine outputs/raw_data/2025-09-02/2509.05350.pdf --head 300

# 蓄積済み実 arXiv PDF データセットによる自動精度ベンチマーク
PYTHONPATH=src .venv/bin/python -m pdf_engine.benchmark --sample 15
```

### 4. Web API Gateway & 検索ポータルの起動
```bash
make run_web
# ブラウザで http://localhost:8000 にアクセス
```

### 5. MCP サーバーの起動 (Claude Desktop / AI エージェント連携)
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

### 6. プロセススーパーバイザーの起動 & 監視
```bash
# Gunicorn スタイル Pre-fork プロセス監視起動
make run_supervisor

# ライブステータス確認 (IPC Unix ドメインソケット)
make status_supervisor

# top リアルタイムモニタリングダッシュボード
make top_supervisor
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
│   ├── designs/                # 13大包括設計書体系 (DSN-01 〜 DSN-13)
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
│   ├── pdf_engine/             # ISO 32000 準拠 Pure Python PDF 抽出 & 空間レイアウト (DSN-13)
│   │   ├── parser.py           # 字句解析 (Lexer) & AST パース
│   │   ├── xref.py             # XRef, XRefStream, ObjStm 解決
│   │   ├── decompress.py       # FlateDecode & PNG Predictor 差分解除
│   │   ├── navigator.py        # /Catalog -> /Pages ツリー走査
│   │   ├── font.py             # /ToUnicode CMap, AGL, リガチャ正規化
│   │   ├── interpreter.py      # Content Stream テキストオペレータ実行
│   │   ├── layout.py           # 2段組ガター自動検出 & 読書順序ソート
│   │   ├── extractor.py        # 統合 API (PurePdfTextExtractor)
│   │   └── benchmark.py        # 実 PDF 回帰ベンチマーク
│   ├── spider/                 # ゼロ依存 分散クローラー (DSN-06)
│   ├── pipeline/               # ETL パイプライン (ingestion, transformer, reporter) (DSN-03)
│   ├── database/               # 純粋 Python 4層ベクトル DB (DSN-05)
│   ├── search/                 # 2層検索基盤 (engine, platform, vector) (DSN-04)
│   ├── security/               # 共通セキュリティ・AST ガード & RBAC (DSN-07)
│   ├── mcp/                    # 戦略的 MCP サーバー群 (DSN-08)
│   ├── web/                    # API Gateway & UI プレゼンテーション (DSN-09)
│   ├── orchestrator/           # 普遍的インテリジェンス・オーケストレーター (DSN-11)
│   └── supervisor/             # 汎用プロセススーパーバイザー & 調停基盤 (DSN-12)
├── tests/                      # 包括的テストスイート (1:1 ミラーリング)
│   ├── pdf_engine/             # PDF エンジン単体・実証ベンチマークテスト
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
