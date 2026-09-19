---
ID: 333
種別: Feature / Enhancement
優先度: Low
ステータス: Closed (Completed)
---

# [FEAT/ENH] スケジューラー初回起動時におけるスパイダー即時実行挙動の制御と仕様明記 (ID: 333)

## 1. 概要 / Summary
`src/workflow/scheduler.py` の `ScheduledTask` 定義において、`last_run: float = 0.0` と初期化されているため、Arbiter プロセス起動直後の初回ポーリング時に全スパイダー（arXiv, CWE, CVE）が即時発火する挙動となっている。
この設計は「システム起動直後に最新データを即時取得し、未収集状態（コールドスタート）を解消する」ための合理的なデフォルト動作であるが、本番環境において初回即時実行を抑止し初回インターバル経過後から実行を開始したいユースケースにも対応できるよう、`run_on_startup: bool = True` および `initial_delay: float = 0.0` の制御オプション、環境変数 `ARXIV_SPIDER_RUN_ON_STARTUP` を導入し、仕様と動作原理をユーザーマニュアルに明記した。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: [scheduler.py](../../src/workflow/scheduler.py), [service.py](../../src/workflow/service.py), [USR-01-user_manual.md](../manuals/USR-01-user_manual.md)
- 要求元: スケジューラー初回起動ライフサイクルの予測可能性および柔軟性向上

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [scheduler.py](../../src/workflow/scheduler.py): `ScheduledTask` への `run_on_startup` フィールド追加、`register_task` / `register_spider_task` での初期 `last_run` 計算ロジック導入
- [x] [service.py](../../src/workflow/service.py): `WorkflowService` への `run_on_startup` 引数および環境変数 `ARXIV_SPIDER_RUN_ON_STARTUP` 連動
- [x] [USR-01-user_manual.md](../manuals/USR-01-user_manual.md): 初回起動時即時実行仕様および環境変数による制御手順の追記
- [x] [test_workflow_hsm.py](../../tests/workflow/test_workflow_hsm.py): `run_on_startup=False` および `initial_delay` の挙動検証テスト追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/333-clarify-or-adjust-scheduler-initial-execution-behavior`

1. **スケジューラーコア改修 (`src/workflow/scheduler.py`)**:
   - `ScheduledTask` に `run_on_startup: bool = True` を追加。
   - `WorkflowScheduler._compute_initial_last_run(now, interval_seconds, run_on_startup, initial_delay)` を実装。
   - `register_task` / `register_spider_task` に `run_on_startup`, `initial_delay` 引数を追加。
2. **サービス層連携 (`src/workflow/service.py`)**:
   - `WorkflowService` 初期化時に `ARXIV_SPIDER_RUN_ON_STARTUP`（デフォルト `true`）を読み取り、`register_default_spider_tasks` に伝播。
3. **ドキュメント明文化 (`docs/manuals/USR-01-user_manual.md`)**:
   - 起動直後に即時実行される目的（コールドスタート解消）と、抑止する場合の環境変数指定方法を記載。
4. **テスト追加 (`tests/workflow/test_workflow_hsm.py`)**:
   - `run_on_startup=False` 時に直ちに `is_due()` が `False` になること、`run_on_startup=True` 時に直ちに `is_due()` が `True` になることを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ScheduledTask` および `WorkflowScheduler` に `run_on_startup` / `initial_delay` の制御が実装されていること。
- [x] `WorkflowService` が環境変数 `ARXIV_SPIDER_RUN_ON_STARTUP` を尊重すること。
- [x] ユーザーマニュアルに初回起動時実行の仕様と設定手順が明確に記述されていること。
- [x] 単体テストおよび全品質ゲート（`make check_format`、`make static_analysis`、`pytest`）が 100% PASS すること。
