#!/usr/bin/env bash
# ==============================================================================
# ULisp Built-in Static Linker (--ld) Verification Suite
# Conforms to DSN-33 Architecture Specification & Issue #784
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ULISP_DIR/build/test_builtin_ld"
COMPILER="$ULISP_DIR/build/scheme-stage1"

mkdir -p "$BUILD_DIR"

echo "========================================================================"
echo " Starting Built-in Static Linker (--ld) Verification Suite (#784)"
echo " Comparing: GNU ld vs ulisp --ld"
echo "========================================================================"

if [ ! -x "$COMPILER" ]; then
    echo "Compiler $COMPILER not found, building..."
    cd "$ULISP_DIR" && ./bootstrap.sh --quick
fi

PASS_COUNT=0
TOTAL_COUNT=0

assert_ld() {
    local test_name="$1"
    local expr="$2"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))

    local test_prefix="$BUILD_DIR/test_${TOTAL_COUNT}"
    local src_file="${test_prefix}.scm"
    local o_file="${test_prefix}.o"
    local bin_gnu="${test_prefix}_gnu"
    local bin_ld="${test_prefix}_builtin_ld"

    echo "$expr" > "$src_file"

    # 1. Compile to relocatable object (.o)
    "$COMPILER" -c "$src_file" -o "$o_file"

    # 2. Golden Path: Link with GNU ld
    ld -m elf_x86_64 -static "$o_file" -o "$bin_gnu"
    local out_gnu exit_gnu=0
    out_gnu=$(ULISP_PRINT_RESULT=1 "$bin_gnu" 2>&1) || exit_gnu=$?

    # 3. Built-in Linker Path: ulisp --ld input.o -o output
    "$COMPILER" --ld "$o_file" -o "$bin_ld"
    if ! readelf -h "$bin_ld" | grep -q "EXEC (Executable file)"; then
        echo "  [FAIL] $test_name: --ld output is not ELF64 ET_EXEC"
        exit 1
    fi

    # Verify W^X and non-executable stack
    if ! readelf -l "$bin_ld" | grep -q "GNU_STACK"; then
        echo "  [FAIL] $test_name: missing GNU_STACK program header"
        exit 1
    fi
    if readelf -l "$bin_ld" | grep "GNU_STACK" | grep -q "E"; then
        echo "  [FAIL] $test_name: GNU_STACK must not be executable (W^X violation)"
        exit 1
    fi

    local out_ld exit_ld=0
    out_ld=$(ULISP_PRINT_RESULT=1 "$bin_ld" 2>&1) || exit_ld=$?

    # 4. Assert exact match between GNU ld and ulisp --ld
    if [ "$out_gnu" != "$out_ld" ] || [ "$exit_gnu" != "$exit_ld" ]; then
        echo "  [FAIL] $test_name (output mismatch)"
        echo "    Expr: $expr"
        echo "    GNU ld    -> exit: $exit_gnu, stdout: '$out_gnu'"
        echo "    ulisp --ld -> exit: $exit_ld, stdout: '$out_ld'"
        exit 1
    fi

    PASS_COUNT=$((PASS_COUNT + 1))
    printf "  \033[32m[PASS]\033[0m %s (exit: %d, out: %s)\n" "$test_name" "$exit_ld" "$out_ld"
}

echo "--- Test Suite 1: Single Object Executables ---"
assert_ld "Integer arithmetic" "(+ (* 10 4) (- 5 3))"
assert_ld "Conditional branching" "(if (> 10 5) 42 0)"
assert_ld "Recursive fibonacci(10)" "(define (fib n) (if (<= n 1) n (+ (fib (- n 1)) (fib (- n 2))))) (fib 10)"
assert_ld "Closure make-adder" "(define (make-adder x) (lambda (y) (+ x y))) ((make-adder 10) 32)"

echo "--- Test Suite 2: 2-Split Build with ulisp_stdlib.o ---"
TOTAL_COUNT=$((TOTAL_COUNT + 1))
SPLIT_SCM="$BUILD_DIR/split_test.scm"
SPLIT_O="$BUILD_DIR/split_test.o"
SPLIT_GNU="$BUILD_DIR/split_gnu"
SPLIT_LD="$BUILD_DIR/split_builtin_ld"

