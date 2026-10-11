.PHONY: all test test_delimcc test_tracer test_auto_instrument test_optimizer test_bridge test_examples clean demo bin run_bin scheme-jit run_scheme_jit ulisp-jit run_ulisp_jit compile_ulisp

ROOT_DIR = $(shell dirname $(CURDIR))
PYTHON = $(shell if [ -x $(ROOT_DIR)/.venv/bin/python ]; then echo $(ROOT_DIR)/.venv/bin/python; else echo python3; fi)
ILISP = $(PYTHON) -m ilisp

all: test

build/test_delimcc_runner.scm: core/delimcc.scm tests/test_delimcc.scm
	@mkdir -p build
	cat core/delimcc.scm tests/test_delimcc.scm > $@

test_delimcc: build/test_delimcc_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_delimcc_runner.scm

build/test_tracer_runner.scm: core/delimcc.scm tracer/tracer.scm tests/test_tracer.scm
	@mkdir -p build
	cat $^ > $@

test_tracer: build/test_tracer_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_tracer_runner.scm

build/test_auto_instrument_runner.scm: core/delimcc.scm tracer/tracer.scm tracer/auto_instrument.scm tests/test_auto_instrument.scm
	@mkdir -p build
	cat $^ > $@

test_auto_instrument: build/test_auto_instrument_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_auto_instrument_runner.scm

build/test_optimizer_runner.scm: core/delimcc.scm tracer/tracer.scm optimizer/pe.scm optimizer/virtuals.scm tests/test_optimizer.scm
	@mkdir -p build
	cat $^ > $@

test_optimizer: build/test_optimizer_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_optimizer_runner.scm

build/test_bridge_runner.scm: core/delimcc.scm tracer/tracer.scm optimizer/pe.scm optimizer/virtuals.scm bridge/to_lir.scm runtime/jit_buffer.scm tests/test_bridge.scm
	@mkdir -p build
	cat $^ > $@

test_bridge: build/test_bridge_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_bridge_runner.scm

build/test_examples_runner.scm: core/delimcc.scm tracer/tracer.scm optimizer/pe.scm optimizer/virtuals.scm bridge/to_lir.scm runtime/jit_buffer.scm examples/tiny_vm.scm examples/scheme_eval.scm tests/test_examples.scm
	@mkdir -p build
	cat $^ > $@

test_examples: build/test_examples_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/test_examples_runner.scm

build/demo_runner.scm: core/delimcc.scm tracer/tracer.scm optimizer/pe.scm optimizer/virtuals.scm bridge/to_lir.scm runtime/jit_buffer.scm examples/tiny_vm.scm examples/scheme_eval.scm examples/demo.scm
	@mkdir -p build
	cat $^ > $@

demo: build/demo_runner.scm
	@PYTHONPATH=$(ROOT_DIR) $(ILISP) build/demo_runner.scm

CC ?= gcc
CFLAGS ?= -no-pie -Wall -O2

ULISP_STAGE2 = $(ROOT_DIR)/ulisp/build/scheme-stage2
ULISP_STAGE1 = $(ROOT_DIR)/ulisp/build/scheme-stage1

bin: bin/tiny_vm

bin/tiny_vm: examples/tiny_vm_aot.scm
	@mkdir -p bin build
	@if [ -x $(ULISP_STAGE2) ]; then \
		cat $(ROOT_DIR)/ulisp/lib/string.scm $(ROOT_DIR)/ulisp/lib/printer.scm $< | $(ULISP_STAGE2) > build/tiny_vm.s; \
	elif [ -x $(ULISP_STAGE1) ]; then \
		cat $(ROOT_DIR)/ulisp/lib/string.scm $(ROOT_DIR)/ulisp/lib/printer.scm $< | $(ULISP_STAGE1) > build/tiny_vm.s; \
	else \
		$(MAKE) -C $(ROOT_DIR)/ulisp stage1; \
		cat $(ROOT_DIR)/ulisp/lib/string.scm $(ROOT_DIR)/ulisp/lib/printer.scm $< | $(ULISP_STAGE1) > build/tiny_vm.s; \
	fi
	$(CC) $(CFLAGS) -o $@ $(ROOT_DIR)/ulisp/runtime.c build/tiny_vm.s
	@echo "Successfully compiled native standalone binary: $@"

