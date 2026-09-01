---
ID: 107
種別: Feature / Bug
優先度: High
ステータス: Closed (Resolved)
---

# [FEAT/BUG] arXiv API タイムアウト時の一時エラーリトライ強化およびパイプライン進捗ログ詳細化 (ID: 107)

## 1. 概要 / Summary
arXiv API へのリクエスト時にネットワーク遅延やアクセス集中によるタイムアウト (`The read operation timed out` / `urllib.error.URLError`) が発生した際、現行実装ではリトライが行われず 1 度で失敗してフォールバックへ移行する課題があった。
また、パイプライン実行時に「どのソースから何件取得され、何件が日付フィルタや重複スキップされ、何件が新規にダウンロード・OKF変換・サマリー更新されたか」の途中経過ログが出力されず、実行進捗が不透明であった。
本 Issue では、タイムアウトを含む一時的ネットワーク例外に対する指数バックオフリトライを導入し、パイプライン各段階（フェッチ、フィルタリング内訳、PDFダウンロード、OKF変換、ナレッジグラフ格納、5階層サマリー更新）の詳細な進捗ログ（Verbose Logging）を実装した。

### 再現手順 / Steps to Reproduce
1. `python3 src/pipeline/arxiv_okf_fetcher.py --start-date 2026-08-26 --end-date 2026-09-01` を実行。
2. ネットワーク遅延等で `[WARN] API fetch failed (The read operation timed out)` が発生し、リトライされずに即時中断・フォールバックされる。
3. 取得から完了までの間に処理件数の内訳や各ステージの進行状況が出力されず、動作状況が把握できない。

### 再現環境 / Environment
- OS / Env: Linux / Ubuntu 24.04 (Python 3.14+)
- File: `src/pipeline/ingestion/arxiv_client.py`, `src/pipeline/arxiv_okf_fetcher.py`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/pipeline/ingestion/arxiv_client.py](../../src/pipeline/ingestion/arxiv_client.py) (`_handle_api_network_error`, `_fetch_api_chunk_with_retry`, `fetch_arxiv_papers`)
- [x] [src/pipeline/arxiv_okf_fetcher.py](../../src/pipeline/arxiv_okf_fetcher.py) (`_filter_and_stage_papers`, `_transform_and_save_okf`, `_ingest_items_into_knowledge_graph`, `_generate_summaries_and_index`)
- [x] [tests/pipeline/test_ingestion.py](../../tests/pipeline/test_ingestion.py)
- [x] [tests/pipeline/test_pipeline.py](../../tests/pipeline/test_pipeline.py)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **なぜタイムアウト時に即座に中断したか**:
   `src/pipeline/ingestion/arxiv_client.py` の `_fetch_api_chunk_with_retry` において、`urllib.error.HTTPError`（HTTP 429/503）のみが `_handle_api_http_error` でリトライ処理され、`URLError` やタイムアウトなどのネットワーク例外は `except Exception as e:` で捕捉されて `return None` していた。
2. **なぜ `No new papers to stage.` となったか**:
   arXiv API フェッチがタイムアウトで失敗した後、フォールバック（または IACR 等の他ソース）から取得された論文が直前の実行で既に処理済み（`processed_papers.json` に記録済み）であったため、新規ステージ対象が 0 件となった。
3. **なぜ進捗が不透明だったか**:
   パイプラインの標準出力がエラー・警告時（`[WARN]`）または全体完了時のみに限定されており、フェッチチャンクの取得数、期間外除外件数、処理済みスキップ件数、OKF 変換ステップの進行度が表示されていなかった。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 
  手動で再実行するか、`--force` フラグを付与して既存論文を強制再処理する。
* **恒久対策 (Permanent Fix)**: 
  - `_handle_api_network_error()` を新設し、タイムアウトや一時的接続切断時にも指数バックオフ（最大 4 回、2^retry * 3 秒）で自動再試行する。
  - HTTP リクエストタイムアウトを 30秒から 45秒に緩和。
  - パイプラインの各処理フェーズ（Ingestion, Filter, PDF Download, OKF Transformer, Knowledge Graph, Reporter）に構造化された進捗ログを標準出力へ出力。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/107-enhance-arxiv-timeout-retry-and-pipeline-progress-logging`

### Phase 1: Ingestion 層の耐障害性強化
1. `src/pipeline/ingestion/arxiv_client.py`:
   - `_handle_api_network_error(err, retry)` を追加し、ネットワーク例外を指数バックオフで再試行。
   - `fetch_arxiv_papers()` でチャンク取得ごとの進捗ログ（`offset`, `limit`, `received`, `cumulative`）を出力。

### Phase 2: パイプライン全体の進捗可視化
1. `src/pipeline/arxiv_okf_fetcher.py`:
   - `_filter_and_stage_papers()`: 受信件数、期間外除外数、処理済みスキップ数、新規ステージ数のサマリーを出力。
   - `_transform_and_save_okf()`: OKF 変換時に `[idx/total]` と出力先 Markdown パスを逐次表示。
   - `_ingest_items_into_knowledge_graph()`: グラフ DB への頂点・エッジ格納結果を表示。
   - `_generate_summaries_and_index()`: 01_per_run 〜 05_annual の各サマリーおよびインデックス更新の完了を表示。

### Phase 3: テストと品質ゲート検証
1. `tests/pipeline/test_ingestion.py` および `tests/pipeline/test_pipeline.py` でリトライ機構およびログ出力が正常に動作することを検証。
2. `make check_format`, `make static_analysis`, `make test` の通過を確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] arXiv API 呼び出しにおいて、HTTP 429/503 に加え `URLError` / タイムアウト発生時にも指数バックオフ（最大 4 回）で自動再試行されること。
- [x] パイプライン実行時に、フェッチ chunk、フィルタリング内訳（受信数、期間外除外数、既存処理済みスキップ数、新規ステージ数）、OKF 変換進捗 `[idx/total]`、ナレッジグラフ格納、5階層サマリー生成の各ログが明確に出力されること。
- [x] `make check_format`, `make static_analysis`, `make test` が 100% PASS すること。
