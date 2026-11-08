#!/usr/bin/env bash
# ==============================================================================
# ULisp Incremental Build Verification Test Suite
# Conforms to DSN-33 Architecture Specification & Issue #608
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ULISP_DIR"

echo "=== [1/4] Ensuring build/ulisp-modular is built and up to date ==="
make build/ulisp-modular

echo "=== [2/4] Verifying base functionality of build/ulisp-modular ==="
echo '(+ 100 234)' > build/test_inc_base.scm
env ULISP_GC_PROFILE=compiler ./build/ulisp-modular < build/test_inc_base.scm > build/test_inc_base.s
as --64 build/test_inc_base.s -o build/test_inc_base.o
ld -m elf_x86_64 -static build/test_inc_base.o -o build/test_inc_base
out=$(ULISP_PRINT_RESULT=1 ./build/test_inc_base)
if [ "$out" != "334" ]; then
    echo "FAIL: Expected 334, got '$out'"
    exit 1
fi
echo "SUCCESS: Base execution verified (334)."

echo "=== [3/6] Touching lir/128_lir_branch_fusion.scm and measuring LIR incremental build time ==="
touch lir/128_lir_branch_fusion.scm

start_ns=$(date +%s%N)
make -j"$(nproc 2>/dev/null || echo 4)" build/ulisp-modular
end_ns=$(date +%s%N)

duration_ms=$(( (end_ns - start_ns) / 1000000 ))
echo "LIR incremental build completed in ${duration_ms} ms."
if [ "$duration_ms" -gt 10000 ]; then
    echo "FAIL: LIR incremental build took ${duration_ms} ms (> 10000 ms limit)"
    exit 1
fi

echo "=== [4/6] Touching frontend/050_cp0.scm and measuring Frontend incremental build time ==="
touch frontend/050_cp0.scm

start_ns=$(date +%s%N)
make -j"$(nproc 2>/dev/null || echo 4)" build/ulisp-modular
end_ns=$(date +%s%N)

duration_ms=$(( (end_ns - start_ns) / 1000000 ))
echo "Frontend incremental build completed in ${duration_ms} ms."
if [ "$duration_ms" -gt 10000 ]; then
    echo "FAIL: Frontend incremental build took ${duration_ms} ms (> 10000 ms limit)"
    exit 1
fi

echo "=== [5/6] Touching backend/143_backend_x86_peephole.scm and measuring Backend incremental build time ==="
touch backend/143_backend_x86_peephole.scm

start_ns=$(date +%s%N)
make -j"$(nproc 2>/dev/null || echo 4)" build/ulisp-modular
end_ns=$(date +%s%N)

duration_ms=$(( (end_ns - start_ns) / 1000000 ))
echo "Backend incremental build completed in ${duration_ms} ms."
if [ "$duration_ms" -gt 10000 ]; then
    echo "FAIL: Backend incremental build took ${duration_ms} ms (> 10000 ms limit)"
    exit 1
fi

echo "=== [6/6] Verifying functionality of incrementally built binary ==="
cat << 'EOF' > build/test_inc_fib.scm
(define (fib n)
  (if (<= n 1)
      n
      (+ (fib (- n 1)) (fib (- n 2)))))
(fib 10)
EOF
env ULISP_GC_PROFILE=compiler ./build/ulisp-modular < build/test_inc_fib.scm > build/test_inc_fib.s
as --64 build/test_inc_fib.s -o build/test_inc_fib.o
ld -m elf_x86_64 -static build/test_inc_fib.o -o build/test_inc_fib
out_fib=$(ULISP_PRINT_RESULT=1 ./build/test_inc_fib)
if [ "$out_fib" != "55" ]; then
    echo "FAIL: Expected 55, got '$out_fib'"
    exit 1
fi
echo "SUCCESS: Post-incremental execution verified (fib 10 = 55)."

echo "======================================================================"
echo "SUCCESS: All Modular Separate Compilation & Incremental Build Tests PASSED!"
echo "======================================================================"
