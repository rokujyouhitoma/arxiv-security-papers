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
CC="gcc"
CFLAGS="-Wall -Wextra -O0 -g"

TMP_S="tmp.s"
TMP_BIN="tmp_bin"
COMPILER="compiler.scm"
ULISP_STAGE1="build/scheme-stage1"
ULISP_BOOT="bin/ulisp-boot"

make compiler
cat lib/posix.scm lib/string.scm lib/port.scm lib/printer.scm lib/reader.scm lib/equality.scm lib/predicates.scm lib/bytevector.scm lib/vector.scm lib/promise.scm lib/exception.scm lib/values.scm lib/continuation.scm lib/parameter.scm lib/gc.scm compiler.scm > build/ulisp_core.scm

echo "=== Step 0: Running Isolated Nanopass Unit Tests (Pass 1-7) ==="
make test_passes
make test_annotator
make test_rtyper
make test_lir

# Determine compiler engine: prefer native scheme-stage1 / ulisp-boot, fallback to ILisp
USE_NATIVE_ULISP=false
ACTIVE_NATIVE=""

if [ "${FORCE_ILISP:-0}" != "1" ]; then
    make stage1 >/dev/null 2>&1 || true
    if [ -x "$ULISP_STAGE1" ]; then
        ACTIVE_NATIVE="$ULISP_STAGE1"
    elif [ -x "$ULISP_BOOT" ]; then
        ACTIVE_NATIVE="$ULISP_BOOT"
    fi

    if [ -n "$ACTIVE_NATIVE" ]; then
        # Smoke test: verify native compiler can compile and execute a trivial integer form correctly
        if echo "42" | ULISP_QUIET=1 "$ACTIVE_NATIVE" > "$TMP_S" 2>/dev/null && \
           $CC -nostdlib -static -o "$TMP_BIN" "$TMP_S" 2>/dev/null && \
           [ "$("./$TMP_BIN" 2>/dev/null)" = "42" ]; then
            USE_NATIVE_ULISP=true
        else
            rm -f "$ULISP_STAGE1"
        fi
        rm -f "$TMP_S" "$TMP_BIN"
    fi
fi

if [ "$USE_NATIVE_ULISP" = true ]; then
    echo "=== Compiler Engine: ULisp Native AOT Compiler ($ACTIVE_NATIVE, Fast mode: < 1s) ==="
    compile_scheme() {
        ULISP_QUIET=1 "$ACTIVE_NATIVE" <<< "$1" > "$2"
    }
else
    echo "=== Compiler Engine: ILisp Python Interpreter (Fallback mode) ==="
    compile_scheme() {
        $ILISP "$COMPILER" <<< "$1" > "$2"
    }
fi

cleanup() {
    rm -f "$TMP_S" "$TMP_BIN"
}
trap cleanup EXIT

assert() {
    expected="$1"
    input="$2"

    if [[ "$input" =~ gc- ]]; then
        full_input="$(cat lib/gc.scm)"$'\n'"$input"
    elif [[ "$input" =~ string-\>symbol || "$input" =~ symbol-\>string ]]; then
        full_input="$(cat lib/string.scm)"$'\n'"$input"
    elif [[ "$input" =~ open-input-string || "$input" =~ open-output-string || "$input" =~ "port\?" || "$input" =~ "input-port\?" || "$input" =~ "output-port\?" || "$input" =~ "textual-port\?" || "$input" =~ "get-output-string" ]]; then
        full_input="$(cat lib/posix.scm lib/string.scm lib/port.scm lib/printer.scm lib/reader.scm lib/equality.scm lib/predicates.scm lib/exception.scm lib/values.scm lib/continuation.scm lib/parameter.scm lib/gc.scm)"$'\n'"$input"
    elif [[ "$input" =~ parameter || "$input" =~ dynamic-wind ]]; then
        full_input="$(cat lib/posix.scm lib/string.scm lib/port.scm lib/printer.scm lib/reader.scm lib/equality.scm lib/predicates.scm lib/exception.scm lib/values.scm lib/continuation.scm lib/parameter.scm lib/gc.scm)"$'\n'"$input"
    elif [[ "$input" =~ bytevector || "$input" =~ utf8 ]]; then
        full_input="$(cat lib/string.scm lib/bytevector.scm)"$'\n'"$input"
    elif [[ "$input" =~ delay || "$input" =~ force || "$input" =~ promise ]]; then
        full_input="$(cat lib/string.scm lib/vector.scm lib/promise.scm)"$'\n'"$input"
    elif [[ "$input" =~ define-record-type || "$input" =~ vector ]]; then
        full_input="$(cat lib/string.scm lib/vector.scm)"$'\n'"$input"
    else
        full_input="$input"
    fi

    mkdir -p build

    # 1. Compile S-expression to x86-64 assembly
    if ! compile_scheme "$full_input" "$TMP_S" 2>build/compile_err.log; then
        printf "\033[31m[COMPILE FAIL]\033[0m %s\n" "$input"
        cat build/compile_err.log
        exit 1
    fi

    # 2. Assemble and link freestanding zero-libc binary
    if ! $CC -nostdlib -static -o "$TMP_BIN" "$TMP_S" 2>build/asm_err.log; then
        printf "\033[31m[ASSEMBLE FAIL]\033[0m %s\n" "$input"
        cat build/asm_err.log
        exit 1
    fi

    # 3. Execute and compare output
    if ! actual=$("./$TMP_BIN" 2>build/run_err.log); then
        printf "\033[31m[EXEC FAIL]\033[0m %s (exit code $?)\n" "$input"
        cat build/run_err.log
        exit 1
    fi

    if [ "$actual" = "$expected" ]; then
        printf "\033[32m[PASS]\033[0m %s => %s\n" "$input" "$actual"
    else
        printf "\033[31m[FAIL]\033[0m %s: expected '%s', but got '%s'\n" "$input" "$expected" "$actual"
        exit 1
    fi
}

