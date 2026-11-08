#!/usr/bin/env bash
# ==============================================================================
# ULisp CLI Diagnostics & Failure Rollback Verification (Issue #785)
# Verifies that:
#   1. Compiler diagnostic logs are emitted to stderr (fd 2), not stdout.
#   2. When compilation fails, the output file specified by -o is NEVER created or left behind.
#   3. Successful compilation produces functional ELF executables with 0755 permissions.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ULISP_DIR/build/cli_diagnostics"
COMPILER="${ULISP_COMPILER_BIN:-$ULISP_DIR/bin/ulisp-boot}"

mkdir -p "$BUILD_DIR"

PASS=0
FAIL=0

check() {
    local name="$1"; shift
    if "$@"; then
        echo "  [PASS] $name"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $name"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Running ULisp CLI Diagnostics & Failure Rollback Test Suite (Issue #785) ==="

# --- Test 1: Unbound Variable Error Rollback ---
OUT_FAIL="$BUILD_DIR/test_unbound_fail.bin"
STDERR_LOG="$BUILD_DIR/unbound_stderr.log"
STDOUT_LOG="$BUILD_DIR/unbound_stdout.log"
rm -f "$OUT_FAIL" "$STDERR_LOG" "$STDOUT_LOG"

set +e
"$COMPILER" -e "(print 1 2)" --target-elf -o "$OUT_FAIL" > "$STDOUT_LOG" 2> "$STDERR_LOG"
STATUS=$?
set -e

check "Test 1a: Exit status is non-zero on unbound variable error" [ "$STATUS" -ne 0 ]
check "Test 1b: Output file is not created/left on compilation failure" [ ! -e "$OUT_FAIL" ]
check "Test 1c: Diagnostic message is emitted to stderr" grep -q "Unbound variable in LIR: print" "$STDERR_LOG"
check "Test 1d: stdout remains clean during compilation error" [ ! -s "$STDOUT_LOG" ]

# --- Test 2: Syntax Error Rollback ---
OUT_SYNTAX="$BUILD_DIR/test_syntax_fail.bin"
SYNTAX_ERR="$BUILD_DIR/syntax_stderr.log"
rm -f "$OUT_SYNTAX" "$SYNTAX_ERR"

set +e
"$COMPILER" -e "(+ 1 (* 2 3" --target-elf -o "$OUT_SYNTAX" 2> "$SYNTAX_ERR"
STATUS=$?
set -e

check "Test 2a: Exit status is non-zero on reader syntax error" [ "$STATUS" -ne 0 ]
check "Test 2b: Output file is not created on syntax error" [ ! -e "$OUT_SYNTAX" ]

# --- Test 3: Successful Standalone ELF Compilation & Execution ---
OUT_PASS="$BUILD_DIR/test_success.bin"
rm -f "$OUT_PASS"

"$COMPILER" -e '(write-string "CLI_DIAGNOSTICS_OK\n")' --target-elf -o "$OUT_PASS"
check "Test 3a: Successful output file exists" [ -f "$OUT_PASS" ]
check "Test 3b: Output binary is executable (0755)" [ -x "$OUT_PASS" ]

EXEC_OUT=$("$OUT_PASS")
check "Test 3c: Binary execution output matches" [ "$EXEC_OUT" = "CLI_DIAGNOSTICS_OK" ]

# --- Test 4: Assembly Mode (-S) Error Rollback ---
OUT_ASM_FAIL="$BUILD_DIR/test_asm_fail.s"
rm -f "$OUT_ASM_FAIL"

set +e
"$COMPILER" -e "(non-existent-function 42)" -S -o "$OUT_ASM_FAIL" 2>/dev/null
STATUS=$?
set -e

check "Test 4a: Exit status is non-zero in -S mode on error" [ "$STATUS" -ne 0 ]
check "Test 4b: -S mode output file is not left behind on error" [ ! -e "$OUT_ASM_FAIL" ]

# --- Test 5: Assembly Mode (-S) Success ---
OUT_ASM_PASS="$BUILD_DIR/test_asm_pass.s"
rm -f "$OUT_ASM_PASS"

"$COMPILER" -e "(+ 10 20)" -S -o "$OUT_ASM_PASS"
check "Test 5a: -S mode produces assembly file on success" [ -s "$OUT_ASM_PASS" ]

# --- Summary ---
echo "=============================================================================="
echo " Results: $PASS Passed, $FAIL Failed"
echo "=============================================================================="

if [ "$FAIL" -gt 0 ]; then
    echo "FAILED: $FAIL test(s) failed."
    exit 1
fi

echo "ALL CLI DIAGNOSTICS TESTS PASSED!"
exit 0

