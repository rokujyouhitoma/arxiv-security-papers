.PHONY: all test test_aot test_jit test_c test_aarch64 test_freestanding bootstrap clean run_42 run_c_42 core compiler test_passes test_annotator test_lvn test_rtyper test_contify test_alias_escape test_lir stage1 jit bin run_jit bench demo \
        test_delimcc test_tracer test_auto_instrument test_optimizer test_guard_elimination test_bridge test_examples test_exceptions test_values test_call_cc test_eqv test_syntax_rules test_ports

CC = gcc
CFLAGS = -Wall -Wextra -O0 -g
CFLAGS_JIT = -no-pie -Wall -O2

ROOT_DIR = $(shell dirname $(CURDIR))
PYTHON = $(shell if [ -x $(ROOT_DIR)/.venv/bin/python ]; then echo $(ROOT_DIR)/.venv/bin/python; else echo python3; fi)
ILISP = $(PYTHON) -m ilisp

PASSES_LIB = passes/00_helpers.scm \
             passes/00b_macro_expander.scm \
             passes/01_desugar.scm \
             passes/02_analysis.scm \
             passes/03_cp0.scm \
             passes/03b_lvn.scm \
             passes/04_anf.scm \
             passes/04b_annotator.scm \
             passes/05b_rtyper.scm \
             passes/04c_contify.scm \
             passes/05_closure_convert.scm \
             passes/06b_alias_escape.scm \
             passes/06_lir.scm \
             passes/07_backend_x86_64.scm \
             passes/07_backend_aarch64.scm \
             passes/07_backend_c.scm

PASSES = $(PASSES_LIB) passes/08_driver.scm

all: test

compiler: compiler.scm

compiler.scm: $(PASSES)
	cat $(PASSES) > $@

build/compiler_passes.scm: $(PASSES_LIB)
	@mkdir -p build
	cat $^ > $@

# --- AOT Nanopass Tests ---
test_passes: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/test_passes.scm > build/test_passes_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_passes_runner.scm

test_lvn: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_lvn.scm > build/test_lvn_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_lvn_runner.scm

test_annotator: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_annotator.scm > build/test_annotator_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_annotator_runner.scm

test_rtyper: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_rtyper.scm > build/test_rtyper_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_rtyper_runner.scm

test_stackmap: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_stackmap.scm > build/test_stackmap_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_stackmap_runner.scm

test_contify: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_contify.scm > build/test_contify_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_contify_runner.scm

test_alias_escape: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_alias_escape.scm > build/test_alias_escape_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_alias_escape_runner.scm

test_toplevel: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_toplevel_direct_call.scm > build/test_toplevel_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_toplevel_runner.scm

test_loop_reg: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_loop_register_allocation.scm > build/test_loop_reg_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_loop_reg_runner.scm
	$(CC) $(CFLAGS_JIT) -o build/test_loop_reg runtime.c build/test_loop_reg.s
	@echo "=== Executing compiled loop_sum binary (1,000,000 iters) ==="
	@res=$$(./build/test_loop_reg); echo "Output: $$res"; test "$$res" = "499999500000"
	@echo "SUCCESS: loop_sum output 499999500000 matches expected exactly!"

test_branch_fusion: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_branch_fusion.scm > build/test_branch_fusion_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_branch_fusion_runner.scm
	$(CC) $(CFLAGS_JIT) -o build/test_predicates_fusion runtime.c build/test_predicates_fusion.s
	@echo "=== Executing compiled predicates fusion binary ==="
	@res=$$(./build/test_predicates_fusion); echo "Output: $$res"; test "$$res" = "255"
	@echo "SUCCESS: branch fusion predicates output 255 (1+2+4+8+16+32+64+128) matches expected!"

test_inplace_shuffle: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_inplace_shuffle.scm > build/test_inplace_shuffle_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_inplace_shuffle_runner.scm
	$(CC) $(CFLAGS_JIT) -o build/test_inplace_shuffle runtime.c build/test_inplace_shuffle.s
	@echo "=== Executing compiled inplace shuffle loop_sum binary ==="
	@res=$$(./build/test_inplace_shuffle); echo "Output: $$res"; test "$$res" = "499999500000"
	@echo "SUCCESS: inplace shuffle loop_sum output 499999500000 matches expected exactly!"
	$(CC) $(CFLAGS_JIT) -o build/test_swap_loop runtime.c build/test_swap_loop.s
	@echo "=== Executing compiled swap_loop binary ==="
	@res=$$(./build/test_swap_loop); echo "Output: $$res"; test "$$res" = "10"
	@echo "SUCCESS: swap_loop output 10 (swap 10 20 -> 20 10 -> returns b=10) matches expected exactly!"
	$(CC) $(CFLAGS_JIT) -o build/test_countdown runtime.c build/test_countdown.s
	@echo "=== Executing compiled countdown binary ==="
	@res=$$(./build/test_countdown); echo "Output: $$res"; test "$$res" = "5050"
	@echo "SUCCESS: countdown sum(1..100) output 5050 matches expected exactly!"

test_lir: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/passes/test_lir.scm > build/test_lir_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_lir_runner.scm

