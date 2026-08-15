---
name: refine-existing-feature
description: arxiv_okf_fetcher.py、arXiv API/RSS通信フォールバック、PDF全文抽出、Google OKF変換エンジン、および5階層サマリーの完成度・堅牢性・パフォーマンスを極限まで研ぎ澄ます標準改善プロシージャスキル。
---

# refine-existing-feature

本スキルは、**「arxiv-security-papers のコアパイプライン（フェッチ・フォールバック・PDFダウンロード・pdftotext全文抽出・OKF変換・5層サマリー生成）の完成度・耐障害性・処理スピード・コード構造を極限まで研ぎ澄ます (Pipeline Refinement & Optimization)」** ための標準プロシージャスキルです。

全 13 大専門エージェント（特に PM, SA, QA, NW, IR, SC）の協調のもと、パイプラインのボトルネックや通信エラーリスクを排除し、最高度の信頼性へ昇華させます。

---

## 🏛️ パイプライン精緻化 5 大改善ピラー (5 Pillars of Pipeline Refinement)

```
[Pillar 1] API/RSS 通信レジリエンス & バックオフの研ぎ澄まし (NW / SC)
       ├── arXiv API (cs.CR) 指数バックオフリトライ (Retry policy) の最適化
       ├── APIレスポンス異常/タイムアウト時の arXiv RSS フィード (https://rss.arxiv.org/rss/cs.CR) へのシームレスなフォールバック
       └── HTTP 通信エラーハンドリングとレート制限の遵守
       ↓
[Pillar 2] 並列 PDF ダウンロード & pdftotext 抽出の高速化・安定化 (IR / SA)
       ├── arXiv PDF の並列ダウンロードおよび一時キャッシュの安全制御
       ├── pdftotext による論文全文抽出時の文字化け・例外処理・タイムアウト防止
       └── 抽出テキスト (<clean_id>.txt) の品質とメモリフットプリント削減
       ↓
[Pillar 3] 冪等性 & processed_papers.json 状態管理の研ぎ澄まし (DB / QA)
       ├── 重複論文 (arxiv_id) の確実なスキップと重複ファイル生成の防止 (--force フラグ制御)
       └── 処理済みリスト JSON の不可逆な破壊を防ぐアトミック書き込み (Atomic Write) の適用
       ↓
[Pillar 4] Google OKF v0.2 / 5層サマリー構造化度の研ぎ澄まし (UI / STR)
       ├── YAML フロントマターおよび provenance/trust のメタデータ完全整合
       └── 01_per_run〜05_annual サマリーのマークダウン表形式および日本語表現の美観・視認性向上
       ↓
[Pillar 5] 統合品質検証ゲート (`verify-quality-gates`) による 100% PASS アサート
```

---

## 📋 実行手順 (Execution Instructions)

### Step 1: ボトルネック特定 & 診断監査 (Diagnostic Audit)
1. 改善対象のモジュール（API取得部、RSSフォールバック部、PDFダウンロード/抽出部、OKF変換部、サマリー作成部）を決定する。
2. ボトルネックや潜在リスク（ネットワークタイムアウト、PDF抽出失敗時のフォールバック漏れ、メモリ肥大化など）を特定する。

### Step 2: 変更アセスメント & 精緻化設計
1. 後方互換性を保証し、`config.json` やデータ保存仕様を壊さない設計を策定する。
2. `create-issue` および `polish-issue` スキルで Issue を作成・精緻化する。

### Step 3: リファクタリング & 高速化実装
1. Python スクリプト (`arxiv_okf_fetcher.py`) を改修する。
2. 通信リトライ、並列ダウンロード制御、アトミックファイル書き込みなどの改善を実装する。

### Step 4: 全自動品質管理ゲート検証 (`verify-quality-gates`)
1. `python3 -m py_compile arxiv_okf_fetcher.py` を実行し、構文エラー 0 件を確認。
2. `verify-quality-gates` スキルを実行し、すべての自動品質ゲート（構文、OKF適合、相対パス、サマリー構造、冪等性）を **100% PASS** させる。

### Step 5: Issue クローズ & Conventional Commit マージ
1. DoD をクリアし、Issue を `Closed` に更新して `docs/issues/closed/` に移動。
2. `git-workflow` スキルを使用して `refactor: [Issue ID] ...` や `perf: [Issue ID] ...` の Conventional Commit を作成。
