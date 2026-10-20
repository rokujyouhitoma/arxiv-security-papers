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

(display "=======================================================") (newline)
(display " Nanopass Framework: All ")
(display *nanopass-tests-passed*)
(display " tests passed!") (newline)
(display "=======================================================") (newline)
