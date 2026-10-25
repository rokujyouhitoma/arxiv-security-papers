.PHONY: all test test_aot test_jit test_c test_aarch64 test_freestanding bootstrap bootstrap_diagnose test_bootstrap_diagnostics bootstrap_verify clean distclean run_42 run_c_42 core compiler test_nanopass test_passes test_verifier test_lir_verifier test_pass_manager test_dataflow test_runtime test_annotator test_lvn test_rtyper test_contify test_alias_escape test_lir test_lir_suite test_backend test_hierarchical stage1 stage2 stage3 bootstrap_stage1 bootstrap_stage2 bootstrap_stage3 jit bin run_jit bench demo \
        test_delimcc test_tracer test_auto_instrument test_optimizer test_guard_elimination test_bridge test_examples test_exceptions test_values test_call_cc test_eqv test_syntax_rules test_ports test_record test_promise test_stdlib test_gc_growth test_gc_profile test_gc_hybrid test_gc_stress

CC = gcc
CFLAGS = -Wall -Wextra -O0 -g
CFLAGS_JIT = -no-pie -Wall -O2

ROOT_DIR = $(shell dirname $(CURDIR))
PYTHON = $(shell if [ -x $(ROOT_DIR)/.venv/bin/python ]; then echo $(ROOT_DIR)/.venv/bin/python; else echo python3; fi)
ILISP = $(PYTHON) -m ilisp
ULISP_BOOT = bin/ulisp-boot
RUN_SCHEME = PYTHONPATH=$(ROOT_DIR) $(ILISP)

# --- 処理系エンジンの決定 (ULISP_BOOT があれば優先、なければ ILISP を使用) ---
ifeq ($(shell test -x $(ULISP_BOOT) && echo yes),yes)
    ULISP_COMPILER ?= ./$(ULISP_BOOT)
    COMPILER_DEP = $(ULISP_BOOT)
    USE_NATIVE_BOOT = 1
else
    ULISP_COMPILER ?= $(RUN_SCHEME) compiler.scm <
    COMPILER_DEP =
    USE_NATIVE_BOOT = 0
endif

ULISP_RUNTIME_LIBS = runtime/gc.scm runtime/io.scm runtime/printer.scm runtime/entry.scm

ULISP_STD_LIBS = lib/posix.scm lib/list.scm lib/string.scm lib/port.scm lib/printer.scm \
                 lib/reader.scm lib/equality.scm lib/predicates.scm lib/math.scm lib/bytevector.scm \
                 lib/vector.scm lib/promise.scm lib/exception.scm lib/values.scm \
                 lib/continuation.scm lib/parameter.scm lib/gc.scm \
                 $(ULISP_RUNTIME_LIBS)

COMPILER_BASE = compiler/helpers.scm \
                compiler/primitives.scm \
                compiler/nanopass_meta.scm \
                compiler/nanopass.scm \
                compiler/verifier.scm \
                compiler/pass_manager.scm \
                compiler/dataflow.scm

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
                 backend/150_backend_aarch64.scm \
                 backend/160_backend_c.scm

PASSES_LIB = $(COMPILER_BASE) $(FRONTEND_PASSES) $(LIR_PASSES) $(BACKEND_PASSES)

PASSES = $(PASSES_LIB) compiler/driver.scm

all: test

compiler: compiler.scm

compiler.scm: $(PASSES)
	cat $(PASSES) > $@

build/compiler_passes.scm: $(PASSES_LIB)
	@mkdir -p build
	cat $^ > $@

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
                 tests/passes/test_160_backend_c.scm

test_all_passes: build/compiler_passes.scm
	@echo "=== Running 1:1 Nanopass Unit Tests (37 Passes) ==="
	@for t in $(NANOPASS_TESTS); do \
		echo "Running $$t..."; \
		cat build/compiler_passes.scm $$t > build/runner_temp.scm && \
		$(RUN_SCHEME) build/runner_temp.scm || exit 1; \
	done
	@echo "SUCCESS: All 37 1:1 Nanopass Unit Tests PASSED!"

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



