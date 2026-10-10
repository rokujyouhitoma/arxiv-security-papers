.PHONY: test test_c test_aarch64 bootstrap clean run_42 run_c_42 core compiler test_passes stage1 stage_mlisp run_mlisp_stage

CC = gcc
CFLAGS = -Wall -Wextra -O0 -g
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

compiler: compiler.scm

compiler.scm: $(PASSES)
	cat $(PASSES) > $@

build/compiler_passes.scm: $(PASSES_LIB)
	@mkdir -p build
	cat $^ > $@

test_passes: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/test_passes.scm > build/test_passes_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_passes_runner.scm

test_aarch64: build/compiler_passes.scm
	@mkdir -p build
	cat build/compiler_passes.scm tests/test_backend_aarch64.scm > build/test_aarch64_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_aarch64_runner.scm

core: build/ulisp_core.scm

build/ulisp_core.scm: lib/string.scm lib/printer.scm lib/reader.scm lib/gc.scm compiler.scm
	@mkdir -p build
	cat $^ > $@

build/runtime.o: runtime.c
	@mkdir -p build
	$(CC) $(CFLAGS) -c $< -o $@

build/stage1.s: compiler.scm build/ulisp_core.scm
	@mkdir -p build
	PYTHONPATH=$(ROOT_DIR) $(ILISP) compiler.scm < build/ulisp_core.scm > $@

build/scheme-stage1: build/stage1.s build/runtime.o
	$(CC) -no-pie $^ -o $@

stage1: build/scheme-stage1

MLISP_RUNNER = $(ROOT_DIR)/mlisp/driver/compile_ulisp_runner.scm

$(MLISP_RUNNER):
	@mkdir -p $(ROOT_DIR)/mlisp/driver
	cat $(ROOT_DIR)/mlisp/core/delimcc.scm \
	    $(ROOT_DIR)/mlisp/tracer/tracer.scm \
	    $(ROOT_DIR)/mlisp/optimizer/pe.scm \
	    $(ROOT_DIR)/mlisp/optimizer/virtuals.scm \
	    $(ROOT_DIR)/mlisp/bridge/to_lir.scm \
	    $(ROOT_DIR)/mlisp/runtime/jit_buffer.scm \
	    compiler.scm > $@

build/stage_mlisp.s: $(MLISP_RUNNER) build/ulisp_core.scm
	@mkdir -p build
	PYTHONPATH=$(ROOT_DIR) $(ILISP) $< < build/ulisp_core.scm > $@

build/scheme-from-mlisp: build/stage_mlisp.s build/runtime.o
	$(CC) -no-pie $^ -o $@

stage_mlisp: build/scheme-from-mlisp

run_mlisp_stage: stage_mlisp
	@echo "Verifying scheme-from-mlisp binary..."
	@echo "(+ 40 2)" | ./build/scheme-from-mlisp > build/test_mlisp.s
	@$(CC) $(CFLAGS) -no-pie -o build/test_mlisp runtime.c build/test_mlisp.s
	@test "$$(./build/test_mlisp)" = "42"
	@echo "SUCCESS: scheme-from-mlisp verified (+ 40 2) = 42"
	@rm -f build/test_mlisp build/test_mlisp.s

test: core
	./test.sh

test_c: compiler
	./test_c.sh

bootstrap: core
	./bootstrap.sh

run_42: core
	@echo "42" | PYTHONPATH=$(ROOT_DIR) $(ILISP) compiler.scm > tmp.s
	@$(CC) $(CFLAGS) -o tmp runtime.c tmp.s
	@./tmp
	@rm -f tmp tmp.s

run_c_42: core
	@mkdir -p build
	@printf "(!target c)\n42\n" | PYTHONPATH=$(ROOT_DIR) $(ILISP) compiler.scm > build/tmp_c_42.c
	@$(CC) $(CFLAGS) -o build/tmp_c_42 runtime.c build/tmp_c_42.c
	@./build/tmp_c_42
	@rm -f build/tmp_c_42.c build/tmp_c_42

clean:
	rm -f tmp tmp_bin *.s *.o
	rm -rf build
