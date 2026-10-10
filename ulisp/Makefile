.PHONY: test bootstrap clean run_42 core compiler test_passes stage1

CC = gcc
CFLAGS = -Wall -Wextra -O0 -g
ILISP = python3 -m ilisp
ROOT_DIR = $(shell dirname $(CURDIR))

PASSES_LIB = passes/00_helpers.scm \
             passes/01_desugar.scm \
             passes/02_analysis.scm \
             passes/03_cp0.scm \
             passes/04_anf.scm \
             passes/05_closure_convert.scm \
             passes/06_lir.scm \
             passes/07_backend_x86_64.scm

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

bootstrap: core
	./bootstrap.sh

run_42: core
	@echo "42" | PYTHONPATH=$(ROOT_DIR) $(ILISP) compiler.scm > tmp.s
	@$(CC) $(CFLAGS) -o tmp runtime.c tmp.s
	@./tmp
	@rm -f tmp tmp.s

clean:
	rm -f tmp tmp_bin *.s *.o
	rm -rf build
