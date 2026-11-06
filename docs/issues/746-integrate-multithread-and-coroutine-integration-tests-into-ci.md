---
ID: 746
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] CI テストマトリクスへのマルチスレッド・コルーチン並行性結合テスト統合 (ID: 746)

## 1. 概要 / Summary
並行性ランタイム向けに `test_supervisor` や `test_concurrency_ci` 等の結合テストが作成されたが、`.github/workflows/ci.yml` では単一スレッドの `make test (pytest)` のみが実行されており、CI 上でマルチスレッド環境やコルーチンでの実動作が検証されていない。
PR やコミット時に自動で並行性・耐障害性回帰テストが実行されるよう、CI ワークフローと Makefile ターゲットを整備する。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue: Follow-up of #722
- 関連資料: CI/CD パイプライン運用標準、Makefile テストスイート定義

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml)
- [ ] [`Makefile`](../../Makefile)
- [ ] [`ulisp/tests/test_supervisor.scm`](../../ulisp/tests/test_supervisor.scm)
- [ ] [`ulisp/tests/test_concurrency_ci.scm`](../../ulisp/tests/test_concurrency_ci.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/746-integrate-multithread-and-coroutine-integration-tests-into-ci`

1. `Makefile`:
   - `test-concurrency` ターゲットを新設し、以下を実行できるように構成：
     - `test_supervisor` (コルーチン版および OS スレッド worker 版)
     - `test_concurrency_ci`
     - `test_multithread_scheduler`
2. `.github/workflows/ci.yml`:
   - 既存の `make test` に加え、`make test-concurrency` を必須チェックステップに追加。
   - Linux x86-64 環境および QEMU AArch64 環境の両方で実行可能なマトリクスジョブを設定。
3. `ulisp/tests/`:
   - コルーチン型子タスクで構成されたテストシナリオと、複数 OS スレッドで構成されたテストシナリオを明示的にパラメータ化して分離・網羅する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `make test-concurrency` で並行性テスト群が一括実行できること
- [ ] GitHub Actions CI 上で `test_supervisor` および `test_concurrency_ci` が自動実行され PASS すること
- [ ] コルーチン型およびマルチスレッド型の双方がテストマトリクスでカバーされていること

