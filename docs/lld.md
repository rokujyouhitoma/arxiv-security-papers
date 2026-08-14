# 詳細設計書 (Low-Level Design - LLD)

## 1. モジュールおよび関数仕様 (`arxiv_okf_fetcher.py`)

### 1.1 原データ保存および PDF/TXT 取得関数
- **`save_raw_paper_data(paper, workspace_dir, config)`**:
  - メタデータ JSON (`<clean_id>_meta.json`) およびアブストラクト (`<clean_id>_raw_abstract.txt`) を保存。
- **`fetch_single_pdf_and_text(paper, raw_dir)`**:
  - arXiv より原論文 PDF (`<clean_id>.pdf`) をダウンロードし、`pdftotext` コマンドで全文テキスト (`<clean_id>.txt`) を自動抽出し `outputs/raw_data/YYYY-MM-DD/` 配下に保存。
  - `ThreadPoolExecutor(max_workers=10)` により並列取得を行い、バッチ処理時間を大幅に短縮。

### 1.2 テンプレート読込・サマリー生成関数
- **`load_template(template_name, default_content, workspace_dir, config)`**:
  - `templates/` ディレクトリから指定のテンプレートファイル（`.md.template`）を動的に読み込み。未存在時は内蔵デフォルト文字列へフォールバック。
- **`generate_*_summary(...)` / `build_okf_from_raw(...)`**:
  - テンプレートファイルへ変数（日付・論文数・テーブルマークダウン・OKFメタデータ等）を挿入してサマリーおよびOKFドキュメントをレンダリング。

---

## 2. データ構造・成果物ファイル定義

### 2.1 原データディレクトリ構成 (`outputs/raw_data/YYYY-MM-DD/`)
- `<clean_id>_meta.json`: メタデータ JSON
- `<clean_id>_raw_abstract.txt`: 原本アブストラクト TXT
- `<clean_id>.pdf`: 原論文 PDF ファイル
- `<clean_id>.txt`: 抽出された全文テキスト TXT ファイル

### 2.2 テンプレートファイル構成 (`templates/`)
- `01_per_run.md.template`: 取得時サマリー用テンプレート
- `02_daily.md.template`: 日次サマリー用テンプレート
- `04_monthly.md.template`: 月次サマリー用テンプレート
- `05_quarterly.md.template`: 四半期サマリー用テンプレート
- `06_semi_annual.md.template`: 半期サマリー用テンプレート
- `07_annual.md.template`: 通期サマリー用テンプレート
- `okf_paper.md.template`: OKF 論文ドキュメント用テンプレート

