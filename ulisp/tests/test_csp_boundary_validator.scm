;;; =======================================================================
;;; Test Suite: CSP Boundary Validator & Dual-Span Diagnostic Reporter
;;; Conforms to DSN-33-03 §4.2, §4.3, DSN-33-02 §3.4 & Issue #876
;;; =======================================================================

(display "\n=== [Test Suite: CSP Boundary Validator & Dual Span Diagnostics (Issue #876)] ===\n")

;;; Helper to extract an entry from an assoc list
(define (test-assoc-get key alist)
  (let ((entry (assq key alist)))
    (if entry (cdr entry) #f)))

;;; Helper to extract diagnostic fields
(define (diag-field diag key)
  (let loop ((entries (cdr diag)))
    (cond
      ((null? entries) #f)
      ((and (pair? (car entries)) (eq? (caar entries) key))
       (if (null? (cdar entries))
           #f
           (cadar entries)))
      (else (loop (cdr entries))))))

(define (diag-subfield diag key subkey)
  (let ((field (diag-field diag key)))
    (if (and (pair? field) (pair? (car field)))
        (let ((entry (assq subkey field)))
          (if entry (cdr entry) #f))
        #f)))

;;; -----------------------------------------------------------------------
;;; Group 1: CSP Predicates & Lift Classification
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: CSP Predicates & Lift Classification ---\n")

;; 1.1 Pure Literals and Static Values
(assert-equal "1.1 Numbers are valid lift targets" #t (csp-valid-lift-target? 42))
(assert-equal "1.1 Booleans are valid lift targets" #t (csp-valid-lift-target? #t))
(assert-equal "1.1 Strings are valid lift targets" #t (csp-valid-lift-target? "hello"))
(assert-equal "1.1 Symbols are valid lift targets" #t (csp-valid-lift-target? 'my-sym))
(assert-equal "1.1 Null is valid lift target" #t (csp-valid-lift-target? '()))
(assert-equal "1.1 Pure pairs are valid lift targets" #t (csp-valid-lift-target? '(1 2 3)))

;; 1.2 Mutable Box Detection
(let ((m-box (cons '%box (cons 100 '()))))
  (assert-equal "1.2 Mutable box is detected" 'illegal-mutable-lift (csp-classify-lift-violation m-box))
  (assert-equal "1.2 Mutable box invalidates lift" #f (csp-valid-lift-target? m-box)))

;; 1.3 Continuation Detection
(let ((k-obj (cons '%continuation (cons 'stack '()))))
  (assert-equal "1.3 Continuation is detected" 'illegal-continuation-lift (csp-classify-lift-violation k-obj))
  (assert-equal "1.3 Continuation invalidates lift" #f (csp-valid-lift-target? k-obj)))

;; 1.4 Opaque Procedure Detection
(let ((proc (lambda (x) (+ x 1))))
  (assert-equal "1.4 Host procedure is detected" 'illegal-procedure-lift (csp-classify-lift-violation proc))
  (assert-equal "1.4 Procedure invalidates lift" #f (csp-valid-lift-target? proc)))

;; 1.5 Deep Nested Mutable Object
(let ((nested-list (list 1 2 (cons '%box (cons 99 '())) 4)))
  (assert-equal "1.5 Nested mutable cell is detected" 'illegal-mutable-lift (csp-classify-lift-violation nested-list))
  (assert-equal "1.5 Nested mutable cell invalidates lift" #f (csp-valid-lift-target? nested-list)))

;;; -----------------------------------------------------------------------
;;; Group 2: DSN-33-03 §4.3 Structured compiler-diagnostic S-Expression
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: DSN-33-03 §4.3 compiler-diagnostic S-Expression ---\n")

(let* ((later-d (make-later-dict))
       (box-val (cons '%box (cons 42 '())))
       (err (later-dict-lift-val later-d box-val #f)))
  (assert-equal "2.1 Lifting box triggers stage-csp-error" #t (stage-csp-error? err))
  (assert-equal "2.1 Error reason is illegal-mutable-lift" 'illegal-mutable-lift (stage-csp-error-reason err))

  (let ((diag (stage-csp-error-diagnostic err)))
    (assert-equal "2.2 S-expr tag is compiler-diagnostic" 'compiler-diagnostic (car diag))
    (assert-equal "2.2 Version is 1.0" "1.0" (diag-field diag 'version))
    (assert-equal "2.2 Severity is error" 'error (diag-field diag 'severity))
    (assert-equal "2.2 Phase is bta-csp-guard" "bta-csp-guard" (diag-field diag 'phase))
    (assert-equal "2.2 Rule is CSP-001" "CSP-001-ILLEGAL-MUTABLE-LIFT" (diag-field diag 'rule))
    (assert-equal "2.2 Message describes prohibited mutable lift"
                  "Prohibited cross-stage lift of mutable object to residual code."
                  (diag-field diag 'message))
    (assert-equal "2.2 Remediation advises immutable values"
                  "Use immutable values or explicit runtime bump-pointer allocation."
                  (diag-field diag 'remediation))))

;; 2.3 Continuation Diagnostic
(let* ((later-d (make-later-dict))
       (k-val (cons '%continuation (cons 'cont '())))
       (err (later-dict-lift-val later-d k-val #f))
       (diag (stage-csp-error-diagnostic err)))
  (assert-equal "2.3 Continuation rule is CSP-002" "CSP-002-ILLEGAL-CONTINUATION-LIFT" (diag-field diag 'rule)))

;; 2.4 Opaque Procedure Diagnostic
(let* ((later-d (make-later-dict))
       (proc-val (lambda (y) (* y 2)))
       (err (later-dict-lift-val later-d proc-val #f))
       (diag (stage-csp-error-diagnostic err)))
  (assert-equal "2.4 Procedure rule is CSP-003" "CSP-003-OPAQUE-PROCEDURE-LIFT" (diag-field diag 'rule)))

;;; -----------------------------------------------------------------------
;;; Group 3: Dual Source Span Provenance (guest-span & host-span)
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Dual Source Span Provenance ---\n")

;; 3.1 Explicit Dual Span Stack in Stage-Val
(let* ((guest-sp (make-source-span "dsl_scripts/user_actor.dsl" 42 15 42 30 #f 0))
       (host-sp (make-source-span "ulisp/compiler/stage_primitives.scm" 108 8 108 25 #f 0))
       (box-sv (make-static-val 'box (cons '%box (cons 999 '())) host-sp guest-sp))
       (later-d (make-later-dict))
       (err (later-dict-lift-val later-d (stage-val-payload box-sv) box-sv))
       (diag (stage-csp-error-diagnostic err)))
  (assert-equal "3.1 Diagnostic tag" 'compiler-diagnostic (car diag))

  (let* ((prov (diag-field diag 'provenance))
         (g-span (test-assoc-get 'guest-span prov))
         (h-span (test-assoc-get 'host-span prov)))
    (assert-equal "3.1 Guest file preserved" "dsl_scripts/user_actor.dsl" (test-assoc-get 'file g-span))
    (assert-equal "3.1 Guest line preserved" 42 (test-assoc-get 'line g-span))
    (assert-equal "3.1 Guest column preserved" 15 (test-assoc-get 'column g-span))

    (assert-equal "3.1 Host file preserved" "ulisp/compiler/stage_primitives.scm" (test-assoc-get 'file h-span))
    (assert-equal "3.1 Host line preserved" 108 (test-assoc-get 'line h-span))
    (assert-equal "3.1 Host column preserved" 8 (test-assoc-get 'column h-span))))

;; 3.2 Fallback when Span is Missing
(let* ((later-d (make-later-dict))
       (err (later-dict-lift-val later-d (cons '%box (cons 1 '())) #f))
       (diag (stage-csp-error-diagnostic err))
       (prov (diag-field diag 'provenance))
       (g-span (test-assoc-get 'guest-span prov))
       (h-span (test-assoc-get 'host-span prov)))
  (assert-equal "3.2 Missing guest file falls back to unknown" "unknown" (test-assoc-get 'file g-span))
  (assert-equal "3.2 Missing guest line falls back to 0" 0 (test-assoc-get 'line g-span))
  (assert-equal "3.2 Missing host file falls back to unknown" "unknown" (test-assoc-get 'file h-span))
  (assert-equal "3.2 Missing host line falls back to 0" 0 (test-assoc-get 'line h-span)))

;;; -----------------------------------------------------------------------
;;; Group 4: Integration in eval-in-stage
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Integration in eval-in-stage ---\n")

;; 4.1 Evaluation with mutable cell in dynamic call is blocked
(let* ((later-d (make-later-dict))
       (m-box (cons '%box (cons 123 '())))
       (env (list (cons 'b (make-static-val 'box m-box #f #f))))
       (res (eval-in-stage later-d env '(process-data b) 1000 100)))
  (assert-equal "4.1 Residual call lifting mutable box is intercepted" #t (stage-csp-error? res))
  (assert-equal "4.1 Error is illegal-mutable-lift" 'illegal-mutable-lift (stage-csp-error-reason res)))

;; 4.2 Legitimate static values are lifted smoothly without CSP error
(let* ((later-d (make-later-dict))
       (env (list (cons 'x (make-dynamic-val 'unknown 'x #f #f))
                  (cons 'y (make-static-val 'number 100 #f #f))))
       (res (eval-in-stage later-d env '(+ x y) 1000 100)))
  (assert-equal "4.2 Valid static lift produces residual code" '(+ x 100) (stage-val-payload res)))

(display "\n[RESULT] All CSP boundary validator and dual-span diagnostics tests PASSED!\n")
