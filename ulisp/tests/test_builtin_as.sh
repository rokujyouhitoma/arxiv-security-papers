#!/usr/bin/env bash
# ==============================================================================
# ULisp Built-in Assembler (--as [--64]) & Direct Object (-c / --target-obj) Tests
# Conforms to DSN-33 Architecture Specification & Issue #783
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ULISP_DIR/build/test_builtin_as"
COMPILER="$ULISP_DIR/build/ulisp-modular"

mkdir -p "$BUILD_DIR"

echo "========================================================================"
echo " Starting Built-in Assembler (--as) & Object (-c) Verification Suite (#783)"
echo " Comparing: [GNU as + GNU ld] vs [ulisp --as --64 + GNU ld] vs [ulisp -c + GNU ld]"
echo "========================================================================"

if [ ! -x "$COMPILER" ]; then
    echo "Compiler $COMPILER not found, building..."
    make -C "$ULISP_DIR" build/ulisp-modular
fi

PASS_COUNT=0
TOTAL_COUNT=0

assert_as_and_c() {
    local test_name="$1"
    local expr="$2"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))

    local test_prefix="$BUILD_DIR/test_${TOTAL_COUNT}"
    local src_file="${test_prefix}.scm"
    local s_file="${test_prefix}.s"
    local o_gnu="${test_prefix}_gnu.o"
    local o_as="${test_prefix}_ulisp_as.o"
    local o_c="${test_prefix}_ulisp_c.o"
    local bin_gnu="${test_prefix}_gnu"
    local bin_as="${test_prefix}_ulisp_as"
    local bin_c="${test_prefix}_ulisp_c"

    echo "$expr" > "$src_file"

    # 1. Golden Path: Compile to .s, assemble with GNU as, link with GNU ld
    "$COMPILER" -b x86 "$src_file" -o "$s_file"
    as --64 "$s_file" -o "$o_gnu"
    ld -m elf_x86_64 -static "$o_gnu" -o "$bin_gnu"

    local out_gnu exit_gnu=0
    out_gnu=$(ULISP_PRINT_RESULT=1 "$bin_gnu" 2>&1) || exit_gnu=$?

    # 2. Built-in Assembler Path: ulisp --as --64 input.s -o output.o + GNU ld
    "$COMPILER" --as --64 "$s_file" -o "$o_as"
    if ! readelf -h "$o_as" | grep -q "REL (Relocatable file)"; then
        echo "  [FAIL] $test_name: --as output is not ELF64 ET_REL"
        exit 1
    fi
    ld -m elf_x86_64 -static "$o_as" -o "$bin_as"

    local out_as exit_as=0
    out_as=$(ULISP_PRINT_RESULT=1 "$bin_as" 2>&1) || exit_as=$?

    # 3. Direct Relocatable Object Path: ulisp -c input.scm -o output.o + GNU ld
    "$COMPILER" -c "$src_file" -o "$o_c"
    if ! readelf -h "$o_c" | grep -q "REL (Relocatable file)"; then
        echo "  [FAIL] $test_name: -c output is not ELF64 ET_REL"
        exit 1
    fi
    ld -m elf_x86_64 -static "$o_c" -o "$bin_c"

    local out_c exit_c=0
    out_c=$(ULISP_PRINT_RESULT=1 "$bin_c" 2>&1) || exit_c=$?

    # 4. Assert exact match across all three paths
    if [ "$out_gnu" != "$out_as" ] || [ "$exit_gnu" != "$exit_as" ]; then
        echo "  [FAIL] $test_name (--as mismatch)"
        echo "    Expr: $expr"
        echo "    GNU as+ld   -> exit: $exit_gnu, stdout: '$out_gnu'"
        echo "    ulisp --as  -> exit: $exit_as, stdout: '$out_as'"
        exit 1
    fi
    if [ "$out_gnu" != "$out_c" ] || [ "$exit_gnu" != "$exit_c" ]; then
        echo "  [FAIL] $test_name (-c mismatch)"
        echo "    Expr: $expr"
        echo "    GNU as+ld   -> exit: $exit_gnu, stdout: '$out_gnu'"
        echo "    ulisp -c    -> exit: $exit_c, stdout: '$out_c'"
        exit 1
    fi

    PASS_COUNT=$((PASS_COUNT + 1))
    printf "  \033[32m[PASS]\033[0m %s (exit: %d, out: %s)\n" "$test_name" "$exit_as" "$out_as"
}

