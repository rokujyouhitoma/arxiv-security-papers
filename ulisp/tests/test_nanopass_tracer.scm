;;; =======================================================================
;;; Unit Test Suite: ULisp Nanopass Framework DSL (Phase 4)
;;; Observability, AST Diff Tracer, and Invariant Verifier Hooks
;;; Conforms to Issue #586 & Keep & Dybvig (2013) Specification
;;; =======================================================================

(define *tracer-tests-passed* 0)
(define *tracer-tests-failed* 0)

(define (assert-equal label expected actual)
  (if (equal? expected actual)
      (begin
        (set! *tracer-tests-passed* (+ *tracer-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (set! *tracer-tests-failed* (+ *tracer-tests-failed* 1))
        (display "  [FAIL] ") (display label)
        (display " -> Expected: ") (write expected)
        (display " but got: ") (write actual) (newline)
        (error "Assertion failed:" label))))

(define (assert-true label cond)
  (assert-equal label #t (if cond #t #f)))

(define (assert-false label cond)
  (assert-equal label #f (if cond #t #f)))

(display "=======================================================") (newline)
(display " Starting Nanopass Phase 4 Tracer & Verifier Test Suite") (newline)
(display "=======================================================") (newline)

;;; Host Macros for Test Environment
(define-macro (define-language . args)
  (nanopass-expand-define-language (cons 'define-language args)))

(define-macro (define-pass . args)
  (nanopass-expand-define-pass (cons 'define-pass args)))

(define-macro (trace-define-pass . args)
  (nanopass-expand-trace-define-pass (cons 'trace-define-pass args)))

;;; -----------------------------------------------------------------------
;;; 1. Language Metainfo & Inheritance Reflection
;;; -----------------------------------------------------------------------

(define-language L_tracer_base
  (terminals
    (symbol (x))
    (constant (c)))
  (Expr (e)
    x
    c
    (if e1 e2 e3)
    (cond (e1 e2) ... (else e_else))
    (e0 e1 ...)))

(define-language L_tracer_mid
  (extends L_tracer_base)
  (Expr (e)
    (- (cond (e1 e2) ... (else e_else)))
    (+ (case-mid e1 e2))))

(define-language L_tracer_target
  (extends L_tracer_mid)
  (Expr (e)
    (- (case-mid e1 e2))
    (+ (core-target e1))))

(assert-true "nanopass-get-all-languages includes registered languages"
             (let ((all-langs (nanopass-get-all-languages)))
               (and (memq 'L_tracer_base all-langs)
                    (memq 'L_tracer_mid all-langs)
                    (memq 'L_tracer_target all-langs))))

(assert-equal "language-parent-chain traces full inheritance hierarchy"
              '(L_tracer_base L_tracer_mid L_tracer_target)
              (language-parent-chain 'L_tracer_target))

(let ((decl (language-declaration 'L_tracer_target)))
  (assert-equal "language-declaration root symbol" 'language-declaration (car decl))
  (assert-equal "language-declaration target name" 'L_tracer_target (cadr decl))
  (assert-equal "language-declaration parent" '(parent L_tracer_mid) (caddr decl))
  (assert-true "language-declaration removed contains case-mid"
               (let ((rm-clause (assq 'removed (cddr decl))))
                 (and rm-clause (memq 'case-mid (cdr rm-clause))))))

;;; -----------------------------------------------------------------------
;;; 2. Structural AST Diff Engine
;;; -----------------------------------------------------------------------

;; Identical expressions have no diff (#f)
(assert-equal "nanopass-ast-diff identical atoms"
              #f
              (nanopass-ast-diff 42 42))

(assert-equal "nanopass-ast-diff identical trees"
              #f
              (nanopass-ast-diff '(if (= x 1) 10 20) '(if (= x 1) 10 20)))

;; Modified atom
(assert-equal "nanopass-ast-diff modified atom"
              '(diff:modified foo bar)
              (nanopass-ast-diff 'foo 'bar))

;; Preserving tree context while pinpointing localized subnode changes
(let ((diff (nanopass-ast-diff '(let ((x 1)) (cond ((= a 1) 10) (else 20)))
                               '(let ((x 1)) (if (= a 1) (begin 10) (begin 20))))))
  (assert-equal "nanopass-ast-diff preserves outer let head" 'let (car diff))
  (assert-equal "nanopass-ast-diff preserves unchanged bindings" '((x 1)) (cadr diff))
  (assert-equal "nanopass-ast-diff flags localized rewrite"
                '(diff:modified (cond ((= a 1) 10) (else 20)) (if (= a 1) (begin 10) (begin 20)))
                (caddr diff)))

;;; -----------------------------------------------------------------------
;;; 3. Global Trace Configuration & Step Tracer
;;; -----------------------------------------------------------------------

(assert-false "nanopass-trace-enabled? initially #f" (nanopass-trace-enabled?))

(enable-nanopass-trace!)
(assert-true "enable-nanopass-trace! sets flag to #t" (nanopass-trace-enabled?))

(disable-nanopass-trace!)
(assert-false "disable-nanopass-trace! resets flag to #f" (nanopass-trace-enabled?))

;; Define pass with trace-define-pass (forces tracing regardless of global flag)
(trace-define-pass test-traced-desugar : L_tracer_base (ir) -> L_tracer_mid ()
  (Expr : Expr (ir) -> Expr ()
    ((cond (else . ,bodies))
     (cons 'begin (map Expr bodies)))
    ((cond (,test . ,bodies) . ,rest)
     (list 'if (Expr test)
           (cons 'begin (map Expr bodies))
           (Expr (cons 'cond rest))))))

(display "\n>>> [DEMO] Testing trace-define-pass output below:") (newline)
(let ((result (test-traced-desugar '(cond ((= a 1) 10) (else 20)))))
  (assert-equal "test-traced-desugar returns correctly transformed AST"
                '(if (= a 1) (begin 10) (begin 20))
                result))

;;; -----------------------------------------------------------------------
;;; 4. Invariant Verifier Hooks & Fail-Fast Assertion
;;; -----------------------------------------------------------------------

(assert-false "nanopass-verifier-enabled? initially #f" (nanopass-verifier-enabled?))

;; Legitimate pass producing valid L_tracer_mid
(define-pass test-valid-pass : L_tracer_base (ir) -> L_tracer_mid ()
  (Expr : Expr (ir) -> Expr ()
    ((cond (else . ,bodies))
     (cons 'begin (map Expr bodies)))
    ((cond (,test . ,bodies) . ,rest)
     (list 'if (Expr test)
           (cons 'begin (map Expr bodies))
           (Expr (cons 'cond rest))))))

;; Faulty pass that intentionally emits removed `cond` into L_tracer_mid (violates language invariant!)
(define-pass test-faulty-pass : L_tracer_base (ir) -> L_tracer_mid ()
  (Expr : Expr (ir) -> Expr ()
    ((bad-node ,x)
     (list 'cond (list '(= x 1) 10) (list 'else 20)))))

;; Without verifier enabled, faulty pass does not raise invariant error
(disable-nanopass-verifier!)
(assert-equal "faulty pass executes unverified when disabled"
              '(cond ((= x 1) 10) (else 20))
              (test-faulty-pass '(bad-node 5)))

;; When verifier is enabled:
(enable-nanopass-verifier!)
(assert-true "nanopass-verifier-enabled? is #t" (nanopass-verifier-enabled?))

;; Valid pass still executes cleanly with verifier hook enabled
(assert-equal "valid pass passes verifier hooks successfully"
              '(if (= a 1) (begin 10) (begin 20))
              (test-valid-pass '(cond ((= a 1) 10) (else 20))))

;; Faulty pass must trigger invariant violation and fail fast!
(display "\n>>> [DEMO] Verifier Hook correctly catching invariant violation:") (newline)
(let ((caught?
       (guard (ex
               (else #t))
         (test-faulty-pass '(bad-node 5))
         #f)))
  (assert-true "verifier hook caught language invariant violation and aborted" caught?))

(disable-nanopass-verifier!)

;;; -----------------------------------------------------------------------
;;; 5. Integration with Lightweight IR Verifier (verifier.scm)
;;; -----------------------------------------------------------------------

(enable-verifier!)
(assert-true "enable-verifier! activates nanopass verifier hook"
             (nanopass-verifier-enabled?))
(assert-true "enable-verifier! activates IR verifier"
             (verifier-enabled?))

(disable-verifier!)
(assert-false "disable-verifier! deactivates nanopass verifier hook"
              (nanopass-verifier-enabled?))
(assert-false "disable-verifier! deactivates IR verifier"
              (verifier-enabled?))

(assert-true "nanopass-verify-pass-data validates valid desugared AST"
             (nanopass-verify-pass-data 'desugar 'L_core '(let ((x 1)) (+ x 2)) 'exit))

(display "=======================================================") (newline)
(display " Nanopass Phase 4: All ")
(display *tracer-tests-passed*)
(display " tests passed!") (newline)
(display "=======================================================") (newline)
