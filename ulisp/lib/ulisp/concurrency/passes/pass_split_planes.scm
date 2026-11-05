;;; =======================================================================
;;; Synapse Concurrency Library: Plane Boundary Splitting Nanopass
;;; Path: lib/ulisp/concurrency/passes/pass_split_planes.scm
;;; Conforms to DSN-37 Section 1.2, 8.1, 12.1 & Phase 3 Task 3.1 (Issue #637)
;;;
;;; Pluggable Compiler Pass provided by (ulisp concurrency):
;;; Injected after pass-030-desugar via (inject-synapse-split-planes-pass!).
;;;
;;; Detects boundary expressions (spawn-task, with-channel) between
;;; Layer 1 (R7RS Control Plane) and Layer 2 (Affine Sub-language Core / ASC),
;;; analyzes captured free variables (immediate, deep-copy, linear-move),
;;; and splits the AST into host boundary bridges and extracted ASC kernels.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. String & Set Utility Helpers
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

(define (%set-union s1 s2)
  (let loop ((rest s1) (acc s2))
    (if (null? rest)
        acc
        (let ((item (car rest)))
          (if (memq item acc)
              (loop (cdr rest) acc)
              (loop (cdr rest) (cons item acc)))))))

(define (%set-difference s1 s2)
  (let loop ((rest s1) (acc '()))
    (if (null? rest)
        (reverse acc)
        (let ((item (car rest)))
          (if (memq item s2)
              (loop (cdr rest) acc)
              (loop (cdr rest) (cons item acc)))))))

;;; -----------------------------------------------------------------------
;;; 2. Free Variable Capture Analysis
;;; -----------------------------------------------------------------------

(define (%extract-formals-list formals)
  (cond
    ((null? formals) '())
    ((symbol? formals) (list formals))
    ((pair? formals)
     (cons (car formals) (%extract-formals-list (cdr formals))))
    (else '())))

(define (%extract-free-vars-list exprs bound-env)
  (let loop ((es exprs) (acc '()))
    (if (null? es)
        acc
        (let ((fvs (extract-free-variables (car es) bound-env)))
          (loop (cdr es) (%set-union fvs acc))))))

(define (scheme-builtin-symbol? s)
  (or (memq s '(+ - * / = < <= > >= modulo quotient
                eq? eqv? equal? not null? boolean? symbol? number? integer? real? pair?
                cons car cdr set-car! set-cdr!
                vector make-vector vector-ref vector-set! vector-length
                string make-string string-ref string-set! string-length
                display write newline error
                send! recv! channel-send! channel-recv! yield! safepoint!))
      (and (symbol? s) (%str-starts-with? "%" (symbol->string s)))))

(define (extract-free-variables expr bound-env)
  (cond
    ;; Symbols: free if not in bound-env and not a built-in primitive
    ((symbol? expr)
     (if (or (memq expr bound-env) (scheme-builtin-symbol? expr))
         '()
         (list expr)))

    ;; Non-pair literals (numbers, booleans, chars, strings, bytevectors)
    ((not (pair? expr))
     '())

    ;; Quoted constants: no free variables
    ((eq? (car expr) 'quote)
     '())

    ;; Conditional (if test then [else])
    ((eq? (car expr) 'if)
     (%extract-free-vars-list (cdr expr) bound-env))

    ;; Sequence (begin expr ...)
    ((eq? (car expr) 'begin)
     (%extract-free-vars-list (cdr expr) bound-env))

    ;; Assignment (set! var val)
    ((eq? (car expr) 'set!)
     (let* ((var (cadr expr))
            (val (caddr expr))
            (var-fvs (if (memq var bound-env) '() (list var)))
            (val-fvs (extract-free-variables val bound-env)))
       (%set-union var-fvs val-fvs)))

    ;; Lambda abstraction (lambda formals body ...)
    ((eq? (car expr) 'lambda)
     (let* ((formals (%extract-formals-list (cadr expr)))
            (bodies (cddr expr))
            (new-env (%set-union formals bound-env)))
       (%extract-free-vars-list bodies new-env)))

    ;; Local binding (let ((var val) ...) body ...) or named-let (let name ((var val) ...) body ...)
    ((and (eq? (car expr) 'let) (pair? (cdr expr)))
     (let* ((is-named? (symbol? (cadr expr)))
            (loop-name (if is-named? (cadr expr) #f))
            (bindings (if is-named? (caddr expr) (cadr expr)))
            (bodies (if is-named? (cdddr expr) (cddr expr)))
            (vars (map car bindings))
            (vals (map cadr bindings))
            (val-fvs (%extract-free-vars-list vals bound-env))
            (inner-bound (if is-named?
                             (%set-union (cons loop-name vars) bound-env)
                             (%set-union vars bound-env)))
            (body-fvs (%extract-free-vars-list bodies inner-bound)))
       (%set-union val-fvs body-fvs)))

    ;; Sequential binding (let* ((var val) ...) body ...)
    ((eq? (car expr) 'let*)
     (let loop ((b-rest (cadr expr)) (cur-env bound-env) (accum-fvs '()))
       (if (null? b-rest)
           (let ((body-fvs (%extract-free-vars-list (cddr expr) cur-env)))
             (%set-union accum-fvs body-fvs))
           (let* ((b (car b-rest))
                  (var (car b))
                  (val (cadr b))
                  (vfvs (extract-free-variables val cur-env)))
             (loop (cdr b-rest) (cons var cur-env) (%set-union accum-fvs vfvs))))))

    ;; Recursive binding (letrec ((var val) ...) body ...)
    ((eq? (car expr) 'letrec)
     (let* ((bindings (cadr expr))
            (bodies (cddr expr))
            (vars (map car bindings))
            (vals (map cadr bindings))
            (rec-env (%set-union vars bound-env))
            (val-fvs (%extract-free-vars-list vals rec-env))
            (body-fvs (%extract-free-vars-list bodies rec-env)))
       (%set-union val-fvs body-fvs)))

    ;; Boundary syntax: spawn-task
    ((eq? (car expr) 'spawn-task)
     (let ((bodies (if (and (pair? (cdr expr)) (pair? (cadr expr)) (not (symbol? (caadr expr))))
                       (cddr expr)
                       (cdr expr))))
       (%extract-free-vars-list bodies bound-env)))

    ;; Boundary syntax: with-channel
    ((eq? (car expr) 'with-channel)
     (let* ((chan-spec (cadr expr))
            (rx-sym (car chan-spec))
            (tx-sym (cadr chan-spec))
            (cap-expr (if (pair? (cddr chan-spec)) (caddr chan-spec) #f))
            (cap-fvs (if cap-expr (extract-free-variables cap-expr bound-env) '()))
            (inner-env (cons rx-sym (cons tx-sym bound-env)))
            (bodies (cddr expr))
            (body-fvs (%extract-free-vars-list bodies inner-env)))
       (%set-union cap-fvs body-fvs)))

    ;; General application (fn arg ...)
    (else
     (%extract-free-vars-list expr bound-env))))

;;; -----------------------------------------------------------------------
;;; 3. Capture Mode Classification (DSN-37 Section 8.1 & 12.1)
;;; -----------------------------------------------------------------------

(define (classify-capture-mode var)
  (if (not (symbol? var))
      (error "classify-capture-mode: expected symbol" var)
      (let ((s (symbol->string var)))
        (cond
          ;; Channel endpoints: Linear Ownership Transfer ('linear-move)
          ((or (%str-starts-with? "chan" s)
               (%str-starts-with? "rx" s)
               (%str-starts-with? "tx" s)
               (%str-ends-with? "-ch" s)
               (%str-ends-with? "-chan" s)
               (%str-ends-with? "-channel" s))
           'linear-move)

          ;; Immediate primitives, counters, indices, flags ('immediate)
          ((or (%str-starts-with? "n" s)
               (%str-starts-with? "i" s)
               (%str-starts-with? "idx" s)
               (%str-starts-with? "count" s)
               (%str-starts-with? "len" s)
               (%str-starts-with? "size" s)
               (%str-starts-with? "max" s)
               (%str-starts-with? "min" s)
               (%str-starts-with? "flag" s)
               (%str-starts-with? "is-" s)
               (%str-ends-with? "?" s))
           'immediate)

          ;; Composite objects, collections, records: Shared-Nothing Deep Copy ('deep-copy)
          (else
           'deep-copy)))))

;;; -----------------------------------------------------------------------
;;; 4. Plane Boundary Splitting AST Transformation
;;; -----------------------------------------------------------------------

(define *asc-kernel-counter* (vector 0))

(define (reset-asc-kernel-counter!)
  (vector-set! *asc-kernel-counter* 0 0))

(define (%next-asc-kernel-name)
  (let* ((c (vector-ref *asc-kernel-counter* 0))
         (next (+ c 1)))
    (vector-set! *asc-kernel-counter* 0 next)
    (string->symbol (string-append "%asc-kernel-" (number->string next)))))

(define (asc-kernel? expr)
  (and (pair? expr)
       (eq? (car expr) '%asc-kernel)))

(define (boundary-bridge? expr)
  (and (pair? expr)
       (eq? (car expr) '%boundary-bridge)))

(define (%split-spawn-task expr)
  (if (or (not (pair? expr)) (not (eq? (car expr) 'spawn-task)))
      (error "%split-spawn-task: expected spawn-task expression" expr)
      (let* ((has-opts? (and (pair? (cdr expr))
                             (pair? (cadr expr))
                             (not (symbol? (caadr expr)))))
             (options (if has-opts? (cadr expr) '()))
             (bodies (if has-opts? (cddr expr) (cdr expr))))
        (if (null? bodies)
            (error "spawn-task: empty task body (CWE-843)" expr)
            (let* ((kname (%next-asc-kernel-name))
                   (fvars (extract-free-variables (cons 'begin bodies) '()))
                   (captures (map (lambda (v) (list v (classify-capture-mode v))) fvars))
                   (kernel-node (list '%asc-kernel (cons kname fvars) (cons 'begin bodies)))
                   (bridge-node (list '%boundary-bridge
                                      captures
                                      kname
                                      (cons 'spawn-task (cons kname fvars)))))
              (cons bridge-node (list kernel-node)))))))

(define (%split-with-channel expr)
  (if (or (not (pair? expr)) (not (eq? (car expr) 'with-channel)))
      (error "%split-with-channel: expected with-channel expression" expr)
      (let* ((chan-spec (cadr expr))
             (rx-sym (car chan-spec))
             (tx-sym (cadr chan-spec))
             (cap-expr (if (pair? (cddr chan-spec)) (caddr chan-spec) 0))
             (bodies (cddr expr)))
        (if (null? bodies)
            (error "with-channel: empty body (CWE-843)" expr)
            (let* ((kname (%next-asc-kernel-name))
                   (inner-env (list rx-sym tx-sym))
                   (fvars (extract-free-variables (cons 'begin bodies) inner-env))
                   (captures (map (lambda (v) (list v (classify-capture-mode v))) fvars))
                   (kernel-formals (append (list rx-sym tx-sym) fvars))
                   (kernel-node (list '%asc-kernel (cons kname kernel-formals) (cons 'begin bodies)))
                   (bridge-node (list '%boundary-bridge
                                      captures
                                      kname
                                      (list 'with-channel (list rx-sym tx-sym cap-expr)
                                            (cons kname kernel-formals)))))
              (cons bridge-node (list kernel-node)))))))

;; Main AST recursive walk
(define (split-planes-ast expr)
  (cond
    ((not (pair? expr))
     (cons expr '()))

    ((eq? (car expr) 'quote)
     (cons expr '()))

    ((eq? (car expr) 'spawn-task)
     (%split-spawn-task expr))

    ((eq? (car expr) 'with-channel)
     (%split-with-channel expr))

    ((eq? (car expr) 'define)
     (if (and (pair? (cdr expr)) (pair? (cddr expr)))
         (let* ((var (cadr expr))
                (val-res (split-planes-ast (caddr expr))))
           (cons (list 'define var (car val-res))
                 (cdr val-res)))
         (cons expr '())))

    ((eq? (car expr) 'if)
     (let* ((t-res (split-planes-ast (cadr expr)))
            (c-res (split-planes-ast (caddr expr)))
            (a-res (if (pair? (cdddr expr))
                       (split-planes-ast (cadddr expr))
                       (cons #f '())))
            (new-expr (if (pair? (cdddr expr))
                          (list 'if (car t-res) (car c-res) (car a-res))
                          (list 'if (car t-res) (car c-res))))
            (all-kernels (append (cdr t-res) (append (cdr c-res) (cdr a-res)))))
       (cons new-expr all-kernels)))

    ((eq? (car expr) 'begin)
     (let loop ((items (cdr expr)) (acc-items '()) (acc-k '()))
       (if (null? items)
           (cons (cons 'begin (reverse acc-items)) acc-k)
           (let ((res (split-planes-ast (car items))))
             (loop (cdr items)
                   (cons (car res) acc-items)
                   (append acc-k (cdr res)))))))

    ((eq? (car expr) 'lambda)
     (let* ((formals (cadr expr))
            (b-res (split-planes-ast (cons 'begin (cddr expr))))
            (b-expr (car b-res))
            (actual-bodies (if (and (pair? b-expr) (eq? (car b-expr) 'begin))
                               (cdr b-expr)
                               (list b-expr))))
       (cons (cons 'lambda (cons formals actual-bodies))
             (cdr b-res))))

    ((and (eq? (car expr) 'let) (pair? (cdr expr)))
     (let* ((is-named? (symbol? (cadr expr)))
            (loop-name (if is-named? (cadr expr) #f))
            (bindings (if is-named? (caddr expr) (cadr expr)))
            (bodies (if is-named? (cdddr expr) (cddr expr)))
            (body-res (split-planes-ast (cons 'begin bodies)))
            (b-expr (car body-res))
            (actual-bodies (if (and (pair? b-expr) (eq? (car b-expr) 'begin))
                               (cdr b-expr)
                               (list b-expr))))
       (let loop ((bs bindings) (acc-b '()) (acc-k (cdr body-res)))
         (if (null? bs)
             (cons (if is-named?
                       (cons 'let (cons loop-name (cons (reverse acc-b) actual-bodies)))
                       (cons 'let (cons (reverse acc-b) actual-bodies)))
                   acc-k)
             (let* ((b (car bs))
                    (v (car b))
                    (init-res (split-planes-ast (cadr b))))
               (loop (cdr bs)
                     (cons (list v (car init-res)) acc-b)
                     (append acc-k (cdr init-res))))))))

    (else
     ;; General application
     (let loop ((elems expr) (acc-elems '()) (acc-k '()))
       (if (null? elems)
           (cons (reverse acc-elems) acc-k)
           (let ((res (split-planes-ast (car elems))))
             (loop (cdr elems)
                   (cons (car res) acc-elems)
                   (append acc-k (cdr res)))))))))

(define (split-planes-pass forms)
  (let loop ((fs forms) (res-forms '()) (res-kernels '()))
    (if (null? fs)
        (append (reverse res-forms) res-kernels)
        (let ((r (split-planes-ast (car fs))))
          (loop (cdr fs)
                (cons (car r) res-forms)
                (append res-kernels (cdr r)))))))

;;; -----------------------------------------------------------------------
;;; 5. Pluggable Pass Injection & Registration API
;;; -----------------------------------------------------------------------

(define (synapse-split-planes-descriptor)
  (make-pass-descriptor
    'pass-synapse-split-planes
    "Synapse Dual-Plane Boundary Splitting"
    'frontend
    0
    split-planes-pass
    #f
    'L_core
    'L_core
    '(pass-030-desugar)
    #t))

(define (inject-synapse-split-planes-pass!)
  (inject-pass-after! 'pass-030-desugar (synapse-split-planes-descriptor)))

(define (remove-synapse-split-planes-pass!)
  (remove-injected-pass! 'pass-synapse-split-planes))
