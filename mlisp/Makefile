.PHONY: all test test_delimcc test_tracer test_optimizer test_bridge test_examples clean

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

test: test_delimcc test_tracer test_optimizer test_bridge test_examples

clean:
	rm -rf build tmp*
