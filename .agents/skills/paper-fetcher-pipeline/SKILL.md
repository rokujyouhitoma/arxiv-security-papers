---
name: paper-fetcher-pipeline
description: arXiv API (cs.CR) からの論文データフェッチ、160日間過去データさかのぼり取得、RSSフィード自動フォールバック、PDF並列ダウンロード、および pdftotext 全文抽出を行うパイプライン実行・運用標準スキル。
---

# paper-fetcher-pipeline

本スキルは、**「arXiv セキュリティ論文 (`cs.CR`) の自動収集・フォールバック通信・PDFダウンロード・`pdftotext` 全文抽出および原本 (Raw) データの保存」** を確実に遂行するための標準プロシージャスキルです。

ネットワークスペシャリスト（NW）、データインフラ（DB）、情報検索（IR）、およびITサービスマネージャ（SM）各エージェントの連携により、高い耐障害性と冪等性を保証します。

---

## 🛰️ 論文フェッチ・データ抽出パイプラインフロー

```
[1. フェッチ起動 (arxiv_okf_fetcher.py)]
       ├── Primary: arXiv API (https://export.arxiv.org/api/query?search_query=cat:cs.CR)
       └── Fallback: arXiv RSS (https://rss.arxiv.org/rss/cs.CR) ※ API エラー/タイムアウト時
       ↓
[2. 重複排除 (Deduplication)]
       └── processed_papers.json を照合し、処理済み arxiv_id をスキップ (冪等性保持)
       ↓
[3. 原本 (Raw) データストレージ保存 (outputs/raw_data/YYYY-MM-DD/)]
       ├── ① <clean_id>_meta.json      : arXiv API メタデータ JSON
       ├── ② <clean_id>_raw_abstract.txt : 原本 Abstract (英文)
       ├── ③ <clean_id>.pdf             : arXiv PDF ファイル直接ダウンロード
       └── ④ <clean_id>.txt             : pdftotext による論文全文抽出テキスト
```

---

## 📋 実行手順 (Instructions)

### Step 1: フェッチ動作環境・依存コマンド確認
1. システム環境において `pdftotext` (poppler-utils) が利用可能であることを確認：
   - 実行確認: `pdftotext -v`
2. 処理済みリスト `processed_papers.json` が正常にロードできることを確認。

### Step 2: arXiv フェッチスクリプト実行
1. コアスクリプト `src/arxiv_okf_fetcher.py` を実行：
   - 通常実行: `python3 src/arxiv_okf_fetcher.py`
   - 過去160日さかのぼりフェッチ: `python3 src/arxiv_okf_fetcher.py --backfill 160`
   - 強制再取得実行: `python3 src/arxiv_okf_fetcher.py --force`

### Step 3: 原本保存データの検証
1. `outputs/raw_data/YYYY-MM-DD/` に4つのファイル形式が正しく生成されているかアサート：
   - `<clean_id>_meta.json` (サイズ > 0 B)
   - `<clean_id>_raw_abstract.txt` (サイズ > 0 B)
   - `<clean_id>.pdf` (PDFヘッダー `%PDF-` 存在確認)
   - `<clean_id>.txt` (抽出テキストが存在すること)

### Step 4: 通信例外時のトラブルシューティング
1. **arXiv API レート制限 (HTTP 429 / 503)**:
   - スクリプトが自動的に指数バックオフ (3秒 -> 6秒 -> 12秒) を行い、改善しない場合は RSS フィード (`https://rss.arxiv.org/rss/cs.CR`) へフォールバックしたことをログ `outputs/log.md` で確認する。
2. **`pdftotext` 抽出失敗時**:
   - PDFが暗号化されているか破損している場合はログをアサートし、AbstractのみからOKFドキュメントを生成する安全制御を動作させる。