test_library: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_library.scm > build/test_library_runner.scm
	@$(RUN_SCHEME) build/test_library_runner.scm
	$(CC) -nostdlib -static -o build/test_library build/test_library.s
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
	$(CC) -nostdlib -static build/test_runtime.s -o build/test_runtime
	./build/test_runtime < /dev/null

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
	$(CC) -nostdlib -static -o build/test_loop_reg build/test_loop_reg.s
	@echo "=== Executing compiled loop_sum binary (1,000,000 iters) ==="
	@res=$$(./build/test_loop_reg); echo "Output: $$res"; test "$$res" = "499999500000"
	@echo "SUCCESS: loop_sum output 499999500000 matches expected exactly!"

test_branch_fusion: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_branch_fusion.scm > build/test_branch_fusion_runner.scm
	@$(RUN_SCHEME) build/test_branch_fusion_runner.scm
	$(CC) -nostdlib -static -o build/test_predicates_fusion build/test_predicates_fusion.s
	@echo "=== Executing compiled predicates fusion binary ==="
	@res=$$(./build/test_predicates_fusion); echo "Output: $$res"; test "$$res" = "255"
	@echo "SUCCESS: branch fusion predicates output 255 (1+2+4+8+16+32+64+128) matches expected!"

test_inplace_shuffle: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_inplace_shuffle.scm > build/test_inplace_shuffle_runner.scm
	@$(RUN_SCHEME) build/test_inplace_shuffle_runner.scm
	$(CC) -nostdlib -static -o build/test_inplace_shuffle build/test_inplace_shuffle.s
	@echo "=== Executing compiled inplace shuffle loop_sum binary ==="
	@res=$$(./build/test_inplace_shuffle); echo "Output: $$res"; test "$$res" = "499999500000"
	@echo "SUCCESS: inplace shuffle loop_sum output 499999500000 matches expected exactly!"
	$(CC) -nostdlib -static -o build/test_swap_loop build/test_swap_loop.s
	@echo "=== Executing compiled swap_loop binary ==="
	@res=$$(./build/test_swap_loop); echo "Output: $$res"; test "$$res" = "10"
	@echo "SUCCESS: swap_loop output 10 (swap 10 20 -> 20 10 -> returns b=10) matches expected exactly!"
	$(CC) -nostdlib -static -o build/test_countdown build/test_countdown.s
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

test_hierarchical: test_lir_suite test_backend
	@echo "=== All Hierarchical LIR Tests Passed ==="

test_aarch64: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/test_backend_aarch64.scm > build/test_aarch64_runner.scm
	@$(RUN_SCHEME) build/test_aarch64_runner.scm

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

test_dataflow: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/test_dataflow.scm > build/test_dataflow_runner.scm
	@$(RUN_SCHEME) build/test_dataflow_runner.scm


test_exceptions: $(COMPILER_DEP)
	@mkdir -p build
	cat lib/posix.scm lib/string.scm lib/port.scm lib/printer.scm lib/reader.scm lib/exception.scm lib/gc.scm tests/test_exceptions.scm > build/test_exn_input.scm
	$(ULISP_COMPILER) build/test_exn_input.scm > build/test_exn.s
	$(CC) -nostdlib -static build/test_exn.s -o build/test_exn
	./build/test_exn

test_values: $(COMPILER_DEP)
	@mkdir -p build
	cat lib/posix.scm lib/string.scm lib/port.scm lib/printer.scm lib/reader.scm lib/equality.scm lib/predicates.scm lib/exception.scm lib/values.scm lib/gc.scm tests/test_values.scm > build/test_values_input.scm
	$(ULISP_COMPILER) build/test_values_input.scm > build/test_values.s
	$(CC) -nostdlib -static build/test_values.s -o build/test_values
	./build/test_values

