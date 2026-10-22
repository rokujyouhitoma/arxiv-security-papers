;;; =======================================================================
;;; Unit Test Suite: ULisp Nanopass Framework DSL (Phase 1)
;;; Conforms to Issue #581 & Keep & Dybvig (2013) Specification
;;; =======================================================================

(define *nanopass-tests-passed* 0)
(define *nanopass-tests-failed* 0)

(define (assert-equal label expected actual)
  (if (equal? expected actual)
      (begin
        (set! *nanopass-tests-passed* (+ *nanopass-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (set! *nanopass-tests-failed* (+ *nanopass-tests-failed* 1))
        (display "  [FAIL] ") (display label)
        (display " -> Expected: ") (write expected)
        (display " but got: ") (write actual) (newline)
        (error "Assertion failed:" label))))

(define (assert-true label cond)
  (assert-equal label #t (if cond #t #f)))

(define (assert-false label cond)
  (assert-equal label #f (if cond #t #f)))

(display "=======================================================") (newline)
(display " Starting Nanopass Framework DSL Unit Test Suite") (newline)
(display "=======================================================") (newline)

;;; -----------------------------------------------------------------------
;;; Host / Interpreter Macros (for ilisp and test environments)
;;; -----------------------------------------------------------------------
(define-macro (define-language . args)
  (nanopass-expand-define-language (cons 'define-language args)))

(define-macro (define-pass . args)
  (nanopass-expand-define-pass (cons 'define-pass args)))

(define-macro (define-parser . args)
  (nanopass-expand-define-parser (cons 'define-parser args)))

(define-macro (define-unparser . args)
  (nanopass-expand-define-unparser (cons 'define-unparser args)))

(define-macro (in-context . args)
  (if (= (length args) 2)
      (list (car args) (cadr args))
      (list 'nanopass-parse-nt (list 'quote (car args)) (caddr args) (list 'quote (cadr args)))))

(define-macro (nanopass-template . args)
  (nanopass-expand-template (car args) '()))

;;; -----------------------------------------------------------------------
;;; 1. define-language & Language Reflection
;;; -----------------------------------------------------------------------

(define-language L_test_src
  (terminals
    (symbol (x))
    (constant (c)))
  (Expr (e)
    x
    c
    (quote datum)
    (if e1 e2 e3)
    (cond (e1 e2) ... (else e_else))
    (let ((x e1) ...) e2)
    (e0 e1 ...)))

(assert-true "L_test_src is registered"
             (nanopass-language? (nanopass-lookup-language 'L_test_src)))

(let ((s-exp (language->s-expression 'L_test_src)))
  (assert-equal "language->s-expression root" 'language (car s-exp))
  (assert-equal "language->s-expression name" 'L_test_src (cadr s-exp)))

(assert-true "L_test_src? symbol" (L_test_src? 'foo))
(assert-true "L_test_src? number" (L_test_src? 42))
(assert-true "L_test_src? if expr" (L_test_src? '(if #t 1 2)))
(assert-true "L_test_src? cond expr" (L_test_src? '(cond ((= a 1) 10) (else 20))))
(assert-true "L_test_src? call expr" (L_test_src? '(+ 1 2)))

;;; -----------------------------------------------------------------------
;;; 2. Language Derivation via `extends` and Invariant Diffs
;;; -----------------------------------------------------------------------

(define-language L_test_core
  (extends L_test_src)
  (Expr (e)
    (- (cond (e1 e2) ... (else e_else)))
    (+ (core-op e1 e2))))

(assert-true "L_test_core? if expr" (L_test_core? '(if #t 1 2)))
(assert-true "L_test_core? core-op" (L_test_core? '(core-op 1 2)))

;; Verification of removed invariant: cond is removed from L_test_core!
(assert-false "L_test_core? rejects removed cond"
              (L_test_core? '(cond ((= a 1) 10) (else 20))))

(let ((diff (language-diff 'L_test_src 'L_test_core)))
  (assert-true "language-diff removed has cond"
               (let ((rm (cadr (assq 'removed diff))))
                 (and (pair? rm) (eq? (caar rm) 'cond))))
  (assert-true "language-diff added has core-op"
               (let ((add (cadr (assq 'added diff))))
                 (and (pair? add) (eq? (caar add) 'core-op)))))

;;; -----------------------------------------------------------------------
;;; 3. define-parser & define-unparser
;;; -----------------------------------------------------------------------

(define-parser parse-src L_test_src)
(define-parser parse-core L_test_core)
(define-unparser unparse-core L_test_core)

(assert-equal "parse-src accepts cond"
              '(cond ((= a 1) 10) (else 20))
              (parse-src '(cond ((= a 1) 10) (else 20))))

(assert-equal "unparse-core preserves ir"
              '(if #t 1 2)
              (unparse-core '(if #t 1 2)))

;;; -----------------------------------------------------------------------
;;; 4. define-pass & Catamorphism Traversal Synthesis
;;; -----------------------------------------------------------------------

;; Pass that desugars cond into if
(define-pass desugar-test-cond : L_test_src (ir) -> L_test_core ()
  (Expr : Expr (ir) -> Expr ()
    ((cond (else . ,bodies))
     (cons 'begin (map Expr bodies)))
    ((cond (,test . ,bodies) . ,rest)
     (list 'if (Expr test)
           (cons 'begin (map Expr bodies))
           (Expr (cons 'cond rest))))))

(assert-equal "desugar-test-cond simple cond"
              '(if (= a 1) (begin 10) (begin 20))
              (desugar-test-cond '(cond ((= a 1) 10) (else 20))))

;; Test automatic Catamorphism synthesis across untouched constructs (let, if, calls):
(assert-equal "desugar-test-cond nested in let and if"
              '(let ((x 1)) (if x (if (= a 1) (begin 10) (begin 20)) 99))
              (desugar-test-cond '(let ((x 1)) (if x (cond ((= a 1) 10) (else 20)) 99))))

;; Verify output of pass conforms to target language L_test_core
(assert-true "desugar-test-cond output is valid L_test_core"
             (L_test_core? (desugar-test-cond '(let ((x 1)) (if x (cond ((= a 1) 10) (else 20)) 99)))))

;;; -----------------------------------------------------------------------
;;; 5. define-pass with Guards
;;; -----------------------------------------------------------------------

(define-pass guard-test-pass : L_test_src (ir) -> L_test_src ()
  (Expr : Expr (ir) -> Expr ()
    ((special ,x) (guard (number? x))
     (list 'special-number (* x 2)))
    ((special ,x)
     (list 'special-other x))))

(assert-equal "guard matches number branch"
              '(special-number 84)
              (guard-test-pass '(special 42)))

(assert-equal "guard falls through to second branch on non-number"
              '(special-other "hello")
              (guard-test-pass '(special "hello")))

;;; -----------------------------------------------------------------------
;;; 6. Canonical L_src and L_core Standard Pipeline Verification
;;; -----------------------------------------------------------------------

(assert-true "Canonical L_src recognizes high-level forms"
             (L_src? '(let* ((x 1) (y 2)) (and x y))))

(assert-false "Canonical L_core rejects un-desugared forms"
              (L_core? '(let* ((x 1) (y 2)) (and x y))))

(assert-true "Canonical L_core accepts canonical core forms"
             (L_core? '(let ((x 1)) (let ((y 2)) (if x y #f)))))

;;; -----------------------------------------------------------------------
;;; 7. Ellipsis (...) Pattern Matching & Template Splice Reconstruction
;;; -----------------------------------------------------------------------

;; Pass that matches let bindings via ellipsis and rewrites them
(define-pass test-ellipsis-let : L_test_src (ir) -> L_test_src ()
  (Expr : Expr (ir) -> Expr ()
    ((let ((,x* ,e*) ...) ,body)
     `(let ((,x* (* ,e* 2)) ...) ,body))))


(assert-equal "test-ellipsis-let unpacks and reconstructs multiple bindings"
              '(let ((a (* 10 2)) (b (* 20 2))) (+ a b))
              (test-ellipsis-let '(let ((a 10) (b 20)) (+ a b))))

(assert-equal "test-ellipsis-let handles empty bindings list"
              '(let () 42)
              (test-ellipsis-let '(let () 42)))

;; Trailing elements after ellipsis: (foo ,x ... ,y)
(define-pass test-ellipsis-trailing : L_test_src (ir) -> L_test_src ()
  (Expr : Expr (ir) -> Expr ()
    ((sum-last ,x ... ,y)
     (list 'result-sum (cons 'list x) y))))

(assert-equal "test-ellipsis-trailing matches prefix list and tail element"
              '(result-sum (list 1 2 3) 4)
              (test-ellipsis-trailing '(sum-last 1 2 3 4)))

(assert-equal "test-ellipsis-trailing matches empty prefix with tail"
              '(result-sum (list) 99)
              (test-ellipsis-trailing '(sum-last 99)))

;; Template splice with ellipsis: (result ,(map ...) ...)
(define-pass test-template-splice : L_test_src (ir) -> L_test_src ()
  (Expr : Expr (ir) -> Expr ()
    ((double-all ,x* ...)
     `(result ,(map (lambda (x) (* x 2)) x*) ...))))

(assert-equal "test-template-splice expands ellipsis in output template"
              '(result 2 4 6)
              (test-template-splice '(double-all 1 2 3)))

;; Nested ellipsis: ((,x ...) ...)
(let ((m (nanopass-match-pattern-inner '((,x ...) ...) '((1 2) (3 4 5) ()) (lambda (x) x))))
  (assert-true "nested ellipsis matches list of lists" (and (pair? m) (car m)))
  (assert-equal "nested ellipsis binds multi-level list"
                '((1 2) (3 4 5) ())
                (cdr (assq 'x (cdr m)))))

;;; -----------------------------------------------------------------------
;;; 8. Subform Local Handlers (in-context) and Multi-Nonterminal Passes
;;; -----------------------------------------------------------------------

(define-language L_test_prog
  (terminals
    (symbol (x))
    (constant (c)))
  (Program (p)
    (%program (d ...) e))
  (Def (d)
    (define x e))
  (Expr (e)
    x
    c
    (if e1 e2 e3)
    (+ e1 e2)
    (e0 e1 ...)))

(define-pass test-multi-nt-pass : L_test_prog (ir) -> L_test_prog ()
  (entry Program)
  (Program : Program (ir) -> Program ()
    ((%program ,defs ,main)
     (list '%program
           (map (lambda (d) (in-context Def d)) defs)
           (in-context Expr main))))
  (Def : Def (ir) -> Def ()
    ((define ,x ,e)
     (list 'define x (in-context Expr e))))
  (Expr : Expr (ir) -> Expr ()
    ((+ ,a ,b)
     (list '+ (in-context Expr a) (in-context Expr b)))
    (,c (guard (number? c))
     (* c 10))))

(let* ((input '(%program ((define val 5) (define base 2)) (+ 5 2)))
       (res (test-multi-nt-pass input)))
  (assert-equal "in-context transforms subforms at Program, Def, and Expr levels"
                '(%program ((define val 50) (define base 20)) (+ 50 20))
                res))

;;; -----------------------------------------------------------------------
;;; 9. Extra Values: Downwards Inherited Attributes
;;; -----------------------------------------------------------------------

(define-pass test-inherited-depth : L_test_src (ir depth) -> L_test_src ()
  (Expr : Expr (ir depth) -> Expr ()
    (,c (guard (number? c))
     (+ c depth))
    ((+ ,a ,b)
     (list '+ (Expr a (+ depth 1)) (Expr b (+ depth 1))))))

(assert-equal "test-inherited-depth propagates depth downward"
              '(+ 12 22)
              (test-inherited-depth '(+ 1 11) 10))

;;; -----------------------------------------------------------------------
;;; 10. Extra Values: Pure Analyzer with Synthesized Accumulator (*)
;;; -----------------------------------------------------------------------

(define-pass test-count-symbols : L_test_src (ir acc) -> * (acc)
  (Expr : Expr (ir acc) -> * (acc)
    (,x (guard (symbol? x))
     (+ acc 1))
    (,c (guard (number? c))
     acc)))

(assert-equal "test-count-symbols counts symbols across subnodes"
              3
              (test-count-symbols '(+ x (* y z)) 0))

;;; -----------------------------------------------------------------------
;;; 11. Extra Values: Free Variable Analysis with Bound and Acc (*)
;;; -----------------------------------------------------------------------

(define-pass test-analyze-frees : L_test_src (ir bound acc) -> * (acc)
  (Expr : Expr (ir bound acc) -> * (acc)
    ((quote ,datum)
     acc)
    (,x (guard (symbol? x))
     (if (or (memq x bound) (memq x acc))
         acc
         (cons x acc)))
    ((lambda (,params ...) ,body)
     (Expr body (append params bound) acc))
    ((let ((,x* ,e*) ...) ,body)
     (let* ((new-acc (let loop ((es e*) (cur-acc acc))
                       (if (null? es)
                           cur-acc
                           (loop (cdr es) (Expr (car es) bound cur-acc)))))
            (new-bound (append x* bound)))
       (Expr body new-bound new-acc)))))

(assert-equal "test-analyze-frees captures free variables"
              '(c a)
              (test-analyze-frees '(let ((x a) (y 1)) (+ x b ((lambda (z) (+ z c)) 2))) '(b) '()))

(display "=======================================================") (newline)
(display " Nanopass Framework: All ")
(display *nanopass-tests-passed*)
(display " tests passed!") (newline)
(display "=======================================================") (newline)

