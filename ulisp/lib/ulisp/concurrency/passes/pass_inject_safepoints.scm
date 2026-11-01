;;; =======================================================================
;;; Synapse Concurrency Library: Safepoint Injection Pass
;;; Path: lib/ulisp/concurrency/passes/pass_inject_safepoints.scm
;;; Conforms to DSN-37 Section 7.2, 12.4 & Phase 3 Task 3.4 (Issue #640)
;;;
;;; Pluggable Compiler Pass provided by (ulisp concurrency):
;;; Injected after pass-synapse-fbip via
;;; (inject-synapse-safepoints-pass!).
;;;
;;; Injects deterministic reduction budget decrement & preemption polling
;;; (%synapse-safepoint-poll!) into all ASC kernel function entries,
;;; lambda prologues, and loop backedges (named-let, recursion).
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Utilities & AST Predicates
;;; -----------------------------------------------------------------------

(define (safepoint-poll-form? expr)
  (and (pair? expr)
       (or (eq? (car expr) '%synapse-safepoint-poll!)
           (eq? (car expr) '%safepoint-poll!))))

(define (make-safepoint-poll)
  '(%synapse-safepoint-poll!))

(define (lambda-form? expr)
  (and (pair? expr)
       (eq? (car expr) 'lambda)
       (pair? (cdr expr))))

(define (named-let-form? expr)
  (and (pair? expr)
       (eq? (car expr) 'let)
       (pair? (cdr expr))
       (symbol? (cadr expr))
       (pair? (cddr expr))))

(define (let-form? expr)
  (and (pair? expr)
       (eq? (car expr) 'let)
       (pair? (cdr expr))
       (not (symbol? (cadr expr)))))

(define (let*-form? expr)
  (and (pair? expr)
       (eq? (car expr) 'let*)
       (pair? (cdr expr))))

(define (begin-form? expr)
  (and (pair? expr)
       (eq? (car expr) 'begin)))

(define (if-form? expr)
  (and (pair? expr)
       (eq? (car expr) 'if)
       (pair? (cdr expr))
       (pair? (cddr expr))))

(define (asc-kernel-form? expr)
  (and (pair? expr)
       (eq? (car expr) '%asc-kernel)
       (pair? (cdr expr))
       (pair? (cddr expr))))

;;; -----------------------------------------------------------------------
;;; 2. Body Sequence Injection Helpers
;;; -----------------------------------------------------------------------

(define (prepend-safepoint-to-list expr-list)
  (if (null? expr-list)
      (list (make-safepoint-poll))
      (if (safepoint-poll-form? (car expr-list))
          expr-list
          (cons (make-safepoint-poll) expr-list))))

(define (wrap-with-safepoint-prologue body-expr)
  (cond
    ((safepoint-poll-form? body-expr)
     body-expr)
    ((begin-form? body-expr)
     (cons 'begin (prepend-safepoint-to-list (cdr body-expr))))
    (else
     (list 'begin (make-safepoint-poll) body-expr))))

;;; -----------------------------------------------------------------------
;;; 3. Recursive AST Traversal & Loop Backedge Injection
;;; -----------------------------------------------------------------------

(define (inject-safepoints-expr expr loop-names)
  (cond
    ((not (pair? expr))
     expr)

    ;; Quoted literals: do not touch
    ((eq? (car expr) 'quote)
     expr)

    ;; Safepoint poll already present: leave intact
    ((safepoint-poll-form? expr)
     expr)

    ;; Lambda abstraction: inject safepoint into prologue
    ((lambda-form? expr)
     (let* ((formals (cadr expr))
            (raw-body (cddr expr))
            (injected-body (prepend-safepoint-to-list raw-body))
            (transformed-body (map (lambda (e) (inject-safepoints-expr e loop-names))
                                   injected-body)))
       (cons 'lambda (cons formals transformed-body))))

    ;; Named let (loop construct): inject into loop entry & track loop identifier
    ((named-let-form? expr)
     (let* ((loop-name (cadr expr))
            (bindings (caddr expr))
            (raw-body (cdddr expr))
            (new-loop-names (if (memq loop-name loop-names)
                                loop-names
                                (cons loop-name loop-names)))
            ;; Transform bindings
            (trans-bindings
              (map (lambda (b)
                     (if (pair? b)
                         (list (car b) (inject-safepoints-expr (cadr b) loop-names))
                         b))
                   bindings))
            ;; Inject safepoint at loop entry
            (injected-body (prepend-safepoint-to-list raw-body))
            (trans-body (map (lambda (e) (inject-safepoints-expr e new-loop-names))
                             injected-body)))
       (cons 'let (cons loop-name (cons trans-bindings trans-body)))))

    ;; Standard let
    ((let-form? expr)
     (let* ((bindings (cadr expr))
            (body (cddr expr))
            (trans-bindings
              (map (lambda (b)
                     (if (pair? b)
                         (list (car b) (inject-safepoints-expr (cadr b) loop-names))
                         b))
                   bindings))
            (trans-body (map (lambda (e) (inject-safepoints-expr e loop-names)) body)))
       (cons 'let (cons trans-bindings trans-body))))

    ;; Standard let*
    ((let*-form? expr)
     (let* ((bindings (cadr expr))
            (body (cddr expr))
            (trans-bindings
              (map (lambda (b)
                     (if (pair? b)
                         (list (car b) (inject-safepoints-expr (cadr b) loop-names))
                         b))
                   bindings))
            (trans-body (map (lambda (e) (inject-safepoints-expr e loop-names)) body)))
       (cons 'let* (cons trans-bindings trans-body))))

    ;; Begin block
    ((begin-form? expr)
     (cons 'begin (map (lambda (e) (inject-safepoints-expr e loop-names)) (cdr expr))))

    ;; If conditional
    ((if-form? expr)
     (let ((test (cadr expr))
           (conseq (caddr expr))
           (alt (if (null? (cdddr expr)) #f (cadddr expr))))
       (if alt
           (list 'if
                 (inject-safepoints-expr test loop-names)
                 (inject-safepoints-expr conseq loop-names)
                 (inject-safepoints-expr alt loop-names))
           (list 'if
                 (inject-safepoints-expr test loop-names)
                 (inject-safepoints-expr conseq loop-names)))))

    ;; Loop backedge call (e.g. (loop-name arg1 arg2))
    ((and (symbol? (car expr)) (memq (car expr) loop-names))
     ;; Explicitly wrap with (%synapse-safepoint-poll!) before the recursive loop backedge
     (let ((trans-args (map (lambda (e) (inject-safepoints-expr e loop-names)) (cdr expr))))
       (list 'begin
             (make-safepoint-poll)
             (cons (car expr) trans-args))))

    ;; General application
    (else
     (map (lambda (e) (inject-safepoints-expr e loop-names)) expr))))

;;; -----------------------------------------------------------------------
;;; 4. ASC Kernel Transformation
;;; -----------------------------------------------------------------------

(define (inject-safepoints-kernel kernel-node)
  (if (not (asc-kernel-form? kernel-node))
      kernel-node
      (let* ((header (cadr kernel-node))
             (body (caddr kernel-node))
             ;; Wrap kernel prologue
             (prologue-wrapped (wrap-with-safepoint-prologue body))
             ;; Traverse and inject loop backedges
             (trans-body (inject-safepoints-expr prologue-wrapped '())))
        (list '%asc-kernel header trans-body))))

(define (inject-safepoints-pass forms)
  (map (lambda (form)
         (if (asc-kernel-form? form)
             (inject-safepoints-kernel form)
             form))
       forms))

;;; -----------------------------------------------------------------------
;;; 5. Pluggable Pass Injection & Registration API
;;; -----------------------------------------------------------------------

(define (synapse-inject-safepoints-descriptor)
  (make-pass-descriptor
    'pass-synapse-inject-safepoints
    "Synapse Reduction Safepoint Injection Pass"
    'frontend
    0
    inject-safepoints-pass
    #f
    'L_core
    'L_core
    '(pass-synapse-fbip)
    #t))

(define (inject-synapse-safepoints-pass!)
  (inject-pass-after! 'pass-synapse-fbip (synapse-inject-safepoints-descriptor)))

(define (remove-synapse-safepoints-pass!)
  (remove-injected-pass! 'pass-synapse-inject-safepoints))

