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
OS_NAME="$(uname -s)"
if [ "$OS_NAME" = "Darwin" ]; then
    CC="${CC:-clang}"
else
    CC="${CC:-gcc}"
fi
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

    # Prepend (!target c) and optional stdlib
    local code
    if [[ "$expr" =~ bytevector || "$expr" =~ utf8 ]]; then
        code="(!target c)"$'\n'"$(cat lib/string.scm lib/bytevector.scm)"$'\n'"$expr"
    elif [[ "$expr" =~ delay || "$expr" =~ force || "$expr" =~ promise ]]; then
        code="(!target c)"$'\n'"$(cat lib/string.scm lib/vector.scm lib/promise.scm)"$'\n'"$expr"
    elif [[ "$expr" =~ define-record-type || "$expr" =~ vector ]]; then
        code="(!target c)"$'\n'"$(cat lib/string.scm lib/vector.scm)"$'\n'"$expr"
    elif [[ "$expr" =~ parameter || "$expr" =~ dynamic-wind ]]; then
        code="(!target c)"$'\n'"$(cat lib/string.scm lib/continuation.scm lib/parameter.scm)"$'\n'"$expr"
    elif [[ "$expr" =~ list-copy || "$expr" =~ make-list ]]; then
        code="(!target c)"$'\n'"$(cat lib/list.scm)"$'\n'"$expr"
    elif [[ "$expr" =~ string-copy || "$expr" =~ string-fill || "$expr" =~ string-map || "$expr" =~ string-for-each || "$expr" =~ string-\>list || "$expr" =~ list-\>string || "$expr" =~ "string<" || "$expr" =~ "string>" || "$expr" =~ "string=" ]]; then
        code="(!target c)"$'\n'"$(cat lib/string.scm)"$'\n'"$expr"
    else
        code="(!target c) $expr"
    fi


    if [ -x "bin/ulisp-boot" ]; then
        printf '%s\n' "$code" > build/tmp_c_in.scm
        ULISP_QUIET=1 bin/ulisp-boot build/tmp_c_in.scm > "$TMP_C" 2>build/compile_err.log || {
            echo -e "\033[31m[COMPILE FAIL]\033[0m $expr"
            cat build/compile_err.log
            FAIL_COUNT=$((FAIL_COUNT + 1))
            exit 1
        }
    else
        printf '%s\n' "$code" | $ILISP "$COMPILER" > "$TMP_C" 2>build/compile_err.log || {
            echo -e "\033[31m[COMPILE FAIL]\033[0m $expr"
            cat build/compile_err.log
            FAIL_COUNT=$((FAIL_COUNT + 1))
            exit 1
        }
    fi

    $CC $CFLAGS "$TMP_C" -o "$TMP_BIN" 2>build/gcc_err.log || {
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

run_test_file_c() {
    local test_file="$1"
    local stdlib="$2"
    local desc="$3"

    local in_file="build/tmp_file_c_in.scm"
    local out_c="build/tmp_file_c.c"
    local out_bin="build/tmp_file_c_bin"

    echo "(!target c)" > "$in_file"
    for f in $stdlib "$test_file"; do
        cat "$f" >> "$in_file"
    done
    if [ -x "bin/ulisp-boot" ]; then
        ULISP_QUIET=1 bin/ulisp-boot "$in_file" > "$out_c" 2>build/compile_err.log || {
            echo -e "\033[31m[COMPILE FAIL]\033[0m $test_file"
            cat build/compile_err.log
            FAIL_COUNT=$((FAIL_COUNT + 1))
            exit 1
        }
    else
        printf '%s\n' "$(cat "$in_file")" | $ILISP "$COMPILER" > "$out_c" 2>build/compile_err.log || {
            echo -e "\033[31m[COMPILE FAIL]\033[0m $test_file"
            cat build/compile_err.log
            FAIL_COUNT=$((FAIL_COUNT + 1))
            exit 1
        }
    fi

    $CC $CFLAGS "$out_c" -o "$out_bin" 2>build/gcc_err.log || {
        echo -e "\033[31m[GCC BUILD FAIL]\033[0m $test_file"
        cat build/gcc_err.log
        FAIL_COUNT=$((FAIL_COUNT + 1))
        exit 1
    }

    local actual
    actual=$("./$out_bin" 2>build/run_err.log | tail -n 1)
    if [ "$actual" = "#t" ]; then
        echo -e "  \033[32m[PASS]\033[0m $desc ($test_file) => #t"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "  \033[31m[FAIL]\033[0m $desc ($test_file) failed (got: '$actual')"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        exit 1
    fi
    rm -f "$in_file" "$out_c" "$out_bin"
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

echo "--- Step 8: Hygienic syntax-rules Macros ---"
assert_c "42" "(define-syntax when (syntax-rules () ((_ c body ...) (if c (begin body ...) #f)))) (when (= 5 5) 42)"
assert_c "100" "(define-syntax unless (syntax-rules () ((_ c body ...) (if c #f (begin body ...))))) (unless (= 5 6) 100)"
assert_c "81" "(define-syntax my-sq (syntax-rules () ((_ x) (* x x)))) (my-sq 9)"

echo "--- Step 9: R7RS Bytevectors for Binary Security ---"
assert_c "#t" "(bytevector? (make-bytevector 5))"
assert_c "#f" '(bytevector? "hello")'
assert_c "#f" "(bytevector? 123)"
assert_c "10" "(bytevector-length (make-bytevector 10))"
assert_c "0" "(bytevector-length (make-bytevector 0))"
assert_c "#u8(0 0 0)" "(make-bytevector 3)"
assert_c "#u8(42 42 42)" "(make-bytevector 3 42)"
assert_c "66" "(let ((bv (make-bytevector 3))) (begin (bytevector-u8-set! bv 0 65) (bytevector-u8-set! bv 1 66) (bytevector-u8-set! bv 2 67) (bytevector-u8-ref bv 1)))"
assert_c "#u8(65 66 67)" "(let ((bv (make-bytevector 3))) (begin (bytevector-u8-set! bv 0 65) (bytevector-u8-set! bv 1 66) (bytevector-u8-set! bv 2 67) bv))"
assert_c "#u8(1 2 3)" "(bytevector 1 2 3)"
assert_c "#u8(10 20 30)" "(bytevector-copy (bytevector 10 20 30))"
assert_c "#u8(20 30)" "(bytevector-copy (bytevector 10 20 30 40) 1 3)"
assert_c "#t" "(bytevector=? (bytevector 1 2 3) (bytevector 1 2 3))"
assert_c "#f" "(bytevector=? (bytevector 1 2 3) (bytevector 1 2 4))"
assert_c "#f" "(bytevector=? (bytevector 1 2) (bytevector 1 2 3))"
assert_c "#u8(1 2 3 4 5)" "(bytevector-append (bytevector 1 2) (bytevector 3 4 5))"
assert_c "#u8(0 1 2 3 0)" "(let ((to (make-bytevector 5 0)) (from (bytevector 1 2 3))) (begin (bytevector-copy! to 1 from) to))"
assert_c "#u8(65 66 67)" '(string->utf8 "ABC")'
assert_c '"Hello"' "(utf8->string (bytevector 72 101 108 108 111))"
assert_c "5" "(bytevector-length (bytevector 0 1 0 2 0))"
assert_c "0" "(bytevector-u8-ref (bytevector 0 1 0 2 0) 2)"

echo "--- Step 10: R7RS Vectors ---"
assert_c "#t" "(vector? (make-vector 5))"
assert_c "#f" '(vector? "hello")'
assert_c "#f" "(vector? '(1 2 3))"
assert_c "#f" "(vector? 123)"
assert_c "10" "(vector-length (make-vector 10))"
assert_c "0" "(vector-length (make-vector 0))"
assert_c "#(#f #f #f)" "(make-vector 3)"
assert_c "#(42 42 42)" "(make-vector 3 42)"
assert_c "20" "(let ((v (make-vector 3))) (begin (vector-set! v 0 10) (vector-set! v 1 20) (vector-set! v 2 30) (vector-ref v 1)))"
assert_c "#(10 20 30)" "(let ((v (make-vector 3))) (begin (vector-set! v 0 10) (vector-set! v 1 20) (vector-set! v 2 30) v))"
assert_c "#(1 2 3)" "(vector 1 2 3)"
assert_c "#(10 20 30)" "(vector-copy (vector 10 20 30))"
assert_c "#(20 30)" "(vector-copy (vector 10 20 30 40) 1 3)"
assert_c "#(9 9 9)" "(let ((v (make-vector 3))) (begin (vector-fill! v 9) v))"
assert_c "#(1 2 3 4 5)" "(vector-append (vector 1 2) (vector 3 4 5))"
assert_c "#(0 1 2 3 0)" "(let ((to (make-vector 5 0)) (from (vector 1 2 3))) (begin (vector-copy! to 1 from) to))"
assert_c "(1 2 3)" "(vector->list (vector 1 2 3))"
assert_c "(2 3)" "(vector->list (vector 1 2 3 4) 1 3)"
assert_c "#(1 2 3)" "(list->vector '(1 2 3))"
assert_c "#(1 #(2 3) 4)" "(vector 1 (vector 2 3) 4)"
assert_c "2" "(vector-ref (vector-ref (vector 1 (vector 2 3) 4) 1) 0)"
assert_c "(#\\h #\\e #\\l #\\l #\\o)" '(string->list "hello")'
assert_c "(#\\e #\\l)" '(string->list "hello" 1 3)'
assert_c '"world"' '(list->string '\''(#\w #\o #\r #\l #\d))'
assert_c "#(#\\a #\\b #\\c)" '(string->vector "abc")'
assert_c "#(#\\b #\\c)" '(string->vector "abcd" 1 3)'
assert_c '"scheme"' '(vector->string (vector #\s #\c #\h #\e #\m #\e))'
assert_c '"ch"' '(vector->string (vector #\s #\c #\h #\e #\m #\e) 1 3)'
assert_c "#t" '(string<? "abc" "abd")'
assert_c "#f" '(string<? "abd" "abc")'
assert_c "#t" '(string<? "a" "b" "c")'
assert_c "#t" '(string>? "z" "y" "x")'
assert_c "#t" '(string<=? "abc" "abc" "abd")'
assert_c "#t" '(string>=? "c" "b" "b" "a")'
assert_c "#t" '(string=? "abc" "abc" "abc")'

echo "--- Step 11: R7RS Parameters & Parameterize ---"
assert_c "10" "(let ((p (make-parameter 10))) (p))"
assert_c "42" "(let ((p (make-parameter 10))) (begin (p 42) (p)))"
assert_c "10" "(let ((p (make-parameter 5 (lambda (x) (* x 2))))) (p))"
assert_c "14" "(let ((p (make-parameter 5 (lambda (x) (* x 2))))) (begin (p 7) (p)))"
assert_c "(20 . 10)" "(let ((p (make-parameter 10))) (let ((res (parameterize ((p 20)) (p)))) (cons res (p))))"
assert_c "33" "(let ((p1 (make-parameter 1)) (p2 (make-parameter 2))) (let ((res (parameterize ((p1 10) (p2 20)) (+ (p1) (p2))))) (+ res (+ (p1) (p2)))))"
assert_c "(1 (2 3 2) 1)" "(let ((p (make-parameter 1))) (cons (p) (cons (parameterize ((p 2)) (cons (p) (cons (parameterize ((p 3)) (p)) (cons (p) '())))) (cons (p) '()))))"
assert_c "42" "(parameterize () 42)"

echo "--- Step 12: R7RS Record-Type Definitions (Issue 549) ---"
assert_c "10" "(define-record-type point (make-point x y) point? (x point-x point-set-x!) (y point-y)) (let ((p (make-point 10 20))) (point-x p))"
assert_c "20" "(define-record-type point (make-point x y) point? (x point-x point-set-x!) (y point-y)) (let ((p (make-point 10 20))) (point-y p))"
assert_c "99" "(define-record-type point (make-point x y) point? (x point-x point-set-x!) (y point-y)) (let ((p (make-point 10 20))) (begin (point-set-x! p 99) (point-x p)))"
assert_c "#t" "(define-record-type point (make-point x y) point? (x point-x) (y point-y)) (point? (make-point 1 2))"
assert_c "#f" "(define-record-type point (make-point x y) point? (x point-x) (y point-y)) (point? (vector 1 2 3))"
assert_c "#f" "(define-record-type point (make-point x y) point? (x point-x) (y point-y)) (point? 42)"
assert_c "(100 . #f)" "(define-record-type task (create-task title) task? (title task-title) (completed? task-completed? task-set-completed!)) (let ((t (create-task 100))) (cons (task-title t) (task-completed? t)))"
assert_c "42" "(define-record-type task (create-task title) task? (title task-title) (completed? task-completed? task-set-completed!)) (let ((t (create-task 100))) (begin (task-set-completed! t 42) (task-completed? t)))"

echo "--- Step 13: R7RS Lazy Evaluation (Issue 550) ---"
assert_c "#t" "(promise? (delay 42))"
assert_c "#t" "(promise? (delay-force (delay 42)))"
assert_c "#t" "(promise? (make-promise 42))"
assert_c "#f" "(promise? 42)"
assert_c "#f" "(promise? (vector 1 2 3))"
assert_c "42" "(force (delay 42))"
assert_c "7" "(force (delay (+ 3 4)))"
assert_c "42" "(force (make-promise 42))"
assert_c "99" "(let ((p (delay 99))) (force (make-promise p)))"
assert_c "42" "(force (delay-force (delay 42)))"
assert_c "1" "(let ((count (vector 0))) (let ((p (delay (begin (vector-set! count 0 (+ (vector-ref count 0) 1)) 42)))) (let ((v1 (force p))) (let ((v2 (force p))) (vector-ref count 0)))))"
assert_c "6" "(define count (vector 0)) (define p (delay (begin (vector-set! count 0 (+ (vector-ref count 0) 1)) (if (> (vector-ref count 0) 5) (vector-ref count 0) (force p))))) (force p)"
assert_c "(0 1 2)" "(letrec ((integers (lambda (n) (delay (cons n (integers (+ n 1))))))) (let ((s (integers 0))) (let ((v0 (car (force s)))) (let ((v1 (car (force (cdr (force s)))))) (let ((v2 (car (force (cdr (force (cdr (force s)))))))) (list v0 v1 v2))))))"
assert_c "42" "(letrec ((loop (lambda (n) (delay-force (if (= n 0) (delay 42) (loop (- n 1))))))) (force (loop 2000)))"
assert_c "100" "(force (force (delay (delay 100))))"

echo "--- Step 14: Standalone R7RS Test Suites (test_*.scm) ---"
run_test_file_c "tests/test_record.scm" "lib/string.scm lib/vector.scm" "R7RS define-record-type suite"
run_test_file_c "tests/test_promise.scm" "lib/string.scm lib/vector.scm lib/promise.scm" "R7RS delay/force/promise suite"
run_test_file_c "tests/test_stdlib_r7rs.scm" "lib/list.scm lib/string.scm lib/vector.scm lib/bytevector.scm lib/equality.scm" "R7RS standard sequence library suite"

rm -f "$TMP_C" "$TMP_BIN"

echo "======================================================="
echo -e "\033[32m All $PASS_COUNT Portable C backend tests PASSED successfully with zero GCC warnings (-Werror)! \033[0m"
echo "======================================================="
