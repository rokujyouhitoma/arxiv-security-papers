PACKAGE=arxiv_okf_fetcher
PYTHON_TARGET_VERSION = 3.14+
PYTHON ?= $(shell if [ -x "$$HOME/.local/python-3.14.7/bin/python3" ]; then echo "$$HOME/.local/python-3.14.7/bin/python3"; elif [ -x "/root/.local/python-3.14.7/bin/python3" ]; then echo "/root/.local/python-3.14.7/bin/python3"; elif command -v python3.14 >/dev/null 2>&1; then command -v python3.14; elif command -v python3 >/dev/null 2>&1; then command -v python3; else echo ""; fi)

ifeq ($(PYTHON),)
$(error "Strict Error: Python ($(PYTHON_TARGET_VERSION)) is required but not found in PATH.")
endif

VENV=.venv
VENV_BIN=${VENV}/bin
VENV_PYTHON=${VENV_BIN}/python

SRC=src/intelligence/cli.py
PYTHON_SRCS := $(shell find src -type f -name "*.py" | sort)
TESTS := $(shell find tests -type f -name "*.py" | sort)

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
setup_hooks: ## Setup Git pre-commit hooks for mandatory check_format and static_analysis
	@mkdir -p .githooks
	@echo '#!/bin/sh' > .githooks/pre-commit
	@echo 'set -e' >> .githooks/pre-commit
	@echo 'echo "=== [Pre-Commit Gate] 1/2: make check_format ==="' >> .githooks/pre-commit
	@echo 'make check_format' >> .githooks/pre-commit
	@echo 'echo "=== [Pre-Commit Gate] 2/2: make static_analysis ==="' >> .githooks/pre-commit
	@echo 'make static_analysis' >> .githooks/pre-commit
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

.PHONY: check_format
check_format: activate ## Check python code formatting and style without modifying files
	${VENV_BIN}/isort --check-only --diff $(PYTHON_SRCS) $(TESTS)
	${VENV_BIN}/black --check --diff $(PYTHON_SRCS) $(TESTS)
	${VENV_BIN}/flake8 $(PYTHON_SRCS) $(TESTS)

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
build_js: activate ## Build minified JS bundle using Google Closure Compiler with strict checks
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
check: check_format static_analysis test ## Run mandatory format check, static_analysis, and test quality gates

.PHONY: verify_quality
verify_quality: check_format static_analysis test build_js ## Mandatory Strict Quality Verification Gate across Python & JS

.PHONY: build
build: activate format static_analysis test build_js py_compile ## run mandatory quality gates (format, static_analysis, test) and build JS/Python

.PHONY: build_vector_db
build_vector_db: activate ## Build or rebuild semantic vector index
	PYTHONPATH=src ${VENV_PYTHON} -m search.vector_engine --build

.PHONY: run_mcp_server
run_mcp_server: activate ## Launch standard Model Context Protocol (MCP) server
	PYTHONPATH=src ${VENV_PYTHON} src/mcp/papers_server.py

.PHONY: run_observability_mcp
run_observability_mcp: activate ## Launch Observability & Profiling MCP server for AI coding agents
	PYTHONPATH=src ${VENV_PYTHON} src/mcp/observability_server.py

.PHONY: run_threat_defense_mcp
run_threat_defense_mcp: activate ## Launch Threat Defense & Secure Patch MCP server
	PYTHONPATH=src ${VENV_PYTHON} src/mcp/threat_defense_server.py

.PHONY: run_tech_radar_mcp
run_tech_radar_mcp: activate ## Launch Tech Radar & Threat Intelligence MCP server
	PYTHONPATH=src ${VENV_PYTHON} src/mcp/tech_radar_server.py

.PHONY: mcp_stats
mcp_stats: activate ## Display and export aggregated MCP usage metrics and performance report
	PYTHONPATH=src ${VENV_PYTHON} -m mcp.analytics --export

.PHONY: eval_search
eval_search: activate ## Run search engine quality benchmark (Precision@K, Recall@K, MAP, MRR, NDCG)
	PYTHONPATH=src ${VENV_PYTHON} -c "from search.eval.evaluator import SearchEvaluator; from search.server.handler.select_handler import SelectHandler; h = SelectHandler(); e = SearchEvaluator(); r = e.evaluate(lambda q, k: [d.get('id', '') for d in h.handle_select(query=q, top_k=k).get('response', {}).get('docs', [])]); print(e.generate_markdown_report(r))"

.PHONY: run_web
run_web: activate ## Launch Glassmorphic Web Search UI & MCP REST API Server (http://localhost:8000)
	PYTHONPATH=src ${VENV_PYTHON} src/web/server.py --port 8000

.PHONY: run_dashboard
run_dashboard: activate ## Launch Graph Engineering Dashboard & Web Server (http://localhost:8000/dashboard)
	PYTHONPATH=src ${VENV_PYTHON} src/web/server.py --port 8000

.PHONY: run_supervisor
run_supervisor: activate ## Launch Gunicorn-style Pre-Fork Process Supervisor & Arbiter (foreground)
	PYTHONPATH=src ${VENV_PYTHON} -m supervisor.cli start $(ARGS)

.PHONY: start_supervisor
start_supervisor: activate ## Launch Process Supervisor in background daemon mode (-D)
	PYTHONPATH=src ${VENV_PYTHON} -m supervisor.cli start -D $(ARGS)

.PHONY: status_supervisor
status_supervisor: activate ## Check live Process Supervisor status via IPC Unix domain socket
	PYTHONPATH=src ${VENV_PYTHON} -m supervisor.cli status

