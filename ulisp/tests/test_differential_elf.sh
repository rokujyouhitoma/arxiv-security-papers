#!/usr/bin/env bash
# ==============================================================================
# ULisp Differential Testing: Golden .s (as+ld) vs Direct-to-ELF (--target-elf)
# Conforms to DSN-33 Architecture Specification & Issue #616
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ULISP_DIR/build/diff_elf"
COMPILER="$ULISP_DIR/build/ulisp-modular"

mkdir -p "$BUILD_DIR"

echo "========================================================================"
echo " Starting Differential ELF Verification Test Suite (Issue #616)"
echo " Comparing: [.s + GNU as + GNU ld] vs [--target-elf]"
echo "========================================================================"

if [ ! -x "$COMPILER" ]; then
    echo "Compiler $COMPILER not found, building..."
    make -C "$ULISP_DIR" build/ulisp-modular
fi

PASS_COUNT=0
TOTAL_COUNT=0

assert_diff() {
    local test_name="$1"
    local expr="$2"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))

    local test_prefix="$BUILD_DIR/test_${TOTAL_COUNT}"
    local src_file="${test_prefix}.scm"
    local s_file="${test_prefix}.s"
    local o_file="${test_prefix}.o"
    local bin_as="${test_prefix}_as"
    local bin_elf="${test_prefix}_direct.elf"

    echo "$expr" > "$src_file"

    # 1. Golden Path: Compile to .s, assemble with as, link with ld
    "$COMPILER" -b x86 "$src_file" > "$s_file"
    as --64 "$s_file" -o "$o_file"
    ld -m elf_x86_64 -static "$o_file" -o "$bin_as"

    local out_as exit_as=0
    out_as=$(ULISP_PRINT_RESULT=1 "$bin_as" 2>&1) || exit_as=$?

    # 2. Direct-to-ELF Path: Pass 144 direct ELF generation
    "$COMPILER" --target-elf "$src_file" > "$bin_elf"
    chmod +x "$bin_elf"

    local out_elf exit_elf=0
    out_elf=$(ULISP_PRINT_RESULT=1 "$bin_elf" 2>&1) || exit_elf=$?

    # 3. Assert exact match
    if [ "$out_as" != "$out_elf" ] || [ "$exit_as" != "$exit_elf" ]; then
        echo "  [FAIL] $test_name"
        echo "    Expr: $expr"
        echo "    Golden (as+ld) -> exit: $exit_as, stdout: '$out_as'"
        echo "    Direct (--target-elf) -> exit: $exit_elf, stdout: '$out_elf'"
        exit 1
    fi

    # 4. Verify ELF format and W^X security
    if ! file "$bin_elf" | grep -q "ELF 64-bit"; then
        echo "  [FAIL] $test_name: Output is not a valid ELF 64-bit binary"
        exit 1
    fi

    # Check for W+X (writeable and executable) segment violations
    if readelf -l "$bin_elf" | grep "LOAD" | grep -q "RWE"; then
        echo "  [FAIL] $test_name: W^X violation detected in ELF segment headers (RWE found)"
        exit 1
    fi

    PASS_COUNT=$((PASS_COUNT + 1))
    printf "  \033[32m[PASS]\033[0m %s (exit: %d, out: %s)\n" "$test_name" "$exit_elf" "$out_elf"
}

# ------------------------------------------------------------------------------
# Test Cases
# ------------------------------------------------------------------------------
echo "--- Test Suite 1: Immediate Values & Arithmetic ---"
assert_diff "Integer literal" "42"
assert_diff "Basic arithmetic" "(+ (* 10 4) (- 5 3))"
assert_diff "Negative number & subtraction" "(- 100 (* 25 3))"
assert_diff "Division and remainder" "(/ 84 2)"

echo "--- Test Suite 2: Branching & Conditional Logic ---"
assert_diff "Boolean condition true" "(if (> 10 5) 42 0)"
assert_diff "Boolean condition false" "(if (< 10 5) 0 42)"
assert_diff "Logical and / or" "(if (and #t (or #f #t)) 100 200)"

echo "--- Test Suite 3: Recursive Functions ---"
assert_diff "Recursive fibonacci(10)" "(define (fib n) (if (<= n 1) n (+ (fib (- n 1)) (fib (- n 2))))) (fib 10)"
assert_diff "Recursive factorial(5)" "(define (fact n) (if (<= n 1) 1 (* n (fact (- n 1))))) (fact 5)"

echo "--- Test Suite 4: Closures & High-Order Functions ---"
assert_diff "Closure make-adder" "(define (make-adder x) (lambda (y) (+ x y))) ((make-adder 10) 32)"
assert_diff "Multi-argument lambda" "((lambda (a b c) (+ a (* b c))) 2 4 10)"

echo "--- Test Suite 5: Lists & Data Structures ---"
assert_diff "List recursion sum-list" "(define (sum-list xs acc) (if (null? xs) acc (sum-list (cdr xs) (+ acc (car xs))))) (sum-list '(1 2 3 4 5 6 7 8 9 10) 0)"
assert_diff "List length" "(define (len xs) (if (null? xs) 0 (+ 1 (len (cdr xs))))) (len '(10 20 30 40 50))"

echo "========================================================================"
echo " All $PASS_COUNT / $TOTAL_COUNT Differential Tests PASSED Successfully!"
echo " 100% equivalence verified between .s (as+ld) and --target-elf."
echo "========================================================================"