cat << 'EOF' > "$SPLIT_SCM"
(include "ulisp/lib/stdlib_macros.scm")
(display "Hello from 2-split builtin ld!\n")
(display (+ 100 234))
(newline)
EOF

"$COMPILER" -I "$ULISP_DIR" -c "$SPLIT_SCM" -o "$SPLIT_O" --allow-extern

# Link with GNU ld
ld -m elf_x86_64 -static "$SPLIT_O" "$ULISP_DIR/build/ulisp_stdlib.o" -o "$SPLIT_GNU"
SPLIT_GNU_OUT=$("$SPLIT_GNU")

# Link with ulisp --ld
"$COMPILER" --ld "$SPLIT_O" "$ULISP_DIR/build/ulisp_stdlib.o" -o "$SPLIT_LD"
SPLIT_LD_OUT=$("$SPLIT_LD")

if [ "$SPLIT_GNU_OUT" != "$SPLIT_LD_OUT" ]; then
    echo "  [FAIL] 2-Split build output mismatch:"
    echo "    GNU ld   : '$SPLIT_GNU_OUT'"
    echo "    ulisp --ld: '$SPLIT_LD_OUT'"
    exit 1
fi
PASS_COUNT=$((PASS_COUNT + 1))
printf "  \033[32m[PASS]\033[0m 2-Split build with ulisp_stdlib.o\n"

echo "--- Test Suite 3: Pure Builtin Pipeline (--as + -c + --ld) ---"
TOTAL_COUNT=$((TOTAL_COUNT + 1))
ASM_S="$BUILD_DIR/math_helper.s"
ASM_O="$BUILD_DIR/math_helper.o"
CALLER_SCM="$BUILD_DIR/caller.scm"
CALLER_O="$BUILD_DIR/caller.o"
PIPELINE_BIN="$BUILD_DIR/pipeline_bin"

cat << 'EOF' > "$ASM_S"
    .intel_syntax noprefix
    .text
    .globl ulisp_fn_square_add
    .type ulisp_fn_square_add, @function
ulisp_fn_square_add:
    # rdi = a (tagged fixnum, a << 2)
    # rsi = b (tagged fixnum, b << 2)
    sar rdi, 2
    sar rsi, 2
    imul rdi, rdi
    add rdi, rsi
    shl rdi, 2
    mov rax, rdi
    ret
EOF

