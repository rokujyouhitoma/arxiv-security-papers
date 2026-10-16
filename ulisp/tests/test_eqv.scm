;;; =======================================================================
;;; ULisp R7RS Equivalence (eqv?) & Standard Predicates Test Suite
;;; Conforms to DSN-33 Architecture Specification & Issue #532
;;; =======================================================================

(define (equal? a b)
  (cond
    ((eq? a b) #t)
    ((and (pair? a) (pair? b))
     (and (equal? (car a) (car b))
          (equal? (cdr a) (cdr b))))
    ((and (string? a) (string? b))
     (string=? a b))
    (else #f)))

(define (test name expected actual)
  (if (equal? expected actual)
      (begin
        (write-string "  [PASS] ")
        (write-string name)
        (write-char #\newline)
        (flush-output-port)
        #t)
      (begin
        (write-string "  [FAIL] ")
        (write-string name)
        (write-string " - Expected: ")
        (write-string (if (boolean? expected) (if expected "#t" "#f") "val"))
        (write-char #\newline)
        (flush-output-port)
        #f)))

(write-string "=== Running ULisp R7RS eqv? & Standard Predicates Tests ===\n")

;;; --- Test 1: eqv? on Immediate Values (Numbers, Chars, Booleans, Null) ---
(write-string "--- Test 1: eqv? on Immediates ---\n")
(test "eqv? on identical positive fixnums" #t (eqv? 42 42))
(test "eqv? on distinct fixnums" #f (eqv? 42 43))
(test "eqv? on zero" #t (eqv? 0 0))
(test "eqv? on identical negative fixnums" #t (eqv? -10 -10))
(test "eqv? on distinct negative fixnums" #f (eqv? -10 -20))
(test "eqv? on identical chars" #t (eqv? #\a #\a))
(test "eqv? on distinct chars" #f (eqv? #\a #\b))
(test "eqv? on identical booleans (#t)" #t (eqv? #t #t))
(test "eqv? on identical booleans (#f)" #t (eqv? #f #f))
(test "eqv? on distinct booleans" #f (eqv? #t #f))
(test "eqv? on identical empty lists" #t (eqv? '() '()))
(test "eqv? on empty list and false" #f (eqv? '() #f))
(test "eqv? on number and false" #f (eqv? 0 #f))
(test "eqv? on number and char" #f (eqv? 97 #\a))

;;; --- Test 2: eqv? on Heap Objects (Pairs, Symbols, Closures) ---
(write-string "--- Test 2: eqv? on Heap Objects ---\n")
(let ((p (cons 1 2)))
  (test "eqv? on same pair instance" #t (eqv? p p)))
(test "eqv? on distinct pair instances" #f (eqv? (cons 1 2) (cons 1 2)))

(test "eqv? on identical symbols" #t (eqv? 'foo 'foo))
(test "eqv? on distinct symbols" #f (eqv? 'foo 'bar))
(let ((s 'my-sym))
  (test "eqv? on symbol bound to variable" #t (eqv? s 'my-sym)))

(let ((f (lambda (x) (+ x 1))))
  (test "eqv? on same closure instance" #t (eqv? f f)))
(test "eqv? on distinct closure instances" #f (eqv? (lambda (x) x) (lambda (x) x)))

;;; --- Test 3: R7RS Numerical Type Predicates ---
(write-string "--- Test 3: Numerical Type Predicates ---\n")
(test "number? on positive integer" #t (number? 42))
(test "number? on zero" #t (number? 0))
(test "number? on negative integer" #t (number? -99))
(test "number? on boolean" #f (number? #t))
(test "number? on char" #f (number? #\a))
(test "number? on pair" #f (number? (cons 1 2)))
(test "number? on empty list" #f (number? '()))

(test "integer? on integer" #t (integer? 100))
(test "integer? on boolean" #f (integer? #f))

(test "exact? on fixnum" #t (exact? 42))
(test "exact-integer? on fixnum" #t (exact-integer? 42))
(test "exact-integer? on symbol" #f (exact-integer? 'sym))

(test "inexact? on fixnum is false" #f (inexact? 42))
(test "inexact? on non-number is false" #f (inexact? #t))

(test "real? on fixnum" #t (real? 55))
(test "rational? on fixnum" #t (rational? 55))
(test "complex? on fixnum" #t (complex? 55))

;;; --- Test 4: boolean=? and symbol=? Predicates ---
(write-string "--- Test 4: boolean=? and symbol=? ---\n")
(test "boolean=? on (#t #t)" #t (boolean=? #t #t))
(test "boolean=? on (#f #f)" #t (boolean=? #f #f))
(test "boolean=? on (#t #f)" #f (boolean=? #t #f))
(test "boolean=? on (#f #t)" #f (boolean=? #f #t))
(test "boolean=? on numbers returns #f" #f (boolean=? 1 1))
(test "boolean=? on (#t number) returns #f" #f (boolean=? #t 1))

(test "symbol=? on same symbols" #t (symbol=? 'alpha 'alpha))
(test "symbol=? on distinct symbols" #f (symbol=? 'alpha 'beta))
(test "symbol=? on non-symbols returns #f" #f (symbol=? 42 42))

;;; --- Test 5: list? Predicate ---
(write-string "--- Test 5: list? Predicate ---\n")
(test "list? on empty list" #t (list? '()))
(test "list? on proper list (1 2 3)" #t (list? (cons 1 (cons 2 (cons 3 '())))))
(test "list? on dotted pair is #f" #f (list? (cons 1 2)))
(test "list? on number is #f" #f (list? 42))
(test "list? on symbol is #f" #f (list? 'sym))

;;; --- Test 6: First-class Function Behavior (High-order Usage) ---
(write-string "--- Test 6: First-class High-order Usage ---\n")
(define (my-memv item ls)
  (let loop ((cur ls))
    (cond
      ((null? cur) #f)
      ((eqv? (car cur) item) cur)
      (else (loop (cdr cur))))))

(let ((found (my-memv 3 '(1 2 3 4 5))))
  (test "my-memv finds element" 3 (car found))
  (test "my-memv returns tail" 4 (cadr found)))

(test "my-memv returns #f when not found" #f (my-memv 99 '(1 2 3)))

(define (apply-pred p a b)
  (p a b))

(test "eqv? passed as closure argument" #t (apply-pred eqv? 100 100))
(test "eqv? passed as closure argument (false)" #f (apply-pred eqv? 100 200))

(write-string "=== All R7RS eqv? & Standard Predicates Tests Complete ===\n")