test_call_cc: $(COMPILER_DEP)
	@mkdir -p build
	cat lib/posix.scm lib/string.scm lib/port.scm lib/printer.scm lib/reader.scm lib/equality.scm lib/predicates.scm lib/exception.scm lib/values.scm lib/continuation.scm lib/gc.scm tests/test_call_cc.scm > build/test_call_cc_input.scm
	$(ULISP_COMPILER) build/test_call_cc_input.scm > build/test_call_cc.s
	$(CC) -nostdlib -static build/test_call_cc.s -o build/test_call_cc
	./build/test_call_cc

test_eqv: $(COMPILER_DEP)
	@mkdir -p build
	cat lib/posix.scm lib/string.scm lib/port.scm lib/printer.scm lib/reader.scm lib/equality.scm lib/predicates.scm lib/exception.scm lib/values.scm lib/continuation.scm lib/gc.scm tests/test_eqv.scm > build/test_eqv_input.scm
	$(ULISP_COMPILER) build/test_eqv_input.scm > build/test_eqv.s
	$(CC) -nostdlib -static build/test_eqv.s -o build/test_eqv
	./build/test_eqv

test_syntax_rules: $(COMPILER_DEP)
	@mkdir -p build
	cat lib/posix.scm lib/string.scm lib/port.scm lib/printer.scm lib/reader.scm lib/equality.scm lib/predicates.scm lib/exception.scm lib/values.scm lib/continuation.scm lib/gc.scm tests/test_syntax_rules.scm > build/test_syntax_rules_input.scm
	$(ULISP_COMPILER) build/test_syntax_rules_input.scm > build/test_syntax_rules.s
	$(CC) -nostdlib -static build/test_syntax_rules.s -o build/test_syntax_rules
	./build/test_syntax_rules

test_ports: $(COMPILER_DEP)
	@mkdir -p build
	cat lib/posix.scm lib/string.scm lib/port.scm lib/printer.scm lib/reader.scm lib/equality.scm lib/predicates.scm lib/exception.scm lib/values.scm lib/continuation.scm lib/gc.scm tests/test_ports.scm > build/test_ports_input.scm
	$(ULISP_COMPILER) build/test_ports_input.scm > build/test_ports.s
	$(CC) -nostdlib -static build/test_ports.s -o build/test_ports
	./build/test_ports

test_record: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_record.scm > build/test_record_input.scm
	$(ULISP_COMPILER) build/test_record_input.scm > build/test_record.s
	$(CC) -nostdlib -static build/test_record.s -o build/test_record
	./build/test_record

test_promise: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_promise.scm > build/test_promise_input.scm
	$(ULISP_COMPILER) build/test_promise_input.scm > build/test_promise.s
	$(CC) -nostdlib -static build/test_promise.s -o build/test_promise
	./build/test_promise

test_stdlib: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_stdlib_r7rs.scm > build/test_stdlib_input.scm
	$(ULISP_COMPILER) build/test_stdlib_input.scm > build/test_stdlib.s
	$(CC) -nostdlib -static build/test_stdlib.s -o build/test_stdlib
	./build/test_stdlib

test_gc_growth: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_gc_growth.scm > build/test_gc_growth_input.scm
	$(ULISP_COMPILER) build/test_gc_growth_input.scm > build/test_gc_growth.s
	$(CC) -nostdlib -static build/test_gc_growth.s -o build/test_gc_growth
	./build/test_gc_growth

test_gc_profile: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_gc_profile.scm > build/test_gc_profile_input.scm
	$(ULISP_COMPILER) build/test_gc_profile_input.scm > build/test_gc_profile.s
	$(CC) -nostdlib -static build/test_gc_profile.s -o build/test_gc_profile
	@echo "--- 1. Testing Default (Standard) Profile ---"
	./build/test_gc_profile
	@echo "--- 2. Testing ULISP_GC_PROFILE=compiler ---"
	ULISP_GC_PROFILE=compiler ./build/test_gc_profile
	@echo "--- 3. Testing ULISP_GC_PROFILE=server ---"
	ULISP_GC_PROFILE=server ./build/test_gc_profile
	@echo "=== All GC Execution Profile Tests Passed! ==="

