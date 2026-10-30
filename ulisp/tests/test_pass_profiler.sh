#!/usr/bin/env bash
# =======================================================================
# ULisp Nanopass Execution Profiler Test Suite
# Conforms to Issue #621 & DSN-33 Architecture Specification
# =======================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ULISP_DIR}/build"
mkdir -p "${BUILD_DIR}"

echo "========================================================================"
echo " Starting Nanopass Execution Profiler Test Suite (Issue #621)"
echo "========================================================================"

# Determine compiler runner
COMPILER_CMD=""
if [ -x "${BUILD_DIR}/ulisp-modular" ]; then
    COMPILER_CMD="${BUILD_DIR}/ulisp-modular"
elif [ -x "${ULISP_DIR}/bin/ulisp-modular" ]; then
    COMPILER_CMD="${ULISP_DIR}/bin/ulisp-modular"
elif [ -x "${ULISP_DIR}/bin/ulisp-boot" ]; then
    COMPILER_CMD="${ULISP_DIR}/bin/ulisp-boot"
elif [ -x "${BUILD_DIR}/ulisp-fast" ]; then
    COMPILER_CMD="${BUILD_DIR}/ulisp-fast"
elif [ -x "${ULISP_DIR}/build/scheme-stage2" ]; then
    COMPILER_CMD="${ULISP_DIR}/build/scheme-stage2"
elif [ -x "${ULISP_DIR}/bin/ulisp" ]; then
    COMPILER_CMD="${ULISP_DIR}/bin/ulisp"
elif command -v gosh >/dev/null 2>&1; then
    COMPILER_CMD="gosh ${ULISP_DIR}/compiler.scm"
elif command -v chibi-scheme >/dev/null 2>&1; then
    COMPILER_CMD="chibi-scheme ${ULISP_DIR}/compiler.scm"
else
    echo "ERROR: No suitable Scheme or ULisp compiler found!"
    exit 1
fi

echo "Using compiler: ${COMPILER_CMD}"

# -----------------------------------------------------------------------
# Test 1: S-expression directive (!time-passes)
# -----------------------------------------------------------------------
echo "--- Test 1: (!time-passes) S-expression Directive ---"
cat <<'EOF' > "${BUILD_DIR}/test_prof_input1.scm"
(!time-passes)
(define (fib n)
  (if (< n 2)
      n
      (+ (fib (- n 1)) (fib (- n 2)))))
(fib 10)
EOF

${COMPILER_CMD} < "${BUILD_DIR}/test_prof_input1.scm" > "${BUILD_DIR}/test_prof1.s" 2> "${BUILD_DIR}/test_prof1.err"

# 1.1 Verify stderr has profiler header and key passes
if ! grep -q "ULisp Nanopass Execution Profile (--time-passes)" "${BUILD_DIR}/test_prof1.err"; then
    echo "FAIL: Missing profiler header in stderr output!"
    cat "${BUILD_DIR}/test_prof1.err"
    exit 1
fi

for pass in "pass-010-library" "pass-020-macro-expander" "pass-030-desugar" "pass-070-anf" "pass-110-closure-convert" "pass-130-lir" "pass-140-backend"; do
    if ! grep -q "${pass}" "${BUILD_DIR}/test_prof1.err"; then
        echo "FAIL: Expected pass '${pass}' not found in profiler report!"
        cat "${BUILD_DIR}/test_prof1.err"
        exit 1
    fi
done

if ! grep -q "Total Compilation Time :" "${BUILD_DIR}/test_prof1.err"; then
    echo "FAIL: Missing Total Compilation Time in report!"
    cat "${BUILD_DIR}/test_prof1.err"
    exit 1
fi

if ! grep -q "Total Heap Allocation  :" "${BUILD_DIR}/test_prof1.err"; then
    echo "FAIL: Missing Total Heap Allocation in report!"
    cat "${BUILD_DIR}/test_prof1.err"
    exit 1
fi

# 1.2 Verify stdout has NO profiler leakage
if grep -q "ULisp Nanopass Execution Profile" "${BUILD_DIR}/test_prof1.s"; then
    echo "FAIL: Profiler output leaked into standard output (assembly)!"
    exit 1
fi

if grep -q "Total Compilation Time" "${BUILD_DIR}/test_prof1.s"; then
    echo "FAIL: Summary leaked into standard output (assembly)!"
    exit 1
fi

# 1.3 Verify generated assembly is valid
if command -v as >/dev/null 2>&1; then
    as "${BUILD_DIR}/test_prof1.s" -o "${BUILD_DIR}/test_prof1.o"
    echo "  [PASS] Assembled generated output successfully with 'as'"
fi

echo "  [PASS] Test 1: (!time-passes) validated successfully."

# -----------------------------------------------------------------------
# Test 2: Environment Variable ULISP_BENCH_PASSES=1
# -----------------------------------------------------------------------
echo "--- Test 2: Environment Variable ULISP_BENCH_PASSES=1 ---"
cat <<'EOF' > "${BUILD_DIR}/test_prof_input2.scm"
(define (fact n)
  (if (<= n 1)
      1
      (* n (fact (- n 1)))))
(fact 5)
EOF

env ULISP_BENCH_PASSES=1 ${COMPILER_CMD} < "${BUILD_DIR}/test_prof_input2.scm" > "${BUILD_DIR}/test_prof2.s" 2> "${BUILD_DIR}/test_prof2.err"

if ! grep -q "ULisp Nanopass Execution Profile (--time-passes)" "${BUILD_DIR}/test_prof2.err"; then
    echo "FAIL: ULISP_BENCH_PASSES=1 did not enable profiler output!"
    cat "${BUILD_DIR}/test_prof2.err"
    exit 1
fi
echo "  [PASS] Test 2: Environment variable ULISP_BENCH_PASSES=1 validated."

# -----------------------------------------------------------------------
# Test 3: Normal Compilation Differential Equivalence (Zero Overhead / No Pollution)
# -----------------------------------------------------------------------
echo "--- Test 3: Differential Equivalence & Zero Output Pollution ---"
${COMPILER_CMD} < "${BUILD_DIR}/test_prof_input2.scm" > "${BUILD_DIR}/test_normal2.s" 2> "${BUILD_DIR}/test_normal2.err"

if grep -q "ULisp Nanopass Execution Profile" "${BUILD_DIR}/test_normal2.err"; then
    echo "FAIL: Normal compilation without flags printed profiler output!"
    exit 1
fi

# Generated code must match bit-for-bit with the code generated under profiling
if ! diff -u "${BUILD_DIR}/test_normal2.s" "${BUILD_DIR}/test_prof2.s" > "${BUILD_DIR}/diff.patch"; then
    echo "FAIL: Generated assembly differed between profiled and non-profiled compilation!"
    cat "${BUILD_DIR}/diff.patch"
    exit 1
fi

echo "  [PASS] Test 3: Differential equivalence verified (exact bit-for-bit match)."

echo "========================================================================"
echo " All Nanopass Execution Profiler Tests PASSED (100% OK)"
echo "========================================================================"
