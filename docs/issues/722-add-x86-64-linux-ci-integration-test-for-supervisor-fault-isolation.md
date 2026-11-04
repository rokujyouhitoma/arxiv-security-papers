---
ID: 722
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] x86-64 Linux における Supervisor 配下の子タスク異常終了隔離と自動再起動の CI 結合テスト追加 (ID: 722)

## 1. 概要 / Summary
x86-64 Linux の CI および結合テストとして、Supervisor の配下で子タスクに `(car '())` を実行させてクラッシュさせ、無関係な並行タスクが正常に完了すること、およびクラッシュした子タスクが Supervisor によって自動で再起動することを確認するエンドツーエンド結合テストを実装する（A2・B4・B6・C7 の受け入れ条件）。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Section 8.4)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [Makefile](../../ulisp/Makefile)
- [ ] [test_supervisor.scm](../../tests/concurrency/test_supervisor.scm)
- [ ] [concurrency_harness.scm](../../tests/concurrency/concurrency_harness.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/722-synapse-ci-fault-isolation-integration-test`

1. Supervisor 配下に `(car '())` を実行する子タスクと、独立して計算を行う無関係なタスクを同時に走らせる結合テストを作成する。
2. 無関係なタスクがクラッシュに巻き込まれず完了すること、およびクラッシュした子タスクが自動で再起動されることを検証するアサーションを実装する。
3. x86-64 Linux の CI ターゲット（`ulisp/Makefile`）に組み込み、A2・B4・B6・C7 の受け入れ条件として自動実行する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Supervisor 配下で子タスクに `(car '())` を実行させた際、無関係なタスクが正常完了し、子が自動再起動することが x86-64 Linux CI テストで検証されること。
- [ ] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

