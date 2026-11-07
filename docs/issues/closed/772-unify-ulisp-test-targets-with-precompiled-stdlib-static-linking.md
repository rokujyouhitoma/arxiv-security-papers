---
ID: 772
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] ULisp 標準ライブラリ (ULISP_STD_LIBS) の事前コンパイル済みオブジェクト化と分割静的リンクへの統一 (ID: 772)

## 1. 概要 / Summary

[ulisp/Makefile](../../../ulisp/Makefile) の各ランタイム・並行処理・R7RS テストターゲット（`test_runtime`, `test_arena`, `test_scheduler`, `test_numeric_tower` 等）において、毎回 `cat $(ULISP_STD_LIBS) test_xxx.scm > build/test_xxx_input.scm` によって **28個の標準ライブラリファイルを結合し、ゼロから全 Nanopass パイプラインで再コンパイルしている問題** を解消した。

標準ライブラリを1回だけ事前コンパイルしたオブジェクトファイル（`build/ulisp_stdlib.o`）を共通依存として確立し、各テスト・アプリケーションは差分コードのみ（`(!allow-extern #t)` 付き）および共通マクロ・定数定義（[`ulisp/lib/stdlib_macros.scm`](../../../ulisp/lib/stdlib_macros.scm)）を結合してコンパイルし、`ld` で静的リンクする方式へ統一することで、テストごとのコンパイル時間を十数秒から 0.1〜0.3 秒前後へ劇的に短縮（約 50〜100 倍高速化）した。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33] ULISP 包括設計仕様書](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
- 依存関係:
  - 先行・関連 Issue: [Issue #607](607-implement-modular-2-split-static-linking-for-ulisp-stdlib-and-compiler.md), [Issue #608](608-implement-separate-compilation-and-incremental-build-for-ulisp.md), [Issue #771](771-optimize-ulisp-host-compiler-seed-and-batch-pass-test-runner.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/Makefile](../../../ulisp/Makefile)
- [x] [ulisp/lib/stdlib_macros.scm](../../../ulisp/lib/stdlib_macros.scm)
- [x] [ulisp/runtime/concurrency/channel.scm](../../../ulisp/runtime/concurrency/channel.scm)
- [x] [ulisp/stdlib_entry.scm](../../../ulisp/stdlib_entry.scm)
- [x] [docs/issues/closed/772-unify-ulisp-test-targets-with-precompiled-stdlib-static-linking.md](772-unify-ulisp-test-targets-with-precompiled-stdlib-static-linking.md)
- [x] [docs/issues/README.md](../README.md)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/772-unify-ulisp-test-targets-with-precompiled-stdlib-static-linking`

1. **標準ライブラリオブジェクト（`build/ulisp_stdlib.o`）の共通依存化**:
   - `build/ulisp_stdlib.o` をビルドターゲットとして明示し、`ULISP_STD_LIBS`（および `stdlib_entry.scm`）に変更がない限り 1 回だけ生成して再利用する Make 依存ルールを確立。
   - `stdlib_entry.scm` に必要な標準手続きが確実に含まれるよう補完。

2. **共通マクロ・定数・リーダーテーブル定義（`lib/stdlib_macros.scm`）の新設**:
   - `(!allow-extern #t)` 単独では脱糖時にマクロ展開される手続き（`display`, `write`, `newline`, `eqv?`, `number?`, 各種数値述語）や IEEE 754 定数（`+inf.0`, `-inf.0`, `+nan.0`, `-nan.0`）、およびリーダーの文字列テーブルに必要な予約シンボル（`'vector-copy-range` 等）を `lib/stdlib_macros.scm` として抽出。

3. **各テストターゲットの差分コンパイル＋静的リンク移行**:
   - `test_runtime`, `test_arena`, `test_atomic`, `test_queue`, `test_channel`, `test_boundary`, `test_epoch`, `test_context_switch`, `test_scheduler`, `test_multithread_scheduler`, `test_links_monitors`, `test_task_mailbox`, `test_let_it_crash`, `test_supervisor`, `test_futex`, `test_registry`, `test_crash_logger`, `test_io_uring`, `test_preemption`, `test_eval_adapter`, `test_concurrency_harness`, `bench_microtasks`, `bench_latency_under_gc`, `test_numeric_tower` 等の各ターゲットにおいて：
     - `cat $(ULISP_STD_LIBS) ...` による巨大結合を廃止し、`cat lib/stdlib_macros.scm <test>.scm` の最小差分コンパイルへ変更。
     - リンク時に `build/ulisp_stdlib.o`（および `build/context.o`, `build/thread.o`, `build/futex.o`, `build/io_uring.o`）を静的結合。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `ULISP_STD_LIBS` 未変更時に 2 回目以降のテストターゲットビルドで標準ライブラリの再コンパイルがスキップされること。
- [x] 各テストターゲット（例: `test_runtime`, `test_arena`, `test_atomic`, `test_numeric_tower` 等）のコンパイルが差分ビルド＋`build/ulisp_stdlib.o` 静的リンクにより高速に完了すること（0.1s〜0.3s/テスト）。
- [x] テスト実行結果の出力・終了コードが従来と完全一致し、100% PASS すること。
- [x] `make format`, `make static_analysis`, `make test` の品質ゲートがすべて正常終了すること。
- [x] 相対リンク規約に 100% 準拠していること。
