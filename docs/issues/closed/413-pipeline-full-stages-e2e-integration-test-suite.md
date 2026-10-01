---
ID: 413
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] パイプライン全ステージ (Ingestion/Transformation/Reporting) のE2E自動統合テスト基盤の構築 (ID: 413)

## 1. 概要 / Summary
パイプラインは Stage 1 (Ingestion: PDF取得・テキスト抽出) → Stage 2 (Transformation: OKF Markdown生成) → Stage 3 (Reporting: 5階層サマリー・Mermaidトレンド・台帳更新) から構成されている。
現状は各モジュール個別の単体テストが整備されているものの、全3ステージを連続で実行し、一時ディレクトリ上で最終的な OKF ドキュメント、5階層サマリー（01_per_run〜05_annual）、Mermaid mindmap、および `papers_catalog.json` / `log.md` が欠落なく生成・更新されることを一気通貫で検証する E2E 統合テストが不足していた。
本 Issue では、外部 arXiv / ネットワークアクセスをモックし、ミリ秒オーダーで安全かつ高速に実行できるエンドツーエンド統合テストスイートを新設し、パイプライン変更時のリグレッションを自動検知できるようにする。

---

## 2. 多角的エージェント検討 / Multi-Agent Review
- **Project Manager (PM)**:
  - リリース前および CI パイプラインで確実に全ステージの正常動作が保証されるよう、包括的なテストシナリオを確立する。
- **Software Quality Assurance (QA)**:
  - 1回目の実行（新規論文処理）と2回目の実行（既存論文スキップの冪等性）の双方を検証し、データの重複登録や破損がないことを確認する。
- **Database / Data Infrastructure Specialist**:
  - `papers_catalog.json`、`outputs/log.md`、`outputs/raw_data/`、`outputs/okf/papers/`、`outputs/executive_summaries/` への書き込み整合性とスキーマ妥当性をアサートする。
- **IT Specialist (NLP & Info Retrieval)**:
  - テキスト抽出および 3点要約・タイトル翻訳が OKF Markdown 内に正しく反映されているかを検証する。

---

## 3. トレーサビリティ / Traceability
- 関連資料:
  - [.agents/AGENTS.md](../../.agents/AGENTS.md) (Section 1: 15専門エージェント統括 - SQA Specialist & Section 6: Raw Data & Idempotency)
  - [src/pipeline/arxiv_okf_fetcher.py](../../src/pipeline/arxiv_okf_fetcher.py)
  - [src/pipeline/reporter/summary_generator.py](../../src/pipeline/reporter/summary_generator.py)
  - [docs/issues/closed/404-okf-5-tier-executive-summary-sync-and-trend-analysis.md](closed/404-okf-5-tier-executive-summary-sync-and-trend-analysis.md)
  - [docs/issues/closed/410-enhance-pipeline-pdf-ingestion-progress-logging.md](closed/410-enhance-pipeline-pdf-ingestion-progress-logging.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [tests/pipeline/test_pipeline_e2e.py](../../tests/pipeline/test_pipeline_e2e.py)
- [ ] [src/pipeline/arxiv_okf_fetcher.py](../../src/pipeline/arxiv_okf_fetcher.py)
- [ ] [docs/issues/README.md](README.md)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/413-pipeline-full-stages-e2e-integration-test-suite`

1. **E2E 統合テストファイルの作成 (`tests/pipeline/test_pipeline_e2e.py`)**:
   - `tempfile.TemporaryDirectory` 内で独立した作業スペースを構成。
   - `run_theme_pipeline("security", target_workspace=tmp_dir)` を実行。
   - arXiv API / PDFダウンロード / pdftotext をモックし、高速かつ安定したテストを実行可能にする。

2. **全成果物の生成・整合性検証**:
   - Stage 1: `outputs/raw_data/` に JSON, PDF, TXT が存在すること。
   - Stage 2: `outputs/okf/papers/` に OKF v0.2 Markdown が生成され、YAML フロントマターが有効であること。
   - Stage 3: `outputs/executive_summaries/` の各階層（01〜05）が生成され、Markdown テーブルおよび Mermaid mindmap が挿入されていること。
   - カタログ & ログ: `outputs/database/papers_catalog.json` および `outputs/log.md` が更新されていること。

3. **冪等性（Idempotency）の E2E 検証**:
   - 同一のテストフィードに対して再度 `run_theme_pipeline` を実行した際、処理件数が 0 件となり、既存ファイルが壊れず安全にスキップされることを確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `tests/pipeline/test_pipeline_e2e.py` が新規作成され、3ステージの連携が一気通貫で検証されること。
- [x] 冪等性（2回目実行時のスキップ）が E2E レベルで自動検証されること。
- [x] 新規 E2E テストを含む全テストスイートおよび品質ゲート (`make format`, `make static_analysis`, `make test`) が 100% PASS すること。
- [x] 全ドキュメント内の内部リンクが相対パスで正しく構成されていること。