test_gc_hybrid: $(COMPILER_DEP)
	@mkdir -p build
	cat $(ULISP_STD_LIBS) tests/test_gc_hybrid.scm > build/test_gc_hybrid_input.scm
	$(ULISP_COMPILER) build/test_gc_hybrid_input.scm > build/test_gc_hybrid.s
	$(CC) -nostdlib -static build/test_gc_hybrid.s -o build/test_gc_hybrid
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
	$(CC) -nostdlib -static build/test_gc_stress_native.s -o build/test_gc_stress_native
	ULISP_GC_STRESS=1 ./build/test_gc_stress_native
	@echo "--- 2. Testing Native x86-64 Backend with (!gc stress) Directive ---"
	echo '(!gc stress)' > build/test_gc_stress_directive_input.scm
	cat $(ULISP_STD_LIBS) tests/test_gc_stress.scm >> build/test_gc_stress_directive_input.scm
	$(ULISP_COMPILER) build/test_gc_stress_directive_input.scm > build/test_gc_stress_directive.s
	$(CC) -nostdlib -static build/test_gc_stress_directive.s -o build/test_gc_stress_directive
	./build/test_gc_stress_directive
	@echo "--- 3. Testing Portable C Backend with ULISP_GC_STRESS=1 ---"
	echo '(!target c)' > build/test_gc_stress_c_input.scm
	cat lib/string.scm lib/vector.scm tests/test_gc_stress.scm >> build/test_gc_stress_c_input.scm
	$(ULISP_COMPILER) build/test_gc_stress_c_input.scm > build/test_gc_stress_c.c
	$(CC) $(CFLAGS) build/test_gc_stress_c.c -o build/test_gc_stress_c
	ULISP_GC_STRESS=1 ./build/test_gc_stress_c
	@echo "--- 4. Testing Portable C Backend with (!gc stress) Directive ---"
	echo '(!target c)' > build/test_gc_stress_c_directive_input.scm
	echo '(!gc stress)' >> build/test_gc_stress_c_directive_input.scm
	cat lib/string.scm lib/vector.scm tests/test_gc_stress.scm >> build/test_gc_stress_c_directive_input.scm
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
		./$(ULISP_BOOT) build/ulisp_core.scm > $@; \
	else \
		echo "=== Stage 1: Compiling with ILisp $(ILISP) ==="; \
		$(RUN_SCHEME) compiler.scm < build/ulisp_core.scm > $@; \
	fi


build/scheme-stage1: build/stage1.s
	$(CC) -nostdlib -static $< -o $@

stage1: build/scheme-stage1
bootstrap_stage1: stage1

build/stage2.s: build/scheme-stage1 build/ulisp_core.scm
	@mkdir -p build
	./build/scheme-stage1 build/ulisp_core.scm > $@

build/scheme-stage2: build/stage2.s
	$(CC) -nostdlib -static $< -o $@

stage2: build/scheme-stage2
bootstrap_stage2: stage2

build/stage3.s: build/scheme-stage2 build/ulisp_core.scm
	@mkdir -p build
	./build/scheme-stage2 build/ulisp_core.scm > $@

build/scheme-stage3: build/stage3.s
	$(CC) -nostdlib -static $< -o $@

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

build/test_bridge_runner.scm: jit/core/delimcc.scm jit/tracer/tracer.scm jit/optimizer/pe.scm jit/optimizer/virtuals.scm tests/jit/test_bridge.scm
	@mkdir -p build
	cat $^ > $@

test_bridge: build/test_bridge_runner.scm
	@$(RUN_SCHEME) build/test_bridge_runner.scm

build/test_examples_runner.scm: jit/core/delimcc.scm jit/tracer/tracer.scm jit/optimizer/pe.scm jit/optimizer/virtuals.scm tests/jit/test_examples.scm
	@mkdir -p build
	cat $^ > $@

test_examples: build/test_examples_runner.scm
	@$(RUN_SCHEME) build/test_examples_runner.scm

build/test_guard_elimination_runner.scm: jit/core/delimcc.scm jit/tracer/tracer.scm jit/optimizer/pe.scm jit/optimizer/virtuals.scm tests/jit/test_guard_elimination.scm
	@mkdir -p build
	cat $^ > $@

