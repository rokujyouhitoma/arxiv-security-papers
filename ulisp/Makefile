.PHONY: all test test_aot test_jit test_c test_aarch64 test_aarch64_env test_aarch64_qemu test_freestanding bootstrap bootstrap_diagnose test_bootstrap_diagnostics bootstrap_verify clean distclean run_42 run_c_42 core compiler test_nanopass test_passes test_verifier test_lir_verifier test_pass_manager test_profiler test_dataflow test_scope test_runtime test_annotator test_lvn test_rtyper test_contify test_alias_escape test_lir test_lir_suite test_backend test_hierarchical stage1 stage2 stage3 bootstrap_stage1 bootstrap_stage2 bootstrap_stage3 jit bin run_jit bench bench_baseline bench_verify demo \
        test_delimcc test_tracer test_auto_instrument test_optimizer test_guard_elimination test_bridge test_examples test_exceptions test_values test_call_cc test_eqv test_syntax_rules test_let_syntax test_ports test_record test_promise test_case_lambda test_stdlib test_base_procedures test_srfi1 test_hashtable test_letrec_star test_file_port test_string_to_number test_max_min test_format test_sort test_printer test_char test_r7rs_cond_expand test_r7rs_include_ci test_r7rs_bytevector_ports test_r7rs_time test_srfi_141_division test_srfi_111_boxes test_srfi_145_assume test_gc_growth test_gc_profile test_gc_hybrid test_gc_stress test_gc_stats \
        test_split_link test_incremental lint_sexpr test_lint_sexpr test_reader_eof test_arena test_atomic test_queue test_channel test_boundary test_epoch test_context_switch test_scheduler test_multithread_scheduler test_links_monitors test_task_mailbox test_let_it_crash test_supervisor test_futex test_registry test_crash_logger test_io_uring test_preemption test_eval_adapter test_concurrency_harness test_concurrency_ci test_pass_split_planes test_pass_check_affine test_pass_fbip test_pass_inline_hotpath test_pass_inject_safepoints

AS ?= as
LD ?= ld
ASFLAGS ?= --64
LDFLAGS ?= -m elf_x86_64 -static
CC ?= gcc
CFLAGS = -Wall -Wextra -O0 -g
CFLAGS_JIT = -no-pie -Wall -O2

# AArch64 Cross-Toolchain & QEMU Emulation
CROSS_AS_AARCH64 ?= aarch64-linux-gnu-as
CROSS_LD_AARCH64 ?= aarch64-linux-gnu-ld
CROSS_CC_AARCH64 ?= aarch64-linux-gnu-gcc
QEMU_AARCH64 ?= $(shell command -v qemu-aarch64 2>/dev/null || command -v qemu-aarch64-static 2>/dev/null)

%.o: %.s
	$(AS) $(ASFLAGS) $< -o $@

ROOT_DIR = $(shell dirname $(CURDIR))
PYTHON = $(shell if [ -x $(ROOT_DIR)/.venv/bin/python ]; then echo $(ROOT_DIR)/.venv/bin/python; else echo python3; fi)
ILISP = $(PYTHON) -m ilisp
ULISP_BOOT = bin/ulisp-boot
RUN_SCHEME = PYTHONPATH=$(ROOT_DIR) $(ILISP)
export ULISP_GC_PROFILE ?= compiler
GOSH_BIN = $(shell command -v gosh 2>/dev/null)

# --- 処理系エンジンの決定 (ULISP_BOOT があれば優先、なければ ILISP を使用) ---
ifeq ($(shell test -x $(ULISP_BOOT) && echo yes),yes)
    ULISP_COMPILER ?= env ULISP_GC_PROFILE=compiler ./$(ULISP_BOOT) <
    COMPILER_DEP = $(ULISP_BOOT)
    USE_NATIVE_BOOT = 1
else
    ULISP_COMPILER ?= $(RUN_SCHEME) compiler.scm <
    COMPILER_DEP =
    USE_NATIVE_BOOT = 0
endif

ULISP_RUNTIME_LIBS = runtime/gc.scm runtime/io.scm runtime/printer.scm runtime/entry.scm

ULISP_STD_LIBS = lib/posix.scm lib/list.scm lib/predicates.scm lib/math.scm lib/char.scm lib/string.scm lib/port.scm lib/printer.scm \
                 lib/reader.scm lib/equality.scm lib/bytevector.scm \
                 lib/vector.scm lib/promise.scm lib/exception.scm lib/values.scm \
                 lib/continuation.scm lib/parameter.scm lib/hashtable.scm lib/comparator.scm \
                 lib/format.scm lib/sort.scm lib/box.scm lib/gc.scm lib/eval.scm \
                 $(ULISP_RUNTIME_LIBS)

ULISP_LARGE_LIBS = lib/set.scm lib/stream.scm lib/generator.scm lib/list-queue.scm lib/lseq.scm lib/charset.scm lib/mapping.scm lib/ilist.scm lib/ideque.scm

COMPILER_BASE = compiler/helpers.scm \
                compiler/primitives.scm \
                compiler/nanopass_meta.scm \
                compiler/nanopass.scm \
                compiler/verifier.scm \
                compiler/pass_manager.scm \
                compiler/dataflow.scm \
                compiler/scope.scm

FRONTEND_PASSES = frontend/frontend_lang.scm \
                  frontend/010_library.scm \
                  frontend/015_dsl_expander.scm \
                  frontend/020_macro_expander.scm \
                  frontend/025_top_level.scm \
                  frontend/026_desugar_constructors.scm \
                  frontend/027_desugar_conditionals.scm \
                  frontend/028_desugar_bindings.scm \
                  frontend/029_desugar_dynamic.scm \
                  frontend/030_desugar.scm \
                  frontend/040_analysis.scm \
                  frontend/050_cp0.scm \
                  frontend/060_lvn.scm \
                  frontend/070_anf.scm \
                  frontend/080_annotator.scm \
                  frontend/090_rtyper.scm \
                  frontend/100_contify.scm \
                  frontend/110_closure_convert.scm \
                  frontend/120_alias_escape.scm

LIR_PASSES = lir/lir_lang.scm \
             lir/lir_verifier.scm \
             lir/123_lir_closures.scm \
             lir/124_lir_call_abi.scm \
             lir/125_lir_continuation.scm \
             lir/126_lir_control.scm \
             lir/127_lir_runtime.scm \
             lir/128_lir_branch_fusion.scm \
             lir/129_lir_primitives.scm \
             lir/130_lir.scm \
             lir/131_lir_safepoint.scm \
             lir/132_lir_braun_ssa.scm \
             lir/133_lir_peephole.scm

BACKEND_PASSES = backend/backend_lang.scm \
                 backend/140_backend_x86_64.scm \
                 backend/141_backend_x86_gc.scm \
                 backend/142_backend_x86_freestanding.scm \
                 backend/143_backend_x86_peephole.scm \
                 backend/elf64_builder.scm \
                 backend/144a_x86_assembler.scm \
                 backend/144_backend_x86_elf.scm \
                 backend/150_backend_aarch64.scm \
                 backend/160_backend_c.scm

PASSES_LIB = $(COMPILER_BASE) $(FRONTEND_PASSES) $(LIR_PASSES) $(BACKEND_PASSES)

PASSES = $(PASSES_LIB) compiler/driver.scm

all: test

compiler: compiler.scm

compiler.scm: $(PASSES)
	@$(PYTHON) scripts/lint_sexpr.py $(PASSES)
	cat $(PASSES) > $@

build/compiler_passes.scm: $(PASSES_LIB)
	@mkdir -p build
	@$(PYTHON) scripts/lint_sexpr.py $(PASSES_LIB)
	cat $^ > $@

lint_sexpr:
	@$(PYTHON) scripts/lint_sexpr.py $(PASSES) $(ULISP_STD_LIBS) $(ULISP_LARGE_LIBS) tests/test_numeric_tower.scm tests/test_aarch64_qemu_smoke.scm lib/srfi/1.sld lib/scheme/list.sld tests/test_srfi1.scm lib/srfi/69.sld lib/srfi/125.sld lib/scheme/hash-table.sld tests/test_hashtable.scm lib/scheme/file.sld tests/test_file_port.scm tests/test_string_to_number.scm tests/test_max_min.scm lib/srfi/28.sld tests/test_format.scm lib/srfi/132.sld lib/srfi/95.sld lib/scheme/sort.sld tests/test_sort.scm lib/scheme/write.sld tests/test_printer.scm runtime/concurrency/arena.scm lib/ulisp/concurrency/arena.sld $(ROOT_DIR)/tests/concurrency/test_arena.scm runtime/concurrency/atomic.scm lib/ulisp/concurrency/atomic.sld $(ROOT_DIR)/tests/concurrency/test_atomic.scm runtime/concurrency/queue.scm lib/ulisp/concurrency/queue.sld $(ROOT_DIR)/tests/concurrency/test_queue.scm runtime/concurrency/channel.scm lib/ulisp/concurrency/channel.sld $(ROOT_DIR)/tests/concurrency/test_channel.scm runtime/concurrency/boundary.scm lib/ulisp/concurrency/boundary.sld $(ROOT_DIR)/tests/concurrency/test_boundary.scm runtime/concurrency/epoch.scm lib/ulisp/concurrency/epoch.sld $(ROOT_DIR)/tests/concurrency/test_epoch.scm runtime/concurrency/context.scm lib/ulisp/concurrency/context.sld $(ROOT_DIR)/tests/concurrency/test_context_switch.scm runtime/concurrency/deque.scm lib/ulisp/concurrency/deque.sld runtime/concurrency/futex.scm lib/ulisp/concurrency/futex.sld $(ROOT_DIR)/tests/concurrency/test_futex.scm runtime/concurrency/registry.scm lib/ulisp/concurrency/registry.sld $(ROOT_DIR)/tests/concurrency/test_registry.scm runtime/concurrency/crash_logger.scm lib/ulisp/concurrency/crash_logger.sld $(ROOT_DIR)/tests/concurrency/test_crash_logger.scm runtime/concurrency/io_uring.scm lib/ulisp/concurrency/io_uring.sld $(ROOT_DIR)/tests/concurrency/test_io_uring.scm runtime/concurrency/scheduler.scm lib/ulisp/concurrency/scheduler.sld $(ROOT_DIR)/tests/concurrency/test_scheduler.scm runtime/concurrency/preempt.scm lib/ulisp/concurrency/preempt.sld $(ROOT_DIR)/tests/concurrency/test_preemption.scm runtime/concurrency/eval_adapter.scm lib/ulisp/concurrency/eval_adapter.sld $(ROOT_DIR)/tests/concurrency/test_eval_adapter.scm $(ROOT_DIR)/tests/concurrency/concurrency_harness.scm lib/ulisp/concurrency/passes/pass_split_planes.scm lib/ulisp/concurrency/passes/split_planes.sld $(ROOT_DIR)/tests/concurrency/test_pass_split_planes.scm lib/ulisp/concurrency/passes/pass_check_affine.scm lib/ulisp/concurrency/passes/check_affine.sld $(ROOT_DIR)/tests/concurrency/test_pass_check_affine.scm lib/ulisp/concurrency/passes/pass_fbip.scm lib/ulisp/concurrency/passes/fbip.sld $(ROOT_DIR)/tests/concurrency/test_pass_fbip.scm lib/ulisp/concurrency/passes/pass_inline_hotpath.scm lib/ulisp/concurrency/passes/inline_hotpath.sld $(ROOT_DIR)/tests/concurrency/test_pass_inline_hotpath.scm lib/ulisp/concurrency/passes/pass_inject_safepoints.scm lib/ulisp/concurrency/passes/inject_safepoints.sld $(ROOT_DIR)/tests/concurrency/test_pass_inject_safepoints.scm $(ROOT_DIR)/benchmarks/concurrency/bench_microtasks.scm $(ROOT_DIR)/benchmarks/concurrency/bench_latency_under_gc.scm

