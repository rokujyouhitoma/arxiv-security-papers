# [REQ-01] システム要件定義書 (System Requirements Specification) — arxiv-security-papers

本ドキュメントは、「`arxiv-security-papers`」プロジェクトの機能要件（FR）、非機能要件（NFR）、セマンティック RAG / MCP 連携要件、および Web ポータル・コンパイラ要件を包括的に定義するシステム要件定義書です。

---

## 1. プロジェクト概要

本プロジェクトは、学術論文リポジトリ `arxiv.org` のコンピュータサイエンス・暗号・セキュリティ分野（`cs.CR`・14,000 件超）から1日4回自動で最新論文を取得し、Google の提唱するナレッジ標準規格 **Google OKF (Open Knowledge Format) v0.2** に準拠したナレッジドキュメントに加工するとともに、5つのレベル（取得時ごと・日次・月次・四半期・通期）で独立管理された完全日本語エグゼクティブサマリーを自動生成・提供する自律型インテリジェンス・パイプラインシステムです。さらに、標準 MCP (Model Context Protocol) サーバ、専門用語同義語拡張付きハイブリッド Vector DB 検索エンジン、および リッチ Glassmorphic Web 検索ポータル（コンパイラエンジン付き）を統合し、AI エージェントと人間の双方に対する即時インテリジェンス環境を提供します。

---

## 2. 機能要件 (Functional Requirements)

### FR-01: arXiv セキュリティ論文のデータ収集および原本 (Raw) 保存 (160日間さかのぼり取得)
- **内容**: arXiv API (`cs.CR` カテゴリ) より過去160日間に遡って全セキュリティ論文をフェッチし、以下の原本データを個別に保存すること。
  1. メタデータ JSON (`<clean_id>_meta.json`)
  2. 原本 Abstract テキスト (`<clean_id>_raw_abstract.txt`)
  3. **原論文 PDF ファイル (`<clean_id>.pdf`)**: arXiv より直接ダウンロード
  4. **抽出本文テキスト (`<clean_id>.txt`)**: `pdftotext` により PDF から全本文テキストを自動抽出
- **保存先**: `outputs/raw_data/YYYY-MM-DD/` (過去160日間の日付フォルダ)

### FR-02: Google OKF v0.2 形式への変換・フォーマット生成
- **内容**: 保存された `outputs/raw_data/` のファイルから、Google OKF (Open Knowledge Format) v0.2 仕様に準拠した YAML フロントマター付き Markdown ドキュメントを作成すること。
- **仕様要件**:
  - `type`: `"security-paper"`
  - `title`: 論文タイトル
  - `description`: 構造化エグゼクティブサマリーの1文要約
  - `resource`: arXiv 論文詳細ページ URL
  - `tags`: カテゴリタグおよび種別タグ
  - `timestamp`: ISO 8601 形式の生成タイムスタンプ
  - `provenance`: 取得元 (`arxiv.org`)、原本 JSON 相対パス、公開日時、著者一覧
  - `trust`: 認証署名/アテストステーション情報
- **保存先**: `outputs/okf_papers/YYYY-MM-DD/<clean_id>.md`

### FR-03: 5階層のエグゼクティブサマリー独立生成・管理 (01_〜05_ 連続項番ソート・表形式・完全日本語化対応)
- **内容**: `outputs/executive_summaries/` 配下の連続項番（01〜05）を冠したソート可能な独立ディレクトリで個別に管理し、文章および論文一覧（マークダウン表形式）は **完全に日本語化 (100% Japanese)** されていること。
  1. **取得時ごとサマリー (01_per_run)**: `outputs/executive_summaries/01_per_run/YYYY-MM-DD/run_HHMM.md`
  2. **一日分サマリー (02_daily)**: `outputs/executive_summaries/02_daily/YYYY-MM-DD.md`
  3. **一か月分サマリー (03_monthly)**: `outputs/executive_summaries/03_monthly/monthly_YYYY-MM-DD.md`
  4. **四半期サマリー (04_quarterly)**: `outputs/executive_summaries/04_quarterly/quarterly_YYYY-MM-DD.md`
  5. **通期サマリー (05_annual)**: `outputs/executive_summaries/05_annual/annual_YYYY-MM-DD.md`

