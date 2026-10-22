;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 029 (Dynamic Environment & Multiple Values)
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
(display " Starting Pass 029 (Dynamic & Values Desugaring) Unit Test") (newline)
(display "=======================================================") (newline)

;; 1. desugar-let-values
(let ((lv (desugar-let-values '(((a b) (values 1 2))) '((+ a b)))))
  (assert-true "desugar-let-values produces call-with-values" (pair? lv))
  (assert-equal "desugar-let-values root is call-with-values" 'call-with-values (car lv)))

;; 2. desugar-let*-values
(let ((lsv (desugar-let*-values '(((a b) (values 1 2)) ((c) 3)) '((+ a b c)))))
  (assert-true "desugar-let*-values produces call-with-values" (pair? lsv))
  (assert-equal "desugar-let*-values root is call-with-values" 'call-with-values (car lsv)))

;; 3. desugar-guard
(let ((g (desugar-guard '(e ((else 0))) '((/ 1 0)))))
  (assert-true "desugar-guard produces %with-handler" (pair? g))
  (assert-equal "desugar-guard root is %with-handler" '%with-handler (car g)))

;; 4. desugar-parameterize
(let ((p (desugar-parameterize '((param1 100)) '((do-something)))))
  (assert-true "desugar-parameterize produces let" (pair? p))
  (assert-equal "desugar-parameterize root is let" 'let (car p)))

;; 5. desugar-define-values
(let ((dv (desugar-define-values '(a b) '(values 1 2) '((+ a b)))))
  (assert-true "desugar-define-values produces let-values" (pair? dv))
  (assert-equal "desugar-define-values root is let-values" 'let-values (car dv)))

(let ((dv-single (desugar-define-values '(x) '(values 42) '())))
  (assert-true "desugar-define-values single produces call-with-values" (pair? dv-single))
  (assert-equal "desugar-define-values single root is call-with-values" 'call-with-values (car dv-single)))

(let ((dyn-res (desugar-dynamic '(begin (define-values (x y) (values 10 20)) (+ x y)))))
  (assert-true "desugar-dynamic expands begin define-values" (pair? dyn-res))
  (assert-equal "desugar-dynamic expands to call-with-values" 'call-with-values (car dyn-res)))

(display "=======================================================") (newline)
(display " Pass 029: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