test_guard_elimination: build/test_guard_elimination_runner.scm
	@$(RUN_SCHEME) build/test_guard_elimination_runner.scm

test_jit: test_delimcc test_tracer test_auto_instrument test_optimizer test_guard_elimination test_bridge test_examples
	@echo "=== [All JIT Component Tests Passed: 112/112] ==="

build/demo_runner.scm: jit/core/delimcc.scm jit/tracer/tracer.scm jit/optimizer/pe.scm jit/optimizer/virtuals.scm jit/examples/tiny_vm.scm jit/examples/scheme_eval.scm jit/examples/demo.scm
	@mkdir -p build
	cat $^ > $@

demo: build/demo_runner.scm
	@$(RUN_SCHEME) build/demo_runner.scm


# --- Unified JIT Binary: bin/ulisp-jit ---
build/ulisp_jit_combined.scm: lib/string.scm lib/port.scm lib/printer.scm lib/reader.scm lib/exception.scm lib/values.scm lib/gc.scm build/compiler_passes.scm driver/jit.scm
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



bin/ulisp-jit: build/ulisp_jit.s
	@mkdir -p bin
	$(CC) -nostdlib -static -o $@ $<
	@echo "Successfully compiled native standalone ulisp-jit binary: $@"

jit: bin/ulisp-jit

run_jit: bin/ulisp-jit
	@echo "=== [1/2] Verifying ulisp-jit JIT Loop Execution ==="
	@echo "(let loop ((i 0) (sum 0)) (if (< i 10) (loop (+ i 1) (+ sum i)) sum))" > build/test_jit_eval.scm
	@./bin/ulisp-jit build/test_jit_eval.scm
	@echo "=== [2/2] Verifying ulisp-jit AOT Compilation ==="
	@printf "(!compile)\n(define (fact n) (if (<= n 1) 1 (* n (fact (- n 1)))))\n(fact 5)\n" > build/test_jit_aot.scm
	@./bin/ulisp-jit build/test_jit_aot.scm > build/test_jit_aot.s
	@$(CC) -nostdlib -static -o build/test_jit_aot build/test_jit_aot.s
	@test "$$(./build/test_jit_aot)" = "120"
	@echo "SUCCESS: ulisp-jit AOT compilation verified (fact 5) = 120!"

# --- Performance Benchmark ---
bench: bin/ulisp-jit
	$(PYTHON) benchmarks/benchmark_stage2_vs_ulisp_jit.py

bench_trio: bin/ulisp-jit
	$(PYTHON) $(ROOT_DIR)/tools/benchmark_ilisp_ulisp.py --iterations 10

bench_perf: bin/ulisp-jit
	$(PYTHON) $(ROOT_DIR)/tools/benchmark_ilisp_ulisp.py --iterations 10 --perf

bench_ci: bin/ulisp-jit
	$(PYTHON) $(ROOT_DIR)/tools/benchmark_ilisp_ulisp.py --iterations 5 --compare $(ROOT_DIR)/outputs/benchmarks/latest.json --threshold 2.5

diff_test: bin/ulisp-jit
	$(PYTHON) $(ROOT_DIR)/tools/differential_test_ulisp.py

# --- Comprehensive Test Suite ---
test_aot: core
	./test.sh

test: test_passes test_pass_manager test_dataflow test_runtime test_annotator test_rtyper test_lir test_aarch64 test_exceptions test_values test_call_cc test_eqv test_syntax_rules test_ports test_record test_promise test_stdlib test_gc_growth test_gc_profile test_gc_hybrid test_gc_stress test_jit test_c test_aot

clean:
	rm -f tmp tmp_bin *.s *.o *.log
	@if [ -d build ]; then \
		find build -mindepth 1 ! -name 'scheme-stage*' ! -name 'stage*.s' -delete; \
	fi

distclean:
	rm -f tmp tmp_bin *.s *.o *.log
	rm -rf build bin

