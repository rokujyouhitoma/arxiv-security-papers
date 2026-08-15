# [DSN-01] 基本設計書 (High-Level Design - HLD) - arxiv-security-papers

本ドキュメントは、「`arxiv-security-papers`」プロジェクトにおける全体アーキテクチャ、コンポーネント構成、データフロー、および MCP/ベクトル DB 連携機構を論理レベルで定義する基本設計書です。

---

## 1. システムアーキテクチャ概要

本システムは、外部の学術リポジトリ（arXiv）からセキュリティ分野（`cs.CR`）の最新論文データを収集し、原論文 PDF / 全文 TXT / メタデータ JSON の永続化、OKF形式変換、5層（ソート項番01〜05付き）の完全日本語エグゼクティブサマリーの生成、セマンティックベクトル DB の自動構築、および MCP JSON-RPC 2.0 サーバ機能を提供する非同期バッチ＆AIインターフェース統合システムです。

```mermaid
flowchart TD
    subgraph External [外部データソース]
        A1[arXiv API / cs.CR]
        A2[arXiv RSS / cs.CR]
        A3[arXiv PDF / cs.CR]
    end

    subgraph CoreEngine [コアパイプラインエンジン (src/)]
        B1[1. Fetcher & Fallback]
        B2[2. Deduplication Check]
        B3[3. Parallel PDF Download & pdftotext]
        B4[4. Raw Data Store]
        B5[5. OKF Converter]
        B6[6. 01-05 Summary Generator]
        B7[7. Vector Engine Indexer]
        B8[8. MCP JSON-RPC Server]
    end

    subgraph OutputsStorage ["成果物集約ストレージ (outputs/)"]
        C1["outputs/raw_data/ (JSON, TXT, PDF)"]
        C2["outputs/okf_papers/ (OKF v0.2 MD)"]
        subgraph ExecSummaries ["outputs/executive_summaries/ (01_〜05_)"]
            D1["01_per_run/ (1日4回)"]
            D2["02_daily/ (1日)"]
            D3["03_monthly/ (月次)"]
            D4["04_quarterly/ (四半期)"]
            D5["05_annual/ (通期)"]
        end
        C3["outputs/vector_db/ (Index JSON)"]
        C4["outputs/index.md & log.md"]
    end

    A1 -->|Primary| B1
    A2 -->|Fallback| B1
    B1 --> B2
    B2 --> B3
    A3 -->|Parallel PDF Fetch| B3
    B3 --> B4
    B4 --> C1
    C1 --> B5
    B5 --> C2
    C2 --> B6
    B6 --> D1 & D2 & D3 & D4 & D5
    C2 --> B7
    B7 --> C3
    C3 <--> B8
    B6 --> C4
```

---

## 2. ディレクトリ構造と物理配置方針

```
/workspace/arxiv-security-papers/
├── .agents/                            # AI エージェントルーツ (Skills, Agents, Hooks, MCP Config)
│   └── mcp_config.json                 # MCP サーバ登録設定
├── docs/                               # 管理・要件・設計ドキュメント
│   ├── processes/                      # 管理プロセス (MNG-01-document_ledger.md)
│   ├── requirements/                   # 要件定義 (REQ-01-system_requirements.md)
│   ├── designs/                        # 基本・詳細設計 (DSN-01-high_level_design.md, DSN-02)
│   ├── mcp/                            # MCP/Vector DB 仕様 (MCP-01-mcp_server_specification.md)
│   ├── issues/                         # Issue 台帳 (README.md, closed/)
│   └── README.md                       # Docs マスターインデックス
├── outputs/                            # 成果物集約ストレージ
│   ├── raw_data/                       # 原論文データ (JSON, Abstract, PDF, Full TXT)
│   ├── okf_papers/                     # Google OKF v0.2 形式ドキュメント (Markdown)
│   ├── executive_summaries/            # 01〜05 階層型日本語エグゼクティブサマリー
│   ├── vector_db/                      # セマンティックベクトル検索インデックス
│   ├── index.md                        # 全成果物ナビゲーションインデックス
│   └── log.md                          # パイプラインログ
├── src/                                # パイプラインソースコード
│   ├── __init__.py
│   ├── arxiv_okf_fetcher.py            # データ収集・OKF変換・サマリー生成
│   ├── vector_engine.py                # セマンティック＋BM25ハイブリッド検索エンジン
│   └── mcp_server.py                   # MCP JSON-RPC 2.0 サーバ
├── templates/                          # サマリーおよび OKF レポート用テンプレート
├── tests/                              # pytest 単体テストスイート
│   ├── __init__.py
│   ├── test_fetcher.py
│   └── test_mcp_server.py
├── .gitignore
├── CHANGELOG.md                        # Keep a Changelog 準拠変更履歴
├── Makefile                            # ビルド・タスクランナー
├── config.json                         # システム構成設定
├── processed_papers.json               # 冪等性管理ステートファイル
├── pyproject.toml                      # Poetry / pytest / isort ビルド定義
└── requirements.txt                    # 依存ライブラリ一覧
```