cat << 'EOF' > "$CALLER_SCM"
(include "ulisp/lib/stdlib_macros.scm")
(!allow-extern #t)
(display (square_add 6 6))
(newline)
EOF

"$COMPILER" --as "$ASM_S" -o "$ASM_O"
"$COMPILER" -I "$ULISP_DIR" -c "$CALLER_SCM" -o "$CALLER_O" --allow-extern
"$COMPILER" --ld "$ASM_O" "$CALLER_O" "$ULISP_DIR/build/ulisp_stdlib.o" -o "$PIPELINE_BIN"

PIPELINE_OUT=$("$PIPELINE_BIN")
if [ "$PIPELINE_OUT" != "42" ]; then
    echo "  [FAIL] Pure builtin pipeline expected '42', got '$PIPELINE_OUT'"
    exit 1
fi
PASS_COUNT=$((PASS_COUNT + 1))
printf "  \033[32m[PASS]\033[0m Pure builtin pipeline (--as + -c + --ld -> %s)\n" "$PIPELINE_OUT"

echo "--- Test Suite 4: Multi-Module Separate Compilation ---"
TOTAL_COUNT=$((TOTAL_COUNT + 1))
MOD_A_SCM="$BUILD_DIR/mod_a.scm"
MOD_B_SCM="$BUILD_DIR/mod_b.scm"
MOD_A_O="$BUILD_DIR/mod_a.o"
MOD_B_O="$BUILD_DIR/mod_b.o"
MOD_AB_BIN="$BUILD_DIR/mod_ab_builtin"

cat << 'EOF' > "$MOD_A_SCM"
(!allow-extern #t)
(include "compiler/module_header.scm")
(define *shared-offset* 2000)
(define (compute-from-a x)
  (+ *shared-offset* (* x x)))
EOF

cat << 'EOF' > "$MOD_B_SCM"
(!allow-extern #t)
(include "compiler/module_header.scm")
(display (compute-from-a 10))
(newline)
EOF

"$COMPILER" --module-name mod_a --no-main -I "$ULISP_DIR" -c "$MOD_A_SCM" -o "$MOD_A_O"
"$COMPILER" -I "$ULISP_DIR" -c "$MOD_B_SCM" -o "$MOD_B_O"
"$COMPILER" --ld "$ULISP_DIR/build/ulisp_stdlib.o" "$MOD_A_O" "$MOD_B_O" -o "$MOD_AB_BIN"

MOD_AB_OUT=$("$MOD_AB_BIN")
if [ "$MOD_AB_OUT" != "2100" ]; then
    echo "  [FAIL] Multi-module execution expected '2100', got '$MOD_AB_OUT'"
    exit 1
fi
PASS_COUNT=$((PASS_COUNT + 1))
printf "  \033[32m[PASS]\033[0m Multi-module separate compilation (mod_a.o + mod_b.o + ulisp_stdlib.o -> %s)\n" "$MOD_AB_OUT"

echo "--- Test Suite 5: Error Handling (Diagnostics) ---"
TOTAL_COUNT=$((TOTAL_COUNT + 1))
# Undefined symbol error check
UNDEF_SCM="$BUILD_DIR/undef.scm"
UNDEF_O="$BUILD_DIR/undef.o"
echo '(!allow-extern #t) (non_existent_func 1 2 3)' > "$UNDEF_SCM"
"$COMPILER" -c "$UNDEF_SCM" -o "$UNDEF_O"

set +e
UNDEF_ERR=$("$COMPILER" --ld "$UNDEF_O" -o "$BUILD_DIR/undef.bin" 2>&1)
UNDEF_CODE=$?
set -e

if [ $UNDEF_CODE -eq 0 ]; then
    echo "  [FAIL] Undefined reference did not exit non-zero"
    exit 1
fi
if ! echo "$UNDEF_ERR" | grep -q "undefined reference to \`ulisp_fn_non_existent_func\`"; then
    echo "  [FAIL] Missing expected diagnostic message for undefined symbol. Got:"
    echo "$UNDEF_ERR"
    exit 1
fi
PASS_COUNT=$((PASS_COUNT + 1))
printf "  \033[32m[PASS]\033[0m Undefined reference detection & diagnostic reporting\n"

TOTAL_COUNT=$((TOTAL_COUNT + 1))
# Duplicate global symbol error check
DUP1_S="$BUILD_DIR/dup1.s"
DUP2_S="$BUILD_DIR/dup2.s"
DUP1_O="$BUILD_DIR/dup1.o"
DUP2_O="$BUILD_DIR/dup2.o"

cat << 'EOF' > "$DUP1_S"
.globl _start
_start:
    ret
.globl my_duplicate_sym
my_duplicate_sym:
    ret
EOF

cat << 'EOF' > "$DUP2_S"
.globl my_duplicate_sym
my_duplicate_sym:
    ret
EOF
"$COMPILER" --as "$DUP1_S" -o "$DUP1_O"
"$COMPILER" --as "$DUP2_S" -o "$DUP2_O"

set +e
DUP_ERR=$("$COMPILER" --ld "$DUP1_O" "$DUP2_O" -o "$BUILD_DIR/dup.bin" 2>&1)
DUP_CODE=$?
set -e

if [ $DUP_CODE -eq 0 ]; then
    echo "  [FAIL] Duplicate global symbol did not exit non-zero"
    exit 1
fi
if ! echo "$DUP_ERR" | grep -q "multiple definition of \`my_duplicate_sym\`"; then
    echo "  [FAIL] Missing expected diagnostic message for multiple definitions. Got:"
    echo "$DUP_ERR"
    exit 1
fi
PASS_COUNT=$((PASS_COUNT + 1))
printf "  \033[32m[PASS]\033[0m Multiple definition detection & diagnostic reporting\n"

echo "========================================================================"
echo " All $PASS_COUNT / $TOTAL_COUNT Built-in Static Linker Tests PASSED!"
echo "========================================================================"
