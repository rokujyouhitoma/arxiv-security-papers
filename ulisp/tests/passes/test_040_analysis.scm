;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 040 (Scope & Free Variable Analysis)
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
(display " Starting Pass 040 (Scope Analysis) Unit Test Suite") (newline)
(display "=======================================================") (newline)

;; 1. Open expression has free variables
(assert-equal "free vars in addition"
              '(x y)
              (free-vars '(+ x y) '()))

;; 2. Lambda parameter is bound
(assert-equal "bound parameter excluded"
              '(y)
              (free-vars '(lambda (x) (+ x y)) '()))

;; 3. Let-bound variable is bound
(assert-equal "let binding excluded"
              '(y)
              (free-vars '(let ((x 1)) (+ x y)) '()))

;; 4. Completely closed expression has 0 free vars
(assert-equal "closed lambda"
              '()
              (free-vars '(lambda (x) (+ x 1)) '()))

;; 5. Nested lambda shadowing
(assert-equal "shadowed lambda parameter"
              '()
              (free-vars '(lambda (x) (lambda (x) (+ x 1))) '()))

;; 6. Letrec mutual recursion free vars
(assert-equal "letrec internal self references bound"
              '(z)
              (free-vars '(letrec ((f (lambda (n) (if (= n 0) z (g (- n 1)))))
                                   (g (lambda (m) (f m))))
                            (f 10))
                         '()))

(display "=======================================================") (newline)
(display " Pass 040: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
