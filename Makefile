PACKAGE=arxiv_okf_fetcher
PYTHON=python3
VENV=.venv
VENV_BIN=${VENV}/bin
VENV_PYTHON=${VENV_BIN}/python
SRC=src/arxiv_okf_fetcher.py
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
setup: activate install ## setup venv, activate and install python libraries

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
py_compile: activate ## py_compile syntax check
	${VENV_PYTHON} -m py_compile ${SRC}
	${VENV_PYTHON} -m py_compile src/vector_engine.py
	${VENV_PYTHON} -m py_compile src/synonym_expander.py
	${VENV_PYTHON} -m py_compile src/mcp_server.py
	${VENV_PYTHON} -m py_compile src/web_server.py

.PHONY: build_js
build_js: ## Build minified JS bundle using Google Closure Compiler (yuzora spec)
	python3 tools/closure-compiler/setup_compiler.py
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

.PHONY: build
build: activate build_js ## run python build / compile check and JS compilation
	${VENV_PYTHON} -m py_compile ${SRC}

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
	${VENV_BIN}/isort ${SRC} src/vector_engine.py src/synonym_expander.py src/mcp_server.py src/web_server.py ${TESTS} || true

.PHONY: black
black: activate ## black
	${VENV_BIN}/black ${SRC} src/vector_engine.py src/synonym_expander.py src/mcp_server.py src/web_server.py ${TESTS} || true

.PHONY: flake8
flake8: activate ## flake8
	${VENV_BIN}/flake8 ${SRC} src/vector_engine.py src/synonym_expander.py src/mcp_server.py src/web_server.py ${TESTS} || true

.PHONY: radon-cc
radon-cc: activate ## radon compute Cyclomatic Complexity (CC)
	${VENV_BIN}/radon cc ${SRC} -s -a -na || true

.PHONY: radon-raw
radon-raw: activate ## radon compute raw metrics
	${VENV_BIN}/radon raw ${SRC} || true

.PHONY: radon-mi
radon-mi: activate ## radon compute the Maintainability Index
	${VENV_BIN}/radon mi ${SRC} -s -na || true

.PHONY: radon-hal
radon-hal: activate ## radon compute their Halstead metrics
	${VENV_BIN}/radon hal ${SRC} || true

.PHONY: xenon
xenon: activate ## xenon
	${VENV_BIN}/xenon --max-absolute A --max-modules A --max-average A src || true

.PHONY: mypy
mypy: activate ## mypy
	${VENV_BIN}/mypy ${SRC} || true

.PHONY: pytest
pytest: activate ## pytest
	${VENV_BIN}/pytest --cov=src --cov-report=term-missing -v ${TESTS} || ${VENV_BIN}/pytest || true
