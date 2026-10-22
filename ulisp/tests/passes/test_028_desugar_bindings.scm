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

;; 4. desugar-do
(let ((do-res (desugar-do '((i 0 (+ i 1))) '((= i 10) i) '())))
  (assert-true "desugar-do produces named let" (pair? do-res))
  (assert-equal "desugar-do root is let" 'let (car do-res))
  (assert-equal "desugar-do init bindings" '((i 0)) (caddr do-res)))

;; 5. desugar-do step omitted
(let ((do-res (desugar-do '((i 0 (+ i 1)) (x 42)) '((= i 10) x) '())))
  (assert-equal "desugar-do step omitted bindings" '((i 0) (x 42)) (caddr do-res))
  ;; Check else branch passes x unchanged
  (let* ((if-expr (cadddr do-res))
         (else-expr (cadddr if-expr)))
    (assert-equal "desugar-do step omitted else call" 'x (caddr else-expr))))

;; 6. desugar-do multi commands
(let ((do-res (desugar-do '((i 0 (+ i 1))) '((= i 5) #t) '((display i) (newline)))))
  (let* ((if-expr (cadddr do-res))
         (else-expr (cadddr if-expr)))
    (assert-equal "desugar-do multi commands else is begin" 'begin (car else-expr))))

;; 7. desugar-bindings do
(let ((expanded (desugar-bindings '(do ((i 0 (+ i 1))) ((= i 10) i)))))
  (assert-true "desugar-bindings do expands to letrec" (pair? expanded))
  (assert-equal "desugar-bindings do root is letrec" 'letrec (car expanded)))

(display "=======================================================") (newline)
(display " Pass 028: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
