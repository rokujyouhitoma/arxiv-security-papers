---
ID: 116
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] 過去160日間大規模バックフィル実行の自律レジューム＆安全なレートリミット制御バッチ機構の確立 (ID: 116)

## 1. 概要 / Summary
arXiv API の厳格なアクセス制限（1リクエストあたり3秒以上の待機間隔、HTTP 429 / 503 防止）を遵守しながら、過去160日分（数千件規模）のセキュリティ論文メタデータ・PDF原本・全文テキスト・OKF v0.2変換・5階層サマリーを安全かつ確実に一括取得・蓄積するための、自律レジューム（中断・再開）可能な長期バックフィル実行エンジンを確立する。

---

## 2. トレーサビリティ / Traceability
- [DSN-03: ETL データパイプライン包括設計書（第5章）](../../docs/designs/DSN-03-pipeline_architecture.md#5-バックフィル--過去データ復元パイプライン)
- [DSN-12: 汎用プロセススーパーバイザー & 調停基盤](../../docs/designs/DSN-12-process_supervisor_and_arbiter.md)
- [AGENTS.md: Governance & PM-Led Multi-Agent Framework](../../.agents/AGENTS.md)
- 運用標準スキル: `backfill-pipeline`

---

## 3. 脅威分析・制約事項 / Threat Analysis & Operational Constraints
1. **arXiv API レート制限 (HTTP 429) & IP ブロック脅威**:
   - *脅威*: 頻回なリクエストにより arXiv 側から一時的・恒久的な IP ブロックを受けるリスク。
   - *緩和策*: `AdaptiveRateLimiter` による厳格な最小 3.0 秒待機間隔保証、HTTP 429 検知時の指数バックオフ（8s $\to$ 16s $\to$ 32s $\to$ 64s）、および継続障害時の RSS 自動フォールバック。
2. **プロセスクラッシュ・ネットワーク断によるデータ欠損・二重取得**:
   - *脅威*: 160日分の途中で異常終了した場合に、最初からやり直しとなり二重フェッチや不整合が発生する。
   - *緩和策*: `outputs/backfill_state.json` による日付・ページ単位のアトミックなチェックポイント保存と、`processed_papers.json` による二重登録防止（冪等性保証）。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/pipeline/arxiv_okf_fetcher.py](../../src/pipeline/arxiv_okf_fetcher.py) (CLI オプション `--backfill`, `--resume`, `--checkpoint-file` 追加)
- [ ] [src/pipeline/ingestion/arxiv_client.py](../../src/pipeline/ingestion/arxiv_client.py) (`AdaptiveRateLimiter` および 160日分ページネーション制御)
- [ ] [src/pipeline/ingestion/adapters/arxiv_adapter.py](../../src/pipeline/ingestion/adapters/arxiv_adapter.py) (チェックポイント連動フェッチ)
- [ ] [Makefile](../../Makefile) (`backfill_160d`, `backfill_resume` ターゲット拡充)
- [ ] [tests/pipeline/test_ingestion.py](../../tests/pipeline/test_ingestion.py) (チェックポイント中断・再開およびレートリミッター単体テスト)
- [ ] [tests/pipeline/test_backfill_resumption.py](../../tests/pipeline/test_backfill_resumption.py) (E2E バックフィルステートマシンテスト)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/116-implement-autonomous-160d-backfill-resumption-and-rate-limiting`

### Step 1: `BackfillStateManager` の実装 (`src/pipeline/ingestion/`)
- チェックポイントファイル `outputs/backfill_state.json` のロード・アトミック更新（一時ファイル書き込み＋`os.replace`）。
- ステート構造:
  - `target_days`: 160
  - `current_target_date`: 処理中の日付文字列 (`YYYY-MM-DD`)
  - `current_page`: 処理中のページインデックス
  - `completed_dates`: 完了済み日付リスト
  - `total_papers_fetched`: 累計取得件数
  - `status`: `"running"` | `"paused"` | `"completed"`

### Step 2: `AdaptiveRateLimiter` の強化 (`src/pipeline/ingestion/arxiv_client.py`)
- トークンバケットアルゴリズムによる最小インターバル 3.0s 制御。
- `urllib.error.HTTPError` (429/503) 捕捉時の指数バックオフと `outputs/logs/` への構造化ログ記録。

### Step 3: `arxiv_okf_fetcher.py` への `--resume` / `--backfill` 統合
- `--backfill <days>`: 指定日数分のバックフィル実行。
- `--resume`: `outputs/backfill_state.json` を検知し、未完了の日付・ページから自動継続。
- 1日単位の処理完了ごとに `outputs/executive_summaries/02_daily/` を生成し、全日程終了時に `03_monthly`, `04_quarterly`, `05_annual` を一括更新。

### Step 4: Makefile ターゲットとテストスイートの実装
- `make backfill_160d`: 160日バックフィル起動。
- `make backfill_resume`: 中断ステートからの再開。
- `tests/pipeline/test_backfill_resumption.py` によるモック通信での中断・再開・完全性テスト。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `BackfillStateManager` がクラッシュ後も直前チェックポイントから正確に未完了日を再開できること
- [ ] リクエスト待機間隔が 3.0 秒以上に保たれ、HTTP 429 発生時に自動バックオフすること
- [ ] `outputs/raw_data/`、`outputs/okf_papers/`、および `outputs/executive_summaries/` のデータ整合性が保たれること
- [ ] Xenon 循環的複雑度が全関数で Grade A ($CC \le 5$) を満たすこと
- [ ] `pytest tests/pipeline/` を含む全テストスイートが 100% PASS すること
