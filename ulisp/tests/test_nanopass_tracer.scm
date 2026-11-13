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

;;; -----------------------------------------------------------------------
;;; 6. Unified Trace Hooks: Single AST Diff Emission (DSN-33-01 T1.3)
;;; -----------------------------------------------------------------------

;; 6.1 Direct standalone `trace-define-pass` call emits AST diff exactly once
(reset-nanopass-ast-diff-display-count!)
(disable-nanopass-trace!)
(let ((res (test-traced-desugar '(cond ((= a 1) 10) (else 20)))))
  (assert-equal "standalone trace-define-pass emits AST diff exactly once"
                1
                (nanopass-ast-diff-display-count)))

;; 6.2 Direct standalone `define-pass` with `(enable-nanopass-trace!)` emits AST diff exactly once
(reset-nanopass-ast-diff-display-count!)
(enable-nanopass-trace!)
(let ((res (test-valid-pass '(cond ((= a 1) 10) (else 20)))))
  (assert-equal "standalone define-pass with global trace enabled emits AST diff exactly once"
                1
                (nanopass-ast-diff-display-count)))
(disable-nanopass-trace!)

;; 6.3 Pipeline execution (`run-single-pass`) of a `define-pass` with `trace-mode = #t`
;;     and `(enable-nanopass-trace!)` emits AST diff exactly ONCE (never twice!)
(let ((pass-desc (make-pass-descriptor
                  'test-valid-pass
                  "Test Valid Pass"
                  'desugar
                  0
                  test-valid-pass
                  #f
                  'L_tracer_base
                  'L_tracer_mid
                  '()
                  #t)))
  (reset-nanopass-ast-diff-display-count!)
  (enable-nanopass-trace!)
  (let ((res (run-single-pass pass-desc '(cond ((= a 1) 10) (else 20)) #f #t)))
    (assert-equal "run-single-pass on define-pass with trace-mode=#t emits AST diff exactly once (no duplicate emission)"
                  1
                  (nanopass-ast-diff-display-count))
    (assert-false "nanopass-in-pipeline-runner? is restored to #f after run-single-pass"
                  (nanopass-in-pipeline-runner?)))
  (disable-nanopass-trace!))

;; 6.4 Pipeline execution (`run-single-pass`) of a `trace-define-pass` with `trace-mode = #t`
;;     also emits AST diff exactly ONCE
(let ((pass-desc (make-pass-descriptor
                  'test-traced-desugar
                  "Test Traced Desugar"
                  'desugar
                  0
                  test-traced-desugar
                  #f
                  'L_tracer_base
                  'L_tracer_mid
                  '()
                  #t)))
  (reset-nanopass-ast-diff-display-count!)
  (let ((res (run-single-pass pass-desc '(cond ((= a 1) 10) (else 20)) #f #t)))
    (assert-equal "run-single-pass on trace-define-pass with trace-mode=#t emits AST diff exactly once"
                  1
                  (nanopass-ast-diff-display-count))))

;;; -----------------------------------------------------------------------
;;; 7. Picopass Provenance Tracking & Fine-grained Firing History (DSN-33-01 T6.2)
;;; -----------------------------------------------------------------------

(display "\n--- [Section 7: Picopass Provenance Tracking & Firing History] ---\n")

;; 7.1 Provenance flags and control
(assert-false "picopass-provenance-enabled? initially #f"
              (picopass-provenance-enabled?))
(enable-picopass-provenance!)
(assert-true "enable-picopass-provenance! sets flag to #t"
             (picopass-provenance-enabled?))
(disable-picopass-provenance!)
(assert-false "disable-picopass-provenance! resets flag to #f"
              (picopass-provenance-enabled?))

;; 7.2 Manual recording and resetting
(enable-picopass-provenance!)
(reset-picopass-provenance!)
(assert-equal "initial firing counts is empty" '() (get-picopass-firing-counts))
(assert-equal "initial firing log is empty" '() (get-picopass-firing-log))

(record-picopass-firing! 'test-rule-alpha '(+ 1 2) 3)
(record-picopass-firing! 'test-rule-alpha '(+ 3 4) 7)
(record-picopass-firing! 'test-rule-beta '(* 2 5) 10)

(let ((counts (get-picopass-firing-counts)))
  (assert-equal "test-rule-alpha fired twice"
                2
                (cdr (assq 'test-rule-alpha counts)))
  (assert-equal "test-rule-beta fired once"
                1
                (cdr (assq 'test-rule-beta counts))))

(let ((log (get-picopass-firing-log)))
  (assert-equal "firing log records 3 events" 3 (length log))
  (assert-equal "first log rule is test-rule-alpha" 'test-rule-alpha (caar log)))

(reset-picopass-provenance!)
(assert-equal "reset-picopass-provenance! clears counts" '() (get-picopass-firing-counts))
(assert-equal "reset-picopass-provenance! clears log" '() (get-picopass-firing-log))
(disable-picopass-provenance!)

;; 7.3 Integration test: define-picopass + fuse-rules firing count tracking
(define-picopass rule-trace-add-zero
  (Expr
    ((+ ,e 0) e)))

(define-picopass rule-trace-mul-one
  (Expr
    ((* ,e 1) e)))

(define-pass test-pass-provenance-fuse : L_tracer_base (ir) -> L_tracer_base ()
  (entry Expr)
  (fuse-rules
    rule-trace-add-zero
    rule-trace-mul-one))

;; Run with provenance DISABLED: counts should remain empty
(reset-picopass-provenance!)
(disable-picopass-provenance!)
(let ((res (test-pass-provenance-fuse '(list (+ x 0) (* y 1) (+ z 0)))))
  (assert-equal "pass output transformed correctly with provenance disabled"
                '(list x y z)
                res)
  (assert-equal "firing counts empty when provenance disabled"
                '()
                (get-picopass-firing-counts)))

;; Run with provenance ENABLED: counts should track rule firings
(reset-picopass-provenance!)
(enable-picopass-provenance!)
(let ((res (test-pass-provenance-fuse '(list (+ a 0) (* b 1) (+ c 0) (* d 1)))))
  (assert-equal "pass output transformed correctly with provenance enabled"
                '(list a b c d)
                res)
  (let ((counts (get-picopass-firing-counts)))
    (assert-equal "rule-trace-add-zero recorded 2 hits"
                  2
                  (cdr (assq 'rule-trace-add-zero counts)))
    (assert-equal "rule-trace-mul-one recorded 2 hits"
                  2
                  (cdr (assq 'rule-trace-mul-one counts)))))

;; 7.4 Display AST diff with Picopass Firings
(reset-nanopass-ast-diff-display-count!)
(nanopass-display-ast-diff 'test-pass-provenance-fuse
                          '(list (+ a 0) (* b 1) (+ c 0) (* d 1))
                          '(list a b c d))
(assert-equal "nanopass-display-ast-diff with firings increments display count"
              1
              (nanopass-ast-diff-display-count))

(reset-picopass-provenance!)
(disable-picopass-provenance!)

(display "=======================================================") (newline)
(display " Nanopass Phase 4: All ")
(display *tracer-tests-passed*)
(display " tests passed!") (newline)
(display "=======================================================") (newline)
