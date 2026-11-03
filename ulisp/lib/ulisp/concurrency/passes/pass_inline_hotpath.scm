;;; =======================================================================
;;; Synapse Concurrency Library: Concurrency Hotpath Inlining & Type Check Elimination Pass
;;; Path: lib/ulisp/concurrency/passes/pass_inline_hotpath.scm
;;; Conforms to DSN-37 Section 4.3, 12.4 & Phase 4 Task 4.1 (Issue #682)
;;;
;;; Pluggable Compiler Pass provided by (ulisp concurrency):
;;; Injected after pass-synapse-fbip and before pass-synapse-inject-safepoints
;;; via (inject-synapse-inline-hotpath-pass!).
;;;
;;; Optimizations performed on statically verified ASC kernels:
;;;   1. Redundant Type Check Elimination:
;;;      Removes runtime defensive type assertions ((channel? c), (task-arena? a), etc.)
;;;      when the resource provenance is statically proven in the type environment.
;;;   2. Hotpath Primitive Inlining:
;;;      Inlines arena bump-pointer allocation, arena reset, and lock-free atomic
;;;      operations into raw low-overhead AST forms, eliminating procedure call
;;;      prologue/epilogue overhead.
;;;   3. CWE-843 / CWE-119 / CWE-362 Safety Guarantees:
;;;      Unproven or dynamic variables retain full defensive checks; inlined arena
;;;      allocations strictly preserve chunk capacity boundary guards.
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

(define (linear-var-name? sym)
  (if (not (symbol? sym))
      #f
      (let ((s (symbol->string sym)))
        (or (%str-starts-with? "chan" s)
            (%str-starts-with? "rx" s)
            (%str-starts-with? "tx" s)
            (%str-starts-with? "buf" s)
            (%str-starts-with? "res" s)
            (%str-ends-with? "-ch" s)
            (%str-ends-with? "-chan" s)
            (%str-ends-with? "-channel" s)
            (%str-ends-with? "-res" s)
            (%str-ends-with? "-buf" s)))))

(define (arena-var-name? sym)
  (if (not (symbol? sym))
      #f
      (let ((s (symbol->string sym)))
        (or (string=? s "arena")
            (%str-starts-with? "arena" s)
            (%str-ends-with? "-arena" s)))))

(define (atomic-box-var-name? sym)
  (if (not (symbol? sym))
      #f
      (let ((s (symbol->string sym)))
        (or (string=? s "box")
            (%str-starts-with? "box" s)
            (%str-ends-with? "-box" s)
            (%str-starts-with? "atomic" s)
            (%str-ends-with? "-atomic" s)))))

(define (task-var-name? sym)
  (if (not (symbol? sym))
      #f
      (let ((s (symbol->string sym)))
        (or (string=? s "task")
            (%str-starts-with? "task" s)
            (%str-ends-with? "-task" s)))))

(define (eliminated-assertion? expr)
  (eq? expr '%eliminated-assertion%))

(define (clean-sequence expr-list)
  (let ((filtered (let filter-loop ((items expr-list))
                    (cond
                      ((null? items) '())
                      ((eliminated-assertion? (car items))
                       (filter-loop (cdr items)))
                      (else
                       (cons (car items) (filter-loop (cdr items))))))))
    (if (null? filtered)
        (list #t)
        filtered)))

;;; -----------------------------------------------------------------------
;;; 2. Type Environment Management (type-env)
;;; -----------------------------------------------------------------------
;;; An environment is an alist: symbol -> 'channel | 'ephemeral-arena | 'atomic-box | 'padded-atomic-box | 'task-context

(define (make-type-env)
  '())

(define (type-env-lookup env sym)
  (let ((entry (assq sym env)))
    (if entry
        (cdr entry)
        #f)))

(define (type-env-extend env sym type)
  (cons (cons sym type) env))

(define (statically-typed? env sym expected-type)
  (let ((actual (type-env-lookup env sym)))
    (cond
      ((not actual) #f)
      ((eq? actual expected-type) #t)
      ;; Compatible atomic types
      ((and (eq? expected-type 'atomic-box) (eq? actual 'padded-atomic-box)) #t)
      ((and (eq? expected-type 'padded-atomic-box) (eq? actual 'atomic-box)) #t)
      (else #f))))

(define (infer-init-type rhs env)
  (cond
    ((not (pair? rhs))
     (if (symbol? rhs)
         (type-env-lookup env rhs)
         #f))
    ((memq (car rhs) '(make-channel make-spsc-channel make-channel-internal make-bounded-channel))
     'channel)
    ((memq (car rhs) '(make-task-arena make-ephemeral-arena make-arena %init-task-arena))
     'ephemeral-arena)
    ((eq? (car rhs) 'make-atomic-box)
     'atomic-box)
    ((eq? (car rhs) 'make-padded-atomic-box)
     'padded-atomic-box)
    ((memq (car rhs) '(make-task-context %make-task-context))
     'task-context)
    (else #f)))

;;; -----------------------------------------------------------------------
;;; 3. Redundant Type Check Elimination
;;; -----------------------------------------------------------------------

(define (type-predicate-match? op v env)
  (cond
    ((memq op '(channel? linear-channel? %channel?))
     (if (statically-typed? env v 'channel) 'always-true 'unknown))
    ((memq op '(task-arena? ephemeral-arena? arena? %task-arena?))
     (if (statically-typed? env v 'ephemeral-arena) 'always-true 'unknown))
    ((memq op '(atomic-box? padded-atomic-box? %atomic-box?))
     (if (or (statically-typed? env v 'atomic-box)
             (statically-typed? env v 'padded-atomic-box))
         'always-true
         'unknown))
    ((memq op '(task-context? %task-context?))
     (if (statically-typed? env v 'task-context) 'always-true 'unknown))
    (else 'unknown)))

(define (evaluate-statically-checked-test test-expr env)
  ;; Returns 'always-true | 'always-false | 'unknown
  (cond
    ((not (pair? test-expr)) 'unknown)

    ;; Direct positive check: (predicate? var)
    ((and (symbol? (car test-expr))
          (pair? (cdr test-expr))
          (symbol? (cadr test-expr))
          (null? (cddr test-expr)))
     (let ((op (car test-expr))
           (v (cadr test-expr)))
       (type-predicate-match? op v env)))

    ;; Inverted check: (not (predicate? var))
    ((and (eq? (car test-expr) 'not)
          (pair? (cdr test-expr))
          (pair? (cadr test-expr))
          (null? (cddr test-expr)))
     (let ((inner-status (evaluate-statically-checked-test (cadr test-expr) env)))
       (cond
         ((eq? inner-status 'always-true) 'always-false)
         ((eq? inner-status 'always-false) 'always-true)
         (else 'unknown))))

    (else 'unknown)))

;;; -----------------------------------------------------------------------
;;; 4. Concurrency Hotpath Inlining Transformations
;;; -----------------------------------------------------------------------

(define (inline-arena-alloc-expr arena-expr size-expr)
  ;; Fast-path bump pointer allocation:
  ;; Reads chunk offset, checks against capacity, and directly updates offset
  ;; without calling %arena-allocate-impl! or performing redundant task-arena? checks.
  ;; CWE-190 guard: the size range check of %arena-allocate-impl! is preserved
  ;; inline; any invalid size is dispatched to the fully-checked slow path.
  (list 'let* (list (list '%%arena arena-expr)
                    (list '%%sz size-expr))
        '(if (and (integer? %%sz) (> %%sz 0) (<= %%sz 1048576))
             (let* ((%%aligned (bitwise-and (+ %%sz 7) -8))
                    (%%off (arena-offset %%arena))
                    (%%next (+ %%off %%aligned)))
               (if (and (null? (arena-chunks %%arena))
                        (<= %%next (arena-capacity %%arena)))
                   (begin
                     (arena-offset-set! %%arena %%next)
                     (arena-total-allocated-set! %%arena (+ (arena-total-allocated %%arena) %%aligned))
                     (+ (arena-base %%arena) %%off))
                   (arena-allocate! %%arena %%sz)))
             (arena-allocate! %%arena %%sz))))

(define (inline-arena-reset-expr arena-expr)
  ;; Fast-path O(1) instant reset without type check
  (list 'let (list (list '%%arena arena-expr))
        '(begin
           (arena-offset-set! %%arena 0)
           (if (not (null? (arena-chunks %%arena)))
               (begin
                 (arena-chunks-set! %%arena '())
                 (arena-chunk-count-set! %%arena 0)))
           (arena-reset-count-set! %%arena (+ (arena-reset-count %%arena) 1))
           #t)))

(define (inline-atomic-ref-expr box-expr)
  ;; Direct accessor bypassing cond type discrimination
  (list '%atomic-box-val box-expr))

(define (inline-atomic-set-expr box-expr val-expr)
  ;; Direct value set with hardware memory fence
  (list 'let (list (list '%%b box-expr)
                   (list '%%v val-expr))
        '(begin
           (%atomic-box-val-set! %%b %%v)
           (%memory-fence)
           %%v)))

(define (inline-atomic-cas-expr box-expr exp-expr new-expr)
  ;; Direct hardware LOCK CMPXCHG primitive
  (list '%atomic-cas! box-expr exp-expr new-expr))

;;; -----------------------------------------------------------------------
;;; 5. Recursive AST Rewriter & Pass Engine
;;; -----------------------------------------------------------------------

(define (inline-hotpath-expr expr env)
  (cond
    ;; Atom (symbol, number, string, boolean, etc.)
    ((not (pair? expr)) expr)

    ;; Quoted constant: preserve as-is
    ((eq? (car expr) 'quote) expr)

    ;; 1. If-conditional: evaluate static type checks
    ((and (eq? (car expr) 'if) (pair? (cdr expr)) (pair? (cddr expr)))
     (let* ((test (cadr expr))
            (conseq (caddr expr))
            (alt (if (null? (cdddr expr)) #f (cadddr expr)))
            (static-status (evaluate-statically-checked-test test env)))
       (cond
         ((eq? static-status 'always-true)
          ;; Consequent is guaranteed: eliminate the condition entirely
          (inline-hotpath-expr conseq env))
         ((eq? static-status 'always-false)
          ;; Condition is statically false:
          (if alt
              (inline-hotpath-expr alt env)
              ;; If no alternate branch was provided, this was a defensive assertion guard
              '%eliminated-assertion%))
         (else
          ;; Unproven condition: retain defensive runtime if-branch
          (let ((trans-test (inline-hotpath-expr test env))
                (trans-conseq (inline-hotpath-expr conseq env))
                (trans-alt (if alt (inline-hotpath-expr alt env) #f)))
            (if trans-alt
                (list 'if trans-test trans-conseq trans-alt)
                (list 'if trans-test trans-conseq)))))))

    ;; 2a. Named let loops: loop name and loop variables shadow outer types
    ((and (eq? (car expr) 'let)
          (pair? (cdr expr))
          (symbol? (cadr expr))
          (pair? (cddr expr)))
     (let* ((loop-name (cadr expr))
            (bindings (caddr expr))
            (body (cdddr expr))
            (trans-bindings
              (map (lambda (b)
                     (if (pair? b)
                         (list (car b) (inline-hotpath-expr (cadr b) env))
                         b))
                   bindings))
            (loop-env (let b-loop ((bs bindings)
                                   (cur-env (type-env-extend env loop-name #f)))
                        (if (null? bs)
                            cur-env
                            (b-loop (cdr bs)
                                    (if (pair? (car bs))
                                        (type-env-extend cur-env (caar bs) #f)
                                        cur-env)))))
            (raw-body (map (lambda (e) (inline-hotpath-expr e loop-env)) body))
            (cleaned-body (clean-sequence raw-body)))
       (cons 'let (cons loop-name (cons trans-bindings cleaned-body)))))

    ;; 2b. Let-bindings: track provenance in type-env and clean dead statements
    ((and (eq? (car expr) 'let)
          (pair? (cdr expr))
          (not (symbol? (cadr expr))) ; standard let
          (pair? (cddr expr)))
     (let* ((bindings (cadr expr))
            (body (cddr expr))
            ;; Build inner environment
            (new-env (let bind-loop ((bs bindings) (cur-env env))
                       (if (null? bs)
                           cur-env
                           (let* ((b (car bs))
                                  (var (car b))
                                  (rhs (cadr b))
                                  (inferred (infer-init-type rhs cur-env))
                                  ;; CWE-843: local bindings are typed only by constructor provenance
                                  (final-type inferred))
                             ;; Always extend so inner bindings shadow outer types
                             (bind-loop (cdr bs)
                                        (type-env-extend cur-env var final-type))))))
            (trans-bindings
              (map (lambda (b)
                     (list (car b) (inline-hotpath-expr (cadr b) env)))
                   bindings))
            (raw-body
              (map (lambda (e) (inline-hotpath-expr e new-env)) body))
            (cleaned-body (clean-sequence raw-body)))
       (cons 'let (cons trans-bindings cleaned-body))))

    ;; 3. Let*-bindings: sequential type propagation
    ((and (eq? (car expr) 'let*)
          (pair? (cdr expr))
          (pair? (cddr expr)))
     (let* ((bindings (cadr expr))
            (body (cddr expr))
            (pair-res (let seq-loop ((bs bindings) (cur-env env) (acc-b '()))
                        (if (null? bs)
                            (cons (reverse acc-b) cur-env)
                            (let* ((b (car bs))
                                   (var (car b))
                                   (rhs (cadr b))
                                   (trans-rhs (inline-hotpath-expr rhs cur-env))
                                   (inferred (infer-init-type rhs cur-env))
                                   ;; CWE-843: local bindings are typed only by constructor provenance
                                   (final-type inferred)
                                   ;; Always extend so inner bindings shadow outer types
                                   (next-env (type-env-extend cur-env var final-type)))
                              (seq-loop (cdr bs)
                                        next-env
                                        (cons (list var trans-rhs) acc-b))))))
            (trans-bindings (car pair-res))
            (final-env (cdr pair-res))
            (raw-body (map (lambda (e) (inline-hotpath-expr e final-env)) body))
            (cleaned-body (clean-sequence raw-body)))
       (cons 'let* (cons trans-bindings cleaned-body))))

    ;; 4. Begin block: clean up eliminated assertions
    ((eq? (car expr) 'begin)
     (let* ((raw-elems (map (lambda (e) (inline-hotpath-expr e env)) (cdr expr)))
            (cleaned (clean-sequence raw-elems)))
       (if (= (length cleaned) 1)
           (car cleaned)
           (cons 'begin cleaned))))

    ;; 5. Lambda expressions: bind parameter types
    ((and (eq? (car expr) 'lambda)
          (pair? (cdr expr))
          (pair? (cddr expr)))
     (let* ((params (cadr expr))
            (body (cddr expr))
            (new-env (let p-loop ((ps params) (cur-env env))
                       (cond
                         ((null? ps) cur-env)
                         ;; Rest parameter (variadic or dotted tail)
                         ((symbol? ps) (type-env-extend cur-env ps #f))
                         ;; Inner lambda params are not verified by check-affine:
                         ;; shadow them with an unknown type (CWE-843 fail-safe)
                         ((pair? ps) (p-loop (cdr ps) (type-env-extend cur-env (car ps) #f)))
                         (else cur-env))))
            (raw-body (map (lambda (e) (inline-hotpath-expr e new-env)) body))
            (cleaned-body (clean-sequence raw-body)))
       (cons 'lambda (cons params cleaned-body))))

    ;; 6. Hotpath Primitive Applications
    ;; a) arena-allocate!
    ((and (memq (car expr) '(arena-allocate! arena-alloc!))
          (pair? (cdr expr))
          (pair? (cddr expr))
          (null? (cdddr expr)))
     (let ((arena-arg (cadr expr))
           (size-arg (caddr expr)))
       (if (and (symbol? arena-arg) (statically-typed? env arena-arg 'ephemeral-arena))
           (inline-arena-alloc-expr (inline-hotpath-expr arena-arg env)
                                   (inline-hotpath-expr size-arg env))
           (map (lambda (e) (inline-hotpath-expr e env)) expr))))

    ;; b) arena-reset!
    ((and (eq? (car expr) 'arena-reset!)
          (pair? (cdr expr))
          (null? (cddr expr)))
     (let ((arena-arg (cadr expr)))
       (if (and (symbol? arena-arg) (statically-typed? env arena-arg 'ephemeral-arena))
           (inline-arena-reset-expr (inline-hotpath-expr arena-arg env))
           (map (lambda (e) (inline-hotpath-expr e env)) expr))))

    ;; c) atomic-ref
    ((and (memq (car expr) '(atomic-ref atomic-box-ref))
          (pair? (cdr expr))
          (null? (cddr expr)))
     (let ((box-arg (cadr expr)))
       (if (and (symbol? box-arg) (statically-typed? env box-arg 'atomic-box))
           (inline-atomic-ref-expr (inline-hotpath-expr box-arg env))
           (map (lambda (e) (inline-hotpath-expr e env)) expr))))

    ;; d) atomic-set!
    ((and (memq (car expr) '(atomic-set! atomic-box-set!))
          (pair? (cdr expr))
          (pair? (cddr expr))
          (null? (cdddr expr)))
     (let ((box-arg (cadr expr))
           (val-arg (caddr expr)))
       (if (and (symbol? box-arg) (statically-typed? env box-arg 'atomic-box))
           (inline-atomic-set-expr (inline-hotpath-expr box-arg env)
                                  (inline-hotpath-expr val-arg env))
           (map (lambda (e) (inline-hotpath-expr e env)) expr))))

    ;; e) atomic-cas!
    ((and (eq? (car expr) 'atomic-cas!)
          (pair? (cdr expr))
          (pair? (cddr expr))
          (pair? (cdddr expr))
          (null? (cddddr expr)))
     (let ((box-arg (cadr expr))
           (exp-arg (caddr expr))
           (new-arg (cadddr expr)))
       (if (and (symbol? box-arg) (statically-typed? env box-arg 'atomic-box))
           (inline-atomic-cas-expr (inline-hotpath-expr box-arg env)
                                  (inline-hotpath-expr exp-arg env)
                                  (inline-hotpath-expr new-arg env))
           (map (lambda (e) (inline-hotpath-expr e env)) expr))))

    ;; General application / recursive walk
    (else
     (map (lambda (e) (inline-hotpath-expr e env)) expr))))

;;; -----------------------------------------------------------------------
;;; 6. ASC Kernel Transformation
;;; -----------------------------------------------------------------------

(define (inline-hotpath-kernel kernel-node)
  (if (or (not (pair? kernel-node)) (not (eq? (car kernel-node) '%asc-kernel)))
      kernel-node
      (let* ((header (cadr kernel-node))
             (body (cddr kernel-node))
             ;; Initialize environment with kernel parameter types
             (params (if (pair? header) (cdr header) '()))
             (init-env (let p-loop ((ps params) (cur-env (make-type-env)))
                         (if (null? ps)
                             cur-env
                             (let* ((p (car ps))
                                    (type (cond
                                            ((linear-var-name? p) 'channel)
                                            ((arena-var-name? p) 'ephemeral-arena)
                                            ((atomic-box-var-name? p) 'atomic-box)
                                            ((task-var-name? p) 'task-context)
                                            (else #f))))
                               (p-loop (cdr ps)
                                       (if type (type-env-extend cur-env p type) cur-env))))))
             (raw-body (map (lambda (e) (inline-hotpath-expr e init-env)) body))
             (cleaned-body (clean-sequence raw-body)))
        (cons '%asc-kernel (cons header cleaned-body)))))

(define (eliminate-redundant-type-checks expr env)
  (inline-hotpath-expr expr env))

(define (inline-concurrency-primitives expr env)
  (inline-hotpath-expr expr env))

(define (inline-hotpath-pass forms)
  (map (lambda (form)
         (if (and (pair? form) (eq? (car form) '%asc-kernel))
             (inline-hotpath-kernel form)
             form))
       forms))

;;; -----------------------------------------------------------------------
;;; 7. Pluggable Pass Injection & Registration API
;;; -----------------------------------------------------------------------

(define (synapse-inline-hotpath-descriptor)
  (make-pass-descriptor
    'pass-synapse-inline-hotpath
    "Synapse Concurrency Hotpath Inlining & Type Check Elimination Pass"
    'frontend
    0
    inline-hotpath-pass
    #f
    'L_core
    'L_core
    '(pass-synapse-fbip)
    #t))

(define (inject-synapse-inline-hotpath-pass!)
  ;; Canonical order: fbip -> inline-hotpath -> inject-safepoints.
  ;; If the safepoint pass is already registered, insert directly before it.
  (if (pass-registered? 'pass-synapse-inject-safepoints)
      (inject-pass-before! 'pass-synapse-inject-safepoints (synapse-inline-hotpath-descriptor))
      (inject-pass-after! 'pass-synapse-fbip (synapse-inline-hotpath-descriptor))))

(define (remove-synapse-inline-hotpath-pass!)
  (remove-injected-pass! 'pass-synapse-inline-hotpath))

