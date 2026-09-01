---
ID: 108
種別: Improvement / Feature
優先度: High
ステータス: Closed (Resolved)
---

# [IMPR/SEC] arXiv API レート制限バックオフ時間の拡張 (8s/16s/32s/64s) および RSS フォールバック遷移ログの明示化 (ID: 108)

## 1. 概要 / Summary
arXiv API (Atom API) に対するアクセス集中時に返される HTTP 429 (Too Many Requests) に対し、現行のバックオフ待機時間（4s/8s/16s、合計約28秒）では arXiv 側のレート制限ウィンドウ（冷却期間）が解除される前にリトライ上限に達してしまう課題があった。
本 Issue では、バックオフ待機時間を `8s -> 16s -> 32s -> 64s`（最大4回再試行、合計最大120秒）に拡張して API フェッチ成功率を飛躍的に向上させるとともに、API フェッチ失敗時に arXiv RSS フィード (`https://rss.arxiv.org/rss/cs.CR`) へ自動フォールバックする遷移ログを明示的に出力する改善を行った。

### 再現手順 / Steps to Reproduce
1. 短期間に複数回 `python3 src/pipeline/arxiv_okf_fetcher.py` を実行。
2. arXiv API から HTTP 429 が返され、4s/8s/16s のリトライ後に上限到達して失敗する。
3. RSS フォールバックへの切り替え発生時に、ユーザーに切り替えの事実が明示されない。

### 再現環境 / Environment
- OS / Env: Linux / Ubuntu 24.04 (Python 3.14+)
- File: `src/pipeline/ingestion/arxiv_client.py`, `src/pipeline/ingestion/adapters/arxiv_adapter.py`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/pipeline/ingestion/arxiv_client.py](../../src/pipeline/ingestion/arxiv_client.py) (`_handle_api_http_error`, `fetch_arxiv_rss_fallback`)
- [x] [src/pipeline/ingestion/adapters/arxiv_adapter.py](../../src/pipeline/ingestion/adapters/arxiv_adapter.py) (`_fetch_raw_paper_dicts`)
- [x] [tests/pipeline/test_ingestion.py](../../tests/pipeline/test_ingestion.py)
- [x] [tests/pipeline/test_source_adapters.py](../../tests/pipeline/test_source_adapters.py)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **なぜ 429 時にリトライが失敗していたか**:
   arXiv API のレート制限は一定期間（通常30秒〜60秒程度）継続することがあり、4s/8s/16s（28秒）ではサーバー側のレート制限状態が解除される前に全リトライを消費していた。
2. **なぜフォールバックの状況が分かりにくかったか**:
   `ArxivSourceAdapter` で API 失敗後に RSS フォールバックを呼び出していたが、フォールバック開始ログが出力されていなかった。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 
  手動で 1〜2 分待機した後にコマンドを再実行する。
* **恒久対策 (Permanent Fix)**: 
  - `_handle_api_http_error()` における待機秒数を `8 * (2 ** retry)` 秒（`8s`, `16s`, `32s`, `64s`）に拡張。
  - `ArxivSourceAdapter` および `fetch_arxiv_rss_fallback` において、RSS フォールバック発動時の明示的ログを出力。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/108-expand-arxiv-rate-limit-backoff-and-rss-fallback-log`

### Phase 1: レート制限バックオフ時間とフォールバックログの改修
1. `src/pipeline/ingestion/arxiv_client.py`:
   - `_handle_api_http_error`: `wait_time = 8 * (2 ** retry)` に更新（8s, 16s, 32s, 64s）。
   - `fetch_arxiv_rss_fallback`: 開始ログ `[Ingestion:arXiv:RSS] Fetching latest papers via RSS fallback feed...` を出力。
2. `src/pipeline/ingestion/adapters/arxiv_adapter.py`:
   - API 失敗時に `[Ingestion:arXiv] API fetch returned 0 papers or rate-limited for '...'. Triggering automatic fallback to arXiv RSS feed...` を出力。

### Phase 2: 単体テストの拡充と品質ゲート検証
1. `tests/pipeline/test_ingestion.py` に 429 バックオフ時間計算（`[8, 16, 32, 64]`）と再試行回数のテストを追加。
2. `make check_format`, `make static_analysis`, `make test` を実行。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] arXiv API の HTTP 429 / 503 発生時に `8s -> 16s -> 32s -> 64s` の待機時間でリトライが実行されること。
- [x] API 取得失敗時に RSS フォールバックへの切り替えログが明瞭に出力されること。
- [x] `make check_format`, `make static_analysis`, `make test` が 100% PASS すること。
