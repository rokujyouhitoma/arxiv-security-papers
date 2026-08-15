PACKAGE=arxiv_okf_fetcher
PYTHON=python3
VENV=.venv
VENV_BIN=${VENV}/bin
VENV_PYTHON=${VENV_BIN}/python
SRC=src/arxiv_okf_fetcher.py
TESTS=tests

all: clean setup format static_analysis test build run

.PHONY: help
help: ## help command
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: clean
clean: ## clean virtualenv and build artifacts
	rm -rf dist/ __pycache__ src/__pycache__ tests/__pycache__ .pytest_cache .mypy_cache

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

.PHONY: test
test: pytest ## pytest

.PHONY: build
build: activate ## run python build / compile check
	${VENV_PYTHON} -m py_compile ${SRC}

.PHONY: run
run: activate ## run python code inside venv
	${VENV_PYTHON} ${SRC}

.PHONY: isort
isort: activate ## isort
	${VENV_BIN}/isort ${SRC} ${TESTS} || true

.PHONY: black
black: activate ## black
	${VENV_BIN}/black ${SRC} ${TESTS} || true

.PHONY: flake8
flake8: activate ## flake8
	${VENV_BIN}/flake8 ${SRC} ${TESTS} || true

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
