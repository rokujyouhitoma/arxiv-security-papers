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
       (exact? v)
       (let ((q (quotient v 1073741824)))
         (and (<= q 2147483647)
              (>= q -2147483647)))))

(define (%ctfe-num-guard r)
  (if (ctfe-valid-fixnum? r) r *ctfe-failure*))

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
           ((guest-pack-fixnum) (if (number? v) (guest-pack-fixnum v) *ctfe-failure*))
           ((guest-unpack-fixnum) (if (number? v) (guest-unpack-fixnum v) *ctfe-failure*))
           ((guest-fixnum?) (if (number? v) (guest-fixnum? v) *ctfe-failure*))
           ((guest-tag-of) (if (number? v) (guest-tag-of v) *ctfe-failure*))
           ((guest-pair?) (if (number? v) (guest-pair? v) *ctfe-failure*))
           ((guest-symbol?) (if (number? v) (guest-symbol? v) *ctfe-failure*))
           ((guest-closure?) (if (number? v) (guest-closure? v) *ctfe-failure*))
           ((guest-vector?) (if (number? v) (guest-vector? v) *ctfe-failure*))
           ((guest-instance?) (if (number? v) (guest-instance? v) *ctfe-failure*))
           ((guest-flonum-ptr?) (if (number? v) (guest-flonum-ptr? v) *ctfe-failure*))
           ((guest-pack-special) (if (number? v) (guest-pack-special v) *ctfe-failure*))
           ((guest-unpack-special) (if (number? v) (guest-unpack-special v) *ctfe-failure*))
           ((guest-special?) (if (number? v) (guest-special? v) *ctfe-failure*))
           ((nan-box-int32) (if (number? v) (nan-box-int32 v) *ctfe-failure*))
           ((nan-unbox-int32) (if (number? v) (nan-unbox-int32 v) *ctfe-failure*))
           ((nan-is-int32?) (if (number? v) (nan-is-int32? v) *ctfe-failure*))
           ((nan-box-pointer) (if (number? v) (nan-box-pointer v) *ctfe-failure*))
           ((nan-unbox-pointer) (if (number? v) (nan-unbox-pointer v) *ctfe-failure*))
           ((nan-is-pointer?) (if (number? v) (nan-is-pointer? v) *ctfe-failure*))
           ((nan-box-special) (if (number? v) (nan-box-special v) *ctfe-failure*))
           ((nan-unbox-special) (if (number? v) (nan-unbox-special v) *ctfe-failure*))
           ((nan-is-special?) (if (number? v) (nan-is-special? v) *ctfe-failure*))
           ((nan-box-flonum) (nan-box-flonum v))
           ((nan-unbox-flonum) (nan-unbox-flonum v))
           ((nan-is-flonum?) (nan-is-flonum? v))
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
           ((guest-pack-pointer) (if (and (number? v1) (number? v2)) (guest-pack-pointer v1 v2) *ctfe-failure*))
           ((guest-unpack-pointer) (if (and (number? v1) (number? v2)) (guest-unpack-pointer v1 v2) *ctfe-failure*))
           ((guest-pointer-of-tag?) (if (and (number? v1) (number? v2)) (guest-pointer-of-tag? v1 v2) *ctfe-failure*))
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
;;; Consolidated CTFE Evaluator (Delegates directly to eval-in-stage via Now-Dict)
;;; Conforms to DSN-33-03 §3.6 Single-Source Semantic Oracle & Issue #888
;;; -----------------------------------------------------------------------

(define (ctfe-eval expr env fuel depth)
  (let* ((now-d (make-now-dict))
         (res (eval-in-stage now-d env expr fuel depth)))
    (cond
      ((stage-csp-error? res) *ctfe-failure*)
      ((stage-val? res)
       (let ((payload (stage-val-payload res)))
         (if (and (number? payload) (not (ctfe-valid-fixnum? payload)))
             *ctfe-failure*
             payload)))
      (else *ctfe-failure*))))

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
;;; 4. Default CSP Error Reporter & Dual-Span Diagnostic Generator
;;; Conforms to DSN-33-03 §4.2, §4.3 & DSN-33-02 §3.4
;;; -----------------------------------------------------------------------