test_lint_sexpr:
	@$(PYTHON) tests/test_lint_sexpr.py

test_r7rs_traceability:
	@$(PYTHON) $(ROOT_DIR)/scripts/verify_r7rs_traceability.py

# --- AOT Nanopass Tests ---
test_nanopass: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/test_nanopass_framework.scm > build/test_nanopass_runner.scm
	@$(RUN_SCHEME) build/test_nanopass_runner.scm
	cat build/compiler_passes.scm tests/test_nanopass_tracer.scm > build/test_nanopass_tracer_runner.scm
	@$(RUN_SCHEME) build/test_nanopass_tracer_runner.scm

docs_nanopass: build/compiler_passes.scm
	@mkdir -p build docs
	cat build/compiler_passes.scm tools/generate_nanopass_docs.scm > build/generate_docs_runner.scm
	@$(RUN_SCHEME) build/generate_docs_runner.scm > docs/spec_nanopass.md
	@echo "Generated docs/spec_nanopass.md"

test_passes: build/compiler_passes.scm test_all_passes
	@mkdir -p build
	cat build/compiler_passes.scm tests/test_passes.scm > build/test_passes_runner.scm
	@$(RUN_SCHEME) build/test_passes_runner.scm

NANOPASS_TESTS = tests/passes/test_000_compiler_diagnostics.scm \
                 tests/passes/test_power_assert.scm \
                 tests/passes/test_traceback.scm \
                 tests/passes/test_010_library.scm \
                 tests/passes/test_015_dsl_expander.scm \
                 tests/passes/test_020_macro_expander.scm \
                 tests/passes/test_025_top_level.scm \
                 tests/passes/test_026_desugar_constructors.scm \
                 tests/passes/test_027_desugar_conditionals.scm \
                 tests/passes/test_028_desugar_bindings.scm \
                 tests/passes/test_029_desugar_dynamic.scm \
                 tests/passes/test_030_desugar.scm \
                 tests/passes/test_040_analysis.scm \
                 tests/passes/test_050_cp0.scm \
                 tests/passes/test_060_lvn.scm \
                 tests/passes/test_070_anf.scm \
                 tests/passes/test_080_annotator.scm \
                 tests/passes/test_090_rtyper.scm \
                 tests/passes/test_100_contify.scm \
                 tests/passes/test_110_closure_convert.scm \
                 tests/passes/test_120_alias_escape.scm \
                 tests/passes/test_123_lir_closures.scm \
                 tests/passes/test_124_lir_call_abi.scm \
                 tests/passes/test_125_lir_continuation.scm \
                 tests/passes/test_126_lir_control.scm \
                 tests/passes/test_127_lir_runtime.scm \
                 tests/passes/test_128_lir_branch_fusion.scm \
                 tests/passes/test_129_lir_primitives.scm \
                 tests/passes/test_130_lir.scm \
                 tests/passes/test_131_lir_safepoint.scm \
                 tests/passes/test_132_lir_braun_ssa.scm \
                 tests/passes/test_133_lir_peephole.scm \
                 tests/passes/test_140_backend_x86_64.scm \
                 tests/passes/test_141_backend_x86_gc.scm \
                 tests/passes/test_142_backend_x86_freestanding.scm \
                 tests/passes/test_143_backend_x86_peephole.scm \
                 tests/passes/test_150_backend_aarch64.scm \
                 tests/passes/test_160_backend_c.scm \
                 tests/passes/test_extern_symbols.scm

test_all_passes: build/compiler_passes.scm
	@echo "=== Running 1:1 Nanopass Unit Tests (38 Passes) ==="
	@for t in $(NANOPASS_TESTS); do \
		echo "Running $$t..."; \
		cat build/compiler_passes.scm $$t > build/runner_temp.scm && \
		$(RUN_SCHEME) build/runner_temp.scm || exit 1; \
	done
	@echo "SUCCESS: All 38 1:1 Nanopass Unit Tests PASSED!"

test_extern_symbols: build/compiler_passes.scm
	@cat build/compiler_passes.scm tests/passes/test_extern_symbols.scm > build/runner_temp.scm
	@$(RUN_SCHEME) build/runner_temp.scm

test_power_assert: build/compiler_passes.scm
	@cat build/compiler_passes.scm tests/passes/test_power_assert.scm > build/runner_temp.scm
	@$(RUN_SCHEME) build/runner_temp.scm

test_traceback: build/compiler_passes.scm
	@cat build/compiler_passes.scm tests/passes/test_traceback.scm > build/runner_temp.scm
	@$(RUN_SCHEME) build/runner_temp.scm

test_140: build/compiler_passes.scm
	@cat build/compiler_passes.scm tests/passes/test_140_backend_x86_64.scm > build/runner_temp.scm
	@$(RUN_SCHEME) build/runner_temp.scm

test_143: build/compiler_passes.scm
	@cat build/compiler_passes.scm tests/passes/test_143_backend_x86_peephole.scm > build/runner_temp.scm
	@$(RUN_SCHEME) build/runner_temp.scm

test_144a: build/compiler_passes.scm
	@cat build/compiler_passes.scm tests/passes/test_144a_x86_assembler.scm > build/runner_temp.scm
	@$(RUN_SCHEME) build/runner_temp.scm

test_elf64: build/compiler_passes.scm
	@cat build/compiler_passes.scm tests/passes/test_elf64_builder.scm > build/runner_temp.scm
	@$(RUN_SCHEME) build/runner_temp.scm

test_144: build/compiler_passes.scm
	@cat build/compiler_passes.scm tests/passes/test_144_backend_x86_elf.scm > build/runner_temp.scm
	@$(RUN_SCHEME) build/runner_temp.scm



test_library: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_library.scm > build/test_library_runner.scm
	@$(RUN_SCHEME) build/test_library_runner.scm
	$(AS) $(ASFLAGS) build/test_library.s -o build/test_library.o
	$(LD) $(LDFLAGS) build/test_library.o -o build/test_library
	@echo "=== Executing compiled library x86-64 binary ==="
	@res=$$(./build/test_library); echo "Output: $$res"; test "$$res" = "260"
	@echo "SUCCESS: library x86-64 output 260 matches expected!"
	$(CC) $(CFLAGS_JIT) -o build/test_library_c build/test_library.c
	@echo "=== Executing compiled library Portable C binary ==="
	@res_c=$$(./build/test_library_c); echo "Output: $$res_c"; test "$$res_c" = "260"
	@echo "SUCCESS: library C output 260 matches expected!"

test_runtime: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_scheme_runtime.scm > build/test_runtime_input.scm
	$(ULISP_COMPILER) build/test_runtime_input.scm > build/test_runtime.s
	$(AS) $(ASFLAGS) build/test_runtime.s -o build/test_runtime.o
	$(LD) $(LDFLAGS) build/test_runtime.o -o build/test_runtime
	./build/test_runtime < /dev/null

test_arena: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/tests/concurrency/test_arena.scm > build/test_arena_input.scm
	$(ULISP_COMPILER) build/test_arena_input.scm > build/test_arena.s
	$(AS) $(ASFLAGS) build/test_arena.s -o build/test_arena.o
	$(LD) $(LDFLAGS) build/test_arena.o -o build/test_arena
	./build/test_arena < /dev/null

test_atomic: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/tests/concurrency/test_atomic.scm > build/test_atomic_input.scm
	$(ULISP_COMPILER) build/test_atomic_input.scm > build/test_atomic.s
	$(AS) $(ASFLAGS) build/test_atomic.s -o build/test_atomic.o
	$(LD) $(LDFLAGS) build/test_atomic.o -o build/test_atomic
	./build/test_atomic < /dev/null

test_queue: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/tests/concurrency/test_queue.scm > build/test_queue_input.scm
	$(ULISP_COMPILER) build/test_queue_input.scm > build/test_queue.s
	$(AS) $(ASFLAGS) build/test_queue.s -o build/test_queue.o
	$(LD) $(LDFLAGS) build/test_queue.o -o build/test_queue
	./build/test_queue < /dev/null

test_channel: $(COMPILER_DEP) build/futex.o
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/tests/concurrency/test_channel.scm > build/test_channel_input.scm
	$(ULISP_COMPILER) build/test_channel_input.scm > build/test_channel.s
	$(AS) $(ASFLAGS) build/test_channel.s -o build/test_channel.o
	$(LD) $(LDFLAGS) build/test_channel.o build/futex.o -o build/test_channel
	./build/test_channel < /dev/null

test_boundary: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/tests/concurrency/test_boundary.scm > build/test_boundary_input.scm
	$(ULISP_COMPILER) build/test_boundary_input.scm > build/test_boundary.s
	$(AS) $(ASFLAGS) build/test_boundary.s -o build/test_boundary.o
	$(LD) $(LDFLAGS) build/test_boundary.o -o build/test_boundary
	./build/test_boundary < /dev/null

