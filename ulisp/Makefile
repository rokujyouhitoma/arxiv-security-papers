.PHONY: test test_c bootstrap clean run_42 run_c_42 core compiler test_passes stage1

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

core: build/ulisp_core.scm

build/ulisp_core.scm: lib/string.scm lib/printer.scm lib/reader.scm compiler.scm
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
