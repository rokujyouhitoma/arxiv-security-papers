---
ID: 823
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] uLisp テストスイート表示形式の SRFI 64 統一フォーマッタ導入とログ出力整流化 (ID: 823)

## 1. 概要 / Summary
uLisp の各種テストスイート（Nanopass 単体テスト、ネイティブ ELF コンパイルテスト、JIT/Pass Manager テスト、Synapse 並行性テスト）において、実行時および完了時の出力表示形式が不揃いになっている。
具体的には：
1. ネイティブ ELF テストは古典的 SRFI 64 のサイレント仕様により終了時に `# of expected passes ...` のみを出力する一方、テストファイル独自に手動で `display` された見出しバナー（`=== Running ... ===` や `--- Group N: ---`）が散在している。
2. Nanopass 単体テスト群 (`common.scm`) は全件 `  [PASS] <name>` を `=======================================================` の等号線で囲んで出力し、表示フォーマットがネイティブ側と乖離している。
3. Synapse 並行性パステスト (`tests/concurrency/test_pass_*.scm`) は自前で独自のアサーション関数とバナーを定義しており、共通ハーネスと未統合である。
4. `Makefile` 内の各テストターゲットで個別に `echo` される見出しや完了メッセージの書式（`=== Running ... ===`、`SUCCESS: ...`、`--- Testing ... ---`）が不統一である。

本イシューでは、SRFI 64 カスタムテストランナー機構 (`test-runner-factory` / `test-runner-simple`) を拡張して統一フォーマッタ (`test-runner-unified`) を導入し、通常実行時（サマリーのみの簡潔出力）と詳細実行時（`ULISP_TEST_VERBOSE=1` 設定時の全件パス出力）の切り替えに対応する。
また、手動 `display` の全廃、並行性パステストの `common.scm` 統合、および `Makefile` ログ出力の整流化を完了し、テストスイート全体の視認性・一貫性を極限まで高める。

---

## 2. トレーサビリティ / Traceability
- **R7RS-large / SRFI 64**: Test Suites and Custom Test Runners (§2 Default & Null Test Runners, §3 Simple Runner Callbacks, §4 Result Properties)
- **R7RS-large / SRFI 78**: Lightweight Testing (§2 `check` and `check-report` formatting)
- **R7RS-large / SRFI 252**: Property Testing (§3 Test Runner integration)
- **先行イシュー**:
  - [819-implement-srfi-64-test-suites-library-and-custom-test-runners.md](closed/819-implement-srfi-64-test-suites-library-and-custom-test-runners.md) (SRFI 64 テストスイート標準ライブラリとカスタムランナー)
  - [820-implement-srfi-78-lightweight-testing-library.md](closed/820-implement-srfi-78-lightweight-testing-library.md) (SRFI 78 軽量テストライブラリと SRFI 64 連携)
  - [821-implement-srfi-252-property-based-testing-library.md](closed/821-implement-srfi-252-property-based-testing-library.md) (SRFI 252 プロパティテストと決定論的ジェネレータ)
  - [822-unify-existing-test-suites-to-srfi-64-and-update-compliance-docs.md](closed/822-unify-existing-test-suites-to-srfi-64-and-update-compliance-docs.md) (既存テストスイートの SRFI 64 統一・引数順序是正)