test_epoch: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/tests/concurrency/test_epoch.scm > build/test_epoch_input.scm
	$(ULISP_COMPILER) build/test_epoch_input.scm > build/test_epoch.s
	$(AS) $(ASFLAGS) build/test_epoch.s -o build/test_epoch.o
	$(LD) $(LDFLAGS) build/test_epoch.o -o build/test_epoch
	./build/test_epoch < /dev/null

build/context.o: runtime/concurrency/context.s
	@mkdir -p build
	$(AS) $(ASFLAGS) runtime/concurrency/context.s -o build/context.o

build/thread.o: runtime/concurrency/thread.s
	@mkdir -p build
	$(AS) $(ASFLAGS) runtime/concurrency/thread.s -o build/thread.o

build/futex.o: runtime/concurrency/futex.s
	@mkdir -p build
	$(AS) $(ASFLAGS) runtime/concurrency/futex.s -o build/futex.o

build/io_uring.o: runtime/concurrency/io_uring.s
	@mkdir -p build
	$(AS) $(ASFLAGS) runtime/concurrency/io_uring.s -o build/io_uring.o

test_context_switch: $(COMPILER_DEP) build/context.o
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/tests/concurrency/test_context_switch.scm > build/test_context_switch_input.scm
	$(ULISP_COMPILER) build/test_context_switch_input.scm > build/test_context_switch.s
	$(AS) $(ASFLAGS) build/test_context_switch.s -o build/test_context_switch.o
	$(LD) $(LDFLAGS) build/test_context_switch.o build/context.o -o build/test_context_switch
	./build/test_context_switch < /dev/null

test_scheduler: $(COMPILER_DEP) build/context.o build/thread.o build/futex.o
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/tests/concurrency/test_scheduler.scm > build/test_scheduler_input.scm
	$(ULISP_COMPILER) build/test_scheduler_input.scm > build/test_scheduler.s
	$(AS) $(ASFLAGS) build/test_scheduler.s -o build/test_scheduler.o
	$(LD) $(LDFLAGS) build/test_scheduler.o build/context.o build/thread.o build/futex.o -o build/test_scheduler
	./build/test_scheduler < /dev/null

test_multithread_scheduler: $(COMPILER_DEP) build/context.o build/thread.o build/futex.o
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/tests/concurrency/test_multithread_scheduler.scm > build/test_multithread_scheduler_input.scm
	$(ULISP_COMPILER) build/test_multithread_scheduler_input.scm > build/test_multithread_scheduler.s
	$(AS) $(ASFLAGS) build/test_multithread_scheduler.s -o build/test_multithread_scheduler.o
	$(LD) $(LDFLAGS) build/test_multithread_scheduler.o build/context.o build/thread.o build/futex.o -o build/test_multithread_scheduler
	./build/test_multithread_scheduler < /dev/null

test_links_monitors: $(COMPILER_DEP) build/context.o build/thread.o build/futex.o
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/tests/concurrency/test_links_monitors.scm > build/test_links_monitors_input.scm
	$(ULISP_COMPILER) build/test_links_monitors_input.scm > build/test_links_monitors.s
	$(AS) $(ASFLAGS) build/test_links_monitors.s -o build/test_links_monitors.o
	$(LD) $(LDFLAGS) build/test_links_monitors.o build/context.o build/thread.o build/futex.o -o build/test_links_monitors
	./build/test_links_monitors < /dev/null

test_task_mailbox: $(COMPILER_DEP) build/context.o build/thread.o build/futex.o
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/tests/concurrency/test_task_mailbox.scm > build/test_task_mailbox_input.scm
	$(ULISP_COMPILER) build/test_task_mailbox_input.scm > build/test_task_mailbox.s
	$(AS) $(ASFLAGS) build/test_task_mailbox.s -o build/test_task_mailbox.o
	$(LD) $(LDFLAGS) build/test_task_mailbox.o build/context.o build/thread.o build/futex.o -o build/test_task_mailbox
	./build/test_task_mailbox < /dev/null

test_let_it_crash: $(COMPILER_DEP) build/context.o build/thread.o build/futex.o
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/tests/concurrency/test_let_it_crash.scm > build/test_let_it_crash_input.scm
	$(ULISP_COMPILER) build/test_let_it_crash_input.scm > build/test_let_it_crash.s
	$(AS) $(ASFLAGS) build/test_let_it_crash.s -o build/test_let_it_crash.o
	$(LD) $(LDFLAGS) build/test_let_it_crash.o build/context.o build/thread.o build/futex.o -o build/test_let_it_crash
	./build/test_let_it_crash < /dev/null

test_supervisor: $(COMPILER_DEP) build/context.o build/thread.o build/futex.o
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/tests/concurrency/test_supervisor.scm > build/test_supervisor_input.scm
	$(ULISP_COMPILER) build/test_supervisor_input.scm > build/test_supervisor.s
	$(AS) $(ASFLAGS) build/test_supervisor.s -o build/test_supervisor.o
	$(LD) $(LDFLAGS) build/test_supervisor.o build/context.o build/thread.o build/futex.o -o build/test_supervisor
	./build/test_supervisor < /dev/null

test_futex: $(COMPILER_DEP) build/context.o build/thread.o build/futex.o
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/tests/concurrency/test_futex.scm > build/test_futex_input.scm
	$(ULISP_COMPILER) build/test_futex_input.scm > build/test_futex.s
	$(AS) $(ASFLAGS) build/test_futex.s -o build/test_futex.o
	$(LD) $(LDFLAGS) build/test_futex.o build/context.o build/thread.o build/futex.o -o build/test_futex
	./build/test_futex < /dev/null

test_registry: $(COMPILER_DEP) build/context.o build/thread.o build/futex.o
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/tests/concurrency/test_registry.scm > build/test_registry_input.scm
	$(ULISP_COMPILER) build/test_registry_input.scm > build/test_registry.s
	$(AS) $(ASFLAGS) build/test_registry.s -o build/test_registry.o
	$(LD) $(LDFLAGS) build/test_registry.o build/context.o build/thread.o build/futex.o -o build/test_registry
	./build/test_registry < /dev/null

test_crash_logger: $(COMPILER_DEP) build/context.o build/thread.o build/futex.o
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/tests/concurrency/test_crash_logger.scm > build/test_crash_logger_input.scm
	$(ULISP_COMPILER) build/test_crash_logger_input.scm > build/test_crash_logger.s
	$(AS) $(ASFLAGS) build/test_crash_logger.s -o build/test_crash_logger.o
	$(LD) $(LDFLAGS) build/test_crash_logger.o build/context.o build/thread.o build/futex.o -o build/test_crash_logger
	./build/test_crash_logger < /dev/null

test_io_uring: $(COMPILER_DEP) build/context.o build/thread.o build/futex.o build/io_uring.o
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/tests/concurrency/test_io_uring.scm > build/test_io_uring_input.scm
	$(ULISP_COMPILER) build/test_io_uring_input.scm > build/test_io_uring.s
	$(AS) $(ASFLAGS) build/test_io_uring.s -o build/test_io_uring.o
	$(LD) $(LDFLAGS) build/test_io_uring.o build/context.o build/thread.o build/futex.o build/io_uring.o -o build/test_io_uring
	./build/test_io_uring < /dev/null

test_preemption: $(COMPILER_DEP) build/context.o build/thread.o build/futex.o
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/tests/concurrency/test_preemption.scm > build/test_preemption_input.scm
	$(ULISP_COMPILER) build/test_preemption_input.scm > build/test_preemption.s
	$(AS) $(ASFLAGS) build/test_preemption.s -o build/test_preemption.o
	$(LD) $(LDFLAGS) build/test_preemption.o build/context.o build/thread.o build/futex.o -o build/test_preemption
	./build/test_preemption < /dev/null

test_eval_adapter: $(COMPILER_DEP) build/context.o build/thread.o build/futex.o
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/tests/concurrency/test_eval_adapter.scm > build/test_eval_adapter_input.scm
	$(ULISP_COMPILER) build/test_eval_adapter_input.scm > build/test_eval_adapter.s
	$(AS) $(ASFLAGS) build/test_eval_adapter.s -o build/test_eval_adapter.o
	$(LD) $(LDFLAGS) build/test_eval_adapter.o build/context.o build/thread.o build/futex.o -o build/test_eval_adapter
	./build/test_eval_adapter < /dev/null

test_concurrency_harness: $(COMPILER_DEP) build/context.o build/thread.o build/futex.o
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/tests/concurrency/concurrency_harness.scm > build/test_concurrency_harness_input.scm
	$(ULISP_COMPILER) build/test_concurrency_harness_input.scm > build/test_concurrency_harness.s
	$(AS) $(ASFLAGS) build/test_concurrency_harness.s -o build/test_concurrency_harness.o
	$(LD) $(LDFLAGS) build/test_concurrency_harness.o build/context.o build/thread.o build/futex.o -o build/test_concurrency_harness
	./build/test_concurrency_harness < /dev/null

test_concurrency: test_multithread_scheduler test_let_it_crash test_supervisor test_scheduler test_links_monitors test_task_mailbox test_preemption test_concurrency_harness

test_concurrency_ci: test_concurrency

bench_microtasks: $(COMPILER_DEP) build/context.o build/thread.o build/futex.o
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/benchmarks/concurrency/bench_microtasks.scm > build/bench_microtasks_input.scm
	$(ULISP_COMPILER) build/bench_microtasks_input.scm > build/bench_microtasks.s
	$(AS) $(ASFLAGS) build/bench_microtasks.s -o build/bench_microtasks.o
	$(LD) $(LDFLAGS) build/bench_microtasks.o build/context.o build/thread.o build/futex.o -o build/bench_microtasks
	./build/bench_microtasks < /dev/null

bench_latency_under_gc: $(COMPILER_DEP) build/context.o build/thread.o build/futex.o
	@mkdir -p build
	cat $(ULISP_STD_LIBS) $(ROOT_DIR)/benchmarks/concurrency/bench_latency_under_gc.scm > build/bench_latency_under_gc_input.scm
	$(ULISP_COMPILER) build/bench_latency_under_gc_input.scm > build/bench_latency_under_gc.s
	$(AS) $(ASFLAGS) build/bench_latency_under_gc.s -o build/bench_latency_under_gc.o
	$(LD) $(LDFLAGS) build/bench_latency_under_gc.o build/context.o build/thread.o build/futex.o -o build/bench_latency_under_gc
	./build/bench_latency_under_gc < /dev/null

