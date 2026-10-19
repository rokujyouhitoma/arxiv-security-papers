;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 027 (Conditionals Desugaring)
;;; Conforms to Issue #574 & Nanopass Architecture Quality Standard
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

(define (assert-true label cond)
  (assert-equal label #t (if cond #t #f)))

(display "=======================================================") (newline)
(display " Starting Pass 027 (Conditionals Desugaring) Unit Test") (newline)
(display "=======================================================") (newline)

;; 1. desugar-and
(assert-equal "desugar-and empty"
              #t
              (desugar-and '()))

(assert-equal "desugar-and 1 arg"
              42
              (desugar-and '(42)))

(assert-equal "desugar-and 2 args"
              '(if #t 42 #f)
              (desugar-and '(#t 42)))

;; 2. desugar-or
(assert-equal "desugar-or empty"
              #f
              (desugar-or '()))

(assert-equal "desugar-or 1 arg"
              42
              (desugar-or '(42)))

(let ((res (desugar-or '(#f 42))))
  (assert-true "desugar-or 2 args produces let" (pair? res))
  (assert-equal "desugar-or root is let" 'let (car res)))

;; 3. desugar-cond
(assert-equal "desugar-cond empty"
              #f
              (desugar-cond '()))

(assert-equal "desugar-cond with else"
              '(if (= 1 2) (begin 10) (begin 20))
              (desugar-cond '(((= 1 2) 10) (else 20))))

;; 4. desugar-case
(let ((case-res (desugar-case 'x '(((1 2) (display "one or two")) (else (display "other"))))))
  (assert-true "desugar-case produces let" (pair? case-res))
  (assert-equal "desugar-case root is let" 'let (car case-res)))

(display "=======================================================") (newline)
(display " Pass 027: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