assert_stdin() {
    expected="$1"
    program="$2"
    stdin_input="$3"

    compile_scheme "$program" "$TMP_S"
    $CC -nostdlib -static -o "$TMP_BIN" "$TMP_S"
    actual=$(printf "%s" "$stdin_input" | "./$TMP_BIN")


    if [ "$actual" = "$expected" ]; then
        printf "\033[32m[PASS]\033[0m %s (stdin: %s) => %s\n" "$program" "$stdin_input" "$actual"
    else
        printf "\033[31m[FAIL]\033[0m %s (stdin: %s): expected '%s', but got '%s'\n" "$program" "$stdin_input" "$expected" "$actual"
        exit 1
    fi
}

echo "=== Running ULisp Phase 1 Tests ==="

# --- Step 1: Integers (Fixnums) ---
echo "-- Step 1: Integers --"
assert "42" "42"
assert "0" "0"
assert "-1" "-1"
assert "100" "100"
assert "-42" "-42"
assert "1000000" "1000000"

# --- Step 2: Immediate Literals ---
echo "-- Step 2: Immediate Literals --"
assert "#t" "#t"
assert "#f" "#f"
assert "()" "()"
assert "#\\a" "#\\a"
assert "#\\z" "#\\z"
assert "#\\A" "#\\A"
assert "#\\newline" "#\\newline"
assert "#\\space" "#\\space"

# --- Step 3: Unary Numeric & Char Primitives ---
echo "-- Step 3: Unary Operations --"
assert "43" "(fxadd1 42)"
assert "41" "(fxsub1 42)"
assert "1" "(fxadd1 0)"
assert "-1" "(fxsub1 0)"
assert "10" "(fxadd1 (fxadd1 8))"
assert "#\\a" "(fixnum->char 97)"
assert "97" "(char->fixnum #\\a)"
assert "#\\b" "(fixnum->char (fxadd1 (char->fixnum #\\a)))"

# --- Step 4: Unary Type Predicates ---
echo "-- Step 4: Type Predicates --"
assert "#t" "(fixnum? 42)"
assert "#t" "(fixnum? 0)"
assert "#f" "(fixnum? #t)"
assert "#f" "(fixnum? #\\a)"
assert "#f" "(fixnum? ())"

assert "#t" "(boolean? #t)"
assert "#t" "(boolean? #f)"
assert "#f" "(boolean? 0)"
assert "#f" "(boolean? #\\a)"
assert "#f" "(boolean? ())"

assert "#t" "(char? #\\a)"
assert "#f" "(char? 42)"
assert "#f" "(char? #t)"
assert "#f" "(char? ())"

assert "#t" "(null? ())"
assert "#f" "(null? 42)"
assert "#f" "(null? #t)"
assert "#f" "(null? #\\a)"

assert "#t" "(zero? 0)"
assert "#f" "(zero? 1)"
assert "#f" "(zero? -1)"
assert "#t" "(zero? (fxsub1 1))"

# R7RS Numerical Predicates
assert "#t" "(number? 42)"
assert "#f" "(number? #t)"
assert "#t" "(integer? 42)"
assert "#f" "(integer? #\\a)"
assert "#t" "(exact? 42)"
assert "#t" "(exact-integer? 42)"
assert "#f" "(inexact? 42)"
assert "#t" "(real? 42)"
assert "#t" "(rational? 42)"
assert "#t" "(complex? 42)"

# =======================================================================
# Phase 2: Stack Management & Local Variables
# =======================================================================
echo "=== Running ULisp Phase 2 Tests ==="

# --- Step 5: Binary Operations (+, -) ---
echo "-- Step 5: Binary Operations (+, -) --"
assert "3" "(+ 1 2)"
assert "42" "(+ 40 2)"
assert "0" "(+ 5 -5)"
assert "7" "(- 10 3)"
assert "-3" "(- 0 3)"
assert "100" "(- (+ 60 50) 10)"
assert "6" "(+ (+ 1 2) 3)"

