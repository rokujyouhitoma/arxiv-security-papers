#!/bin/bash
set -euo pipefail

# =======================================================================
# Unit Test Suite: Bootstrap Diagnostics & Fallback Trace (Issue #605)
# =======================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ULISP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$ULISP_DIR/.." && pwd)"
TEST_TMP="$ULISP_DIR/build/test_diagnostics_tmp"

mkdir -p "$TEST_TMP"

TESTS_RUN=0
TESTS_PASSED=0

assert_true() {
    local label="$1"
    local condition="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$condition" = "1" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  \033[1;32m[PASS]\033[0m $label"
    else
        echo -e "  \033[1;31m[FAIL]\033[0m $label" >&2
        exit 1
    fi
}

echo "======================================================="
echo " Starting Issue #605 (Bootstrap Diagnostics) Test Suite"
echo "======================================================="

# Extract diagnose_stage_failure definition from bootstrap.sh to test in isolation
EXTRACTED_LIB="$TEST_TMP/diag_lib.sh"
cat << 'EOF' > "$EXTRACTED_LIB"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ULISP_DIR="$ROOT_DIR/ulisp"
BUILD_DIR="$ULISP_DIR/build"
PYTHON_BIN="python3"
if [ -x "$ROOT_DIR/.venv/bin/python" ]; then
    PYTHON_BIN="$ROOT_DIR/.venv/bin/python"
fi
BOOT_BIN="$ULISP_DIR/bin/ulisp-boot"
GOSH_BIN="$(command -v gosh 2>/dev/null || true)"
EOF

# Extract diagnose_stage_failure function from bootstrap.sh
sed -n '/^BOOTSTRAP_DIAGNOSE=/,/^check_asm_output()/p' "$ULISP_DIR/bootstrap.sh" | sed '$d' >> "$EXTRACTED_LIB"

# Prepare small sample Scheme input files
SAMPLE_INPUT="$TEST_TMP/sample_input.scm"
echo "(display 42)" > "$SAMPLE_INPUT"

SAMPLE_ERR_INPUT="$TEST_TMP/sample_err_input.scm"
echo "(undefined-variable-for-diag-test 1 2 3)" > "$SAMPLE_ERR_INPUT"

# --- Group 1: Advisory Banner & Error Classification ---
echo "--- Group 1: Advisory Banner & Error Classification ---"

# Test SIGSEGV classification (exit code 139)
OUT1="$TEST_TMP/out1.log"
(
    source "$EXTRACTED_LIB"
    export BOOTSTRAP_DIAGNOSE=1
    diagnose_stage_failure "Stage 2 (scheme-stage1)" "/dev/null" 139 "Crash during execution" "$SAMPLE_INPUT"
) > "$OUT1" 2>&1 || true

has_banner=$(grep -q "\[DIAGNOSTIC ADVISORY\] Bootstrap Stage Failure Detected!" "$OUT1" && echo 1 || echo 0)
assert_true "Advisory banner displayed on failure" "$has_banner"

has_sigsegv=$(grep -q "Segmentation fault (SIGSEGV)" "$OUT1" && echo 1 || echo 0)
assert_true "Exit code 139 classified as SIGSEGV" "$has_sigsegv"

# Test Scheme runtime exception classification
OUT2="$TEST_TMP/out2.log"
DUMMY_ERR_ASM="$TEST_TMP/dummy_err.s"
echo "*** ERROR: unbound variable: car" > "$DUMMY_ERR_ASM"
(
    source "$EXTRACTED_LIB"
    export BOOTSTRAP_DIAGNOSE=1
    diagnose_stage_failure "Stage 1 (native)" "$DUMMY_ERR_ASM" 0 "Runtime exception" "$SAMPLE_INPUT"
) > "$OUT2" 2>&1 || true

has_extracted=$(grep -q "\*\*\* ERROR: unbound variable: car" "$OUT2" && echo 1 || echo 0)
assert_true "Runtime error message extracted and displayed" "$has_extracted"

# --- Group 2: Suppression with BOOTSTRAP_DIAGNOSE=0 ---
echo "--- Group 2: Suppression with BOOTSTRAP_DIAGNOSE=0 ---"

OUT3="$TEST_TMP/out3.log"
(
    source "$EXTRACTED_LIB"
    export BOOTSTRAP_DIAGNOSE=0
    diagnose_stage_failure "Stage 2 (scheme-stage1)" "/dev/null" 139 "Crash" "$SAMPLE_INPUT"
) > "$OUT3" 2>&1 || true

is_suppressed=$([ ! -s "$OUT3" ] && echo 1 || echo 0)
assert_true "Diagnostics completely suppressed when BOOTSTRAP_DIAGNOSE=0" "$is_suppressed"

# --- Group 3: Recursion Guard ---
echo "--- Group 3: Recursion Guard ---"

OUT4="$TEST_TMP/out4.log"
(
    source "$EXTRACTED_LIB"
    export BOOTSTRAP_DIAGNOSE=1
    _DIAGNOSING=1
    diagnose_stage_failure "Stage 2" "/dev/null" 1 "Recursive call test" "$SAMPLE_INPUT"
) > "$OUT4" 2>&1 || true

is_recursion_guarded=$([ ! -s "$OUT4" ] && echo 1 || echo 0)
assert_true "Recursion guard (_DIAGNOSING=1) prevents repeated diagnosis" "$is_recursion_guarded"

# --- Group 4: Direct Fallback Command Output ---
echo "--- Group 4: Direct Fallback Command Output ---"

has_repro_cmd=$(grep -q "Direct Reproduction Command" "$OUT1" && echo 1 || echo 0)
assert_true "Direct reproduction command provided in output" "$has_repro_cmd"

# --- Group 5: Secondary Diagnostic Trace Execution ---
echo "--- Group 5: Secondary Diagnostic Trace Execution ---"

OUT5="$TEST_TMP/out5.log"
(
    source "$EXTRACTED_LIB"
    export BOOTSTRAP_DIAGNOSE=1
    diagnose_stage_failure "Stage 2 (scheme-stage1)" "/dev/null" 1 "Unbound variable error" "$SAMPLE_ERR_INPUT"
) > "$OUT5" 2>&1 || true

has_fallback_attempt=$(grep -E -q "Executing Secondary Diagnostic Fallback Trace" "$OUT5" && echo 1 || echo 0)
assert_true "Secondary diagnostic fallback execution triggered" "$has_fallback_attempt"

# Cleanup temporary test files
rm -rf "$TEST_TMP"

echo "======================================================="
echo " Test Suite Results: $TESTS_PASSED / $TESTS_RUN Passed"
echo "======================================================="
