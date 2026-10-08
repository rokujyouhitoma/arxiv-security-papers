#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$DIR/.." && pwd)"
export PYTHONPATH="$ROOT_DIR"
cd "$DIR"

ILISP="python3 -m ilisp"
CC="gcc"
CFLAGS="-Wall -Wextra -O0 -g"

TMP_S="tmp.s"
TMP_BIN="tmp_bin"
COMPILER="compiler.scm"

mkdir -p build
make compiler
cat lib/string.scm lib/printer.scm lib/reader.scm compiler.scm > build/ulisp_core.scm

cleanup() {
    rm -f "$TMP_S" "$TMP_BIN"
}
trap cleanup EXIT

assert() {
    expected="$1"
    input="$2"

    if [[ "$input" =~ \'[a-zA-Z] || "$input" =~ string-\>symbol ]]; then
        full_input="$(cat lib/string.scm)"$'\n'"$input"
    else
        full_input="$input"
    fi

    # 1. Compile S-expression to x86-64 assembly
    $ILISP "$COMPILER" <<< "$full_input" > "$TMP_S"

    # 2. Assemble and link with minimal C runtime
    $CC $CFLAGS -o "$TMP_BIN" runtime.c "$TMP_S"

    # 3. Execute and compare output
    actual=$("./$TMP_BIN")

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

    $ILISP "$COMPILER" <<< "$program" > "$TMP_S"
    $CC $CFLAGS -o "$TMP_BIN" runtime.c "$TMP_S"
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

# =======================================================================
# Phase 7: Self-Hosting Bootstrap & Fixed-Point Verification
# =======================================================================
echo "=== Running ULisp Phase 7 Self-Hosting Bootstrap Test ==="
./bootstrap.sh


echo -e "\033[32m=== All Phase 1 through Phase 7 tests & Self-Hosting Bootstrap passed successfully! ===\033[0m"
