;;; =======================================================================
;;; Synapse Concurrency Library: Affine Ownership Checker & RAII Drop Pass
;;; Path: lib/ulisp/concurrency/passes/pass_check_affine.scm
;;; Conforms to DSN-37 Section 4.3, 12.2 & Phase 3 Task 3.2 (Issue #638)
;;;
;;; Pluggable Compiler Pass provided by (ulisp concurrency):
;;; Injected after pass-synapse-split-planes via
;;; (inject-synapse-check-affine-pass!).
;;;
;;; Statically validates affine linearity constraints in ASC kernels:
;;;   1. Forbids destructive mutation (set!, set-car!, vector-set!, etc.)
;;;   2. Forbids non-local continuations (call/cc, dynamic-wind)
;;;   3. Enforces Move semantics and rejects Use-After-Move (CWE-416)
;;;   4. Injects deterministic RAII drop code (%affine-drop!) for unconsumed
;;;      linear resources at scope exits.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Utilities and Symbol Predicates
;;; -----------------------------------------------------------------------

(define (%str-starts-with? prefix str)
  (let ((plen (string-length prefix))
        (slen (string-length str)))
    (if (> plen slen)
        #f
        (let loop ((i 0))
          (if (< i plen)
              (if (char=? (string-ref prefix i) (string-ref str i))
                  (loop (+ i 1))
                  #f)
              #t)))))

(define (%str-ends-with? suffix str)
  (let ((suflen (string-length suffix))
        (slen (string-length str)))
    (if (> suflen slen)
        #f
        (let ((offset (- slen suflen)))
          (let loop ((i 0))
            (if (< i suflen)
                (if (char=? (string-ref suffix i) (string-ref str (+ offset i)))
                    (loop (+ i 1))
                    #f)
                #t))))))

(define (affine-forbidden-syntax? op)
  (memq op '(set! set-car! set-cdr!
             vector-set! string-set! bytevector-u8-set!
             call/cc call-with-current-continuation dynamic-wind)))

(define (linear-variable? sym)
  (if (not (symbol? sym))
      #f
      (let ((s (symbol->string sym)))
        (or (%str-starts-with? "chan" s)
            (%str-starts-with? "rx" s)
            (%str-starts-with? "tx" s)
            (%str-starts-with? "res" s)
            (%str-starts-with? "buf" s)
            (%str-ends-with? "-ch" s)
            (%str-ends-with? "-chan" s)
            (%str-ends-with? "-channel" s)
            (%str-ends-with? "-res" s)
            (%str-ends-with? "-buf" s)))))

(define (channel-borrow-operation? op)
  (memq op '(channel-recv! recv!
             channel-try-recv! try-recv!
             channel-recv-timeout!
             channel-try-recv-with-status!
             channel-try-dequeue-val!
             channel-spsc-try-dequeue-val!
             channel-recv-values!
             channel-try-recv-values!
             channel-recv-unboxed!
             channel-try-recv-unboxed!
             channel-count
             channel-capacity
             channel-empty?
             channel-full?
             channel-closed?
             channel-poisoned?
             channel-stats)))

(define (channel-send-operation? op)
  (memq op '(channel-send! send!
             channel-try-send! try-send!
             channel-send-unboxed!
             channel-try-send-unboxed!
             channel-spsc-try-enqueue!
             broadcast-send!)))

(define (channel-consume-operation? op)
  (memq op '(channel-close! close!
             channel-poison!
             %affine-drop!)))

;;; -----------------------------------------------------------------------
;;; 2. Linear Ownership Environment (lin-env)
;;; -----------------------------------------------------------------------
;;; An environment is an alist mapping symbol -> 'available | 'moved

(define (lin-env-lookup env sym)
  (let ((entry (assq sym env)))
    (if entry
        (cdr entry)
        #f)))

(define (lin-env-set env sym status)
  (let loop ((e env) (acc '()))
    (cond
      ((null? e)
       (cons (cons sym status) acc))
      ((eq? (caar e) sym)
       (append (reverse acc) (cons (cons sym status) (cdr e))))
      (else
       (loop (cdr e) (cons (car e) acc))))))

(define (lin-env-add-available env sym)
  (if (lin-env-lookup env sym)
      env
      (cons (cons sym 'available) env)))

(define (lin-env-unconsumed env)
  (let loop ((e env) (res '()))
    (cond
      ((null? e) (reverse res))
      ((eq? (cdar e) 'available)
       (loop (cdr e) (cons (caar e) res)))
      (else
       (loop (cdr e) res)))))

;;; -----------------------------------------------------------------------
;;; 3. Static AST Validation (Safe Diagnostic Analyzer)
;;; -----------------------------------------------------------------------
;;; Returns either:
;;;   (list 'ok final-env)
;;;   (list 'error 'forbidden-syntax op)
;;;   (list 'error 'use-after-move sym)

(define (validate-affine-ast-internal expr env)
  (cond
    ;; Non-pairs: atoms, literals
    ((not (pair? expr))
     (if (symbol? expr)
         (let ((st (lin-env-lookup env expr)))
           (if (eq? st 'moved)
               (list 'error 'use-after-move expr)
               (list 'ok env)))
         (list 'ok env)))

    ;; Quote: constants untouched
    ((eq? (car expr) 'quote)
     (list 'ok env))

    ;; Forbidden mutations & continuations
    ((affine-forbidden-syntax? (car expr))
     (list 'error 'forbidden-syntax (car expr)))

    ;; Sequence: (begin expr1 expr2 ...)
    ((eq? (car expr) 'begin)
     (let loop ((es (cdr expr)) (cur-env env))
       (if (null? es)
           (list 'ok cur-env)
           (let ((r (validate-affine-ast-internal (car es) cur-env)))
             (if (eq? (car r) 'error)
                 r
                 (loop (cdr es) (cadr r)))))))

    ;; Conditional: (if test then [else])
    ((eq? (car expr) 'if)
     (let ((test-r (validate-affine-ast-internal (cadr expr) env)))
       (if (eq? (car test-r) 'error)
           test-r
           (let* ((env-after-test (cadr test-r))
                  (then-r (validate-affine-ast-internal (caddr expr) env-after-test)))
             (if (eq? (car then-r) 'error)
                 then-r
                 (if (not (pair? (cdddr expr)))
                     then-r
                     (let ((else-r (validate-affine-ast-internal (cadddr expr) env-after-test)))
                       (if (eq? (car else-r) 'error)
                           else-r
                           (let* ((env-after-then (cadr then-r))
                                  (env-after-else (cadr else-r))
                                  (merged (let merge-loop ((e env-after-test) (acc '()))
                                            (if (null? e)
                                                (reverse acc)
                                                (let* ((sym (caar e))
                                                       (st-then (lin-env-lookup env-after-then sym))
                                                       (st-else (lin-env-lookup env-after-else sym))
                                                       (new-st (if (or (eq? st-then 'moved) (eq? st-else 'moved))
                                                                   'moved
                                                                   'available)))
                                                  (merge-loop (cdr e) (cons (cons sym new-st) acc)))))))
                             (list 'ok merged))))))))))

    ;; Local binding: (let ((v e) ...) body ...) or named-let: (let name ((v e) ...) body ...)
    ((and (eq? (car expr) 'let) (pair? (cdr expr)))
     (let* ((is-named? (symbol? (cadr expr)))
            (bindings (if is-named? (caddr expr) (cadr expr)))
            (bodies (if is-named? (cdddr expr) (cddr expr))))
       (let init-loop ((bs bindings) (cur-env env) (new-vars '()))
         (if (pair? bs)
             (let* ((b (car bs))
                    (v (car b))
                    (val-expr (cadr b))
                    (val-r (validate-affine-ast-internal val-expr cur-env)))
               (if (eq? (car val-r) 'error)
                   val-r
                   (let* ((env-after (cadr val-r))
                          (is-lin? (linear-variable? v))
                          (env-with-v (if is-lin?
                                          (lin-env-add-available env-after v)
                                          env-after)))
                     (init-loop (cdr bs)
                                env-with-v
                                (if is-lin? (cons v new-vars) new-vars)))))
             ;; Body validation
             (let ((body-r (validate-affine-ast-internal (cons 'begin bodies) cur-env)))
               (if (eq? (car body-r) 'error)
                   body-r
                   (let* ((env-after-body (cadr body-r))
                          (outer-env (let clean-loop ((e env-after-body))
                                       (cond
                                         ((null? e) '())
                                         ((memq (caar e) new-vars) (clean-loop (cdr e)))
                                         (else (cons (car e) (clean-loop (cdr e))))))))
                     (list 'ok outer-env))))))))

    ;; Applications: channel operations vs custom function calls
    ((pair? expr)
     (let ((op (car expr))
           (args (cdr expr)))
       (cond
         ((affine-forbidden-syntax? op)
          (list 'error 'forbidden-syntax op))

         ;; Channel borrow operation: channel endpoint is borrowed ('available maintained)
         ((channel-borrow-operation? op)
          (let loop ((as args) (cur-env env))
            (if (null? as)
                (list 'ok cur-env)
                (let* ((arg (car as))
                       (r (validate-affine-ast-internal arg cur-env)))
                  (if (eq? (car r) 'error)
                      r
                      (loop (cdr as) (cadr r)))))))

         ;; Channel send operation: channel endpoint is borrowed; payload argument is moved if linear
         ((channel-send-operation? op)
          (if (null? args)
              (list 'ok env)
              (let* ((ch-arg (car args))
                     (ch-r (validate-affine-ast-internal ch-arg env)))
                (if (eq? (car ch-r) 'error)
                    ch-r
                    (let loop ((as (cdr args)) (cur-env (cadr ch-r)))
                      (if (null? as)
                          (list 'ok cur-env)
                          (let* ((arg (car as))
                                 (r (validate-affine-ast-internal arg cur-env)))
                            (if (eq? (car r) 'error)
                                r
                                (let* ((env-after (cadr r))
                                       (env-moved (if (and (symbol? arg) (linear-variable? arg))
                                                      (let ((st (lin-env-lookup env-after arg)))
                                                        (if (eq? st 'moved)
                                                            #f
                                                            (lin-env-set env-after arg 'moved)))
                                                      env-after)))
                                  (if (not env-moved)
                                      (list 'error 'use-after-move arg)
                                      (loop (cdr as) env-moved)))))))))))

         ;; Channel consume operation (close!, poison!, drop!): channel endpoint is consumed ('moved)
         ((channel-consume-operation? op)
          (let loop ((as args) (cur-env env))
            (if (null? as)
                (list 'ok cur-env)
                (let* ((arg (car as))
                       (r (validate-affine-ast-internal arg cur-env)))
                  (if (eq? (car r) 'error)
                      r
                      (let* ((env-after (cadr r))
                             (env-moved (if (and (symbol? arg) (linear-variable? arg))
                                            (let ((st (lin-env-lookup env-after arg)))
                                              (if (eq? st 'moved)
                                                  #f
                                                  (lin-env-set env-after arg 'moved)))
                                            env-after)))
                        (if (not env-moved)
                            (list 'error 'use-after-move arg)
                            (loop (cdr as) env-moved))))))))

         ;; General function application: linear arguments are moved
         (else
          (let loop ((as args) (cur-env env))
            (if (null? as)
                (list 'ok cur-env)
                (let* ((arg (car as))
                       (r (validate-affine-ast-internal arg cur-env)))
                  (if (eq? (car r) 'error)
                      r
                      (let* ((env-after (cadr r))
                             (env-moved (if (and (symbol? arg) (linear-variable? arg))
                                            (let ((st (lin-env-lookup env-after arg)))
                                              (if (eq? st 'moved)
                                                  #f
                                                  (lin-env-set env-after arg 'moved)))
                                            env-after)))
                        (if (not env-moved)
                            (list 'error 'use-after-move arg)
                            (loop (cdr as) env-moved)))))))))))

    (else
     (list 'ok env))))

(define (validate-affine-ast expr init-env)
  (validate-affine-ast-internal expr init-env))

;;; -----------------------------------------------------------------------
;;; 4. AST Transformation with Automatic RAII Drop Injection
;;; -----------------------------------------------------------------------

(define (transform-affine-expr expr env)
  (cond
    ((not (pair? expr))
     (cons expr env))

    ((eq? (car expr) 'quote)
     (cons expr env))

    ((eq? (car expr) 'begin)
     (let loop ((es (cdr expr)) (acc '()) (cur-env env))
       (if (null? es)
           (cons (cons 'begin (reverse acc)) cur-env)
           (let ((r (transform-affine-expr (car es) cur-env)))
             (loop (cdr es) (cons (car r) acc) (cdr r))))))

    ((eq? (car expr) 'if)
     (let* ((test-r (transform-affine-expr (cadr expr) env))
            (test-ast (car test-r))
            (env-after-test (cdr test-r))
            (then-r (transform-affine-expr (caddr expr) env-after-test))
            (then-ast (car then-r))
            (env-after-then (cdr then-r))
            (has-else? (pair? (cdddr expr))))
       (if (not has-else?)
           (cons (list 'if test-ast then-ast) env-after-then)
           (let* ((else-r (transform-affine-expr (cadddr expr) env-after-test))
                  (else-ast (car else-r))
                  (env-after-else (cdr else-r))
                  (merged (let merge-loop ((e env-after-test) (acc '()))
                            (if (null? e)
                                (reverse acc)
                                (let* ((sym (caar e))
                                       (st-then (lin-env-lookup env-after-then sym))
                                       (st-else (lin-env-lookup env-after-else sym))
                                       (new-st (if (or (eq? st-then 'moved) (eq? st-else 'moved))
                                                   'moved
                                                   'available)))
                                  (merge-loop (cdr e) (cons (cons sym new-st) acc)))))))
             (cons (list 'if test-ast then-ast else-ast) merged)))))

    ((and (eq? (car expr) 'let) (pair? (cdr expr)))
     (let* ((is-named? (symbol? (cadr expr)))
            (loop-name (if is-named? (cadr expr) #f))
            (bindings (if is-named? (caddr expr) (cadr expr)))
            (bodies (if is-named? (cdddr expr) (cddr expr))))
       (let init-loop ((bs bindings) (acc-b '()) (cur-env env) (new-vars '()))
         (if (pair? bs)
             (let* ((b (car bs))
                    (v (car b))
                    (val-expr (cadr b))
                    (val-r (transform-affine-expr val-expr cur-env))
                    (val-ast (car val-r))
                    (env-after (cdr val-r))
                    (is-lin? (linear-variable? v))
                    (opt-val-ast (if (and is-lin?
                                          (pair? val-ast)
                                          (eq? (car val-ast) 'make-channel))
                                     (cons 'make-spsc-channel (cdr val-ast))
                                     val-ast))
                    (env-with-v (if is-lin?
                                    (lin-env-add-available env-after v)
                                    env-after)))
               (init-loop (cdr bs)
                          (cons (list v opt-val-ast) acc-b)
                          env-with-v
                          (if is-lin? (cons v new-vars) new-vars)))
             ;; Process body with new variables in scope
             (let* ((body-r (transform-affine-expr (cons 'begin bodies) cur-env))
                    (body-ast (car body-r))
                    (env-after-body (cdr body-r))
                    ;; Find unconsumed variables among newly bound variables
                    (drops (let drop-loop ((vs new-vars) (acc-d '()))
                             (if (null? vs)
                                 (reverse acc-d)
                                 (let ((st (lin-env-lookup env-after-body (car vs))))
                                   (if (eq? st 'available)
                                       (drop-loop (cdr vs) (cons (car vs) acc-d))
                                       (drop-loop (cdr vs) acc-d))))))
                    ;; Generate RAII drop wrapping if there are unconsumed linear variables
                    (final-body
                      (if (null? drops)
                          (if (and (pair? body-ast) (eq? (car body-ast) 'begin))
                              (cdr body-ast)
                              (list body-ast))
                          (let ((res-sym (string->symbol "__raii_res")))
                            (list
                              (list 'let (list (list res-sym body-ast))
                                    (cons 'begin
                                          (append
                                            (map (lambda (dv) (list '%affine-drop! dv)) drops)
                                            (list res-sym))))))))
                    ;; Remove out-of-scope new-vars from outer env
                    (outer-env (let clean-loop ((e env-after-body))
                                 (cond
                                   ((null? e) '())
                                   ((memq (caar e) new-vars) (clean-loop (cdr e)))
                                   (else (cons (car e) (clean-loop (cdr e))))))))
               (cons (if is-named?
                         (cons 'let (cons loop-name (cons (reverse acc-b) final-body)))
                         (cons 'let (cons (reverse acc-b) final-body)))
                     outer-env))))))

    ;; Applications: channel operations vs custom function calls
    ((pair? expr)
     (let ((op (car expr))
           (args (cdr expr)))
       (cond
         ;; Channel borrow operation: endpoint is borrowed ('available maintained)
         ((channel-borrow-operation? op)
          (let loop ((as args) (acc-args '()) (cur-env env))
            (if (null? as)
                (cons (cons op (reverse acc-args)) cur-env)
                (let* ((arg (car as))
                       (r (transform-affine-expr arg cur-env)))
                  (loop (cdr as) (cons (car r) acc-args) (cdr r))))))

         ;; Channel send operation: channel borrowed, linear payload moved
         ((channel-send-operation? op)
          (if (null? args)
              (cons (list op) env)
              (let* ((ch-arg (car args))
                     (ch-r (transform-affine-expr ch-arg env))
                     (ch-ast (car ch-r))
                     (ch-env (cdr ch-r)))
                (let loop ((as (cdr args)) (acc-args (list ch-ast)) (cur-env ch-env))
                  (if (null? as)
                      (cons (cons op (reverse acc-args)) cur-env)
                      (let* ((arg (car as))
                             (r (transform-affine-expr arg cur-env))
                             (arg-ast (car r))
                             (env-after (cdr r))
                             (env-moved (if (and (symbol? arg) (linear-variable? arg))
                                            (lin-env-set env-after arg 'moved)
                                            env-after)))
                        (loop (cdr as) (cons arg-ast acc-args) env-moved)))))))

         ;; Channel consume operation: endpoint is moved
         ((channel-consume-operation? op)
          (let loop ((as args) (acc-args '()) (cur-env env))
            (if (null? as)
                (cons (cons op (reverse acc-args)) cur-env)
                (let* ((arg (car as))
                       (r (transform-affine-expr arg cur-env))
                       (arg-ast (car r))
                       (env-after (cdr r))
                       (env-moved (if (and (symbol? arg) (linear-variable? arg))
                                      (lin-env-set env-after arg 'moved)
                                      env-after)))
                  (loop (cdr as) (cons arg-ast acc-args) env-moved)))))

         ;; General application: linear arguments are moved
         (else
          (let loop ((as args) (acc-args '()) (cur-env env))
            (if (null? as)
                (cons (cons op (reverse acc-args)) cur-env)
                (let* ((arg (car as))
                       (r (transform-affine-expr arg cur-env))
                       (arg-ast (car r))
                       (env-after (cdr r))
                       (env-moved (if (and (symbol? arg) (linear-variable? arg))
                                      (lin-env-set env-after arg 'moved)
                                      env-after)))
                  (loop (cdr as) (cons arg-ast acc-args) env-moved))))))))

    (else
     (cons expr env))))

;;; -----------------------------------------------------------------------
;;; 5. ASC Kernel Transformation & Kernel-Level RAII Drop
;;; -----------------------------------------------------------------------

(define (check-affine-kernel kernel-node)
  (if (or (not (pair? kernel-node)) (not (eq? (car kernel-node) '%asc-kernel)))
      kernel-node
      (let* ((header (cadr kernel-node))
             (kname (car header))
             (formals (cdr header))
             (body (if (pair? (cddr kernel-node))
                       (if (and (pair? (caddr kernel-node)) (eq? (car (caddr kernel-node)) 'begin))
                           (caddr kernel-node)
                           (cons 'begin (cddr kernel-node)))
                       '(begin #f)))
             ;; Initialize environment with linear formals
             (init-env (let loop ((fs formals) (acc '()))
                         (if (null? fs)
                             acc
                             (let ((f (car fs)))
                               (if (linear-variable? f)
                                   (loop (cdr fs) (lin-env-add-available acc f))
                                   (loop (cdr fs) acc))))))
             ;; Validate first: report diagnostic errors on forbidden syntax or use-after-move
             (validation (validate-affine-ast body init-env)))
        (cond
          ((and (pair? validation) (eq? (car validation) 'error))
           (let ((err-type (cadr validation))
                 (irritant (caddr validation)))
             (cond
               ((eq? err-type 'forbidden-syntax)
                (error "[AFFINE-COMPILER-ERROR] Forbidden side-effect or control-flow syntax in ASC kernel" irritant))
               ((eq? err-type 'use-after-move)
                (error "[AFFINE-LINEARITY-VIOLATION] Use-After-Move detected: variable has already been transferred" irritant))
               (else
                (error "[AFFINE-ERROR] Affine type check failed" validation)))))
          (else
           ;; Validation passed: perform transformation with automatic RAII drop
           (let* ((body-r (transform-affine-expr body init-env))
                  (transformed-body (car body-r))
                  (final-env (cdr body-r))
                  (unconsumed (lin-env-unconsumed final-env))
                  (wrapped-body
                    (if (null? unconsumed)
                        transformed-body
                        (let ((res-sym (string->symbol "__kernel_res")))
                          (list 'let (list (list res-sym transformed-body))
                                (cons 'begin
                                      (append
                                        (map (lambda (v) (list '%affine-drop! v)) unconsumed)
                                        (list res-sym))))))))
             (list '%asc-kernel header wrapped-body)))))))

(define (check-affine-pass forms)
  (map (lambda (form)
         (if (and (pair? form) (eq? (car form) '%asc-kernel))
             (check-affine-kernel form)
             form))
       forms))

;;; -----------------------------------------------------------------------
;;; 6. Pluggable Pass Injection & Registration API
;;; -----------------------------------------------------------------------

(define (synapse-check-affine-descriptor)
  (make-pass-descriptor
    'pass-synapse-check-affine
    "Synapse Affine Ownership Check & RAII Drop"
    'frontend
    0
    check-affine-pass
    #f
    'L_core
    'L_core
    '(pass-synapse-split-planes)
    #t))

(define (inject-synapse-check-affine-pass!)
  (inject-pass-after! 'pass-synapse-split-planes (synapse-check-affine-descriptor)))

(define (remove-synapse-check-affine-pass!)
  (remove-injected-pass! 'pass-synapse-check-affine))
