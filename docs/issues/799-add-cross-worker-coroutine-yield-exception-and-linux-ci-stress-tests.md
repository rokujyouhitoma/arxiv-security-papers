---
ID: 799
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/TEST] クロスワーカー環境におけるコルーチン yield 後例外テスト拡充および Linux 実機 CI 検証環境の確立 (ID: 799)

## 1. 概要 / Summary
Issue #787 および #791 においてコルーチンの例外処理と並列テスト（Group 11）が追加されたが、現状のテストは「単一スレッド同一スタック上での再開」または「外側からの `task-exit!` による停止」に限定されており、「ワーカー A で yield したコルーチンがワーカー B で再開（Work-Stealing / Task Migration）され、その直後に例外（例: `(car '())`）を発生させたケース」のスタック巻き戻しおよび例外ハンドラ連鎖復元の実機テストが未網羅のまま残されている。
また、開発環境が macOS arm64 に偏っていることで x86-64 Linux 向けビルドや実機ストレステストがローカルで実行されず、静的コードレビューのみでパス判定される構造的リスクが存在する。
本 Issue では、クロスワーカーでの再開・例外発生テストスイートを追加するとともに、Linux コンテナ / CI 上で自動実行される並行ストレステスト（ThreadSanitizer 連携含む）環境を確立する。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue: [787-fix-coroutine-exception-handler-chain-restore-after-yield.md](closed/787-fix-coroutine-exception-handler-chain-restore-after-yield.md), [791-add-parallel-integration-tests-for-supervisor-and-coroutines.md](closed/791-add-parallel-integration-tests-for-supervisor-and-coroutines.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [tests/concurrency/test_parallel_coroutine.scm](../../tests/concurrency/test_parallel_coroutine.scm) - クロスワーカー例外テストケース追加
- [ ] [ulisp/Makefile](../../ulisp/Makefile) - Linux / Docker テスト実行ターゲット整備
- [ ] [.github/workflows/](../../.github/workflows/) - CI マトリクス設定（Linux x86-64 自動テスト）

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/799-add-cross-worker-coroutine-yield-exception-and-linux-ci-stress-tests`

1. **クロスワーカー yield 後例外テストの作成**:
   - `scheduler-run-parallel!` 上でコルーチンを生成し、worker 0 で yield させる。
   - 他の worker にタスクをスチール / 移行させて再開し、直後に意図的なランタイムエラー（`(car '())` やゼロ除算）をトリガーする。
   - 例外ハンドラ連鎖が壊れずに捕捉され、Supervisor に正しく `DOWN` 通知が届くことを検証。
2. **Linux 実機検証パイプラインの整備**:
   - `make -C ulisp test_concurrency_stress` を整備し、複数スレッドでの高頻度マイグレーション・例外発生テストを 10,000 サイクル実行可能にする。
   - arm64 環境からでも再現可能なコンテナビルドまたは Linux CI 上での自動実行を義務化する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 異ワーカー間でのコルーチン再開＋例外発生テストが作成され、正常にパスすること。
- [ ] Linux x86-64 環境において並行ストレステストが自動実行され、デッドロックや未捕捉例外が 0 件であること。
- [ ] CI パイプラインでクロスプラットフォーム（Linux x86-64 / macOS arm64）の自動回帰テストが確立されていること。

