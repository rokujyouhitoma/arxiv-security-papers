#!/bin/bash
# =======================================================================
# ULisp Frontend LIR Unit Test Suite (--target-lir)
# Conforms to DSN-33 Architecture Specification & Issue #591
#
# Fast-fail, toolchain-independent frontend verification.
# Verifies that Scheme sources compile to valid Canonical LIR S-expressions
# without invoking external C/Assembler compilers.
# =======================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$DIR/.." && pwd)"
export PYTHONPATH="$ROOT_DIR:$PYTHONPATH"
cd "$DIR"

if [ -x "$ROOT_DIR/.venv/bin/python" ]; then
    PYTHON_BIN="$ROOT_DIR/.venv/bin/python"
else
    PYTHON_BIN="python3"
fi
ILISP="${ILISP:-$PYTHON_BIN -m ilisp}"

# Prefer native ulisp-boot if available, as in test.sh
if [ -x "bin/ulisp-boot" ]; then
    COMPILER_EXEC="./bin/ulisp-boot"
elif [ -x "build/scheme-stage1" ]; then
    COMPILER_EXEC="./build/scheme-stage1"
else
    COMPILER_EXEC="$ILISP compiler.scm"
fi

PASSED=0
FAILED=0

echo "======================================================="
echo " Starting ULisp Frontend LIR Unit Test Suite (--target-lir)"
echo " Compiler engine: $COMPILER_EXEC"
echo "======================================================="

run_lir_test() {
    local test_name="$1"
    local input_scheme="$2"
    local expected_pattern="$3"

    local output
    output=$(echo "$input_scheme" | $COMPILER_EXEC 2>&1 || true)

    if echo "$output" | grep -q "%lir-program" && echo "$output" | grep -q "$expected_pattern"; then
        echo "  [PASS] $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $test_name"
        echo "    Input: $input_scheme"
        echo "    Expected pattern: $expected_pattern"
        echo "    Output was: $output"
        FAILED=$((FAILED + 1))
    fi
}

run_directive_test() {
    local test_name="$1"
    local input_scheme="$2"
    local expected_pattern="$3"

    local output
    output=$(echo "(!target lir) $input_scheme" | $COMPILER_EXEC 2>&1 || true)

    if echo "$output" | grep -q "%lir-program" && echo "$output" | grep -q "$expected_pattern"; then
        echo "  [PASS] $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $test_name"
        echo "    Input: (!target lir) $input_scheme"
        echo "    Expected pattern: $expected_pattern"
        echo "    Output was: $output"
        FAILED=$((FAILED + 1))
    fi
}

echo "--- Group 1: CLI Flag --target-lir Tests ---"
# Tagged Fixnum 42: 42 << 2 = 168
run_lir_test "Constant Integer (Tagged Fixnum)" "--target-lir 42" "%mov %rax 168"

# Dynamic addition preventing CP0 constant folding
run_lir_test "Dynamic Addition" "--target-lir (define (add20 x) (+ x 20))" "%add"

# Local variable binding
run_lir_test "Local Let Binding" "--target-lir (let ((x 5)) (+ x 1))" "%mov"

# Dynamic branch preventing CP0 dead branch pruning
run_lir_test "Dynamic Conditional Branch" "--target-lir (define (test-if c) (if c 1 2))" "%jump"

# Lambda invocation
run_lir_test "Simple Lambda Invocation" "--target-lir ((lambda (x) (+ x 1)) 42)" "%call"

echo "--- Group 2: S-expression Directive (!target lir) Tests ---"
# Tagged Fixnum 100: 100 << 2 = 400
run_directive_test "Directive Constant Integer" "100" "%mov %rax 400"
run_directive_test "Directive Boolean True" "#t" "%mov %rax"

# Dynamic subtraction
run_directive_test "Directive Dynamic Subtraction" "(define (sub20 x) (- x 20))" "%sub"

# User-defined function generating %lir-function
run_directive_test "Directive Multi-argument Function" "(define (f a b) (+ a b)) (f 3 4)" "%lir-function"

echo "======================================================="
echo " Frontend LIR Unit Tests Summary"
echo " Passed: $PASSED, Failed: $FAILED"
echo "======================================================="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