bench_concurrency: bench_microtasks bench_latency_under_gc

test_lvn: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_lvn.scm > build/test_lvn_runner.scm
	@$(RUN_SCHEME) build/test_lvn_runner.scm

test_annotator: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_annotator.scm > build/test_annotator_runner.scm
	@$(RUN_SCHEME) build/test_annotator_runner.scm

test_rtyper: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_rtyper.scm > build/test_rtyper_runner.scm
	@$(RUN_SCHEME) build/test_rtyper_runner.scm

test_stackmap: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_stackmap.scm > build/test_stackmap_runner.scm
	@$(RUN_SCHEME) build/test_stackmap_runner.scm

test_contify: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_contify.scm > build/test_contify_runner.scm
	@$(RUN_SCHEME) build/test_contify_runner.scm

test_alias_escape: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_alias_escape.scm > build/test_alias_escape_runner.scm
	@$(RUN_SCHEME) build/test_alias_escape_runner.scm

test_toplevel: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_toplevel_direct_call.scm > build/test_toplevel_runner.scm
	@$(RUN_SCHEME) build/test_toplevel_runner.scm

test_loop_reg: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_loop_register_allocation.scm > build/test_loop_reg_runner.scm
	@$(RUN_SCHEME) build/test_loop_reg_runner.scm
	$(AS) $(ASFLAGS) build/test_loop_reg.s -o build/test_loop_reg.o
	$(LD) $(LDFLAGS) build/test_loop_reg.o -o build/test_loop_reg
	@echo "=== Executing compiled loop_sum binary (1,000,000 iters) ==="
	@res=$$(./build/test_loop_reg); echo "Output: $$res"; test "$$res" = "499999500000"
	@echo "SUCCESS: loop_sum output 499999500000 matches expected exactly!"

test_branch_fusion: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_branch_fusion.scm > build/test_branch_fusion_runner.scm
	@$(RUN_SCHEME) build/test_branch_fusion_runner.scm
	$(AS) $(ASFLAGS) build/test_predicates_fusion.s -o build/test_predicates_fusion.o
	$(LD) $(LDFLAGS) build/test_predicates_fusion.o -o build/test_predicates_fusion
	@echo "=== Executing compiled predicates fusion binary ==="
	@res=$$(./build/test_predicates_fusion); echo "Output: $$res"; test "$$res" = "255"
	@echo "SUCCESS: branch fusion predicates output 255 (1+2+4+8+16+32+64+128) matches expected!"

test_inplace_shuffle: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_inplace_shuffle.scm > build/test_inplace_shuffle_runner.scm
	@$(RUN_SCHEME) build/test_inplace_shuffle_runner.scm
	$(AS) $(ASFLAGS) build/test_inplace_shuffle.s -o build/test_inplace_shuffle.o
	$(LD) $(LDFLAGS) build/test_inplace_shuffle.o -o build/test_inplace_shuffle
	@echo "=== Executing compiled inplace shuffle loop_sum binary ==="
	@res=$$(./build/test_inplace_shuffle); echo "Output: $$res"; test "$$res" = "499999500000"
	@echo "SUCCESS: inplace shuffle loop_sum output 499999500000 matches expected exactly!"
	$(AS) $(ASFLAGS) build/test_swap_loop.s -o build/test_swap_loop.o
	$(LD) $(LDFLAGS) build/test_swap_loop.o -o build/test_swap_loop
	@echo "=== Executing compiled swap_loop binary ==="
	@res=$$(./build/test_swap_loop); echo "Output: $$res"; test "$$res" = "10"
	@echo "SUCCESS: swap_loop output 10 (swap 10 20 -> 20 10 -> returns b=10) matches expected exactly!"
	$(AS) $(ASFLAGS) build/test_countdown.s -o build/test_countdown.o
	$(LD) $(LDFLAGS) build/test_countdown.o -o build/test_countdown
	@echo "=== Executing compiled countdown binary ==="
	@res=$$(./build/test_countdown); echo "Output: $$res"; test "$$res" = "5050"
	@echo "SUCCESS: countdown sum(1..100) output 5050 matches expected exactly!"

test_lir: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_lir.scm > build/test_lir_runner.scm
	@$(RUN_SCHEME) build/test_lir_runner.scm

test_lir_suite: compiler.scm
	@bash test_lir.sh

test_backend: compiler.scm
	@bash test_backend.sh

test_differential_elf: build/ulisp-modular
	@bash tests/test_differential_elf.sh

# --- Minimal DWARF Debug Info Verification (Issue #619) ---
test-debug test_dwarf_debug: build/ulisp-modular
	@bash tests/test_dwarf_debug.sh

test_hierarchical: test_lir_suite test_backend
	@echo "=== All Hierarchical LIR Tests Passed ==="

test_aarch64: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/test_backend_aarch64.scm > build/test_aarch64_runner.scm
	@$(RUN_SCHEME) build/test_aarch64_runner.scm

test_aarch64_env:
	@CROSS_AS_AARCH64="$(CROSS_AS_AARCH64)" \
	 CROSS_LD_AARCH64="$(CROSS_LD_AARCH64)" \
	 CROSS_CC_AARCH64="$(CROSS_CC_AARCH64)" \
	 QEMU_AARCH64="$(QEMU_AARCH64)" \
	 bash scripts/test_aarch64_env.sh

test_aarch64_qemu: compiler
	@CROSS_AS_AARCH64="$(CROSS_AS_AARCH64)" \
	 CROSS_LD_AARCH64="$(CROSS_LD_AARCH64)" \
	 QEMU_AARCH64="$(QEMU_AARCH64)" \
	 bash scripts/test_aarch64_qemu_smoke.sh

test_verifier: build/compiler_passes.scm test_lir_verifier
	@mkdir -p build
	cat build/compiler_passes.scm tests/test_verifier.scm > build/test_verifier_runner.scm
	@$(RUN_SCHEME) build/test_verifier_runner.scm

test_lir_verifier: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/test_lir_verifier.scm > build/test_lir_verifier_runner.scm
	@$(RUN_SCHEME) build/test_lir_verifier_runner.scm

test_pass_manager: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/test_pass_manager.scm > build/test_pass_manager_runner.scm
	@$(RUN_SCHEME) build/test_pass_manager_runner.scm

test_pass_split_planes: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm lib/ulisp/concurrency/passes/pass_split_planes.scm $(ROOT_DIR)/tests/concurrency/test_pass_split_planes.scm > build/test_pass_split_planes_runner.scm
	@$(RUN_SCHEME) build/test_pass_split_planes_runner.scm

test_pass_check_affine: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm lib/ulisp/concurrency/passes/pass_split_planes.scm lib/ulisp/concurrency/passes/pass_check_affine.scm $(ROOT_DIR)/tests/concurrency/test_pass_check_affine.scm > build/test_pass_check_affine_runner.scm
	@$(RUN_SCHEME) build/test_pass_check_affine_runner.scm

test_pass_fbip: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm lib/ulisp/concurrency/passes/pass_split_planes.scm lib/ulisp/concurrency/passes/pass_check_affine.scm lib/ulisp/concurrency/passes/pass_fbip.scm $(ROOT_DIR)/tests/concurrency/test_pass_fbip.scm > build/test_pass_fbip_runner.scm
	@$(RUN_SCHEME) build/test_pass_fbip_runner.scm

test_pass_inline_hotpath: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm lib/ulisp/concurrency/passes/pass_split_planes.scm lib/ulisp/concurrency/passes/pass_check_affine.scm lib/ulisp/concurrency/passes/pass_fbip.scm lib/ulisp/concurrency/passes/pass_inline_hotpath.scm lib/ulisp/concurrency/passes/pass_inject_safepoints.scm $(ROOT_DIR)/tests/concurrency/test_pass_inline_hotpath.scm > build/test_pass_inline_hotpath_runner.scm
	@$(RUN_SCHEME) build/test_pass_inline_hotpath_runner.scm

test_pass_inject_safepoints: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm lib/ulisp/concurrency/passes/pass_split_planes.scm lib/ulisp/concurrency/passes/pass_check_affine.scm lib/ulisp/concurrency/passes/pass_fbip.scm lib/ulisp/concurrency/passes/pass_inline_hotpath.scm lib/ulisp/concurrency/passes/pass_inject_safepoints.scm $(ROOT_DIR)/tests/concurrency/test_pass_inject_safepoints.scm > build/test_pass_inject_safepoints_runner.scm
	@$(RUN_SCHEME) build/test_pass_inject_safepoints_runner.scm

test_profiler: compiler.scm
	@echo "=== Running Compiler Nanopass Profiler Test Suite (Issue #621) ==="
	@bash tests/test_pass_profiler.sh

test_dataflow: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/test_dataflow.scm > build/test_dataflow_runner.scm
	@$(RUN_SCHEME) build/test_dataflow_runner.scm

test_scope: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/test_scope.scm > build/test_scope_runner.scm
	@$(RUN_SCHEME) build/test_scope_runner.scm

test_include_source_loc: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/test_include_source_loc.scm > build/test_include_source_loc_runner.scm
	@$(RUN_SCHEME) build/test_include_source_loc_runner.scm


test_exceptions: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_exceptions.scm > build/test_exn_input.scm
	$(ULISP_COMPILER) build/test_exn_input.scm > build/test_exn.s
	$(AS) $(ASFLAGS) build/test_exn.s -o build/test_exn.o
	$(LD) $(LDFLAGS) build/test_exn.o -o build/test_exn
	./build/test_exn

test_values: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_values.scm > build/test_values_input.scm
	$(ULISP_COMPILER) build/test_values_input.scm > build/test_values.s
	$(AS) $(ASFLAGS) build/test_values.s -o build/test_values.o
	$(LD) $(LDFLAGS) build/test_values.o -o build/test_values
	./build/test_values

test_call_cc: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_call_cc.scm > build/test_call_cc_input.scm
	$(ULISP_COMPILER) build/test_call_cc_input.scm > build/test_call_cc.s
	$(AS) $(ASFLAGS) build/test_call_cc.s -o build/test_call_cc.o
	$(LD) $(LDFLAGS) build/test_call_cc.o -o build/test_call_cc
	./build/test_call_cc

