---
ID: 330
種別: Bug
優先度: High
ステータス: Closed (Resolved)
---

# [BUG] スケジューラー (WorkflowScheduler) における例外握りつぶしの解消と失敗ステータス記録 (ID: 330)

## 1. 概要 / Summary
`src/workflow/scheduler.py` の `_execute_task()`（114-119行目）において、タスクハンドラー実行時の例外が `except Exception: task.last_run = _now()` で無言で握りつぶされていた。
このため、エラー発生時にスタックトレースが記録されず障害調査が困難となり、タスクの実行結果ステータスやエラーメッセージが追跡できない問題を解消した。
例外発生時の明示的なスタックトレースロギング (`logger.exception`)、`ScheduledTask` のステータス・エラー保持（`last_status="FAILED"`, `last_error=str(exc)`）、および `to_dict()` でのメタデータ露出を実装し、障害検知・可観測性を確立した。

### 再現手順 / Steps to Reproduce
1. スパイダーハンドラーやタスク実行時に意図的な例外（ネットワークエラー、構文エラー等）を発生させる。
2. スケジューラーログに例外が出力されず、無言で次回スケジュール時刻（`last_run`）のみ更新される。
3. タスク一覧 API / ステータスインスペクションに失敗ステータスが通知・表示されない。

### 再現環境 / Environment
- OS / Env: Linux / Antigravity IDE
- File: `src/workflow/scheduler.py`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [scheduler.py](../../src/workflow/scheduler.py): `_execute_task` での例外ロギング、`ScheduledTask` への `last_status` / `last_error` 追跡追加
- [x] [test_workflow_hsm.py](../../tests/workflow/test_workflow_hsm.py): スケジューラー例外ハンドリングおよびタスクステータス更新の単体テスト追加

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `WorkflowScheduler._execute_task()` 内の例外処理節で `logger.exception` が呼ばれておらず、例外情報が握りつぶされていた。
- `ScheduledTask` が実行成否（`last_status`）や最後のエラーメッセージ（`last_error`）をフィールドとして保持していなかったため、スケジューラーのインスペクション API（`list_tasks()`）経由で外部から失敗を検知できなかった。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: ハンドラー内部で個別にログ出力を行う。
* **恒久対策 (Permanent Fix)**:
  1. `ScheduledTask` に `last_status: str = "IDLE"` および `last_error: Optional[str] = None` を追加し、`to_dict()` に含める。
  2. `_execute_task()` で成功時は `task.last_status = "SUCCESS"`, `task.last_error = None`、失敗時は `task.last_status = "FAILED"`, `task.last_error = str(exc)` を記録。
  3. ロガーで `logger.exception("[WorkflowScheduler] Task '%s' execution failed: %s", task.task_id, exc)` を確実に呼び出す。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/330-fix-workflow-scheduler-silent-exception-swallowing`

1. `src/workflow/scheduler.py` の `ScheduledTask` データクラスに `last_status` と `last_error` フィールドを追加し、`to_dict()` に含める。
2. `_execute_task()` を改修し、成功時と失敗時のステータス更新を行う。
3. `tests/workflow/test_workflow_hsm.py` に、例外送出ハンドラーが登録されたタスクの `last_status == "FAILED"` および `last_error` 記録を検証するテストを追加。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] スケジューラータスク実行で例外が発生した場合に、ログにスタックトレースが出力されること。
- [x] `ScheduledTask` の `last_status` が `"FAILED"` となり、`last_error` に例外メッセージが格納されること。
- [x] `list_tasks()` や `to_dict()` を通じてエラー情報が露出されること。
- [x] 単体テストが追加され、全品質ゲート（`make check_format`、`make static_analysis`、`pytest`）が 100% PASS すること。