# --- Step 6: Multiplications & Comparisons (*, =, <, <=, >, >=) ---
echo "-- Step 6: Multiplications & Comparisons (*, =, <, <=, >, >=) --"
assert "42" "(* 6 7)"
assert "0" "(* 0 100)"
assert "-20" "(* 4 -5)"
assert "24" "(* (* 2 3) 4)"

assert "#t" "(= 5 5)"
assert "#f" "(= 5 6)"
assert "#t" "(= 0 0)"
assert "#t" "(= (+ 2 3) 5)"

assert "#t" "(< 2 3)"
assert "#f" "(< 3 2)"
assert "#f" "(< 3 3)"

assert "#t" "(<= 2 3)"
assert "#t" "(<= 3 3)"
assert "#f" "(<= 4 3)"

assert "#t" "(> 5 2)"
assert "#f" "(> 2 5)"
assert "#f" "(> 3 3)"

assert "#t" "(>= 5 2)"
assert "#t" "(>= 3 3)"
assert "#f" "(>= 2 5)"

# --- Step 7: Local Variables (let) ---
echo "-- Step 7: Local Variables (let) --"
assert "10" "(let ((x 10)) x)"
assert "30" "(let ((x 10) (y 20)) (+ x y))"
assert "30" "(let ((x 5) (y 10) (z 2)) (* (+ x y) 2))"
assert "42" "(let ((a 6) (b 7)) (* a b))"

# --- Step 8: Nested let & Variable Shadowing ---
echo "-- Step 8: Nested let & Variable Shadowing --"
assert "15" "(let ((x 5)) (let ((y 10)) (+ x y)))"
assert "20" "(let ((x 10)) (let ((x 20)) x))"
assert "12" "(let ((x 2)) (let ((x (+ x 4))) (* x 2)))"
assert "7"  "(let ((x 1)) (+ x (let ((x 2)) (+ x 4))))"
assert "100" "(let ((x (let ((y 10)) (* y y)))) x)"

# =======================================================================
# Phase 3: Conditionals & Control Flow
# =======================================================================
echo "=== Running ULisp Phase 3 Tests ==="

# --- Step 9: Conditionals (if) ---
echo "-- Step 9: Conditionals (if) --"
assert "1" "(if #t 1 2)"
assert "2" "(if #f 1 2)"
assert "10" "(if (= 5 5) 10 20)"
assert "20" "(if (= 5 6) 10 20)"
assert "42" "(if (< 2 3) (+ 40 2) (- 100 50))"
assert "#f" "(if #f 1)"

# Truthiness in Scheme: everything except #f is true (including 0 and '())
echo "-- Truthiness Rules --"
assert "1" "(if 0 1 2)"
assert "1" "(if () 1 2)"
assert "1" "(if #\\a 1 2)"
assert "1" "(if 42 1 2)"

# --- Step 10: Logical Desugaring (and, or, not) ---
echo "-- Step 10: Logical Desugaring (and, or, not) --"
assert "#f" "(not #t)"
assert "#t" "(not #f)"
assert "#f" "(not 0)"
assert "#f" "(not ())"

assert "#t" "(and)"
assert "42" "(and 42)"
assert "3" "(and 1 2 3)"
assert "#f" "(and #t #f #t)"
assert "30" "(and #t (> 5 2) (+ 10 20))"

assert "#f" "(or)"
assert "42" "(or 42)"
assert "1" "(or 1 2 3)"
assert "2" "(or #f 2 #f)"
assert "50" "(or #f #f 50)"

# Short-circuiting verification (nested let side effects or logic)
assert "10" "(let ((x 10)) (if (or #t (= x 0)) x 0))"

# --- Step 11: Sequences (begin) ---
echo "-- Step 11: Sequences (begin) --"
assert "42" "(begin 42)"
assert "3" "(begin 1 2 3)"
assert "15" "(begin (+ 1 2) (* 3 4) (+ 10 5))"
assert "100" "(let ((x 10)) (begin (+ x 1) (* x x)))"

# =======================================================================
# Phase 4: Heap Memory & Compound Data Structures
# =======================================================================
echo "=== Running ULisp Phase 4 Tests ==="

# --- Step 12 & 13: Pairs and Lists (cons, car, cdr, pair?) ---
echo "-- Step 12 & 13: cons, car, cdr, pair? --"
assert "(1 . 2)" "(cons 1 2)"
assert "(1 2)" "(cons 1 (cons 2 ()))"
assert "(1 2 3)" "(cons 1 (cons 2 (cons 3 ())))"
assert "1" "(car (cons 1 2))"
assert "2" "(cdr (cons 1 2))"
assert "3" "(car (cdr (cons 1 (cons 3 ()))))"
assert "((1 . 2) 3 . 4)" "(cons (cons 1 2) (cons 3 4))"

