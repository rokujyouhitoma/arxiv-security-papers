.PHONY: test bootstrap clean run_42 core compiler

CC = gcc
CFLAGS = -Wall -Wextra -O0 -g
ILISP = python3 -m ilisp
ROOT_DIR = $(shell dirname $(CURDIR))

PASSES = passes/00_helpers.scm \
         passes/01_desugar.scm \
         passes/02_analysis.scm \
         passes/03_cp0.scm \
         passes/04_anf.scm \
         passes/05_closure_convert.scm \
         passes/06_emitter.scm \
         passes/07_codegen.scm \
         passes/08_driver.scm

compiler: compiler.scm

compiler.scm: $(PASSES)
	cat $(PASSES) > $@

core: build/ulisp_core.scm

build/ulisp_core.scm: lib/string.scm lib/printer.scm lib/reader.scm compiler.scm
	@mkdir -p build
	cat $^ > $@

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
