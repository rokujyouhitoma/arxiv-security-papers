;;; =======================================================================
;;; MLisp Optimizer: Partial Evaluator & Constant Folder (pe.scm)
;;; Conforms to DSN-34 Architecture Specification, Issue #507 & Issue #520
;;;
;;; 100% Pure Scheme Implementation of Trace Partial Evaluation & Guard Elimination:
;;; - Static type knowledge propagation (S-Annotator integration)
;;; - A-priori Guard Elimination (removal of statically verified guards)
;;; - Dominating Guard Elimination (redundant guards after assertion removed)
;;; - Constant propagation and constant folding
;;; - Redundant assignment elimination (%mov x x -> empty)
;;; - Trivial predicate guard elimination (always true guards removed)
;;; - Dispatch and hint flattening (%merge removal)
;;; =======================================================================

;;; Check if an operand is a literal integer/constant
(define (pe-constant? x)
  (or (number? x) (boolean? x) (string? x)))

;;; Constant environment lookup
(define (lookup-const env var)
  (let ((entry (assq var env)))
    (if entry (cdr entry) #f)))

;;; Bind or update a constant in environment
(define (bind-const env var val)
  (cons (cons var val) (filter (lambda (e) (not (eq? (car e) var))) env)))

;;; Invalidate variable in environment (variable reassigned to unknown)
(define (unbind-const env var)
  (filter (lambda (e) (not (eq? (car e) var))) env))

;;; Resolve an operand to its constant value if known, or itself
(define (resolve-opnd env opnd)
  (if (symbol? opnd)
      (let ((c (lookup-const env opnd)))
        (if c c opnd))
      opnd))

;;; -----------------------------------------------------------------------
;;; Type Environment Tracking & Inference for JIT Traces (Issue #520)
;;; -----------------------------------------------------------------------

;;; Type environment lookup
(define (lookup-type env var)
  (let ((entry (assq var env)))
    (if entry (cdr entry) #f)))

;;; Bind or update a type in environment
(define (bind-type env var type)
  (cons (cons var type) (filter (lambda (e) (not (eq? (car e) var))) env)))

;;; Invalidate variable type in environment
(define (unbind-type env var)
  (filter (lambda (e) (not (eq? (car e) var))) env))

;;; Resolve variable/operand type
(define (resolve-type type-env opnd)
  (cond
    ((number? opnd) 'fixnum)
    ((boolean? opnd) 'boolean)
    ((string? opnd) 'string)
    ((symbol? opnd) (lookup-type type-env opnd))
    (else #f)))

;;; Fold a binary arithmetic operation on constants
(define (fold-binary-op op a b)
  (cond
    ((and (number? a) (number? b))
     (case op
       ((%add +) (+ a b))
       ((%sub -) (- a b))
       ((%mul *) (* a b))
       ((%div /) (if (zero? b) #f (quotient a b)))
       ((%mod modulo) (if (zero? b) #f (modulo a b)))
       (else #f)))
    (else #f)))

;;; Fold comparison condition
(define (fold-guard-cond cond-type a b)
  (cond
    ((and (number? a) (number? b))
     (case cond-type
       ((cmp-lt <) (< a b))
       ((cmp-le <=) (<= a b))
       ((cmp-gt >) (> a b))
       ((cmp-ge >=) (>= a b))
       ((cmp-eq =) (= a b))
       (else #f)))
    (else #f)))

;;; Optimize a single trace instruction with both constant & type environments
;;; Returns (values optimized-inst-or-#f updated-const-env updated-type-env)
(define (optimize-pe-instruction-typed inst const-env type-env)
  (let ((op (car inst)))
    (case op
      ;; Loop header / footer - preserve as is
      ((%trace-loop-entry %trace-loop-jump)
       (values inst const-env type-env))

      ;; Hint markers - drop
      ((%merge)
       (values #f const-env type-env))

      ;; Assignment / Move
      ((%mov)
       (let* ((dst (cadr inst))
              (src (caddr inst))
              (resolved-src (resolve-opnd const-env src))
              (src-type (resolve-type type-env resolved-src)))
         (if (eq? dst resolved-src)
             ;; Self assignment: drop (%mov x x)
             (values #f const-env type-env)
             (let ((new-type-env (if src-type
                                     (bind-type type-env dst src-type)
                                     (unbind-type type-env dst))))
               (if (pe-constant? resolved-src)
                   ;; Propagate constant
                   (values (list '%mov dst resolved-src)
                           (bind-const const-env dst resolved-src)
                           new-type-env)
                   ;; Unknown assignment: invalidate dst in const-env
                   (values (list '%mov dst resolved-src)
                           (unbind-const const-env dst)
                           new-type-env))))))

      ;; Binary arithmetic
      ((%add %sub %mul %div %mod)
       (let* ((dst (cadr inst))
              (arg1 (caddr inst))
              (arg2 (cadddr inst))
              (r1 (resolve-opnd const-env arg1))
              (r2 (resolve-opnd const-env arg2))
              (t1 (resolve-type type-env r1))
              (t2 (resolve-type type-env r2))
              (folded (fold-binary-op op r1 r2))
              ;; If both arguments are fixnum (or numbers), the result is statically fixnum!
              (result-type (if (and (or (number? r1) (eq? t1 'fixnum))
                                    (or (number? r2) (eq? t2 'fixnum)))
                               'fixnum
                               #f))
              (new-type-env (if result-type
                                (bind-type type-env dst result-type)
                                (unbind-type type-env dst))))
         (if (number? folded)
             ;; Successfully folded! Convert to %mov dst constant
             (values (list '%mov dst folded)
                     (bind-const const-env dst folded)
                     (bind-type new-type-env dst 'fixnum))
             ;; Keep instruction with resolved operands
             (values (list op dst r1 r2)
                     (unbind-const const-env dst)
                     new-type-env))))

      ;; Guards
      ((%guard)
       (let* ((cond-type (cadr inst))
              (arg1 (caddr inst))
              (arg2 (cadddr inst))
              (fail-lbl (car (cddddr inst)))
              (r1 (resolve-opnd const-env arg1))
              (r2 (resolve-opnd const-env arg2)))
         (cond
           ;; 1. Type Guards (type-fixnum / fixnum-check)
           ((memq cond-type '(type-fixnum fixnum-check))
            (let ((t1 (resolve-type type-env r1)))
              (if (or (number? r1) (eq? t1 'fixnum))
                  ;; Statically guaranteed to be fixnum -> eliminate redundant guard!
                  (values #f
                          const-env
                          (if (symbol? arg1) (bind-type type-env arg1 'fixnum) type-env))
                  ;; First time guard encountered: retain guard, but bind type for subsequent steps!
                  (values (list '%guard cond-type r1 r2 fail-lbl)
                          const-env
                          (if (symbol? arg1) (bind-type type-env arg1 'fixnum) type-env)))))

           ;; 2. Comparison Guards (cmp-lt, cmp-le, etc.)
           ((fold-guard-cond cond-type r1 r2)
            => (lambda (truth)
                 (if (eq? truth #t)
                     ;; Guard is statically known to be TRUE -> drop redundant guard!
                     (values #f const-env type-env)
                     ;; Keep guard with resolved operands
                     (values (list '%guard cond-type r1 r2 fail-lbl) const-env type-env))))

           (else
            ;; Keep guard with resolved operands
            (values (list '%guard cond-type r1 r2 fail-lbl) const-env type-env)))))

      ;; Other instructions
      (else
       (values inst const-env type-env)))))

;;; Backward compatibility wrapper for optimize-pe-instruction
(define (optimize-pe-instruction inst env)
  (call-with-values
    (lambda () (optimize-pe-instruction-typed inst env '()))
    (lambda (opt-inst new-const-env new-type-env)
      (values opt-inst new-const-env))))

;;; Optimize entire instruction list of a trace
(define (optimize-pe-body-typed body init-type-env)
  (let loop ((rest body)
             (c-env '())
             (t-env init-type-env)
             (acc '()))
    (if (null? rest)
        (reverse acc)
        (let ((inst (car rest)))
          (call-with-values
            (lambda () (optimize-pe-instruction-typed inst c-env t-env))
            (lambda (opt-inst new-c-env new-t-env)
              (if opt-inst
                  (loop (cdr rest) new-c-env new-t-env (cons opt-inst acc))
                  (loop (cdr rest) new-c-env new-t-env acc))))))))

(define (optimize-pe-body body)
  (optimize-pe-body-typed body '()))

;;; Entrypoint: optimize complete (%trace-loop ...) S-expression
(define (optimize-trace-pe trace)
  (if (not (and (pair? trace) (eq? (car trace) '%trace-loop)))
      trace
      (let* ((fields (cdr trace))
             (pc (assq '%pc fields))
             (types-entry (assq '%types fields))
             (init-types (if types-entry (cadr types-entry) '()))
             (body-entry (assq '%body fields))
             (body (if body-entry (cadr body-entry) '()))
             (opt-body (optimize-pe-body-typed body init-types)))
        (list '%trace-loop
              pc
              (list '%body opt-body)))))