test_eqv: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_eqv.scm > build/test_eqv_input.scm
	$(ULISP_COMPILER) build/test_eqv_input.scm > build/test_eqv.s
	$(AS) $(ASFLAGS) build/test_eqv.s -o build/test_eqv.o
	$(LD) $(LDFLAGS) build/test_eqv.o -o build/test_eqv
	./build/test_eqv

test_syntax_rules: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_syntax_rules.scm > build/test_syntax_rules_input.scm
	$(ULISP_COMPILER) build/test_syntax_rules_input.scm > build/test_syntax_rules.s
	$(AS) $(ASFLAGS) build/test_syntax_rules.s -o build/test_syntax_rules.o
	$(LD) $(LDFLAGS) build/test_syntax_rules.o -o build/test_syntax_rules
	./build/test_syntax_rules

test_let_syntax: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_let_syntax.scm > build/test_let_syntax_input.scm
	$(ULISP_COMPILER) build/test_let_syntax_input.scm > build/test_let_syntax.s
	$(AS) $(ASFLAGS) build/test_let_syntax.s -o build/test_let_syntax.o
	$(LD) $(LDFLAGS) build/test_let_syntax.o -o build/test_let_syntax
	./build/test_let_syntax

test_ports: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_ports.scm > build/test_ports_input.scm
	$(ULISP_COMPILER) build/test_ports_input.scm > build/test_ports.s
	$(AS) $(ASFLAGS) build/test_ports.s -o build/test_ports.o
	$(LD) $(LDFLAGS) build/test_ports.o -o build/test_ports
	./build/test_ports

test_reader_eof: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_reader_eof.scm > build/test_reader_eof_input.scm
	$(ULISP_COMPILER) build/test_reader_eof_input.scm > build/test_reader_eof.s
	$(AS) $(ASFLAGS) build/test_reader_eof.s -o build/test_reader_eof.o
	$(LD) $(LDFLAGS) build/test_reader_eof.o -o build/test_reader_eof
	./build/test_reader_eof

test_record: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_record.scm > build/test_record_input.scm
	$(ULISP_COMPILER) build/test_record_input.scm > build/test_record.s
	$(AS) $(ASFLAGS) build/test_record.s -o build/test_record.o
	$(LD) $(LDFLAGS) build/test_record.o -o build/test_record
	./build/test_record

test_promise: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_promise.scm > build/test_promise_input.scm
	$(ULISP_COMPILER) build/test_promise_input.scm > build/test_promise.s
	$(AS) $(ASFLAGS) build/test_promise.s -o build/test_promise.o
	$(LD) $(LDFLAGS) build/test_promise.o -o build/test_promise
	./build/test_promise

test_case_lambda: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_case_lambda.scm > build/test_case_lambda_input.scm
	$(ULISP_COMPILER) build/test_case_lambda_input.scm > build/test_case_lambda.s
	$(AS) $(ASFLAGS) build/test_case_lambda.s -o build/test_case_lambda.o
	$(LD) $(LDFLAGS) build/test_case_lambda.o -o build/test_case_lambda
	./build/test_case_lambda

test_stdlib: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_stdlib_r7rs.scm > build/test_stdlib_input.scm
	$(ULISP_COMPILER) build/test_stdlib_input.scm > build/test_stdlib.s
	$(AS) $(ASFLAGS) build/test_stdlib.s -o build/test_stdlib.o
	$(LD) $(LDFLAGS) build/test_stdlib.o -o build/test_stdlib
	./build/test_stdlib

test_base_procedures: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_base_procedures.scm > build/test_base_procedures_input.scm
	$(ULISP_COMPILER) build/test_base_procedures_input.scm > build/test_base_procedures.s
	$(AS) $(ASFLAGS) build/test_base_procedures.s -o build/test_base_procedures.o
	$(LD) $(LDFLAGS) build/test_base_procedures.o -o build/test_base_procedures
	./build/test_base_procedures

test_srfi1: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_srfi1.scm > build/test_srfi1_input.scm
	$(ULISP_COMPILER) build/test_srfi1_input.scm > build/test_srfi1.s
	$(AS) $(ASFLAGS) build/test_srfi1.s -o build/test_srfi1.o
	$(LD) $(LDFLAGS) build/test_srfi1.o -o build/test_srfi1
	./build/test_srfi1

test_hashtable: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_hashtable.scm > build/test_hashtable_input.scm
	$(ULISP_COMPILER) build/test_hashtable_input.scm > build/test_hashtable.s
	$(AS) $(ASFLAGS) build/test_hashtable.s -o build/test_hashtable.o
	$(LD) $(LDFLAGS) build/test_hashtable.o -o build/test_hashtable
	./build/test_hashtable

test_letrec_star: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_letrec_star.scm > build/test_letrec_star_input.scm
	$(ULISP_COMPILER) build/test_letrec_star_input.scm > build/test_letrec_star.s
	$(AS) $(ASFLAGS) build/test_letrec_star.s -o build/test_letrec_star.o
	$(LD) $(LDFLAGS) build/test_letrec_star.o -o build/test_letrec_star
	./build/test_letrec_star

test_file_port: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_file_port.scm > build/test_file_port_input.scm
	$(ULISP_COMPILER) build/test_file_port_input.scm > build/test_file_port.s
	$(AS) $(ASFLAGS) build/test_file_port.s -o build/test_file_port.o
	$(LD) $(LDFLAGS) build/test_file_port.o -o build/test_file_port
	./build/test_file_port

test_string_to_number: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_string_to_number.scm > build/test_string_to_number_input.scm
	$(ULISP_COMPILER) build/test_string_to_number_input.scm > build/test_string_to_number.s
	$(AS) $(ASFLAGS) build/test_string_to_number.s -o build/test_string_to_number.o
	$(LD) $(LDFLAGS) build/test_string_to_number.o -o build/test_string_to_number
	./build/test_string_to_number

test_max_min: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_max_min.scm > build/test_max_min_input.scm
	$(ULISP_COMPILER) build/test_max_min_input.scm > build/test_max_min.s
	$(AS) $(ASFLAGS) build/test_max_min.s -o build/test_max_min.o
	$(LD) $(LDFLAGS) build/test_max_min.o -o build/test_max_min
	./build/test_max_min

test_format: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_format.scm > build/test_format_input.scm
	$(ULISP_COMPILER) build/test_format_input.scm > build/test_format.s
	$(AS) $(ASFLAGS) build/test_format.s -o build/test_format.o
	$(LD) $(LDFLAGS) build/test_format.o -o build/test_format
	./build/test_format

test_sort: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_sort.scm > build/test_sort_input.scm
	$(ULISP_COMPILER) build/test_sort_input.scm > build/test_sort.s
	$(AS) $(ASFLAGS) build/test_sort.s -o build/test_sort.o
	$(LD) $(LDFLAGS) build/test_sort.o -o build/test_sort
	./build/test_sort

test_printer: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_printer.scm > build/test_printer_input.scm
	$(ULISP_COMPILER) build/test_printer_input.scm > build/test_printer.s
	$(AS) $(ASFLAGS) build/test_printer.s -o build/test_printer.o
	$(LD) $(LDFLAGS) build/test_printer.o -o build/test_printer
	./build/test_printer

test_char: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_char.scm > build/test_char_input.scm
	$(ULISP_COMPILER) build/test_char_input.scm > build/test_char.s
	$(AS) $(ASFLAGS) build/test_char.s -o build/test_char.o
	$(LD) $(LDFLAGS) build/test_char.o -o build/test_char
	./build/test_char

test_process_context: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_process_context.scm > build/test_process_context_input.scm
	$(ULISP_COMPILER) build/test_process_context_input.scm > build/test_process_context.s
	$(AS) $(ASFLAGS) build/test_process_context.s -o build/test_process_context.o
	$(LD) $(LDFLAGS) build/test_process_context.o -o build/test_process_context
	./build/test_process_context

test_eval_load_repl: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_eval_load_repl.scm > build/test_eval_load_repl_input.scm
	$(ULISP_COMPILER) build/test_eval_load_repl_input.scm > build/test_eval_load_repl.s
	$(AS) $(ASFLAGS) build/test_eval_load_repl.s -o build/test_eval_load_repl.o
	$(LD) $(LDFLAGS) build/test_eval_load_repl.o -o build/test_eval_load_repl
	./build/test_eval_load_repl

test_r7rs_cond_expand: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_r7rs_cond_expand.scm > build/test_r7rs_cond_expand_input.scm
	$(ULISP_COMPILER) build/test_r7rs_cond_expand_input.scm > build/test_r7rs_cond_expand.s
	$(AS) $(ASFLAGS) build/test_r7rs_cond_expand.s -o build/test_r7rs_cond_expand.o
	$(LD) $(LDFLAGS) build/test_r7rs_cond_expand.o -o build/test_r7rs_cond_expand
	./build/test_r7rs_cond_expand

test_r7rs_include_ci: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_r7rs_include_ci.scm > build/test_r7rs_include_ci_input.scm
	$(ULISP_COMPILER) build/test_r7rs_include_ci_input.scm > build/test_r7rs_include_ci.s
	$(AS) $(ASFLAGS) build/test_r7rs_include_ci.s -o build/test_r7rs_include_ci.o
	$(LD) $(LDFLAGS) build/test_r7rs_include_ci.o -o build/test_r7rs_include_ci
	./build/test_r7rs_include_ci

test_r7rs_bytevector_ports: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_r7rs_bytevector_ports.scm > build/test_r7rs_bytevector_ports_input.scm
	$(ULISP_COMPILER) build/test_r7rs_bytevector_ports_input.scm > build/test_r7rs_bytevector_ports.s
	$(AS) $(ASFLAGS) build/test_r7rs_bytevector_ports.s -o build/test_r7rs_bytevector_ports.o
	$(LD) $(LDFLAGS) build/test_r7rs_bytevector_ports.o -o build/test_r7rs_bytevector_ports
	./build/test_r7rs_bytevector_ports