assert "#t" "(pair? (cons 1 2))"
assert "#t" "(pair? (cons 1 ()))"
assert "#f" "(pair? 42)"
assert "#f" "(pair? #t)"
assert "#f" "(pair? ())"

# --- Step 14: Mutation (set-car!, set-cdr!) ---
echo "-- Step 14: set-car!, set-cdr! --"
assert "10" "(let ((p (cons 1 2))) (begin (set-car! p 10) (car p)))"
assert "20" "(let ((p (cons 1 2))) (begin (set-cdr! p 20) (cdr p)))"
assert "(99 . 2)" "(let ((p (cons 1 2))) (begin (set-car! p 99) p))"
assert "(1 . 88)" "(let ((p (cons 1 2))) (begin (set-cdr! p 88) p))"
assert "(42 . 42)" "(let ((p (cons 1 2))) (begin (set-car! p 42) (set-cdr! p 42) p))"

# --- Step 15: Quoted Literals (quote) ---
echo "-- Step 15: quote --"
assert "42" "'42"
assert "#t" "'#t"
assert "#\\a" "'#\\a"
assert "()" "'()"
assert "(1 2 3)" "'(1 2 3)"
assert "(1 . 2)" "'(1 . 2)"
assert "((1 2) (3 4))" "'((1 2) (3 4))"
assert "1" "(car '(1 2 3))"
assert "(2 3)" "(cdr '(1 2 3))"

# --- Step 16: Identity and Pointer Equality (eq?) ---
echo "-- Step 16: Pointer Equality (eq?) --"
assert "#t" "(eq? 42 42)"
assert "#f" "(eq? 42 43)"
assert "#t" "(eq? #t #t)"
assert "#f" "(eq? #t #f)"
assert "#t" "(eq? () ())"
assert "#f" "(eq? () #f)"

# Same pair vs distinct pairs
assert "#t" "(let ((p (cons 1 2))) (eq? p p))"
assert "#f" "(eq? (cons 1 2) (cons 1 2))"
assert "#t" "(let ((p '(1 2))) (eq? p p))"

# Symbol quoting and eq? comparison
assert "#t" "(eq? 'a 'a)"
assert "#f" "(eq? 'a 'b)"
assert "#t" "(let ((x 'foo)) (eq? x 'foo))"
assert "#f" "(let ((x 'foo)) (eq? x 'bar))"

# R7RS eqv? comparisons
assert "#t" "(eqv? 42 42)"
assert "#f" "(eqv? 42 43)"
assert "#t" "(eqv? #\\a #\\a)"
assert "#f" "(eqv? #\\a #\\b)"
assert "#t" "(eqv? 'foo 'foo)"
assert "#f" "(eqv? 'foo 'bar)"
assert "#t" "(let ((p (cons 1 2))) (eqv? p p))"
assert "#f" "(eqv? (cons 1 2) (cons 1 2))"
assert "#t" "(boolean=? #t #t)"
assert "#t" "(boolean=? #f #f)"
assert "#f" "(boolean=? #t #f)"
assert "#t" "(symbol=? 'foo 'foo)"
assert "#f" "(symbol=? 'foo 'bar)"

# =======================================================================
# Phase 5: Procedures, Closures & Tail Call Optimization (TCO)
# =======================================================================
echo "=== Running ULisp Phase 5 Tests ==="

# --- Step 17: Procedure Calls & Direct Lambdas ---
echo "-- Step 17: Direct Lambdas & Multi-args --"
assert "42" "((lambda (x) (+ x 1)) 41)"
assert "42" "((lambda (x y) (+ (* x 10) y)) 4 2)"
assert "6" "((lambda (a b c) (+ a (+ b c))) 1 2 3)"
assert "10" "(let ((add (lambda (x y) (+ x y)))) (add 4 6))"

# --- Step 19 & 20: Free Variables & Closures ---
echo "-- Step 19 & 20: Closures & Higher-Order Functions --"
assert "15" "(let ((a 10)) (let ((f (lambda (x) (+ a x)))) (f 5)))"
assert "30" "(let ((a 10) (b 20)) (let ((f (lambda () (+ a b)))) (f)))"

# Currying / Returning a procedure
assert "15" "(let ((make-adder (lambda (n) (lambda (x) (+ x n))))) (let ((add5 (make-adder 5))) (add5 10)))"
assert "42" "(let ((make-adder (lambda (n) (lambda (x) (+ x n))))) ((make-adder 40) 2))"

# Higher-order function: procedure as argument
assert "12" "(let ((apply2 (lambda (f x) (f (f x))))) (apply2 (lambda (n) (* n 2)) 3))"

# State / Pair capturing closure
assert "(1 . 2)" "(let ((p (cons 1 2))) (let ((get-p (lambda () p))) (get-p)))"