test_aarch64: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/test_backend_aarch64.scm > build/test_aarch64_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_aarch64_runner.scm

test_exceptions: build/scheme-stage2
	@mkdir -p build
	cat lib/posix.scm lib/string.scm lib/port.scm lib/printer.scm lib/reader.scm lib/exception.scm lib/gc.scm tests/test_exceptions.scm > build/test_exn_input.scm
	./build/scheme-stage2 build/test_exn_input.scm > build/test_exn.s
	$(CC) -nostdlib -static build/test_exn.s -o build/test_exn
	./build/test_exn

test_values: build/scheme-stage2
	@mkdir -p build
	cat lib/posix.scm lib/string.scm lib/port.scm lib/printer.scm lib/reader.scm lib/exception.scm lib/values.scm lib/gc.scm tests/test_values.scm > build/test_values_input.scm
	./build/scheme-stage2 build/test_values_input.scm > build/test_values.s
	$(CC) -nostdlib -static build/test_values.s -o build/test_values
	./build/test_values

test_call_cc: build/scheme-stage2
	@mkdir -p build
	cat lib/posix.scm lib/string.scm lib/port.scm lib/printer.scm lib/reader.scm lib/equality.scm lib/predicates.scm lib/exception.scm lib/values.scm lib/continuation.scm lib/gc.scm tests/test_call_cc.scm > build/test_call_cc_input.scm
	./build/scheme-stage2 build/test_call_cc_input.scm > build/test_call_cc.s
	$(CC) -nostdlib -static build/test_call_cc.s -o build/test_call_cc
	./build/test_call_cc

test_eqv: build/scheme-stage2
	@mkdir -p build
	cat lib/posix.scm lib/string.scm lib/port.scm lib/printer.scm lib/reader.scm lib/equality.scm lib/predicates.scm lib/exception.scm lib/values.scm lib/continuation.scm lib/gc.scm tests/test_eqv.scm > build/test_eqv_input.scm
	./build/scheme-stage2 build/test_eqv_input.scm > build/test_eqv.s
	$(CC) -nostdlib -static build/test_eqv.s -o build/test_eqv
	./build/test_eqv

test_syntax_rules: build/scheme-stage2
	@mkdir -p build
	cat lib/posix.scm lib/string.scm lib/port.scm lib/printer.scm lib/reader.scm lib/equality.scm lib/predicates.scm lib/exception.scm lib/values.scm lib/continuation.scm lib/gc.scm tests/test_syntax_rules.scm > build/test_syntax_rules_input.scm
	./build/scheme-stage2 build/test_syntax_rules_input.scm > build/test_syntax_rules.s
	$(CC) -nostdlib -static build/test_syntax_rules.s -o build/test_syntax_rules
	./build/test_syntax_rules

test_ports: build/scheme-stage2
	@mkdir -p build
	cat lib/posix.scm lib/string.scm lib/port.scm lib/printer.scm lib/reader.scm lib/equality.scm lib/predicates.scm lib/exception.scm lib/values.scm lib/continuation.scm lib/gc.scm tests/test_ports.scm > build/test_ports_input.scm
	./build/scheme-stage2 build/test_ports_input.scm > build/test_ports.s
	$(CC) -nostdlib -static build/test_ports.s -o build/test_ports
	./build/test_ports

test_freestanding: compiler
	@echo "=== Running Zero-libc Bare-Metal Freestanding Tests ==="
	@PYTHONPATH=$(ROOT_DIR) $(PYTHON) -m pytest $(ROOT_DIR)/tests/test_bare_metal_ulisp.py -v

test_c: compiler
	./test_c.sh

core: build/ulisp_core.scm

build/ulisp_core.scm: lib/posix.scm lib/string.scm lib/port.scm lib/printer.scm lib/reader.scm lib/equality.scm lib/predicates.scm lib/bytevector.scm lib/vector.scm lib/exception.scm lib/values.scm lib/continuation.scm lib/parameter.scm lib/gc.scm compiler.scm
	@mkdir -p build
	cat $^ > $@

ULISP_BOOT = bin/ulisp-boot

build/stage1.s: compiler.scm build/ulisp_core.scm
	@mkdir -p build
	@if [ -x "$(ULISP_BOOT)" ] && [ "$(FULL_BOOTSTRAP)" != "1" ]; then \
		echo "=== Stage 1: Fast compiling with native seed $(ULISP_BOOT) ==="; \
		./$(ULISP_BOOT) build/ulisp_core.scm > $@; \
	else \
		echo "=== Stage 1: Compiling with ILisp $(ILISP) ==="; \
		PYTHONPATH=$(ROOT_DIR) $(ILISP) compiler.scm < build/ulisp_core.scm > $@; \
	fi

build/scheme-stage1: build/stage1.s
	$(CC) -nostdlib -static $< -o $@

stage1: build/scheme-stage1

bootstrap: core
	./bootstrap.sh

# --- JIT Component Tests (94 Tests) ---
build/test_delimcc_runner.scm: jit/core/delimcc.scm tests/jit/test_delimcc.scm
	@mkdir -p build
	cat $^ > $@

