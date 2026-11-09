#!/usr/bin/env bash
# ==============================================================================
# ULisp 1-Step Executable Compilation Verification Suite
# Issue #786: Support one-step executable compilation with automatic stdlib linking
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ULISP_DIR/build/test_onestep_compile"
COMPILER="${ULISP_COMPILER:-$ULISP_DIR/build/scheme-stage1}"

if [ ! -x "$COMPILER" ]; then
    if [ -x "$ULISP_DIR/bin/ulisp-boot" ]; then
        COMPILER="$ULISP_DIR/bin/ulisp-boot"
    else
        echo "Error: compiler executable not found at $COMPILER or $ULISP_DIR/bin/ulisp-boot" >&2
        exit 1
    fi
fi

mkdir -p "$BUILD_DIR"

echo "========================================================================"
echo " Starting 1-Step Executable Compilation Verification Suite (#786)"
echo " Compiler: $COMPILER"
echo "========================================================================"

PASS_COUNT=0
TOTAL_COUNT=0

assert_success() {
    local test_name="$1"
    local cmd="$2"
    local expected_output="$3"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))

    echo -n "Test $TOTAL_COUNT: $test_name ... "
    local out
    if ! out=$(eval "$cmd" 2>&1); then
        echo "FAIL (Command exited with error)"
        echo "  Command: $cmd"
        echo "  Output:  $out"
        exit 1
    fi

    if [ -n "$expected_output" ] && [ "$out" != "$expected_output" ]; then
        echo "FAIL (Output mismatch)"
        echo "  Command:  $cmd"
        echo "  Expected: $expected_output"
        echo "  Actual:   $out"
        exit 1
    fi

    echo "PASS"
    PASS_COUNT=$((PASS_COUNT + 1))
}

assert_failure_cleanup() {
    local test_name="$1"
    local cmd="$2"
    local target_bin="$3"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))

    echo -n "Test $TOTAL_COUNT: $test_name ... "
    rm -f "$target_bin"
    if eval "$cmd" >/dev/null 2>&1; then
        echo "FAIL (Expected command to fail, but it succeeded)"
        echo "  Command: $cmd"
        exit 1
    fi

    if [ -e "$target_bin" ]; then
        echo "FAIL (Lingering binary detected on error: $target_bin)"
        exit 1
    fi

    echo "PASS"
    PASS_COUNT=$((PASS_COUNT + 1))
}

# ------------------------------------------------------------------------------
# Test 1: Inline 1-step compile & run with display / newline (prelude + stdlib)
# ------------------------------------------------------------------------------
BIN1="$BUILD_DIR/test1.bin"
assert_success "Inline expression 1-step compilation and execution" \
    "\"$COMPILER\" -e '(begin (display \"hello, world\") (newline))' -o \"$BIN1\" && \"$BIN1\"" \
    "hello, world"

# Verify ELF header & security properties of BIN1
TOTAL_COUNT=$((TOTAL_COUNT + 1))
echo -n "Test $TOTAL_COUNT: BIN1 is ELF64 ET_EXEC with PT_GNU_STACK ... "
if ! readelf -h "$BIN1" | grep -q "EXEC (Executable file)"; then
    echo "FAIL (Not an ELF executable)"
    exit 1
fi
if ! readelf -l "$BIN1" | grep -q "GNU_STACK"; then
    echo "FAIL (Missing PT_GNU_STACK)"
    exit 1
fi
echo "PASS"
PASS_COUNT=$((PASS_COUNT + 1))

# ------------------------------------------------------------------------------
# Test 2: Arithmetic and loop with stdlib procedures (write, display)
# ------------------------------------------------------------------------------
BIN2="$BUILD_DIR/test2.bin"
assert_success "Loop and arithmetic 1-step compilation" \
    "\"$COMPILER\" -e '(let loop ((n 5)) (if (> n 0) (begin (write n) (display \" \") (loop (- n 1))) (newline)))' -o \"$BIN2\" && \"$BIN2\"" \
    "5 4 3 2 1 "

