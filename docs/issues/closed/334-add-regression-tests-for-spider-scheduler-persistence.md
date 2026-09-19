---
ID: 334
種別: Test / Quality
優先度: High
ステータス: Closed (Completed)
---

# [TEST/QUAL] スパイダー定期実行 DB 永続化およびスケジューラー自動ディスパッチの包括的回帰テスト追加 (ID: 334)

## 1. 概要 / Summary
Issue 329 および Issue 330 で導入された定期実行パイプラインの DB 永続化（`SpiderExecutionStorage` 連携）と例外ハンドリングが将来の改修で先祖返り・回帰（Regression）しないよう、自動テストスイートを包括的に拡充した。
`WorkflowScheduler` と `SpiderTaskOperator`、および `SpiderExecutionStorage` が結合した状態で、定期実行サイクルが稼働した際に全スパイダーの実行レコードが VDB（`spider_execution.vdb`）へ確実に永続化・増加すること、さらに Supervisor `WorkflowLifecycleHook` を通じたライフサイクル管理が正しく機能することを実証する回帰テストを追加した。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: Issue 329, Issue 330, Issue 331, Issue 332, Issue 333, [test_spider_operator.py](../../tests/workflow/test_spider_operator.py), [test_arbiter.py](../../tests/supervisor/test_arbiter.py)
- 要求元: 回帰バグ防止および品質ゲート（Quality Gates）の強化

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [test_spider_operator.py](../../tests/workflow/test_spider_operator.py): スケジューラーによる全スパイダー一括ディスパッチと VDB 永続化レコード増加のエンドツーエンド回帰テスト追加
- [x] [test_arbiter.py](../../tests/supervisor/test_arbiter.py): Supervisor `WorkflowLifecycleHook` の初期化・定期フラッシュ・メトリクス連携テスト追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `test/334-add-regression-tests-for-spider-scheduler-persistence`

1. **スケジューラー ＆ VDB 永続化 E2E 回帰テスト (`tests/workflow/test_spider_operator.py`)**:
   - 一時ディレクトリ内の実 `SpiderExecutionStorage`（VDB）とモック `SpiderDaemonClient` を使用。
   - `WorkflowScheduler` に arXiv, CWE, KEV-CVE の 3 スパイダーを登録。
   - 初回ポーリング（`run_due_tasks()`）を実行し、全タスクがディスパッチされることを確認。
   - `storage.list_history()` で 3 件の実行ログが追加され、すべて `SUCCESS`、`job_id` 命名規則、`item_count` が整合していることを検証。
   - 直後に再度 `run_due_tasks()` を実行した場合、0 件ディスパッチ（インターバル未経過）となることを確認。
2. **Supervisor ライフサイクル回帰テスト (`tests/supervisor/test_arbiter.py`)**:
   - `WorkflowLifecycleHook` をインスタンス化し、`setup()`, `health_check()`, `on_flush()`, `get_metrics()` の一連のライフサイクルがエラーなく完了することを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] スケジューラーによる全スパイダー定期ディスパッチ後の VDB 永続化レコード増加を検証する E2E 回帰テストが追加され PASS すること。
- [x] Supervisor ライフサイクルフックとメトリクス連携を検証するテストが PASS すること。
- [x] 全品質ゲート（`make check_format`、`make static_analysis`、`pytest`）が 100% PASS すること。
