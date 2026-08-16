PACKAGE=arxiv_okf_fetcher
PYTHON ?= $(shell if [ -x "$$HOME/.local/python-3.14.7/bin/python3" ]; then echo "$$HOME/.local/python-3.14.7/bin/python3"; elif [ -x "/root/.local/python-3.14.7/bin/python3" ]; then echo "/root/.local/python-3.14.7/bin/python3"; elif command -v python3.14 >/dev/null 2>&1; then command -v python3.14; else which python3; fi)
VENV=.venv
VENV_BIN=${VENV}/bin
VENV_PYTHON=${VENV_BIN}/python

SRC=src/arxiv_okf_fetcher.py
PYTHON_SRCS = src/arxiv_okf_fetcher.py \
              src/vector_engine.py \
              src/synonym_expander.py \
              src/mcp_server.py \
              src/web_server.py \
              src/search/__init__.py \
              src/search/utils.py \
              src/search/vector_engine.py \
              src/search/ingestion/__init__.py \
              src/search/ingestion/analyzer.py \
              src/search/ingestion/field_schema.py \
              src/search/ingestion/fm_index.py \
              src/search/ingestion/faceted_index.py \
              src/search/ingestion/raptor_tree.py \
              src/search/query/__init__.py \
              src/search/query/query_parser.py \
              src/search/query/synonym_expander.py \
              src/search/query/query_cache.py \
              src/search/ranking/__init__.py \
              src/search/ranking/knowledge_graph.py \
              src/search/ranking/proximity_graph.py \
              src/search/ranking/citation_network.py \
              src/search/presentation/__init__.py \
              src/search/presentation/highlighter.py
TESTS=tests

COMPILER = tools/closure-compiler/closure-compiler-v20240317.jar
JS_SRCS = site/js/lexer.js \
          site/js/parser.js \
          site/js/evaluator.js \
          site/js/renderer.js \
          site/js/markdown_compiler.js \
          site/app.js
JS_OUT = site/app-min.js

all: clean setup format static_analysis test build run

.PHONY: help
help: ## help command
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: clean
clean: ## clean virtualenv and build artifacts
	rm -rf dist/ __pycache__ src/__pycache__ tests/__pycache__ .pytest_cache .mypy_cache outputs/vector_db/ ${JS_OUT}

.PHONY: setup
setup: activate install setup_hooks ## setup venv, activate, install python libraries, and setup git hooks

.PHONY: setup_hooks
setup_hooks: ## Setup Git pre-commit hooks for mandatory format, static_analysis, test
	@mkdir -p .githooks
	@echo '#!/bin/sh' > .githooks/pre-commit
	@echo 'set -e' >> .githooks/pre-commit
	@echo 'echo "=== [Pre-Commit Gate] 1/3: make format ==="' >> .githooks/pre-commit
	@echo 'make format' >> .githooks/pre-commit
	@echo 'echo "=== [Pre-Commit Gate] 2/3: make static_analysis ==="' >> .githooks/pre-commit
	@echo 'make static_analysis' >> .githooks/pre-commit
	@echo 'echo "=== [Pre-Commit Gate] 3/3: make test ==="' >> .githooks/pre-commit
	@echo 'make test' >> .githooks/pre-commit
	@chmod +x .githooks/pre-commit
	@git config core.hooksPath .githooks
	@echo "Git pre-commit hooks configured successfully in .githooks"

.PHONY: activate
activate: ## Create and activate venv
	@if [ ! -d "${VENV}" ]; then ${PYTHON} -m venv ${VENV}; fi

.PHONY: install
install: activate ## Install python libraries into venv
	${VENV_BIN}/pip install --upgrade pip
	${VENV_BIN}/pip install -r requirements.txt

.PHONY: format
format: isort black flake8 ## format python code

.PHONY: static_analysis
static_analysis: radon-cc radon-raw radon-mi radon-hal xenon mypy py_compile ## static analysis

.PHONY: py_compile
py_compile: activate ## py_compile syntax check for all python sources
	@for py in $(PYTHON_SRCS); do \
		${VENV_PYTHON} -m py_compile $$py || exit 1; \
	done

.PHONY: build_js
build_js: activate ## Build minified JS bundle using Google Closure Compiler (yuzora spec)
	${VENV_PYTHON} tools/closure-compiler/setup_compiler.py
	java -jar $(COMPILER) \
		--compilation_level SIMPLE_OPTIMIZATIONS \
		--warning_level VERBOSE \
		--language_in ECMASCRIPT_NEXT \
		--language_out ECMASCRIPT_2020 \
		--externs site/externs.js \
		--js $(JS_SRCS) \
		--js_output_file $(JS_OUT)

.PHONY: test
test: pytest ## pytest

.PHONY: check
check: format static_analysis test ## Run mandatory format, static_analysis, and test quality gates

.PHONY: verify_quality
verify_quality: format static_analysis test build_js ## Mandatory Quality Verification Gate across Python & JS

.PHONY: build
build: activate format static_analysis test build_js py_compile ## run mandatory quality gates (format, static_analysis, test) and build JS/Python

.PHONY: build_vector_db
build_vector_db: activate ## Build or rebuild semantic vector index
	${VENV_PYTHON} src/vector_engine.py --build

.PHONY: run_mcp_server
run_mcp_server: activate ## Launch standard Model Context Protocol (MCP) server
	${VENV_PYTHON} src/mcp_server.py

.PHONY: run_web
run_web: activate ## Launch Glassmorphic Web Search UI & MCP REST API Server (http://localhost:8000)
	${VENV_PYTHON} src/web_server.py --port 8000

.PHONY: rag_query
rag_query: activate ## Perform semantic vector RAG search e.g. make rag_query Q="LLM Jailbreak"
	${VENV_PYTHON} src/vector_engine.py --query "$(Q)"

.PHONY: run
run: activate ## run python code inside venv
	${VENV_PYTHON} ${SRC}

.PHONY: isort
isort: activate ## isort
	${VENV_BIN}/isort $(PYTHON_SRCS) ${TESTS} || true

.PHONY: black
black: activate ## black
	${VENV_BIN}/black $(PYTHON_SRCS) ${TESTS} || true

.PHONY: flake8
flake8: activate ## flake8
	${VENV_BIN}/flake8 $(PYTHON_SRCS) ${TESTS} || true

.PHONY: radon-cc
radon-cc: activate ## radon compute Cyclomatic Complexity (CC)
	${VENV_BIN}/radon cc $(PYTHON_SRCS) -s -a -na || true

.PHONY: radon-raw
radon-raw: activate ## radon compute raw metrics
	${VENV_BIN}/radon raw $(PYTHON_SRCS) || true

.PHONY: radon-mi
radon-mi: activate ## radon compute the Maintainability Index
	${VENV_BIN}/radon mi $(PYTHON_SRCS) -s -na || true

.PHONY: radon-hal
radon-hal: activate ## radon compute their Halstead metrics
	${VENV_BIN}/radon hal $(PYTHON_SRCS) || true

.PHONY: xenon
xenon: activate ## xenon
	${VENV_BIN}/xenon --max-absolute A --max-modules A --max-average A src || true

.PHONY: mypy
mypy: activate ## mypy
	${VENV_BIN}/mypy $(PYTHON_SRCS) || true

.PHONY: pytest
pytest: activate ## pytest
	${VENV_BIN}/pytest -v ${TESTS}