# --- Recursion with letrec ---
echo "-- Recursion with letrec --"
assert "120" "(letrec ((fact (lambda (n) (if (= n 0) 1 (* n (fact (- n 1))))))) (fact 5))"
assert "55" "(letrec ((fib (lambda (n) (if (<= n 1) n (+ (fib (- n 1)) (fib (- n 2))))))) (fib 10))"

# --- Step 18: Tail Call Optimization (TCO) Depth Test ---
echo "-- Step 18: Tail Call Optimization (TCO) --"
# Non-tail recursion of 1000000 would cause stack overflow (SIGSEGV).
# TCO runs in O(1) stack space and finishes in milliseconds.
assert "42" "(letrec ((loop (lambda (n) (if (= n 0) 42 (loop (- n 1)))))) (loop 1000000))"
assert "100" "(letrec ((sum (lambda (n acc) (if (= n 0) acc (sum (- n 1) (+ acc 1)))))) (sum 100 0))"

# =======================================================================
# Phase 6: Parser (read), Minimal I/O & Desugaring (cond, let*)
# =======================================================================
echo "=== Running ULisp Phase 6 Tests ==="

# --- Step 23: Desugaring (cond, let*) ---
echo "-- Step 23: Desugaring (cond, let*) --"
assert "20" "(cond ((= 1 2) 10) ((= 3 3) 20) (else 30))"
assert "30" "(cond ((= 1 2) 10) (else 30))"
assert "10" "(cond ((= 1 1) 10))"
assert "#f" "(cond ((= 1 2) 10))"
assert "30" "(let* ((x 10) (y (+ x 5)) (z (* y 2))) z)"
assert "42" "(let* ((a 6) (b 7)) (* a b))"

# Multi-expression bodies (implicit begin in lambda, let, letrec)
assert "100" "(let ((x 10)) (+ x 1) (* x x))"
assert "42" "((lambda (x) (+ x 1) 42) 0)"

# --- Step 21: Minimal I/O Primitives ---
echo "-- Step 21: Minimal I/O Primitives --"
assert_stdin "#\\A" "(read-char)" "A"
assert_stdin "#\\B" "(begin (read-char) (read-char))" "AB"
assert_stdin "#t" "(eof-object? (read-char))" ""
assert_stdin "#f" "(eof-object? (read-char))" "x"
assert_stdin "#\\X" "(begin (peek-char) (read-char))" "XYZ"

# --- Step 22: Hand-written Recursive Descent S-Expression Reader (read) ---
echo "-- Step 22: Hand-written S-Expression Reader --"

