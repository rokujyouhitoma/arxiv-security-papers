#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$DIR/.." && pwd)"
export PYTHONPATH="$ROOT_DIR"
cd "$DIR"

if [ -x "$ROOT_DIR/.venv/bin/python" ]; then
    PYTHON_BIN="$ROOT_DIR/.venv/bin/python"
else
    PYTHON_BIN="python3"
fi
ILISP="${ILISP:-$PYTHON_BIN -m ilisp}"
CC="${CC:-gcc}"
CFLAGS="-Wall -Wextra -Werror -O2"

TMP_C="build/tmp_c_test.c"
TMP_BIN="build/tmp_c_bin"
COMPILER="compiler.scm"

mkdir -p build
make compiler

echo "======================================================="
echo " Starting ULisp Portable C Backend Test Suite"
echo " Compiler: $CC ($CFLAGS)"
echo "======================================================="

PASS_COUNT=0
FAIL_COUNT=0

assert_c() {
    local expected="$1"
    local expr="$2"
    local stdin_input="${3:-}"

    # Prepend (!target c) to instruct driver to emit C
    local code="(!target c) $expr"

    printf '%s\n' "$code" | $ILISP "$COMPILER" > "$TMP_C" 2>build/compile_err.log || {
        echo -e "\033[31m[COMPILE FAIL]\033[0m $expr"
        cat build/compile_err.log
        FAIL_COUNT=$((FAIL_COUNT + 1))
        exit 1
    }

    $CC $CFLAGS runtime.c "$TMP_C" -o "$TMP_BIN" 2>build/gcc_err.log || {
        echo -e "\033[31m[GCC BUILD FAIL]\033[0m $expr"
        cat build/gcc_err.log
        FAIL_COUNT=$((FAIL_COUNT + 1))
        exit 1
    }

    local actual
    if [ -n "$stdin_input" ]; then
        actual=$(echo -n "$stdin_input" | "$TMP_BIN")
    else
        actual=$("$TMP_BIN")
    fi

    if [ "$actual" = "$expected" ]; then
        echo -e "  \033[32m[PASS]\033[0m $expr => $actual"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "  \033[31m[FAIL]\033[0m $expr => Expected '$expected', got '$actual'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        exit 1
    fi
}

echo "--- Step 1: Immediate Values & Types ---"
assert_c "42" "42"
assert_c "-10" "-10"
assert_c "#t" "#t"
assert_c "#f" "#f"
assert_c "#\\a" "#\\a"
assert_c "()" "()"

echo "--- Step 2: Arithmetic Operations ---"
assert_c "15" "(+ 10 5)"
assert_c "5" "(- 10 5)"
assert_c "50" "(* 10 5)"
assert_c "2" "(quotient 10 5)"
assert_c "3" "(/ 21 7)"
assert_c "42" "(+ (* 6 7) 0)"

echo "--- Step 3: Conditionals & Logic ---"
assert_c "1" "(if #t 1 2)"
assert_c "2" "(if #f 1 2)"
assert_c "10" "(if (= 5 5) 10 20)"
assert_c "20" "(if (= 5 6) 10 20)"
assert_c "42" "(if (< 2 3) (+ 40 2) (- 100 50))"
assert_c "#t" "(and #t #t)"
assert_c "#f" "(and #t #f)"
assert_c "#t" "(or #f #t)"
assert_c "#f" "(not #t)"

echo "--- Step 4: Local Variables & Closures ---"
assert_c "30" "(let ((x 10) (y 20)) (+ x y))"
assert_c "42" "(let* ((a 1) (b 20) (c (+ a b))) (* c 2))"
assert_c "100" "((lambda (x) (* x x)) 10)"
assert_c "42" "((lambda (f x) (f x)) (lambda (n) (+ n 2)) 40)"

echo "--- Step 5: Data Structures & Pairs ---"
assert_c "(1 . 2)" "(cons 1 2)"
assert_c "(1 2 3)" "(list 1 2 3)"
assert_c "1" "(car (cons 1 2))"
assert_c "2" "(cdr (cons 1 2))"
assert_c "#t" "(pair? (cons 1 2))"
assert_c "#f" "(pair? 42)"
assert_c "#t" "(null? ())"

echo "--- Step 6: Strings ---"
assert_c "5" '(string-length "hello")'
assert_c "0" '(string-length "")'
assert_c '#\h' '(string-ref "hello" 0)'
assert_c '#\o' '(string-ref "hello" 4)'
assert_c '"abc"' '(let ((s (make-string 3))) (begin (string-set! s 0 #\a) (string-set! s 1 #\b) (string-set! s 2 #\c) s))'

echo "--- Step 7: Recursion & Tail Call Optimization ---"
assert_c "55" "(letrec ((fib (lambda (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2))))))) (fib 10))"
assert_c "120" "(letrec ((fact (lambda (n acc) (if (= n 0) acc (fact (- n 1) (* n acc)))))) (fact 5 1))"

echo "--- Step 8: Metacircular Macros ---"
assert_c "42" "(define-macro (when c . body) (list 'if c (cons 'begin body) #f)) (when (= 5 5) 42)"
assert_c "100" "(define-macro (unless c . body) (list 'if c #f (cons 'begin body))) (unless (= 5 6) 100)"
assert_c "81" "(defmacro my-sq (x) (list '* x x)) (my-sq 9)"

rm -f "$TMP_C" "$TMP_BIN"

echo "======================================================="
echo -e "\033[32m All $PASS_COUNT Portable C backend tests PASSED successfully with zero GCC warnings (-Werror)! \033[0m"
echo "======================================================="
