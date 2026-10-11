.PHONY: all test test_aot test_jit test_c test_aarch64 test_freestanding bootstrap clean run_42 run_c_42 core compiler test_passes stage1 jit bin run_jit bench demo \
        test_delimcc test_tracer test_auto_instrument test_optimizer test_bridge test_examples

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
             passes/04_anf.scm \
             passes/05_closure_convert.scm \
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

test_aarch64: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/test_backend_aarch64.scm > build/test_aarch64_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_aarch64_runner.scm

test_freestanding: compiler
	@echo "=== Running Zero-libc Bare-Metal Freestanding Tests ==="
	@PYTHONPATH=$(ROOT_DIR) $(PYTHON) -m pytest $(ROOT_DIR)/tests/test_bare_metal_ulisp.py -v

test_c: compiler
	./test_c.sh

core: build/ulisp_core.scm

build/ulisp_core.scm: lib/posix.scm lib/string.scm lib/printer.scm lib/reader.scm lib/gc.scm compiler.scm
	@mkdir -p build
	cat $^ > $@

build/stage1.s: compiler.scm build/ulisp_core.scm
	@mkdir -p build
	PYTHONPATH=$(ROOT_DIR) $(ILISP) compiler.scm < build/ulisp_core.scm > $@

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

test_jit: test_delimcc test_tracer test_auto_instrument test_optimizer test_bridge test_examples
	@echo "=== [All JIT Component Tests Passed: 94/94] ==="

build/demo_runner.scm: jit/core/delimcc.scm jit/tracer/tracer.scm jit/optimizer/pe.scm jit/optimizer/virtuals.scm jit/bridge/to_lir.scm jit/runtime/jit_buffer.scm jit/examples/tiny_vm.scm jit/examples/scheme_eval.scm jit/examples/demo.scm
	@mkdir -p build
	cat $^ > $@

demo: build/demo_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/demo_runner.scm

# --- Unified JIT Binary: bin/ulisp-jit ---
build/ulisp_jit_combined.scm: lib/string.scm lib/printer.scm lib/reader.scm lib/gc.scm build/compiler_passes.scm driver/jit.scm
	@mkdir -p build
	cat $^ > $@

build/ulisp_jit.s: build/ulisp_jit_combined.scm compiler.scm
	@mkdir -p build
	PYTHONPATH=$(ROOT_DIR) $(ILISP) compiler.scm < $< > $@

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

bench_ci: bin/ulisp-jit
	$(PYTHON) $(ROOT_DIR)/tools/benchmark_ilisp_ulisp.py --iterations 5 --compare $(ROOT_DIR)/outputs/benchmarks/latest.json --threshold 2.5

# --- Comprehensive Test Suite ---
test_aot: core
	./test.sh

test: test_passes test_aarch64 test_jit test_c test_aot

clean:
	rm -f tmp tmp_bin *.s *.o
	rm -rf build bin
