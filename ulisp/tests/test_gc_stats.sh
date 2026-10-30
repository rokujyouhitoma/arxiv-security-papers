#!/usr/bin/env bash
# =======================================================================
# ULisp Runtime GC Statistics (ULISP_GC_STATS) Test Suite
# Conforms to Issue #622 & DSN-33 Architecture Specification
# =======================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ULISP_DIR}/build"
mkdir -p "${BUILD_DIR}"

echo "========================================================================"
echo " Starting Runtime GC Statistics Test Suite (Issue #622)"
echo "========================================================================"

# Determine compiler runner
COMPILER_CMD=""
if [ -n "${ULISP_COMPILER:-}" ]; then
    COMPILER_CMD="${ULISP_COMPILER}"
elif command -v gosh >/dev/null 2>&1; then
    COMPILER_CMD="gosh ${ULISP_DIR}/compiler.scm"
elif command -v python3 >/dev/null 2>&1 && python3 -c "import ilisp" >/dev/null 2>&1; then
    COMPILER_CMD="python3 -m ilisp ${ULISP_DIR}/compiler.scm"
elif [ -x "${BUILD_DIR}/ulisp-modular" ]; then
    COMPILER_CMD="${BUILD_DIR}/ulisp-modular"
elif [ -x "${ULISP_DIR}/bin/ulisp-boot" ]; then
    COMPILER_CMD="${ULISP_DIR}/bin/ulisp-boot"
elif [ -x "${ULISP_DIR}/bin/ulisp" ]; then
    COMPILER_CMD="${ULISP_DIR}/bin/ulisp"
elif command -v chibi-scheme >/dev/null 2>&1; then
    COMPILER_CMD="chibi-scheme ${ULISP_DIR}/compiler.scm"
else
    COMPILER_CMD="python3 -m ilisp ${ULISP_DIR}/compiler.scm"
fi

echo "Using compiler: ${COMPILER_CMD}"

