;;; =======================================================================
;;; MLisp Optimizer: Partial Evaluator & Constant Folder (pe.scm)
;;; Conforms to DSN-34 Architecture Specification & Issue #507
;;;
;;; 100% Pure Scheme Implementation of Trace Partial Evaluation:
;;; - Constant propagation and constant folding
;;; - Redundant assignment elimination (%mov x x -> empty)
;;; - Trivial guard elimination (always true guards removed)
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

;;; Optimize a single trace instruction
;;; Returns (values optimized-inst-or-#f updated-env)
(define (optimize-pe-instruction inst env)
  (let ((op (car inst)))
    (case op
      ;; Loop header / footer - preserve as is
      ((%trace-loop-entry %trace-loop-jump)
       (values inst env))

      ;; Hint markers - drop
      ((%merge)
       (values #f env))

      ;; Assignment / Move
      ((%mov)
       (let* ((dst (cadr inst))
              (src (caddr inst))
              (resolved-src (resolve-opnd env src)))
         (if (eq? dst resolved-src)
             ;; Self assignment: drop (%mov x x)
             (values #f env)
             (if (pe-constant? resolved-src)
                 ;; Propagate constant
                 (values `(%mov ,dst ,resolved-src) (bind-const env dst resolved-src))
                 ;; Unknown assignment: invalidate dst
                 (values `(%mov ,dst ,resolved-src) (unbind-const env dst))))))

      ;; Binary arithmetic
      ((%add %sub %mul %div %mod)
       (let* ((dst (cadr inst))
              (arg1 (caddr inst))
              (arg2 (cadddr inst))
              (r1 (resolve-opnd env arg1))
              (r2 (resolve-opnd env arg2))
              (folded (fold-binary-op op r1 r2)))
         (if (number? folded)
             ;; Successfully folded! Convert to %mov dst constant
             (values `(%mov ,dst ,folded) (bind-const env dst folded))
             ;; Keep instruction with resolved operands
             (values `(,op ,dst ,r1 ,r2) (unbind-const env dst)))))

      ;; Guards
      ((%guard)
       (let* ((cond-type (cadr inst))
              (arg1 (caddr inst))
              (arg2 (cadddr inst))
              (fail-lbl (car (cddddr inst)))
              (r1 (resolve-opnd env arg1))
              (r2 (resolve-opnd env arg2))
              (truth (fold-guard-cond cond-type r1 r2)))
         (cond
           ((eq? truth #t)
            ;; Guard is statically known to be TRUE -> drop redundant guard!
            (values #f env))
           (else
            ;; Keep guard with resolved operands
            (values `(%guard ,cond-type ,r1 ,r2 ,fail-lbl) env)))))

      ;; Other instructions
      (else
       (values inst env)))))

;;; Optimize entire instruction list of a trace
(define (optimize-pe-body body)
  (let loop ((rest body)
             (env '())
             (acc '()))
    (if (null? rest)
        (reverse acc)
        (let ((inst (car rest)))
          (call-with-values
            (lambda () (optimize-pe-instruction inst env))
            (lambda (opt-inst new-env)
              (if opt-inst
                  (loop (cdr rest) new-env (cons opt-inst acc))
                  (loop (cdr rest) new-env acc))))))))

;;; Entrypoint: optimize complete (%trace-loop ...) S-expression
(define (optimize-trace-pe trace)
  (if (not (and (pair? trace) (eq? (car trace) '%trace-loop)))
      trace
      (let* ((fields (cdr trace))
             (pc (assq '%pc fields))
             (body-entry (assq '%body fields))
             (body (if body-entry (cadr body-entry) '()))
             (opt-body (optimize-pe-body body)))
        `(%trace-loop
           ,pc
           (%body ,opt-body)))))