PARSER_CODE='(letrec
  ((is-space (lambda (c) (or (eq? c #\space) (eq? c #\newline) (eq? c #\tab))))
   (skip-ws (lambda ()
              (let ((c (peek-char)))
                (if (and (not (eof-object? c)) (is-space c))
                    (begin (read-char) (skip-ws))
                    #t))))
   (read-num-acc (lambda (acc)
                   (let ((c (peek-char)))
                     (if (and (not (eof-object? c))
                              (and (>= (char->fixnum c) (char->fixnum #\0))
                                   (<= (char->fixnum c) (char->fixnum #\9))))
                         (begin
                           (read-char)
                           (read-num-acc (+ (* acc 10) (- (char->fixnum c) (char->fixnum #\0)))))
                         acc))))
   (read-list (lambda ()
                (skip-ws)
                (let ((c (peek-char)))
                  (cond
                    ((eof-object? c) '\''())
                    ((eq? c #\))
                     (read-char)
                     '\''())
                    ((eq? c #\.)
                     (read-char)
                     (skip-ws)
                     (let ((cdr-val (read-val)))
                       (skip-ws)
                       (read-char)
                       cdr-val))
                    (else
                     (let ((elem (read-val)))
                       (cons elem (read-list))))))))
   (read-val (lambda ()
               (skip-ws)
               (let ((c (peek-char)))
                 (cond
                   ((eof-object? c) c)
                   ((eq? c #\()
                    (read-char)
                    (read-list))
                   ((and (>= (char->fixnum c) (char->fixnum #\0))
                         (<= (char->fixnum c) (char->fixnum #\9)))
                    (read-num-acc 0))
                   ((eq? c #\#)
                    (read-char)
                    (let ((c2 (read-char)))
                      (cond
                        ((eq? c2 #\t) #t)
                        ((eq? c2 #\f) #f)
                        (else #f))))
                   (else
                    (read-char)))))))
  (read-val))'

assert_stdin "(1 2 3)" "$PARSER_CODE" "(1 2 3)"
assert_stdin "(1 . 2)" "$PARSER_CODE" "(1 . 2)"
assert_stdin "((10 20) (30 40))" "$PARSER_CODE" "((10 20) (30 40))"
assert_stdin "(1 #t #f)" "$PARSER_CODE" "(1 #t #f)"
assert_stdin "42" "$PARSER_CODE" "42"

# --- Step 24: Low-level string & arithmetic primitives (Issue 494) ---
echo "-- Step 24: Issue 494 Low-level String & Arithmetic Primitives --"
assert "7" "(quotient 42 6)"
assert "3" "(quotient 10 3)"
assert "-3" "(quotient -10 3)"
assert "6" "(/ 42 7)"
assert "5" '(string-length "hello")'
assert "0" '(string-length "")'
assert '#\h' '(string-ref "hello" 0)'
assert '#\o' '(string-ref "hello" 4)'
assert '"abc"' '(let ((s (make-string 3))) (begin (string-set! s 0 #\a) (string-set! s 1 #\b) (string-set! s 2 #\c) s))'

# --- Step 25: Hygienic syntax-rules Macro Expander (Issue 533) ---
echo "-- Step 25: Issue 533 Hygienic syntax-rules Macro Expander --"
assert "42" "(define-syntax when (syntax-rules () ((_ c body ...) (if c (begin body ...) #f)))) (when (= 5 5) 42)"
assert "100" "(define-syntax unless (syntax-rules () ((_ c body ...) (if c #f (begin body ...))))) (unless (= 5 6) 100)"
assert "81" "(define-syntax my-square (syntax-rules () ((_ x) (* x x)))) (my-square 9)"
assert "42" "(define-syntax inc (syntax-rules () ((_ x) (+ x 1)))) (inc (inc 40))"
assert "105" "(define-syntax with-tmp (syntax-rules () ((_ val expr) (let ((temp val)) (+ temp expr))))) (let ((temp 100)) (with-tmp 5 temp))"

# --- Step 26: Target Runtime Cheney Garbage Collector (Issue 501) ---
echo "-- Step 26: Issue 501 Target Garbage Collector --"
assert "7" "(bitwise-and 15 7)"
assert "9" "(bitwise-ior 8 1)"
assert "60" "(let* ((orig (%get-heap-ptr)) (half 4096) (from orig) (to (+ orig half))) (begin (gc-init! from to half (%get-rsp)) (let ((lst (cons 10 (cons 20 (cons 30 (quote ())))))) (begin (gc-collect! (%get-rsp)) (+ (car lst) (+ (car (cdr lst)) (car (cdr (cdr lst)))))))))"
assert "300" "(let* ((orig (%get-heap-ptr)) (half 4096) (from orig) (to (+ orig half))) (begin (gc-init! from to half (%get-rsp)) (let ((lst (cons 100 200))) (begin (gc-collect! (%get-rsp)) (gc-collect! (%get-rsp)) (gc-collect! (%get-rsp)) (+ (car lst) (cdr lst))))))"
assert "10" "(let* ((orig (%get-heap-ptr)) (half 4096) (from orig) (to (+ orig half))) (begin (gc-init! from to half (%get-rsp)) (let ((p (cons 10 (quote ())))) (begin (gc-collect! (%get-rsp)) (car p)))))"

# --- Step 27: Contification & Local Closure Elimination (Issue 522) ---
echo "-- Step 27: Issue 522 Contification & Local Closure Elimination --"
assert "55" "(let loop ((n 10) (acc 0)) (if (= n 0) acc (loop (- n 1) (+ acc n))))"
assert "120" "(letrec ((fact (lambda (n acc) (if (= n 1) acc (fact (- n 1) (* acc n)))))) (fact 5 1))"
assert "45" "(letrec ((sum (lambda (i total) (if (= i 10) total (sum (+ i 1) (+ total i)))))) (sum 0 0))"

# --- Step 28: R7RS String Ports (Issue 534) ---
echo "-- Step 28: Issue 534 R7RS String Ports --"
assert "(1 2 3)" '(read (open-input-string "(1 2 3)"))'
assert '"(+ 1 2)"' '(let ((p (open-output-string))) (begin (display (read (open-input-string "(+ 1 2)")) p) (get-output-string p)))'
assert '"hello"' '(let ((p (open-output-string))) (begin (display "hello" p) (get-output-string p)))'
assert '""hello""' '(let ((p (open-output-string))) (begin (write "hello" p) (get-output-string p)))'
assert '"123 world"' '(let ((p (open-output-string))) (begin (display 123 p) (write-char #\space p) (display "world" p) (get-output-string p)))'
assert "#t" '(port? (open-input-string "abc"))'
assert "#t" '(input-port? (open-input-string "abc"))'
assert "#f" '(output-port? (open-input-string "abc"))'
assert "#t" '(output-port? (open-output-string))'
assert "#f" '(input-port? (open-output-string))'
assert "#t" '(textual-port? (open-output-string))'
assert "#\\b" '(let ((p (open-input-string "abc"))) (begin (read-char p) (read-char p)))'
assert "#\\x" '(let ((p (open-input-string "xyz"))) (begin (peek-char p) (read-char p)))'
assert "#t" '(let ((p (open-input-string ""))) (eof-object? (read-char p)))'

# --- Step 29: R7RS Bytevectors for Binary Security (Issue 535) ---
echo "-- Step 29: Issue 535 R7RS Bytevectors for Binary Security --"
assert "#t" "(bytevector? (make-bytevector 5))"
assert "#f" '(bytevector? "hello")'
assert "#f" "(bytevector? 123)"
assert "10" "(bytevector-length (make-bytevector 10))"
assert "0" "(bytevector-length (make-bytevector 0))"
assert "#u8(0 0 0)" "(make-bytevector 3)"
assert "#u8(42 42 42)" "(make-bytevector 3 42)"
assert "66" "(let ((bv (make-bytevector 3))) (begin (bytevector-u8-set! bv 0 65) (bytevector-u8-set! bv 1 66) (bytevector-u8-set! bv 2 67) (bytevector-u8-ref bv 1)))"
assert "#u8(65 66 67)" "(let ((bv (make-bytevector 3))) (begin (bytevector-u8-set! bv 0 65) (bytevector-u8-set! bv 1 66) (bytevector-u8-set! bv 2 67) bv))"
assert "#u8(1 2 3)" "(bytevector 1 2 3)"
assert "#u8(10 20 30)" "(bytevector-copy (bytevector 10 20 30))"
assert "#u8(20 30)" "(bytevector-copy (bytevector 10 20 30 40) 1 3)"
assert "#t" "(bytevector=? (bytevector 1 2 3) (bytevector 1 2 3))"
assert "#f" "(bytevector=? (bytevector 1 2 3) (bytevector 1 2 4))"
assert "#f" "(bytevector=? (bytevector 1 2) (bytevector 1 2 3))"
assert "#u8(1 2 3 4 5)" "(bytevector-append (bytevector 1 2) (bytevector 3 4 5))"
assert "#u8(0 1 2 3 0)" "(let ((to (make-bytevector 5 0)) (from (bytevector 1 2 3))) (begin (bytevector-copy! to 1 from) to))"
assert "#u8(65 66 67)" '(string->utf8 "ABC")'
assert '"Hello"' "(utf8->string (bytevector 72 101 108 108 111))"
assert "5" "(bytevector-length (bytevector 0 1 0 2 0))"
assert "0" "(bytevector-u8-ref (bytevector 0 1 0 2 0) 2)"

# --- Step 30: R7RS Vectors (Issue 536) ---
echo "-- Step 30: Issue 536 R7RS Vectors --"
assert "#t" "(vector? (make-vector 5))"
assert "#f" '(vector? "hello")'
assert "#f" "(vector? '(1 2 3))"
assert "#f" "(vector? 123)"
assert "10" "(vector-length (make-vector 10))"
assert "0" "(vector-length (make-vector 0))"
assert "#(#f #f #f)" "(make-vector 3)"
assert "#(42 42 42)" "(make-vector 3 42)"
assert "20" "(let ((v (make-vector 3))) (begin (vector-set! v 0 10) (vector-set! v 1 20) (vector-set! v 2 30) (vector-ref v 1)))"
assert "#(10 20 30)" "(let ((v (make-vector 3))) (begin (vector-set! v 0 10) (vector-set! v 1 20) (vector-set! v 2 30) v))"
assert "#(1 2 3)" "(vector 1 2 3)"
assert "#(10 20 30)" "(vector-copy (vector 10 20 30))"
assert "#(20 30)" "(vector-copy (vector 10 20 30 40) 1 3)"
assert "#(9 9 9)" "(let ((v (make-vector 3))) (begin (vector-fill! v 9) v))"
assert "#(1 2 3 4 5)" "(vector-append (vector 1 2) (vector 3 4 5))"
assert "#(0 1 2 3 0)" "(let ((to (make-vector 5 0)) (from (vector 1 2 3))) (begin (vector-copy! to 1 from) to))"
assert "(1 2 3)" "(vector->list (vector 1 2 3))"
assert "(2 3)" "(vector->list (vector 1 2 3 4) 1 3)"
assert "#(1 2 3)" "(list->vector '(1 2 3))"
assert "#(1 #(2 3) 4)" "(vector 1 (vector 2 3) 4)"
assert "2" "(vector-ref (vector-ref (vector 1 (vector 2 3) 4) 1) 0)"
assert "#(100 200)" "(let loop ((i 0) (last-v (vector 0 0))) (if (< i 50) (loop (+ i 1) (vector 100 200)) last-v))"

# --- Step 31: R7RS Parameters & Parameterize (Issue 537) ---
echo "-- Step 31: Issue 537 R7RS Parameters & Parameterize --"
assert "10" "(let ((p (make-parameter 10))) (p))"
assert "42" "(let ((p (make-parameter 10))) (begin (p 42) (p)))"
assert "10" "(let ((p (make-parameter 5 (lambda (x) (* x 2))))) (p))"
assert "14" "(let ((p (make-parameter 5 (lambda (x) (* x 2))))) (begin (p 7) (p)))"
assert "(20 . 10)" "(let ((p (make-parameter 10))) (let ((res (parameterize ((p 20)) (p)))) (cons res (p))))"
assert "33" "(let ((p1 (make-parameter 1)) (p2 (make-parameter 2))) (let ((res (parameterize ((p1 10) (p2 20)) (+ (p1) (p2))))) (+ res (+ (p1) (p2)))))"
assert "(1 (2 3 2) 1)" "(let ((p (make-parameter 1))) (cons (p) (cons (parameterize ((p 2)) (cons (p) (cons (parameterize ((p 3)) (p)) (cons (p) '())))) (cons (p) '()))))"
assert "10" "(let ((p (make-parameter 10))) (guard (e (else (p))) (parameterize ((p 99)) (raise 'error))))"
assert "100" "(let ((p (make-parameter 100)) (saved-k (cons #f '()))) (let ((res (call/cc (lambda (k) (set-car! saved-k k) 0)))) (if (= res 0) (parameterize ((p 200)) ((car saved-k) 1)) (p))))"
assert "42" "(parameterize () 42)"

# --- Step 32: R7RS Record-Type Definitions (Issue 549) ---
echo "-- Step 32: Issue 549 R7RS define-record-type --"
assert "10" "(define-record-type point (make-point x y) point? (x point-x point-set-x!) (y point-y)) (let ((p (make-point 10 20))) (point-x p))"
assert "20" "(define-record-type point (make-point x y) point? (x point-x point-set-x!) (y point-y)) (let ((p (make-point 10 20))) (point-y p))"
assert "99" "(define-record-type point (make-point x y) point? (x point-x point-set-x!) (y point-y)) (let ((p (make-point 10 20))) (begin (point-set-x! p 99) (point-x p)))"
assert "#t" "(define-record-type point (make-point x y) point? (x point-x) (y point-y)) (point? (make-point 1 2))"
assert "#f" "(define-record-type point (make-point x y) point? (x point-x) (y point-y)) (point? (vector 1 2 3))"
assert "#f" "(define-record-type point (make-point x y) point? (x point-x) (y point-y)) (point? 42)"
assert "(100 . #f)" "(define-record-type task (create-task title) task? (title task-title) (completed? task-completed? task-set-completed!)) (let ((t (create-task 100))) (cons (task-title t) (task-completed? t)))"
assert "42" "(define-record-type task (create-task title) task? (title task-title) (completed? task-completed? task-set-completed!)) (let ((t (create-task 100))) (begin (task-set-completed! t 42) (task-completed? t)))"

echo "-- Step 32b: Standalone R7RS Record-Type Test Suite (tests/test_record.scm) --"
make test_record

# --- Step 33: R7RS Lazy Evaluation (Issue 550) ---
echo "-- Step 33: Issue 550 R7RS delay, force, delay-force, make-promise, promise? --"
assert "#t" "(promise? (delay 42))"
assert "#t" "(promise? (delay-force (delay 42)))"
assert "#t" "(promise? (make-promise 42))"
assert "#f" "(promise? 42)"
assert "#f" "(promise? (vector 1 2 3))"
assert "42" "(force (delay 42))"
assert "7" "(force (delay (+ 3 4)))"
assert "42" "(force (make-promise 42))"
assert "99" "(let ((p (delay 99))) (force (make-promise p)))"
assert "42" "(force (delay-force (delay 42)))"
assert "1" "(let ((count (vector 0))) (let ((p (delay (begin (vector-set! count 0 (+ (vector-ref count 0) 1)) 42)))) (let ((v1 (force p))) (let ((v2 (force p))) (vector-ref count 0)))))"
assert "6" "(define count (vector 0)) (define p (delay (begin (vector-set! count 0 (+ (vector-ref count 0) 1)) (if (> (vector-ref count 0) 5) (vector-ref count 0) (force p))))) (force p)"
assert "(0 1 2)" "(letrec ((integers (lambda (n) (delay (cons n (integers (+ n 1))))))) (let ((s (integers 0))) (let ((v0 (car (force s)))) (let ((v1 (car (force (cdr (force s)))))) (let ((v2 (car (force (cdr (force (cdr (force s)))))))) (list v0 v1 v2))))))"
assert "42" "(letrec ((loop (lambda (n) (delay-force (if (= n 0) (delay 42) (loop (- n 1))))))) (force (loop 2000)))"
assert "100" "(force (force (delay (delay 100))))"

echo "-- Step 33b: Standalone R7RS Lazy Evaluation Test Suite (tests/test_promise.scm) --"
make test_promise

# =======================================================================
# Phase 7: Self-Hosting Bootstrap & Fixed-Point Verification
# =======================================================================
echo "=== Running ULisp Phase 7 Self-Hosting Bootstrap Test ==="
BOOTSTRAP_FAST="${BOOTSTRAP_FAST:-1}" ./bootstrap.sh


echo -e "\033[32m=== All Phase 1 through Phase 7 tests & Self-Hosting Bootstrap passed successfully! ===\033[0m"