### FR-04: OKF ルートインデックスおよびログの自動更新
- **内容**: 全ての成果物（Rawデータ、OKF論文、5層のサマリー）へのリンクとステータスを一覧化する OKF インデックスファイル `outputs/index.md` （完全日本語化された表形式）およびログファイル `outputs/log.md` を自動更新すること。

### FR-05: 定期自動実行機能 (Schedule Cron)
- **内容**: 1日4回 (`00:00`, `06:00`, `12:00`, `18:00` UTC/JST) に処理を自動起動し、最新論文の取得・変換・サマリー更新を行うこと。

### FR-06: 専門用語シノニム拡張付きハイブリッド Vector RAG 検索エンジン (v2.0.0)
- **内容**: 14,000件以上の全 OKF 論文ドキュメントを永続インデックス化 (`outputs/vector_db/index.json`) し、`SynonymExpander` モジュールによる日英専門用語（ペンテスト, 自動運転, マルウェア, 暗号, LLMセキュリティ, 脅威モデリング等）の双方向展開、および多重フィールド加重スコアリング（Title: 3.5, Tags: 3.0, Description: 2.5, Abstract: 1.5）を実施すること。

### FR-07: Model Context Protocol (MCP) サーバ ＆ 4大ツール提供
- **内容**: Anthropic / Google 提唱の MCP JSON-RPC 2.0 サーバ経由で 4 大ツール (`search_security_papers`, `get_paper_summary`, `get_latest_trends`, `query_attack_technique`) を安全に公開すること。

### FR-08: Glassmorphic Executive Web ポータル ＆ GET クエリパラメータ連動
- **内容**: `site/` 配下にモダンなダークモード Web UI (`http://localhost:8000`) を提供し、Google スタイルの URL クエリパラメータ (`?q=クエリ&tag=カテゴリ`) および History API (`history.pushState`) による直感的な検索・ダイレクトアクセス機能を提供すること。

### FR-09: クライアントサイド Markdown Compiler Engine (Lexer, Parser, AST, Evaluator, Renderer)
- **内容**: マークダウン構文を解析・変換・描画するコンパイラエンジンをモジュール分割開発 (`site/js/lexer.js`, `parser.js`, `evaluator.js`, `renderer.js`, `markdown_compiler.js`) し、表形式データおよび Mermaid 図 (`mermaid.run()`) をブラウザ上で動的描画すること。

---

## 3. 非機能要件 (Non-Functional Requirements)

### NFR-01: 可用性・障害耐性 (Reliability & Fault Tolerance)
- arXiv API (`https://export.arxiv.org/api/query`) 呼び出し時のネットワーク遅延やタイムアウトに対応するため、標準 API の失敗時には RSS フィード (`https://rss.arxiv.org/rss/cs.CR`) への自動フォールバックを行う。

### NFR-02: 冪等性・重複排除 (Idempotency & Deduplication)
- 処理済み論文の ID (`arxiv_id`) を `processed_papers.json` に記録し、同一論文の重複処理および重複ファイル生成を防止する（`--force` フラグ指定時を除く）。

### NFR-03: トレーサビリティ・検証可能性 (Traceability)
- 全ての OKF ドキュメントおよびサマリーに生成タイムスタンプと原本 Raw JSON への相対パスを含め、AI エージェントまたは人間が判断根拠を追跡できるようにする。

### NFR-04: セキュリティ・パス境界検証 (Security & Path Boundary Guard)
- MCP サーバ、Web API サーバー、および各ハンドラにおいて、ワークスペース外へのアクセスや機密ファイル（`.ssh`, `.env`, `etc/passwd` 等）の不正閲覧を防ぐ `is_safe_workspace_path` ガードおよび `os.path.realpath` 検証を必須適用する。

### NFR-05: Google Closure Compiler ツール配置 ＆ 最適化ビルド (`yuzora` 準拠)
- `tools/closure-compiler/closure-compiler-v20240317.jar` を配置し、外部シンボル保護ファイル (`site/externs.js`) を用いて `Makefile` の `make build_js` により最軽量ミニファイ JS (`site/app-min.js`) を全自動生成すること。

### NFR-06: 品質管理ゲート (Quality Gates SLA)
- `make py_compile`, `make static_analysis`, `make test`, `make build_js` の自動検証により、Python / JS 構文エラー 0 件、絶対パスリンク 0 件、および pytest 単体テスト 100% PASS を義務付ける。
