---
name: refine-okf-data
description: arXiv論文のGoogle OKF v0.2形式データ、構造化日本語エグゼクティブサマリー、セキュリティドメインタグ、およびRawデータ追跡メタデータの精緻化・質的向上を行う標準プロシージャスキル。
---

# refine-okf-data

本スキルは、**「arXivセキュリティ論文のGoogle OKF v0.2形式ドキュメント、構造化日本語エグゼクティブサマリー、タグ分類、およびRawデータメタデータトレーサビリティの質を研ぎ澄ます (OKF Data & Executive Summary Refinement)」** ための標準プロシージャスキルです。

エデュケーション（EDU）、情報検索（IR）、システム監査（AU）、セキュリティ（SC/NW/DB）、およびUI/UXデザイナー（UI）各エージェントの専門知識を総動員し、論文データの正確性・可読性・構造化度を最大化します。

---

## 📚 OKF データ精緻化 4 大ピラー (4 Pillars of OKF Refinement)

```
[Pillar 1] Google OKF v0.2 フロントマター & メタデータの研ぎ澄まし (SC / AU)
       ├── YAML フロントマター (type, title, description, resource, tags, timestamp, provenance, trust) の完全整合性
       ├── arXiv 論文カテゴリ (cs.CR, cs.NI, cs.AI) およびセキュリティ種別タグ (zero-trust, cryptanalysis, edr, iot) の最適化
       └── raw_data JSON (<clean_id>_meta.json) への相対パス追跡 (provenance) の正当性アサーション
       ↓
[Pillar 2] 1文日本語アブストラクト & 構造化要約の研ぎ澄まし (IR / EDU / Persona)
       ├── 英文論文 Abstract からの精度高い1文日本語要約 (description) の推敲
       ├── 専門用語（例: ZKP, eBPF, SGX, Homomorphic Encryption, EDR/XDR）の日本語定訳の厳格統一
       └── 曖昧な機械翻訳表現の排除と論理的密度の向上
       ↓
[Pillar 3] 5階層エグゼクティブサマリーの精緻化 (01_per_run〜05_annual) (STR / PM)
       ├── 01_per_run (取得時), 02_daily (日次), 03_monthly (月次), 04_quarterly (四半期), 05_annual (通期) サマリーの表形式完全日本語化
       ├── 日時・論文数・カテゴリ別動向の定量的集計整合性検証
       └── C-Level / セキュリティマネージャ向けの動向トピックハイライトの推敲
       ↓
[Pillar 4] カタログ・ログ同期 & 相対パスアサーション (QA / UI)
       ├── outputs/index.md (OKF Root Index) および outputs/log.md の最新状態同期
       └── 全 Markdown 内における相対パスリンク100%徹底 (絶対パス 0 件)
```

---

## 📋 実行手順 (Execution Instructions)

### Step 1: OKF ドキュメント & サマリーの品質チェック
1. 対象となる OKF ドキュメント (`outputs/okf_papers/YYYY-MM-DD/*.md`) またはサマリー (`outputs/executive_summaries/0X_*/*.md`) を指定する。
2. 以下の点を確認：
   - OKF YAML フロントマターの必須キー（`type`, `title`, `description`, `resource`, `tags`, `timestamp`, `provenance`, `trust`）がすべて存在するか。
   - `provenance` 内の `raw_json_path` が `outputs/raw_data/YYYY-MM-DD/<clean_id>_meta.json` への正当な相対パスになっているか。
   - サマリー内の表形式およびテキストが100%日本語化されているか。

### Step 2: 改善計画・Issue 起票 (`create-issue` & `polish-issue`)
1. 修正・強化方針を策定し、`create-issue` で Issue を作成する（種別: `Docs` または `Enhancement`）。
2. `polish-issue` スキルを適用し、具体的に修正・推敲する対象ファイル、タグ分類ルール、要約日本語訳の変更点、DoD を明確化する。

### Step 3: OKF データ & 日本語サマリーの推敲・精緻化
1. **YAML フロントマター精査**: タグ（`tags`）に最適なセキュリティドメイン（例: `web-security`, `cryptography`, `hardware-security`）が含まれるよう精査。
2. **要約の推敲**: `description`（1文日本語要約）が論文の貢献と革新性を簡潔明瞭に表現しているか推敲。
3. **5階層サマリー更新**: `outputs/executive_summaries/` 配下の該当サマリー表を最新データに同期・推敲。

### Step 4: 全自動品質検証 (`verify-quality-gates`)
1. `verify-quality-gates` スキルを実行し、以下の項目がすべて PASS することを確認：
   - Python文法・モジュール構文エラー 0件
   - 相対パスリンク違反 0件 (絶対パス `file:///` または `/root/` の混入 0件)
   - 01〜05サマリーディレクトリ存在確認 100% PASS
   - 冪等性ファイル `processed_papers.json` 読み込み検証 PASS

### Step 5: Issue クローズ & Conventional Commit マージ
1. DoD をクリアし、Issue を `Closed` に更新して `docs/issues/closed/` に移動。
2. `git-workflow` スキルを使用して `docs: [Issue ID] ...` や `data: [Issue ID] ...` の Conventional Commit を作成。
