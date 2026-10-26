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
env ULISP_GC_PROFILE=compiler ULISP_QUIET=1 ./build/ulisp-modular < build/test_inc_base.scm > build/test_inc_base.s
gcc -nostdlib -static build/test_inc_base.s -o build/test_inc_base
out=$(./build/test_inc_base)
if [ "$out" != "334" ]; then
    echo "FAIL: Expected 334, got '$out'"
    exit 1
fi
echo "SUCCESS: Base execution verified (334)."

echo "=== [3/4] Touching lir/128_lir_branch_fusion.scm and measuring incremental build time ==="
touch lir/128_lir_branch_fusion.scm

start_ns=$(date +%s%N)
make build/ulisp-modular
end_ns=$(date +%s%N)

duration_ms=$(( (end_ns - start_ns) / 1000000 ))
echo "Incremental build completed in ${duration_ms} ms."

echo "=== [4/4] Verifying functionality of incrementally built binary ==="
cat << 'EOF' > build/test_inc_fib.scm
(define (fib n)
  (if (<= n 1)
      n
      (+ (fib (- n 1)) (fib (- n 2)))))
(fib 10)
EOF
env ULISP_GC_PROFILE=compiler ULISP_QUIET=1 ./build/ulisp-modular < build/test_inc_fib.scm > build/test_inc_fib.s
gcc -nostdlib -static build/test_inc_fib.s -o build/test_inc_fib
out_fib=$(./build/test_inc_fib)
if [ "$out_fib" != "55" ]; then
    echo "FAIL: Expected 55, got '$out_fib'"
    exit 1
fi
echo "SUCCESS: Post-incremental execution verified (fib 10 = 55)."

echo "======================================================================"
echo "SUCCESS: All Modular Separate Compilation & Incremental Build Tests PASSED!"
echo "======================================================================"
