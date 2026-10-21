;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 015 (Nanopass DSL Procedural Expander)
;;; Conforms to Issue #587 & Nanopass Architecture Quality Standard
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
(display " Starting Pass 015 (DSL Expander) Unit Test Suite") (newline)
(display "=======================================================") (newline)

;; 1. Pass-through of standard definitions and expressions
(let* ((forms '((define (square x) (* x x))
                (+ (square 4) 10)))
       (expanded (expand-dsl-forms forms)))
  (assert-equal "pass-through standard forms"
                '((define (square x) (* x x))
                  (+ (square 4) 10))
                expanded))

;; 2. Discarding of host-only define-macro forms
(let* ((forms '((define-macro (my-host-macro x) x)
                (define a 42)))
       (expanded (expand-dsl-forms forms)))
  (assert-equal "filter out define-macro"
                '((define a 42))
                expanded))

;; 3. Flattening of begin forms
(let* ((forms '((begin
                  (define x 1)
                  (define-macro (host-noop) #f)
                  (define y 2))
                (+ x y)))
       (expanded (expand-dsl-forms forms)))
  (assert-equal "flatten begin and filter define-macro"
                '((define x 1)
                  (define y 2)
                  (+ x y))
                expanded))

;; 4. Expansion of define-language
(let* ((forms '((define-language L_test_p015
                  (terminals
                    (symbol (x))
                    (fixnum (n)))
                  (Expr (e)
                    x
                    n
                    (+ e1 e2)))))
       (expanded (expand-dsl-forms forms)))
  ;; Output should contain language definition and grammar table
  (assert-true "define-language produces list of definitions"
               (and (pair? expanded)
                    (pair? (car expanded))
                    (eq? (caar expanded) 'define)))
  (assert-true "define-language defines __lang_L_test_p015"
               (eq? (cadar expanded) '__lang_L_test_p015)))

;; 5. Expansion of define-pass
(let* ((forms '((define-pass p015-identity : L_test_p015 (e) -> L_test_p015 ()
                  (Expr : Expr (e) -> Expr ()
                    ((+ ,e1 ,e2) `(+ ,e1 ,e2))
                    (,x x)
                    (,n n)))))
       (expanded (expand-dsl-forms forms)))
  (assert-true "define-pass produces procedure definition"
               (and (pair? expanded)
                    (pair? (car expanded))
                    (eq? (caar expanded) 'define)
                    (eq? (caadar expanded) 'p015-identity))))

;; 6. Expansion of define-parser and define-unparser
(let* ((forms '((define-parser parse-p015 L_test_p015)
                (define-unparser unparse-p015 L_test_p015)))
       (expanded (expand-dsl-forms forms)))
  (assert-true "define-parser produces define form"
               (and (pair? expanded)
                    (eq? (caar expanded) 'define)
                    (eq? (caadar expanded) 'parse-p015)))
  (assert-true "define-unparser produces define form"
               (and (pair? (cdr expanded))
                    (eq? (car (cadr expanded)) 'define)
                    (eq? (car (cadr (cadr expanded))) 'unparse-p015))))

(display "=======================================================") (newline)
(display " Pass 015: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
