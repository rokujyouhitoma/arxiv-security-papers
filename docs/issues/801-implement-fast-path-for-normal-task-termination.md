---
ID: 801
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/PERF] 正常終了タスク向け Fast-path Termination による実行フェーズオーバーヘッドの削減 (ID: 801)

## 1. 概要 / Summary
Synapse のタスク終了処理 `task-handle-termination!`（`links.scm:230-293`）では、タスクが正常終了（`reason == 'normal`）した場合であっても、以下の重厚な処理が無差別に実行されている：
1. 終了理由シンボルに対する `(channel-deep-copy reason)`
2. 空リストであっても毎回実行される `atomic-swap!`（monitors box, links box）
3. 保有チャネルの解放走査
4. プロセスレジストリの登録解除フック呼び出し
5. 例外ガード付きのタスクテーブル削除

しかし、ベンチマークや実稼働で大量に生成・消化されるマイクロタスクの大多数は、リンクや監視を持たず、チャネルを保有せず、正常終了（`'normal`）する。
これらのタスクに対して毎回ディープコピーや多段階の atomic-swap を走らせることは、実行時間（11/03 の 22ms から 11/07 の 106ms へ約4.8倍悪化）の主要な上乗せ要因となっている。
本 Issue では、正常終了かつ monitor/link/owned-channels が存在しないタスク向けに、不要なディープコピーや box swap を全スキップして直ちにタスク状態を `terminated` に更新し、テーブルから削除して返却する「Fast-path Normal Exit」を導入する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [concurrency_evaluation.md](../../docs/benchmarks/concurrency_evaluation.md)
- 関連 Issue: [794-optimize-task-table-to-o1-slot-array-and-eliminate-quadratic-spawn-overhead.md](794-optimize-task-table-to-o1-slot-array-and-eliminate-quadratic-spawn-overhead.md), [800-implement-lazy-allocation-for-task-context-atomic-boxes.md](800-implement-lazy-allocation-for-task-context-atomic-boxes.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/links.scm](../../ulisp/runtime/concurrency/links.scm) - `task-handle-termination!`
- [ ] [tests/concurrency/test_channel.scm](../../tests/concurrency/test_channel.scm) - 正常終了タスクの単体テスト
- [ ] [docs/benchmarks/concurrency_evaluation.md](../../docs/benchmarks/concurrency_evaluation.md) - 実行フェーズ計測

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/801-implement-fast-path-for-normal-task-termination`

1. **Fast-path 判定条件の追加**:
   - `reason` が `'normal`（または即値）であるかを検査。
   - `(task-monitored-by-box task)`, `(task-links-box task)`, `(task-owned-channels-box task)` が `#f` または空リストであるかを検査。
2. **Fast-path 実行ロジック**:
   - ディープコピーをバイパス。
   - `task-state-set!` を `terminated`、`task-reductions-set!` を 0 に即時設定。
   - `task-table-unregister!` のみを呼び出して即座にリターン。
3. **Slow-path（異常終了・リンク監視あり）との分離**:
   - クラッシュや監視が存在する場合は既存の安全なカスケード通知・Poisoning 処理を完全に維持。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] リンク・監視を持たない正常終了マイクロタスクが Fast-path を通過すること。
- [ ] 10万タスクの実行フェーズ所要時間（106 ms）が大幅に短縮（目標 <30 ms）されること。
- [ ] クラッシュ時やリンクが存在するタスクの異常終了通知機能にリグレッションがないこと。

