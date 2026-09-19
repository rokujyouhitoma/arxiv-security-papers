---
ID: 330
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG] スケジューラー (WorkflowScheduler) における例外握りつぶしの解消と失敗ステータス記録 (ID: 330)

## 1. 概要 / Summary
`src/workflow/scheduler.py` の `_execute_task()`（114-119行目）において、タスクハンドラー実行時の例外が `except Exception: task.last_run = _now()` で無言で握りつぶされている。
このため、エラー発生時にスタックトレースが記録されず障害調査が困難となり、DB に失敗（FAILED）ステータスやエラーメッセージが記録されないため Web UI 上の「メッセージ/エラー」列にも失敗が可視化されない問題を解消する。

### 再現手順 / Steps to Reproduce
1. スパイダーハンドラーやタスク実行時に意図的な例外（ネットワークエラー、構文エラー等）を発生させる。
2. スケジューラーログに例外が出力されず、無言で次回スケジュール時刻（`last_run`）のみ更新される。
3. Web UI に失敗ステータスが通知・表示されない。

### 再現環境 / Environment
- OS / Env: Linux / Antigravity IDE
- File: `src/workflow/scheduler.py`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [scheduler.py](../../src/workflow/scheduler.py)
- [ ] [spider_operator.py](../../src/workflow/operators/spider_operator.py)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `WorkflowScheduler._execute_task()` 内の例外処理節で `logger.exception` などのロギング処理が一切行われておらず、例外情報が失われている。
- タスク実行失敗時にエラー結果（`CrawlResult(success=False, error_message=...)` 相当）を永続化層へ通知・記録するフォールバック処理が存在しない。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: なし（ログに残らないため原因究明が遅延する）。
* **恒久対策 (Permanent Fix)**: `logger.exception()` によるスタックトレース出力の追加、および例外発生時にも失敗ステータスとエラー内容を保持して永続化層へ `record_finish` を行うハンドリング機構の実装。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/330-fix-workflow-scheduler-silent-exception-swallowing`

1. `WorkflowScheduler._execute_task()` に詳細な例外ロギング（`logger.error`/`logger.exception`）を追加。
2. ハンドラー側（またはスケジューラー側）で例外発生時に `CrawlResult(success=False, error=str(exc))` を構築し、`SpiderExecutionStorage.record_finish` を呼び出す。
3. Web UI の「メッセージ/エラー」列に実際のエラーメッセージが表示されるよう連携。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] スケジューラータスク実行で例外が発生した場合に、ログにスタックトレースが出力されること。
- [ ] 例外発生時に FAILED ステータスおよびエラーメッセージが DB に記録されること。
- [ ] Web UI 上のエラー列にエラー内容が可視化されること。
- [ ] 全品質ゲート（フォーマット、xenon、型チェック、単体テスト）が 100% PASS すること。