(define (csp-normalize-span sp)
  (cond
    ;; <source-span> record
    ((source-span? sp)
     (list (cons 'file (span-file sp))
           (cons 'line (span-start-line sp))
           (cons 'column (span-start-col sp))))
    ;; Association list ((file . ...) (line . ...) (column . ...))
    ((and (pair? sp) (pair? (car sp)) (assq 'file sp))
     sp)
    ;; List format (span file line col) or (file line col)
    ((and (pair? sp) (eq? (car sp) 'span) (>= (length sp) 4))
     (list (cons 'file (cadr sp))
           (cons 'line (caddr sp))
           (cons 'column (cadddr sp))))
    ((and (pair? sp) (= (length sp) 3) (string? (car sp)))
     (list (cons 'file (car sp))
           (cons 'line (cadr sp))
           (cons 'column (caddr sp))))
    ;; String format (e.g. "path/to/file")
    ((and (string? sp) (> (string-length sp) 0))
     (list (cons 'file sp)
           (cons 'line 0)
           (cons 'column 0)))
    ;; Fallback
    (else
     '((file . "unknown")
       (line . 0)
       (column . 0)))))

(define (csp-extract-dual-spans loc)
  (let* ((guest-raw
          (cond
            ((stage-val? loc) (stage-val-guest-span loc))
            ((and (pair? loc) (assq 'guest loc)) (cdr (assq 'guest loc)))
            (else #f)))
         (host-raw
          (cond
            ((stage-val? loc) (stage-val-host-span loc))
            ((and (pair? loc) (assq 'host loc)) (cdr (assq 'host loc)))
            ((source-span? loc) loc)
            (else #f))))
    (list (cons 'guest-span (csp-normalize-span guest-raw))
          (cons 'host-span (csp-normalize-span host-raw)))))

(define (csp-resolve-rule-info dict reason loc)
  (case reason
    ((illegal-mutable-lift)
     (list "CSP-001-ILLEGAL-MUTABLE-LIFT"
           "Prohibited cross-stage lift of mutable object to residual code."
           '((variable . #f)
             (source-stage . 1)
             (target-stage . 0)
             (binding-time . dynamic)
             (inferred-type . mutable-cell))
           "Use immutable values or explicit runtime bump-pointer allocation."))

    ((illegal-continuation-lift)
     (list "CSP-002-ILLEGAL-CONTINUATION-LIFT"
           "Prohibited cross-stage lift of host continuation to residual code."
           '((variable . #f)
             (source-stage . 1)
             (target-stage . 0)
             (binding-time . dynamic)
             (inferred-type . continuation))
           "Delimit continuations to current stage or represent as residual closures."))

    ((illegal-procedure-lift)
     (list "CSP-003-OPAQUE-PROCEDURE-LIFT"
           "Prohibited cross-stage lift of opaque host procedure to residual code."
           '((variable . #f)
             (source-stage . 1)
             (target-stage . 0)
             (binding-time . dynamic)
             (inferred-type . opaque-procedure))
           "Define functions as residual lambda expressions or use defmacro."))

    ((now-stage-cannot-evaluate-dynamic)
     (list "CSP-004-NOW-STAGE-CANNOT-EVALUATE-DYNAMIC"
           "Now stage cannot evaluate dynamic or partially-static expressions."
           '((source-stage . 1)
             (target-stage . 1)
             (binding-time . dynamic))
           "Defer evaluation to Later stage or eliminate dynamic dependencies."))

    ((ctfe-fuel-exhausted)
     (list "CSP-005-RESOURCE-BOUND-FUEL-EXHAUSTED"
           "Compile-time evaluation exceeded maximum fuel limit (CWE-400 guard)."
           '((resource . fuel)
             (limit-exceeded . #t))
           "Increase compile-time fuel or restructure recursion into tail-call loops."))

    ((ctfe-depth-overflow)
     (list "CSP-006-RESOURCE-BOUND-DEPTH-OVERFLOW"
           "Compile-time evaluation exceeded maximum stack depth (CWE-400 guard)."
           '((resource . depth)
             (limit-exceeded . #t))
           "Increase recursion depth limit or flatten nested expressions."))

    ((invalid-negative-stage-level)
     (list "CSP-007-INVALID-NEGATIVE-STAGE-LEVEL"
           "Encountered invalid negative stage level transition."
           '((stage-level . invalid))
           "Ensure stage level is non-negative."))

    (else
     (list "CSP-099-GENERAL-STAGE-ERROR"
           "Stage evaluation error."
           (list (cons 'reason reason))
           "Check stage constraints and bindings."))))

(define (make-compiler-diagnostic-sexpr dict reason loc)
  (let* ((rule-info (csp-resolve-rule-info dict reason loc))
         (rule (car rule-info))
         (msg (cadr rule-info))
         (details (caddr rule-info))
         (remediation (cadddr rule-info))
         (spans (csp-extract-dual-spans loc)))
    (list 'compiler-diagnostic
          (list 'version "1.0")
          (list 'severity 'error)
          (list 'phase "bta-csp-guard")
          (list 'rule rule)
          (list 'message msg)
          (list 'details details)
          (list 'provenance spans)
          (list 'remediation remediation))))

(define (default-stage-csp-error-reporter dict reason loc)
  (let ((diag (make-compiler-diagnostic-sexpr dict reason loc)))
    (cons '%stage-csp-error (cons reason (cons loc (cons diag '()))))))

(define (stage-csp-error? x)
  (and (pair? x)
       (or (eq? (car x) '%stage-csp-error)
           (eq? (car x) 'compiler-diagnostic))))

(define (stage-csp-error-reason err)
  (cond
    ((not (stage-csp-error? err)) #f)
    ((eq? (car err) '%stage-csp-error) (cadr err))
    ((eq? (car err) 'compiler-diagnostic)
     (let ((rule-entry (assq 'rule (cdr err))))
       (if rule-entry (cadr rule-entry) 'unknown-csp-error)))
    (else #f)))

(define (stage-csp-error-diagnostic err)
  (cond
    ((not (stage-csp-error? err)) #f)
    ((eq? (car err) 'compiler-diagnostic) err)
    ((and (pair? (cddr err)) (pair? (cdddr err)))
     (cadddr err))
    (else
     (make-compiler-diagnostic-sexpr (make-now-dict) (cadr err) (cddr err)))))

(define (stage-box? x)
  (and (pair? x) (eq? (car x) '%box) (pair? (cdr x))))

(define (stage-continuation? x)
  (and (pair? x) (eq? (car x) '%continuation)))

(define (csp-classify-lift-violation val)
  (cond
    ;; 1. Mutable cell (Box) -> CSP-001
    ((stage-box? val)
     'illegal-mutable-lift)

    ;; 2. Host Continuation -> CSP-002
    ((stage-continuation? val)
     'illegal-continuation-lift)

    ;; 3. Opaque Host Procedure / Native Closure -> CSP-003
    ((procedure? val)
     'illegal-procedure-lift)

    ;; 4. Pair / List recursive check
    ((pair? val)
     (let ((car-viol (csp-classify-lift-violation (car val))))
       (if car-viol
           car-viol
           (csp-classify-lift-violation (cdr val)))))

    ;; 5. Valid lift targets
    (else #f)))

(define (csp-valid-lift-target? val)
  (not (csp-classify-lift-violation val)))

;;; -----------------------------------------------------------------------
;;; 5. Now Dictionary (Immediate Evaluation & Ground Truth Oracle)
;;; -----------------------------------------------------------------------

(define (now-dict-apply-prim-1 dict op a)
  (cond
    ((eq? op 'abs) (if (number? a) (%ctfe-num-guard (if (< a 0) (- 0 a) a)) *ctfe-failure*))
    ((eq? op 'not) (if a #f #t))
    ((eq? op 'null?) (null? a))
    ((eq? op 'pair?) (pair? a))
    ((eq? op 'number?) (number? a))
    ((eq? op 'boolean?) (boolean? a))
    ((eq? op 'symbol?) (symbol? a))
    ((eq? op 'string?) (string? a))
    ((eq? op 'char?) (char? a))
    ((eq? op 'zero?) (if (number? a) (= a 0) *ctfe-failure*))
    ((eq? op 'car) (if (pair? a) (car a) *ctfe-failure*))
    ((eq? op 'cdr) (if (pair? a) (cdr a) *ctfe-failure*))
    ((eq? op 'caar) (if (and (pair? a) (pair? (car a))) (caar a) *ctfe-failure*))
    ((eq? op 'cadr) (if (and (pair? a) (pair? (cdr a))) (cadr a) *ctfe-failure*))
    ((eq? op 'cdar) (if (and (pair? a) (pair? (car a))) (cdar a) *ctfe-failure*))
    ((eq? op 'cddr) (if (and (pair? a) (pair? (cdr a))) (cddr a) *ctfe-failure*))
    ((eq? op 'length) (if (list? a) (length a) *ctfe-failure*))
    ((eq? op 'reverse) (if (list? a) (reverse a) *ctfe-failure*))
    ((eq? op '-) (if (number? a) (%ctfe-num-guard (- 0 a)) *ctfe-failure*))
    ((eq? op 'string-length) (if (string? a) (string-length a) *ctfe-failure*))
    ((eq? op 'vector-length) (if (vector? a) (vector-length a) *ctfe-failure*))
    ((eq? op 'bitwise-not) (if (number? a) (ctfe-bitwise-not a) *ctfe-failure*))
    (else *ctfe-failure*)))

(define (now-dict-apply-prim-2 dict op a b)
  (cond
    ((eq? op '+) (if (and (number? a) (number? b)) (%ctfe-num-guard (+ a b)) *ctfe-failure*))
    ((eq? op '-) (if (and (number? a) (number? b)) (%ctfe-num-guard (- a b)) *ctfe-failure*))
    ((eq? op '*) (if (and (number? a) (number? b)) (%ctfe-num-guard (* a b)) *ctfe-failure*))
    ((or (eq? op 'quotient) (eq? op '/))
     (if (and (number? a) (number? b) (not (= b 0))) (%ctfe-num-guard (quotient a b)) *ctfe-failure*))
    ((eq? op 'modulo)
     (if (and (number? a) (number? b) (not (= b 0))) (%ctfe-num-guard (modulo a b)) *ctfe-failure*))
    ((eq? op 'remainder)
     (if (and (number? a) (number? b) (not (= b 0))) (%ctfe-num-guard (remainder a b)) *ctfe-failure*))
    ((eq? op 'min) (if (and (number? a) (number? b)) (min a b) *ctfe-failure*))
    ((eq? op 'max) (if (and (number? a) (number? b)) (max a b) *ctfe-failure*))
    ((eq? op '=) (= a b))
    ((eq? op '<) (< a b))
    ((eq? op '<=) (<= a b))
    ((eq? op '>) (> a b))
    ((eq? op '>=) (>= a b))
    ((eq? op 'eq?) (eq? a b))
    ((eq? op 'equal?) (equal? a b))
    ((eq? op 'char=?) (if (and (char? a) (char? b)) (char=? a b) *ctfe-failure*))
    ((eq? op 'boolean=?) (if (and (boolean? a) (boolean? b)) (eq? a b) *ctfe-failure*))
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
  (let ((violation (csp-classify-lift-violation val)))
    (if violation
        (stage-signal-csp-error dict violation (or loc val))
        ;; Lift static value into residual literal
        (cond
          ((or (number? val) (boolean? val) (char? val) (string? val)) val)
          ((symbol? val) (list 'quote val))
          ((null? val) (list 'quote '()))
          ((pair? val) (list 'quote val))
          (else (list 'quote val))))))

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

;;; =======================================================================
;;; Partially Static Data Structures (PSDS) & Provenance (DSN-33-03 §3.4)
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 7. <stage-val> Record Definition
;;; -----------------------------------------------------------------------

(define-record-type <stage-val>
  (%make-stage-val-raw tag kind payload host-span guest-span)
  stage-val?
  (tag         stage-val-tag)
  (kind        stage-val-kind)
  (payload     stage-val-payload)
  (host-span   stage-val-host-span)
  (guest-span  stage-val-guest-span))

(define (stage-val-pure-static? sv)
  (and (stage-val? sv) (eq? (stage-val-kind sv) 'pure-static)))

(define (stage-val-partially-static? sv)
  (and (stage-val? sv) (eq? (stage-val-kind sv) 'partially-static)))

(define (stage-val-pure-dynamic? sv)
  (and (stage-val? sv) (eq? (stage-val-kind sv) 'pure-dynamic)))

;; Constructor helpers
(define (make-static-val tag payload host-sp guest-sp)
  (%make-stage-val-raw tag 'pure-static payload host-sp guest-sp))

(define (make-dynamic-val tag payload host-sp guest-sp)
  (%make-stage-val-raw tag 'pure-dynamic payload host-sp guest-sp))

(define (make-psds-val tag payload host-sp guest-sp)
  (%make-stage-val-raw tag 'partially-static payload host-sp guest-sp))

;; Provenance Stack extraction
(define (stage-val-provenance sv)
  (if (stage-val? sv)
      (list (cons 'guest (stage-val-guest-span sv))
            (cons 'host (stage-val-host-span sv)))
      (list (cons 'guest #f) (cons 'host #f))))

;;; -----------------------------------------------------------------------
;;; 8. PSDS Pair Reduction Operations (Static Spine Elimination)
;;; -----------------------------------------------------------------------

(define (stage-cons car-sv cdr-sv host-sp guest-sp)
  (let ((car-static? (stage-val-pure-static? car-sv))
        (cdr-static? (stage-val-pure-static? cdr-sv)))
    (if (and car-static? cdr-static?)
        ;; Both operands are pure-static -> construct pure-static Scheme pair immediately
        (make-static-val
          'pair
          (cons (stage-val-payload car-sv) (stage-val-payload cdr-sv))
          host-sp
          guest-sp)
        ;; At least one operand is dynamic/PSDS -> construct partially-static meta-pair
        (make-psds-val
          'pair
          (cons car-sv cdr-sv)
          host-sp
          guest-sp))))

(define (stage-car dict sv loc)
  (cond
    ((not (stage-val? sv))
     *ctfe-failure*)
    ((stage-val-pure-static? sv)
     (let ((p (stage-val-payload sv)))
       (if (pair? p)
           (make-static-val 'any (car p) loc (stage-val-guest-span sv))
           *ctfe-failure*)))
    ((stage-val-partially-static? sv)
     ;; Static spine: retrieve component directly at compile time!
     ;; Zero residual 'car' instruction emitted!
     (let ((p (stage-val-payload sv)))
       (if (pair? p)
           (car p)
           *ctfe-failure*)))
    ((stage-val-pure-dynamic? sv)
     ;; Pure dynamic: emit residual car ANF instruction
     (let ((res (stage-apply-prim-1 dict 'car (stage-val-payload sv))))
       (make-dynamic-val 'any res loc (stage-val-guest-span sv))))
    (else *ctfe-failure*)))

(define (stage-cdr dict sv loc)
  (cond
    ((not (stage-val? sv))
     *ctfe-failure*)
    ((stage-val-pure-static? sv)
     (let ((p (stage-val-payload sv)))
       (if (pair? p)
           (make-static-val 'any (cdr p) loc (stage-val-guest-span sv))
           *ctfe-failure*)))
    ((stage-val-partially-static? sv)
     ;; Static spine: retrieve component directly at compile time!
     ;; Zero residual 'cdr' instruction emitted!
     (let ((p (stage-val-payload sv)))
       (if (pair? p)
           (cdr p)
           *ctfe-failure*)))
    ((stage-val-pure-dynamic? sv)
     ;; Pure dynamic: emit residual cdr ANF instruction
     (let ((res (stage-apply-prim-1 dict 'cdr (stage-val-payload sv))))
       (make-dynamic-val 'any res loc (stage-val-guest-span sv))))
    (else *ctfe-failure*)))


;;; =======================================================================
;;; Stage-Polymorphic Evaluator Core Loop (DSN-33-03 §2.6, §3.5, §3.7)
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 9. Environment Utilities & Primitive Predicates
;;; -----------------------------------------------------------------------

(define (stage-env-lookup-entry env sym)
  (assq sym env))

(define (stage-env-lookup env sym)
  (let ((entry (assq sym env)))
    (if entry
        (cdr entry)
        #f)))

(define (stage-env-extend env sym val)
  (cons (cons sym val) env))

(define (stage-constant-type expr)
  (cond
    ((number? expr) 'number)
    ((boolean? expr) 'boolean)
    ((char? expr) 'char)
    ((string? expr) 'string)
    ((null? expr) 'null)
    (else 'constant)))

(define (stage-known-primitive? sym)
  (if (memq sym '(+ - * / quotient modulo remainder abs min max
                  not null? pair? boolean? number? symbol? string? char?
                  zero? list?
                  car cdr caar cadr cdar cddr length reverse cons list append
                  assq memq
                  eq? eqv? equal? char=? boolean=? symbol=? = < <= > >=
                  bitwise-and bitwise-ior bitwise-xor bitwise-not arithmetic-shift
                  char->integer integer->char string-length vector-length
                  vector-ref vector-set! make-vector string-ref
                  local-slot-ref local-slot-set!
                  guest-pack-fixnum guest-unpack-fixnum guest-fixnum?
                  guest-pack-pointer guest-unpack-pointer guest-tag-of
                  guest-pointer-of-tag? guest-pair? guest-symbol? guest-closure?
                  guest-vector? guest-instance? guest-flonum-ptr?
                  guest-pack-special guest-unpack-special guest-special?
                  nan-box-int32 nan-unbox-int32 nan-is-int32?
                  nan-box-pointer nan-unbox-pointer nan-is-pointer?
                  nan-box-special nan-unbox-special nan-is-special?
                  nan-box-flonum nan-unbox-flonum nan-is-flonum?
                  fx+ fx- fx* fxadd1 fxsub1
                  display write newline))
      #t
      #f))

(define (stage-pure-effect-free? sym)
  (if (memq sym '(+ - * abs not null? pair? boolean? number? symbol? string? char?
                  zero? list? length reverse cons list append
                  assq memq
                  eq? eqv? equal? char=? boolean=? symbol=? = < <= > >=
                  bitwise-and bitwise-ior bitwise-xor bitwise-not arithmetic-shift
                  char->integer integer->char string-length vector-length
                  vector-ref make-vector local-slot-ref
                  guest-pack-fixnum guest-unpack-fixnum guest-fixnum?
                  guest-pack-pointer guest-unpack-pointer guest-tag-of
                  guest-pointer-of-tag? guest-pair? guest-symbol? guest-closure?
                  guest-vector? guest-instance? guest-flonum-ptr?
                  guest-pack-special guest-unpack-special guest-special?
                  nan-box-int32 nan-unbox-int32 nan-is-int32?
                  nan-box-pointer nan-unbox-pointer nan-is-pointer?
                  nan-box-special nan-unbox-special nan-is-special?
                  nan-box-flonum nan-unbox-flonum nan-is-flonum?
                  fx+ fx- fx* fxadd1 fxsub1))
      #t
      #f))

(define (stage-potentially-trapping-prim? sym)
  (if (memq sym '(/ quotient modulo remainder car cdr caar cadr cdar cddr vector-ref string-ref local-slot-ref))
      #t
      #f))

(define (stage-impure-primitive? sym)
  (if (memq sym '(display write newline set-car! set-cdr! vector-set! string-set! local-slot-set!))
      #t
      #f))

(define (stage-pure-expression? expr)
  (cond
    ((or (number? expr) (boolean? expr) (char? expr) (string? expr) (null? expr)) #t)
    ((symbol? expr) #t)
    ((not (pair? expr)) #t)
    ((eq? (car expr) 'quote) #t)
    ((eq? (car expr) '%bta-annotated)
     (stage-pure-expression? (caddr expr)))
    ((stage-pure-effect-free? (car expr))
     (let loop ((args (cdr expr)))
       (cond
         ((null? args) #t)
         ((stage-pure-expression? (car args)) (loop (cdr args)))
         (else #f))))
    (else #f)))

;;; -----------------------------------------------------------------------
;;; 10. Primitive & Function Application Dispatch
;;; -----------------------------------------------------------------------

(define (all-pure-static? svs)
  (cond
    ((null? svs) #t)
    ((stage-val-pure-static? (car svs)) (all-pure-static? (cdr svs)))
    (else #f)))

(define (extract-payloads svs)
  (if (null? svs)
      '()
      (cons (stage-val-payload (car svs))
            (extract-payloads (cdr svs)))))

(define (find-first-csp-error lst)
  (cond
    ((null? lst) #f)
    ((stage-csp-error? (car lst)) (car lst))
    (else (find-first-csp-error (cdr lst)))))

(define (extract-lifted-payloads dict svs)
  (if (null? svs)
      '()
      (let* ((sv (car svs))
             (p (if (stage-val-pure-static? sv)
                    (stage-lift-val dict (stage-val-payload sv) sv)
                    (stage-val-payload sv))))
        (cons p (extract-lifted-payloads dict (cdr svs))))))

(define (eval-in-stage-apply-known-prim dict op args loc)
  (let ((nargs (length args)))
    (cond
      ;; Impure primitive under Later stage -> directly demote to residual code (Speculative Trap / Effect Leak Prevention)
      ((and (stage-impure-primitive? op) (stage-dict-later? dict))
       (let* ((lifted (extract-lifted-payloads dict args))
              (csp-err (find-first-csp-error lifted)))
         (if csp-err
             csp-err
             (let ((res-call (cons op lifted)))
               (make-dynamic-val 'any res-call loc #f)))))

      ;; Impure primitive under Now stage -> not allowed during CTFE / Now stage evaluation!
      ((and (stage-impure-primitive? op) (stage-dict-now? dict))
       (stage-signal-csp-error dict 'impure-primitive-in-now-stage (cons op (extract-payloads args))))

      ;; All arguments are pure-static -> execute CTFE directly via Now dictionary
      ((all-pure-static? args)
       (let* ((raw-args (extract-payloads args))
              (raw-res
               (cond
                 ((= nargs 0) (ctfe-apply-primitive op '()))
                 ((= nargs 1)
                  (let ((res (stage-apply-prim-1 (make-now-dict) op (car raw-args))))
                    (if (ctfe-failure? res)
                        (ctfe-apply-primitive op raw-args)
                        res)))
                 ((= nargs 2)
                  (let ((res (stage-apply-prim-2 (make-now-dict) op (car raw-args) (cadr raw-args))))
                    (if (ctfe-failure? res)
                        (ctfe-apply-primitive op raw-args)
                        res)))
                 ((= nargs 3)
                  (let ((res (stage-apply-prim-3 (make-now-dict) op (car raw-args) (cadr raw-args) (caddr raw-args))))
                    (if (ctfe-failure? res)
                        (ctfe-apply-primitive op raw-args)
                        res)))
                 ((= nargs 4)
                  (let ((res (stage-apply-prim-4 (make-now-dict) op (car raw-args) (cadr raw-args) (caddr raw-args) (cadddr raw-args))))
                    (if (ctfe-failure? res)
                        (ctfe-apply-primitive op raw-args)
                        res)))
                 (else (ctfe-apply-primitive op raw-args)))))
         (if (ctfe-failure? raw-res)
             (if (stage-dict-now? dict)
                 (stage-signal-csp-error dict 'ctfe-primitive-failure (cons op raw-args))
                 ;; Later dict: demote speculative failure to residual call
                 (let* ((lifted (extract-lifted-payloads dict args))
                        (csp-err (find-first-csp-error lifted)))
                   (if csp-err
                       csp-err
                       (let ((res-call (cond
                                         ((= nargs 1) (stage-apply-prim-1 dict op (car lifted)))
                                         ((= nargs 2) (stage-apply-prim-2 dict op (car lifted) (cadr lifted)))
                                         ((= nargs 3) (stage-apply-prim-3 dict op (car lifted) (cadr lifted) (caddr lifted)))
                                         (else (cons op lifted)))))
                         (make-dynamic-val 'any res-call loc #f)))))
             (make-static-val (stage-constant-type raw-res) raw-res loc #f))))

      ;; Dynamic or partially-static arguments in Now dict -> CSP error!
      ((stage-dict-now? dict)
       (stage-signal-csp-error dict 'now-stage-cannot-evaluate-dynamic (cons op (extract-payloads args))))

      ;; Dynamic or PSDS in Later dict -> residual code generation
      (else
       (cond
         ;; PSDS cons
         ((and (eq? op 'cons) (= nargs 2))
          (stage-cons (car args) (cadr args) loc #f))

         ;; PSDS car
         ((and (eq? op 'car) (= nargs 1))
          (stage-car dict (car args) loc))

         ;; PSDS cdr
         ((and (eq? op 'cdr) (= nargs 1))
          (stage-cdr dict (car args) loc))

         ;; Guest Frame Lowering: assq (DSN-33-04 §2.2 & Issue #892)
         ((and (eq? op 'assq) (= nargs 2))
          (let ((key-sv (car args))
                (env-sv (cadr args)))
            (cond
              ;; If key is static and a guest frame descriptor is currently active
              ((and (stage-val-pure-static? key-sv)
                    (procedure? get-current-guest-frame-descriptor)
                    (get-current-guest-frame-descriptor))
               (let* ((gfd (get-current-guest-frame-descriptor))
                      (var-name (stage-val-payload key-sv))
                      (slot-idx (gfd-lookup-slot gfd var-name)))
                 (if slot-idx
                     (let* ((esc? (gfd-escapes? gfd slot-idx))
                            (val-expr (if esc?
                                          (list 'vector-ref (stage-val-payload env-sv) slot-idx)
                                          (list 'local-slot-ref slot-idx))))
                       ;; Return a PSDS pair so that (cdr (assq 'var env)) immediately simplifies to val-expr!
                       (stage-cons key-sv (make-dynamic-val 'any val-expr loc #f) loc #f))
                     (let* ((lifted (extract-lifted-payloads dict args)))
                       (make-dynamic-val 'any (cons 'assq lifted) loc #f)))))
              (else
               (let* ((lifted (extract-lifted-payloads dict args)))
                 (make-dynamic-val 'any (cons 'assq lifted) loc #f))))))

         ;; Tag Stripping: guest-unpack-fixnum (DSN-33-04 §2.3 & Issue #893)
         ((and (eq? op 'guest-unpack-fixnum) (= nargs 1))
          (let* ((arg (car args))
                 (p (stage-val-payload arg)))
            (cond
              ((and (pair? p) (eq? (car p) 'guest-pack-fixnum) (pair? (cdr p)))
               (make-dynamic-val 'integer (cadr p) loc #f))
              (else
               (let ((lifted (extract-lifted-payloads dict args)))
                 (make-dynamic-val 'any (cons op lifted) loc #f))))))

         ;; Tag Stripping: guest-fixnum?
         ((and (eq? op 'guest-fixnum?) (= nargs 1))
          (let* ((arg (car args))
                 (p (stage-val-payload arg)))
            (cond
              ((and (pair? p) (eq? (car p) 'guest-pack-fixnum))
               (make-static-val 'boolean #t loc #f))
              (else
               (let ((lifted (extract-lifted-payloads dict args)))
                 (make-dynamic-val 'any (cons op lifted) loc #f))))))

         ;; Tag Stripping: nan-unbox-int32
         ((and (eq? op 'nan-unbox-int32) (= nargs 1))
          (let* ((arg (car args))
                 (p (stage-val-payload arg)))
            (cond
              ((and (pair? p) (eq? (car p) 'nan-box-int32) (pair? (cdr p)))
               (make-dynamic-val 'integer (cadr p) loc #f))
              (else
               (let ((lifted (extract-lifted-payloads dict args)))
                 (make-dynamic-val 'any (cons op lifted) loc #f))))))

         ;; Tag Stripping: nan-is-int32?
         ((and (eq? op 'nan-is-int32?) (= nargs 1))
          (let* ((arg (car args))
                 (p (stage-val-payload arg)))
            (cond
              ((and (pair? p) (eq? (car p) 'nan-box-int32))
               (make-static-val 'boolean #t loc #f))
              (else
               (let ((lifted (extract-lifted-payloads dict args)))
                 (make-dynamic-val 'any (cons op lifted) loc #f))))))

         ;; Tag Stripping: nan-unbox-pointer
         ((and (eq? op 'nan-unbox-pointer) (= nargs 1))
          (let* ((arg (car args))
                 (p (stage-val-payload arg)))
            (cond
              ((and (pair? p) (eq? (car p) 'nan-box-pointer) (pair? (cdr p)))
               (make-dynamic-val 'pointer (cadr p) loc #f))
              (else
               (let ((lifted (extract-lifted-payloads dict args)))
                 (make-dynamic-val 'any (cons op lifted) loc #f))))))

         ;; Tag Stripping: nan-is-pointer?
         ((and (eq? op 'nan-is-pointer?) (= nargs 1))
          (let* ((arg (car args))
                 (p (stage-val-payload arg)))
            (cond
              ((and (pair? p) (eq? (car p) 'nan-box-pointer))
               (make-static-val 'boolean #t loc #f))
              (else
               (let ((lifted (extract-lifted-payloads dict args)))
                 (make-dynamic-val 'any (cons op lifted) loc #f))))))

         ;; Tag Stripping: nan-unbox-flonum
         ((and (eq? op 'nan-unbox-flonum) (= nargs 1))
          (let* ((arg (car args))
                 (p (stage-val-payload arg)))
            (cond
              ((and (pair? p) (eq? (car p) 'nan-box-flonum) (pair? (cdr p)))
               (make-dynamic-val 'real (cadr p) loc #f))
              (else
               (let ((lifted (extract-lifted-payloads dict args)))
                 (make-dynamic-val 'any (cons op lifted) loc #f))))))

         ;; Tag Stripping: nan-is-flonum?
         ((and (eq? op 'nan-is-flonum?) (= nargs 1))
          (let* ((arg (car args))
                 (p (stage-val-payload arg)))
            (cond
              ((and (pair? p) (eq? (car p) 'nan-box-flonum))
               (make-static-val 'boolean #t loc #f))
              (else
               (let ((lifted (extract-lifted-payloads dict args)))
                 (make-dynamic-val 'any (cons op lifted) loc #f))))))

         ;; Tag Stripping: guest-unpack-pointer
         ((and (eq? op 'guest-unpack-pointer) (= nargs 2))
          (let* ((arg1 (car args))
                 (arg2 (cadr args))
                 (p1 (stage-val-payload arg1))
                 (p2 (stage-val-payload arg2)))
            (cond
              ((and (pair? p1) (eq? (car p1) 'guest-pack-pointer) (pair? (cdr p1)) (pair? (cddr p1))
                    (equal? (caddr p1) p2))
               (make-dynamic-val 'pointer (cadr p1) loc #f))
              (else
               (let ((lifted (extract-lifted-payloads dict args)))
                 (make-dynamic-val 'any (cons op lifted) loc #f))))))

         ;; Tag Stripping: guest-pointer-of-tag?
         ((and (eq? op 'guest-pointer-of-tag?) (= nargs 2))
          (let* ((arg1 (car args))
                 (arg2 (cadr args))
                 (p1 (stage-val-payload arg1))
                 (p2 (stage-val-payload arg2)))
            (cond
              ((and (pair? p1) (eq? (car p1) 'guest-pack-pointer) (pair? (cdr p1)) (pair? (cddr p1))
                    (equal? (caddr p1) p2))
               (make-static-val 'boolean #t loc #f))
              (else
               (let ((lifted (extract-lifted-payloads dict args)))
                 (make-dynamic-val 'any (cons op lifted) loc #f))))))

         ;; General dynamic primitive residualization
         (else
          (let* ((lifted (extract-lifted-payloads dict args))
                 (csp-err (find-first-csp-error lifted)))
            (if csp-err
                csp-err
                (let ((res-call
                       (cond
                         ((= nargs 1) (stage-apply-prim-1 dict op (car lifted)))
                         ((= nargs 2) (stage-apply-prim-2 dict op (car lifted) (cadr lifted)))
                         ((= nargs 3) (stage-apply-prim-3 dict op (car lifted) (cadr lifted) (caddr lifted)))
                         ((= nargs 4) (stage-apply-prim-4 dict op (car lifted) (cadr lifted) (caddr lifted) (cadddr lifted)))
                         (else (cons op lifted)))))
                  (make-dynamic-val 'any res-call loc #f))))))))))

(define (eval-in-stage-apply dict env head args-exprs fuel depth)
  (let loop ((exprs args-exprs)
             (curr-fuel fuel)
             (acc '()))
    (cond
      ((null? exprs)
       (let ((evaled-args (reverse acc)))
         (if (stage-known-primitive? head)
             (eval-in-stage-apply-known-prim dict head evaled-args #f)
             ;; Variable or lambda application
             (let ((callee-sv (if (symbol? head)
                                  (eval-in-stage dict env head curr-fuel depth)
                                  (eval-in-stage dict env head curr-fuel depth))))
               (cond
                 ((stage-csp-error? callee-sv) callee-sv)
                 ((stage-dict-now? dict)
                  (let ((callee (stage-val-payload callee-sv))
                        (arg-vals (extract-payloads evaled-args)))
                    (let ((res (stage-emit-call dict callee arg-vals)))
                      (if (ctfe-failure? res)
                          (stage-signal-csp-error dict 'now-call-failed (cons head arg-vals))
                          (make-static-val (stage-constant-type res) res #f #f)))))
                 (else
                  ;; Later dict: emit residual call
                  (let* ((callee-expr (stage-val-payload callee-sv))
                         (arg-exprs (extract-lifted-payloads dict evaled-args))
                         (csp-err (find-first-csp-error arg-exprs)))
                    (if csp-err
                        csp-err
                        (let ((res (stage-emit-call dict callee-expr arg-exprs)))
                          (make-dynamic-val 'any res #f #f))))))))))
      ((<= curr-fuel 0)
       (stage-signal-csp-error dict 'ctfe-fuel-exhausted head))
      (else
       (let ((sv (eval-in-stage dict env (car exprs) (- curr-fuel 1) depth)))
         (if (stage-csp-error? sv)
             sv
             (loop (cdr exprs) (- curr-fuel 1) (cons sv acc))))))))

;;; -----------------------------------------------------------------------
;;; 11. Let Bindings Handler
;;; -----------------------------------------------------------------------

(define (eval-in-stage-let dict env bindings body fuel depth)
  (let loop ((bs bindings)
             (curr-env env)
             (curr-fuel fuel)
             (acc-dyn '()))
    (cond
      ((null? bs)
       ;; All bindings processed, evaluate body
       (let ((body-sv (eval-in-stage dict curr-env body curr-fuel depth)))
         (cond
           ((stage-csp-error? body-sv) body-sv)
           ((null? acc-dyn) body-sv)
           (else
            ;; Wrap residual let-anf bindings from acc-dyn (in reverse order)
            (let wrap ((rem acc-dyn) (curr-payload (stage-val-payload body-sv)))
              (if (null? rem)
                  (make-dynamic-val 'any curr-payload #f #f)
                  (let* ((binding (car rem))
                         (var (car binding))
                         (rhs (cadr binding))
                         (nested (stage-bind-let dict var rhs (lambda () curr-payload))))
                    (wrap (cdr rem) nested))))))))
      ((<= curr-fuel 0)
       (stage-signal-csp-error dict 'ctfe-fuel-exhausted body))
      (else
       (let* ((b (car bs))
              (var (car b))
              (val-expr (cadr b))
              (val-sv (eval-in-stage dict curr-env val-expr (- curr-fuel 1) depth)))
         (cond
           ((stage-csp-error? val-sv) val-sv)
           ((stage-dict-now? dict)
            ;; Now dict: always bind value into environment
            (loop (cdr bs)
                  (stage-env-extend curr-env var val-sv)
                  (- curr-fuel 1)
                  acc-dyn))
           (else
            ;; Later dict:
            ;; Pure-static values are bound directly to env (inlined at compile time!)
            ;; Dynamic values are bound to env as dynamic variable reference, and scheduled for residual let
            (if (stage-val-pure-static? val-sv)
                (loop (cdr bs)
                      (stage-env-extend curr-env var val-sv)
                      (- curr-fuel 1)
                      acc-dyn)
                (loop (cdr bs)
                      (stage-env-extend curr-env var (make-dynamic-val (stage-val-tag val-sv) var #f #f))
                      (- curr-fuel 1)
                      (cons (list var (stage-val-payload val-sv)) acc-dyn))))))))))

(define (eval-in-stage-let* dict env bindings body fuel depth)
  (let loop ((bs bindings)
             (curr-env env)
             (curr-fuel fuel)
             (acc-dyn '()))
    (cond
      ((null? bs)
       ;; All bindings processed, evaluate body
       (let ((body-sv (eval-in-stage dict curr-env body curr-fuel depth)))
         (cond
           ((stage-csp-error? body-sv) body-sv)
           ((null? acc-dyn) body-sv)
           (else
            ;; Wrap residual let-anf bindings from acc-dyn (in reverse order)
            (let wrap ((rem acc-dyn) (curr-payload (stage-val-payload body-sv)))
              (if (null? rem)
                  (make-dynamic-val 'any curr-payload #f #f)
                  (let* ((binding (car rem))
                         (var (car binding))
                         (rhs (cadr binding))
                         (nested (stage-bind-let dict var rhs (lambda () curr-payload))))
                    (wrap (cdr rem) nested))))))))
      ((<= curr-fuel 0)
       (stage-signal-csp-error dict 'ctfe-fuel-exhausted body))
      (else
       (let* ((b (car bs))
              (var (car b))
              (val-expr (cadr b))
              ;; Sequential let*: each binding sees prior bindings in curr-env
              (val-sv (eval-in-stage dict curr-env val-expr (- curr-fuel 1) depth)))
         (cond
           ((stage-csp-error? val-sv) val-sv)
           ((stage-dict-now? dict)
            ;; Now dict: always bind value into environment sequentially
            (loop (cdr bs)
                  (stage-env-extend curr-env var val-sv)
                  (- curr-fuel 1)
                  acc-dyn))
           (else
            ;; Later dict:
            (if (stage-val-pure-static? val-sv)
                (loop (cdr bs)
                      (stage-env-extend curr-env var val-sv)
                      (- curr-fuel 1)
                      acc-dyn)
                (loop (cdr bs)
                      (stage-env-extend curr-env var (make-dynamic-val (stage-val-tag val-sv) var #f #f))
                      (- curr-fuel 1)
                      (cons (list var (stage-val-payload val-sv)) acc-dyn))))))))))

;;; -----------------------------------------------------------------------
;;; 12. Main eval-in-stage Core Loop
;;; -----------------------------------------------------------------------

(define (eval-in-stage dict env expr fuel depth)
  ;; 1. Resource bounds check (CWE-400 guard)
  (cond
    ((<= fuel 0)
     (stage-signal-csp-error dict 'ctfe-fuel-exhausted expr))
    ((<= depth 0)
     (stage-signal-csp-error dict 'ctfe-depth-overflow expr))

    ;; 2. Literals / Constants
    ((or (number? expr) (boolean? expr) (char? expr) (string? expr) (null? expr))
     (make-static-val (stage-constant-type expr) expr #f #f))

    ;; 3. Quoted forms
    ((and (pair? expr) (eq? (car expr) 'quote))
     (if (and (pair? (cdr expr)) (null? (cddr expr)))
         (make-static-val 'quoted (cadr expr) #f #f)
         (stage-signal-csp-error dict 'invalid-quote-syntax expr)))

    ;; 4. Symbols (Variable References)
    ((symbol? expr)
     (let ((entry (stage-env-lookup-entry env expr)))
       (if entry
           (let ((found (cdr entry)))
             (if (stage-val? found)
                 found
                 (make-static-val (stage-constant-type found) found #f #f)))
           (if (stage-dict-now? dict)
               (stage-signal-csp-error dict 'unbound-variable expr)
               (make-dynamic-val 'unknown expr #f #f)))))

    ;; 5. Non-pair forms (bytevectors, vectors, etc.)
    ((not (pair? expr))
     (make-static-val 'constant expr #f #f))

    ;; 6. Compound expressions
    (else
     (let ((head (car expr))
           (f1 (- fuel 1))
           (d1 (- depth 1)))
       (case head
         ;; Conditional: (if test then [else])
         ((if)
          (let ((test-expr (cadr expr))
                (then-expr (caddr expr))
                (else-expr (if (null? (cdddr expr)) #f (cadddr expr))))
            (let ((test-sv (eval-in-stage dict env test-expr f1 d1)))
              (cond
                ((stage-csp-error? test-sv) test-sv)
                ((stage-val-pure-static? test-sv)
                 ;; Static branch decision: dead branch is eliminated at compile-time!
                 (if (stage-val-payload test-sv)
                     (eval-in-stage dict env then-expr f1 depth)
                     (if else-expr
                         (eval-in-stage dict env else-expr f1 depth)
                         (make-static-val 'boolean #f #f #f))))
                (else
                 ;; Dynamic / PSDS branch: emit residual if-anf
                 (let ((res-expr
                        (stage-emit-if
                         dict
                         (stage-val-payload test-sv)
                         (lambda ()
                           (let ((th-sv (eval-in-stage dict env then-expr f1 d1)))
                             (if (stage-val? th-sv) (stage-val-payload th-sv) th-sv)))
                         (lambda ()
                           (if else-expr
                               (let ((el-sv (eval-in-stage dict env else-expr f1 d1)))
                                 (if (stage-val? el-sv) (stage-val-payload el-sv) el-sv))
                               #f)))))
                   (make-dynamic-val 'any res-expr #f #f)))))))

         ;; Sequential: (begin e ...)
         ((begin)
          (let loop ((es (cdr expr)) (curr-fuel f1) (last-sv (make-static-val 'unspecified #f #f #f)))
            (cond
              ((null? es) last-sv)
              ((<= curr-fuel 0) (stage-signal-csp-error dict 'ctfe-fuel-exhausted expr))
              (else
               (let ((sv (eval-in-stage dict env (car es) (- curr-fuel 1) d1)))
                 (if (stage-csp-error? sv)
                     sv
                     (loop (cdr es) (- curr-fuel 1) sv)))))))

         ;; Local Bindings: (let ((var val) ...) body)
         ((let let-anf)
          (if (and (pair? (cdr expr)) (pair? (cddr expr)))
              (let ((bindings (cadr expr))
                    (body (caddr expr)))
                (eval-in-stage-let dict env bindings body f1 d1))
              (stage-signal-csp-error dict 'invalid-let-syntax expr)))

         ;; Sequential Bindings: (let* ((var val) ...) body)
         ((let*)
          (if (and (pair? (cdr expr)) (pair? (cddr expr)))
              (let ((bindings (cadr expr))
                    (body (caddr expr)))
                (eval-in-stage-let* dict env bindings body f1 d1))
              (stage-signal-csp-error dict 'invalid-let-syntax expr)))

         ;; Pure Lambda Definition & Local Invocation
         ((lambda)
          (if (and (pair? (cdr expr)) (pair? (cddr expr)))
              (let ((params (cadr expr))
                    (lbody (caddr expr)))
                (if (stage-dict-now? dict)
                    (make-static-val 'closure (list '%ctfe-closure params lbody env) #f #f)
                    (make-dynamic-val 'procedure expr #f #f)))
              (stage-signal-csp-error dict 'invalid-lambda-syntax expr)))

         ;; Meta-Stage Constructs (DSN-33-03 §6.1)
         ((stage-now)
          (if (pair? (cdr expr))
              (let* ((now-d (make-now-dict))
                     (sv (eval-in-stage now-d env (cadr expr) f1 d1)))
                (cond
                  ((stage-csp-error? sv) sv)
                  ((stage-dict-now? dict) sv)
                  (else
                   ;; In Later dict: lift the evaluated static value into residual code
                   (let ((p (stage-val-payload sv)))
                     (make-static-val (stage-val-tag sv) p (stage-val-host-span sv) (stage-val-guest-span sv))))))
              (stage-signal-csp-error dict 'invalid-stage-syntax expr)))

         ((stage-later)
          (if (pair? (cdr expr))
              (let ((later-d (make-later-dict)))
                (eval-in-stage later-d env (cadr expr) f1 d1))
              (stage-signal-csp-error dict 'invalid-stage-syntax expr)))

         ((stage-lift)
          (if (pair? (cdr expr))
              (let* ((now-d (make-now-dict))
                     (sv (eval-in-stage now-d env (cadr expr) f1 d1)))
                (cond
                  ((stage-csp-error? sv) sv)
                  ((stage-val-pure-static? sv)
                   (let* ((later-d (make-later-dict))
                          (lifted (stage-lift-val later-d (stage-val-payload sv) sv)))
                     (if (stage-csp-error? lifted)
                         lifted
                         (make-static-val 'lifted lifted (stage-val-host-span sv) (stage-val-guest-span sv)))))
                  (else
                   (stage-signal-csp-error dict 'now-stage-cannot-evaluate-dynamic expr))))
              (stage-signal-csp-error dict 'invalid-stage-syntax expr)))

         ((stage-quasiquote)
          (if (pair? (cdr expr))
              (eval-in-stage dict env (cadr expr) f1 d1)
              (stage-signal-csp-error dict 'invalid-stage-syntax expr)))

         ;; BTA 4-Valued Lattice Annotated Form (DSN-33-03 §2.5, §4.1 & Issue #891)
         ((%bta-annotated)
          (if (and (pair? (cdr expr)) (pair? (cddr expr)))
              (let ((bt (cadr expr))
                    (inner (caddr expr)))
                (cond
                  ;; Speculatively reduce static & pure expressions at compile-time (Now)
                  ((and (eq? bt 'static) (stage-pure-expression? inner))
                   (let* ((now-d (make-now-dict))
                          (res-sv (eval-in-stage now-d env inner f1 d1)))
                     (cond
                       ((stage-csp-error? res-sv)
                        ;; Speculative Trap guard: fallback to ordinary evaluation if Now errors
                        (eval-in-stage dict env inner f1 d1))
                       ((stage-dict-now? dict)
                        res-sv)
                       (else
                        ;; In Later dict: promote evaluated static constant into residual AST
                        (make-static-val (stage-val-tag res-sv)
                                         (stage-val-payload res-sv)
                                         (stage-val-host-span res-sv)
                                         (stage-val-guest-span res-sv))))))
                  (else
                   ;; Otherwise transparently evaluate inner expression under current dictionary
                   (eval-in-stage dict env inner f1 d1))))
              (stage-signal-csp-error dict 'invalid-bta-syntax expr)))

         ;; Function / Primitive Application
         (else
          (eval-in-stage-apply dict env head (cdr expr) f1 d1)))))))

;;; -----------------------------------------------------------------------
;;; 13. Relative Stage-Level Transition & High-Level Evaluator Interface
;;; -----------------------------------------------------------------------

(define (stage-eval-level dict-now dict-later env expr fuel depth stage-level)
  (cond
    ((< stage-level 0)
     (stage-signal-csp-error dict-later 'invalid-negative-stage-level expr))
    ((> stage-level 0)
     ;; Higher stage: execute immediately via Now dictionary
     (eval-in-stage dict-now env expr fuel depth))
    (else
     ;; Stage-level 0: transition to Later dictionary (residual code generation)
     (eval-in-stage dict-later env expr fuel depth))))

(define (stage-eval-expr dict env expr)
  (eval-in-stage dict env expr *ctfe-default-step-limit* *ctfe-default-depth-limit*))


;;; -----------------------------------------------------------------------
;;; 14. Single-Source Semantic Oracle Interface (DSN-33-03 §3.6)
;;; -----------------------------------------------------------------------

(define (eval-with-now-oracle-opt expr env fuel depth)
  (let* ((now-d (make-now-dict))
         (res (eval-in-stage now-d env expr fuel depth)))
    (cond
      ((stage-csp-error? res) #f)
      ((stage-val? res)
       (let ((p (stage-val-payload res)))
         (val->ast-const p)))
      (else #f))))

(define (eval-with-now-oracle expr)
  (eval-with-now-oracle-opt expr '() *ctfe-default-step-limit* *ctfe-default-depth-limit*))

(register-language-evaluator! 'L_stage_poly
  (lambda (expr env fuel depth)
    (eval-with-now-oracle-opt expr env fuel depth)))


;;; =======================================================================
;;; Binding-Time Analysis (BTA) Engine (DSN-33-03 §4.1)
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 15. BTA Environment & Inference Rules
;;; -----------------------------------------------------------------------

(define (bta-env-empty) '())

(define (bta-env-lookup env var)
  (let ((entry (assq var env)))
    (if entry
        (cdr entry)
        'dynamic)))

(define (bta-env-extend env var type)
  (cons (cons var type) env))

(define (bta-infer-expr expr env)
  (cond
    ;; 1. Self-evaluating constants & literals
    ((or (number? expr) (boolean? expr) (char? expr) (string? expr) (null? expr))
     'static)

    ;; 2. Quoted datums
    ((and (pair? expr) (eq? (car expr) 'quote))
     'static)

    ;; 3. Variable references
    ((symbol? expr)
     (bta-env-lookup env expr))

    ;; 4. Non-pair forms
    ((not (pair? expr))
     'static)

    ;; 5. Compound forms
    (else
     (let ((head (car expr)))
       (case head
         ;; Conditional: (if test then [else])
         ((if)
          (let ((test-bt (bta-infer-expr (cadr expr) env))
                (then-bt (bta-infer-expr (caddr expr) env))
                (else-bt (if (pair? (cdddr expr))
                             (bta-infer-expr (cadddr expr) env)
                             'static)))
            (if (eq? test-bt 'static)
                (bta-join then-bt else-bt)
                'dynamic)))

         ;; Sequential: (begin e ...)
         ((begin)
          (let loop ((es (cdr expr)) (last-bt 'static))
            (if (null? es)
                last-bt
                (loop (cdr es) (bta-infer-expr (car es) env)))))

         ;; Local Bindings: (let ((x e) ...) body)
         ((let)
          (if (and (pair? (cdr expr)) (pair? (cddr expr)))
              (let ((bindings (cadr expr))
                    (body (caddr expr)))
                (let loop ((bs bindings) (curr-env env))
                  (if (null? bs)
                      (bta-infer-expr body curr-env)
                      (let* ((b (car bs))
                             (var (car b))
                             (rhs (cadr b))
                             (rhs-bt (bta-infer-expr rhs env)))
                        (loop (cdr bs) (bta-env-extend curr-env var rhs-bt))))))
              'dynamic))

         ;; Pairs & PSDS constructor: (cons a b)
         ((cons)
          (if (and (pair? (cdr expr)) (pair? (cddr expr)))
              (let ((car-bt (bta-infer-expr (cadr expr) env))
                    (cdr-bt (bta-infer-expr (caddr expr) env)))
                (if (and (eq? car-bt 'static) (eq? cdr-bt 'static))
                    'static
                    'psds))
              'dynamic))

         ;; Pair accessors: (car p), (cdr p)
         ((car cdr)
          (if (pair? (cdr expr))
              (let ((arg-bt (bta-infer-expr (cadr expr) env)))
                (cond
                  ((eq? arg-bt 'static) 'static)
                  ((eq? arg-bt 'psds) 'dynamic)
                  (else 'dynamic)))
              'dynamic))

         ;; Known Primitives
         (else
          (if (stage-known-primitive? head)
              (let loop ((args (cdr expr)))
                (cond
                  ((null? args) 'static)
                  ((eq? (bta-infer-expr (car args) env) 'static)
                   (loop (cdr args)))
                  (else 'dynamic)))
              'dynamic)))))))

(define (bta-annotate-ast expr env)
  (let ((bt (bta-infer-expr expr env)))
    (list '%bta-annotated bt expr)))

(define (bta-annotated? x)
  (and (pair? x) (eq? (car x) '%bta-annotated)))

(define (bta-annotation-type x)
  (if (bta-annotated? x) (cadr x) 'dynamic))

(define (bta-annotation-expr x)
  (if (bta-annotated? x) (caddr x) x))

;;; -----------------------------------------------------------------------
;;; Hybrid BTA Static Environment Extraction & Recursive AST Annotation
;;; Conforms to DSN-33-03 §2.5, §4.1 & Issue #891
;;; -----------------------------------------------------------------------

(define (bta-extract-static-env bta-env runtime-env)
  (let loop ((bs (if (list? bta-env) bta-env '())) (acc '()))
    (if (null? bs)
        (reverse acc)
        (let* ((b (car bs))
               (var (car b))
               (bt (cdr b)))
          (if (or (eq? bt 'static) (eq? bt 'psds))
              (let ((entry (assq var runtime-env)))
                (if entry
                    (loop (cdr bs) (cons entry acc))
                    (loop (cdr bs) acc)))
              (loop (cdr bs) acc))))))

(define (bta-annotate-ast-recursive expr env)
  (cond
    ((or (number? expr) (boolean? expr) (char? expr) (string? expr) (null? expr))
     (list '%bta-annotated 'static expr))
    ((symbol? expr)
     (let ((bt (let ((entry (assq expr env)))
                 (if entry (cdr entry) 'dynamic))))
       (list '%bta-annotated bt expr)))
    ((not (pair? expr))
     (list '%bta-annotated 'static expr))
    ((eq? (car expr) 'quote)
     (list '%bta-annotated 'static expr))
    ((eq? (car expr) '%bta-annotated)
     expr)
    (else
     (let ((head (car expr)))
       (case head
         ((if)
          (let* ((test-ann (bta-annotate-ast-recursive (cadr expr) env))
                 (then-ann (bta-annotate-ast-recursive (caddr expr) env))
                 (else-ann (if (pair? (cdddr expr))
                               (bta-annotate-ast-recursive (cadddr expr) env)
                               #f))
                 (test-bt (bta-annotation-type test-ann))
                 (then-bt (bta-annotation-type then-ann))
                 (else-bt (if else-ann (bta-annotation-type else-ann) 'static))
                 (overall-bt (if (eq? test-bt 'static)
                                 (bta-join then-bt else-bt)
                                 'dynamic)))
            (list '%bta-annotated overall-bt
                  (if else-ann
                      (list 'if test-ann then-ann else-ann)
                      (list 'if test-ann then-ann)))))
         ((let let-anf)
          (if (and (pair? (cdr expr)) (pair? (cddr expr)))
              (let* ((bindings (cadr expr))
                     (body (caddr expr))
                     (new-bs-and-env
                      (let loop ((bs bindings) (curr-env env) (ann-bs '()))
                        (if (null? bs)
                            (cons (reverse ann-bs) curr-env)
                            (let* ((b (car bs))
                                   (var (car b))
                                   (rhs (cadr b))
                                   (rhs-ann (bta-annotate-ast-recursive rhs env))
                                   (rhs-bt (bta-annotation-type rhs-ann)))
                              (loop (cdr bs)
                                    (bta-env-extend curr-env var rhs-bt)
                                    (cons (list var rhs-ann) ann-bs))))))
                     (ann-bindings (car new-bs-and-env))
                     (extended-env (cdr new-bs-and-env))
                     (body-ann (bta-annotate-ast-recursive body extended-env))
                     (overall-bt (bta-annotation-type body-ann)))
                (list '%bta-annotated overall-bt
                      (list head ann-bindings body-ann)))
              (list '%bta-annotated 'dynamic expr)))
         ((cons)
          (if (and (pair? (cdr expr)) (pair? (cddr expr)))
              (let* ((car-ann (bta-annotate-ast-recursive (cadr expr) env))
                     (cdr-ann (bta-annotate-ast-recursive (caddr expr) env))
                     (car-bt (bta-annotation-type car-ann))
                     (cdr-bt (bta-annotation-type cdr-ann))
                     (overall-bt (if (and (eq? car-bt 'static) (eq? cdr-bt 'static))
                                     'static
                                     'psds)))
                (list '%bta-annotated overall-bt
                      (list 'cons car-ann cdr-ann)))
              (list '%bta-annotated 'dynamic expr)))
         ((car cdr)
          (if (pair? (cdr expr))
              (let* ((arg-ann (bta-annotate-ast-recursive (cadr expr) env))
                     (arg-bt (bta-annotation-type arg-ann))
                     (overall-bt (if (eq? arg-bt 'static) 'static 'dynamic)))
                (list '%bta-annotated overall-bt
                      (list head arg-ann)))
              (list '%bta-annotated 'dynamic expr)))
         (else
          (let* ((sub-anns (map (lambda (e) (bta-annotate-ast-recursive e env)) (cdr expr)))
                 (args-static? (let loop ((as sub-anns))
                                 (cond
                                   ((null? as) #t)
                                   ((eq? (bta-annotation-type (car as)) 'static)
                                    (loop (cdr as)))
                                   (else #f))))
                 (overall-bt (if (and (stage-known-primitive? head) args-static?)
                                 'static
                                 'dynamic)))
            (list '%bta-annotated overall-bt
                  (cons head sub-anns)))))))))

(define (bta-hybrid-stage-lower expr runtime-env bta-initial-env)
  (let* ((static-env (bta-extract-static-env bta-initial-env runtime-env))
         (full-bta-env (let loop ((re runtime-env) (be (if (list? bta-initial-env) bta-initial-env '())))
                         (if (null? re)
                             be
                             (let* ((v (caar re))
                                    (existing (assq v be)))
                               (if existing
                                   (loop (cdr re) be)
                                   (loop (cdr re) (bta-env-extend be v 'static)))))))
         (annotated (bta-annotate-ast-recursive expr full-bta-env)))
    (stage-poly-lower annotated static-env)))

;;; =======================================================================
;;; Specialization Engine & Hard Limits & Generalization (DSN-33-03 §5.1-§5.3)
;;; =======================================================================

(define *max-spec-instances* 8)
(define *max-spec-depth* 4)

;;; -----------------------------------------------------------------------
;;; 16. Static Projection Operator Pi_static & Signature Key
;;; -----------------------------------------------------------------------

(define (stage-project-static-key sv)
  (cond
    ((not (stage-val? sv)) sv)
    ((stage-val-pure-static? sv)
     (let ((p (stage-val-payload sv)))
       (if (pair? p)
           (cons (stage-project-static-key (car p))
                 (stage-project-static-key (cdr p)))
           p)))
    ((stage-val-partially-static? sv)
     (let ((p (stage-val-payload sv)))
       (if (pair? p)
           (cons (stage-project-static-key (car p))
                 (stage-project-static-key (cdr p)))
           '*dynamic*)))
    ((stage-val-pure-dynamic? sv)
     '*dynamic*)
    (else '*dynamic*)))

(define (make-spec-signature-key fn-name arg-svs)
  (let loop ((rem arg-svs) (acc '()))
    (if (null? rem)
        (cons fn-name (reverse acc))
        (loop (cdr rem) (cons (stage-project-static-key (car rem)) acc)))))

;;; -----------------------------------------------------------------------
;;; 17. <spec-memo-table> Record Definition
;;; -----------------------------------------------------------------------

(define-record-type <spec-memo-table>
  (%make-spec-memo-table-raw table-box instances-box residual-fns-box depth-box counter-box)
  spec-memo-table?
  (table-box        %spec-memo-table-box)
  (instances-box    %spec-memo-instances-box)
  (residual-fns-box %spec-memo-residual-fns-box)
  (depth-box        %spec-memo-depth-box)
  (counter-box      %spec-memo-counter-box))

(define (make-spec-memo-table)
  (%make-spec-memo-table-raw
    (cons '() '())  ;; table: ((key . spec-name) ...)
    (cons '() '())  ;; instances: ((fn . count) ...)
    (cons '() '())  ;; residual-fns: (fn-def ...)
    (cons 0 '())    ;; current depth
    (cons 0 '())))  ;; unique symbol counter

(define (spec-memo-table-entries memo)
  (car (%spec-memo-table-box memo)))

(define (spec-memo-lookup memo key)
  (let loop ((entries (car (%spec-memo-table-box memo))))
    (cond
      ((null? entries) #f)
      ((equal? (caar entries) key) (cdar entries))
      (else (loop (cdr entries))))))

(define (spec-memo-instance-count memo fn-name)
  (let loop ((entries (car (%spec-memo-instances-box memo))))
    (cond
      ((null? entries) 0)
      ((eq? (caar entries) fn-name) (cdar entries))
      (else (loop (cdr entries))))))

(define (spec-memo-current-depth memo)
  (car (%spec-memo-depth-box memo)))

(define (spec-memo-set-depth! memo d)
  (set-car! (%spec-memo-depth-box memo) d))

(define (spec-memo-can-specialize? memo fn-name key depth)
  (cond
    ((> depth *max-spec-depth*) #f)
    ((>= (spec-memo-instance-count memo fn-name) *max-spec-instances*) #f)
    (else #t)))

(define (spec-memo-register! memo fn-name key)
  (let* ((ctr-box (%spec-memo-counter-box memo))
         (id (car ctr-box))
         (spec-name (string->symbol
                      (string-append (symbol->string fn-name) "$spec" (number->string id)))))
    (set-car! ctr-box (+ id 1))
    ;; Register in table
    (let ((tbl-box (%spec-memo-table-box memo)))
      (set-car! tbl-box (cons (cons key spec-name) (car tbl-box))))
    ;; Increment instance count
    (let* ((inst-box (%spec-memo-instances-box memo))
           (insts (car inst-box)))
      (let loop ((rem insts) (acc '()) (found #f))
        (cond
          ((null? rem)
           (if found
               (set-car! inst-box (reverse acc))
               (set-car! inst-box (cons (cons fn-name 1) insts))))
          ((eq? (caar rem) fn-name)
           (loop (cdr rem) (cons (cons fn-name (+ (cdar rem) 1)) acc) #t))
          (else
           (loop (cdr rem) (cons (car rem) acc) found)))))
    spec-name))

(define (spec-memo-record-residual-fn! memo fn-def)
  (let ((box (%spec-memo-residual-fns-box memo)))
    (set-car! box (cons fn-def (car box)))))

(define (spec-memo-residual-fns memo)
  (reverse (car (%spec-memo-residual-fns-box memo))))

;;; -----------------------------------------------------------------------
;;; 18. Generalization (Widening) & Argument Demotion
;;; -----------------------------------------------------------------------

(define (spec-widen-arguments arg-svs)
  (let loop ((rem arg-svs) (acc '()))
    (if (null? rem)
        (reverse acc)
        (let* ((sv (car rem))
               (p (if (stage-val? sv) (stage-val-payload sv) sv))
               (w-sv (make-dynamic-val 'widened p #f #f)))
          (loop (cdr rem) (cons w-sv acc))))))

(define (spec-extract-dynamic-payloads arg-svs)
  (let loop ((rem arg-svs) (acc '()))
    (if (null? rem)
        (reverse acc)
        (let ((sv (car rem)))
          (cond
            ((stage-val-pure-dynamic? sv)
             (loop (cdr rem) (cons (stage-val-payload sv) acc)))
            ((stage-val-partially-static? sv)
             (loop (cdr rem) (cons (stage-val-payload sv) acc)))
            (else
             (loop (cdr rem) acc)))))))

(define (specialize-or-widen memo fn-name arg-svs depth spec-builder-proc)
  (let ((key (make-spec-signature-key fn-name arg-svs)))
    ;; 1. Memoization cache lookup
    (let ((cached (spec-memo-lookup memo key)))
      (if cached
          (list 'cached cached (spec-extract-dynamic-payloads arg-svs))
          ;; 2. Hard limits check (Instances & Depth)
          (if (spec-memo-can-specialize? memo fn-name key depth)
              ;; 3. Specialize: allocate name & emit residual function
              (let* ((spec-fn (spec-memo-register! memo fn-name key))
                     (prev-depth (spec-memo-current-depth memo)))
                (spec-memo-set-depth! memo (+ depth 1))
                (let ((fn-def (spec-builder-proc spec-fn arg-svs)))
                  (spec-memo-record-residual-fn! memo fn-def)
                  (spec-memo-set-depth! memo prev-depth)
                  (list 'specialized spec-fn (spec-extract-dynamic-payloads arg-svs))))
              ;; 4. Widening fallback: generalize arguments
              (let ((widened-args (spec-widen-arguments arg-svs)))
                (list 'widened fn-name (let loop ((rem widened-args) (acc '()))
                                         (if (null? rem)
                                             (reverse acc)
                                             (loop (cdr rem) (cons (stage-val-payload (car rem)) acc)))))))))))

;;; -----------------------------------------------------------------------
;;; 19. Stage-Poly Lowering Nanopass (L-StagePoly -> L-Residual-ANF)
;;; Conforms to DSN-33-03 §2.1, §3.3, §6.2 & Issue #879
;;; -----------------------------------------------------------------------

(define *stage-poly-lower-counter* (cons 0 '()))

(define (stage-poly-lower-gensym prefix)
  (let ((id (car *stage-poly-lower-counter*)))
    (set-car! *stage-poly-lower-counter* (+ id 1))
    (string->symbol (string-append prefix (number->string id)))))

(define (stage-atomic-value? x)
  (or (number? x) (boolean? x) (char? x) (string? x) (symbol? x) (null? x)))

(define (stage-normalize-to-residual-anf expr)
  (cond
    ;; %bta-annotated transparent unwrap
    ((and (pair? expr) (eq? (car expr) '%bta-annotated))
     (stage-normalize-to-residual-anf (caddr expr)))

    ;; Atomic value
    ((stage-atomic-value? expr)
     (list 'atom-value expr))

    ((not (pair? expr))
     (list 'atom-value expr))

    ;; (if-anf test then else) -> (if test (norm then) (norm else))
    ((eq? (car expr) 'if-anf)
     (let ((test (cadr expr))
           (then (caddr expr))
           (else-e (cadddr expr)))
       (list 'if test
             (stage-normalize-to-residual-anf then)
             (stage-normalize-to-residual-anf else-e))))

    ;; (let-anf ((x rhs)) body)
    ((eq? (car expr) 'let-anf)
     (let* ((bindings (cadr expr))
            (body (caddr expr))
            (b (car bindings))
            (var (car b))
            (rhs (cadr b)))
       (list 'let-anf (list (list var rhs))
             (stage-normalize-to-residual-anf body))))

    ;; (call-anf fn args ...) -> (let-call ((t (fn args ...))) (atom-value t))
    ((eq? (car expr) 'call-anf)
     (let ((tmp (stage-poly-lower-gensym "call$")))
       (list 'let-call (list (list tmp (cons (cadr expr) (cddr expr))))
             (list 'atom-value tmp))))

    ;; Quoted literal: '(...) -> (atom-value '(..))
    ((eq? (car expr) 'quote)
     (list 'atom-value expr))

    ;; Residual function or primitive application: (op arg ...)
    (else
     (if (stage-known-primitive? (car expr))
         (let ((tmp (stage-poly-lower-gensym "prim$")))
           (list 'let-anf (list (list tmp expr))
                 (list 'atom-value tmp)))
         (let ((tmp (stage-poly-lower-gensym "app$")))
           (list 'let-call (list (list tmp expr))
                 (list 'atom-value tmp)))))))

(define stage-poly-lower
  (case-lambda
    ((expr env)
     (let* ((later-d (make-later-dict))
            (res-sv (eval-in-stage later-d env expr *ctfe-default-step-limit* *ctfe-default-depth-limit*)))
       (cond
         ((stage-csp-error? res-sv)
          res-sv)
         ((stage-val? res-sv)
          (let ((p (stage-val-payload res-sv)))
            (stage-normalize-to-residual-anf p)))
         (else
          (stage-normalize-to-residual-anf res-sv)))))
    ((expr env bta-env-or-gfd)
     (if (and (procedure? guest-frame-descriptor?) (guest-frame-descriptor? bta-env-or-gfd))
         (with-guest-frame-descriptor bta-env-or-gfd
           (lambda () (stage-poly-lower expr env)))
         (bta-hybrid-stage-lower expr env bta-env-or-gfd)))
    ((expr env bta-env gfd)
     (if (and (procedure? guest-frame-descriptor?) (guest-frame-descriptor? gfd))
         (with-guest-frame-descriptor gfd
           (lambda () (bta-hybrid-stage-lower expr env bta-env)))
         (bta-hybrid-stage-lower expr env bta-env)))))

;;; -----------------------------------------------------------------------
;;; 8. Triple-Differential Oracle & Metamorphic Evaluation
;;; Conforms to DSN-33-03 §3.6 & §4.4
;;; -----------------------------------------------------------------------

(define (eval-residual-anf-expr expr env)
  (cond
    ((and (pair? expr) (eq? (car expr) '%bta-annotated))
     (eval-residual-anf-expr (caddr expr) env))
    ((number? expr) expr)
    ((boolean? expr) expr)
    ((char? expr) expr)
    ((string? expr) expr)
    ((symbol? expr)
     (let ((b (assq expr env)))
       (if b (cdr b) expr)))
    ((pair? expr)
     (let ((head (car expr)))
       (cond
         ((eq? head 'atom-value)
          (let ((v (cadr expr)))
            (if (and (pair? v) (eq? (car v) 'quote))
                (cadr v)
                (eval-residual-anf-expr v env))))
         ((eq? head 'quote)
          (cadr expr))
         ((eq? head 'let-anf)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (let ((b (car bindings)))
              (let ((var (car b))
                    (val (eval-residual-anf-expr (cadr b) env)))
                (eval-residual-anf-expr body (cons (cons var val) env))))))
         ((eq? head 'let-call)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (let ((b (car bindings)))
              (let ((var (car b))
                    (val (eval-residual-anf-expr (cadr b) env)))
                (eval-residual-anf-expr body (cons (cons var val) env))))))
         ((eq? head 'if)
          (let ((test-val (eval-residual-anf-expr (cadr expr) env)))
            (if test-val
                (eval-residual-anf-expr (caddr expr) env)
                (eval-residual-anf-expr (cadddr expr) env))))
         ((eq? head '+)
          (+ (eval-residual-anf-expr (cadr expr) env)
             (eval-residual-anf-expr (caddr expr) env)))
         ((eq? head '-)
          (- (eval-residual-anf-expr (cadr expr) env)
             (eval-residual-anf-expr (caddr expr) env)))
         ((eq? head '*)
          (* (eval-residual-anf-expr (cadr expr) env)
             (eval-residual-anf-expr (caddr expr) env)))
         ((eq? head '<)
          (< (eval-residual-anf-expr (cadr expr) env)
             (eval-residual-anf-expr (caddr expr) env)))
         ((eq? head '>)
          (> (eval-residual-anf-expr (cadr expr) env)
             (eval-residual-anf-expr (caddr expr) env)))
         ((eq? head '=)
          (= (eval-residual-anf-expr (cadr expr) env)
             (eval-residual-anf-expr (caddr expr) env)))
         ((eq? head 'bitwise-and)
          (ctfe-bitwise-and (eval-residual-anf-expr (cadr expr) env)
                            (eval-residual-anf-expr (caddr expr) env)))
         ((eq? head 'bitwise-ior)
          (ctfe-bitwise-ior (eval-residual-anf-expr (cadr expr) env)
                            (eval-residual-anf-expr (caddr expr) env)))
         ((eq? head 'bitwise-xor)
          (ctfe-bitwise-xor (eval-residual-anf-expr (cadr expr) env)
                            (eval-residual-anf-expr (caddr expr) env)))
         ((eq? head 'arithmetic-shift)
          (ctfe-arithmetic-shift (eval-residual-anf-expr (cadr expr) env)
                                 (eval-residual-anf-expr (caddr expr) env)))
         ((eq? head 'vector-ref)
          (let ((vec (eval-residual-anf-expr (cadr expr) env))
                (idx (eval-residual-anf-expr (caddr expr) env)))
            (if (vector? vec)
                (vector-ref vec idx)
                (list 'vector-ref vec idx))))
         ((eq? head 'local-slot-ref)
          (let ((idx (eval-residual-anf-expr (cadr expr) env)))
            (let ((b (assq idx env)))
              (if b (cdr b) (list 'local-slot-ref idx)))))
         ((eq? head 'guest-pack-fixnum)
          (guest-pack-fixnum (eval-residual-anf-expr (cadr expr) env)))
         ((eq? head 'guest-unpack-fixnum)
          (guest-unpack-fixnum (eval-residual-anf-expr (cadr expr) env)))
         ((eq? head 'guest-fixnum?)
          (guest-fixnum? (eval-residual-anf-expr (cadr expr) env)))
         ((eq? head 'guest-pack-pointer)
          (guest-pack-pointer (eval-residual-anf-expr (cadr expr) env)
                              (eval-residual-anf-expr (caddr expr) env)))
         ((eq? head 'guest-unpack-pointer)
          (guest-unpack-pointer (eval-residual-anf-expr (cadr expr) env)
                                (eval-residual-anf-expr (caddr expr) env)))
         ((eq? head 'guest-pointer-of-tag?)
          (guest-pointer-of-tag? (eval-residual-anf-expr (cadr expr) env)
                                 (eval-residual-anf-expr (caddr expr) env)))
         ((eq? head 'nan-box-int32)
          (nan-box-int32 (eval-residual-anf-expr (cadr expr) env)))
         ((eq? head 'nan-unbox-int32)
          (nan-unbox-int32 (eval-residual-anf-expr (cadr expr) env)))
         ((eq? head 'nan-is-int32?)
          (nan-is-int32? (eval-residual-anf-expr (cadr expr) env)))
         ((eq? head 'nan-box-pointer)
          (nan-box-pointer (eval-residual-anf-expr (cadr expr) env)))
         ((eq? head 'nan-unbox-pointer)
          (nan-unbox-pointer (eval-residual-anf-expr (cadr expr) env)))
         ((eq? head 'nan-is-pointer?)
          (nan-is-pointer? (eval-residual-anf-expr (cadr expr) env)))
         ((eq? head 'nan-box-flonum)
          (nan-box-flonum (eval-residual-anf-expr (cadr expr) env)))
         ((eq? head 'nan-unbox-flonum)
          (nan-unbox-flonum (eval-residual-anf-expr (cadr expr) env)))
         ((eq? head 'nan-is-flonum?)
          (nan-is-flonum? (eval-residual-anf-expr (cadr expr) env)))
         (else
          (let ((b (assq head env)))
            (if b
                (let ((fn (cdr b)))
                  (if (procedure? fn)
                      (let ((arg1 (eval-residual-anf-expr (cadr expr) env))
                            (arg2 (if (pair? (cddr expr)) (eval-residual-anf-expr (caddr expr) env) #f)))
                        (if (pair? (cddr expr))
                            (fn arg1 arg2)
                            (fn arg1)))
                      expr))
                expr))))))
    (else expr)))

(define (run-triple-differential-oracle expr env)
  (let* ((v-now (eval-with-now-oracle-opt expr env *ctfe-default-step-limit* *ctfe-default-depth-limit*))
         (residual-ast (stage-poly-lower expr env))
         (v-residual (eval-residual-anf-expr residual-ast env)))
    (list (equal? v-now v-residual) v-now v-residual residual-ast)))

;;; -----------------------------------------------------------------------
;;; 9. Stage-Poly Lowering Pass Integration (DSN-33-03 §2.6, §8.1 & Issue #887)
;;; -----------------------------------------------------------------------

(define (stage-meta-syntax-tag? sym)
  (and (symbol? sym)
       (or (eq? sym 'stage-now)
           (eq? sym 'stage-later)
           (eq? sym 'stage-lift)
           (eq? sym 'stage-quasiquote)
           (eq? sym 'stage-splice)
           (eq? sym 'stage-run))
       (let ((s (symbol->raw-name sym)))
         (or (string=? s "stage-now")
             (string=? s "stage-later")
             (string=? s "stage-lift")
             (string=? s "stage-quasiquote")
             (string=? s "stage-splice")
             (string=? s "stage-run")))))

(define (contains-stage-meta-syntax? form)
  (cond
    ((not (pair? form)) #f)
    ((eq? (car form) 'quote) #f)
    ((stage-meta-syntax-tag? (car form)) #t)
    (else
     (or (contains-stage-meta-syntax? (car form))
         (contains-stage-meta-syntax? (cdr form))))))

(define (stage-poly-lower-body body)
  (if (null? body)
      '()
      (cons (if (contains-stage-meta-syntax? (car body))
                (stage-poly-lower (car body) '())
                (car body))
            (stage-poly-lower-body (cdr body)))))

(define (stage-poly-lower-form form)
  (cond
    ((not (pair? form)) form)
    ((and (eq? (car form) 'define) (pair? (cdr form)))
     (let ((target (cadr form)))
       (if (symbol? target)
           (if (pair? (cddr form))
               (if (contains-stage-meta-syntax? (caddr form))
                   (list 'define target (stage-poly-lower (caddr form) '()))
                   form)
               form)
           (if (contains-stage-meta-syntax? (cddr form))
               (cons 'define (cons target (stage-poly-lower-body (cddr form))))
               form))))
    ((contains-stage-meta-syntax? form)
     (stage-poly-lower form '()))
    (else form)))

(define (stage-poly-lower-all form-or-forms)
  (cond
    ((null? form-or-forms) '())
    ((not (pair? form-or-forms))
     (stage-poly-lower-form form-or-forms))
    ((eq? (car form-or-forms) '%program)
     (let ((defs (cadr form-or-forms))
           (main (caddr form-or-forms)))
       (list '%program
             (let loop ((ds defs))
               (if (null? ds)
                   '()
                   (cons (stage-poly-lower-form (car ds))
                         (loop (cdr ds)))))
             (stage-poly-lower-form main))))
    ((eq? (car form-or-forms) 'define)
     (stage-poly-lower-form form-or-forms))
    (else
     (let loop ((fs form-or-forms))
       (if (null? fs)
           '()
           (cons (stage-poly-lower-form (car fs))
                 (loop (cdr fs))))))))