test_r7rs_time: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_r7rs_time.scm > build/test_r7rs_time_input.scm
	$(ULISP_COMPILER) build/test_r7rs_time_input.scm > build/test_r7rs_time.s
	$(AS) $(ASFLAGS) build/test_r7rs_time.s -o build/test_r7rs_time.o
	$(LD) $(LDFLAGS) build/test_r7rs_time.o -o build/test_r7rs_time
	./build/test_r7rs_time

test_srfi_141_division: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_srfi_141_division.scm > build/test_srfi_141_division_input.scm
	$(ULISP_COMPILER) build/test_srfi_141_division_input.scm > build/test_srfi_141_division.s
	$(AS) $(ASFLAGS) build/test_srfi_141_division.s -o build/test_srfi_141_division.o
	$(LD) $(LDFLAGS) build/test_srfi_141_division.o -o build/test_srfi_141_division
	./build/test_srfi_141_division

test_srfi_111_boxes: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_srfi_111_boxes.scm > build/test_srfi_111_boxes_input.scm
	$(ULISP_COMPILER) build/test_srfi_111_boxes_input.scm > build/test_srfi_111_boxes.s
	$(AS) $(ASFLAGS) build/test_srfi_111_boxes.s -o build/test_srfi_111_boxes.o
	$(LD) $(LDFLAGS) build/test_srfi_111_boxes.o -o build/test_srfi_111_boxes
	./build/test_srfi_111_boxes

test_srfi_145_assume: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_srfi_145_assume.scm > build/test_srfi_145_assume_input.scm
	$(ULISP_COMPILER) build/test_srfi_145_assume_input.scm > build/test_srfi_145_assume.s
	$(AS) $(ASFLAGS) build/test_srfi_145_assume.s -o build/test_srfi_145_assume.o
	$(LD) $(LDFLAGS) build/test_srfi_145_assume.o -o build/test_srfi_145_assume
	./build/test_srfi_145_assume

test_comparator: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_comparator.scm > build/test_comparator_input.scm
	$(ULISP_COMPILER) build/test_comparator_input.scm > build/test_comparator.s
	$(AS) $(ASFLAGS) build/test_comparator.s -o build/test_comparator.o
	$(LD) $(LDFLAGS) build/test_comparator.o -o build/test_comparator
	./build/test_comparator

test_set: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) lib/set.scm tests/test_set.scm > build/test_set_input.scm
	$(ULISP_COMPILER) build/test_set_input.scm > build/test_set.s
	$(AS) $(ASFLAGS) build/test_set.s -o build/test_set.o
	$(LD) $(LDFLAGS) build/test_set.o -o build/test_set
	./build/test_set

test_srfi_41_streams: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) lib/stream.scm tests/test_srfi_41_streams.scm > build/test_srfi_41_streams_input.scm
	$(ULISP_COMPILER) build/test_srfi_41_streams_input.scm > build/test_srfi_41_streams.s
	$(AS) $(ASFLAGS) build/test_srfi_41_streams.s -o build/test_srfi_41_streams.o
	$(LD) $(LDFLAGS) build/test_srfi_41_streams.o -o build/test_srfi_41_streams
	./build/test_srfi_41_streams

test_generator: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) lib/generator.scm tests/test_generator.scm > build/test_generator_input.scm
	$(ULISP_COMPILER) build/test_generator_input.scm > build/test_generator.s
	$(AS) $(ASFLAGS) build/test_generator.s -o build/test_generator.o
	$(LD) $(LDFLAGS) build/test_generator.o -o build/test_generator
	./build/test_generator

test_list_queue_lseq: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) lib/generator.scm lib/list-queue.scm lib/lseq.scm tests/test_list_queue_lseq.scm > build/test_list_queue_lseq_input.scm
	$(ULISP_COMPILER) build/test_list_queue_lseq_input.scm > build/test_list_queue_lseq.s
	$(AS) $(ASFLAGS) build/test_list_queue_lseq.s -o build/test_list_queue_lseq.o
	$(LD) $(LDFLAGS) build/test_list_queue_lseq.o -o build/test_list_queue_lseq
	./build/test_list_queue_lseq

test_charset: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) lib/charset.scm tests/test_charset.scm > build/test_charset_input.scm
	$(ULISP_COMPILER) build/test_charset_input.scm > build/test_charset.s
	$(AS) $(ASFLAGS) build/test_charset.s -o build/test_charset.o
	$(LD) $(LDFLAGS) build/test_charset.o -o build/test_charset
	./build/test_charset

test_mapping: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) lib/mapping.scm tests/test_mapping.scm > build/test_mapping_input.scm
	$(ULISP_COMPILER) build/test_mapping_input.scm > build/test_mapping.s
	$(AS) $(ASFLAGS) build/test_mapping.s -o build/test_mapping.o
	$(LD) $(LDFLAGS) build/test_mapping.o -o build/test_mapping
	./build/test_mapping

test_ilist_ideque: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) lib/ilist.scm lib/ideque.scm tests/test_ilist_ideque.scm > build/test_ilist_ideque_input.scm
	$(ULISP_COMPILER) build/test_ilist_ideque_input.scm > build/test_ilist_ideque.s
	$(AS) $(ASFLAGS) build/test_ilist_ideque.s -o build/test_ilist_ideque.o
	$(LD) $(LDFLAGS) build/test_ilist_ideque.o -o build/test_ilist_ideque
	./build/test_ilist_ideque

test_gc_growth: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_gc_growth.scm > build/test_gc_growth_input.scm
	$(ULISP_COMPILER) build/test_gc_growth_input.scm > build/test_gc_growth.s
	$(AS) $(ASFLAGS) build/test_gc_growth.s -o build/test_gc_growth.o
	$(LD) $(LDFLAGS) build/test_gc_growth.o -o build/test_gc_growth
	./build/test_gc_growth

test_gc_profile: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_gc_profile.scm > build/test_gc_profile_input.scm
	$(ULISP_COMPILER) build/test_gc_profile_input.scm > build/test_gc_profile.s
	$(AS) $(ASFLAGS) build/test_gc_profile.s -o build/test_gc_profile.o
	$(LD) $(LDFLAGS) build/test_gc_profile.o -o build/test_gc_profile
	@echo "--- 1. Testing Default (Standard) Profile ---"
	env -u ULISP_GC_PROFILE ./build/test_gc_profile
	@echo "--- 2. Testing ULISP_GC_PROFILE=compiler ---"
	ULISP_GC_PROFILE=compiler ./build/test_gc_profile
	@echo "--- 3. Testing ULISP_GC_PROFILE=server ---"
	ULISP_GC_PROFILE=server ./build/test_gc_profile
	@echo "=== All GC Execution Profile Tests Passed! ==="

test_gc_hybrid: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_gc_hybrid.scm > build/test_gc_hybrid_input.scm
	$(ULISP_COMPILER) build/test_gc_hybrid_input.scm > build/test_gc_hybrid.s
	$(AS) $(ASFLAGS) build/test_gc_hybrid.s -o build/test_gc_hybrid.o
	$(LD) $(LDFLAGS) build/test_gc_hybrid.o -o build/test_gc_hybrid
	@echo "--- 1. Testing Hybrid Exact-Conservative Scanning (Standard) ---"
	./build/test_gc_hybrid
	@echo "--- 2. Testing Hybrid Scanning with DEBUG_GC=1 ---"
	DEBUG_GC=1 ./build/test_gc_hybrid
	@echo "=== All Hybrid Scanning Tests Passed! ==="

test_gc_stress: $(COMPILER_DEP)
	@mkdir -p build
	@echo "--- 1. Testing Native x86-64 Backend with ULISP_GC_STRESS=1 ---"
	cat $(ULISP_STD_LIBS) tests/test_gc_stress.scm > build/test_gc_stress_input.scm
	$(ULISP_COMPILER) build/test_gc_stress_input.scm > build/test_gc_stress_native.s
	$(AS) $(ASFLAGS) build/test_gc_stress_native.s -o build/test_gc_stress_native.o
	$(LD) $(LDFLAGS) build/test_gc_stress_native.o -o build/test_gc_stress_native
	ULISP_GC_STRESS=1 ./build/test_gc_stress_native
	@echo "--- 2. Testing Native x86-64 Backend with (!gc stress) Directive ---"
	echo '(!gc stress)' > build/test_gc_stress_directive_input.scm
	cat $(ULISP_STD_LIBS) tests/test_gc_stress.scm >> build/test_gc_stress_directive_input.scm
	$(ULISP_COMPILER) build/test_gc_stress_directive_input.scm > build/test_gc_stress_directive.s
	$(AS) $(ASFLAGS) build/test_gc_stress_directive.s -o build/test_gc_stress_directive.o
	$(LD) $(LDFLAGS) build/test_gc_stress_directive.o -o build/test_gc_stress_directive
	./build/test_gc_stress_directive
	@echo "--- 3. Testing Portable C Backend with ULISP_GC_STRESS=1 ---"
	echo '(!target c)' > build/test_gc_stress_c_input.scm
	cat lib/char.scm lib/string.scm lib/vector.scm tests/test_gc_stress.scm >> build/test_gc_stress_c_input.scm
	$(ULISP_COMPILER) build/test_gc_stress_c_input.scm > build/test_gc_stress_c.c
	$(CC) $(CFLAGS) build/test_gc_stress_c.c -o build/test_gc_stress_c
	ULISP_GC_STRESS=1 ./build/test_gc_stress_c
	@echo "--- 4. Testing Portable C Backend with (!gc stress) Directive ---"
	echo '(!target c)' > build/test_gc_stress_c_directive_input.scm
	echo '(!gc stress)' >> build/test_gc_stress_c_directive_input.scm
	cat lib/char.scm lib/string.scm lib/vector.scm tests/test_gc_stress.scm >> build/test_gc_stress_c_directive_input.scm
	$(ULISP_COMPILER) build/test_gc_stress_c_directive_input.scm > build/test_gc_stress_c_directive.c
	$(CC) $(CFLAGS) build/test_gc_stress_c_directive.c -o build/test_gc_stress_c_directive
	./build/test_gc_stress_c_directive
	@echo "=== All GC Stress Tests Passed Successfully! ==="

test_freestanding: compiler
	@echo "=== Running Zero-libc Bare-Metal Freestanding Tests ==="
	@PYTHONPATH=$(ROOT_DIR) $(PYTHON) -m pytest $(ROOT_DIR)/tests/test_bare_metal_ulisp.py -v

test_c: compiler
	./test_c.sh

core: build/ulisp_core.scm

