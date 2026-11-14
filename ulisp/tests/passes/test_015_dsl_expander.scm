;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 015 (Nanopass DSL Procedural Expander)
;;; Conforms to Issue #587 & Nanopass Architecture Quality Standard
;;; =======================================================================




(define (symbol-has-prefix? sym prefix)
  (and (symbol? sym)
       (let ((s (symbol->string sym))
             (p (symbol->string prefix)))
         (and (>= (string-length s) (string-length p))
              (string=? (substring s 0 (string-length p)) p)))))

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

;; 7. Expansion of define-picopass (Issue #758)
(let* ((forms '((define-picopass p015-rule-const
                  (Expr
                    (('quote ,c) (list 'const c))))))
       (expanded (expand-dsl-forms forms)))
  (assert-true "define-picopass produces list of definitions"
               (and (pair? expanded)
                    (pair? (car expanded))
                    (eq? (caar expanded) 'define)))
  (assert-true "define-picopass defines descriptor"
               (symbol-has-prefix? (cadar expanded) '__desc_p015-rule-const))
  (assert-true "define-picopass defines procedure"
               (and (pair? (cadr expanded))
                    (eq? (caadr expanded) 'define)
                    (eq? (car (cadadr expanded)) 'p015-rule-const)))
  ;; Verify compile-time rule registration
  (let ((desc (nanopass-lookup-rule 'p015-rule-const)))
    (assert-true "picopass registered in *nanopass-rules*" (rule-descriptor? desc))
    (assert-equal "picopass kind is 'pico" 'pico (rule-kind desc))
    (assert-equal "picopass head-tags is '(quote)" '(quote) (rule-head-tags desc))))

;; 8. Expansion of define-femtopass (Issue #758)
(let* ((forms '((define-femtopass p015-rule-count
                  (Expr : (depth) -> (count)
                    (('quote ,c) 1)
                    ((+ ,e1 ,e2) (+ (femto-recurse e1 (+ depth 1))
                                    (femto-recurse e2 (+ depth 1))))))))
       (expanded (expand-dsl-forms forms)))
  (assert-true "define-femtopass produces definitions"
               (and (pair? expanded)
                    (pair? (car expanded))
                    (eq? (caar expanded) 'define)))
  (assert-true "define-femtopass defines descriptor"
               (symbol-has-prefix? (cadar expanded) '__desc_p015-rule-count))
  (assert-true "define-femtopass defines procedure"
               (and (pair? (cadr expanded))
                    (eq? (caadr expanded) 'define)
                    (eq? (car (cadadr expanded)) 'p015-rule-count)))
  (let ((desc (nanopass-lookup-rule 'p015-rule-count)))
    (assert-true "femtopass registered in *nanopass-rules*" (rule-descriptor? desc))
    (assert-equal "femtopass kind is 'femto" 'femto (rule-kind desc))))

;; 9. Expansion of define-attopass (Issue #758)
(let* ((forms '((define-attopass p015-rule-check-var
                  (Expr
                    (,x (guard (symbol? x)) (picopass-fail "Raw variable not allowed" ir))))))
       (expanded (expand-dsl-forms forms)))
  (assert-true "define-attopass produces definitions"
               (and (pair? expanded)
                    (pair? (car expanded))
                    (eq? (caar expanded) 'define)))
  (assert-true "define-attopass defines descriptor"
               (symbol-has-prefix? (cadar expanded) '__desc_p015-rule-check-var))
  (assert-true "define-attopass defines procedure"
               (and (pair? (cadr expanded))
                    (eq? (caadr expanded) 'define)
                    (eq? (car (cadadr expanded)) 'p015-rule-check-var)))
  (let ((desc (nanopass-lookup-rule 'p015-rule-check-var)))
    (assert-true "attopass registered in *nanopass-rules*" (rule-descriptor? desc))
    (assert-equal "attopass kind is 'atto" 'atto (rule-kind desc))))

;; 10. Source location wrapper propagation (%source-loc) on define-picopass
(let* ((forms '((%source-loc "test_p015.scm" 42 7
                  (define-picopass p015-loc-rule
                    (Expr
                      ((const ,c) c))))))
       (expanded (expand-dsl-forms forms)))
  (assert-true "source-loc wrapped picopass produces source-loc items"
               (and (pair? expanded)
                    (eq? (caar expanded) '%source-loc)
                    (equal? (cadar expanded) "test_p015.scm")
                    (equal? (caddar expanded) 42)
                    (equal? (cadddr (car expanded)) 7)))
  (let ((desc (nanopass-lookup-rule 'p015-loc-rule)))
    (assert-true "source-loc picopass registered at compile-time" (rule-descriptor? desc))
    (assert-equal "source-loc picopass kind is 'pico" 'pico (rule-kind desc))))

(display "=======================================================") (newline)
(display " Pass 015: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
