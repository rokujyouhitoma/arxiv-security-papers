# 基本設計書 (High-Level Design - HLD)

## 1. システムアーキテクチャ概要

本システムは、外部の学術リポジトリ（arXiv）からセキュリティ分野の最新論文データを収集し、原論文 PDF / 全文 TXT / メタデータ JSON の永続化、OKF形式変換、7層（項番01〜07付き）の日本語エグゼクティブサマリーの生成を行い、全成果物を `outputs/` に集約・管理する非同期バッチ処理システムです。

```mermaid
flowchart TD
    subgraph External [外部データソース]
        A1[arXiv API / cs.CR]
        A2[arXiv RSS / cs.CR]
        A3[arXiv PDF / cs.CR]
    end

    subgraph CoreEngine [コアパイプラインエンジン (arxiv_okf_fetcher.py)]
        B1[1. Fetcher & Fallback]
        B2[2. Deduplication Check]
        B3[3. Parallel PDF Download & pdftotext Extraction]
        B4[4. Raw Data Store (JSON/TXT/PDF)]
        B5[5. OKF Converter]
        B6[6. 01-07 Summary Generator]
        B7[7. Index & Log Updater]
    end

    subgraph OutputsStorage ["成果物集約ストレージ (outputs/)"]
        C1["outputs/raw_data/<br/>(JSON, Abstract TXT, PDF, Full TXT)"]
        C2["outputs/okf_papers/<br/>(OKF v0.2 Markdown)"]
        subgraph ExecSummaries ["outputs/executive_summaries/ (ソート済み01-07層)"]
            D1["01_per_run/ (1日4回)"]
            D2["02_daily/ (1日)"]
            D3["03_weekly/ (7日)"]
            D4["04_monthly/ (30日)"]
            D5["05_quarterly/ (90日)"]
            D6["06_semi_annual/ (180日)"]
            D7["07_annual/ (365日)"]
        end
        C3["outputs/index.md & log.md<br/>(OKFカタログ & ログ)"]
    end

    A1 -->|Primary| B1
    A2 -->|Fallback| B1
    B1 --> B2
    B2 -->|新規論文| B3
    A3 -->|Parallel PDF Fetch| B3
    B3 --> B4
    B4 -->|保存| C1
    C1 -->|入力| B5
    B5 -->|生成| C2
    C2 -->|入力| B6
    B6 -->|生成| D1
    B6 -->|生成| D2
    B6 -->|生成| D3
    B6 -->|生成| D4
    B6 -->|生成| D5
    B6 -->|生成| D6
    B6 -->|生成| D7
    B6 --> B7
    B7 -->|更新| C3
```

---

## 2. ディレクトリ構造と層別設計方針

全ての成果物は `outputs/` ディレクトリ配下に集約・集積され、管理されます。

```
/workspace/arxiv-security-papers/
├── docs/                               # アーキテクチャドキュメント (要件書・HLD・LLD)
├── outputs/                            # 【全成果物集約ディレクトリ】
│   ├── raw_data/                       # 原論文データ (JSON, Abstract, PDF, Full TXT)
│   │   └── YYYY-MM-DD/
│   │       ├── <clean_id>_meta.json    # メタデータ JSON
│   │       ├── <clean_id>_raw_abstract.txt # 原本アブストラクト TXT
│   │       ├── <clean_id>.pdf          # ダウンロードした原論文 PDF
│   │       └── <clean_id>.txt          # pdftotext により抽出した全文 TXT
│   ├── okf_papers/                     # Google OKF v0.2 形式ドキュメント (Markdown)
│   ├── executive_summaries/            # 7層の項番付き日本語エグゼクティブサマリー
│   │   ├── 01_per_run/                 # 1. 取得時ごとサマリー (1日4回)
│   │   ├── 02_daily/                   # 2. 日次統合サマリー (1日)
│   │   ├── 03_weekly/                  # 3. 週次サマリー (過去7日間)
│   │   ├── 04_monthly/                 # 4. 月次サマリー (過去30日間)
│   │   ├── 05_quarterly/               # 5. 四半期サマリー (過去90日間)
│   │   ├── 06_semi_annual/             # 6. 半期サマリー (過去180日間)
│   │   └── 07_annual/                  # 7. 通期サマリー (過去365日間)
│   ├── index.md                        # 全成果物へのナビゲーションを提供する OKF Root Index
│   └── log.md                          # 実行ログ
├── processed_papers.json               # 処理済み論文の冪等性保持状態
├── config.json                         # システム構成設定ファイル
└── arxiv_okf_fetcher.py                # コア処理実行スクリプト
```
