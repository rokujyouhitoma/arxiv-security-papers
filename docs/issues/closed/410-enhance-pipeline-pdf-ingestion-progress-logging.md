---
ID: 410
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] パイプラインにおけるPDF取得・全文テキスト抽出の進捗可視化とリアルタイムログの強化 (ID: 410)

## 1. 概要 / Summary
`make pipeline` または `arxiv_okf_fetcher.py` の実行時、`[Pipeline:Filter]` の出力直後に `_download_theme_pdfs` による大量の PDF ダウンロードおよび Pure-Python エンジン / pdftotext による全文テキスト抽出がバックグラウンドで行われる。
しかし、このフェーズにおいて開始アナウンスログおよび各論文ごとの完了進捗ログ（`[xx/total]`）が出力されておらず、かつ標準出力のフラッシュが行われていなかったため、ユーザー視点でプロセスがハング・停止しているように見えてしまう課題があった。
本 Issue では、PDF ダウンロードおよびテキスト抽出フェーズにおけるリアルタイムな進捗ログ（件数・パーセンテージ・処理ID・成功/失敗）の出力、および `sys.stdout.flush` を徹底し、パイプラインの進行状況を完全に可視化する。

---

## 2. 多角的エージェント検討 / Multi-Agent Review
- **Project Manager (PM)**:
  - ユーザーがパイプラインの停止・進行中を直感的に識別できるよう、進捗率（%）および件数カウントを明瞭に表示する。
- **IT Service Manager (ITSM)**:
  - パイプライン各ステージ（Stage 1/3 Ingestion, Stage 2/3 Transformation, Stage 3/3 Reporting）の境界をログに明示し、障害発生時の切り分け容易性を確保する。
- **Software Quality Assurance (QA)**:
  - スレッドプール内で例外が発生した場合も握りつぶさずに進捗ログ上にエラー種別を反映し、パイプライン全体がデッドロックしないことを保証する。
- **Information Security Specialist**:
  - ログに個人情報や機微なAPI認証キーが出力されないこと、arXiv/IACR等のダウンロード先URLがサニタイズされたクリーンIDとして表現されることを確認する。

---

## 3. トレーサビリティ / Traceability
- 関連資料:
  - [.agents/AGENTS.md](../../.agents/AGENTS.md) (Section 1: 15専門エージェント統括 & ログ監査・可視化)
  - [src/pipeline/arxiv_okf_fetcher.py](../../src/pipeline/arxiv_okf_fetcher.py)
  - [src/pipeline/ingestion/pdf_extractor.py](../../src/pipeline/ingestion/pdf_extractor.py)
  - [tests/pipeline/test_ingestion.py](../../tests/pipeline/test_ingestion.py)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/pipeline/arxiv_okf_fetcher.py](../../src/pipeline/arxiv_okf_fetcher.py)
- [x] [src/pipeline/ingestion/pdf_extractor.py](../../src/pipeline/ingestion/pdf_extractor.py)
- [x] [tests/pipeline/test_ingestion.py](../../tests/pipeline/test_ingestion.py)
- [x] [docs/issues/README.md](README.md)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/410-enhance-pipeline-pdf-ingestion-progress-logging`

1. **`fetch_single_pdf_and_text` のステータス返却**:
   - `src/pipeline/ingestion/pdf_extractor.py` の `fetch_single_pdf_and_text(paper, raw_dir)` において、ダウンロード成否・テキスト抽出成否・キャッシュ有無を辞書で返却：
     ```python
     {
         "clean_id": clean_id,
         "arxiv_id": paper.get("arxiv_id", clean_id),
         "pdf": pdf_ok,
         "txt": txt_ok,
         "pdf_cached": pdf_cached,
         "txt_cached": txt_cached,
     }
     ```

2. **`_download_theme_pdfs` のリアルタイム進捗ログと集計**:
   - `src/pipeline/arxiv_okf_fetcher.py` の `_download_theme_pdfs` を改修：
     - 開始ログ: `[YYYY-MM-DD HH:MM:SS] [ETL:Ingestion] Starting parallel download & text extraction for {total} papers (concurrency: {max_workers})...`
     - スレッド完了毎: `[Ingestion:PDF] [{completed:>3d}/{total:<3d}] ({pct:>5.1f}%) Paper: {clean_id:<25s} [{status_desc}]`
     - 完了サマリー: `[ETL:Ingestion] Finished downloading & extracting {total} papers in {elapsed:.1f}s (PDF OK: {pdf_count}/{total}, TXT OK: {txt_count}/{total}).`
     - 即時ターミナル描画のための `flush=True` 指定。

3. **パイプラインステージ境界の可視化**:
   - `run_theme_pipeline` 内で各ステージの開始ログ（Stage 1/3, Stage 2/3, Stage 3/3）を明示。
   - `_transform_and_save_okf`、`_filter_and_stage_papers` 内の進捗ログにも `flush=True` を徹底。

4. **テストの拡張**:
   - `tests/pipeline/test_ingestion.py` に `fetch_single_pdf_and_text` の戻り値構造とキャッシュ判定を検証する単体テストを追加。
   - `_download_theme_pdfs` の進捗ログ出力が正しく動作することを検証するテストを追加。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `fetch_single_pdf_and_text` が PDF / TXT の存在・取得状態を含む辞書を返却すること。
- [x] `_download_theme_pdfs` 実行時に開始ログ、各件の進捗ログ（パーセント・件数・ステータス）、完了サマリーログが出力されること。
- [x] すべての進捗ログで `flush=True` が保証され、ターミナルでリアルタイムに進捗が確認できること。
- [x] 単体テストが追加され、既存のテストスイートおよび品質ゲート (`make format`, `make static_analysis`, `make test`) がすべて 100% PASS すること。
- [x] 全ドキュメント内の内部リンクが相対パスで正しく構成されていること。
