#!/bin/bash
# =======================================================================
# ULisp Backend LIR Unit Test Suite (Direct LIR Ingestion)
# Conforms to DSN-33 Architecture Specification & Issue #591
#
# Isolated backend verification without frontend preprocessing.
# Feeds Canonical LIR S-expressions directly to compiler backend,
# verifies x86-64 native assembly generation and standalone execution.
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
CC="${CC:-gcc}"

# Prefer native ulisp-boot if available, as in test.sh
if [ -x "bin/ulisp-boot" ]; then
    COMPILER_EXEC="./bin/ulisp-boot"
elif [ -x "build/scheme-stage1" ]; then
    COMPILER_EXEC="./build/scheme-stage1"
else
    COMPILER_EXEC="$ILISP compiler.scm"
fi

TMP_S="build/tmp_backend_out.s"
TMP_BIN="build/tmp_backend_bin"
mkdir -p build

PASSED=0
FAILED=0

echo "======================================================="
echo " Starting ULisp Backend Unit Test Suite (Direct LIR)"
echo " Compiler engine: $COMPILER_EXEC"
echo "======================================================="

run_backend_native_test() {
    local test_name="$1"
    local fixture_file="$2"
    local expected_output="$3"

    # Ingest Canonical LIR directly, target x86_64 native backend
    if cat "$fixture_file" | $COMPILER_EXEC > "$TMP_S" 2>/dev/null; then
        if $CC -nostdlib -static -o "$TMP_BIN" "$TMP_S" 2>/dev/null; then
            local actual_output
            actual_output=$("$TMP_BIN" 2>/dev/null || true)
            if [ "$actual_output" = "$expected_output" ]; then
                echo "  [PASS] $test_name (Output: $actual_output)"
                PASSED=$((PASSED + 1))
            else
                echo "  [FAIL] $test_name (Expected '$expected_output', got '$actual_output')"
                FAILED=$((FAILED + 1))
            fi
        else
            echo "  [FAIL] $test_name (x86 Assembly Compilation failed)"
            FAILED=$((FAILED + 1))
        fi
    else
        echo "  [FAIL] $test_name (LIR Ingestion failed)"
        FAILED=$((FAILED + 1))
    fi
    rm -f "$TMP_S" "$TMP_BIN"
}

echo "--- Group 1: Direct LIR Ingestion -> x86-64 Backend Tests ---"
# Fixture 01: returns fixnum 84 -> printed value = 84 / 4 = 21 (or raw value depending on tag)
# In ULisp runtime: fixnum is quotient val 4. So 84 / 4 = 21.
run_backend_native_test "Fixture 01: Constant Integer" "tests/fixtures/lir/01_const_int.lir" "21"

# Fixture 02: 20 + 40 = 60 -> printed = 60 / 4 = 15
run_backend_native_test "Fixture 02: LIR Addition" "tests/fixtures/lir/02_add.lir" "15"

# Fixture 03: conditional branch to label -> returns 200 -> printed = 200 / 4 = 50
run_backend_native_test "Fixture 03: LIR Branch" "tests/fixtures/lir/03_branch.lir" "50"

echo "======================================================="
echo " Backend LIR Unit Tests Summary"
echo " Passed: $PASSED, Failed: $FAILED"
echo "======================================================="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
