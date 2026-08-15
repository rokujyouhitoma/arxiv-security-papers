---
name: health-check-monitor
description: arXiv API/RSS 疎通状況、pdftotext 抽出成功率、processed_papers.json 整合性、および outputs/log.md 障害履歴を一括診断・自動リカバリ提案を行うパイプライン監視・ヘルスチェック標準スキル。
---

# health-check-monitor

本スキルは、**「arXiv セキュリティ論文自動フェッチパイプラインの正常性、通信状態、`pdftotext` 抽出成功率、および `processed_papers.json` 整合性を定期的かつ一括で自動診断し、発生したエラーの早期発見とリカバリ手順の提示を行う」** ための標準プロシージャスキルです。

ITサービスマネージャ（SM）、ソフトウェア品質保証（QA）、およびネットワーク（NW）の連携により、1日4回の定期バッチの無停止安定運用を支えます。

---

## 🏥 パイプライン健全性 5 大診断項目

```
[1. arXiv API / RSS 疎通診断 (NW)]
       ├── arXiv API (https://export.arxiv.org/api/query) HTTP レスポンスタイム & ステータス確認
       └── arXiv RSS (https://rss.arxiv.org/rss/cs.CR) 疎通テスト
       ↓
[2. pdftotext 抽出成功率診断 (IR)]
       └── outputs/raw_data/ 配下の PDF に対する TXT 抽出成功率 (目標 >= 98%) のアサート
       ↓
[3. 冪等性リスト整合性診断 (DB)]
       └── processed_papers.json の JSON 正常構造 & 重複キー存在チェック
       ↓
[4. OKF v0.2 & 01-05サマリー最新性診断 (QA / STR)]
       └── 最新実行日のサマリー更新履歴および outputs/index.md 最終同期時刻のチェック
       ↓
[5. 総合ヘルスレポート出力 (SM)]
       └── outputs/log.md へのヘルス診断ログ記録
```

---

## 📋 実行手順 (Instructions)

### Step 1: 通信疎通テスト (API & RSS)
1. 以下の curl コマンドで通信疎通を確認：
   - arXiv API: `curl -sI https://export.arxiv.org/api/query?search_query=cat:cs.CR\&max_results=1 | head -n 1` (HTTP/1.1 200 OK)
   - arXiv RSS: `curl -sI https://rss.arxiv.org/rss/cs.CR | head -n 1` (HTTP/1.1 200 OK)

### Step 2: システム依存モジュールチェック
1. `pdftotext` コマンドおよび Python バージョンを確認：
   - `pdftotext -v`
   - `python3 -V`

### Step 3: `processed_papers.json` 健全性チェック
1. 以下のコマンドで `processed_papers.json` の壊れがないかアサート：
   - 実行: `python3 -c "import json; d=json.load(open('processed_papers.json')); print(f'Total processed: {len(d)} papers')"`

### Step 4: 診断結果レポート出力
1. 全項目のテスト結果をアサートし、異常が検知された場合は自動リカバリ手順（例: `--force` 再取得、`processed_papers.json` のバックアップ復元）を `outputs/log.md` に追記。