# -----------------------------------------------------------------------
# Test 1: x86-64 Freestanding Native - Quiet-by-Default (ULISP_GC_STATS unset)
# -----------------------------------------------------------------------
echo "--- Test 1: x86-64 Freestanding - Quiet-by-Default ---"
cat <<'EOF' > "${BUILD_DIR}/test_gc_stats_1.scm"
(cons 1 (cons 2 (cons 3 '())))
EOF

${COMPILER_CMD} < "${BUILD_DIR}/test_gc_stats_1.scm" > "${BUILD_DIR}/test_gc_stats_1.s"
as --64 "${BUILD_DIR}/test_gc_stats_1.s" -o "${BUILD_DIR}/test_gc_stats_1.o"
ld -m elf_x86_64 -static "${BUILD_DIR}/test_gc_stats_1.o" -o "${BUILD_DIR}/test_gc_stats_1_bin"

res=$(ULISP_PRINT_RESULT=1 "${BUILD_DIR}/test_gc_stats_1_bin" 2> "${BUILD_DIR}/test_gc_stats_1.err")
test "${res}" = "(1 2 3)"
if [ -s "${BUILD_DIR}/test_gc_stats_1.err" ]; then
    echo "FAIL: Expected empty stderr when ULISP_GC_STATS is unset, got:"
    cat "${BUILD_DIR}/test_gc_stats_1.err"
    exit 1
fi
echo "PASS: Quiet-by-default verified (stderr is empty)."

# -----------------------------------------------------------------------
# Test 2: x86-64 Freestanding Native - ULISP_GC_STATS=1
# -----------------------------------------------------------------------
echo "--- Test 2: x86-64 Freestanding - ULISP_GC_STATS=1 ---"
res=$(ULISP_PRINT_RESULT=1 ULISP_GC_STATS=1 "${BUILD_DIR}/test_gc_stats_1_bin" 2> "${BUILD_DIR}/test_gc_stats_2.err")
test "${res}" = "(1 2 3)"

if ! grep -q "\[ULISP GC STATS\] Collections:" "${BUILD_DIR}/test_gc_stats_2.err"; then
    echo "FAIL: Missing [ULISP GC STATS] header in stderr output!"
    cat "${BUILD_DIR}/test_gc_stats_2.err"
    exit 1
fi

if ! grep -q "Alloc: 72 bytes" "${BUILD_DIR}/test_gc_stats_2.err"; then
    echo "FAIL: Expected 'Alloc: 72 bytes' for 3 cons cells, got:"
    cat "${BUILD_DIR}/test_gc_stats_2.err"
    exit 1
fi

if ! grep -q "Copied:" "${BUILD_DIR}/test_gc_stats_2.err" || ! grep -q "GC Time:" "${BUILD_DIR}/test_gc_stats_2.err"; then
    echo "FAIL: Expected Copied and GC Time fields in stderr output!"
    cat "${BUILD_DIR}/test_gc_stats_2.err"
    exit 1
fi
echo "PASS: ULISP_GC_STATS=1 allocation tracking verified (Alloc: 72 bytes)."

# -----------------------------------------------------------------------
# Test 3: x86-64 Freestanding Native - Multiple Allocations Loop & GC
# -----------------------------------------------------------------------
echo "--- Test 3: x86-64 Freestanding - Loop Allocations ---"
cat <<'EOF' > "${BUILD_DIR}/test_gc_stats_3.scm"
(letrec ((build (lambda (n acc)
                  (if (= n 0)
                      acc
                      (build (- n 1) (cons n acc))))))
  (car (build 1000 '())))
EOF

${COMPILER_CMD} < "${BUILD_DIR}/test_gc_stats_3.scm" > "${BUILD_DIR}/test_gc_stats_3.s"
as --64 "${BUILD_DIR}/test_gc_stats_3.s" -o "${BUILD_DIR}/test_gc_stats_3.o"
ld -m elf_x86_64 -static "${BUILD_DIR}/test_gc_stats_3.o" -o "${BUILD_DIR}/test_gc_stats_3_bin"

res=$(ULISP_PRINT_RESULT=1 ULISP_GC_STATS=1 "${BUILD_DIR}/test_gc_stats_3_bin" 2> "${BUILD_DIR}/test_gc_stats_3.err")
test "${res}" = "1"

if ! grep -q "Alloc:" "${BUILD_DIR}/test_gc_stats_3.err"; then
    echo "FAIL: Missing Alloc in loop allocation test!"
    cat "${BUILD_DIR}/test_gc_stats_3.err"
    exit 1
fi
echo "PASS: Loop allocation stats verified."

# -----------------------------------------------------------------------
# Test 4: C Backend - ULISP_GC_STATS=1
# -----------------------------------------------------------------------
echo "--- Test 4: C Backend - ULISP_GC_STATS=1 ---"
cat <<'EOF' > "${BUILD_DIR}/test_gc_stats_4.scm"
(!target c)
(cons 10 (cons 20 (cons 30 '())))
EOF

${COMPILER_CMD} < "${BUILD_DIR}/test_gc_stats_4.scm" > "${BUILD_DIR}/test_gc_stats_4.c"
${CC:-gcc} -O2 -Wno-unused-label "${BUILD_DIR}/test_gc_stats_4.c" -o "${BUILD_DIR}/test_gc_stats_4_bin"

res_c=$(ULISP_PRINT_RESULT=1 ULISP_GC_STATS=1 "${BUILD_DIR}/test_gc_stats_4_bin" 2> "${BUILD_DIR}/test_gc_stats_4.err")
test "${res_c}" = "(10 20 30)"

if ! grep -q "\[ULISP GC STATS\] Collections:" "${BUILD_DIR}/test_gc_stats_4.err"; then
    echo "FAIL: Missing [ULISP GC STATS] header in C backend stderr!"
    cat "${BUILD_DIR}/test_gc_stats_4.err"
    exit 1
fi

if ! grep -q "Alloc:" "${BUILD_DIR}/test_gc_stats_4.err"; then
    echo "FAIL: Missing Alloc in C backend stderr!"
    cat "${BUILD_DIR}/test_gc_stats_4.err"
    exit 1
fi
echo "PASS: C Backend ULISP_GC_STATS=1 verified."

# -----------------------------------------------------------------------
# Test 5: Disabled when ULISP_GC_STATS=0
# -----------------------------------------------------------------------
echo "--- Test 5: ULISP_GC_STATS=0 Explicit Disable ---"
res=$(ULISP_PRINT_RESULT=1 ULISP_GC_STATS=0 "${BUILD_DIR}/test_gc_stats_1_bin" 2> "${BUILD_DIR}/test_gc_stats_5.err")
test "${res}" = "(1 2 3)"
if [ -s "${BUILD_DIR}/test_gc_stats_5.err" ]; then
    echo "FAIL: Expected empty stderr when ULISP_GC_STATS=0, got:"
    cat "${BUILD_DIR}/test_gc_stats_5.err"
    exit 1
fi
echo "PASS: ULISP_GC_STATS=0 correctly disabled statistics."

echo "========================================================================"
echo " ALL GC STATISTICS TESTS PASSED (5/5)!"
echo "========================================================================"