build/ulisp_core.scm: $(ULISP_STD_LIBS) compiler.scm
	@mkdir -p build
	echo '(!gc none)' > $@
	cat $^ >> $@

build/stage1.s: compiler.scm build/ulisp_core.scm
	@mkdir -p build
	@if [ -x "$(ULISP_BOOT)" ] && [ "$(FULL_BOOTSTRAP)" != "1" ]; then \
		echo "=== Stage 1: Fast compiling with native seed $(ULISP_BOOT) ==="; \
		./$(ULISP_BOOT) < build/ulisp_core.scm > $@; \
	else \
		echo "=== Stage 1: Compiling with ILisp $(ILISP) ==="; \
		$(RUN_SCHEME) compiler.scm < build/ulisp_core.scm > $@; \
	fi


build/stage1.o: build/stage1.s
	$(AS) $(ASFLAGS) $< -o $@

build/scheme-stage1: build/stage1.o
	$(LD) $(LDFLAGS) $< -o $@

stage1: build/scheme-stage1
bootstrap_stage1: stage1

build/stage2.s: build/scheme-stage1 build/ulisp_core.scm
	@mkdir -p build
	./build/scheme-stage1 < build/ulisp_core.scm > $@

build/stage2.o: build/stage2.s
	$(AS) $(ASFLAGS) $< -o $@

build/scheme-stage2: build/stage2.o
	$(LD) $(LDFLAGS) $< -o $@

stage2: build/scheme-stage2
bootstrap_stage2: stage2

build/stage3.s: build/scheme-stage2 build/ulisp_core.scm
	@mkdir -p build
	./build/scheme-stage2 < build/ulisp_core.scm > $@

build/stage3.o: build/stage3.s
	$(AS) $(ASFLAGS) $< -o $@

build/scheme-stage3: build/stage3.o
	$(LD) $(LDFLAGS) $< -o $@

stage3: build/scheme-stage3
bootstrap_stage3: stage3

bootstrap_verify: stage2 stage3
	@echo "=== Verifying 3-Stage Bootstrap Fixed Point (stage2.s vs stage3.s) ==="
	@if cmp -s build/stage2.s build/stage3.s; then \
		echo "SUCCESS: Fixed-point convergence confirmed (Stage 2 and Stage 3 outputs are bit-for-bit identical)!"; \
		mkdir -p bin; \
		cp -f build/scheme-stage2 bin/ulisp-boot; \
		chmod +x bin/ulisp-boot; \
		echo "Seed binary bin/ulisp-boot updated successfully."; \
	else \
		echo "FAILURE: Discrepancy detected between stage2.s and stage3.s"; \
		diff -u build/stage2.s build/stage3.s | head -n 50; \
		exit 1; \
	fi

# --- SCM to x86_64 Assembly Compilation Macro ---
# Prioritizes:
# 1. Verified seed binary bin/ulisp-boot (fastest & most stable host)
# 2. Fully self-hosted modular binary build/ulisp-modular
# 3. Intermediate split binary build/ulisp-fast
# 4. Bootstrap stages (stage2 -> stage1)
# 5. External host Scheme (gosh -> python/ilisp)
define COMPILE_SCM_TO_S
	@if [ -x "$(ULISP_BOOT)" ] && [ "$(FULL_BOOTSTRAP)" != "1" ]; then \
		env ULISP_GC_PROFILE=compiler ./$(ULISP_BOOT) < $(1) > $(2); \
	elif [ -x "build/ulisp-modular" ]; then \
		env ULISP_GC_PROFILE=compiler ./build/ulisp-modular < $(1) > $(2); \
	elif [ -x "build/ulisp-fast" ]; then \
		env ULISP_GC_PROFILE=compiler ./build/ulisp-fast < $(1) > $(2); \
	elif [ -x "build/scheme-stage2" ]; then \
		env ULISP_GC_PROFILE=compiler ./build/scheme-stage2 < $(1) > $(2); \
	elif [ -x "build/scheme-stage1" ]; then \
		env ULISP_GC_PROFILE=compiler ./build/scheme-stage1 < $(1) > $(2); \
	elif [ -n "$(GOSH_BIN)" ]; then \
		$(GOSH_BIN) compiler.scm < $(1) > $(2); \
	else \
		$(RUN_SCHEME) compiler.scm < $(1) > $(2); \
	fi
endef

# --- Modular 2-Split Static Linking Targets (Issue #607) ---
build/ulisp_stdlib.s: compiler.scm stdlib_entry.scm $(ULISP_STD_LIBS)
	@mkdir -p build
	@echo "=== Compiling Standard Library Module (stdlib_entry.scm) ==="
	@echo "(!gc none) (!module #t)" > build/stdlib_input.scm
	@cat stdlib_entry.scm >> build/stdlib_input.scm
	$(call COMPILE_SCM_TO_S,build/stdlib_input.scm,$@)

build/ulisp_stdlib.o: build/ulisp_stdlib.s
	$(AS) $(ASFLAGS) $< -o $@

build/ulisp_compiler.s: compiler.scm compiler_entry.scm $(COMPILER_BASE) $(FRONTEND_PASSES) $(LIR_PASSES) $(BACKEND_PASSES) compiler/driver.scm
	@mkdir -p build
	@echo "=== Compiling Compiler Module (compiler_entry.scm) ==="
	@echo "(!gc none) (!allow-extern #t)" > build/compiler_input.scm
	@cat compiler_entry.scm >> build/compiler_input.scm
	$(call COMPILE_SCM_TO_S,build/compiler_input.scm,$@)

build/ulisp_compiler.o: build/ulisp_compiler.s
	$(AS) $(ASFLAGS) $< -o $@

build/ulisp-fast: build/ulisp_stdlib.o build/ulisp_compiler.o
	@mkdir -p build
	@echo "=== Statically Linking Split Objects (ulisp_stdlib.o + ulisp_compiler.o) ==="
	$(LD) $(LDFLAGS) $^ -o $@

test_split_link: build/ulisp-fast
	@echo "=== Verifying 2-Split Statically Linked Compiler Binary (build/ulisp-fast) ==="
	cat $(ULISP_STD_LIBS) > build/test_split_input.scm
	@echo '(display "Hello from split-linked ULisp!\n") (display (+ 123 456)) (newline)' >> build/test_split_input.scm
	./build/ulisp-fast build/test_split_input.scm > build/test_split.s
	$(AS) $(ASFLAGS) build/test_split.s -o build/test_split.o
	$(LD) $(LDFLAGS) build/test_split.o -o build/test_split
	@echo "Executing compiled test binary:"
	@res=$$(./build/test_split | tr -d '\r\n'); \
	echo "Output: $$res"; \
	test "$$res" = "Hello from split-linked ULisp!579"
	@echo "SUCCESS: 2-split static linking verification PASSED!"

# --- Modular Separate Compilation & Incremental Build (Issue #608) ---
build/meta/compiler_env.sbi: compiler/module_header.scm
	@mkdir -p build/meta
	cp $< $@

build/compiler_base.s: $(COMPILER_BASE) build/meta/compiler_env.sbi
	@mkdir -p build
	@echo "=== Compiling Compiler Base Module ==="
	@echo "(!gc none) (!module-name compiler_base) (!import-sbi build/meta/compiler_env.sbi)" > build/compiler_base_in.scm
	@cat $(COMPILER_BASE) >> build/compiler_base_in.scm
	$(call COMPILE_SCM_TO_S,build/compiler_base_in.scm,$@)

build/compiler_base.o: build/compiler_base.s
	$(AS) $(ASFLAGS) $< -o $@

build/frontend_passes.s: $(FRONTEND_PASSES) build/meta/compiler_env.sbi
	@mkdir -p build
	@echo "=== Compiling Frontend Passes Module ==="
	@echo "(!gc none) (!module-name frontend_passes) (!import-sbi build/meta/compiler_env.sbi)" > build/frontend_passes_in.scm
	@cat $(FRONTEND_PASSES) >> build/frontend_passes_in.scm
	$(call COMPILE_SCM_TO_S,build/frontend_passes_in.scm,$@)

build/frontend_passes.o: build/frontend_passes.s
	$(AS) $(ASFLAGS) $< -o $@

build/lir_passes.s: $(LIR_PASSES) build/meta/compiler_env.sbi
	@mkdir -p build
	@echo "=== Compiling LIR Passes Module ==="
	@echo "(!gc none) (!module-name lir_passes) (!import-sbi build/meta/compiler_env.sbi)" > build/lir_passes_in.scm
	@cat $(LIR_PASSES) >> build/lir_passes_in.scm
	$(call COMPILE_SCM_TO_S,build/lir_passes_in.scm,$@)

build/lir_passes.o: build/lir_passes.s
	$(AS) $(ASFLAGS) $< -o $@

build/backend_passes.s: $(BACKEND_PASSES) build/meta/compiler_env.sbi
	@mkdir -p build
	@echo "=== Compiling Backend Passes Module ==="
	@echo "(!gc none) (!module-name backend_passes) (!import-sbi build/meta/compiler_env.sbi)" > build/backend_passes_in.scm
	@cat $(BACKEND_PASSES) >> build/backend_passes_in.scm
	$(call COMPILE_SCM_TO_S,build/backend_passes_in.scm,$@)

build/backend_passes.o: build/backend_passes.s
	$(AS) $(ASFLAGS) $< -o $@

build/compiler_driver.s: compiler/driver.scm build/meta/compiler_env.sbi
	@mkdir -p build
	@echo "=== Compiling Driver Module ==="
	@echo "(!gc none) (!allow-extern #t) (!import-sbi build/meta/compiler_env.sbi)" > build/compiler_driver_in.scm
	@cat compiler/driver.scm >> build/compiler_driver_in.scm
	$(call COMPILE_SCM_TO_S,build/compiler_driver_in.scm,$@)

build/compiler_driver.o: build/compiler_driver.s
	$(AS) $(ASFLAGS) $< -o $@

MODULAR_COMPILER_OBJS = build/ulisp_stdlib.o \
                        build/compiler_base.o \
                        build/frontend_passes.o \
                        build/lir_passes.o \
                        build/backend_passes.o \
                        build/compiler_driver.o

