---
ID: 334
種別: Feature
優先度: High
ステータス: Open (New)
---

# [TEST/QUAL] スパイダー定期実行 DB 永続化およびスケジューラー自動ディスパッチの包括的回帰テスト追加 (ID: 334)

## 1. 概要 / Summary
Issue 329 および Issue 330 で導入される定期実行パイプラインの DB 永続化（`SpiderExecutionStorage` 連携）と例外ハンドリングが将来の改修で先祖返り・回帰（Regression）しないよう、自動テストスイートを拡充する。
`SpiderTaskOperator.execute()` のストレージ連携単体テスト、および Arbiter スケジューラー 1 サイクル実行後に DB レコードが増加することを確認するエンドツーエンド統合テストを追加する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: Issue 329, Issue 330, `tests/workflow/test_spider_operator.py`, `tests/supervisor/test_arbiter.py`
- 要求元: 回帰バグ防止および品質ゲート（Quality Gates）の強化

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [test_spider_operator.py](../../tests/workflow/test_spider_operator.py)
- [ ] [test_arbiter.py](../../tests/supervisor/test_arbiter.py)
- [ ] [spider_operator.py](../../src/workflow/operators/spider_operator.py)
- [ ] [scheduler.py](../../src/workflow/scheduler.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/334-add-regression-tests-for-spider-scheduler-persistence`

1. 単体テスト:
   - `SpiderTaskOperator.execute()` が `SpiderExecutionStorage.record_start` と `record_finish` を正常・異常系双方で確実に呼び出すことを検証。
2. 統合テスト:
   - モック HTTP またはインメモリクライアントを用い、Arbiter/スケジューラーが 1 サイクル稼働した後に `spider_execution.vdb` 内の `spider_execution_web` レコード件数が増加することを確認。
3. 異常系テスト:
   - 例外発生時に FAILED ステータスとエラーメッセージが記録され、スケジューラーがハング・握りつぶしなく稼働を継続することを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `SpiderTaskOperator` の永続化呼び出し検証テストが追加され PASS すること。
- [ ] スケジューラーによる定期実行後の DB 永続化レコード増加を検証するテストが PASS すること。
- [ ] `make test` および全品質ゲートが 100% PASS すること。
