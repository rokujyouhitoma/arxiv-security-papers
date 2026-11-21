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
    ((pair? opnd) 'pair)
    ((symbol? opnd) (lookup-type type-env opnd))
    (else #f)))

;;; -----------------------------------------------------------------------
;;; Dominating Guard Environment Tracking (Issue #900)
;;; -----------------------------------------------------------------------

;;; Invalidate any guarded conditions involving modified-var
(define (unbind-guard-conds guard-env modified-var)
  (filter (lambda (entry)
            (let ((r1 (cadr entry))
                  (r2 (caddr entry)))
              (not (or (eq? r1 modified-var) (eq? r2 modified-var)))))
          guard-env))

;;; Check if a condition is already dominated by a prior guard
(define (condition-dominated? guard-env cond-type r1 r2)
  (let loop ((rest guard-env))
    (if (null? rest)
        #f
        (let ((entry (car rest)))
          (if (and (eq? (car entry) cond-type)
                   (equal? (cadr entry) r1)
                   (equal? (caddr entry) r2))
              #t
              (loop (cdr rest)))))))

;;; Record a satisfied guard condition
(define (bind-guard-cond guard-env cond-type r1 r2)
  (cons (list cond-type r1 r2)
        (filter (lambda (entry)
                  (not (and (eq? (car entry) cond-type)
                            (equal? (cadr entry) r1)
                            (equal? (caddr entry) r2))))
                guard-env)))

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

;;; Optimize a single trace instruction with constant, type, and dominating guard environments
;;; Returns (values optimized-inst-or-#f updated-const-env updated-type-env updated-guard-env)
(define (optimize-pe-instruction-full inst const-env type-env guard-env)
  (let ((op (car inst)))
    (case op
      ;; Loop header / footer - preserve as is
      ((%trace-loop-entry %trace-loop-jump)
       (values inst const-env type-env guard-env))

      ;; Hint markers - drop
      ((%merge)
       (values #f const-env type-env guard-env))

      ;; Assignment / Move
      ((%mov)
       (let* ((dst (cadr inst))
              (src (caddr inst))
              (resolved-src (resolve-opnd const-env src))
              (src-type (resolve-type type-env resolved-src))
              (clean-guard-env (unbind-guard-conds guard-env dst)))
         (if (eq? dst resolved-src)
             ;; Self assignment: drop (%mov x x)
             (values #f const-env type-env clean-guard-env)
             (let ((new-type-env (if src-type
                                     (bind-type type-env dst src-type)
                                     (unbind-type type-env dst))))
               (if (pe-constant? resolved-src)
                   ;; Propagate constant
                   (values (list '%mov dst resolved-src)
                           (bind-const const-env dst resolved-src)
                           new-type-env
                           clean-guard-env)
                   ;; Unknown assignment: invalidate dst in const-env
                   (values (list '%mov dst resolved-src)
                           (unbind-const const-env dst)
                           new-type-env
                           clean-guard-env))))))

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
              (clean-guard-env (unbind-guard-conds guard-env dst))
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
                     (bind-type new-type-env dst 'fixnum)
                     clean-guard-env)
             ;; Keep instruction with resolved operands
             (values (list op dst r1 r2)
                     (unbind-const const-env dst)
                     new-type-env
                     clean-guard-env))))

      ;; Guards (%guard cond-type arg1 arg2 fail-lbl . extra)
      ((%guard)
       (let* ((cond-type (cadr inst))
              (arg1 (caddr inst))
              (arg2 (cadddr inst))
              (fail-lbl (car (cddddr inst)))
              (extra (cdr (cddddr inst)))
              (r1 (resolve-opnd const-env arg1))
              (r2 (resolve-opnd const-env arg2)))
         (cond
           ;; 1. Check if condition is already dominated by a prior guard!
           ((condition-dominated? guard-env cond-type r1 r2)
            (values #f const-env type-env guard-env))

           ;; 2. Type Guards (type-fixnum / fixnum-check / type-boolean / type-pair / type-string)
           ((memq cond-type '(type-fixnum fixnum-check))
            (let ((t1 (resolve-type type-env r1)))
              (if (or (number? r1) (eq? t1 'fixnum))
                  ;; Statically guaranteed to be fixnum -> eliminate redundant guard!
                  (values #f
                          const-env
                          (if (symbol? arg1) (bind-type type-env arg1 'fixnum) type-env)
                          (bind-guard-cond guard-env cond-type r1 r2))
                  ;; First time guard encountered: retain guard with extra fields preserved
                  (values (append (list '%guard cond-type r1 r2 fail-lbl) extra)
                          const-env
                          (if (symbol? arg1) (bind-type type-env arg1 'fixnum) type-env)
                          (bind-guard-cond guard-env cond-type r1 r2)))))

           ((eq? cond-type 'type-boolean)
            (let ((t1 (resolve-type type-env r1)))
              (if (or (boolean? r1) (eq? t1 'boolean))
                  (values #f
                          const-env
                          (if (symbol? arg1) (bind-type type-env arg1 'boolean) type-env)
                          (bind-guard-cond guard-env cond-type r1 r2))
                  (values (append (list '%guard cond-type r1 r2 fail-lbl) extra)
                          const-env
                          (if (symbol? arg1) (bind-type type-env arg1 'boolean) type-env)
                          (bind-guard-cond guard-env cond-type r1 r2)))))

           ((eq? cond-type 'type-pair)
            (let ((t1 (resolve-type type-env r1)))
              (if (or (pair? r1) (eq? t1 'pair))
                  (values #f
                          const-env
                          (if (symbol? arg1) (bind-type type-env arg1 'pair) type-env)
                          (bind-guard-cond guard-env cond-type r1 r2))
                  (values (append (list '%guard cond-type r1 r2 fail-lbl) extra)
                          const-env
                          (if (symbol? arg1) (bind-type type-env arg1 'pair) type-env)
                          (bind-guard-cond guard-env cond-type r1 r2)))))

           ((eq? cond-type 'type-string)
            (let ((t1 (resolve-type type-env r1)))
              (if (or (string? r1) (eq? t1 'string))
                  (values #f
                          const-env
                          (if (symbol? arg1) (bind-type type-env arg1 'string) type-env)
                          (bind-guard-cond guard-env cond-type r1 r2))
                  (values (append (list '%guard cond-type r1 r2 fail-lbl) extra)
                          const-env
                          (if (symbol? arg1) (bind-type type-env arg1 'string) type-env)
                          (bind-guard-cond guard-env cond-type r1 r2)))))

           ;; 3. Comparison Guards (cmp-lt, cmp-le, etc.)
           ((fold-guard-cond cond-type r1 r2)
            => (lambda (truth)
                 (if (eq? truth #t)
                     ;; Guard is statically known to be TRUE -> drop redundant guard!
                     (values #f const-env type-env (bind-guard-cond guard-env cond-type r1 r2))
                     ;; Keep guard with resolved operands and preserved extra fields
                     (values (append (list '%guard cond-type r1 r2 fail-lbl) extra)
                             const-env
                             type-env
                             (bind-guard-cond guard-env cond-type r1 r2)))))

           (else
            ;; Keep guard with resolved operands and preserved extra fields
            (values (append (list '%guard cond-type r1 r2 fail-lbl) extra)
                    const-env
                    type-env
                    (bind-guard-cond guard-env cond-type r1 r2))))))

      ;; Other instructions
      (else
       (values inst const-env type-env guard-env)))))

;;; Backward compatibility wrapper for optimize-pe-instruction-typed
(define (optimize-pe-instruction-typed inst const-env type-env)
  (call-with-values
    (lambda () (optimize-pe-instruction-full inst const-env type-env '()))
    (lambda (opt-inst new-const-env new-type-env new-guard-env)
      (values opt-inst new-const-env new-type-env))))

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
             (g-env '())
             (acc '()))
    (if (null? rest)
        (reverse acc)
        (let ((inst (car rest)))
          (call-with-values
            (lambda () (optimize-pe-instruction-full inst c-env t-env g-env))
            (lambda (opt-inst new-c-env new-t-env new-g-env)
              (if opt-inst
                  (loop (cdr rest) new-c-env new-t-env new-g-env (cons opt-inst acc))
                  (loop (cdr rest) new-c-env new-t-env new-g-env acc))))))))

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