# ------------------------------------------------------------------------------
# Test 3: Scheme file input 1-step compile & run
# ------------------------------------------------------------------------------
SRC3="$BUILD_DIR/test3.scm"
BIN3="$BUILD_DIR/test3.bin"
cat << 'EOF' > "$SRC3"
(define (fact n)
  (if (<= n 1)
      1
      (* n (fact (- n 1)))))

(display "fact(6) = ")
(write (fact 6))
(newline)
EOF
assert_success "Scheme source file 1-step compilation" \
    "\"$COMPILER\" \"$SRC3\" -o \"$BIN3\" && \"$BIN3\"" \
    "fact(6) = 720"

# ------------------------------------------------------------------------------
# Test 4: Separate compilation with -c outputs .o (ET_REL) without linking
# ------------------------------------------------------------------------------
OBJ4="$BUILD_DIR/test4.o"
assert_success "-c option outputs ET_REL relocatable object" \
    "\"$COMPILER\" -c -e '(display \"from obj\n\")' -o \"$OBJ4\" && readelf -h \"$OBJ4\" | grep -q 'REL (Relocatable file)'" \
    ""

# Verify that linking OBJ4 with built-in ld produces runnable binary
BIN4="$BUILD_DIR/test4.bin"
STDLIB_OBJ="$ULISP_DIR/build/ulisp_stdlib.o"
assert_success "Built-in ld links object created by -c with stdlib" \
    "\"$COMPILER\" --ld \"$OBJ4\" \"$STDLIB_OBJ\" -o \"$BIN4\" && \"$BIN4\"" \
    "from obj"

# ------------------------------------------------------------------------------
# Test 5: Assembly output with -S outputs assembly text
# ------------------------------------------------------------------------------
ASM5="$BUILD_DIR/test5.s"
assert_success "-S option outputs assembly text" \
    "\"$COMPILER\" -S -e '(+ 1 2)' -o \"$ASM5\" && grep -q '_start:' \"$ASM5\"" \
    ""

# ------------------------------------------------------------------------------
# Test 6: --nostdlib disables prelude and stdlib linking
# ------------------------------------------------------------------------------
BIN6_FAIL="$BUILD_DIR/test6_fail.bin"
assert_failure_cleanup "--nostdlib rejects stdlib display as unbound" \
    "\"$COMPILER\" --nostdlib -e '(display \"hello\")' -o \"$BIN6_FAIL\"" \
    "$BIN6_FAIL"

BIN6_PASS="$BUILD_DIR/test6_pass.bin"
assert_success "--nostdlib allows freestanding arithmetic" \
    "\"$COMPILER\" --nostdlib -e '(+ 10 20)' -o \"$BIN6_PASS\" && ULISP_PRINT_RESULT=1 \"$BIN6_PASS\"" \
    "30"

# ------------------------------------------------------------------------------
# Test 7: Rollback / unlink on compilation error (Issue #785)
# ------------------------------------------------------------------------------
BIN7_UNBOUND="$BUILD_DIR/test7_unbound.bin"
assert_failure_cleanup "Unbound variable error leaves no output binary behind" \
    "\"$COMPILER\" -e '(undeclared-symbol-test 1 2)' -o \"$BIN7_UNBOUND\"" \
    "$BIN7_UNBOUND"

BIN7_SYNTAX="$BUILD_DIR/test7_syntax.bin"
assert_failure_cleanup "Syntax error leaves no output binary behind" \
    "\"$COMPILER\" -e '(if 1)' -o \"$BIN7_SYNTAX\"" \
    "$BIN7_SYNTAX"

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo "========================================================================"
echo " 1-Step Compilation Test Suite Complete: $PASS_COUNT / $TOTAL_COUNT PASS"
echo "========================================================================"
exit 0