scheme-jit: bin/scheme-jit

bin/scheme-jit: driver/scheme_jit.scm
	@mkdir -p bin build
	@if [ -x $(ULISP_STAGE2) ]; then \
		cat $(ROOT_DIR)/ulisp/lib/string.scm $(ROOT_DIR)/ulisp/lib/printer.scm $< | $(ULISP_STAGE2) > build/scheme_jit.s; \
	elif [ -x $(ULISP_STAGE1) ]; then \
		cat $(ROOT_DIR)/ulisp/lib/string.scm $(ROOT_DIR)/ulisp/lib/printer.scm $< | $(ULISP_STAGE1) > build/scheme_jit.s; \
	else \
		$(MAKE) -C $(ROOT_DIR)/ulisp stage1; \
		cat $(ROOT_DIR)/ulisp/lib/string.scm $(ROOT_DIR)/ulisp/lib/printer.scm $< | $(ULISP_STAGE1) > build/scheme_jit.s; \
	fi
	$(CC) $(CFLAGS) -o $@ $(ROOT_DIR)/ulisp/runtime.c build/scheme_jit.s
	@echo "Successfully compiled native standalone JIT binary: $@"

run_scheme_jit: bin/scheme-jit
	./bin/scheme-jit

run_bin: bin/tiny_vm
	./bin/tiny_vm

ULISP_DIR = $(ROOT_DIR)/ulisp

build/ulisp_jit_combined.scm: $(ULISP_DIR)/lib/string.scm $(ULISP_DIR)/lib/printer.scm $(ULISP_DIR)/lib/reader.scm $(ULISP_DIR)/lib/gc.scm $(ULISP_DIR)/build/compiler_passes.scm driver/ulisp_jit.scm
	@mkdir -p build
	cat $^ > $@

build/ulisp_jit.s: build/ulisp_jit_combined.scm
	@mkdir -p build
	PYTHONPATH=$(ROOT_DIR) $(ILISP) $(ULISP_DIR)/compiler.scm < $< > $@

ulisp-jit: bin/ulisp-jit

bin/ulisp-jit: build/ulisp_jit.s
	@mkdir -p bin
	$(CC) $(CFLAGS) -o $@ $(ULISP_DIR)/runtime.c $<
	@echo "Successfully compiled native standalone ulisp-jit binary: $@"

run_ulisp_jit: bin/ulisp-jit
	@echo "=== [1/2] Verifying ulisp-jit JIT Loop Execution ==="
	@echo "(let loop ((i 0) (sum 0)) (if (< i 10) (loop (+ i 1) (+ sum i)) sum))" > build/test_jit_eval.scm
	@./bin/ulisp-jit build/test_jit_eval.scm
	@echo "=== [2/2] Verifying ulisp-jit AOT Compilation ==="
	@printf "(!compile)\n(define (fact n) (if (<= n 1) 1 (* n (fact (- n 1)))))\n(fact 5)\n" > build/test_jit_aot.scm
	@./bin/ulisp-jit build/test_jit_aot.scm > build/test_jit_aot.s
	@$(CC) $(CFLAGS) -o build/test_jit_aot $(ULISP_DIR)/runtime.c build/test_jit_aot.s
	@test "$$(./build/test_jit_aot)" = "120"
	@echo "SUCCESS: ulisp-jit AOT compilation verified (fact 5) = 120!"

compile_ulisp: bin/ulisp-jit
	@echo "ulisp-jit is ready for compiling ulisp programs."


test: test_delimcc test_tracer test_auto_instrument test_optimizer test_bridge test_examples

clean:
	rm -rf build bin tmp*
