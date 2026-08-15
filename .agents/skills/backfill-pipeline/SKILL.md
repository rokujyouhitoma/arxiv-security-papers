---
name: backfill-pipeline
description: arXiv API のレート制限 (HTTP 429) や通信遅延を考慮しながら、過去160日間の過去論文を一括安全フェッチ・PDF抽出・OKF変換・5層サマリー一括更新するバックフィル運用標準スキル。
---

# backfill-pipeline

本スキルは、**「arXiv セキュリティ論文 (`cs.CR`) の過去160日間に遡る全データのバックフィル（一括過去データ取得・原本保存・OKF変換・5階層サマリー再集計）を通信障害やネットワーク制限を回避しながら安全に完遂する」** ための標準プロシージャスキルです。

ネットワーク（NW）、データインフラ（DB）、およびサービスマネージャ（SM）の連携により、自動バッチの安定実行とデータの完全性を保証します。

---

## 🔄 バックフィル実行フロー

```
[1. バックフィル起動準備]
       ├── processed_papers.json の状態バックアップ
       └── outputs/raw_data/ および outputs/okf_papers/ の日付ディレクトリ構造確保
       ↓
[2. バックオフ制御付きバッチフェッチ (arxiv_okf_fetcher.py --backfill 160)]
       ├── arXiv API Query (160日さかのぼり)
       ├── API 応答遅延時: 指数バックオフ (3s -> 6s -> 12s)
       └── API リクエスト失敗/制限時: arXiv RSS フィード自動フォールバック
       ↓
[3. 並列 PDF キャッシュ & pdftotext 抽出]
       ├── PDF ダウンロードの段階的実行 (1リクエストごと 1.5s インターバル)
       └── pdftotext 全文テキスト抽出し outputs/raw_data/YYYY-MM-DD/ に保存
       ↓
[4. Google OKF v0.2 変換 & 5層サマリー全一括更新]
       └── outputs/executive_summaries/ (01_per_run〜05_annual) の一括生成・再集計
```

---

## 📋 実行手順 (Instructions)

### Step 1: 事前確認
1. ディスク容量を確認（PDFダウンロード用に十分な容量があること）。
2. `python3 src/arxiv_okf_fetcher.py --help` を実行しバックフィルオプションを確認。

### Step 2: バックフィルフェッチの実行
1. 以下のコマンドを実行して過去160日分のバックフィルを開始：
   - 実行: `python3 src/arxiv_okf_fetcher.py --backfill 160`
2. 通信ログを確認し、レート制限が発生していないかアサート。

### Step 3: データ整合性 & 冪等性チェック
1. `processed_papers.json` に新たな `arxiv_id` が追加記録されたことを確認。
2. `outputs/raw_data/` 配下に過去160日間の日付ディレクトリが作成され、JSON/TXT/PDFが格納されたことをアサート。

### Step 4: 5層サマリー一括再生成 (`--update-summaries`)
1. バックフィル完了後、全サマリー層を最新データで更新：
   - 実行: `python3 src/arxiv_okf_fetcher.py --update-summaries`
2. `verify-quality-gates` スキルを実行し、品質管理ゲート（相対パス違反0件、サマリー完全日本語化等）を PASS することを確認。
