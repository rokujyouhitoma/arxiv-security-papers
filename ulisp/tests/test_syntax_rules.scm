;;; =======================================================================
;;; ULisp Hygienic syntax-rules Macro Expander Test Suite (R7RS Section 4.3)
;;; Conforms to DSN-33 Architecture Specification & Issue #533
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
        (display expected)
        (write-string ", Actual: ")
        (display actual)
        (write-char #\newline)
        (flush-output-port)
        (exit 1))))

(write-string "=== Running ULisp Hygienic syntax-rules Macro Tests ===\n")

;;; --- Test 1: Basic syntax-rules Macro (when & unless) ---
(write-string "--- Test 1: Basic when & unless Macros ---\n")
(define-syntax my-when
  (syntax-rules ()
    ((_ test body ...)
     (if test (begin body ...) #f))))

(define-syntax my-unless
  (syntax-rules ()
    ((_ test body ...)
     (if test #f (begin body ...)))))

(test "my-when true branch evaluates bodies" 42 (my-when (= 1 1) (+ 40 2)))
(test "my-when false branch returns #f" #f (my-when (= 1 2) 42))
(test "my-unless true branch returns #f" #f (my-unless (= 1 1) 100))
(test "my-unless false branch evaluates bodies" 100 (my-unless (= 1 2) (+ 50 50)))

;;; --- Test 2: Multi-rule Pattern Dispatch ---
(write-string "--- Test 2: Multi-rule Pattern Dispatch ---\n")
(define-syntax my-inc
  (syntax-rules ()
    ((_ x) (+ x 1))
    ((_ x step) (+ x step))))

(test "my-inc single arg uses default step 1" 11 (my-inc 10))
(test "my-inc two args uses specified step" 15 (my-inc 10 5))

;;; --- Test 3: Ellipsis Zero or More Repetitions ---
(write-string "--- Test 3: Ellipsis Zero or More Repetitions ---\n")
(define-syntax my-sum
  (syntax-rules ()
    ((_) 0)
    ((_ a) a)
    ((_ a b ...) (+ a (my-sum b ...)))))

(test "my-sum with 0 arguments" 0 (my-sum))
(test "my-sum with 1 argument" 42 (my-sum 42))
(test "my-sum with 3 arguments" 60 (my-sum 10 20 30))
(test "my-sum with 5 arguments" 150 (my-sum 10 20 30 40 50))

;;; --- Test 4: Literal Identifier Matching (else / =>) ---
(write-string "--- Test 4: Literal Identifier Matching ---\n")
(define-syntax my-cond-branch
  (syntax-rules (else)
    ((_ (else body ...))
     (begin body ...))
    ((_ (test body ...))
     (if test (begin body ...) #f))))

(test "my-cond-branch matches test branch" 777 (my-cond-branch ((= 3 3) 777)))
(test "my-cond-branch matches else branch" 999 (my-cond-branch (else 999)))

;;; --- Test 5: Hygienic Variable Capture Prevention (Hygiene) ---
(write-string "--- Test 5: Hygienic Variable Capture Prevention ---\n")
;; In an unhygienic macro, introducing a local variable named 'temp' would
;; shadow the caller's variable 'temp'.
;; In syntax-rules, 'temp' is automatically renamed to an unforgeable identifier.
(define-syntax with-temp-binding
  (syntax-rules ()
    ((_ val expr)
     (let ((temp val))
       (+ temp expr)))))

(let ((temp 100))
  ;; If hygiene works, 'expr' (temp) refers to caller's 100, while macro's 'temp' is 5.
  ;; Result must be 5 + 100 = 105.
  (test "hygiene protects caller variable from macro temporary capture"
        105
        (with-temp-binding 5 temp)))

;;; --- Test 6: Nested Macro Expansion ---
(write-string "--- Test 6: Nested Macro Expansion ---\n")
(define-syntax square
  (syntax-rules ()
    ((_ x) (* x x))))

(define-syntax sum-of-squares
  (syntax-rules ()
    ((_ a b)
     (+ (square a) (square b)))))

(test "nested macro expansion works correctly" 25 (sum-of-squares 3 4))

(write-string "=== All Hygienic syntax-rules Macro Tests Complete ===\n")