test_delimcc: build/test_delimcc_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_delimcc_runner.scm

build/test_tracer_runner.scm: jit/core/delimcc.scm jit/tracer/tracer.scm tests/jit/test_tracer.scm
	@mkdir -p build
	cat $^ > $@

test_tracer: build/test_tracer_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_tracer_runner.scm

build/test_auto_instrument_runner.scm: jit/core/delimcc.scm jit/tracer/tracer.scm jit/tracer/auto_instrument.scm tests/jit/test_auto_instrument.scm
	@mkdir -p build
	cat $^ > $@

test_auto_instrument: build/test_auto_instrument_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_auto_instrument_runner.scm

build/test_optimizer_runner.scm: jit/core/delimcc.scm jit/tracer/tracer.scm jit/optimizer/pe.scm jit/optimizer/virtuals.scm tests/jit/test_optimizer.scm
	@mkdir -p build
	cat $^ > $@

test_optimizer: build/test_optimizer_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_optimizer_runner.scm

build/test_bridge_runner.scm: jit/core/delimcc.scm jit/tracer/tracer.scm jit/optimizer/pe.scm jit/optimizer/virtuals.scm jit/bridge/to_lir.scm jit/runtime/jit_buffer.scm tests/jit/test_bridge.scm
	@mkdir -p build
	cat $^ > $@

test_bridge: build/test_bridge_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_bridge_runner.scm

build/test_examples_runner.scm: jit/core/delimcc.scm jit/tracer/tracer.scm jit/optimizer/pe.scm jit/optimizer/virtuals.scm jit/bridge/to_lir.scm jit/runtime/jit_buffer.scm jit/examples/tiny_vm.scm jit/examples/scheme_eval.scm tests/jit/test_examples.scm
	@mkdir -p build
	cat $^ > $@

test_examples: build/test_examples_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_examples_runner.scm

build/test_guard_elimination_runner.scm: jit/core/delimcc.scm jit/tracer/tracer.scm jit/optimizer/pe.scm jit/optimizer/virtuals.scm jit/bridge/to_lir.scm jit/runtime/jit_buffer.scm tests/jit/test_guard_elimination.scm
	@mkdir -p build
	cat $^ > $@

test_guard_elimination: build/test_guard_elimination_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_guard_elimination_runner.scm

test_jit: test_delimcc test_tracer test_auto_instrument test_optimizer test_guard_elimination test_bridge test_examples
	@echo "=== [All JIT Component Tests Passed: 112/112] ==="

build/demo_runner.scm: jit/core/delimcc.scm jit/tracer/tracer.scm jit/optimizer/pe.scm jit/optimizer/virtuals.scm jit/bridge/to_lir.scm jit/runtime/jit_buffer.scm jit/examples/tiny_vm.scm jit/examples/scheme_eval.scm jit/examples/demo.scm
	@mkdir -p build
	cat $^ > $@

demo: build/demo_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/demo_runner.scm

# --- Unified JIT Binary: bin/ulisp-jit ---
build/ulisp_jit_combined.scm: lib/string.scm lib/port.scm lib/printer.scm lib/reader.scm lib/exception.scm lib/values.scm lib/gc.scm build/compiler_passes.scm driver/jit.scm
	@mkdir -p build
	cat $^ > $@

build/ulisp_jit.s: build/ulisp_jit_combined.scm compiler.scm
	@mkdir -p build
	@if [ -x build/scheme-stage2 ]; then \
		./build/scheme-stage2 < build/ulisp_jit_combined.scm > $@; \
	else \
		PYTHONPATH=$(ROOT_DIR) $(ILISP) compiler.scm < $< > $@; \
	fi

bin/ulisp-jit: build/ulisp_jit.s runtime.c
	@mkdir -p bin
	$(CC) $(CFLAGS_JIT) -o $@ runtime.c $<
	@echo "Successfully compiled native standalone ulisp-jit binary: $@"

jit: bin/ulisp-jit

run_jit: bin/ulisp-jit
	@echo "=== [1/2] Verifying ulisp-jit JIT Loop Execution ==="
	@echo "(let loop ((i 0) (sum 0)) (if (< i 10) (loop (+ i 1) (+ sum i)) sum))" > build/test_jit_eval.scm
	@./bin/ulisp-jit build/test_jit_eval.scm
	@echo "=== [2/2] Verifying ulisp-jit AOT Compilation ==="
	@printf "(!compile)\n(define (fact n) (if (<= n 1) 1 (* n (fact (- n 1)))))\n(fact 5)\n" > build/test_jit_aot.scm
	@./bin/ulisp-jit build/test_jit_aot.scm > build/test_jit_aot.s
	@$(CC) $(CFLAGS_JIT) -o build/test_jit_aot runtime.c build/test_jit_aot.s
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

test: test_passes test_annotator test_rtyper test_lir test_aarch64 test_exceptions test_values test_call_cc test_eqv test_syntax_rules test_ports test_jit test_c test_aot

clean:
	rm -f tmp tmp_bin *.s *.o
	rm -rf build

distclean: clean
	rm -rf bin
