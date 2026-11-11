---
ID: 806
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Nanopass AOT コンパイラによる軽量タスク Spawn の直接インライン展開とクロージャ呼出し排除 (ID: 806)

## 1. 概要 / Summary
Synapse の線形チャネルにおいて、Nanopass AOT 最適化パス（`pass_inline_hotpath.scm`）による直接インライン展開により、メッセージ送受信ペア遅延を 38.5ns（1,289万 msgs/sec）まで極小化し、Go の channel（34ns）に肉薄する性能を達成した。
同様のコンパイラ最適化をマイクロタスクの生成・ディスパッチ（`scheduler-spawn!`）にも導入する。
キャプチャ変数のない軽量タスク（引数なし thunk）、または単純なアキュムレータ更新タスクに対し、`<task-context>` を介した汎用クロージャ動的呼び出し（間接 call）をバイパスし、生の関数ポインタへの直接ジャンプ（`jmp`）およびインライン実行コードを生成する。これにより、タスク呼び出し時のスタックフレーム構築およびクロージャディスパッチコストを極限まで排除する。

---

## 2. トレーサビリティ / Traceability
- [Issue #688: Nanopass AOT Inlining for Channel Hotpaths](closed/688-implement-nanopass-aot-inlining-for-channel-hotpaths.md)
- [concurrency_evaluation.md](../benchmarks/concurrency_evaluation.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/ulisp/concurrency/passes/pass_inline_hotpath.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_inline_hotpath.scm) - `scheduler-spawn!` 呼び出しサイトの検知と軽量タスクインライン展開
- [ ] [ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm) - 直接ディスパッチ対応のタスク実行ハンドラ
- [ ] [tests/concurrency/test_pass_inline_hotpath.scm](../../tests/concurrency/test_pass_inline_hotpath.scm) - タスク spawn インライン展開の AST/LIR 検証
- [ ] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm) - インラインタスクの極小実行レイテンシ測定

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/806-implement-nanopass-aot-inlining-for-lightweight-task-spawning`

1. `pass_inline_hotpath.scm` において、`(scheduler-spawn! sched (lambda () ...))` の呼び出しパターンを検出。
2. ラムダが閉包変数をキャプチャしない静的関数である場合、`<task-context>` に直接ネイティブ関数ラベルまたはインライン展開コードを埋め込む。
3. タスク実行ホットパス（`scheduler-execute-task!`）において、クロージャ呼出しをバイパスして直接ネイティブ呼び出しを行う。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `pass_inline_hotpath.scm` が軽量タスクの spawn を認識し、インライン化または直接関数ポインタ呼び出しコードを生成すること。
- [ ] タスクディスパッチのクロージャオーバーヘッドが排除され、タスク実行単体レイテンシが短縮されること。
- [ ] コンパイラテストおよび並行性回帰テストが全件 PASS すること。