- **設計ガイド**:
  - [ulisp/docs/guide_testing.md](../../ulisp/docs/guide_testing.md) (Layer 11: R7RS / SRFI 規格準拠テストスイート)
  - [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (Section 4.1 Test Suites)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### A. テストランナー・マクロ・共通ハーネス基盤 (4ファイル)
- [x] [ulisp/lib/test.scm](../../ulisp/lib/test.scm) (SRFI 64 統一カスタムテストランナー `test-runner-unified` 実装、バナー・サマリー出力整流化、Verboseモード対応)
- [x] [ulisp/lib/stdlib_macros.scm](../../ulisp/lib/stdlib_macros.scm) (モジュラーコンパイル環境向け SRFI 64 マクロの出力コールバック同期)
- [x] [ulisp/tests/passes/common.scm](../../ulisp/tests/passes/common.scm) (Nanopass 共通ハーネスの出力スタイルを `test.scm` と同期、Verboseモード対応)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (テストターゲットの `echo` バナー・成否メッセージの書式統一)

### B. ネイティブ ELF 実行 SRFI 64 テストスイート（手動バナー削除・統一ランナー適用）(15ファイル)
- [x] [ulisp/tests/test_numeric_tower.scm](../../ulisp/tests/test_numeric_tower.scm)
- [x] [ulisp/tests/test_char.scm](../../ulisp/tests/test_char.scm)
- [x] [ulisp/tests/test_exceptions.scm](../../ulisp/tests/test_exceptions.scm)
- [x] [ulisp/tests/test_file_port.scm](../../ulisp/tests/test_file_port.scm)
- [x] [ulisp/tests/test_case_lambda.scm](../../ulisp/tests/test_case_lambda.scm)
- [x] [ulisp/tests/test_record.scm](../../ulisp/tests/test_record.scm)
- [x] [ulisp/tests/test_scheme_runtime.scm](../../ulisp/tests/test_scheme_runtime.scm)
- [x] [ulisp/tests/test_srfi1.scm](../../ulisp/tests/test_srfi1.scm)
- [x] [ulisp/tests/test_string_to_number.scm](../../ulisp/tests/test_string_to_number.scm)
- [x] [ulisp/tests/test_srfi_64.scm](../../ulisp/tests/test_srfi_64.scm)
- [x] [ulisp/tests/test_srfi_78.scm](../../ulisp/tests/test_srfi_78.scm)
- [x] [ulisp/tests/test_srfi_252.scm](../../ulisp/tests/test_srfi_252.scm)
- [x] [tests/concurrency/test_arena.scm](../../tests/concurrency/test_arena.scm)
- [x] [tests/concurrency/test_atomic.scm](../../tests/concurrency/test_atomic.scm)
- [x] [tests/concurrency/test_queue.scm](../../tests/concurrency/test_queue.scm)

### C. Synapse 並行性パステスト（common.scm 統合・独自アサーション排除）(5ファイル)
- [x] [tests/concurrency/test_pass_split_planes.scm](../../tests/concurrency/test_pass_split_planes.scm)
- [x] [tests/concurrency/test_pass_check_affine.scm](../../tests/concurrency/test_pass_check_affine.scm)
- [x] [tests/concurrency/test_pass_fbip.scm](../../tests/concurrency/test_pass_fbip.scm)
- [x] [tests/concurrency/test_pass_inline_hotpath.scm](../../tests/concurrency/test_pass_inline_hotpath.scm)
- [x] [tests/concurrency/test_pass_inject_safepoints.scm](../../tests/concurrency/test_pass_inject_safepoints.scm)

### D. Nanopass 単体テスト群（共通ハーネス common.scm 連携検証・重複除去確認）(39ファイル)
- [x] [ulisp/tests/passes/test_000_compiler_diagnostics.scm](../../ulisp/tests/passes/test_000_compiler_diagnostics.scm)
- [x] [ulisp/tests/passes/test_power_assert.scm](../../ulisp/tests/passes/test_power_assert.scm)
- [x] [ulisp/tests/passes/test_traceback.scm](../../ulisp/tests/passes/test_traceback.scm)
- [x] [ulisp/tests/passes/test_010_library.scm](../../ulisp/tests/passes/test_010_library.scm)
- [x] [ulisp/tests/passes/test_015_dsl_expander.scm](../../ulisp/tests/passes/test_015_dsl_expander.scm)
- [x] [ulisp/tests/passes/test_020_macro_expander.scm](../../ulisp/tests/passes/test_020_macro_expander.scm)
- [x] [ulisp/tests/passes/test_025_top_level.scm](../../ulisp/tests/passes/test_025_top_level.scm)
- [x] [ulisp/tests/passes/test_026_desugar_constructors.scm](../../ulisp/tests/passes/test_026_desugar_constructors.scm)
- [x] [ulisp/tests/passes/test_027_desugar_conditionals.scm](../../ulisp/tests/passes/test_027_desugar_conditionals.scm)
- [x] [ulisp/tests/passes/test_028_desugar_bindings.scm](../../ulisp/tests/passes/test_028_desugar_bindings.scm)
- [x] [ulisp/tests/passes/test_029_desugar_dynamic.scm](../../ulisp/tests/passes/test_029_desugar_dynamic.scm)
- [x] [ulisp/tests/passes/test_030_desugar.scm](../../ulisp/tests/passes/test_030_desugar.scm)
- [x] [ulisp/tests/passes/test_040_analysis.scm](../../ulisp/tests/passes/test_040_analysis.scm)
- [x] [ulisp/tests/passes/test_050_cp0.scm](../../ulisp/tests/passes/test_050_cp0.scm)
- [x] [ulisp/tests/passes/test_060_lvn.scm](../../ulisp/tests/passes/test_060_lvn.scm)
- [x] [ulisp/tests/passes/test_070_anf.scm](../../ulisp/tests/passes/test_070_anf.scm)
- [x] [ulisp/tests/passes/test_080_annotator.scm](../../ulisp/tests/passes/test_080_annotator.scm)
- [x] [ulisp/tests/passes/test_090_rtyper.scm](../../ulisp/tests/passes/test_090_rtyper.scm)
- [x] [ulisp/tests/passes/test_100_contify.scm](../../ulisp/tests/passes/test_100_contify.scm)
- [x] [ulisp/tests/passes/test_110_closure_convert.scm](../../ulisp/tests/passes/test_110_closure_convert.scm)
- [x] [ulisp/tests/passes/test_120_alias_escape.scm](../../ulisp/tests/passes/test_120_alias_escape.scm)
- [x] [ulisp/tests/passes/test_123_lir_closures.scm](../../ulisp/tests/passes/test_123_lir_closures.scm)
- [x] [ulisp/tests/passes/test_124_lir_call_abi.scm](../../ulisp/tests/passes/test_124_lir_call_abi.scm)
- [x] [ulisp/tests/passes/test_125_lir_continuation.scm](../../ulisp/tests/passes/test_125_lir_continuation.scm)
- [x] [ulisp/tests/passes/test_126_lir_control.scm](../../ulisp/tests/passes/test_126_lir_control.scm)
- [x] [ulisp/tests/passes/test_127_lir_runtime.scm](../../ulisp/tests/passes/test_127_lir_runtime.scm)
- [x] [ulisp/tests/passes/test_128_lir_branch_fusion.scm](../../ulisp/tests/passes/test_128_lir_branch_fusion.scm)
- [x] [ulisp/tests/passes/test_129_lir_primitives.scm](../../ulisp/tests/passes/test_129_lir_primitives.scm)
- [x] [ulisp/tests/passes/test_130_lir.scm](../../ulisp/tests/passes/test_130_lir.scm)
- [x] [ulisp/tests/passes/test_131_lir_safepoint.scm](../../ulisp/tests/passes/test_131_lir_safepoint.scm)
- [x] [ulisp/tests/passes/test_132_lir_braun_ssa.scm](../../ulisp/tests/passes/test_132_lir_braun_ssa.scm)
- [x] [ulisp/tests/passes/test_133_lir_peephole.scm](../../ulisp/tests/passes/test_133_lir_peephole.scm)
- [x] [ulisp/tests/passes/test_140_backend_x86_64.scm](../../ulisp/tests/passes/test_140_backend_x86_64.scm)
- [x] [ulisp/tests/passes/test_141_backend_x86_gc.scm](../../ulisp/tests/passes/test_141_backend_x86_gc.scm)
- [x] [ulisp/tests/passes/test_142_backend_x86_freestanding.scm](../../ulisp/tests/passes/test_142_backend_x86_freestanding.scm)
- [x] [ulisp/tests/passes/test_143_backend_x86_peephole.scm](../../ulisp/tests/passes/test_143_backend_x86_peephole.scm)
- [x] [ulisp/tests/passes/test_150_backend_aarch64.scm](../../ulisp/tests/passes/test_150_backend_aarch64.scm)
- [x] [ulisp/tests/passes/test_160_backend_c.scm](../../ulisp/tests/passes/test_160_backend_c.scm)
- [x] [ulisp/tests/passes/test_extern_symbols.scm](../../ulisp/tests/passes/test_extern_symbols.scm)

### E. 単体実行用・派生パス単体テスト (12ファイル)
- [x] [ulisp/tests/passes/test_alias_escape.scm](../../ulisp/tests/passes/test_alias_escape.scm)
- [x] [ulisp/tests/passes/test_annotator.scm](../../ulisp/tests/passes/test_annotator.scm)
- [x] [ulisp/tests/passes/test_branch_fusion.scm](../../ulisp/tests/passes/test_branch_fusion.scm)
- [x] [ulisp/tests/passes/test_contify.scm](../../ulisp/tests/passes/test_contify.scm)
- [x] [ulisp/tests/passes/test_inplace_shuffle.scm](../../ulisp/tests/passes/test_inplace_shuffle.scm)
- [x] [ulisp/tests/passes/test_library.scm](../../ulisp/tests/passes/test_library.scm)
- [x] [ulisp/tests/passes/test_lir.scm](../../ulisp/tests/passes/test_lir.scm)
- [x] [ulisp/tests/passes/test_loop_register_allocation.scm](../../ulisp/tests/passes/test_loop_register_allocation.scm)
- [x] [ulisp/tests/passes/test_lvn.scm](../../ulisp/tests/passes/test_lvn.scm)
- [x] [ulisp/tests/passes/test_rtyper.scm](../../ulisp/tests/passes/test_rtyper.scm)
- [x] [ulisp/tests/passes/test_stackmap.scm](../../ulisp/tests/passes/test_stackmap.scm)
- [x] [ulisp/tests/passes/test_toplevel_direct_call.scm](../../ulisp/tests/passes/test_toplevel_direct_call.scm)

### F. Pass Manager / JIT 単体テスト（フォーマット整合性確認）(9ファイル)
- [x] [ulisp/tests/test_pass_manager.scm](../../ulisp/tests/test_pass_manager.scm)
- [x] [ulisp/tests/test_passes.scm](../../ulisp/tests/test_passes.scm)
- [x] [ulisp/tests/jit/test_delimcc.scm](../../ulisp/tests/jit/test_delimcc.scm)
- [x] [ulisp/tests/jit/test_tracer.scm](../../ulisp/tests/jit/test_tracer.scm)
- [x] [ulisp/tests/jit/test_auto_instrument.scm](../../ulisp/tests/jit/test_auto_instrument.scm)
- [x] [ulisp/tests/jit/test_optimizer.scm](../../ulisp/tests/jit/test_optimizer.scm)
- [x] [ulisp/tests/jit/test_bridge.scm](../../ulisp/tests/jit/test_bridge.scm)
- [x] [ulisp/tests/jit/test_examples.scm](../../ulisp/tests/jit/test_examples.scm)
- [x] [ulisp/tests/jit/test_guard_elimination.scm](../../ulisp/tests/jit/test_guard_elimination.scm)

### G. ドキュメント (2ファイル)
- [x] [ulisp/docs/guide_testing.md](../../ulisp/docs/guide_testing.md) (Layer 11 にテスト出力フォーマット規格および Verbose モード仕様を追記)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (Issue #823 のトレーサビリティエントリ追記)

### H. Synapse 並行性ランタイムテスト群（手動 PASS/FAIL 排除・SRFI 64 統一）(17ファイル)
- [x] [tests/concurrency/test_channel.scm](../../tests/concurrency/test_channel.scm)
- [x] [tests/concurrency/test_boundary.scm](../../tests/concurrency/test_boundary.scm)
- [x] [tests/concurrency/test_epoch.scm](../../tests/concurrency/test_epoch.scm)
- [x] [tests/concurrency/test_context_switch.scm](../../tests/concurrency/test_context_switch.scm)
- [x] [tests/concurrency/test_scheduler.scm](../../tests/concurrency/test_scheduler.scm)
- [x] [tests/concurrency/test_multithread_scheduler.scm](../../tests/concurrency/test_multithread_scheduler.scm)
- [x] [tests/concurrency/test_links_monitors.scm](../../tests/concurrency/test_links_monitors.scm)
- [x] [tests/concurrency/test_task_mailbox.scm](../../tests/concurrency/test_task_mailbox.scm)
- [x] [tests/concurrency/test_let_it_crash.scm](../../tests/concurrency/test_let_it_crash.scm)
- [x] [tests/concurrency/test_supervisor.scm](../../tests/concurrency/test_supervisor.scm)
- [x] [tests/concurrency/test_futex.scm](../../tests/concurrency/test_futex.scm)
- [x] [tests/concurrency/test_registry.scm](../../tests/concurrency/test_registry.scm)
- [x] [tests/concurrency/test_crash_logger.scm](../../tests/concurrency/test_crash_logger.scm)
- [x] [tests/concurrency/test_io_uring.scm](../../tests/concurrency/test_io_uring.scm)
- [x] [tests/concurrency/test_preemption.scm](../../tests/concurrency/test_preemption.scm)
- [x] [tests/concurrency/test_eval_adapter.scm](../../tests/concurrency/test_eval_adapter.scm)
- [x] [tests/concurrency/concurrency_harness.scm](../../tests/concurrency/concurrency_harness.scm)

### I. ネイティブ R7RS / コア / GC テスト群（手動 PASS/FAIL 排除・SRFI 64 統一）(19ファイル)
- [x] [ulisp/tests/test_values.scm](../../ulisp/tests/test_values.scm)
- [x] [ulisp/tests/test_call_cc.scm](../../ulisp/tests/test_call_cc.scm)
- [x] [ulisp/tests/test_eqv.scm](../../ulisp/tests/test_eqv.scm)
- [x] [ulisp/tests/test_syntax_rules.scm](../../ulisp/tests/test_syntax_rules.scm)
- [x] [ulisp/tests/test_ports.scm](../../ulisp/tests/test_ports.scm)
- [x] [ulisp/tests/test_promise.scm](../../ulisp/tests/test_promise.scm)
- [x] [ulisp/tests/test_stdlib_r7rs.scm](../../ulisp/tests/test_stdlib_r7rs.scm)
- [x] [ulisp/tests/test_base_procedures.scm](../../ulisp/tests/test_base_procedures.scm)
- [x] [ulisp/tests/test_hashtable.scm](../../ulisp/tests/test_hashtable.scm)
- [x] [ulisp/tests/test_letrec_star.scm](../../ulisp/tests/test_letrec_star.scm)
- [x] [ulisp/tests/test_max_min.scm](../../ulisp/tests/test_max_min.scm)
- [x] [ulisp/tests/test_format.scm](../../ulisp/tests/test_format.scm)
- [x] [ulisp/tests/test_sort.scm](../../ulisp/tests/test_sort.scm)
- [x] [ulisp/tests/test_printer.scm](../../ulisp/tests/test_printer.scm)
- [x] [ulisp/tests/test_process_context.scm](../../ulisp/tests/test_process_context.scm)
- [x] [ulisp/tests/test_gc_growth.scm](../../ulisp/tests/test_gc_growth.scm)
- [x] [ulisp/tests/test_gc_profile.scm](../../ulisp/tests/test_gc_profile.scm)
- [x] [ulisp/tests/test_gc_hybrid.scm](../../ulisp/tests/test_gc_hybrid.scm)
- [x] [ulisp/tests/test_gc_stress.scm](../../ulisp/tests/test_gc_stress.scm)

### J. コンパイラ検証・診断テスト群（出力整流化）(4ファイル)
- [x] [ulisp/tests/test_reader_eof.scm](../../ulisp/tests/test_reader_eof.scm)
- [x] [ulisp/tests/test_scope.scm](../../ulisp/tests/test_scope.scm)
- [x] [ulisp/tests/test_include_source_loc.scm](../../ulisp/tests/test_include_source_loc.scm)
- [x] [ulisp/tests/test_pass_profiler.sh](../../ulisp/tests/test_pass_profiler.sh)

### K. Nanopass コンパイラ検証スイート（common.scm 統合・SRFI 64 統一）(3ファイル)
- [x] [ulisp/tests/test_pass_manager.scm](../../ulisp/tests/test_pass_manager.scm)
- [x] [ulisp/tests/test_backend_aarch64.scm](../../ulisp/tests/test_backend_aarch64.scm)
- [x] [ulisp/tests/test_dataflow.scm](../../ulisp/tests/test_dataflow.scm)

### L. JIT コンポーネントテストスイート（common.scm 統合・SRFI 64 統一）(7ファイル)
- [x] [ulisp/tests/jit/test_delimcc.scm](../../ulisp/tests/jit/test_delimcc.scm)
- [x] [ulisp/tests/jit/test_tracer.scm](../../ulisp/tests/jit/test_tracer.scm)
- [x] [ulisp/tests/jit/test_auto_instrument.scm](../../ulisp/tests/jit/test_auto_instrument.scm)
- [x] [ulisp/tests/jit/test_optimizer.scm](../../ulisp/tests/jit/test_optimizer.scm)
- [x] [ulisp/tests/jit/test_guard_elimination.scm](../../ulisp/tests/jit/test_guard_elimination.scm)
- [x] [ulisp/tests/jit/test_bridge.scm](../../ulisp/tests/jit/test_bridge.scm)
- [x] [ulisp/tests/jit/test_examples.scm](../../ulisp/tests/jit/test_examples.scm)

### M. シェルスクリプト統合テストスイート（統一バナー・サマリー出力）(3ファイル)
- [x] [ulisp/tests/test_cli_diagnostics.sh](../../ulisp/tests/test_cli_diagnostics.sh)
- [x] [ulisp/tests/test_pass_profiler.sh](../../ulisp/tests/test_pass_profiler.sh)
- [x] [ulisp/tests/test_gc_stats.sh](../../ulisp/tests/test_gc_stats.sh)

### N. 不要・非標準手動バナー残存ファイルのクリーンアップ (18ファイル)
- [x] [ulisp/tests/test_process_context.scm](../../ulisp/tests/test_process_context.scm)
- [x] [ulisp/tests/test_gc_profile.scm](../../ulisp/tests/test_gc_profile.scm)
- [x] [ulisp/tests/test_gc_hybrid.scm](../../ulisp/tests/test_gc_hybrid.scm)
- [x] [ulisp/tests/test_gc_stress.scm](../../ulisp/tests/test_gc_stress.scm)
- [x] [ulisp/tests/test_format.scm](../../ulisp/tests/test_format.scm)
- [x] [ulisp/tests/test_sort.scm](../../ulisp/tests/test_sort.scm)
- [x] [ulisp/tests/passes/test_stackmap.scm](../../ulisp/tests/passes/test_stackmap.scm)
- [x] [ulisp/tests/passes/test_141_backend_x86_gc.scm](../../ulisp/tests/passes/test_141_backend_x86_gc.scm)
- [x] [ulisp/tests/test_promise.scm](../../ulisp/tests/test_promise.scm)
- [x] [ulisp/tests/test_r7rs_cond_expand.scm](../../ulisp/tests/test_r7rs_cond_expand.scm)
- [x] [ulisp/tests/test_srfi_145_assume.scm](../../ulisp/tests/test_srfi_145_assume.scm)
- [x] [ulisp/tests/test_r7rs_time.scm](../../ulisp/tests/test_r7rs_time.scm)
- [x] [ulisp/tests/test_srfi_111_boxes.scm](../../ulisp/tests/test_srfi_111_boxes.scm)
- [x] [ulisp/tests/test_comparator.scm](../../ulisp/tests/test_comparator.scm)
- [x] [ulisp/tests/test_srfi_252.scm](../../ulisp/tests/test_srfi_252.scm)
- [x] [ulisp/tests/test_r7rs_bytevector_ports.scm](../../ulisp/tests/test_r7rs_bytevector_ports.scm)
- [x] [ulisp/tests/test_set.scm](../../ulisp/tests/test_set.scm)
- [x] [ulisp/tests/test_srfi_141_division.scm](../../ulisp/tests/test_srfi_141_division.scm)
- [x] [ulisp/tests/test_eval_load_repl.scm](../../ulisp/tests/test_eval_load_repl.scm)
- [x] [ulisp/tests/test_srfi_78.scm](../../ulisp/tests/test_srfi_78.scm)
- [x] [ulisp/tests/test_r7rs_include_ci.scm](../../ulisp/tests/test_r7rs_include_ci.scm)
- [x] [ulisp/tests/test_srfi_41_streams.scm](../../ulisp/tests/test_srfi_41_streams.scm)
- [x] [ulisp/tests/test_let_syntax.scm](../../ulisp/tests/test_let_syntax.scm)
- [x] [ulisp/tests/test_generator.scm](../../ulisp/tests/test_generator.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/823-unify-test-runner-output-formats-and-add-verbose-mode`

### Step 1: 統一テストランナー (`test-runner-unified`) の設計と実装
1. **`ulisp/lib/test.scm` の拡張**:
   - `test-runner-unified` 手続きを新設し、`test-runner-factory` のデフォルトに設定。
   - 環境変数 `ULISP_TEST_VERBOSE` の取得（`get-environment-variable "ULISP_TEST_VERBOSE"`。取得不可または未定義時は `#f`）。
   - コールバック仕様：
     - **`test-on-group-begin`**:
       `test-begin` 呼び出し時にグループスタック深さ 1 の場合（トップレベルスイート開始時）：
       ```text
       === [Test Suite: <suite-name>] ===
       ```
       を出力。
     - **`test-on-test-end`**:
       - 成功 (`pass`) 時:
         - `ULISP_TEST_VERBOSE=1` の場合: `  [PASS] <test-name>` を出力。
         - 通常時（デフォルト）: 何も出力しない（サイレント）。
       - 予期された失敗 (`xfail`) 時: `  [XFAIL] <test-name>` を出力。
       - 失敗 (`fail`) または予期せぬ成功 (`xpass`) 時:
         - モードに関わらず赤字またはハイライトで失敗詳細を出力：
           ```text
             [FAIL] <test-name>
               Expected: <expected-value>
               Actual:   <actual-value>
           ```
     - **`test-on-final`**:
       スイート完了時（`test-end` 実行時）：
       ```text
       -------------------------------------------------------
        [RESULT] <suite-name>: X passed, Y failed, Z skipped (Total: N)
       -------------------------------------------------------
       ```
       ※ 全件成功（fail=0, xpass=0）時はグリーン調の `[PASS]` / `[RESULT]`、失敗検知時は `[FAIL]` を明示。

### Step 2: モジュラーコンパイルマクロ (`ulisp/lib/stdlib_macros.scm`) への同期
- ネイティブ ELF リンク時に `test-begin`, `test-end`, `test-assert`, `test-equal` 等が `test-runner-unified` のコールバックを自動起動できるようにマクロ展開コードを整理。

### Step 3: Nanopass 共通ハーネス (`ulisp/tests/passes/common.scm`) の出力スタイル整合
- `common.scm` の `test-begin` / `test-end` / `assert-report` の出力を、SRFI 64 統一ランナーと同一のフォーマット・境界線スタイル（`=== [Test Suite: ...] ===` および `[RESULT] ...`）に調和。
- `ULISP_TEST_VERBOSE` の有無を判定し、デフォルトではスイートごとの要約サマリーのみを出力、`ULISP_TEST_VERBOSE=1` 時に全 785 件のアサーション行を表示するように切り替え可能化。

### Step 4: Synapse 並行性パステスト (5ファイル) の `common.scm` 統合
- `tests/concurrency/test_pass_*.scm` にハードコードされた手動の `(display "======================")` および重複した `assert-true` / `assert-false` / `*test-count*` の cons セル定義を完全撤去。
- `common.scm` をロードして SRFI 64 標準形式 `(test-begin ...)`, `(test-assert ...)`, `(test-end ...)` に一本化。
- `ulisp/Makefile` の各ターゲット (`test_pass_split_planes`, `test_pass_check_affine`, `test_pass_fbip`, `test_pass_inline_hotpath`, `test_pass_inject_safepoints`) に `$(PASS_COMMON)` を依存として明記。

### Step 5: ネイティブテストファイル内の手動 `display` 撤去
- `test_char.scm`, `test_srfi1.scm`, `test_srfi_64.scm`, `test_srfi_78.scm`, `test_srfi_252.scm`, `test_arena.scm`, `test_atomic.scm`, `test_queue.scm` 内に残る手動の `(display "=== Running ... ===\n")` および `(display "--- Group N: ---")` を削除し、テストランナーの `test-begin` / `test-group` に委任。

### Step 6: `ulisp/Makefile` のログ出力整流化
- `Makefile` 内の各テストターゲットにおいて、テスト実行コマンド自体の直前に重複して出力されている `echo "=== Running ... ==="` や `echo "SUCCESS: ..."` を整理し、二重出力・表記ゆれを解消。

### Step 7: ドキュメントの改訂
- `ulisp/docs/guide_testing.md` の「Layer 11: R7RS / SRFI 規格準拠テストスイート」に「テストランナー出力フォーマット規約と Verbose モード」のセクションを追加。
- `ulisp/docs/ref_r7rs_compliance.md` に Issue #823 のエントリを記録。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] **統一テストランナー**: `ulisp/lib/test.scm` に `test-runner-unified` が実装され、`test-runner-factory` のデフォルトとして機能すること。
- [x] **出力フォーマットの一貫性**:
  - トップレベルスイート開始時に `=== [Test Suite: <name>] ===` が出力されること。
  - スイート完了時に `-------------------------------------------------------` および `[RESULT] <name>: X passed ...` が出力されること。
  - 失敗時に `[FAIL]` および期待値／実測値の詳細が必ず出力されること。
- [x] **Verbose モードの動作検証**:
  - デフォルト実行時: アサーション行が抑制され、サマリーのみが簡潔に出力されること。
  - `ULISP_TEST_VERBOSE=1` 実行時: 個々のアサーションごとに `  [PASS] <name>` が表示されること。
- [x] **Synapse 並行性パステストの統合**:
  - `tests/concurrency/test_pass_*.scm` (5ファイル) から重複ボイラープレートが排除され、`common.scm` 経由で実行されること。
- [x] **テストファイル内手動バナーの完全削除**:
  - `test_char.scm`, `test_srfi1.scm`, `test_srfi_64.scm`, `test_srfi_78.scm`, `test_srfi_252.scm` 等から手動 `display` が排除されていること。
- [x] **全テスト 100% PASS**:
  - `make -C ulisp lint_sexpr` が 100% PASS すること。
  - `python3 scripts/verify_r7rs_traceability.py` が 100% PASS すること。
  - `make -C ulisp test_all_passes` が 39 パス全件 PASS すること。
  - `make -C ulisp test` (全モジュラーおよび並行性テスト) が 100% PASS すること。
- [x] **リポジトリ全体トリプル品質ゲート**:
  - `make format`: エラー 0 件
  - `make static_analysis`: エラー 0 件
  - `make test`: カバレッジ 80% 以上を維持して 100% PASS
- [x] **仕様準拠ドキュメント更新**:
  - `ulisp/docs/guide_testing.md` および `ulisp/docs/ref_r7rs_compliance.md` が最新化されていること。