.PHONY: stop_supervisor
stop_supervisor: activate ## Gracefully stop Process Supervisor daemon and all workers
	PYTHONPATH=src ${VENV_PYTHON} -m supervisor.cli stop

.PHONY: reload_supervisor
reload_supervisor: activate ## Rolling reload Process Supervisor configuration and workers
	PYTHONPATH=src ${VENV_PYTHON} -m supervisor.cli reload

.PHONY: top_supervisor
top_supervisor: activate ## Live process & worker top monitoring dashboard
	PYTHONPATH=src ${VENV_PYTHON} -m supervisor.cli top $(ARGS)

.PHONY: orchestrate
orchestrate: activate ## Run Universal Intelligence Orchestrator 6-phase autonomous cycle
	PYTHONPATH=src ${VENV_PYTHON} src/intelligence/cli.py cycle $(ARGS)

.PHONY: orchestrate_daemon
orchestrate_daemon: activate ## Run Universal Intelligence Orchestrator in continuous daemon mode
	PYTHONPATH=src ${VENV_PYTHON} src/intelligence/cli.py daemon $(ARGS)

.PHONY: pipeline
pipeline: activate ## Run multi-theme arXiv ETL ingestion pipeline directly
	PYTHONPATH=src ${VENV_PYTHON} src/pipeline/arxiv_okf_fetcher.py

.PHONY: backfill_160d
backfill_160d: activate ## Run autonomous 160-day historical arXiv backfill batch
	PYTHONPATH=src ${VENV_PYTHON} src/pipeline/arxiv_okf_fetcher.py --backfill 160 $(ARGS)

.PHONY: backfill_resume
backfill_resume: activate ## Resume interrupted historical arXiv backfill from checkpoint
	PYTHONPATH=src ${VENV_PYTHON} src/pipeline/arxiv_okf_fetcher.py --resume $(ARGS)

.PHONY: rag_query
rag_query: activate ## Perform semantic vector RAG search e.g. make rag_query Q="LLM Jailbreak"
	PYTHONPATH=src ${VENV_PYTHON} -m search.vector_engine --query "$(Q)"

.PHONY: build_knowledge_graph
build_knowledge_graph: activate ## Extract ontology and construct persistent Security Knowledge Graph
	PYTHONPATH=src ${VENV_PYTHON} -m graph.cli build

.PHONY: graph_stats
graph_stats: activate ## Display topological statistics of Security Knowledge Graph
	PYTHONPATH=src ${VENV_PYTHON} -m graph.cli show

.PHONY: run
run: activate ## Run Universal Autonomous Intelligence Orchestrator (or custom $SRC)
	PYTHONPATH=src ${VENV_PYTHON} ${SRC} $(ARGS)

.PHONY: aggregate_analytics
aggregate_analytics: activate ## Run batch pre-calculation of strategic KPIs and threat analytics
	PYTHONPATH=src ${VENV_PYTHON} -m analytics.cli aggregate

.PHONY: isort
isort: activate ## isort
	${VENV_BIN}/isort $(PYTHON_SRCS) ${TESTS}

.PHONY: black
black: activate ## black
	${VENV_BIN}/black $(PYTHON_SRCS) ${TESTS}

.PHONY: flake8
flake8: activate ## flake8
	${VENV_BIN}/flake8 $(PYTHON_SRCS) ${TESTS}

.PHONY: radon-cc
radon-cc: activate ## radon compute Cyclomatic Complexity (CC)
	${VENV_BIN}/radon cc $(PYTHON_SRCS) -s -a -na

.PHONY: radon-raw
radon-raw: activate ## radon compute raw metrics
	${VENV_BIN}/radon raw $(PYTHON_SRCS)

.PHONY: radon-mi
radon-mi: activate ## radon compute the Maintainability Index
	${VENV_BIN}/radon mi $(PYTHON_SRCS) -s -na

.PHONY: radon-hal
radon-hal: activate ## radon compute their Halstead metrics
	${VENV_BIN}/radon hal $(PYTHON_SRCS)

.PHONY: xenon
xenon: activate ## xenon strict cyclomatic complexity enforcement (Grade A avg/modules/absolute)
	${VENV_BIN}/xenon --max-absolute A --max-modules A --max-average A src

.PHONY: mypy
mypy: activate ## mypy
	${VENV_BIN}/mypy --strict src

.PHONY: pytest
pytest: activate ## pytest (fast execution excluding @pytest.mark.slow)
	${VENV_BIN}/pytest -v --strict-markers -m "not slow" -W error --cov=src --cov-fail-under=80 ${TESTS}

.PHONY: test_scenarios
test_scenarios: activate ## Run DSN-14 Scenarios 1-7 in tests/database/scenarios/
	${VENV_BIN}/pytest -v --strict-markers -W error tests/database/scenarios/

.PHONY: test_slow
test_slow: activate ## Run only slow-running comprehensive stress tests (@pytest.mark.slow)
	${VENV_BIN}/pytest -v --strict-markers -m slow -W error ${TESTS}

.PHONY: test_all
test_all: activate ## Run all tests including slow comprehensive E2E scenarios
	${VENV_BIN}/pytest -v --strict-markers -W error --cov=src --cov-fail-under=80 ${TESTS}

.PHONY: ir_eval
ir_eval: activate ## Evaluate IR ranking accuracy metrics (NDCG@10, MRR, MAP)
	PYTHONPATH=src ${VENV_PYTHON} -m search.eval.ci_gate --update-baseline

.PHONY: check_ir_regression
check_ir_regression: activate ## Enforce CI quality gate against IR metrics regression (threshold <= 3%)
	PYTHONPATH=src ${VENV_PYTHON} -m search.eval.ci_gate --threshold 0.03

