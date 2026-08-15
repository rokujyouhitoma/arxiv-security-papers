# [REQ-01] システム要件定義書 (System Requirements Specification) - arxiv-security-papers

本ドキュメントは、「`arxiv-security-papers`」プロジェクトの機能要件（FR）、非機能要件（NFR）、および AI エージェント / MCP サーバ連携要件を包括的に定義するシステム要件定義書です。

---

## 1. プロジェクト概要

本プロジェクトは、学術論文リポジトリ `arxiv.org` のコンピュータサイエンス・暗号・セキュリティ分野（`cs.CR`）から1日4回自動で最新論文を取得し、Googleの提唱するナレッジ標準規格 **Google OKF (Open Knowledge Format) v0.2** に準拠したナレッジドキュメントに加工するとともに、5つのレベル（取得時ごと・日次・月次・四半期・通期）で独立管理された完全日本語エグゼクティブサマリーを自動生成・提供するパイプラインシステムです。さらに、標準 MCP (Model Context Protocol) サーバおよびベクトル DB 検索エンジンを統合し、AI エージェントに対する即時セマンティック検索環境を提供します。

---

## 2. 機能要件 (Functional Requirements)

### FR-01: arXiv セキュリティ論文のデータ収集および原本 (Raw) 保存 (160日間さかのぼり取得)
- **内容**: arXiv API (`cs.CR` カテゴリ) より過去160日間に遡って全セキュリティ論文をフェッチし、以下の原本データを個別に保存すること。
  1. メタデータ JSON (`<clean_id>_meta.json`)
  2. 原本 Abstract テキスト (`<clean_id>_raw_abstract.txt`)
  3. **原論文 PDF ファイル (`<clean_id>.pdf`)**: arXiv より直接ダウンロード
  4. **抽出本文テキスト (`<clean_id>.txt`)**: `pdftotext` によりPDFから全本文テキストを自動抽出
- **保存先**: `outputs/raw_data/YYYY-MM-DD/` (過去160日間の日付フォルダ)

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

### FR-03: 5階層のエグゼクティブサマリー独立生成・管理 (01_〜05_ 連続項番ソート・表形式・完全日本語化対応)
それぞれ `outputs/executive_summaries/` 配下の連続項番（01〜05）を冠したソート可能な独立ディレクトリで個別に管理し、文章および論文一覧（マークダウン表形式）は **完全に日本語化 (100% Japanese)** されていること。
1. **取得時ごとサマリー (01_per_run)**: `outputs/executive_summaries/01_per_run/YYYY-MM-DD/run_HHMM.md`
2. **一日分サマリー (02_daily)**: `outputs/executive_summaries/02_daily/YYYY-MM-DD.md`
3. **一か月分サマリー (03_monthly)**: `outputs/executive_summaries/03_monthly/monthly_YYYY-MM-DD.md`
4. **四半期サマリー (04_quarterly)**: `outputs/executive_summaries/04_quarterly/quarterly_YYYY-MM-DD.md`
5. **通期サマリー (05_annual)**: `outputs/executive_summaries/05_annual/annual_YYYY-MM-DD.md`

### FR-04: OKF ルートインデックスおよびログの自動更新
- **内容**: 全ての成果物（Rawデータ、OKF論文、5層のサマリー）へのリンクとステータスを一覧化する OKF インデックスファイル `outputs/index.md` （完全日本語化された表形式）およびログファイル `outputs/log.md` を自動更新すること。

### FR-05: 定期自動実行機能 (Schedule Cron)
- **内容**: 1日4回 (`00:00`, `06:00`, `12:00`, `18:00` UTC/JST) に処理を自動起動し、最新論文の取得・変換・サマリー更新を行うこと。

### FR-06: MCP サーバ ＆ ベクトル DB セマンティック検索機能 (Model Context Protocol)
- **内容**: 14,000件以上の全 OKF 論文ドキュメントを永続インデックス化 (`outputs/vector_db/index.json`) し、MCP JSON-RPC 2.0 サーバ経由で 4大ツール (`search_security_papers`, `get_paper_summary`, `get_latest_trends`, `query_attack_technique`) を提供すること。

---

## 3. 非機能要件 (Non-Functional Requirements)

### NFR-01: 可用性・障害耐性 (Reliability & Fault Tolerance)
- arXiv API (`https://export.arxiv.org/api/query`) 呼び出し時のネットワーク遅延やタイムアウトに対応するため、標準 API の失敗時には RSS フィード (`https://rss.arxiv.org/rss/cs.CR`) への自動フォールバックを行う。

### NFR-02: 冪等性・重複排除 (Idempotency & Deduplication)
- 処理済み論文の ID (`arxiv_id`) を `processed_papers.json` に記録し、同一論文の重複処理および重複ファイル生成を防止する（`--force` フラグ指定時を除く）。

### NFR-03: トレーサビリティ・検証可能性 (Traceability)
- 全ての OKF ドキュメントおよびサマリーに生成タイムスタンプと原本 Raw JSON への相対パスを含め、AI エージェントまたは人間が判断根拠を追跡できるようにする。

### NFR-04: セキュリティ・パス検証 (Security & Path Validation)
- MCP サーバおよび各ハンドラにおいて、ワークスペース外へのアクセスや敏感ファイル（`.ssh`, `.env`, `etc/passwd` 等）の不正閲覧を防ぐ `is_safe_workspace_path` ガードおよび `os.path.realpath` 検証を必須適用する。
