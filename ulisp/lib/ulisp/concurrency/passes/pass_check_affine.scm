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

;; NOTE (Issue #797): Variable name heuristics are completely eliminated from the compiler.
;; All linear variables must be established via explicit type annotation (: var type),
;; constructor provenance, or function signatures.
(define (linear-variable-name-hint? sym)
  #f)

;; Backward-compatibility stub: name-based linearity is disabled (#797)
(define (linear-variable? sym)
  #f)

;;; -----------------------------------------------------------------------
;;; 1b. Function Signatures & Return Type Propagation (Issue #792)
;;; -----------------------------------------------------------------------

(define (linear-type? ty)
  (memq ty '(channel
             spsc-channel
             bounded-channel
             linear
             linear-resource
             channel-pair)))

(define *default-affine-signatures*
  '((make-channel . channel)
    (make-spsc-channel . spsc-channel)
    (make-bounded-channel . channel)
    (make-channel-internal . channel)
    (make-channel-pair . channel-pair)
    (channel-pair . channel-pair)))

(define *affine-sig-registry* '())

(define (register-affine-signature! name return-type)
  (set! *affine-sig-registry*
        (cons (cons name return-type) *affine-sig-registry*)))

(define (reset-affine-signatures!)
  (set! *affine-sig-registry* '()))

(define (lookup-affine-signature fn-name . opt-sig-env)
  (let ((sig-env (if (pair? opt-sig-env) (car opt-sig-env) '())))
    (cond
      ((assq fn-name sig-env) => cdr)
      ((assq fn-name *affine-sig-registry*) => cdr)
      ((assq fn-name *default-affine-signatures*) => cdr)
      (else #f))))

(define (%parse-return-type type-expr)
  (cond
    ((symbol? type-expr)
     (if (linear-type? type-expr) type-expr #f))
    ((and (pair? type-expr)
          (eq? (car type-expr) '->)
          (pair? (cdr type-expr))
          (pair? (cddr type-expr)))
     (%parse-return-type (caddr type-expr)))
    (else #f)))

(define (infer-body-linear-return-type body-forms sig-env)
  (if (null? body-forms)
      #f
      (let loop ((es body-forms))
        (if (null? (cdr es))
            (infer-expr-linear-return-type (car es) sig-env)
            (loop (cdr es))))))

(define (infer-expr-linear-return-type expr sig-env)
  (cond
    ((not (pair? expr)) #f)
    ;; (!linear expr)
    ((eq? (car expr) '!linear) 'linear)
    ;; (: type expr) or (: expr type)
    ((and (eq? (car expr) ':) (pair? (cdr expr)))
     (cond
       ((linear-type? (cadr expr)) (cadr expr))
       ((and (pair? (cddr expr)) (linear-type? (caddr expr))) (caddr expr))
       (else #f)))
    ;; Direct constructor call: (make-channel ...)
    ((linear-constructor-op? (car expr))
     (cond
       ((eq? (car expr) 'make-spsc-channel) 'spsc-channel)
       ((or (eq? (car expr) 'make-channel-pair) (eq? (car expr) 'channel-pair)) 'channel-pair)
       (else 'channel)))
    ;; Known signature call: (create-pipe ...)
    ((symbol? (car expr))
     (lookup-affine-signature (car expr) sig-env))
    ;; (begin e1 ... en)
    ((eq? (car expr) 'begin)
     (infer-body-linear-return-type (cdr expr) sig-env))
    ;; (let (...) body ...)
    ((and (eq? (car expr) 'let) (pair? (cdr expr)))
     (let ((bodies (if (symbol? (cadr expr)) (cdddr expr) (cddr expr))))
       (infer-body-linear-return-type bodies sig-env)))
    ;; (let* (...) body ...)
    ((and (eq? (car expr) 'let*) (pair? (cdr expr)) (pair? (cddr expr)))
     (infer-body-linear-return-type (cddr expr) sig-env))
    ;; (letrec (...) body ...)
    ((and (eq? (car expr) 'letrec) (pair? (cdr expr)) (pair? (cddr expr)))
     (infer-body-linear-return-type (cddr expr) sig-env))
    ;; (if test then [else])
    ((eq? (car expr) 'if)
     (let ((then-t (infer-expr-linear-return-type (caddr expr) sig-env))
           (else-t (if (pair? (cdddr expr))
                       (infer-expr-linear-return-type (cadddr expr) sig-env)
                       #f)))
       (or then-t else-t)))
    (else #f)))

(define (scan-form-signatures forms . opt-base-env)
  (let* ((base (if (pair? opt-base-env) (car opt-base-env) '()))
         (extract-one-pass
           (lambda (cur-env)
             (let loop ((fs forms) (acc cur-env))
               (if (null? fs)
                   acc
                   (let ((form (car fs)))
                     (cond
                       ;; Case 1: (: fname sig)
                       ((and (pair? form)
                             (eq? (car form) ':)
                             (pair? (cdr form))
                             (symbol? (cadr form))
                             (pair? (cddr form)))
                        (let* ((fn-name (cadr form))
                               (ret-ty (%parse-return-type (caddr form))))
                          (if (and ret-ty (not (assq fn-name acc)))
                              (loop (cdr fs) (cons (cons fn-name ret-ty) acc))
                              (loop (cdr fs) acc))))

                       ;; Case 2: (define (: fname sig) ...)
                       ((and (pair? form)
                             (eq? (car form) 'define)
                             (pair? (cdr form))
                             (pair? (cadr form))
                             (eq? (caadr form) ':)
                             (pair? (cdadr form))
                             (symbol? (cadadr form))
                             (pair? (cddadr form)))
                        (let* ((fn-name (cadadr form))
                               (ret-ty (%parse-return-type (car (cddadr form)))))
                          (if (and ret-ty (not (assq fn-name acc)))
                              (loop (cdr fs) (cons (cons fn-name ret-ty) acc))
                              (loop (cdr fs) acc))))

                       ;; Case 3: (define (fname . args) : return-type body ...)
                       ((and (pair? form)
                             (eq? (car form) 'define)
                             (pair? (cdr form))
                             (pair? (cadr form))
                             (symbol? (caadr form))
                             (pair? (cddr form))
                             (eq? (caddr form) ':)
                             (pair? (cdddr form)))
                        (let* ((fn-name (caadr form))
                               (ret-ty (%parse-return-type (cadddr form))))
                          (if (and ret-ty (not (assq fn-name acc)))
                              (loop (cdr fs) (cons (cons fn-name ret-ty) acc))
                              (loop (cdr fs) acc))))

                       ;; Case 4: (define (fname . args) body ...) - tail expression inference
                       ((and (pair? form)
                             (eq? (car form) 'define)
                             (pair? (cdr form))
                             (pair? (cadr form))
                             (symbol? (caadr form))
                             (pair? (cddr form)))
                        (let* ((fn-name (caadr form))
                               (bodies (cddr form))
                               (ret-ty (infer-body-linear-return-type bodies acc)))
                          (if (and ret-ty (not (assq fn-name acc)))
                              (loop (cdr fs) (cons (cons fn-name ret-ty) acc))
                              (loop (cdr fs) acc))))

                       (else
                        (loop (cdr fs) acc)))))))))
    (let fixpoint-loop ((iter 0) (cur-env base))
      (if (>= iter 4)
          cur-env
          (let ((next-env (extract-one-pass cur-env)))
            (if (= (length next-env) (length cur-env))
                cur-env
                (fixpoint-loop (+ iter 1) next-env)))))))

(define (linear-constructor-op? op)
  (memq op '(make-channel
             make-spsc-channel
             make-bounded-channel
             make-channel-internal
             make-channel-pair
             channel-pair)))

(define (non-linear-literal? expr)
  (or (number? expr)
      (boolean? expr)
      (char? expr)
      (string? expr)
      (bytevector? expr)
      (null? expr)
      (and (pair? expr) (eq? (car expr) 'quote))))

(define (linear-constructor-expr? expr env . opt-sig-env)
  (let ((sig-env (if (pair? opt-sig-env) (car opt-sig-env) '())))
    (cond
      ((symbol? expr)
       (eq? (lin-env-lookup env expr) 'available))
      ((not (pair? expr)) #f)
      ((linear-constructor-op? (car expr)) #t)
      ((and (eq? (car expr) '!linear) (pair? (cdr expr))) #t)
      ((and (eq? (car expr) ':) (pair? (cdr expr)))
       (or (linear-type? (cadr expr))
           (and (pair? (cddr expr)) (linear-type? (caddr expr)))))
      ((and (symbol? (car expr))
            (let ((ret-ty (lookup-affine-signature (car expr) sig-env)))
              (and ret-ty (linear-type? ret-ty))))
       #t)
      (else #f))))

(define (infer-linear-binding? var val-expr env . opt-sig-env)
  (let ((sig-env (if (pair? opt-sig-env) (car opt-sig-env) '())))
    (cond
      ;; 1. Explicit linear constructor call: (make-channel ...)
      ((and (pair? val-expr) (linear-constructor-op? (car val-expr)))
       #t)
      ;; 2. Explicit !linear annotation: (!linear <expr>)
      ((and (pair? val-expr) (eq? (car val-expr) '!linear))
       #t)
      ;; 3. Type annotation in value: (: channel expr) or (: expr channel)
      ((and (pair? val-expr)
            (eq? (car val-expr) ':)
            (pair? (cdr val-expr))
            (linear-type? (cadr val-expr)))
       #t)
      ((and (pair? val-expr)
            (eq? (car val-expr) ':)
            (pair? (cdr val-expr))
            (pair? (cddr val-expr))
            (linear-type? (caddr val-expr)))
       #t)
      ;; 4. Typed binding variable: (: c channel) or (c : channel) or (c channel)
      ((and (pair? var)
            (eq? (car var) ':)
            (pair? (cdr var))
            (pair? (cddr var))
            (linear-type? (caddr var)))
       #t)
      ((and (pair? var)
            (pair? (cdr var))
            (eq? (cadr var) ':)
            (pair? (cddr var))
            (linear-type? (caddr var)))
       #t)
      ((and (pair? var)
            (pair? (cdr var))
            (linear-type? (cadr var)))
       #t)
      ;; 5. Linear variable alias / move: (let ((c2 c1)) ...) where c1 is 'available in env
      ((and (symbol? val-expr) (eq? (lin-env-lookup env val-expr) 'available))
       #t)
      ;; 6. Function call returning a linear type via sig-env or registry (Issue #792)
      ((and (pair? val-expr)
            (symbol? (car val-expr))
            (let ((ret-ty (lookup-affine-signature (car val-expr) sig-env)))
              (and ret-ty (linear-type? ret-ty))))
       #t)
      ;; 7. Known non-linear literal or primitive arithmetic (CWE-843 False-Positive Protection)
      ((non-linear-literal? val-expr)
       #f)
      ((and (pair? val-expr)
            (memq (car val-expr) '(+ - * / modulo quotient remainder < > <= >= = eq? equal? zero? not cons list vector string-append)))
       #f)
      ;; NOTE (Issue #792): Variable name heuristic (linear-variable-name-hint?) is completely eliminated!
      ;; Variables named result, response, etc. will NEVER be inferred as linear.
      (else #f))))

(define (kernel-formal-var f)
  (cond
    ((symbol? f) f)
    ((and (pair? f) (eq? (car f) ':) (pair? (cdr f))) (cadr f))
    ((and (pair? f) (pair? (cdr f)) (eq? (cadr f) ':) (pair? (cddr f))) (car f))
    ((and (pair? f) (symbol? (car f))) (car f))
    (else f)))

(define (kernel-formal-linear? f)
  (cond
    ;; (: var type)
    ((and (pair? f) (eq? (car f) ':) (pair? (cdr f)) (pair? (cddr f)))
     (linear-type? (caddr f)))
    ;; (var : type)
    ((and (pair? f) (pair? (cdr f)) (eq? (cadr f) ':) (pair? (cddr f)))
     (linear-type? (caddr f)))
    ;; (var type)
    ((and (pair? f) (pair? (cdr f)) (linear-type? (cadr f)))
     #t)
    ;; Symbol formal without explicit linear type annotation is strictly non-linear (Issue #797)
    ((symbol? f)
     #f)
    (else #f)))

(define (lin-env-mark-moved env sym)
  (lin-env-set env sym 'moved))

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

(define (validate-affine-ast-internal expr env sig-env)
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
           (let ((r (validate-affine-ast-internal (car es) cur-env sig-env)))
             (if (eq? (car r) 'error)
                 r
                 (loop (cdr es) (cadr r)))))))

    ;; Conditional: (if test then [else])
    ((eq? (car expr) 'if)
     (let ((test-r (validate-affine-ast-internal (cadr expr) env sig-env)))
       (if (eq? (car test-r) 'error)
           test-r
           (let* ((env-after-test (cadr test-r))
                  (then-r (validate-affine-ast-internal (caddr expr) env-after-test sig-env)))
             (if (eq? (car then-r) 'error)
                 then-r
                 (if (not (pair? (cdddr expr)))
                     then-r
                     (let ((else-r (validate-affine-ast-internal (cadddr expr) env-after-test sig-env)))
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
                    (v (kernel-formal-var (car b)))
                    (val-expr (cadr b))
                    (val-r (validate-affine-ast-internal val-expr cur-env sig-env)))
               (if (eq? (car val-r) 'error)
                   val-r
                   (let* ((env-eval (cadr val-r))
                          (is-lin? (infer-linear-binding? (car b) val-expr env-eval sig-env))
                          ;; If val-expr is an existing linear symbol, transfer its ownership (mark moved)
                          (env-after (if (and (symbol? val-expr)
                                              (eq? (lin-env-lookup env-eval val-expr) 'available))
                                         (lin-env-set env-eval val-expr 'moved)
                                         env-eval))
                          (env-with-v (if is-lin?
                                          (lin-env-add-available env-after v)
                                          env-after)))
                     (init-loop (cdr bs)
                                env-with-v
                                (if is-lin? (cons v new-vars) new-vars)))))
             ;; Body validation
             (let ((body-r (validate-affine-ast-internal (cons 'begin bodies) cur-env sig-env)))
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
                       (r (validate-affine-ast-internal arg cur-env sig-env)))
                  (if (eq? (car r) 'error)
                      r
                      (loop (cdr as) (cadr r)))))))

         ;; Channel send operation: channel endpoint is borrowed; payload argument is moved if linear
         ((channel-send-operation? op)
          (if (null? args)
              (list 'ok env)
              (let* ((ch-arg (car args))
                     (ch-r (validate-affine-ast-internal ch-arg env sig-env)))
                (if (eq? (car ch-r) 'error)
                    ch-r
                    (let loop ((as (cdr args)) (cur-env (cadr ch-r)))
                      (if (null? as)
                          (list 'ok cur-env)
                          (let* ((arg (car as))
                                 (r (validate-affine-ast-internal arg cur-env sig-env)))
                            (if (eq? (car r) 'error)
                                r
                                (let* ((env-after (cadr r))
                                       (env-moved (if (and (symbol? arg) (lin-env-lookup env-after arg))
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
                       (r (validate-affine-ast-internal arg cur-env sig-env)))
                  (if (eq? (car r) 'error)
                      r
                      (let* ((env-after (cadr r))
                             (env-moved (if (and (symbol? arg) (lin-env-lookup env-after arg))
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
                       (r (validate-affine-ast-internal arg cur-env sig-env)))
                  (if (eq? (car r) 'error)
                      r
                      (let* ((env-after (cadr r))
                             (env-moved (if (and (symbol? arg) (lin-env-lookup env-after arg))
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

(define (validate-affine-ast expr init-env . opt-sig-env)
  (let ((sig-env (if (pair? opt-sig-env) (car opt-sig-env) '())))
    (validate-affine-ast-internal expr init-env sig-env)))

;;; -----------------------------------------------------------------------
;;; 4. AST Transformation with Automatic RAII Drop Injection
;;; -----------------------------------------------------------------------

(define (%unwrap-linear-annotation expr)
  (cond
    ((not (pair? expr)) expr)
    ((and (eq? (car expr) '!linear) (pair? (cdr expr)))
     (cadr expr))
    ((and (eq? (car expr) ':) (pair? (cdr expr)))
     (if (linear-type? (cadr expr))
         (if (pair? (cddr expr)) (caddr expr) (cadr expr))
         (cadr expr)))
    (else expr)))

(define (transform-affine-expr-internal expr env sig-env)
  (cond
    ((not (pair? expr))
     (cons expr env))

    ((eq? (car expr) 'quote)
     (cons expr env))

    ((eq? (car expr) 'begin)
     (let loop ((es (cdr expr)) (acc '()) (cur-env env))
       (if (null? es)
           (cons (cons 'begin (reverse acc)) cur-env)
           (let ((r (transform-affine-expr-internal (car es) cur-env sig-env)))
             (loop (cdr es) (cons (car r) acc) (cdr r))))))

    ((eq? (car expr) 'if)
     (let* ((test-r (transform-affine-expr-internal (cadr expr) env sig-env))
            (test-ast (car test-r))
            (env-after-test (cdr test-r))
            (then-r (transform-affine-expr-internal (caddr expr) env-after-test sig-env))
            (then-ast (car then-r))
            (env-after-then (cdr then-r))
            (has-else? (pair? (cdddr expr))))
       (if (not has-else?)
           (cons (list 'if test-ast then-ast) env-after-then)
           (let* ((else-r (transform-affine-expr-internal (cadddr expr) env-after-test sig-env))
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
                    (v (kernel-formal-var (car b)))
                    (val-expr (cadr b))
                    (val-r (transform-affine-expr-internal val-expr cur-env sig-env))
                    (val-ast (car val-r))
                    (env-eval (cdr val-r))
                    (is-lin? (infer-linear-binding? (car b) val-expr env-eval sig-env))
                    (unwrapped-ast (%unwrap-linear-annotation val-ast))
                    (opt-val-ast (if (and is-lin?
                                          (pair? unwrapped-ast)
                                          (eq? (car unwrapped-ast) 'make-channel))
                                     (cons 'make-spsc-channel (cdr unwrapped-ast))
                                     unwrapped-ast))
                    ;; If val-expr is an existing linear symbol, transfer ownership (mark moved)
                    (env-after (if (and (symbol? val-expr)
                                        (eq? (lin-env-lookup env-eval val-expr) 'available))
                                   (lin-env-set env-eval val-expr 'moved)
                                   env-eval))
                    (env-with-v (if is-lin?
                                    (lin-env-add-available env-after v)
                                    env-after)))
               (init-loop (cdr bs)
                          (cons (list v opt-val-ast) acc-b)
                          env-with-v
                          (if is-lin? (cons v new-vars) new-vars)))
             ;; Process body with new variables in scope
             (let* ((body-r (transform-affine-expr-internal (cons 'begin bodies) cur-env sig-env))
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
                       (r (transform-affine-expr-internal arg cur-env sig-env)))
                  (loop (cdr as) (cons (car r) acc-args) (cdr r))))))

         ;; Channel send operation: channel borrowed, linear payload moved
         ((channel-send-operation? op)
          (if (null? args)
              (cons (list op) env)
              (let* ((ch-arg (car args))
                     (ch-r (transform-affine-expr-internal ch-arg env sig-env))
                     (ch-ast (car ch-r))
                     (ch-env (cdr ch-r)))
                (let loop ((as (cdr args)) (acc-args (list ch-ast)) (cur-env ch-env))
                  (if (null? as)
                      (cons (cons op (reverse acc-args)) cur-env)
                      (let* ((arg (car as))
                             (r (transform-affine-expr-internal arg cur-env sig-env))
                             (arg-ast (car r))
                             (env-after (cdr r))
                             (env-moved (if (and (symbol? arg) (lin-env-lookup env-after arg))
                                            (lin-env-set env-after arg 'moved)
                                            env-after)))
                        (loop (cdr as) (cons arg-ast acc-args) env-moved)))))))

         ;; Channel consume operation: endpoint is moved
         ((channel-consume-operation? op)
          (let loop ((as args) (acc-args '()) (cur-env env))
            (if (null? as)
                (cons (cons op (reverse acc-args)) cur-env)
                (let* ((arg (car as))
                       (r (transform-affine-expr-internal arg cur-env sig-env))
                       (arg-ast (car r))
                       (env-after (cdr r))
                       (env-moved (if (and (symbol? arg) (lin-env-lookup env-after arg))
                                      (lin-env-set env-after arg 'moved)
                                      env-after)))
                  (loop (cdr as) (cons arg-ast acc-args) env-moved)))))

         ;; General application: linear arguments are moved
         (else
          (let loop ((as args) (acc-args '()) (cur-env env))
            (if (null? as)
                (cons (cons op (reverse acc-args)) cur-env)
                (let* ((arg (car as))
                       (r (transform-affine-expr-internal arg cur-env sig-env))
                       (arg-ast (car r))
                       (env-after (cdr r))
                       (env-moved (if (and (symbol? arg) (lin-env-lookup env-after arg))
                                      (lin-env-set env-after arg 'moved)
                                      env-after)))
                  (loop (cdr as) (cons arg-ast acc-args) env-moved))))))))

    (else
     (cons expr env))))

(define (transform-affine-expr expr env . opt-sig-env)
  (let ((sig-env (if (pair? opt-sig-env) (car opt-sig-env) '())))
    (transform-affine-expr-internal expr env sig-env)))

(define (check-affine-expr expr . opt-args)
  (let ((env (if (pair? opt-args) (car opt-args) '()))
        (sig-env (if (and (pair? opt-args) (pair? (cdr opt-args))) (cadr opt-args) '())))
    (car (transform-affine-expr expr env sig-env))))

;;; -----------------------------------------------------------------------
;;; 5. ASC Kernel Transformation & Kernel-Level RAII Drop
;;; -----------------------------------------------------------------------

(define (check-affine-kernel kernel-node . opt-sig-env)
  (let ((sig-env (if (pair? opt-sig-env) (car opt-sig-env) '())))
    (if (or (not (pair? kernel-node)) (not (eq? (car kernel-node) '%asc-kernel)))
        kernel-node
        (let* ((header (cadr kernel-node))
               (kname (car header))
               (formals (cdr header))
               (raw-formals (map kernel-formal-var formals))
               (norm-header (cons kname raw-formals))
               (body (if (pair? (cddr kernel-node))
                         (if (and (pair? (caddr kernel-node)) (eq? (car (caddr kernel-node)) 'begin))
                             (caddr kernel-node)
                             (cons 'begin (cddr kernel-node)))
                         '(begin #f)))
               ;; Initialize environment with linear formals (typed or hinted)
               (init-env (let loop ((fs formals) (acc '()))
                           (if (null? fs)
                               acc
                               (let* ((f (car fs))
                                      (var (kernel-formal-var f)))
                                 (if (kernel-formal-linear? f)
                                     (loop (cdr fs) (lin-env-add-available acc var))
                                     (loop (cdr fs) acc))))))
               ;; Validate first: report diagnostic errors on forbidden syntax or use-after-move
               (validation (validate-affine-ast body init-env sig-env)))
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
             (let* ((body-r (transform-affine-expr body init-env sig-env))
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
               (list '%asc-kernel norm-header wrapped-body))))))))

(define (check-affine-pass forms)
  (let ((sig-env (scan-form-signatures forms)))
    (map (lambda (form)
           (if (and (pair? form) (eq? (car form) '%asc-kernel))
               (check-affine-kernel form sig-env)
               form))
         forms)))

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
