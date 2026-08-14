# 要求・要件定義書 (Requirements Specification)

## 1. プロジェクト概要
本プロジェクトは、学術論文リポジトリ `arxiv.org` のコンピュータサイエンス・暗号・セキュリティ分野（`cs.CR`）から1日4回自動で最新論文を取得し、Googleの提唱するナレッジ標準規格 **Google OKF (Open Knowledge Format) v0.2** に準拠したナレッジドキュメントに加工するとともに、4つのレベル（取得時ごと・日次・週次・月次）で独立管理されたエグゼクティブサマリーを自動生成・提供するパイプラインシステムを構築するものです。

---

## 2. 機能要件 (Functional Requirements)

### FR-01: arXiv セキュリティ論文のデータ収集および原本 (Raw) 保存 (160日間さかのぼり取得)
- **内容**: arXiv API (`cs.CR` カテゴリ) より過去160日間に遡って全セキュリティ論文をフェッチし、以下の原本データを個別に保存すること。
  1. メタデータ JSON (`<clean_id>_meta.json`)
  2. 原本 Abstract テキスト (`<clean_id>_raw_abstract.txt`)
  3. **原論文 PDF ファイル (`<clean_id>.pdf`)**: arXiv より直接ダウンロード
  4. **抽出本文テキスト (`<clean_id>.txt`)**: `pdftotext` によりPDFから全本文テキストを自動抽出
- **保存先**: `outputs/raw_data/YYYY-MM-DD/` (過去160日間の日付フォルダ)



- **目的**: データソースの原本性を担保し、後続処理での再変換や検証を可能にする。

### FR-02: Google OKF v0.2 形式への変換・フォーマット生成
- **内容**: 保存された `outputs/raw_data/` のファイルから、Google OKF (Open Knowledge Format) v0.2 仕様に準拠した YAML フロントマター付き Markdown ドキュメントを作成すること。
- **仕様要件**:
  - `type`: `"security-paper"`
  - `title`: 論文タイトル
  - `description`: 構造化エグゼクティブサマリーの1文要約
  - `resource`: arXiv論文詳細ページURL
  - `tags`: カテゴリタグおよび種別タグ
  - `timestamp`: ISO 8601 形式の生成タイムスタンプ
  - `provenance`: 取得元 (`arxiv.org`)、原本JSON相対パス、公開日時、著者一覧
  - `trust`: 認証署名/アテストステーション情報
- **保存先**: `outputs/okf_papers/YYYY-MM-DD/<clean_id>.md`

### FR-03: 7層のエグゼクティブサマリー独立生成・管理 (01_〜07_ 項番付きソート・表形式・完全日本語化対応)
それぞれのサマリー層は `outputs/executive_summaries/` 配下の項番（01〜07）を冠したソート可能な独立ディレクトリで個別に管理されること。サマリー内の文章および論文一覧（マークダウン表形式）は **完全に日本語化 (100% Japanese)** されていること。

1. **取得時ごとサマリー (01_per_run)**:
   - 1日4回（6時間ごと）のバッチ取得の都度、当該バッチで処理された論文に対する日本語表形式サマリーを作成する。
   - 保存先: `outputs/executive_summaries/01_per_run/YYYY-MM-DD/run_HHMM.md`
2. **一日分サマリー (02_daily)**:
   - 1日に1回、その日に収集された全論文を統合した日本語表形式の日次サマリーを作成・更新する。
   - 保存先: `outputs/executive_summaries/02_daily/YYYY-MM-DD.md`
3. **一週間分サマリー (03_weekly)**:
   - 1日に1回、過去7日間に収集された論文群を俯瞰・集計した日本語表形式の週次サマリーを作成・更新する。
   - 保存先: `outputs/executive_summaries/03_weekly/weekly_YYYY-MM-DD.md`
4. **一か月分サマリー (04_monthly)**:
   - 1日に1回、過去30日間に収集された論文群を集計した日本語表形式の月次動向サマリーを作成・更新する。
   - 保存先: `outputs/executive_summaries/04_monthly/monthly_YYYY-MM-DD.md`
5. **四半期サマリー (05_quarterly)**:
   - 1日に1回、過去90日間に収集された論文群を集計した日本語表形式の四半期レポートを作成・更新する。
   - 保存先: `outputs/executive_summaries/05_quarterly/quarterly_YYYY-MM-DD.md`
6. **半期サマリー (06_semi_annual)**:
   - 1日に1回、過去180日間に収集された論文群を集計した日本語表形式の半期戦略レポートを作成・更新する。
   - 保存先: `outputs/executive_summaries/06_semi_annual/semi_annual_YYYY-MM-DD.md`
7. **通期サマリー (07_annual)**:
   - 1日に1回、過去365日間に収集された論文群を集計した日本語表形式の通期総括レポートを作成・更新する。
   - 保存先: `outputs/executive_summaries/07_annual/annual_YYYY-MM-DD.md`

### FR-04: OKF ルートインデックスおよびログの自動更新
- **内容**: 全ての成果物（Rawデータ、OKF論文、7層のサマリー）へのリンクとステータスを一覧化する OKF インデックスファイル `outputs/index.md` （完全日本語化された表形式）およびログファイル `outputs/log.md` を自動更新すること。
- **保存先**: `outputs/index.md`, `outputs/log.md`





### FR-05: 定期自動実行機能
- **内容**: 1日4回 (`00:00`, `06:00`, `12:00`, `18:00` UTC/JST) に処理を自動起動し、最新論文の取得・変換・サマリー更新を行うこと。

---

## 3. 非機能要件 (Non-Functional Requirements)

### NFR-01: 可用性・障害耐性 (Reliability & Fault Tolerance)
- arXiv API (`https://export.arxiv.org/api/query`) 呼び出し時のネットワーク遅延やタイムアウトに対応するため、標準 API の失敗時には RSS フィード (`https://rss.arxiv.org/rss/cs.CR`) への自動フォールバックを行う。

### NFR-02: 冪等性・重複排除 (Idempotency & Deduplication)
- 処理済み論文の ID (`arxiv_id`) を `processed_papers.json` に記録し、同一論文の重複処理および重複ファイル生成を防止する（`--force` フラグ指定時を除く）。

### NFR-03: トレーサビリティ・検証可能性 (Traceability)
- 全ての OKF ドキュメントおよびサマリーに生成タイムスタンプと原本 Raw JSON への相対パスを含め、後からAIエージェントまたは人間が判断根拠を追跡できるようにする。
