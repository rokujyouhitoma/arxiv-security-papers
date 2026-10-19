;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 050 (CP0 Constant Folding & DCE)
;;; Conforms to Issue #572 & Nanopass Architecture Quality Standard
;;; =======================================================================

(define *pass-tests-passed* 0)
(define *pass-tests-failed* 0)

(define (assert-equal label expected actual)
  (if (equal? expected actual)
      (begin
        (set! *pass-tests-passed* (+ *pass-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (set! *pass-tests-failed* (+ *pass-tests-failed* 1))
        (display "  [FAIL] ") (display label)
        (display " -> Expected: ") (write expected)
        (display " but got: ") (write actual) (newline)
        (error "Assertion failed:" label))))

(display "=======================================================") (newline)
(display " Starting Pass 050 (CP0 Optimization) Unit Test Suite") (newline)
(display "=======================================================") (newline)

;; 1. Arithmetic constant folding
(assert-equal "fold addition"
              30
              (cp0-optimize '(+ 10 20)))

(assert-equal "fold multiplication"
              42
              (cp0-optimize '(* 6 7)))

;; 2. Boolean & conditional reduction
(assert-equal "fold if-true branch"
              10
              (cp0-optimize '(if #t 10 20)))

(assert-equal "fold if-false branch"
              20
              (cp0-optimize '(if #f 10 20)))

;; 3. Primitive predicate folding
(assert-equal "fold zero?"
              #t
              (cp0-optimize '(zero? 0)))

;; 4. Dead Code Elimination (DCE) on letrec
(assert-equal "dce letrec eliminate unused binding"
              '(letrec ((f (lambda (x) (+ x 1)))) (f 10))
              (cp0-optimize '(letrec ((f (lambda (x) (+ x 1)))
                                      (g (lambda (y) (* y 2))))
                               (f 10))))

(assert-equal "dce letrec eliminate dead mutual recursion cycle"
              '(letrec ((live (lambda (z) (+ z 1)))) (live 5))
              (cp0-optimize '(letrec ((dead-a (lambda (x) (dead-b x)))
                                      (dead-b (lambda (y) (dead-a y)))
                                      (live (lambda (z) (+ z 1))))
                               (live 5))))

(assert-equal "dce letrec degenerate to body when all bindings unused"
              100
              (cp0-optimize '(letrec ((unused (lambda (x) (* x 2)))
                                      (val 42))
                               100)))

;; 5. Dead Code Elimination on let
(assert-equal "dce let eliminate dead pure bindings"
              '(let ((x 1)) x)
              (cp0-optimize '(let ((x 1) (y (+ 2 3))) x)))

(assert-equal "dce let degenerate to body when all bindings dead"
              42
              (cp0-optimize '(let ((dead1 10) (dead2 (+ 3 4))) 42)))

(display "=======================================================") (newline)
(display " Pass 050: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
