---
name: verify-quality-gates
description: arxiv-security-papers パイプライン全体の全品質管理ゲート (Quality Gates) を一括自動検証するプロシージャスキル。Python構文エラー0件、Google OKF v0.2仕様適合、絶対パスリンク排除 (0件検出)、01〜05サマリー階層構造、および冪等性・トレーサビリティの 100% PASS を保証する。
---
# verify-quality-gates

本スキルは、`arxiv-security-papers` リポジトリ（arXiv `cs.CR` 論文自動フェッチ・Google OKF v0.2 変換・5層エグゼクティブサマリー生成パイプライン）における最高水準のデータ品質・堅牢性・保守性を担保するため、すべての変更・リリース前に必ず実行し完全合格（全 PASS）を検証する統合品質管理ゲートプロシージャです。

---

## 🛡️ 統合品質管理ゲート一覧 (Quality Gate Criteria for arxiv-security-papers)

以下の 5 つの品質ゲートを順次検証し、**すべてエラー・警告・違反が 0 件** であることを厳格にアサートします。

```
[Quality Gate 1] Python パイプラインエンジン構文・コンパイルゲート (Makefile: py_compile)
       ├── make py_compile (または python3 -m py_compile arxiv_okf_fetcher.py) 構文エラー 0件
       ↓
[Quality Gate 2] Google OKF v0.2 スキーマ & YAML フロントマター適合ゲート
       ├── outputs/okf_papers/ の YAML フロントマター 8大必須キー (type, title, description, resource, tags, timestamp, provenance, trust) 存在アサーション
       ↓
[Quality Gate 3] 相対パスリンクガバナンスゲート (Relative Path Governance)
       ├── docs/, outputs/, .agents/ 内の Markdown における絶対パス (file:///, /root/, /workspace/) 違反: 0件
       ↓
[Quality Gate 4] 5階層エグゼクティブサマリー順序・完全日本語適合ゲート (01-05 Sequential Summary Tiering)
       ├── outputs/executive_summaries/ 配下の 01_per_run, 02_daily, 03_monthly, 04_quarterly, 05_annual 連続項番ディレクトリ存在アサーション
       └── サマリー本文および論文一覧表の 100% 日本語化アサーション
       ↓
[Quality Gate 5] 冪等性・Rawデータトレーサビリティアサーションゲート
       ├── processed_papers.json の JSON 正常読み込みおよび重複排除キー整合性
       └── raw_data/ への相対パスリンク (provenance.raw_json_path) の実在性アサーション
```

---

## 📋 実行・検証チェックリスト (Instructions)

### Gate 1: Python パイプラインエンジン構文ゲート
- **実行コマンド**: `make py_compile` (または `python3 -m py_compile arxiv_okf_fetcher.py`)
- **判定基準**:
  - Python スクリプトのコンパイルエラーおよび構文エラーが **完全 0 件** であること（Exit Code 0）。

### Gate 2: Google OKF v0.2 スキーマ適合ゲート
- **判定基準**:
  - 生成された OKF ドキュメント (`outputs/okf_papers/YYYY-MM-DD/*.md`) が Google OKF v0.2 仕様を満たしていること。
  - YAML フロントマターに `type: "security-paper"`, `title`, `description` (1文日本語要約), `resource`, `tags`, `timestamp`, `provenance`, `trust` が正しく格納されていること。

### Gate 3: 相対パスリンクガバナンスゲート
- **実行コマンド**: `grep -rn "file:///" docs/ outputs/ .agents/ || true`
- **判定基準**:
  - リポジトリ内の全 Markdown ドキュメントにおいて、実効絶対パスリンク (`file:///...`, `/root/...`, `/workspace/...`) の違反件数が **完全 0 件** であること。

### Gate 4: 5階層エグゼクティブサマリー構造 & 100% 日本語化ゲート
- **判定基準**:
  - `outputs/executive_summaries/` 配下に `01_per_run`, `02_daily`, `03_monthly`, `04_quarterly`, `05_annual` ディレクトリが項番順に正しく配置されていること。
  - サマリーレポート内のテキストおよび論文一覧表がすべて日本語化されていること。

### Gate 5: 冪等性 & Rawデータトレーサビリティゲート
- **判定基準**:
  - `processed_papers.json` が正常な JSON オブジェクトであり、処理済み論文の `arxiv_id` を正しく保持していること。
  - `outputs/raw_data/YYYY-MM-DD/` 配下に `<clean_id>_meta.json`, `<clean_id>_raw_abstract.txt`, `<clean_id>.pdf`, `<clean_id>.txt` が保存され、OKFドキュメントから到達可能であること。

---

## 🎯 検証結果出力ルール

全ゲートの検証結果ログを確認し、すべての判定が PASS である場合のみリリース・完了報告へ移行します。1 件でも違反・エラーが発生した場合は即座に作業を修正・再実行します。
