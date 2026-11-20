;;; =======================================================================
;;; ULisp Compiler: Nanopass AST Constant Evaluator & CTFE Framework
;;; Conforms to DSN-38 §2, DSN-33 §3.1 & Issue #825
;;; =======================================================================
;;; Provides:
;;; - eval-in-language: Compile-Time Function Execution (CTFE) & AST reduction
;;; - define-evaluator-for-language: DSL for intermediate language evaluators
;;; - Resource-bounded evaluation (Fuel step limit & recursion depth limit)
;;;   to prevent denial-of-service / infinite compilation loops (CWE-400).
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; Resource Budget & Safety Parameters (CWE-400 Guards)
;;; -----------------------------------------------------------------------

(define *ctfe-default-step-limit* 10000)
(define *ctfe-default-depth-limit* 256)

;;; Sentinel token representing evaluation failure, timeout, or free variable
(define *ctfe-failure* (cons '%ctfe-failure 'unreduced))

(define (ctfe-failure? x)
  (and (pair? x) (eq? (car x) '%ctfe-failure)))

(define (ctfe-success? x)
  (not (ctfe-failure? x)))

;;; -----------------------------------------------------------------------
;;; Environment Operations
;;; -----------------------------------------------------------------------

(define (ctfe-env-empty) '())

(define (ctfe-env-extend env var val)
  (cons (cons var val) env))

(define (ctfe-env-extend* env vars vals)
  (let loop ((vs vars) (es vals) (acc env))
    (cond
      ((and (null? vs) (null? es)) acc)
      ((or (null? vs) (null? es)) acc)
      (else
       (loop (cdr vs) (cdr es) (cons (cons (car vs) (car es)) acc))))))

(define (ctfe-env-lookup env var)
  (let ((entry (assq var env)))
    (if entry (cdr entry) *ctfe-failure*)))

;;; -----------------------------------------------------------------------
;;; Language Evaluator Registry
;;; Uses cons cell (*language-evaluators-cell*) to prevent top-level set! in LIR/AOT
;;; -----------------------------------------------------------------------

(define *language-evaluators-cell* (cons '() '()))

(define (get-language-evaluators)
  (car *language-evaluators-cell*))

(define (set-language-evaluators! lst)
  (set-car! *language-evaluators-cell* lst))

(define (register-language-evaluator! lang-name eval-proc)
  (let ((cur (get-language-evaluators)))
    (set-language-evaluators!
      (cons (cons lang-name eval-proc)
            (let filter-out ((lst cur))
              (cond
                ((null? lst) '())
                ((eq? (caar lst) lang-name) (filter-out (cdr lst)))
                (else (cons (car lst) (filter-out (cdr lst))))))))))

(define (lookup-language-evaluator lang-name)
  (let ((entry (assq lang-name (get-language-evaluators))))
    (if entry (cdr entry) #f)))

;;; -----------------------------------------------------------------------
;;; Portable Bitwise Arithmetic Helpers (Zero External Dependency)
;;; -----------------------------------------------------------------------

(define (ctfe-bitwise-bound a b)
  (let ((ma (if (< a 0) (- 0 a) a))
        (mb (if (< b 0) (- 0 b) b)))
    (let loop ((p 1) (pows '()))
      (if (and (> p ma) (> p mb))
          (cons p pows)
          (loop (+ p p) (cons p pows))))))

(define (ctfe-bitwise-and a b)
  (cond
    ((or (= a 0) (= b 0)) 0)
    ((= a -1) b)
    ((= b -1) a)
    (else
     (let* ((bound (ctfe-bitwise-bound a b))
            (P (car bound))
            (pows (cdr bound))
            (ua (if (< a 0) (+ a P) a))
            (ub (if (< b 0) (+ b P) b)))
       (let loop ((ps pows) (ra ua) (rb ub) (acc 0))
         (if (null? ps)
             (if (and (< a 0) (< b 0)) (- acc P) acc)
             (let* ((bit (car ps))
                    (ha (>= ra bit))
                    (hb (>= rb bit))
                    (ra2 (if ha (- ra bit) ra))
                    (rb2 (if hb (- rb bit) rb))
                    (acc2 (if (and ha hb) (+ acc bit) acc)))
               (loop (cdr ps) ra2 rb2 acc2))))))))

(define (ctfe-bitwise-ior a b)
  (cond
    ((= a 0) b)
    ((= b 0) a)
    ((or (= a -1) (= b -1)) -1)
    (else
     (let* ((bound (ctfe-bitwise-bound a b))
            (P (car bound))
            (pows (cdr bound))
            (ua (if (< a 0) (+ a P) a))
            (ub (if (< b 0) (+ b P) b)))
       (let loop ((ps pows) (ra ua) (rb ub) (acc 0))
         (if (null? ps)
             (if (or (< a 0) (< b 0)) (- acc P) acc)
             (let* ((bit (car ps))
                    (ha (>= ra bit))
                    (hb (>= rb bit))
                    (ra2 (if ha (- ra bit) ra))
                    (rb2 (if hb (- rb bit) rb))
                    (acc2 (if (or ha hb) (+ acc bit) acc)))
               (loop (cdr ps) ra2 rb2 acc2))))))))

(define (ctfe-bitwise-not n)
  (- -1 n))

(define (ctfe-bitwise-xor a b)
  (- (ctfe-bitwise-ior a b) (ctfe-bitwise-and a b)))

(define (ctfe-arithmetic-shift n count)
  (cond
    ((= count 0) n)
    ((> count 0)
     (let loop ((val n) (c count))
       (if (<= c 0) val (loop (* val 2) (- c 1)))))
    (else
     (let loop ((val n) (c (- count)))
       (if (<= c 0)
           val
           (let ((next (if (>= val 0)
                           (quotient val 2)
                           (let ((q (quotient val 2)))
                             (if (= (* q 2) val)
                                 q
                                 (- q 1))))))
             (loop next (- c 1))))))))

;;; -----------------------------------------------------------------------
;;; Primitive Operator Evaluation
;;; -----------------------------------------------------------------------

(define (ctfe-pure-prim? op)
  (or (pure-prim? op)
      (memq op '(min max abs remainder
                 bitwise-and bitwise-ior bitwise-xor bitwise-not arithmetic-shift
                 reverse append string-length char=? boolean=? symbol=?
                 fx+ fx- fx*))))

(define (ctfe-valid-fixnum? v)
  (and (integer? v)
       (let ((q (quotient v 1073741824)))
         (and (<= q 2147483647)
              (>= q -2147483647)))))

(define (ctfe-apply-primitive op args)
  (let ((nargs (length args)))
    (cond
      ;; 0-argument primitives
      ((= nargs 0)
       (case op
         ((+) 0)
         ((*) 1)
         (else *ctfe-failure*)))

      ;; 1-argument primitives
      ((= nargs 1)
       (let ((v (car args)))
         (case op
           ((+) (if (number? v) v *ctfe-failure*))
           ((-) (if (number? v) (let ((r (- 0 v))) (if (ctfe-valid-fixnum? r) r *ctfe-failure*)) *ctfe-failure*))
           ((fxadd1) (if (number? v) (let ((r (+ v 1))) (if (ctfe-valid-fixnum? r) r *ctfe-failure*)) *ctfe-failure*))
           ((fxsub1) (if (number? v) (let ((r (- v 1))) (if (ctfe-valid-fixnum? r) r *ctfe-failure*)) *ctfe-failure*))
           ((abs) (if (number? v) (let ((r (abs v))) (if (ctfe-valid-fixnum? r) r *ctfe-failure*)) *ctfe-failure*))
           ((zero?) (if (number? v) (= v 0) *ctfe-failure*))
           ((not) (if (eq? v #f) #t #f))
           ((null?) (null? v))
           ((pair?) (pair? v))
           ((boolean?) (boolean? v))
           ((number? fixnum? integer? exact? exact-integer? real? rational? complex?)
            (number? v))
           ((char?) (char? v))
           ((symbol?) (symbol? v))
           ((string?) (string? v))
           ((list?) (list? v))
           ((car) (if (pair? v) (car v) *ctfe-failure*))
           ((cdr) (if (pair? v) (cdr v) *ctfe-failure*))
           ((caar) (if (and (pair? v) (pair? (car v))) (caar v) *ctfe-failure*))
           ((cadr) (if (and (pair? v) (pair? (cdr v))) (cadr v) *ctfe-failure*))
           ((cdar) (if (and (pair? v) (pair? (car v))) (cdar v) *ctfe-failure*))
           ((cddr) (if (and (pair? v) (pair? (cdr v))) (cddr v) *ctfe-failure*))
           ((length) (if (list? v) (length v) *ctfe-failure*))
           ((reverse) (if (list? v) (reverse v) *ctfe-failure*))
           ((bitwise-not) (if (number? v) (ctfe-bitwise-not v) *ctfe-failure*))
           ((char->integer) (if (char? v) (char->integer v) *ctfe-failure*))
           ((integer->char) (if (and (number? v) (>= v 0) (<= v #x10ffff)) (integer->char v) *ctfe-failure*))
           ((string-length) (if (string? v) (string-length v) *ctfe-failure*))
           (else *ctfe-failure*))))

      ;; 2-argument primitives
      ((= nargs 2)
       (let ((v1 (car args))
             (v2 (cadr args)))
         (case op
           ((+ fx+) (if (and (number? v1) (number? v2)) (let ((r (+ v1 v2))) (if (ctfe-valid-fixnum? r) r *ctfe-failure*)) *ctfe-failure*))
           ((- fx-) (if (and (number? v1) (number? v2)) (let ((r (- v1 v2))) (if (ctfe-valid-fixnum? r) r *ctfe-failure*)) *ctfe-failure*))
           ((* fx*) (if (and (number? v1) (number? v2)) (let ((r (* v1 v2))) (if (ctfe-valid-fixnum? r) r *ctfe-failure*)) *ctfe-failure*))
           ((quotient /)
            (if (and (number? v1) (number? v2) (not (= v2 0)))
                (let ((r (quotient v1 v2)))
                  (if (ctfe-valid-fixnum? r) r *ctfe-failure*))
                *ctfe-failure*))
           ((modulo)
            (if (and (number? v1) (number? v2) (not (= v2 0)))
                (let ((r (modulo v1 v2)))
                  (if (ctfe-valid-fixnum? r) r *ctfe-failure*))
                *ctfe-failure*))
           ((remainder)
            (if (and (number? v1) (number? v2) (not (= v2 0)))
                (let ((r (remainder v1 v2)))
                  (if (ctfe-valid-fixnum? r) r *ctfe-failure*))
                *ctfe-failure*))
           ((min) (if (and (number? v1) (number? v2)) (min v1 v2) *ctfe-failure*))
           ((max) (if (and (number? v1) (number? v2)) (max v1 v2) *ctfe-failure*))
           ((=) (if (and (number? v1) (number? v2)) (= v1 v2) *ctfe-failure*))
           ((<) (if (and (number? v1) (number? v2)) (< v1 v2) *ctfe-failure*))
           ((<=) (if (and (number? v1) (number? v2)) (<= v1 v2) *ctfe-failure*))
           ((>) (if (and (number? v1) (number? v2)) (> v1 v2) *ctfe-failure*))
           ((>=) (if (and (number? v1) (number? v2)) (>= v1 v2) *ctfe-failure*))
           ((eq? eqv?) (eq? v1 v2))
           ((equal?) (equal? v1 v2))
           ((char=?) (if (and (char? v1) (char? v2)) (char=? v1 v2) *ctfe-failure*))
           ((boolean=?) (if (and (boolean? v1) (boolean? v2)) (eq? v1 v2) *ctfe-failure*))
           ((symbol=?) (if (and (symbol? v1) (symbol? v2)) (eq? v1 v2) *ctfe-failure*))
           ((cons) (cons v1 v2))
           ((append) (if (list? v1) (append v1 v2) *ctfe-failure*))
           ((bitwise-and) (if (and (number? v1) (number? v2)) (ctfe-bitwise-and v1 v2) *ctfe-failure*))
           ((bitwise-ior) (if (and (number? v1) (number? v2)) (ctfe-bitwise-ior v1 v2) *ctfe-failure*))
           ((bitwise-xor) (if (and (number? v1) (number? v2)) (ctfe-bitwise-xor v1 v2) *ctfe-failure*))
           ((arithmetic-shift) (if (and (number? v1) (number? v2)) (ctfe-arithmetic-shift v1 v2) *ctfe-failure*))
           (else *ctfe-failure*))))

      ;; 3 or more arguments (variadic reduction)
      ((> nargs 2)
       (case op
         ((+)
          (let loop ((rest args) (acc 0))
            (cond
              ((null? rest) acc)
              ((number? (car rest))
               (let ((next (+ acc (car rest))))
                 (if (ctfe-valid-fixnum? next)
                     (loop (cdr rest) next)
                     *ctfe-failure*)))
              (else *ctfe-failure*))))
         ((*)
          (let loop ((rest args) (acc 1))
            (cond
              ((null? rest) acc)
              ((number? (car rest))
               (let ((next (* acc (car rest))))
                 (if (ctfe-valid-fixnum? next)
                     (loop (cdr rest) next)
                     *ctfe-failure*)))
              (else *ctfe-failure*))))
         ((min)
          (let loop ((rest (cdr args)) (acc (car args)))
            (cond
              ((not (number? acc)) *ctfe-failure*)
              ((null? rest) acc)
              ((number? (car rest)) (loop (cdr rest) (min acc (car rest))))
              (else *ctfe-failure*))))
         ((max)
          (let loop ((rest (cdr args)) (acc (car args)))
            (cond
              ((not (number? acc)) *ctfe-failure*)
              ((null? rest) acc)
              ((number? (car rest)) (loop (cdr rest) (max acc (car rest))))
              (else *ctfe-failure*))))
         ((list) args)
         (else *ctfe-failure*)))

      (else *ctfe-failure*))))

;;; -----------------------------------------------------------------------
;;; Core Tree-Walk Evaluator (ctfe-eval)
;;; -----------------------------------------------------------------------

(define (ctfe-eval expr env fuel depth)
  (cond
    ;; Resource bounds check (CWE-400 guard)
    ((or (<= fuel 0) (<= depth 0)) *ctfe-failure*)

    ;; Self-evaluating literals
    ((number? expr) expr)
    ((boolean? expr) expr)
    ((char? expr) expr)
    ((string? expr) expr)

    ;; Variable lookup
    ((symbol? expr)
     (ctfe-env-lookup env expr))

    ;; Non-pair forms (bytevectors, vectors, etc.)
    ((not (pair? expr)) expr)

    ;; Compound expressions
    (else
     (let ((op (car expr))
           (f1 (- fuel 1))
           (d1 (- depth 1)))
       (case op
         ;; Quoted datum
         ((quote)
          (if (and (pair? (cdr expr)) (null? (cddr expr)))
              (cadr expr)
              *ctfe-failure*))

         ;; Conditional: (if test then [else])
         ((if)
          (let ((test-expr (cadr expr))
                (then-expr (caddr expr))
                (else-expr (if (null? (cdddr expr)) #f (cadddr expr))))
            (let ((test-val (ctfe-eval test-expr env f1 d1)))
              (cond
                ((ctfe-failure? test-val) *ctfe-failure*)
                ((eq? test-val #f)
                 (if else-expr
                     (ctfe-eval else-expr env f1 d1)
                     #f))
                (else
                 (ctfe-eval then-expr env f1 d1))))))

         ;; Sequential: (begin e ...)
         ((begin)
          (let loop ((es (cdr expr)) (curr-fuel f1) (last-val #f))
            (cond
              ((null? es) last-val)
              ((<= curr-fuel 0) *ctfe-failure*)
              (else
               (let ((v (ctfe-eval (car es) env (- curr-fuel 1) d1)))
                 (if (ctfe-failure? v)
                     *ctfe-failure*
                     (loop (cdr es) (- curr-fuel 1) v)))))))

         ;; Local Bindings: (let ((x e) ...) body)
         ((let)
          (if (and (pair? (cdr expr)) (pair? (cddr expr)))
              (let ((bindings (cadr expr))
                    (body (caddr expr)))
                (let loop ((bs bindings) (curr-env env) (curr-fuel f1) (acc-vars '()) (acc-vals '()))
                  (cond
                    ((null? bs)
                     (let ((extended (ctfe-env-extend* env (reverse acc-vars) (reverse acc-vals))))
                       (ctfe-eval body extended curr-fuel d1)))
                    ((<= curr-fuel 0) *ctfe-failure*)
                    (else
                     (let* ((b (car bs))
                            (var (car b))
                            (val-expr (cadr b))
                            (v (ctfe-eval val-expr env (- curr-fuel 1) d1)))
                       (if (ctfe-failure? v)
                           *ctfe-failure*
                           (loop (cdr bs) curr-env (- curr-fuel 1)
                                 (cons var acc-vars) (cons v acc-vals))))))))
              *ctfe-failure*))

         ;; Sequential Bindings: (let* ((x e) ...) body)
         ((let*)
          (if (and (pair? (cdr expr)) (pair? (cddr expr)))
              (let ((bindings (cadr expr))
                    (body (caddr expr)))
                (let loop ((bs bindings) (curr-env env) (curr-fuel f1))
                  (cond
                    ((null? bs)
                     (ctfe-eval body curr-env curr-fuel d1))
                    ((<= curr-fuel 0) *ctfe-failure*)
                    (else
                     (let* ((b (car bs))
                            (var (car b))
                            (val-expr (cadr b))
                            (v (ctfe-eval val-expr curr-env (- curr-fuel 1) d1)))
                       (if (ctfe-failure? v)
                           *ctfe-failure*
                           (loop (cdr bs) (ctfe-env-extend curr-env var v) (- curr-fuel 1))))))))
              *ctfe-failure*))

         ;; Pure Lambda Definition & Local Invocation:
         ;; Supports ((lambda (x ...) body) arg ...)
         ((lambda)
          ;; First-class closures in CTFE represented as tagged tuple
          (list '%ctfe-closure (cadr expr) (caddr expr) env))

         ;; Function Application / Primitive Call
         (else
          (cond
            ;; 1. Primitive function call: (op arg ...) where op is a pure symbol
            ((and (symbol? op) (ctfe-pure-prim? op))
             (let loop ((as (cdr expr)) (curr-fuel f1) (evaluated-args '()))
               (cond
                 ((null? as)
                  (ctfe-apply-primitive op (reverse evaluated-args)))
                 ((<= curr-fuel 0) *ctfe-failure*)
                 (else
                  (let ((v (ctfe-eval (car as) env (- curr-fuel 1) d1)))
                    (if (ctfe-failure? v)
                        *ctfe-failure*
                        (loop (cdr as) (- curr-fuel 1) (cons v evaluated-args))))))))

            ;; 2. First-class closure application (direct lambda, curried, or bound variable)
            (else
             (let ((fn-val (ctfe-eval op env f1 d1)))
               (if (and (pair? fn-val) (eq? (car fn-val) '%ctfe-closure))
                   (let ((params (cadr fn-val))
                         (cbody (caddr fn-val))
                         (cenv (cadddr fn-val))
                         (args (cdr expr)))
                     (if (= (length params) (length args))
                         (let loop ((ps params) (as args) (curr-fuel f1) (evaluated-args '()))
                           (cond
                             ((null? ps)
                              (let ((call-env (ctfe-env-extend* cenv params (reverse evaluated-args))))
                                (ctfe-eval cbody call-env curr-fuel d1)))
                             ((<= curr-fuel 0) *ctfe-failure*)
                             (else
                              (let ((v (ctfe-eval (car as) env (- curr-fuel 1) d1)))
                                (if (ctfe-failure? v)
                                    *ctfe-failure*
                                    (loop (cdr ps) (cdr as) (- curr-fuel 1) (cons v evaluated-args)))))))
                         *ctfe-failure*))
                   *ctfe-failure*))))))))))

;;; -----------------------------------------------------------------------
;;; Public API: eval-in-language & ctfe-try-reduce
;;; -----------------------------------------------------------------------

;;; Evaluates an expression within a specific Nanopass language context.
;;; Returns the reduced AST node if fully evaluated to a constant, or #f if unreduced.
(define (eval-in-language-opt lang expr env step-limit depth-limit)
  (let* ((fuel (if step-limit step-limit *ctfe-default-step-limit*))
         (depth (if depth-limit depth-limit *ctfe-default-depth-limit*))
         (custom-eval (lookup-language-evaluator lang)))
    (if custom-eval
        (custom-eval expr env fuel depth)
        (let ((result (ctfe-eval expr env fuel depth)))
          (if (ctfe-failure? result)
              #f
              (val->ast-const result))))))

(define (eval-in-language lang expr)
  (eval-in-language-opt lang expr (ctfe-env-empty) *ctfe-default-step-limit* *ctfe-default-depth-limit*))

;;; Helper to safely attempt CTFE reduction on an AST expression.
;;; Returns the reduced constant AST node on success, or #f on failure.
(define (ctfe-try-reduce expr)
  (if (and (pure-expr? expr)
           (null? (free-vars expr '())))
      (eval-in-language 'L_core expr)
      #f))

;;; -----------------------------------------------------------------------
;;; Default Language Evaluator Registrations
;;; -----------------------------------------------------------------------

(register-language-evaluator! 'L_core
  (lambda (expr env fuel depth)
    (let ((res (ctfe-eval expr env fuel depth)))
      (if (ctfe-failure? res)
          #f
          (val->ast-const res)))))

(register-language-evaluator! 'Scheme
  (lambda (expr env fuel depth)
    (let ((res (ctfe-eval expr env fuel depth)))
      (if (ctfe-failure? res)
          #f
          (val->ast-const res)))))

;;; =======================================================================
;;; Stage-Polymorphic Dictionary Framework (DSN-33-03 §3.1, §3.2, §3.3, §3.7)
;;; Conforms to Futamura Projection, No-set! & Fixed-Arity self-hosting rules
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. <stage-dict> Record Definition
;;; -----------------------------------------------------------------------

(define-record-type <stage-dict>
  (%make-stage-dict-raw name stage-level apply-prim-1 apply-prim-2 apply-prim-3 apply-prim-4
                        bind-let emit-if emit-call lift-val signal-csp-error)
  stage-dict?
  (name             stage-dict-name)
  (stage-level      stage-dict-stage-level)
  (apply-prim-1     stage-dict-apply-prim-1)
  (apply-prim-2     stage-dict-apply-prim-2)
  (apply-prim-3     stage-dict-apply-prim-3)
  (apply-prim-4     stage-dict-apply-prim-4)
  (bind-let         stage-dict-bind-let)
  (emit-if          stage-dict-emit-if)
  (emit-call        stage-dict-emit-call)
  (lift-val         stage-dict-lift-val)
  (signal-csp-error stage-dict-signal-csp-error))

(define (stage-dict-now? dict)
  (eq? (stage-dict-name dict) 'now))

(define (stage-dict-later? dict)
  (eq? (stage-dict-name dict) 'later))

;;; -----------------------------------------------------------------------
;;; 2. Convenience Invocation Wrappers
;;; -----------------------------------------------------------------------

(define (stage-apply-prim-1 dict op arg1)
  ((stage-dict-apply-prim-1 dict) dict op arg1))

(define (stage-apply-prim-2 dict op arg1 arg2)
  ((stage-dict-apply-prim-2 dict) dict op arg1 arg2))

(define (stage-apply-prim-3 dict op arg1 arg2 arg3)
  ((stage-dict-apply-prim-3 dict) dict op arg1 arg2 arg3))

(define (stage-apply-prim-4 dict op arg1 arg2 arg3 arg4)
  ((stage-dict-apply-prim-4 dict) dict op arg1 arg2 arg3 arg4))

(define (stage-bind-let dict var rhs body-thunk)
  ((stage-dict-bind-let dict) dict var rhs body-thunk))

(define (stage-emit-if dict test-val then-thunk else-thunk)
  ((stage-dict-emit-if dict) dict test-val then-thunk else-thunk))

(define (stage-emit-call dict callee args)
  ((stage-dict-emit-call dict) dict callee args))

(define (stage-lift-val dict val loc)
  ((stage-dict-lift-val dict) dict val loc))

(define (stage-signal-csp-error dict reason loc)
  ((stage-dict-signal-csp-error dict) dict reason loc))

;;; -----------------------------------------------------------------------
;;; 3. Temporary Variable Generator for Later Dictionaries
;;; Uses cons cell counter to satisfy No-set! self-hosting rules
;;; -----------------------------------------------------------------------

(define (make-temp-var-generator prefix)
  (let ((counter (cons 0 '())))
    (lambda ()
      (let ((id (car counter)))
        (set-car! counter (+ id 1))
        (string->symbol (string-append prefix (number->string id)))))))

;;; -----------------------------------------------------------------------
;;; 4. Default CSP Error Reporter
;;; -----------------------------------------------------------------------

(define (default-stage-csp-error-reporter dict reason loc)
  (cons '%stage-csp-error (cons reason loc)))

(define (stage-csp-error? x)
  (and (pair? x) (eq? (car x) '%stage-csp-error)))

;;; -----------------------------------------------------------------------
;;; 5. Now Dictionary (Immediate Evaluation & Ground Truth Oracle)
;;; -----------------------------------------------------------------------

(define (now-dict-apply-prim-1 dict op a)
  (cond
    ((eq? op 'abs) (if (< a 0) (- 0 a) a))
    ((eq? op 'not) (if a #f #t))
    ((eq? op 'null?) (null? a))
    ((eq? op 'pair?) (pair? a))
    ((eq? op 'number?) (number? a))
    ((eq? op 'boolean?) (boolean? a))
    ((eq? op 'symbol?) (symbol? a))
    ((eq? op 'string?) (string? a))
    ((eq? op 'char?) (char? a))
    ((eq? op 'car) (if (pair? a) (car a) *ctfe-failure*))
    ((eq? op 'cdr) (if (pair? a) (cdr a) *ctfe-failure*))
    ((eq? op '-) (- 0 a))
    ((eq? op 'string-length) (if (string? a) (string-length a) *ctfe-failure*))
    ((eq? op 'vector-length) (if (vector? a) (vector-length a) *ctfe-failure*))
    (else *ctfe-failure*)))

(define (now-dict-apply-prim-2 dict op a b)
  (cond
    ((eq? op '+) (+ a b))
    ((eq? op '-) (- a b))
    ((eq? op '*) (* a b))
    ((eq? op 'quotient) (if (= b 0) *ctfe-failure* (quotient a b)))
    ((eq? op 'modulo) (if (= b 0) *ctfe-failure* (modulo a b)))
    ((eq? op 'remainder) (if (= b 0) *ctfe-failure* (remainder a b)))
    ((eq? op '=) (= a b))
    ((eq? op '<) (< a b))
    ((eq? op '<=) (<= a b))
    ((eq? op '>) (> a b))
    ((eq? op '>=) (>= a b))
    ((eq? op 'eq?) (eq? a b))
    ((eq? op 'equal?) (equal? a b))
    ((eq? op 'cons) (cons a b))
    ((eq? op 'bitwise-and) (ctfe-bitwise-and a b))
    ((eq? op 'bitwise-ior) (ctfe-bitwise-ior a b))
    ((eq? op 'bitwise-xor) (ctfe-bitwise-xor a b))
    ((eq? op 'arithmetic-shift) (ctfe-arithmetic-shift a b))
    (else *ctfe-failure*)))

(define (now-dict-apply-prim-3 dict op a b c)
  (cond
    ((eq? op 'vector-ref) (if (and (vector? a) (number? b) (>= b 0) (< b (vector-length a)))
                              (vector-ref a b)
                              *ctfe-failure*))
    ((eq? op 'string-ref) (if (and (string? a) (number? b) (>= b 0) (< b (string-length a)))
                              (string-ref a b)
                              *ctfe-failure*))
    (else *ctfe-failure*)))

(define (now-dict-apply-prim-4 dict op a b c d)
  *ctfe-failure*)

(define (now-dict-bind-let dict var rhs-val body-thunk)
  ;; For Now dict, body-thunk is invoked directly
  (body-thunk))

(define (now-dict-emit-if dict test-val then-thunk else-thunk)
  ;; Immediate condition evaluation: dead-code branch is completely skipped!
  (if (and (boolean? test-val) (not test-val))
      (else-thunk)
      (if test-val
          (then-thunk)
          (else-thunk))))

(define (now-dict-emit-call dict callee-proc arg-vals)
  ;; Immediate closure invocation
  (cond
    ((procedure? callee-proc)
     (let ((n (length arg-vals)))
       (cond
         ((= n 0) (callee-proc))
         ((= n 1) (callee-proc (car arg-vals)))
         ((= n 2) (callee-proc (car arg-vals) (cadr arg-vals)))
         ((= n 3) (callee-proc (car arg-vals) (cadr arg-vals) (caddr arg-vals)))
         (else *ctfe-failure*))))
    ((and (pair? callee-proc) (eq? (car callee-proc) '%ctfe-closure))
     (let* ((params (cadr callee-proc))
            (body (caddr callee-proc))
            (cenv (cadddr callee-proc)))
       (if (= (length params) (length arg-vals))
           (let ((call-env (ctfe-env-extend* cenv params arg-vals)))
             (ctfe-eval body call-env *ctfe-default-step-limit* *ctfe-default-depth-limit*))
           *ctfe-failure*)))
    (else *ctfe-failure*)))

(define (now-dict-lift-val dict val loc)
  ;; In Now stage, lifting is an identity operation
  val)

(define (make-now-dict)
  (%make-stage-dict-raw
    'now
    1
    now-dict-apply-prim-1
    now-dict-apply-prim-2
    now-dict-apply-prim-3
    now-dict-apply-prim-4
    now-dict-bind-let
    now-dict-emit-if
    now-dict-emit-call
    now-dict-lift-val
    default-stage-csp-error-reporter))

;;; -----------------------------------------------------------------------
;;; 6. Later Dictionary (Residualization & MIR-ANF Node Emitter)
;;; -----------------------------------------------------------------------

(define (later-dict-apply-prim-1 dict op a)
  (list op a))

(define (later-dict-apply-prim-2 dict op a b)
  (list op a b))

(define (later-dict-apply-prim-3 dict op a b c)
  (list op a b c))

(define (later-dict-apply-prim-4 dict op a b c d)
  (list op a b c d))

(define (later-dict-bind-let dict var rhs-expr body-thunk)
  (let ((body-expr (body-thunk)))
    (list 'let-anf (list (list var rhs-expr)) body-expr)))

(define (later-dict-emit-if dict test-expr then-thunk else-thunk)
  (let ((then-branch (then-thunk))
        (else-branch (else-thunk)))
    (list 'if-anf test-expr then-branch else-branch)))

(define (later-dict-emit-call dict callee-expr arg-exprs)
  (cons 'call-anf (cons callee-expr arg-exprs)))

(define (later-dict-lift-val dict val loc)
  ;; Lift static value into residual literal
  (cond
    ((or (number? val) (boolean? val) (char? val) (string? val)) val)
    ((symbol? val) (list 'quote val))
    ((null? val) (list 'quote '()))
    ((pair? val) (list 'quote val))
    (else (list 'quote val))))

(define (make-later-dict)
  (%make-stage-dict-raw
    'later
    0
    later-dict-apply-prim-1
    later-dict-apply-prim-2
    later-dict-apply-prim-3
    later-dict-apply-prim-4
    later-dict-bind-let
    later-dict-emit-if
    later-dict-emit-call
    later-dict-lift-val
    default-stage-csp-error-reporter))