echo "--- Test Suite 1: Immediate Values, Branching & Functions ---"
assert_as_and_c "Integer arithmetic" "(+ (* 10 4) (- 5 3))"
assert_as_and_c "Conditional branching" "(if (> 10 5) 42 0)"
assert_as_and_c "Recursive fibonacci(10)" "(define (fib n) (if (<= n 1) n (+ (fib (- n 1)) (fib (- n 2))))) (fib 10)"
assert_as_and_c "Closure make-adder" "(define (make-adder x) (lambda (y) (+ x y))) ((make-adder 10) 32)"
assert_as_and_c "List recursion & strings" "(define *greeting* \"hello\") (string-length *greeting*)"

echo "--- Test Suite 2: Multi-Module Separate Compilation (.init_array, ulisp_globals_sec, .bss) ---"
TOTAL_COUNT=$((TOTAL_COUNT + 1))
MOD_A_SCM="$BUILD_DIR/mod_a.scm"
MOD_B_SCM="$BUILD_DIR/mod_b.scm"
MOD_A_S="$BUILD_DIR/mod_a.s"
MOD_A_O="$BUILD_DIR/mod_a.o"
MOD_B_O="$BUILD_DIR/mod_b.o"
MOD_AB_BIN="$BUILD_DIR/mod_ab"

cat << 'EOF' > "$MOD_A_SCM"
(!allow-extern #t)
(include "compiler/module_header.scm")
(define *shared-offset* 1000)
(define (compute-from-a x)
  (+ *shared-offset* (* x x)))
EOF

cat << 'EOF' > "$MOD_B_SCM"
(!allow-extern #t)
(include "compiler/module_header.scm")
(display (compute-from-a 12))
(newline)
EOF

# Assemble mod_a via --as --64 and compile mod_b directly via -c
"$COMPILER" --module-name mod_a --no-main -I "$ULISP_DIR" "$MOD_A_SCM" -o "$MOD_A_S"
"$COMPILER" --as --64 "$MOD_A_S" -o "$MOD_A_O"
"$COMPILER" -I "$ULISP_DIR" -c "$MOD_B_SCM" -o "$MOD_B_O"

# Verify .rela.init_array and .rela.ulisp_globals_sec exist in mod_a.o
if ! readelf -r "$MOD_A_O" | grep -q "\.rela\.init_array"; then
    echo "  [FAIL] Multi-module: missing .rela.init_array in $MOD_A_O"
    exit 1
fi
if ! readelf -r "$MOD_A_O" | grep -q "\.rela\.ulisp_globals_sec"; then
    echo "  [FAIL] Multi-module: missing .rela.ulisp_globals_sec in $MOD_A_O"
    exit 1
fi

ld -m elf_x86_64 -static "$ULISP_DIR/build/ulisp_stdlib.o" "$MOD_A_O" "$MOD_B_O" -o "$MOD_AB_BIN"
MOD_AB_OUT=$("$MOD_AB_BIN")
if [ "$MOD_AB_OUT" != "1144" ]; then
    echo "  [FAIL] Multi-module execution expected '1144', got '$MOD_AB_OUT'"
    exit 1
fi
PASS_COUNT=$((PASS_COUNT + 1))
printf "  \033[32m[PASS]\033[0m Multi-module separate compilation (--as + -c + ulisp_stdlib.o -> %s)\n" "$MOD_AB_OUT"

echo "========================================================================"
echo " All $PASS_COUNT / $TOTAL_COUNT Built-in Assembler & Object Tests PASSED!"
echo "========================================================================"

