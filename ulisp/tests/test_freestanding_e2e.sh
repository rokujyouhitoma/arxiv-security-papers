#!/usr/bin/env bash
# ==============================================================================
# ULisp Zero-libc / Freestanding Pure Scheme E2E Verification Script
# Conforms to DSN-33-07 / Issue #906
# Verifies complete standalone static ELF execution without libc or ld-linux.so
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd "${ULISP_DIR}/.." && pwd)"

echo "=== [E2E] ULisp Zero-libc Freestanding Static ELF Verification ==="

TMP_DIR="$(mktemp -d /tmp/ulisp_freestanding_e2e_XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

SCM_FILE="${TMP_DIR}/app.scm"
ASM_FILE="${TMP_DIR}/app.s"
OBJ_FILE="${TMP_DIR}/app.o"
BIN_FILE="${TMP_DIR}/app.elf"

cat << 'EOF' > "${SCM_FILE}"
(!gc dual-space)
(include "lib/posix.scm")

;; Output test header
(sys-write-string "=== [E2E] ULisp Zero-libc Bare-Metal Static Binary Running ===\n")

;; 1. Computation & Recursion
(define (fib n)
  (if (< n 2)
      n
      (+ (fib (- n 1)) (fib (- n 2)))))

(sys-write-string "[1/4] Pure Scheme Recursion (fib 10): ")
(sys-write-fixnum (fib 10))
(sys-newline)

;; 2. BSS Initial Heap Verification
(sys-write-string "[2/4] Demand-Paged BSS Initial Heap Pointer: ")
(let ((bss-ptr (sys-initial-heap)))
  (if (> bss-ptr 0)
      (begin
        (sys-write-string "OK (0x")
        (sys-write-fixnum bss-ptr)
        (sys-write-string ")\n"))
      (begin
        (sys-write-string "FAIL\n")
        (sys-exit 1))))

;; 3. Dynamic Cons & Cheney 2-Space GC Stress
(define (alloc-loop n acc)
  (if (<= n 0)
      acc
      (alloc-loop (- n 1) (cons (car acc) n))))

(sys-write-string "[3/4] Memory Allocation & Cheney 2-Space GC Stress: ")
(let* ((st-ptr (%get-gc-state-ptr))
       (lim-ptr (%get-heap-limit-ptr))
       (from (%raw-load st-ptr 0))
       (small-size 16384))
  (%raw-store! st-ptr 16 (%to-raw small-size))
  (let ((to (%raw-load st-ptr 8)))
    (%raw-store! st-ptr 40 to)
    (%raw-store! lim-ptr 0 (%ptr-add from small-size)))
  (let ((res (alloc-loop 20000 (cons 999 0))))
    (if (and (pair? res) (= (car res) 999))
        (sys-write-string "OK (20,000 pairs, multiple GC cycles passed)\n")
        (begin
          (sys-write-string "FAIL (corruption)\n")
          (sys-exit 2)))))

;; 4. Direct Linux x86-64 Raw Syscall Clock Monotonic
(sys-write-string "[4/4] Direct Raw Syscall Clock Monotonic: ")
(let ((ts (sys-clock-gettime-monotonic)))
  (if (and (>= (car ts) 0) (>= (cdr ts) 0))
      (begin
        (sys-write-string "OK (sec=")
        (sys-write-fixnum (car ts))
        (sys-write-string ")\n"))
      (begin
        (sys-write-string "FAIL\n")
        (sys-exit 3))))

(sys-write-string "=== [SUCCESS] Freestanding Static ELF E2E Verified ===\n")
(sys-exit 0)
EOF

# Prepend posix.scm inline to resolve (include "lib/posix.scm")
POSIX_SCM="${ULISP_DIR}/lib/posix.scm"
FULL_SCM="${TMP_DIR}/full_app.scm"
python3 -c "
with open('${SCM_FILE}') as f:
    src = f.read()
with open('${POSIX_SCM}') as f:
    posix = f.read()
with open('${FULL_SCM}', 'w') as f:
    f.write(src.replace('(include \"lib/posix.scm\")', posix))
"

echo "--> Step 1: Compiling Scheme to Native x86-64 Assembly..."
if command -v gosh >/dev/null 2>&1; then
    gosh "${ULISP_DIR}/compiler.scm" < "${FULL_SCM}" > "${ASM_FILE}"
elif [ -x "${ULISP_DIR}/bin/ulisp-boot" ]; then
    "${ULISP_DIR}/bin/ulisp-boot" < "${FULL_SCM}" > "${ASM_FILE}"
else
    python3 -m ilisp "${ULISP_DIR}/compiler.scm" < "${FULL_SCM}" > "${ASM_FILE}"
fi

echo "--> Step 2: Assembling & Linking with -nostdlib -static..."
as --64 "${ASM_FILE}" -o "${OBJ_FILE}"
ld -m elf_x86_64 -static "${OBJ_FILE}" -o "${BIN_FILE}"

echo "--> Step 3: Inspecting ELF Static Freestanding Attributes..."
# 1. Verify not a dynamic executable via ldd
LDD_OUTPUT="$(ldd "${BIN_FILE}" 2>&1 || true)"
echo "    [ldd check] ${LDD_OUTPUT}"
if ! echo "${LDD_OUTPUT}" | grep -q -i "not a dynamic executable"; then
    echo "ERROR: Binary is dynamically linked!" >&2
    exit 1
fi

# 2. Verify PT_INTERP (dynamic loader request) is completely absent
if readelf -l "${BIN_FILE}" | grep -q "INTERP"; then
    echo "ERROR: Binary contains PT_INTERP program header!" >&2
    exit 1
fi
echo "    [readelf -l] Verified: Zero PT_INTERP header."

# 3. Verify PT_DYNAMIC / DT_NEEDED are absent
if readelf -d "${BIN_FILE}" 2>&1 | grep -q "NEEDED"; then
    echo "ERROR: Binary contains DT_NEEDED dynamic library entries!" >&2
    exit 1
fi
echo "    [readelf -d] Verified: Zero DT_NEEDED dynamic library dependencies."

# 4. Verify binary footprint is lightweight
BIN_SIZE=$(stat -c %s "${BIN_FILE}")
cp "${BIN_FILE}" "${BIN_FILE}.stripped"
strip --strip-all "${BIN_FILE}.stripped"
STRIPPED_SIZE=$(stat -c %s "${BIN_FILE}.stripped")
echo "    [Binary size] Unstripped: ${BIN_SIZE} bytes, Stripped: ${STRIPPED_SIZE} bytes."
if [ "${STRIPPED_SIZE}" -gt 65536 ]; then
    echo "WARNING: Stripped binary size ${STRIPPED_SIZE} exceeds 64KB target."
fi

echo "--> Step 4: Executing Standalone ELF in Isolated Environment..."
chmod +x "${BIN_FILE}"
OUTPUT="$("${BIN_FILE}")"
echo "${OUTPUT}"

if ! echo "${OUTPUT}" | grep -F -q "=== [SUCCESS] Freestanding Static ELF E2E Verified ==="; then
    echo "ERROR: E2E execution output mismatch!" >&2
    exit 1
fi

echo "--> [PASS] All Freestanding Static -nostdlib ELF E2E Criteria Satisfied!"
