;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 028 (Bindings Desugaring)
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
(display " Starting Pass 028 (Bindings Desugaring) Unit Test") (newline)
(display "=======================================================") (newline)

;; 1. make-body-expr
(assert-equal "make-body-expr empty"
              '(begin)
              (make-body-expr '()))

(assert-equal "make-body-expr 1 expr"
              42
              (make-body-expr '(42)))

(assert-equal "make-body-expr multi exprs"
              '(begin 1 2 3)
              (make-body-expr '(1 2 3)))

;; 2. desugar-let*
(assert-equal "desugar-let* empty bindings"
              '(+ 1 2)
              (desugar-let* '() '((+ 1 2))))

(assert-equal "desugar-let* nested let"
              '(let ((x 1)) (let ((y 2)) (+ x y)))
              (desugar-let* '((x 1) (y 2)) '((+ x y))))

;; 3. desugar-named-let
(let ((nlet (desugar-named-let '(let loop ((n 10)) (if (= n 0) 0 (loop (- n 1)))))))
  (assert-true "desugar-named-let produces letrec" (pair? nlet))
  (assert-equal "desugar-named-let root is letrec" 'letrec (car nlet)))

(display "=======================================================") (newline)
(display " Pass 028: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
