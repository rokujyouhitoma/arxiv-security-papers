# 詳細設計書 (Low-Level Design - LLD)

## 1. モジュールおよび関数仕様 (`arxiv_okf_fetcher.py`)

### 1.1 原データ保存および PDF/TXT 取得関数
- **`save_raw_paper_data(paper, workspace_dir, config)`**:
  - メタデータ JSON (`<clean_id>_meta.json`) およびアブストラクト (`<clean_id>_raw_abstract.txt`) を保存。
- **`fetch_single_pdf_and_text(paper, raw_dir)`**:
  - arXiv より原論文 PDF (`<clean_id>.pdf`) をダウンロードし、`pdftotext` コマンドで全文テキスト (`<clean_id>.txt`) を自動抽出し `outputs/raw_data/YYYY-MM-DD/` 配下に保存。
  - `ThreadPoolExecutor(max_workers=10)` により並列取得を行い、バッチ処理時間を大幅に短縮。

---

## 2. データ構造・成果物ファイル定義

### 2.1 原データディレクトリ構成 (`outputs/raw_data/YYYY-MM-DD/`)
- `<clean_id>_meta.json`: メタデータ JSON
- `<clean_id>_raw_abstract.txt`: 原本アブストラクト TXT
- `<clean_id>.pdf`: 原論文 PDF ファイル
- `<clean_id>.txt`: 抽出された全文テキスト TXT ファイル
