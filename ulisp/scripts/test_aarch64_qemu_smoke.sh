#!/bin/bash
# ==============================================================================
# ULisp AArch64 AOT Native Code Generation & QEMU Smoke Test Suite
# Conforms to Issue #691 & DSN-33 Architecture Specification
# Verifies zero-libc static ELF binary generation and execution under QEMU.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CROSS_AS="${CROSS_AS_AARCH64:-aarch64-linux-gnu-as}"
CROSS_LD="${CROSS_LD_AARCH64:-aarch64-linux-gnu-ld}"
QEMU="${QEMU_AARCH64:-$(command -v qemu-aarch64 || command -v qemu-aarch64-static || true)}"

if [ -z "${QEMU}" ] || [ ! -x "${QEMU}" ]; then
    echo "ERROR: qemu-aarch64 emulator not found." >&2
    exit 1
fi

if ! command -v "${CROSS_AS}" >/dev/null 2>&1; then
    echo "ERROR: Cross-assembler ${CROSS_AS} not found." >&2
    exit 1
fi

if ! command -v "${CROSS_LD}" >/dev/null 2>&1; then
    echo "ERROR: Cross-linker ${CROSS_LD} not found." >&2
    exit 1
fi

TMP_DIR="$(mktemp -d /tmp/ulisp_aarch64_smoke_XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "======================================================================="
echo " Starting ULisp AArch64 AOT Native Execution & QEMU Smoke Test Suite"
echo " Toolchain : ${CROSS_AS} / ${CROSS_LD} / ${QEMU}"
echo "======================================================================="

TESTS_PASSED=0
TESTS_FAILED=0

run_qemu_test() {
    local test_name="$1"
    local scheme_code="$2"
    local expected_exit="$3"
    local expected_stdout="${4:-}"

    echo "--> [Testing] ${test_name}..."

    local src_file="${TMP_DIR}/test.scm"
    local asm_file="${TMP_DIR}/test.s"
    local obj_file="${TMP_DIR}/test.o"
    local bin_file="${TMP_DIR}/test.bin"
    local out_file="${TMP_DIR}/test.stdout"

    printf "%s\n" "${scheme_code}" > "${src_file}"

    # 1. Compile Scheme to GNU AArch64 assembly
    if ! gosh -I "${ULISP_DIR}" "${ULISP_DIR}/compiler.scm" --target=aarch64 < "${src_file}" > "${asm_file}" 2>/dev/null; then
        echo "  [FAIL] Compilation to AArch64 assembly failed for: ${test_name}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi

    # 2. Assemble with cross-assembler
    if ! "${CROSS_AS}" "${asm_file}" -o "${obj_file}" >/dev/null 2>&1; then
        echo "  [FAIL] Cross-assembly failed for: ${test_name}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi

    # 3. Link with cross-linker (static ELF)
    if ! "${CROSS_LD}" -static "${obj_file}" -o "${bin_file}" >/dev/null 2>&1; then
        echo "  [FAIL] Static linking failed for: ${test_name}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi

    # 4. Execute under QEMU user emulation
    set +e
    "${QEMU}" "${bin_file}" > "${out_file}" 2>&1
    local actual_exit=$?
    set -e

    if [ "${actual_exit}" -ne "${expected_exit}" ]; then
        echo "  [FAIL] ${test_name}: Expected exit code ${expected_exit}, got ${actual_exit}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi

    if [ -n "${expected_stdout}" ]; then
        local actual_stdout
        actual_stdout="$(cat "${out_file}")"
        if [ "${actual_stdout}" != "${expected_stdout}" ]; then
            echo "  [FAIL] ${test_name}: Expected stdout '${expected_stdout}', got '${actual_stdout}'"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    fi

    echo "  [PASS] ${test_name} (Exit code ${actual_exit})"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
}

# --- Case 1: Arithmetic & Immediate Calculation ---
run_qemu_test "Case 1: Simple Arithmetic (+ 40 2)" "(+ 40 2)" 42

# --- Case 2: Recursive Fibonacci (Branching & Call ABI) ---
run_qemu_test "Case 2: Recursive Fibonacci (fib 10)" '
(define (fib n)
  (if (<= n 1)
      n
      (+ (fib (- n 1)) (fib (- n 2)))))
(fib 10)
' 55

# --- Case 3: Strings & Zero-libc I/O ---
run_qemu_test "Case 3: Strings & write-string stdout" '
(begin
  (write-string "Hello AArch64 Pure Scheme!\n")
  0)
' 0 "Hello AArch64 Pure Scheme!"

# --- Case 4: Higher-Order Closures & Environment Capture ---
run_qemu_test "Case 4: Higher-Order Closures" '
((lambda (x)
   ((lambda (y)
      (+ x y))
    12))
 30)
' 42

# --- Case 5: 100,000 Iteration Tail Call Optimization (TCO) Loop ---
run_qemu_test "Case 5: 100k-iteration TCO Loop" '
(define (loop-test n acc)
  (if (= n 0)
      acc
      (loop-test (- n 1) (+ acc 1))))
(loop-test 100000 42)
' 202

# --- Case 6: Pure Scheme write-char & Newline ---
run_qemu_test "Case 6: write-char primitives" '
(begin
  (write-char #\A)
  (write-char #\A)
  (write-char #\R)
  (write-char #\C)
  (write-char #\H)
  (write-char #\6)
  (write-char #\4)
  (write-char #\newline)
  0)
' 0 "AARCH64"

# --- Case 7: Exception Guard & Raise (Issue #748 TPIDR_EL0 TLS) ---
run_qemu_test "Case 7: Exception Guard & Raise via TLS Handler Chain" '
(guard (ex
        ((eq? ex 99) 42)
        (else 0))
  (+ 10 20)
  (raise 99))
' 42

# --- Case 8: First-Class Continuation call/cc (Issue #748) ---
run_qemu_test "Case 8: First-Class call/cc with Handler State" '
(%raw-call/cc
  (lambda (k)
    (k 42)
    100))
' 42

# --- Case 9: Nested Exception Guard & Handler Chain Isolation (Issue #748) ---
run_qemu_test "Case 9: Nested Exception Guard & Handler Chain Isolation" '
(guard (outer ((eq? outer 999) 0))
  (let ((res (guard (inner ((eq? inner 10) 42))
               (raise 10))))
    res))
' 42

echo "======================================================================="
if [ "${TESTS_FAILED}" -eq 0 ]; then
    echo " ALL ${TESTS_PASSED} AArch64 QEMU Smoke Tests PASSED Successfully!"
    echo "======================================================================="
    exit 0
else
    echo " FAILED: ${TESTS_FAILED} test(s) failed out of $((TESTS_PASSED + TESTS_FAILED))"
    echo "======================================================================="
    exit 1
fi
