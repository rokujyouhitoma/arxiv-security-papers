---
name: executive-summary-generator
description: 01_per_run (取得時), 02_daily (日次), 03_monthly (月次), 04_quarterly (四半期), 05_annual (通期) の 5 階層の独立した完全日本語マークダウン表形式エグゼクティブサマリーを自動生成・更新する標準スキル。
---

# executive-summary-generator

本スキルは、**「収集された OKF 論文群から、01_per_run〜05_annual の 5 階層で独立管理される完全日本語マークダウン表形式のエグゼクティブサマリーを自動生成・集計・更新する」** ための標準プロシージャスキルです。

ITストラテジスト（STR）、プロジェクトマネージャ（PM）、UI/UXデザイナー（UI）、およびサービスマネージャ（SM）の連携により、層別の価値と集計の整合性を確保します。

---

## 📊 5 階層エグゼクティブサマリー管理構造

全サマリー層は、ソート可能な 01〜05 の項番ディレクトリで個別に管理されます：

```
outputs/executive_summaries/
├── 01_per_run/       # 1. 取得時ごとサマリー (1日4回 00/06/12/18) [run_HHMM.md]
├── 02_daily/         # 2. 日次統合サマリー (1日) [YYYY-MM-DD.md]
├── 03_monthly/       # 3. 月次動向サマリー (直近30日) [monthly_YYYY-MM-DD.md]
├── 04_quarterly/     # 4. 四半期レポート (直近90日) [quarterly_YYYY-MM-DD.md]
└── 05_annual/        # 5. 通期総括レポート (直近365日) [annual_YYYY-MM-DD.md]
```

---

## 📋 サマリー出力フォーマット要件 (100% Japanese Markdown Table)

すべてのサマリーファイルは、以下の日本語表形式テンプレートに適合している必要があります：

```markdown
# [層名] セキュリティ論文エグゼクティブサマリー (集計日: YYYY-MM-DD)

## 1. 全体動向ハイライト
- **対象期間**: YYYY-MM-DD 〜 YYYY-MM-DD
- **総収集論文数**: XX 件
- **注目セキュリティカテゴリ**: [例: Zero Trust, 暗号解読, EDR, eBPF]

## 2. 論文一覧表 (完全日本語化)

| No. | arXiv ID | 論文タイトル (日本語) | カテゴリ | 1文要約 (日本語) | 詳細OKFリンク |
|:---:|:---:|---|:---:|---|:---:|
| 1 | `XXXX.XXXXX` | 日本語タイトル | cs.CR | 日本語1文要約 | [OKFドキュメント](../../okf_papers/YYYY-MM-DD/clean_id.md) |

## 3. 総括コメント
[セキュリティ管理者・研究者向けの総括インサイト]
```

---

## 📋 実行手順 (Instructions)

### Step 1: 5階層ディレクトリの存在アサーション
1. `outputs/executive_summaries/` 配下に `01_per_run`, `02_daily`, `03_monthly`, `04_quarterly`, `05_annual` が存在することを確認。

### Step 2: サマリー生成スクリプト実行
1. `src/arxiv_okf_fetcher.py` のサマリー生成モジュールを実行：
   - 全層サマリー更新: `python3 src/arxiv_okf_fetcher.py --update-summaries`

### Step 3: サマリー品質アサーション (Quality Gate 4)
1. **完全日本語化チェック**: 英語の要約や未翻訳タイトルが表内に残っていないこと。
2. **表形式崩れチェック**: マークダウンテーブルパイプ `|` の崩れがないこと。
3. **相対パスリンクアサーション**: OKFドキュメントへのリンクが正当な相対パス (`../../okf_papers/...`) であること。
