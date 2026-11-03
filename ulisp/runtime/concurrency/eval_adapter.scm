;;; =======================================================================
;;; ULisp Runtime Concurrency: Dual-Mode S-expression Evaluation Adapter
;;; (eval_adapter.scm)
;;;
;;; Conforms to DSN-37 Section 13, Section 14.7 (Phase 5 Task 5.3), Issue #644
;;;
;;; Provides:
;;;   1. AST Affine Syntax Linter: (lint-affine-syntax expr [linear-vars])
;;;   2. Dynamic Task Arena Scoping: (with-task-arena task thunk) & (current-task-arena)
;;;   3. Hierarchical Scope Environment: <eval-env> & (make-eval-env)
;;;   4. Reduction-Accounting Tree-Walk Evaluator: (eval-in-task expr env task)
;;;   5. Deterministic Preemptive Safepoint Yielding on Budget Exhaustion (CWE-400)
;;; =======================================================================

;; -----------------------------------------------------------------------
;; 1. AST Affine Syntax Linter (CWE-416 / Linearity Guard)
;; -----------------------------------------------------------------------

;; Fault-tolerance and supervision stubs (overridden when panic.scm / links.scm / supervisor.scm are loaded)
(define synapse-panic! (case-lambda (() #f) ((r) #f) ((r d) #f)))
(define synapse-secure-panic! (case-lambda (() #f) ((r) #f) ((r d) #f)))
(define synapse-assert-true! (case-lambda ((c) #f) ((c m) #f)))
(define with-synapse-task-boundary (case-lambda ((t) #f) ((t thunk) #f)))
(define current-synapse-task (lambda () #f))
(define task-link! (lambda (a b) #f))
(define task-unlink! (lambda (a b) #f))
(define task-monitor (lambda (a b) -1))
(define task-demonitor (lambda (a b) #f))
(define task-trap-exit! (lambda (t v) #f))
(define task-trapping-exit? (lambda (t) #f))
(define make-child-spec (case-lambda ((id thunk) #f) ((id thunk restart-type) #f)))
(define make-supervisor-spec (case-lambda ((strategy) #f) ((strategy max-restarts) #f) ((strategy max-restarts period-seconds) #f)))
(define make-supervisor (lambda (spec children) #f))
(define supervisor-start! (lambda (sup) #f))
(define supervisor-stop! (lambda (sup) #f))
(define supervisor-handle-child-down! (lambda (sup ref tid reason) #f))
(define supervisor-child-task (lambda (sup id) #f))
;; Process Registry stubs (#669)
(define synapse-register! (case-lambda ((n t) #f) ((r n t) #f)))
(define synapse-unregister! (case-lambda ((n) #f) ((r n) #f)))
(define synapse-whereis (case-lambda ((n) #f) ((r n) #f)))
(define synapse-rebind! (case-lambda ((n t) #f) ((r n t) #f)))
(define synapse-send-named! (case-lambda ((n m) #f) ((r n m) #f)))
;; Crash Logger stubs (#670)
(define make-crash-report (case-lambda ((t r) #f) ((t r d) #f) ((t r d s) #f) ((t r d s m) #f) ((t r d s m n) #f)))
(define crash-report? (lambda (x) #f))
(define make-crash-ring-buffer (case-lambda (() #f) ((c) #f)))
(define crash-ring-buffer? (lambda (x) #f))
(define crash-buffer-enqueue! (lambda (b r) #f))
(define crash-buffer-dequeue! (lambda (b) #f))
(define crash-buffer-drain! (lambda (b) '()))
(define synapse-log-task-crash! (case-lambda ((t r) #f) ((t r d) #f) ((t r d s) #f) ((t r d s m) #f) ((t r d s m n) #f)))
(define format-crash-report (lambda (r) ""))
(define synapse-crash-metrics (lambda () '()))
;; io_uring stubs (#677, #683)
(define make-io-uring (case-lambda (() #f) ((e) #f) ((e s) #f) ((e s i) #f)))
(define io-uring? (lambda (x) #f))
(define io-uring-close! (lambda (r) #f))
(define io-uring-sqpoll? (lambda (r) #f))
(define io-uring-sq-idle-ms (lambda (r) 0))
(define io-uring-registered-buffers (lambda (r) (vector)))
(define io-uring-registered-buffer-count (lambda (r) 0))
(define io-uring-enter-syscall-count (lambda (r) 0))
(define io-uring-sqpoll-kick-count (lambda (r) 0))
(define io-uring-register-buffers! (lambda (r b) #f))
(define io-uring-unregister-buffers! (lambda (r) #f))
(define io-uring-submit-nop! (case-lambda ((r u) #f) ((r u t) #f)))
(define io-uring-submit-read! (lambda (r f b o l t) #f))
(define io-uring-submit-write! (lambda (r f b o l t) #f))
(define io-uring-submit-read-fixed! (lambda (r f b o l t) #f))
(define io-uring-submit-write-fixed! (lambda (r f b o l t) #f))
(define io-uring-sqpoll-wakeup! (lambda (r) #t))
(define io-uring-poll-completions! (lambda (r) 0))
(define io-uring-dequeue-completion! (lambda (r) #f))
(define io-uring-stats (lambda (r) '()))

;; Deep-equal helper for AST symbols and values
(define (%sym-equal? a b)
  (cond
    ((eqv? a b) #t)
    ((and (pair? a) (pair? b))
     (and (%sym-equal? (car a) (car b))
          (%sym-equal? (cdr a) (cdr b))))
    (else #f)))

(define (%memq-sym sym lst)
  (if (null? lst)
      #f
      (if (eq? sym (car lst))
          #t
          (%memq-sym sym (cdr lst)))))

(define (%extract-binding-names bindings)
  (let loop ((bs bindings))
    (if (null? bs)
        '()
        (if (pair? (car bs))
            (cons (caar bs) (loop (cdr bs)))
            (loop (cdr bs))))))

(define (%count-var-refs var expr)
  (cond
    ((null? expr) 0)
    ((symbol? expr) (if (eq? expr var) 1 0))
    ((not (pair? expr)) 0)
    ;; Special forms handling
    ((eq? (car expr) 'quote) 0)
    ((eq? (car expr) 'if)
     ;; In branching, take the max between then and else branches (exclusive execution)
     (let ((test-cnt (%count-var-refs var (cadr expr)))
           (then-cnt (%count-var-refs var (caddr expr)))
           (else-cnt (if (pair? (cdddr expr)) (%count-var-refs var (cadddr expr)) 0)))
       (+ test-cnt (if (> then-cnt else-cnt) then-cnt else-cnt))))
    ((or (eq? (car expr) 'lambda) (eq? (car expr) 'let) (eq? (car expr) 'let*))
     ;; If shadow, do not count inner
     (let ((params (if (eq? (car expr) 'lambda) (cadr expr) (%extract-binding-names (cadr expr)))))
       (if (%memq-sym var params)
           0
           (let loop ((rest (cddr expr)) (acc 0))
             (if (null? rest)
                 acc
                 (loop (cdr rest) (+ acc (%count-var-refs var (car rest)))))))))
    (else
     (let loop ((rest expr) (acc 0))
       (if (null? rest)
           acc
           (if (pair? rest)
               (loop (cdr rest) (+ acc (%count-var-refs var (car rest))))
               (+ acc (%count-var-refs var rest))))))))

(define (%lint-affine-core expr linear-vars)
  (cond
    ((null? expr) #t)
    ((symbol? expr) #t)
    ((not (pair? expr)) #t)
    ;; Rule 1: set! is strictly forbidden in affine sub-language
    ((eq? (car expr) 'set!)
     (cons 'error (cons 'forbidden-set! (if (pair? (cdr expr)) (cadr expr) 'unknown))))
    ((eq? (car expr) 'quote) #t)
    ;; Rule 2: Linear variables must not be consumed more than once (Double-Move detection)
    ((and (pair? linear-vars) (pair? expr))
     (let var-loop ((vs linear-vars))
       (if (null? vs)
           ;; Continue traversal for inner expressions
           (let inner-loop ((es expr))
             (if (null? es)
                 #t
                 (if (pair? es)
                     (let ((res (%lint-affine-core (car es) linear-vars)))
                       (if (and (pair? res) (eq? (car res) 'error))
                           res
                           (inner-loop (cdr es))))
                     #t)))
           (let* ((v (car vs))
                  (refs (%count-var-refs v expr)))
             (if (> refs 1)
                 (cons 'error (cons 'double-move v))
                 (var-loop (cdr vs)))))))
    (else
     (let loop ((es expr))
       (if (null? es)
           #t
           (if (pair? es)
               (let ((res (%lint-affine-core (car es) linear-vars)))
                 (if (and (pair? res) (eq? (car res) 'error))
                     res
                     (loop (cdr es))))
               #t))))))

(define lint-affine-syntax
  (case-lambda
    ((expr)
     (%lint-affine-core expr '()))
    ((expr linear-vars)
     (%lint-affine-core expr linear-vars))))

(define affine-syntax-valid?
  (case-lambda
    ((expr)
     (eq? (%lint-affine-core expr '()) #t))
    ((expr linear-vars)
     (eq? (%lint-affine-core expr linear-vars) #t))))

;; -----------------------------------------------------------------------
;; 2. Dynamic Task Arena Scoping (with-task-arena)
;; -----------------------------------------------------------------------

(define *active-task-arena-box* (make-vector 1 #f))

(define (current-task-arena)
  (vector-ref *active-task-arena-box* 0))

(define (%valid-task-or-arena? obj)
  (or (not obj)
      (task-arena? obj)
      (task-context? obj)
      (budgeted-task? obj)))

(define (%resolve-task-arena obj)
  (cond
    ((not obj) #f)
    ((task-arena? obj) obj)
    ((task-context? obj)
     (let ((a (task-arena obj)))
       (if (and a (task-arena? a))
           a
           #f)))
    ((budgeted-task? obj)
     (let ((tgt (task-target-obj obj)))
       (if (task-arena? tgt)
           tgt
           (%resolve-task-arena tgt))))
    (else #f)))

(define (with-task-arena task-or-arena thunk)
  (if (not (%valid-task-or-arena? task-or-arena))
      (error "with-task-arena: invalid task or arena object (CWE-843)" task-or-arena)
      (let ((arena (%resolve-task-arena task-or-arena)))
        (if (not arena)
            (thunk)
            (let ((prev-arena (current-task-arena)))
              (begin
                (vector-set! *active-task-arena-box* 0 arena)
                (let ((res (thunk)))
                  (begin
                    (vector-set! *active-task-arena-box* 0 prev-arena)
                    res))))))))

;; -----------------------------------------------------------------------
;; 3. Hierarchical Scope Environment (<eval-env>)
;; -----------------------------------------------------------------------

(define-record-type <eval-env>
  (%make-eval-env bindings-box parent)
  eval-env?
  (bindings-box %eval-env-bindings-box)
  (parent       eval-env-parent))

(define (%make-env-internal parent)
  (let ((box (make-vector 1 '())))
    (%make-eval-env box parent)))

(define make-eval-env
  (case-lambda
    (() (%make-env-internal #f))
    ((parent)
     (if (and parent (not (eval-env? parent)))
         (error "make-eval-env: parent must be <eval-env> or #f (CWE-843)" parent)
         (%make-env-internal parent)))))

(define (eval-env-bind! env sym val)
  (if (not (eval-env? env))
      (error "eval-env-bind!: expected <eval-env> (CWE-843)" env)
      (if (not (symbol? sym))
          (error "eval-env-bind!: expected symbol key" sym)
          (let* ((box (%eval-env-bindings-box env))
                 (cur (vector-ref box 0)))
            (vector-set! box 0 (cons (cons sym val) cur))
            val))))

(define (eval-env-lookup env sym)
  (if (not (eval-env? env))
      (error "eval-env-lookup: expected <eval-env> (CWE-843)" env)
      (let loop ((cur env))
        (if (not cur)
            (error "eval-env-lookup: unbound variable" sym)
            (let* ((box (%eval-env-bindings-box cur))
                   (alist (vector-ref box 0))
                   (cell (assq sym alist)))
              (if cell
                  (cdr cell)
                  (loop (eval-env-parent cur))))))))

(define (eval-env-bound? env sym)
  (if (not (eval-env? env))
      #f
      (let loop ((cur env))
        (if (not cur)
            #f
            (let* ((box (%eval-env-bindings-box cur))
                   (alist (vector-ref box 0))
                   (cell (assq sym alist)))
              (if cell
                  #t
                  (loop (eval-env-parent cur))))))))

;; -----------------------------------------------------------------------
;; 4. Evaluator Closure (<eval-closure>)
;; -----------------------------------------------------------------------

(define-record-type <eval-closure>
  (make-eval-closure params body env)
  eval-closure?
  (params eval-closure-params)
  (body   eval-closure-body)
  (env    eval-closure-env))

;; -----------------------------------------------------------------------
;; 5. Reduction-Accounting Tree-Walk Evaluator (eval-in-task)
;; -----------------------------------------------------------------------

;; Custom Yield Hook for Tests & Telemetry
(define *eval-yield-hook-box* (make-vector 1 #f))

(define (set-eval-yield-hook! proc)
  (vector-set! *eval-yield-hook-box* 0 proc))

(define (eval-yield-hook)
  (vector-ref *eval-yield-hook-box* 0))

(define (%poll-task-budget! task)
  (if task
      (begin
        (task-consume-reductions! task 1)
        (if (task-exhausted? task)
            (begin
              ;; Invoke custom yield hook if configured
              (let ((hook (eval-yield-hook)))
                (if (procedure? hook)
                    (hook task)))
              ;; Cooperative yield and replenish
              (scheduler-yield! task)
              (task-replenish! task)
              #t)
            #f))
      #f))

(define (%eval-step expr env task)
  (begin
    ;; 1. Step reduction accounting (CWE-400 resource exhaustion guard)
    (%poll-task-budget! task)

    ;; 2. S-expression AST Dispatch
    (cond
    ;; Self-evaluating literals
    ((or (number? expr) (boolean? expr) (string? expr) (char? expr) (null? expr) (vector? expr))
     expr)

    ;; Identifier Lookup
    ((symbol? expr)
     (eval-env-lookup env expr))

    ;; Non-pair unexpected datum
    ((not (pair? expr))
     expr)

    ;; (quote datum)
    ((eq? (car expr) 'quote)
     (cadr expr))

    ;; (if test then [else])
    ((eq? (car expr) 'if)
     (let ((test-val (%eval-step (cadr expr) env task)))
       (if (not (eq? test-val #f))
           (%eval-step (caddr expr) env task)
           (if (pair? (cdddr expr))
               (%eval-step (cadddr expr) env task)
               #f))))

    ;; (begin . exprs)
    ((eq? (car expr) 'begin)
     (let loop ((rest (cdr expr)) (last-val #f))
       (if (null? rest)
           last-val
           (loop (cdr rest) (%eval-step (car rest) env task)))))

    ;; (lambda params . body)
    ((eq? (car expr) 'lambda)
     (let ((params (cadr expr))
           (body (if (null? (cddr expr))
                     #f
                     (if (null? (cdddr expr))
                         (caddr expr)
                         (cons 'begin (cddr expr))))))
       (make-eval-closure params body env)))

    ;; (let ((k v) ...) . body)
    ((eq? (car expr) 'let)
     (let* ((bindings (cadr expr))
            (body (if (null? (cdddr expr))
                      (caddr expr)
                      (cons 'begin (cddr expr))))
            (new-env (make-eval-env env)))
       (let bind-loop ((bs bindings))
         (if (null? bs)
             (%eval-step body new-env task)
             (let* ((b (car bs))
                    (sym (car b))
                    (val-expr (cadr b))
                    (val (%eval-step val-expr env task)))
               (eval-env-bind! new-env sym val)
               (bind-loop (cdr bs)))))))

    ;; (let* ((k v) ...) . body)
    ((eq? (car expr) 'let*)
     (let* ((bindings (cadr expr))
            (body (if (null? (cdddr expr))
                      (caddr expr)
                      (cons 'begin (cddr expr)))))
       (let loop ((bs bindings) (cur-env env))
         (if (null? bs)
             (%eval-step body cur-env task)
             (let* ((b (car bs))
                    (sym (car b))
                    (val-expr (cadr b))
                    (val (%eval-step val-expr cur-env task))
                    (next-env (make-eval-env cur-env)))
               (eval-env-bind! next-env sym val)
               (loop (cdr bs) next-env))))))

    ;; (define var expr)
    ((eq? (car expr) 'define)
     (if (pair? (cadr expr))
         ;; (define (name . params) . body) syntax sugar
         (let* ((name (caadr expr))
                (params (cdadr expr))
                (body (if (null? (cdddr expr))
                          (caddr expr)
                          (cons 'begin (cddr expr))))
                (clo (make-eval-closure params body env)))
           (eval-env-bind! env name clo)
           name)
         ;; (define name val-expr)
         (let* ((sym (cadr expr))
                (val (%eval-step (caddr expr) env task)))
           (eval-env-bind! env sym val)
           sym)))

    ;; Application: (proc . args)
    (else
     (let* ((proc (%eval-step (car expr) env task))
            (arg-vals (let loop ((as (cdr expr)))
                        (if (null? as)
                            '()
                            (cons (%eval-step (car as) env task)
                                  (loop (cdr as)))))))
       (cond
         ((eval-closure? proc)
          (let* ((clo-params (eval-closure-params proc))
                 (clo-body (eval-closure-body proc))
                 (clo-env (make-eval-env (eval-closure-env proc))))
            (let bind-args ((ps clo-params) (vs arg-vals))
              (cond
                ((and (null? ps) (null? vs))
                 (%eval-step clo-body clo-env task))
                ((or (null? ps) (null? vs))
                 (error "eval application: arity mismatch" (length arg-vals)))
                (else
                 (eval-env-bind! clo-env (car ps) (car vs))
                 (bind-args (cdr ps) (cdr vs)))))))
         ((procedure? proc)
          (apply proc arg-vals))
         (else
          (error "eval application: expected procedure or closure" proc))))))))

;; Main Evaluation Entry Point
(define eval-in-task
  (case-lambda
    ((expr)
     (%eval-step expr (make-default-eval-env) #f))
    ((expr env-or-task)
     (if (eval-env? env-or-task)
         (%eval-step expr env-or-task #f)
         (with-task-arena env-or-task
           (lambda ()
             (%eval-step expr (make-default-eval-env) env-or-task)))))
    ((expr env task)
     (with-task-arena task
       (lambda ()
         (%eval-step expr env task))))))

;; -----------------------------------------------------------------------
;; 6. Default Evaluation Environment Factory
;; -----------------------------------------------------------------------

(define %prim-add
  (case-lambda
    (() 0)
    ((a) a)
    ((a b) (+ a b))
    ((a b c) (+ (+ a b) c))))

(define %prim-sub
  (case-lambda
    ((a) (- 0 a))
    ((a b) (- a b))
    ((a b c) (- (- a b) c))))

(define %prim-mul
  (case-lambda
    (() 1)
    ((a) a)
    ((a b) (* a b))
    ((a b c) (* (* a b) c))))

(define %prim-div
  (case-lambda
    ((a b) (/ a b))))

(define (make-default-eval-env)
  (let ((env (make-eval-env)))
    (begin
      ;; Arithmetic & Comparison
      (eval-env-bind! env '+ %prim-add)
      (eval-env-bind! env '- %prim-sub)
      (eval-env-bind! env '* %prim-mul)
      (eval-env-bind! env '/ %prim-div)
      (eval-env-bind! env 'quotient (lambda (a b) (quotient a b)))
      (eval-env-bind! env 'modulo (lambda (a b) (modulo a b)))
      (eval-env-bind! env '= (lambda (a b) (= a b)))
      (eval-env-bind! env '< (lambda (a b) (< a b)))
      (eval-env-bind! env '> (lambda (a b) (> a b)))
      (eval-env-bind! env '<= (lambda (a b) (<= a b)))
      (eval-env-bind! env '>= (lambda (a b) (>= a b)))
      (eval-env-bind! env 'zero? (lambda (x) (zero? x)))
      ;; Boolean & Equality
      (eval-env-bind! env 'not (lambda (x) (not x)))
      (eval-env-bind! env 'boolean? (lambda (x) (boolean? x)))
      (eval-env-bind! env 'eq? (lambda (a b) (eq? a b)))
      (eval-env-bind! env 'eqv? (lambda (a b) (eqv? a b)))
      ;; Pairs & Lists
      (eval-env-bind! env 'cons (lambda (a b) (cons a b)))
      (eval-env-bind! env 'car (lambda (p) (car p)))
      (eval-env-bind! env 'cdr (lambda (p) (cdr p)))
      (eval-env-bind! env 'null? (lambda (p) (null? p)))
      (eval-env-bind! env 'pair? (lambda (p) (pair? p)))
      (eval-env-bind! env 'list (lambda (a b) (list a b)))
      (eval-env-bind! env 'length (lambda (l) (length l)))
      ;; Vectors
      (eval-env-bind! env 'vector (lambda (a b) (vector a b)))
      (eval-env-bind! env 'make-vector (lambda (n) (make-vector n)))
      (eval-env-bind! env 'vector-ref (lambda (v i) (vector-ref v i)))
      (eval-env-bind! env 'vector-set! (lambda (v i x) (begin (vector-set! v i x) x)))
      (eval-env-bind! env 'vector-length (lambda (v) (vector-length v)))
      ;; Concurrency Primitives
      (eval-env-bind! env 'make-channel make-channel)
      (eval-env-bind! env 'channel? channel?)
      (eval-env-bind! env 'channel-send! channel-send!)
      (eval-env-bind! env 'channel-recv! channel-recv!)
      (eval-env-bind! env 'channel-close! channel-close!)
      (eval-env-bind! env 'arena-allocate! arena-allocate!)
      (eval-env-bind! env 'arena-reset! arena-reset!)
      (eval-env-bind! env 'current-task-arena current-task-arena)
      (eval-env-bind! env 'task-reductions task-reductions)
      (eval-env-bind! env 'task-exhausted? task-exhausted?)
      (eval-env-bind! env 'scheduler-yield! scheduler-yield!)
      ;; Fault Tolerance & Let-It-Crash (#668)
      (eval-env-bind! env 'synapse-panic! synapse-panic!)
      (eval-env-bind! env 'synapse-secure-panic! synapse-secure-panic!)
      (eval-env-bind! env 'synapse-assert-true! synapse-assert-true!)
      (eval-env-bind! env 'with-synapse-task-boundary with-synapse-task-boundary)
      (eval-env-bind! env 'current-synapse-task current-synapse-task)
      (eval-env-bind! env 'task-link! task-link!)
      (eval-env-bind! env 'task-unlink! task-unlink!)
      (eval-env-bind! env 'task-monitor task-monitor)
      (eval-env-bind! env 'task-demonitor task-demonitor)
      ;; Supervision Tree (#667)
      (eval-env-bind! env 'make-child-spec make-child-spec)
      (eval-env-bind! env 'make-supervisor-spec make-supervisor-spec)
      (eval-env-bind! env 'make-supervisor make-supervisor)
      (eval-env-bind! env 'supervisor-start! supervisor-start!)
      (eval-env-bind! env 'supervisor-stop! supervisor-stop!)
      (eval-env-bind! env 'supervisor-handle-child-down! supervisor-handle-child-down!)
      (eval-env-bind! env 'supervisor-child-task supervisor-child-task)
      ;; Process Registry (#669)
      (eval-env-bind! env 'synapse-register! synapse-register!)
      (eval-env-bind! env 'synapse-unregister! synapse-unregister!)
      (eval-env-bind! env 'synapse-whereis synapse-whereis)
      (eval-env-bind! env 'synapse-rebind! synapse-rebind!)
      (eval-env-bind! env 'synapse-send-named! synapse-send-named!)
      ;; Crash Logger (#670)
      (eval-env-bind! env 'make-crash-report make-crash-report)
      (eval-env-bind! env 'crash-report? crash-report?)
      (eval-env-bind! env 'make-crash-ring-buffer make-crash-ring-buffer)
      (eval-env-bind! env 'crash-ring-buffer? crash-ring-buffer?)
      (eval-env-bind! env 'crash-buffer-enqueue! crash-buffer-enqueue!)
      (eval-env-bind! env 'crash-buffer-dequeue! crash-buffer-dequeue!)
      (eval-env-bind! env 'crash-buffer-drain! crash-buffer-drain!)
      (eval-env-bind! env 'synapse-log-task-crash! synapse-log-task-crash!)
      (eval-env-bind! env 'format-crash-report format-crash-report)
      (eval-env-bind! env 'synapse-crash-metrics synapse-crash-metrics)
      ;; io_uring (#677, #683)
      (eval-env-bind! env 'make-io-uring make-io-uring)
      (eval-env-bind! env 'io-uring? io-uring?)
      (eval-env-bind! env 'io-uring-close! io-uring-close!)
      (eval-env-bind! env 'io-uring-sqpoll? io-uring-sqpoll?)
      (eval-env-bind! env 'io-uring-sq-idle-ms io-uring-sq-idle-ms)
      (eval-env-bind! env 'io-uring-registered-buffers io-uring-registered-buffers)
      (eval-env-bind! env 'io-uring-registered-buffer-count io-uring-registered-buffer-count)
      (eval-env-bind! env 'io-uring-enter-syscall-count io-uring-enter-syscall-count)
      (eval-env-bind! env 'io-uring-sqpoll-kick-count io-uring-sqpoll-kick-count)
      (eval-env-bind! env 'io-uring-register-buffers! io-uring-register-buffers!)
      (eval-env-bind! env 'io-uring-unregister-buffers! io-uring-unregister-buffers!)
      (eval-env-bind! env 'io-uring-submit-nop! io-uring-submit-nop!)
      (eval-env-bind! env 'io-uring-submit-read! io-uring-submit-read!)
      (eval-env-bind! env 'io-uring-submit-write! io-uring-submit-write!)
      (eval-env-bind! env 'io-uring-submit-read-fixed! io-uring-submit-read-fixed!)
      (eval-env-bind! env 'io-uring-submit-write-fixed! io-uring-submit-write-fixed!)
      (eval-env-bind! env 'io-uring-sqpoll-wakeup! io-uring-sqpoll-wakeup!)
      (eval-env-bind! env 'io-uring-poll-completions! io-uring-poll-completions!)
      (eval-env-bind! env 'io-uring-dequeue-completion! io-uring-dequeue-completion!)
      (eval-env-bind! env 'io-uring-stats io-uring-stats)
      env)))