build/ulisp-modular: $(MODULAR_COMPILER_OBJS)
	@mkdir -p build bin
	@echo "=== Statically Linking Modular ULisp Binary ($@) ==="
	$(LD) $(LDFLAGS) $^ -o $@
	cp $@ bin/ulisp-modular
	cp $@ bin/ulisp-modular

test_incremental: build/ulisp-modular
	@bash tests/test_incremental_build.sh


bootstrap: core
	./bootstrap.sh

bootstrap_diagnose: core
	BOOTSTRAP_DIAGNOSE=1 ./bootstrap.sh

test_bootstrap_diagnostics:
	@bash tests/test_bootstrap_diagnostics.sh

# --- JIT Component Tests (94 Tests) ---
build/test_delimcc_runner.scm: jit/core/delimcc.scm tests/jit/test_delimcc.scm
	@mkdir -p build
	cat $^ > $@

test_delimcc: build/test_delimcc_runner.scm
	@$(RUN_SCHEME) build/test_delimcc_runner.scm

build/test_tracer_runner.scm: jit/core/delimcc.scm jit/tracer/tracer.scm tests/jit/test_tracer.scm
	@mkdir -p build
	cat $^ > $@

test_tracer: build/test_tracer_runner.scm
	@$(RUN_SCHEME) build/test_tracer_runner.scm

build/test_auto_instrument_runner.scm: jit/core/delimcc.scm jit/tracer/tracer.scm jit/tracer/auto_instrument.scm tests/jit/test_auto_instrument.scm
	@mkdir -p build
	cat $^ > $@

test_auto_instrument: build/test_auto_instrument_runner.scm
	@$(RUN_SCHEME) build/test_auto_instrument_runner.scm

build/test_optimizer_runner.scm: jit/core/delimcc.scm jit/tracer/tracer.scm jit/optimizer/pe.scm jit/optimizer/virtuals.scm tests/jit/test_optimizer.scm
	@mkdir -p build
	cat $^ > $@

test_optimizer: build/test_optimizer_runner.scm
	@$(RUN_SCHEME) build/test_optimizer_runner.scm

build/test_bridge_runner.scm: jit/core/delimcc.scm jit/tracer/tracer.scm jit/optimizer/pe.scm jit/optimizer/virtuals.scm jit/bridge/to_lir.scm jit/runtime/jit_buffer.scm tests/jit/test_bridge.scm
	@mkdir -p build
	cat $^ > $@

test_bridge: build/test_bridge_runner.scm
	@$(RUN_SCHEME) build/test_bridge_runner.scm

build/test_examples_runner.scm: jit/core/delimcc.scm jit/tracer/tracer.scm jit/optimizer/pe.scm jit/optimizer/virtuals.scm jit/bridge/to_lir.scm jit/runtime/jit_buffer.scm jit/examples/tiny_vm.scm jit/examples/scheme_eval.scm tests/jit/test_examples.scm
	@mkdir -p build
	cat $^ > $@

test_examples: build/test_examples_runner.scm
	@$(RUN_SCHEME) build/test_examples_runner.scm

build/test_guard_elimination_runner.scm: jit/core/delimcc.scm jit/tracer/tracer.scm jit/optimizer/pe.scm jit/optimizer/virtuals.scm jit/bridge/to_lir.scm jit/runtime/jit_buffer.scm tests/jit/test_guard_elimination.scm
	@mkdir -p build
	cat $^ > $@

test_guard_elimination: build/test_guard_elimination_runner.scm
	@$(RUN_SCHEME) build/test_guard_elimination_runner.scm

test_jit: test_delimcc test_tracer test_auto_instrument test_optimizer test_guard_elimination test_bridge test_examples
	@echo "=== [All JIT Component Tests Passed: 112/112] ==="

build/demo_runner.scm: jit/core/delimcc.scm jit/tracer/tracer.scm jit/optimizer/pe.scm jit/optimizer/virtuals.scm jit/bridge/to_lir.scm jit/runtime/jit_buffer.scm jit/examples/tiny_vm.scm jit/examples/scheme_eval.scm jit/examples/demo.scm
	@mkdir -p build
	cat $^ > $@

demo: build/demo_runner.scm
	@$(RUN_SCHEME) build/demo_runner.scm


# --- Unified JIT Binary: bin/ulisp-jit ---
build/ulisp_jit_combined.scm: lib/posix.scm lib/list.scm lib/predicates.scm lib/math.scm lib/char.scm lib/string.scm lib/port.scm lib/printer.scm lib/reader.scm lib/exception.scm lib/values.scm lib/gc.scm build/compiler_passes.scm driver/jit.scm
	@mkdir -p build
	cat $^ > $@

build/ulisp_jit.s: build/ulisp_jit_combined.scm compiler.scm
	@mkdir -p build
	@if [ -x build/scheme-stage2 ]; then \
		echo "=== Compiling ulisp_jit using Stage 2 compiler ==="; \
		./build/scheme-stage2 < build/ulisp_jit_combined.scm > $@; \
	elif [ -x "$(ULISP_BOOT)" ]; then \
		echo "=== Compiling ulisp_jit using native seed $(ULISP_BOOT) ==="; \
		./$(ULISP_BOOT) < build/ulisp_jit_combined.scm > $@; \
	else \
		echo "=== Compiling ulisp_jit with ILisp $(ILISP) ==="; \
		$(RUN_SCHEME) compiler.scm < $< > $@; \
	fi



build/ulisp_jit.o: build/ulisp_jit.s
	$(AS) $(ASFLAGS) $< -o $@

bin/ulisp-jit: build/ulisp_jit.o
	@mkdir -p bin
	$(LD) $(LDFLAGS) -o $@ $<
	@echo "Successfully compiled native standalone ulisp-jit binary: $@"

jit: bin/ulisp-jit

run_jit: bin/ulisp-jit
	@echo "=== [1/2] Verifying ulisp-jit JIT Loop Execution ==="
	@echo "(let loop ((i 0) (sum 0)) (if (< i 10) (loop (+ i 1) (+ sum i)) sum))" > build/test_jit_eval.scm
	@./bin/ulisp-jit build/test_jit_eval.scm
	@echo "=== [2/2] Verifying ulisp-jit AOT Compilation ==="
	@printf "(!compile)\n(define (fact n) (if (<= n 1) 1 (* n (fact (- n 1)))))\n(fact 5)\n" > build/test_jit_aot.scm
	@./bin/ulisp-jit build/test_jit_aot.scm > build/test_jit_aot.s
	@$(AS) $(ASFLAGS) build/test_jit_aot.s -o build/test_jit_aot.o
	@$(LD) $(LDFLAGS) -o build/test_jit_aot build/test_jit_aot.o
	@test "$$(./build/test_jit_aot)" = "120"
	@echo "SUCCESS: ulisp-jit AOT compilation verified (fact 5) = 120!"

# --- Performance Benchmark ---
bench: compiler
	@mkdir -p build
	$(PYTHON) benchmarks/benchmark_c_vs_x86.py

bench_baseline: compiler
	@mkdir -p build
	$(PYTHON) benchmarks/benchmark_c_vs_x86.py --perf --iterations 30 --warmup 5 --baseline

bench_verify: compiler
	@mkdir -p build
	$(PYTHON) benchmarks/benchmark_c_vs_x86.py --perf --iterations 5
	$(PYTHON) benchmarks/verify_regression.py --threshold-latency 15.0 --threshold-size 5.0

bench_stage2_vs_jit: bin/ulisp-jit
	$(PYTHON) benchmarks/benchmark_stage2_vs_ulisp_jit.py

bench_trio: bin/ulisp-jit
	$(PYTHON) $(ROOT_DIR)/tools/benchmark_ilisp_ulisp.py --iterations 10

bench_perf: compiler
	$(PYTHON) benchmarks/benchmark_c_vs_x86.py --perf

bench_ci: bin/ulisp-jit
	$(PYTHON) $(ROOT_DIR)/tools/benchmark_ilisp_ulisp.py --iterations 5 --compare $(ROOT_DIR)/outputs/benchmarks/latest.json --threshold 2.5

diff_test: bin/ulisp-jit
	$(PYTHON) $(ROOT_DIR)/tools/differential_test_ulisp.py

# --- Comprehensive Test Suite ---
test_aot: core
	./test.sh

test_gc_stats: compiler
	@echo "=== Running Runtime GC Statistics Tests (Issue #622) ==="
	bash tests/test_gc_stats.sh

test_numeric_tower: $(COMPILER_DEP)
	@echo "=== Running R7RS Numeric Tower Tests (Issues #711-#715) ==="
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_numeric_tower.scm > build/test_numeric_tower_input.scm
	$(ULISP_COMPILER) build/test_numeric_tower_input.scm > build/test_numeric_tower.s
	$(AS) $(ASFLAGS) build/test_numeric_tower.s -o build/test_numeric_tower.o
	$(LD) $(LDFLAGS) build/test_numeric_tower.o -o build/test_numeric_tower
	./build/test_numeric_tower < /dev/null
	@echo "SUCCESS: All R7RS Numeric Tower tests passed!"

test: test_lint_sexpr test_r7rs_traceability test_reader_eof test_passes test_pass_manager test_pass_split_planes test_pass_check_affine test_pass_fbip test_pass_inline_hotpath test_pass_inject_safepoints test_profiler test_dataflow test_scope test_include_source_loc test_runtime test_arena test_atomic test_queue test_channel test_boundary test_epoch test_context_switch test_scheduler test_multithread_scheduler test_links_monitors test_task_mailbox test_let_it_crash test_supervisor test_futex test_registry test_crash_logger test_io_uring test_preemption test_eval_adapter test_concurrency_harness test_annotator test_rtyper test_lir test_aarch64 test_exceptions test_values test_call_cc test_eqv test_syntax_rules test_ports test_record test_promise test_case_lambda test_stdlib test_base_procedures test_srfi1 test_hashtable test_letrec_star test_file_port test_string_to_number test_max_min test_format test_sort test_printer test_char test_process_context test_gc_growth test_gc_profile test_gc_hybrid test_gc_stress test_gc_stats test_jit test_c test_aot

clean:
	rm -f tmp tmp_bin *.s *.o *.log
	@if [ -d build ]; then \
		find build -mindepth 1 ! -name 'scheme-stage*' ! -name 'stage*.s' ! -name 'stage*.o' -delete; \
	fi

distclean:
	rm -f tmp tmp_bin *.s *.o *.log
	rm -rf build bin

