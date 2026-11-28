;;; =======================================================================
;;; ULisp Compiler Pass 4b: S-Annotator (Abstract Interpretation Type Inference)
;;; Conforms to DSN-33 Architecture Specification & Issue #517
;;; Note: Performs abstract interpretation on ANF-normalized Scheme AST.
;;;       Infers types and range intervals using a monotone lattice (LUB),
;;;       populates type annotations, and supports R-Scheme type checking.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Type Lattice Constructors & Predicates
;;; -----------------------------------------------------------------------

(define (type-bot) 'bot)
(define (type-top) 'top)
(define (type-fixnum) 'fixnum)
(define (type-fixnum-range min-val max-val) (list 'fixnum min-val max-val))
(define (type-boolean) 'boolean)
(define (type-pair car-t cdr-t) (list 'pair car-t cdr-t))
(define (type-null) 'null)
(define (type-string) 'string)
(define (type-symbol) 'symbol)
(define (type-char) 'char)
(define (type-closure id arg-types ret-type) (list 'closure id arg-types ret-type))

(define (type-bot? t) (eq? t 'bot))
(define (type-top? t) (eq? t 'top))
(define (type-fixnum? t)
  (or (eq? t 'fixnum)
      (and (pair? t) (eq? (car t) 'fixnum))))
(define (type-has-range? t)
  (and (pair? t) (eq? (car t) 'fixnum) (= (length t) 3)))
(define (type-range-min t) (cadr t))
(define (type-range-max t) (caddr t))

(define (type-boolean? t) (eq? t 'boolean))
(define (type-pair? t) (and (pair? t) (eq? (car t) 'pair)))
(define (type-pair-car t) (if (type-pair? t) (cadr t) (type-top)))
(define (type-pair-cdr t) (if (type-pair? t) (caddr t) (type-top)))

(define (type-null? t) (eq? t 'null))
(define (type-string? t) (eq? t 'string))
(define (type-symbol? t) (eq? t 'symbol))
(define (type-char? t) (eq? t 'char))
(define (type-closure? t) (and (pair? t) (eq? (car t) 'closure)))

(define (temp-var? sym)
  (and (symbol? sym)
       (let ((str (symbol->string sym)))
         (and (> (string-length str) 1)
              (char=? (string-ref str 0) #\%)
              (char=? (string-ref str 1) #\t)))))

;;; -----------------------------------------------------------------------
;;; 2. Lattice Join (Least Upper Bound: LUB, \sqcup) & Meet (GLB, \sqcap)
;;; -----------------------------------------------------------------------

(define (type-equal? t1 t2)
  (cond
    ((and (symbol? t1) (symbol? t2)) (eq? t1 t2))
    ((and (number? t1) (number? t2)) (= t1 t2))
    ((and (boolean? t1) (boolean? t2)) (eq? t1 t2))
    ((and (null? t1) (null? t2)) #t)
    ((and (pair? t1) (pair? t2))
     (and (type-equal? (car t1) (car t2))
          (type-equal? (cdr t1) (cdr t2))))
    (else (eq? t1 t2))))

(define (type-lub t1 t2)
  (cond
    ((type-bot? t1) t2)
    ((type-bot? t2) t1)
    ((type-top? t1) (type-top))
    ((type-top? t2) (type-top))
    ((type-equal? t1 t2) t1)
    ;; Range & Fixnum unification
    ((and (type-fixnum? t1) (type-fixnum? t2))
     (if (and (type-has-range? t1) (type-has-range? t2))
         (let ((min1 (type-range-min t1))
               (max1 (type-range-max t1))
               (min2 (type-range-min t2))
               (max2 (type-range-max t2)))
           (type-fixnum-range (if (< min1 min2) min1 min2)
                              (if (> max1 max2) max1 max2)))
         (type-fixnum)))
    ;; Pair unification
    ((and (type-pair? t1) (type-pair? t2))
     (type-pair (type-lub (type-pair-car t1) (type-pair-car t2))
                (type-lub (type-pair-cdr t1) (type-pair-cdr t2))))
    ;; List-like: Pair and Null join to Pair(top, top) or Top
    ((and (or (type-pair? t1) (type-null? t1))
          (or (type-pair? t2) (type-null? t2)))
     (type-top))
    ;; Closure unification: preserve identity & merge return types when identical
    ((and (type-closure? t1) (type-closure? t2))
     (if (eq? (cadr t1) (cadr t2))
         (type-closure (cadr t1) (caddr t1) (type-lub (cadddr t1) (cadddr t2)))
         (type-top)))
    ;; Disjoint types join to Top (dynamic / any)
    (else (type-top))))

(define (type-meet t1 t2)
  (cond
    ((type-bot? t1) (type-bot))
    ((type-bot? t2) (type-bot))
    ((type-top? t1) t2)
    ((type-top? t2) t1)
    ((type-equal? t1 t2) t1)
    ;; Range & Fixnum meet
    ((and (type-fixnum? t1) (type-fixnum? t2))
     (cond
       ((and (type-has-range? t1) (type-has-range? t2))
        (let* ((min1 (type-range-min t1))
               (max1 (type-range-max t1))
               (min2 (type-range-min t2))
               (max2 (type-range-max t2))
               (new-min (if (> min1 min2) min1 min2))
               (new-max (if (< max1 max2) max1 max2)))
          (if (> new-min new-max)
              (type-bot)
              (type-fixnum-range new-min new-max))))
       ((type-has-range? t1) t1)
       ((type-has-range? t2) t2)
       (else (type-fixnum))))
    ;; Pair meet
    ((and (type-pair? t1) (type-pair? t2))
     (let ((car-m (type-meet (type-pair-car t1) (type-pair-car t2)))
           (cdr-m (type-meet (type-pair-cdr t1) (type-pair-cdr t2))))
       (if (or (type-bot? car-m) (type-bot? cdr-m))
           (type-bot)
           (type-pair car-m cdr-m))))
    ;; Disjoint types meet to Bottom
    (else (type-bot))))

;;; -----------------------------------------------------------------------
;;; 3. Type Environment Management & Predicate Extraction
;;; -----------------------------------------------------------------------

(define (type-env-lookup var env)
  (let ((entry (assq var env)))
    (if entry
        (cdr entry)
        (type-top))))

(define (type-env-lookup-fact var env)
  (let loop ((rest env))
    (cond
      ((null? rest) #f)
      ((and (pair? (car rest))
            (pair? (caar rest))
            (eq? (car (caar rest)) '%fact)
            (eq? (cdr (caar rest)) var))
       (cdar rest))
      (else (loop (cdr rest))))))

(define (type-env-extend var type env)
  (cons (cons var type) env))

(define (type-env-extend-with-fact var type fact env)
  (cons (cons (cons '%fact var) fact)
        (cons (cons var type) env)))

(define (type-env-extend-multi vars types env)
  (if (or (null? vars) (null? types))
      env
      (cons (cons (car vars) (car types))
            (type-env-extend-multi (cdr vars) (cdr types) env))))

(define (type-env-merge env1 env2)
  (let loop ((rest env1) (acc '()))
    (if (null? rest)
        acc
        (let* ((var (caar rest))
               (t1 (type-env-lookup var env1))
               (t2 (type-env-lookup var env2)))
          (loop (cdr rest) (cons (cons var (type-lub t1 t2)) acc))))))

(define (predicate-op? op)
  (memq op '(fixnum? integer? number? pair? boolean? null? symbol? string? char? procedure? zero? = < <= > >= not)))

(define (extract-predicate-narrowing test env)
  (cond
    ;; Variable lookup: check if variable was bound to a predicate fact in ANF let
    ((symbol? test)
     (let ((fact (type-env-lookup-fact test env)))
       (if fact
           (extract-predicate-narrowing fact env)
           (cons #f #f))))
    ((not (pair? test))
     (cons #f #f))
    (else
     (let ((op (car test)))
       (cond
         ((memq op '(fixnum? integer? number?))
          (if (and (pair? (cdr test)) (symbol? (cadr test)))
              (let ((var (cadr test)))
                (cons (cons var (type-fixnum))
                      (cons var (if (type-fixnum? (type-env-lookup var env)) (type-bot) (type-env-lookup var env)))))
              (cons #f #f)))
         ((eq? op 'pair?)
          (if (and (pair? (cdr test)) (symbol? (cadr test)))
              (let ((var (cadr test)))
                (cons (cons var (type-pair (type-top) (type-top)))
                      (cons var (if (type-pair? (type-env-lookup var env)) (type-bot) (type-env-lookup var env)))))
              (cons #f #f)))
         ((eq? op 'boolean?)
          (if (and (pair? (cdr test)) (symbol? (cadr test)))
              (let ((var (cadr test)))
                (cons (cons var (type-boolean))
                      (cons var (if (type-boolean? (type-env-lookup var env)) (type-bot) (type-env-lookup var env)))))
              (cons #f #f)))
         ((eq? op 'null?)
          (if (and (pair? (cdr test)) (symbol? (cadr test)))
              (let ((var (cadr test)))
                (cons (cons var (type-null))
                      (cons var (if (type-null? (type-env-lookup var env)) (type-bot) (type-env-lookup var env)))))
              (cons #f #f)))
         ((eq? op 'symbol?)
          (if (and (pair? (cdr test)) (symbol? (cadr test)))
              (let ((var (cadr test)))
                (cons (cons var (type-symbol))
                      (cons var (if (type-symbol? (type-env-lookup var env)) (type-bot) (type-env-lookup var env)))))
              (cons #f #f)))
         ((eq? op 'string?)
          (if (and (pair? (cdr test)) (symbol? (cadr test)))
              (let ((var (cadr test)))
                (cons (cons var (type-string))
                      (cons var (if (type-string? (type-env-lookup var env)) (type-bot) (type-env-lookup var env)))))
              (cons #f #f)))
         ((eq? op 'char?)
          (if (and (pair? (cdr test)) (symbol? (cadr test)))
              (let ((var (cadr test)))
                (cons (cons var (type-char))
                      (cons var (if (type-char? (type-env-lookup var env)) (type-bot) (type-env-lookup var env)))))
              (cons #f #f)))
         ((eq? op 'procedure?)
          (if (and (pair? (cdr test)) (symbol? (cadr test)))
              (let ((var (cadr test)))
                (cons (cons var (type-closure 'any '() (type-top)))
                      (cons var (type-env-lookup var env))))
              (cons #f #f)))
         ((eq? op 'zero?)
          (if (and (pair? (cdr test)) (symbol? (cadr test)))
              (let ((var (cadr test)))
                (cons (cons var (type-fixnum-range 0 0))
                      (cons var (type-env-lookup var env))))
              (cons #f #f)))
         ((eq? op '=)
          (cond
            ((and (pair? (cdr test)) (pair? (cddr test))
                  (symbol? (cadr test)) (number? (caddr test)))
             (let ((var (cadr test)) (n (caddr test)))
               (cons (cons var (type-fixnum-range n n))
                     (cons var (type-env-lookup var env)))))
            ((and (pair? (cdr test)) (pair? (cddr test))
                  (number? (cadr test)) (symbol? (caddr test)))
             (let ((var (caddr test)) (n (cadr test)))
               (cons (cons var (type-fixnum-range n n))
                     (cons var (type-env-lookup var env)))))
            (else (cons #f #f))))
         ((eq? op 'not)
          (if (pair? (cdr test))
              (let ((sub (extract-predicate-narrowing (cadr test) env)))
                (cons (cdr sub) (car sub)))
              (cons #f #f)))
         (else (cons #f #f)))))))

(define (narrow-var-in-branch var test branch-then? env)
  (let* ((narrowing (extract-predicate-narrowing test env))
         (info (if branch-then? (car narrowing) (cdr narrowing))))
    (if (and (pair? info) (eq? (car info) var))
        (type-meet (type-env-lookup var env) (cdr info))
        (type-env-lookup var env))))

;;; Global Type Tables for Whole-Program Traceability (256-slot hash buckets)
(define *annotator-bucket-count* 256)
(define *global-type-env* (make-vector 256 '()))
(define *expr-type-table* (make-vector 256 '()))

(define (annotator-bucket-idx sym)
  (modulo (symbol->hash-idx sym) *annotator-bucket-count*))

(define (reset-type-annotations!)
  (let loop ((i 0))
    (if (< i *annotator-bucket-count*)
        (begin
          (vector-set! *global-type-env* i '())
          (vector-set! *expr-type-table* i '())
          (loop (+ i 1)))))
  (reset-cfa-state!))

(define (record-var-type! var type)
  (let ((idx (annotator-bucket-idx var)))
    (vector-set! *global-type-env* idx
                 (cons (cons var type) (vector-ref *global-type-env* idx)))))

(define (get-var-type var)
  (type-env-lookup var (vector-ref *global-type-env* (annotator-bucket-idx var))))

(define (record-expr-type! expr-id type)
  (let ((idx (annotator-bucket-idx expr-id)))
    (vector-set! *expr-type-table* idx
                 (cons (cons expr-id type) (vector-ref *expr-type-table* idx)))))

(define (get-expr-type expr-id)
  (type-env-lookup expr-id (vector-ref *expr-type-table* (annotator-bucket-idx expr-id))))

;;; -----------------------------------------------------------------------
;;; 4. Abstract Evaluation Engine for ANF Expressions
;;; -----------------------------------------------------------------------

;;; Arithmetic abstract transfer functions
(define (abstract-eval-arith op t1 t2)
  (if (and (type-fixnum? t1) (type-fixnum? t2))
      (if (and (type-has-range? t1) (type-has-range? t2))
          (let ((min1 (type-range-min t1))
                (max1 (type-range-max t1))
                (min2 (type-range-min t2))
                (max2 (type-range-max t2)))
            (if (and (integer? min1) (<= min1 536870911) (>= min1 -536870911)
                     (integer? max1) (<= max1 536870911) (>= max1 -536870911)
                     (integer? min2) (<= min2 536870911) (>= min2 -536870911)
                     (integer? max2) (<= max2 536870911) (>= max2 -536870911))
                (case op
                  ((+) (type-fixnum-range (+ min1 min2) (+ max1 max2)))
                  ((-) (type-fixnum-range (- min1 max2) (- max1 min2)))
                  ((*) (type-fixnum))
                  (else (type-fixnum)))
                (type-fixnum)))
          (type-fixnum))
      (type-fixnum)))

;;; Primitive procedure abstract evaluation
(define (abstract-eval-prim op arg-types)
  (cond
    ;; Arithmetic
    ((memq op '(+ - * modulo quotient / bitwise-and bitwise-ior bitwise-arithmetic-shift))
     (let ((t1 (if (pair? arg-types) (car arg-types) (type-top)))
           (t2 (if (and (pair? arg-types) (pair? (cdr arg-types))) (cadr arg-types) (type-top))))
       (abstract-eval-arith op t1 t2)))
    ((memq op '(fxadd1 fxsub1 %to-raw %to-fixnum))
     (type-fixnum))
    ;; Predicates -> Boolean
    ((memq op '(= < <= > >= eq? eqv? char=? boolean=? symbol=? zero? fixnum? integer? number? exact? exact-integer? inexact? real? rational? complex? boolean? char? null? not symbol? pair? procedure? string? list? eof-object?))
     (type-boolean))
    ;; Data structure primitives
    ((eq? op 'cons)
     (let ((t1 (if (pair? arg-types) (car arg-types) (type-top)))
           (t2 (if (and (pair? arg-types) (pair? (cdr arg-types))) (cadr arg-types) (type-top))))
       (type-pair t1 t2)))
    ((eq? op 'car)
     (let ((t (if (pair? arg-types) (car arg-types) (type-top))))
       (type-pair-car t)))
    ((eq? op 'cdr)
     (let ((t (if (pair? arg-types) (car arg-types) (type-top))))
       (type-pair-cdr t)))
    ((memq op '(string-length bytevector-length bytevector-u8-ref vector-length %num-args))
     (type-fixnum))
    ((memq op '(bytevector? vector?))
     (type-boolean))
    ((memq op '(make-string string-ref))
     (if (eq? op 'make-string) (type-string) (type-char)))
    ((memq op '(%get-rsp %get-heap-ptr %get-gc-state-ptr %get-safepoint-flag-ptr %get-environ-ptr %get-symtab-bounds %get-initial-heap-ptr %get-initial-heap sys-initial-heap %raw-load %raw-load-u8 %ptr-add %ptr-tag-add))
     (type-fixnum))
    (else (type-top))))

;;; Abstract evaluation of arbitrary ANF expression
(define (abstract-eval-expr expr env)
  (cond
    ;; Integer literal
    ((number? expr)
     (type-fixnum-range expr expr))
    ;; Boolean literal
    ((boolean? expr)
     (type-boolean))
    ;; Char literal
    ((char? expr)
     (type-char))
    ;; String literal
    ((string? expr)
     (type-string))
    ;; Null literal
    ((null? expr)
     (type-null))
    ;; Symbol lookup
    ((symbol? expr)
     (type-env-lookup expr env))
    ;; Quoted constant
    ((and (pair? expr) (eq? (car expr) 'quote))
     (let ((datum (cadr expr)))
       (cond
         ((number? datum) (type-fixnum-range datum datum))
         ((boolean? datum) (type-boolean))
         ((char? datum) (type-char))
         ((string? datum) (type-string))
         ((null? datum) (type-null))
         ((symbol? datum) (type-symbol))
         ((pair? datum) (type-pair (type-top) (type-top)))
         (else (type-top)))))
    ;; Compound ANF forms
    ((pair? expr)
     (let ((op (car expr)))
       (case op
         ;; Conditional branching with flow-sensitive narrowing
         ((if)
          (let* ((test-expr (cadr expr))
                 (narrowing (extract-predicate-narrowing test-expr env))
                 (then-narrow (car narrowing))
                 (else-narrow (cdr narrowing))
                 (then-env (if (pair? then-narrow)
                               (let* ((var (car then-narrow))
                                      (curr-t (type-env-lookup var env))
                                      (new-t (type-meet curr-t (cdr then-narrow))))
                                 (type-env-extend var new-t env))
                               env))
                 (else-env (if (pair? else-narrow)
                               (let* ((var (car else-narrow))
                                      (curr-t (type-env-lookup var env))
                                      (new-t (type-meet curr-t (cdr else-narrow))))
                                 (type-env-extend var new-t env))
                               env))
                 (then-t (abstract-eval-expr (caddr expr) then-env))
                 (else-t (if (null? (cdddr expr))
                             (type-boolean)
                             (abstract-eval-expr (cadddr expr) else-env))))
            (type-lub then-t else-t)))
         ;; Sequential execution
         ((begin)
          (let loop ((rest (cdr expr)) (last-t (type-top)))
            (if (null? rest)
                last-t
                (loop (cdr rest) (abstract-eval-expr (car rest) env)))))
         ;; Local let bindings
         ((let)
          (if (symbol? (cadr expr))
              ;; Named let (loop): Fixpoint iteration
              (abstract-eval-named-let (cadr expr) (caddr expr) (cdddr expr) env)
              ;; Standard let
              (let* ((bindings (cadr expr))
                     (body (cddr expr))
                     (new-env (let bind-loop ((bs bindings) (e env))
                                (if (null? bs)
                                    e
                                    (let* ((b (car bs))
                                           (var (car b))
                                           (rhs (cadr b))
                                           (val-t (abstract-eval-expr rhs env))
                                           (fact (if (and (pair? rhs) (predicate-op? (car rhs)))
                                                     rhs
                                                     #f)))
                                      (if (not (temp-var? var))
                                          (record-var-type! var val-t))
                                      (bind-loop (cdr bs)
                                                 (if fact
                                                     (type-env-extend-with-fact var val-t fact e)
                                                     (type-env-extend var val-t e))))))))
                (let body-loop ((rest body) (last-t (type-top)))
                  (if (null? rest)
                      last-t
                      (body-loop (cdr rest) (abstract-eval-expr (car rest) new-env)))))))
         ;; Mutual recursion (letrec)
         ((letrec)
          (let* ((bindings (cadr expr))
                 (body-expr (if (null? (cddr expr)) #f (caddr expr)))
                 (init-call-args
                  (if (and (= (length bindings) 1)
                           (let* ((b (car bindings))
                                  (val (cadr b)))
                             (and (pair? val) (eq? (car val) 'lambda))))
                      (extract-initial-call-args (caar bindings) body-expr)
                      #f)))
            (if (and init-call-args
                     (let* ((b (car bindings))
                            (val (cadr b))
                            (params (cadr val)))
                       (and (= (length init-call-args) (length params))
                            (let check-nums ((is init-call-args) (has-num? #f))
                              (if (null? is)
                                  has-num?
                                  (let ((arg-t (abstract-eval-expr (car is) env)))
                                    (cond
                                      ((or (number? (car is)) (type-fixnum? arg-t))
                                       (check-nums (cdr is) #t))
                                      ((type-closure? arg-t)
                                       (check-nums (cdr is) has-num?))
                                      (else #f))))))))
                ;; Desugared named-let loop or single recursive numeric function
                (let* ((b (car bindings))
                       (fn-name (car b))
                       (fn-val (cadr b))
                       (params (cadr fn-val))
                       (lbodies (cddr fn-val))
                       (inits init-call-args)
                       (named-bindings (let make-bs ((ps params) (is inits) (acc '()))
                                         (if (or (null? ps) (null? is))
                                             (reverse acc)
                                             (make-bs (cdr ps) (cdr is) (cons (list (car ps) (car is)) acc)))))
                       (fn-ret-t (abstract-eval-named-let fn-name named-bindings lbodies env)))
                  (if (and (pair? body-expr) (eq? (car body-expr) fn-name))
                      fn-ret-t
                      (let ((ext-env (type-env-extend fn-name (type-closure fn-name params fn-ret-t) env))
                            (body (cddr expr)))
                        (let body-loop ((rest body) (last-t (type-top)))
                          (if (null? rest)
                              last-t
                              (body-loop (cdr rest) (abstract-eval-expr (car rest) ext-env)))))))
                ;; General letrec
                (let* ((body (cddr expr))
                       (new-env (let bind-loop ((bs bindings) (e env))
                                  (if (null? bs)
                                      e
                                      (let ((var (caar bs)))
                                        (bind-loop (cdr bs) (type-env-extend var (type-top) e)))))))
                  (let body-loop ((rest body) (last-t (type-top)))
                    (if (null? rest)
                        last-t
                        (body-loop (cdr rest) (abstract-eval-expr (car rest) new-env))))))))
         ;; Lambda abstraction
         ((lambda)
          (let ((params (cadr expr)))
            (type-closure (unique-label-sym "lam") params (type-top))))
         ((%with-handler %call-with-values %values %raw-call/cc)
          (type-top))
         ;; Procedure call or primitive
         (else
          (let ((arg-types (map (lambda (a) (abstract-eval-expr a env)) (cdr expr))))
            (if (or (unary-prim? op) (binop-prim? op) (triop-prim? op) (zero-arg-prim? op) (septop-prim? op))
                (abstract-eval-prim op arg-types)
                (let ((fn-t (abstract-eval-expr op env)))
                  (if (type-closure? fn-t)
                      (cadddr fn-t)
                      (type-top)))))))))
    (else (type-top))))

;;; -----------------------------------------------------------------------
;;; 5. Named-let & Loop Fixpoint Iteration
;;; -----------------------------------------------------------------------

(define (extract-initial-call-args fn-name expr)
  (cond
    ((not (pair? expr)) #f)
    ((eq? (car expr) fn-name) (cdr expr))
    ((eq? (car expr) 'let)
     (let ((bindings (cadr expr))
           (body (if (pair? (cddr expr)) (caddr expr) #f)))
       (let loop ((bs bindings))
         (if (null? bs)
             (extract-initial-call-args fn-name body)
             (let ((res (extract-initial-call-args fn-name (cadar bs))))
               (if res res (loop (cdr bs))))))))
    ((eq? (car expr) 'begin)
     (let loop ((es (cdr expr)))
       (if (null? es) #f
           (let ((res (extract-initial-call-args fn-name (car es))))
             (if res res (loop (cdr es)))))))
    (else #f)))

(define (abstract-eval-named-let loop-name bindings body env)
  (let* ((vars (map car* bindings))
         (init-types (map (lambda (b) (abstract-eval-expr (cadr b) env)) bindings)))
    ;; Iterative fixpoint loop up to 5 steps
    (let fixpoint-loop ((step 0)
                        (current-arg-types init-types)
                        (current-ret-type (type-bot)))
      (let* ((loop-closure (type-closure loop-name vars current-ret-type))
             (loop-env (type-env-extend loop-name loop-closure
                                        (type-env-extend-multi vars current-arg-types env)))
             ;; Evaluate body expressions under loop-env
             (body-type (let eval-body ((rest body) (last-t (type-bot)))
                          (if (null? rest)
                              last-t
                              (eval-body (cdr rest) (abstract-eval-expr (car rest) loop-env)))))
             (next-ret-type (type-lub current-ret-type body-type)))
        (if (or (>= step 4)
                (type-equal? next-ret-type current-ret-type))
            ;; Fixpoint reached or widened
            (begin
              (let rec-rec ((vs vars) (ts current-arg-types))
                (if (and (pair? vs) (pair? ts))
                    (begin
                      (record-var-type! (car vs) (car ts))
                      (rec-rec (cdr vs) (cdr ts)))))
              (if (type-bot? next-ret-type) (type-top) next-ret-type))
            ;; Continue fixpoint iteration
            (fixpoint-loop (+ step 1) current-arg-types next-ret-type))))))

;;; -----------------------------------------------------------------------
;;; 6. Whole-Form Annotation Driver Pass
;;; -----------------------------------------------------------------------

(define (annotate-form form)
  (cond
    ((and (pair? form) (eq? (car form) 'define))
     (let ((head (cadr form))
           (body (cddr form)))
       (if (pair? head)
           ;; (define (name args...) body...)
           (let* ((fn-name (car head))
                  (params (cdr head))
                  (param-types (map (lambda (p) (type-top)) params))
                  (fn-env (type-env-extend-multi params param-types '()))
                  (ret-type (let eval-b ((rest body) (last-t (type-top)))
                              (if (null? rest)
                                  last-t
                                  (eval-b (cdr rest) (abstract-eval-expr (car rest) fn-env))))))
             (record-var-type! fn-name (type-closure fn-name params ret-type))
             form)
           ;; (define name val)
           (let* ((var head)
                  (val-t (abstract-eval-expr (car body) '())))
             (record-var-type! var val-t)
             form))))
    (else
     (abstract-eval-expr form '())
     form)))

;;; -----------------------------------------------------------------------
;;; 7. Whole-Program 0-CFA Closure Flow & HOF Monomorphization (Issue #972)
;;; -----------------------------------------------------------------------

(define *cfa-bot* '())
(define *cfa-top* '*cfa-top*)
(define *cfa-max-closure-set* 4)
(define *cfa-max-solver-iters* 8)
(define *cfa-max-clones-per-fn* 4)
(define *cfa-max-total-clones* 32)
(define *cfa-max-inline-body-cost* 48)
(define *cfa-bucket-count* 256)

(define *cfa-lambda-table* (make-vector 256 '()))
(define *cfa-var-closures* (make-vector 256 '()))
(define *cfa-lam-returns* (make-vector 256 '()))
(define *cfa-singleton-targets* (make-vector 256 '()))
(define *cfa-expr-lam-ids* (cons '() '()))
(define *cfa-mutated-vars* (cons '() '()))

(define (cfa-bucket-idx sym)
  (modulo (symbol->hash-idx sym) *cfa-bucket-count*))

(define (reset-cfa-state!)
  (set-car! *cfa-expr-lam-ids* '())
  (set-car! *cfa-mutated-vars* '())
  (let loop ((i 0))
    (if (< i *cfa-bucket-count*)
        (begin
          (vector-set! *cfa-lambda-table* i '())
          (vector-set! *cfa-var-closures* i '())
          (vector-set! *cfa-lam-returns* i '())
          (vector-set! *cfa-singleton-targets* i '())
          (loop (+ i 1))))))

(define (cfa-top? s) (eq? s *cfa-top*))
(define (cfa-bot? s) (null? s))

(define (cfa-memq-list? x lst)
  (and (pair? lst) (if (eq? (car lst) x) #t (cfa-memq-list? x (cdr lst)))))

(define (cfa-join s1 s2)
  (cond
    ((or (cfa-top? s1) (cfa-top? s2)) *cfa-top*)
    ((null? s1) s2)
    ((null? s2) s1)
    (else
     (let loop ((rem s2) (acc s1) (len (length s1)))
       (cond
         ((> len *cfa-max-closure-set*) *cfa-top*)
         ((null? rem) acc)
         ((cfa-memq-list? (car rem) acc)
          (loop (cdr rem) acc len))
         ((>= len *cfa-max-closure-set*) *cfa-top*)
         (else
          (loop (cdr rem) (cons (car rem) acc) (+ len 1))))))))

(define (cfa-set-equal? s1 s2)
  (cond
    ((cfa-top? s1) (cfa-top? s2))
    ((cfa-top? s2) #f)
    ((not (= (length s1) (length s2))) #f)
    (else
     (let loop ((rem s1))
       (cond
         ((null? rem) #t)
         ((cfa-memq-list? (car rem) s2) (loop (cdr rem)))
         (else #f))))))

;; Lambda record: (list lam-id owner-sym params body frees arity unsafe? cost)
(define (register-cfa-lambda! lam-id owner-sym params body frees arity unsafe? cost)
  (let ((idx (cfa-bucket-idx lam-id))
        (info (list lam-id owner-sym params body frees arity unsafe? cost)))
    (vector-set! *cfa-lambda-table* idx
                 (cons (cons lam-id info) (vector-ref *cfa-lambda-table* idx)))
    info))

(define (get-cfa-lambda-info lam-id)
  (if (symbol? lam-id)
      (let ((e (assq lam-id (vector-ref *cfa-lambda-table* (cfa-bucket-idx lam-id)))))
        (if e (cdr e) #f))
      #f))

(define (cfa-lam-id info) (car info))
(define (cfa-lam-owner info) (cadr info))
(define (cfa-lam-params info) (caddr info))
(define (cfa-lam-body info) (cadddr info))
(define (cfa-lam-frees info) (car (cddddr info)))
(define (cfa-lam-arity info) (cadr (cddddr info)))
(define (cfa-lam-unsafe? info) (caddr (cddddr info)))
(define (cfa-lam-cost info) (cadddr (cddddr info)))

(define (get-cfa-closure-set var)
  (let ((e (assq var (vector-ref *cfa-var-closures* (cfa-bucket-idx var)))))
    (if e (cdr e) *cfa-bot*)))

(define (record-cfa-closure-set! var cset)
  (let* ((idx (cfa-bucket-idx var))
         (bucket (vector-ref *cfa-var-closures* idx))
         (e (assq var bucket)))
    (if e
        (set-cdr! e cset)
        (vector-set! *cfa-var-closures* idx (cons (cons var cset) bucket)))))

(define (join-cfa-var-set! var incoming changed-box)
  (let* ((eff (if (memq var (car *cfa-mutated-vars*)) *cfa-top* incoming))
         (cur (get-cfa-closure-set var))
         (joined (cfa-join cur eff)))
    (if (not (cfa-set-equal? cur joined))
        (begin
          (record-cfa-closure-set! var joined)
          (set-car! changed-box #t)))
    joined))

(define (record-cfa-singleton-target! var lam-id)
  (let* ((idx (cfa-bucket-idx var))
         (bucket (vector-ref *cfa-singleton-targets* idx))
         (e (assq var bucket)))
    (if e
        (set-cdr! e lam-id)
        (vector-set! *cfa-singleton-targets* idx (cons (cons var lam-id) bucket)))))

(define (get-cfa-singleton-target var)
  (if (symbol? var)
      (let ((e (assq var (vector-ref *cfa-singleton-targets* (cfa-bucket-idx var)))))
        (if e (cdr e) #f))
      #f))

(define (cfa-record-bound-var! name seen-box dup-box)
  (if (symbol? name)
      (if (memq name (car seen-box))
          (if (not (memq name (car dup-box)))
              (set-car! dup-box (cons name (car dup-box))))
          (set-car! seen-box (cons name (car seen-box))))))

(define (cfa-collect-mutated-and-dups expr seen-defs dup-defs seen-all dup-all)
  (cond
    ((not (pair? expr)) #f)
    ((or (eq? (car expr) 'quote) (eq? (car expr) 'declare)) #f)
    ((and (eq? (car expr) 'define) (pair? (cdr expr)))
     (let ((name (if (pair? (cadr expr)) (caadr expr) (cadr expr))))
       (cfa-record-bound-var! name seen-defs dup-defs)
       (cfa-record-bound-var! name seen-all dup-all)
       (if (pair? (cadr expr))
           (for-each (lambda (p) (cfa-record-bound-var! p seen-all dup-all))
                     (cp0-lambda-formal-syms (cdr (cadr expr)))))
       (cfa-collect-mutated-and-dups (cddr expr) seen-defs dup-defs seen-all dup-all)))
    ((and (memq (car expr) '(let letrec)) (pair? (cdr expr)) (list? (cadr expr)))
     (for-each
       (lambda (b)
         (if (pair? b)
             (begin
               (cfa-record-bound-var! (car b) seen-all dup-all)
               (if (pair? (cdr b))
                   (cfa-collect-mutated-and-dups (cadr b) seen-defs dup-defs seen-all dup-all)))))
       (cadr expr))
     (cfa-collect-mutated-and-dups (cddr expr) seen-defs dup-defs seen-all dup-all))
    ((and (eq? (car expr) 'lambda) (pair? (cdr expr)))
     (for-each (lambda (p) (cfa-record-bound-var! p seen-all dup-all))
               (cp0-lambda-formal-syms (cadr expr)))
     (cfa-collect-mutated-and-dups (cddr expr) seen-defs dup-defs seen-all dup-all))
    ((and (eq? (car expr) 'set!) (pair? (cdr expr)) (symbol? (cadr expr)))
     (if (not (memq (cadr expr) (car *cfa-mutated-vars*)))
         (set-car! *cfa-mutated-vars* (cons (cadr expr) (car *cfa-mutated-vars*))))
     (if (pair? (cddr expr))
         (cfa-collect-mutated-and-dups (caddr expr) seen-defs dup-defs seen-all dup-all)))
    (else
     (cfa-collect-mutated-and-dups (car expr) seen-defs dup-defs seen-all dup-all)
     (cfa-collect-mutated-and-dups (cdr expr) seen-defs dup-defs seen-all dup-all))))

(define (cfa-lookup-expr-lam-id lam-expr)
  (let ((e (assq lam-expr (car *cfa-expr-lam-ids*))))
    (if e (cdr e) #f)))

(define (cfa-extract-lambda-body expr)
  (cond
    ((not (pair? expr)) #f)
    ((and (eq? (car expr) 'lambda) (pair? (cdr expr)) (pair? (cddr expr)))
     (if (null? (cdddr expr))
         (caddr expr)
         (cons 'begin (cddr expr))))
    (else #f)))

(define (cfa-strip-leading-safepoint expr caller-body)
  (if (and (pair? expr)
           (eq? (car expr) 'begin)
           (pair? (cdr expr))
           (pair? (cadr expr))
           (memq (caadr expr) '(%synapse-safepoint-poll! %safepoint-poll!))
           (pair? (cddr expr))
           (or (occurs-in? '%synapse-safepoint-poll! caller-body)
               (occurs-in? '%safepoint-poll! caller-body)))
      (if (null? (cdddr expr))
          (caddr expr)
          (cons 'begin (cddr expr)))
      expr))

(define (cfa-expr-has-unsafe-op? expr)
  (cond
    ((symbol? expr)
     (if (memq expr '(%synapse-safepoint-poll! %safepoint-poll!))
         #f
         (cp0-has-unsafe-inline-op? expr)))
    ((not (pair? expr)) #f)
    ((or (eq? (car expr) 'quote) (eq? (car expr) 'declare)) #f)
    ((memq (car expr) '(%synapse-safepoint-poll! %safepoint-poll!)) #f)
    ((memq (car expr)
           '(set! %num-args %get-rsp %get-rbp gc-collect! gc-minor-collect!
             call/cc %raw-call/cc dynamic-wind %with-handler
             with-exception-handler guard %cont-fun %cont-call
             %make-closure %make-closure-env %inline-asm error raise))
     #t)
    ((and (symbol? (car expr)) (cp0-asm-or-runtime-stub-name? (car expr)))
     #t)
    (else
     (or (cfa-expr-has-unsafe-op? (car expr))
         (cfa-expr-has-unsafe-op? (cdr expr))))))

(define (cfa-register-lambda-node! lam-expr owner-sym)
  (let ((existing (cfa-lookup-expr-lam-id lam-expr)))
    (if existing
        existing
        (let* ((params (cadr lam-expr))
               (body (cfa-extract-lambda-body lam-expr))
               (proper? (cp0-proper-formal-list? params))
               (arity (if proper? (length params) -1))
               (frees (if (and proper? body)
                          (cp0-collect-free-syms body params '())
                          '()))
               (unsafe? (or (not proper?)
                            (not body)
                            (and owner-sym (cp0-asm-or-runtime-stub-name? owner-sym))
                            (cfa-expr-has-unsafe-op? body)))
               (cost (if body
                         (let ((c (cp0-expr-cost body *cfa-max-inline-body-cost*)))
                           (if c c (+ *cfa-max-inline-body-cost* 1)))
                         (+ *cfa-max-inline-body-cost* 1)))
               (lam-id (unique-label-sym "cfa_lam")))
          (set-car! *cfa-expr-lam-ids* (cons (cons lam-expr lam-id) (car *cfa-expr-lam-ids*)))
          (register-cfa-lambda! lam-id owner-sym params (or body #f) frees arity unsafe? cost)
          lam-id))))

(define (cfa-harvest-lambdas! expr)
  (cond
    ((not (pair? expr)) #f)
    ((or (eq? (car expr) 'quote) (eq? (car expr) 'declare)) #f)
    ((and (eq? (car expr) 'define) (pair? (cdr expr)) (pair? (cddr expr)))
     (let ((head (cadr expr))
           (rhs (caddr expr)))
       (if (and (symbol? head) (pair? rhs) (eq? (car rhs) 'lambda) (pair? (cdr rhs)) (pair? (cddr rhs)))
           (begin
             (cfa-register-lambda-node! rhs head)
             (for-each cfa-harvest-lambdas! (cddr rhs)))
           (cfa-harvest-lambdas! (cdr expr)))))
    ((and (memq (car expr) '(let letrec)) (pair? (cdr expr)) (list? (cadr expr)) (pair? (cddr expr)))
     (for-each
       (lambda (b)
         (let ((var (car b))
               (rhs (cadr b)))
           (if (and (pair? rhs) (eq? (car rhs) 'lambda) (pair? (cdr rhs)) (pair? (cddr rhs)))
               (begin
                 (cfa-register-lambda-node! rhs var)
                 (for-each cfa-harvest-lambdas! (cddr rhs)))
               (cfa-harvest-lambdas! rhs))))
       (cadr expr))
     (for-each cfa-harvest-lambdas! (cddr expr)))
    ((and (eq? (car expr) 'lambda) (pair? (cdr expr)) (pair? (cddr expr)))
     (cfa-register-lambda-node! expr #f)
     (for-each cfa-harvest-lambdas! (cddr expr)))
    (else
     (cfa-harvest-lambdas! (car expr))
     (cfa-harvest-lambdas! (cdr expr)))))

(define (cfa-known-prim-op? op)
  (or (zero-arg-prim? op)
      (unary-prim? op)
      (binop-prim? op)
      (triop-prim? op)
      (septop-prim? op)
      (pure-prim? op)
      (lir-primitive? op)
      (memq op '(cons car cdr list vector vector-ref vector-set! make-vector
                 make-string string-ref string-set! string-length string=?
                 %raw-add %raw-sub %raw-mul %unbox-fixnum %box-fixnum
                 %cont-call %make-closure %make-closure-env %closure-ref %closure-set!
                 %global-ref %global-set! %direct-call annotate))))

(define (cfa-opaque-extractor-op? op)
  (memq op '(car cdr caar cadr cdar cddr
             caaar caadr cadar caddr cdaar cdadr cddar cdddr
             caaaar caaadr caadar caaddr cadaar cadadr caddar cadddr
             cdaaar cdaadr cdadar cdaddr cddaar cddadr cdddar cddddr
             list-ref list-tail vector-ref %closure-ref %global-ref
             apply call/cc call-with-current-continuation %raw-call/cc
             values call-with-values %call-with-values)))

(define (cfa-container-mutator-op? op)
  (memq op '(cons list vector make-vector set-car! set-cdr!
             vector-set! %closure-set! %global-set!)))

(define (cfa-widen-closure-set! cset changed-box)
  (if (and (pair? cset) (not (cfa-top? cset)))
      (for-each
        (lambda (lid)
          (let ((info (get-cfa-lambda-info lid)))
            (if (and info (cp0-proper-formal-list? (cfa-lam-params info)))
                (for-each (lambda (p) (join-cfa-var-set! p *cfa-top* changed-box))
                          (cfa-lam-params info)))))
        cset)))

(define (cfa-widen-expr-params! expr changed-box)
  (cfa-widen-closure-set! (get-cfa-closure-set-from-expr expr) changed-box))

(define (get-cfa-closure-set-from-expr expr)
  (cond
    ((symbol? expr) (get-cfa-closure-set expr))
    ((and (pair? expr) (eq? (car expr) 'lambda))
     (let ((lid (cfa-lookup-expr-lam-id expr)))
       (if lid (list lid) *cfa-bot*)))
    (else *cfa-bot*)))

(define (get-cfa-lam-return lam-id)
  (let ((e (assq lam-id (vector-ref *cfa-lam-returns* (cfa-bucket-idx lam-id)))))
    (if e (cdr e) *cfa-bot*)))

(define (join-cfa-lam-return! lam-id incoming changed-box)
  (let* ((idx (cfa-bucket-idx lam-id))
         (bucket (vector-ref *cfa-lam-returns* idx))
         (e (assq lam-id bucket))
         (cur (if e (cdr e) *cfa-bot*))
         (joined (cfa-join cur incoming)))
    (if (not (cfa-set-equal? cur joined))
        (begin
          (if e
              (set-cdr! e joined)
              (vector-set! *cfa-lam-returns* idx (cons (cons lam-id joined) bucket)))
          (set-car! changed-box #t)))
    joined))

(define (cfa-eval-flow expr changed-box)
  (cond
    ((or (number? expr) (boolean? expr) (char? expr) (string? expr) (null? expr))
     *cfa-bot*)
    ((symbol? expr)
     (get-cfa-closure-set expr))
    ((not (pair? expr)) *cfa-bot*)
    (else
     (let ((op (car expr)))
       (cond
         ((or (eq? op 'quote) (eq? op 'declare)) *cfa-bot*)
         ((and (eq? op 'lambda) (pair? (cdr expr)))
          (let ((lid (cfa-lookup-expr-lam-id expr)))
            (if lid
                (let ((ret-s (let bl ((es (cddr expr)) (cur *cfa-bot*))
                               (if (null? es) cur (bl (cdr es) (cfa-eval-flow (car es) changed-box))))))
                  (join-cfa-lam-return! lid ret-s changed-box)
                  (list lid))
                *cfa-top*)))
         ((and (eq? op 'if) (pair? (cdr expr)) (pair? (cddr expr)))
          (cfa-eval-flow (cadr expr) changed-box)
          (let ((t-set (cfa-eval-flow (caddr expr) changed-box))
                (e-set (if (null? (cdddr expr))
                           *cfa-bot*
                           (cfa-eval-flow (cadddr expr) changed-box))))
            (cfa-join t-set e-set)))
         ((eq? op 'begin)
          (let loop ((es (cdr expr)) (last-s *cfa-bot*))
            (if (null? es)
                last-s
                (loop (cdr es) (cfa-eval-flow (car es) changed-box)))))
         ((and (eq? op 'let) (pair? (cdr expr)) (list? (cadr expr)) (pair? (cddr expr)))
          (for-each
            (lambda (b)
              (let ((var (car b))
                    (rhs-set (cfa-eval-flow (cadr b) changed-box)))
                (join-cfa-var-set! var rhs-set changed-box)))
            (cadr expr))
          (let loop ((es (cddr expr)) (last-s *cfa-bot*))
            (if (null? es)
                last-s
                (loop (cdr es) (cfa-eval-flow (car es) changed-box)))))
         ((and (eq? op 'letrec) (pair? (cdr expr)) (list? (cadr expr)) (pair? (cddr expr)))
          (for-each
            (lambda (b)
              (let ((var (car b))
                    (rhs-set (cfa-eval-flow (cadr b) changed-box)))
                (join-cfa-var-set! var rhs-set changed-box)))
            (cadr expr))
          (let loop ((es (cddr expr)) (last-s *cfa-bot*))
            (if (null? es)
                last-s
                (loop (cdr es) (cfa-eval-flow (car es) changed-box)))))
         ((and (eq? op 'set!) (pair? (cdr expr)) (pair? (cddr expr)))
          (if (symbol? (cadr expr))
              (join-cfa-var-set! (cadr expr) *cfa-top* changed-box))
          (cfa-eval-flow (caddr expr) changed-box)
          *cfa-bot*)
         ((and (eq? op '%cont-fun) (>= (length expr) 5))
          (let ((params (caddr expr))
                (f-body (cadddr expr))
                (in-body (cadr (cdddr expr))))
            (for-each (lambda (p) (join-cfa-var-set! p *cfa-top* changed-box)) params)
            (cfa-eval-flow f-body changed-box)
            (cfa-eval-flow in-body changed-box)))
         ((and (eq? op '%program) (pair? (cdr expr)) (pair? (cddr expr)))
          (for-each
            (lambda (d)
              (if (and (pair? d) (eq? (car d) 'define) (pair? (cdr d)) (pair? (cddr d)))
                  (let ((var (cadr d))
                        (rhs (caddr d)))
                    (if (symbol? var)
                        (join-cfa-var-set! var (cfa-eval-flow rhs changed-box) changed-box)
                        (cfa-eval-flow d changed-box)))
                  (cfa-eval-flow d changed-box)))
            (cadr expr))
          (cfa-eval-flow (caddr expr) changed-box))
         ((and (eq? op 'define) (pair? (cdr expr)) (pair? (cddr expr)))
          (if (symbol? (cadr expr))
              (join-cfa-var-set! (cadr expr) (cfa-eval-flow (caddr expr) changed-box) changed-box)
              (cfa-eval-flow (cddr expr) changed-box))
          *cfa-bot*)
         ((and (symbol? op) (cfa-opaque-extractor-op? op))
          (for-each
            (lambda (a)
              (let ((aset (cfa-eval-flow a changed-box)))
                (if (memq op '(apply call/cc call-with-current-continuation %raw-call/cc %call-with-values))
                    (cfa-widen-closure-set! aset changed-box))))
            (cdr expr))
          *cfa-top*)
         ((and (symbol? op) (cfa-container-mutator-op? op))
          (for-each
            (lambda (a)
              (cfa-widen-closure-set! (cfa-eval-flow a changed-box) changed-box))
            (cdr expr))
          *cfa-bot*)
         ((and (symbol? op) (cfa-known-prim-op? op))
          (for-each (lambda (a) (cfa-eval-flow a changed-box)) (cdr expr))
          *cfa-bot*)
         ((not (list? expr)) *cfa-top*)
         (else
          (let* ((args (cdr expr))
                 (nargs (length args))
                 (arg-sets (map (lambda (a) (cfa-eval-flow a changed-box)) args))
                 (op-set (cfa-eval-flow op changed-box)))
            (if (or (cfa-top? op-set) (null? op-set))
                (begin
                  (for-each
                    (lambda (aset)
                      (if (and (pair? aset) (not (cfa-top? aset)))
                          (for-each
                            (lambda (lid)
                              (let ((info (get-cfa-lambda-info lid)))
                                (if (and info (cp0-proper-formal-list? (cfa-lam-params info)))
                                    (for-each (lambda (p) (join-cfa-var-set! p *cfa-top* changed-box))
                                              (cfa-lam-params info)))))
                            aset)))
                    arg-sets)
                  *cfa-top*)
                (let loop ((lids op-set) (ret-acc *cfa-bot*))
                  (if (null? lids)
                      ret-acc
                      (let ((info (get-cfa-lambda-info (car lids))))
                        (if (or (not info) (not (= (cfa-lam-arity info) nargs)))
                            (begin
                              (if (symbol? op)
                                  (join-cfa-var-set! op *cfa-top* changed-box))
                              *cfa-top*)
                            (begin
                              (let p-loop ((ps (cfa-lam-params info)) (as arg-sets))
                                (if (and (pair? ps) (pair? as))
                                    (begin
                                      (join-cfa-var-set! (car ps) (car as) changed-box)
                                      (p-loop (cdr ps) (cdr as)))))
                              (let ((body-ret (get-cfa-lam-return (car lids))))
                                (loop (cdr lids) (cfa-join ret-acc body-ret))))))))))))))))

(define (cfa-finalize-singletons! dup-defs)
  (let loop ((i 0))
    (if (< i *cfa-bucket-count*)
        (begin
          (for-each
            (lambda (entry)
              (let ((var (car entry))
                    (cset (cdr entry)))
                (if (and (symbol? var)
                         (not (memq var (car *cfa-mutated-vars*)))
                         (not (memq var dup-defs))
                         (pair? cset)
                         (not (cfa-top? cset))
                         (null? (cdr cset)))
                    (let ((info (get-cfa-lambda-info (car cset))))
                      (if (and info (>= (cfa-lam-arity info) 0))
                          (record-cfa-singleton-target! var (car cset)))))))
            (vector-ref *cfa-var-closures* i))
          (loop (+ i 1))))))

(define (cfa-analyze-program form)
  (reset-cfa-state!)
  (if (or (not (pair? form)) (number? form) (boolean? form) (string? form) (char? form))
      #f
      (let ((seen-defs (cons '() '()))
            (dup-defs (cons '() '()))
            (seen-all (cons '() '()))
            (dup-all (cons '() '())))
        (cfa-collect-mutated-and-dups form seen-defs dup-defs seen-all dup-all)
        (for-each (lambda (m) (record-cfa-closure-set! m *cfa-top*))
                  (car *cfa-mutated-vars*))
        (for-each (lambda (d) (record-cfa-closure-set! d *cfa-top*))
                  (car dup-defs))
        (cfa-harvest-lambdas! form)
        (let iter-loop ((iter 0))
          (if (< iter *cfa-max-solver-iters*)
              (let ((changed-box (cons #f '())))
                (if (and (list? form)
                         (pair? (car form))
                         (not (eq? (caar form) 'lambda)))
                    (for-each (lambda (f) (cfa-eval-flow f changed-box)) form)
                    (cfa-eval-flow form changed-box))
                (if (car changed-box)
                    (iter-loop (+ iter 1))))))
        (cfa-finalize-singletons! (car dup-all))
        #t)))

;;; -----------------------------------------------------------------------
;;; 8. Higher-Order Function Monomorphization & Loop Specialization (Issue #972)
;;; -----------------------------------------------------------------------

(define (cfa-remove-nth-elem lst idx)
  (let loop ((xs lst) (i 0) (acc '()))
    (if (null? xs)
        (reverse acc)
        (if (= i idx)
            (loop (cdr xs) (+ i 1) acc)
            (loop (cdr xs) (+ i 1) (cons (car xs) acc))))))

(define (cfa-param-list-index params sym)
  (let loop ((ps params) (i 0))
    (cond
      ((null? ps) #f)
      ((eq? (car ps) sym) i)
      (else (loop (cdr ps) (+ i 1))))))

(define (cfa-map-subexprs fn lst)
  (cond
    ((null? lst) '())
    ((pair? lst) (cons (fn (car lst)) (cfa-map-subexprs fn (cdr lst))))
    (else (fn lst))))

(define (cfa-every-subexpr? pred lst)
  (cond
    ((null? lst) #t)
    ((pair? lst) (and (pred (car lst)) (cfa-every-subexpr? pred (cdr lst))))
    (else (pred lst))))

(define (cfa-subst-drop-arg expr fn-name drop-idx clone-name)
  (cond
    ((not (pair? expr)) expr)
    ((or (eq? (car expr) 'quote) (eq? (car expr) 'declare)) expr)
    ((and (eq? (car expr) 'lambda) (pair? (cdr expr)))
     (let ((params (cadr expr)))
       (if (memq fn-name (cp0-lambda-formal-syms params))
           expr
           (cons 'lambda
                 (cons params
                       (cfa-map-subexprs (lambda (b) (cfa-subst-drop-arg b fn-name drop-idx clone-name))
                                         (cddr expr)))))))
    ((and (eq? (car expr) 'let) (pair? (cdr expr)) (list? (cadr expr)) (pair? (cddr expr)))
     (let* ((bs (cadr expr))
            (new-bs (map (lambda (b)
                           (list (car b) (cfa-subst-drop-arg (cadr b) fn-name drop-idx clone-name)))
                         bs))
            (new-bodies (if (memq fn-name (map car* bs))
                            (cddr expr)
                            (cfa-map-subexprs (lambda (b) (cfa-subst-drop-arg b fn-name drop-idx clone-name))
                                              (cddr expr)))))
       (cons 'let (cons new-bs new-bodies))))
    ((and (eq? (car expr) 'letrec) (pair? (cdr expr)) (list? (cadr expr)) (pair? (cddr expr)))
     (let ((bs (cadr expr)))
       (if (memq fn-name (map car* bs))
           expr
           (cons 'letrec
                 (cons (map (lambda (b)
                              (list (car b) (cfa-subst-drop-arg (cadr b) fn-name drop-idx clone-name)))
                            bs)
                       (cfa-map-subexprs (lambda (b) (cfa-subst-drop-arg b fn-name drop-idx clone-name))
                                         (cddr expr)))))))
    ((eq? (car expr) fn-name)
     (cons clone-name
           (cfa-remove-nth-elem
             (cfa-map-subexprs (lambda (a) (cfa-subst-drop-arg a fn-name drop-idx clone-name)) (cdr expr))
             drop-idx)))
    (else
     (cons (cfa-subst-drop-arg (car expr) fn-name drop-idx clone-name)
           (cfa-map-subexprs (lambda (a) (cfa-subst-drop-arg a fn-name drop-idx clone-name)) (cdr expr))))))

(define (cfa-self-calls-preserve-param? fn-name p-idx expr expected-sym)
  (cond
    ((not (pair? expr)) #t)
    ((or (eq? (car expr) 'quote) (eq? (car expr) 'declare)) #t)
    ((and (eq? (car expr) 'lambda) (pair? (cdr expr)))
     (let ((fs (cp0-lambda-formal-syms (cadr expr))))
       (if (or (memq fn-name fs) (memq expected-sym fs))
           #t
           (cfa-every-subexpr? (lambda (b) (cfa-self-calls-preserve-param? fn-name p-idx b expected-sym))
                               (cddr expr)))))
    ((and (eq? (car expr) 'let) (pair? (cdr expr)) (list? (cadr expr)))
     (let ((bs (cadr expr)))
       (and (cfa-every-subexpr? (lambda (b) (cfa-self-calls-preserve-param? fn-name p-idx (cadr b) expected-sym)) bs)
            (or (memq fn-name (map car* bs))
                (memq expected-sym (map car* bs))
                (cfa-every-subexpr? (lambda (b) (cfa-self-calls-preserve-param? fn-name p-idx b expected-sym))
                                    (cddr expr))))))
    ((and (eq? (car expr) 'letrec) (pair? (cdr expr)) (list? (cadr expr)))
     (let ((bs (cadr expr)))
       (if (or (memq fn-name (map car* bs)) (memq expected-sym (map car* bs)))
           #t
           (and (cfa-every-subexpr? (lambda (b) (cfa-self-calls-preserve-param? fn-name p-idx (cadr b) expected-sym)) bs)
                (cfa-every-subexpr? (lambda (b) (cfa-self-calls-preserve-param? fn-name p-idx b expected-sym))
                                    (cddr expr))))))
    ((eq? (car expr) fn-name)
     (let ((args (cdr expr)))
       (and (> (length args) p-idx)
            (eq? (list-ref args p-idx) expected-sym)
            (let loop ((as args) (i 0))
              (cond
                ((null? as) #t)
                ((= i p-idx) (loop (cdr as) (+ i 1)))
                (else (and (cfa-self-calls-preserve-param? fn-name p-idx (car as) expected-sym)
                           (loop (cdr as) (+ i 1)))))))))
    (else
     (and (cfa-self-calls-preserve-param? fn-name p-idx (car expr) expected-sym)
          (cfa-every-subexpr? (lambda (a) (cfa-self-calls-preserve-param? fn-name p-idx a expected-sym))
                              (cdr expr))))))

(define (cfa-var-only-called-with-arity? var arity expr fn-name fn-idx)
  (cond
    ((symbol? expr) (not (eq? expr var)))
    ((not (pair? expr)) #t)
    ((or (eq? (car expr) 'quote) (eq? (car expr) 'declare)) #t)
    ((and (eq? (car expr) 'lambda) (pair? (cdr expr)))
     (if (memq var (cp0-lambda-formal-syms (cadr expr)))
         #t
         (cfa-every-subexpr? (lambda (b) (cfa-var-only-called-with-arity? var arity b fn-name fn-idx))
                             (cddr expr))))
    ((and (eq? (car expr) 'let) (pair? (cdr expr)) (list? (cadr expr)))
     (let ((bs (cadr expr)))
       (and (cfa-every-subexpr? (lambda (b) (cfa-var-only-called-with-arity? var arity (cadr b) fn-name fn-idx)) bs)
            (or (memq var (map car* bs))
                (cfa-every-subexpr? (lambda (b) (cfa-var-only-called-with-arity? var arity b fn-name fn-idx))
                                    (cddr expr))))))
    ((and (eq? (car expr) 'letrec) (pair? (cdr expr)) (list? (cadr expr)))
     (let ((bs (cadr expr)))
       (if (memq var (map car* bs))
           #t
           (and (cfa-every-subexpr? (lambda (b) (cfa-var-only-called-with-arity? var arity (cadr b) fn-name fn-idx)) bs)
                (cfa-every-subexpr? (lambda (b) (cfa-var-only-called-with-arity? var arity b fn-name fn-idx))
                                    (cddr expr))))))
    ((and fn-name (eq? (car expr) fn-name))
     (let loop ((as (cdr expr)) (i 0))
       (cond
         ((null? as) #t)
         ((and fn-idx (= i fn-idx))
          (loop (cdr as) (+ i 1)))
         (else
          (and (cfa-var-only-called-with-arity? var arity (car as) fn-name fn-idx)
               (loop (cdr as) (+ i 1)))))))
    ((eq? (car expr) var)
     (and (or (not arity) (= (length (cdr expr)) arity))
          (cfa-every-subexpr? (lambda (a) (cfa-var-only-called-with-arity? var arity a fn-name fn-idx))
                              (cdr expr))))
    (else
     (and (cfa-var-only-called-with-arity? var arity (car expr) fn-name fn-idx)
          (cfa-every-subexpr? (lambda (a) (cfa-var-only-called-with-arity? var arity a fn-name fn-idx))
                              (cdr expr))))))

(define (cfa-any-memq? needles haystack)
  (let loop ((ns needles))
    (and (pair? ns)
         (or (memq (car ns) haystack)
             (loop (cdr ns))))))

(define (cfa-specializable-lambda-info? lam-info forbidden-vars)
  (and lam-info
       (>= (cfa-lam-arity lam-info) 0)
       (not (cfa-lam-unsafe? lam-info))
       (<= (cfa-lam-cost lam-info) *cfa-max-inline-body-cost*)
       (cfa-lam-body lam-info)
       (not (and (cfa-lam-owner lam-info)
                 (occurs-in? (cfa-lam-owner lam-info) (cfa-lam-body lam-info))))
       (not (cfa-any-memq? (cfa-lam-frees lam-info) forbidden-vars))
       (not (cfa-any-memq? (cfa-lam-frees lam-info) (car *cfa-mutated-vars*)))))

(define (cfa-inline-param-calls expr param-var lam-params lam-body)
  (cond
    ((not (pair? expr)) expr)
    ((or (eq? (car expr) 'quote) (eq? (car expr) 'declare)) expr)
    ((and (eq? (car expr) param-var) (= (length (cdr expr)) (length lam-params)))
     (let ((new-args (cfa-map-subexprs (lambda (a) (cfa-inline-param-calls a param-var lam-params lam-body)) (cdr expr))))
       (let ((expanded (cp0-expand-beta-call lam-params lam-body new-args)))
         (if expanded
             expanded
             (cons (car expr) new-args)))))
    ((and (eq? (car expr) 'lambda) (pair? (cdr expr)))
     (let ((fs (cp0-lambda-formal-syms (cadr expr))))
       (if (memq param-var fs)
           expr
           (cons 'lambda (cons (cadr expr)
                               (cfa-map-subexprs (lambda (b) (cfa-inline-param-calls b param-var lam-params lam-body))
                                                 (cddr expr)))))))
    ((and (memq (car expr) '(let letrec)) (pair? (cdr expr)) (list? (cadr expr)))
     (let* ((bs (cadr expr))
            (new-bs (if (eq? (car expr) 'let)
                        (map (lambda (b)
                               (list (car b) (cfa-inline-param-calls (cadr b) param-var lam-params lam-body)))
                             bs)
                        (if (memq param-var (map car* bs))
                            bs
                            (map (lambda (b)
                                   (list (car b) (cfa-inline-param-calls (cadr b) param-var lam-params lam-body)))
                                 bs))))
            (new-bodies (if (memq param-var (map car* bs))
                            (cddr expr)
                            (cfa-map-subexprs (lambda (b) (cfa-inline-param-calls b param-var lam-params lam-body))
                                              (cddr expr)))))
       (cons (car expr) (cons new-bs new-bodies))))
    (else
     (cons (cfa-inline-param-calls (car expr) param-var lam-params lam-body)
           (cfa-map-subexprs (lambda (a) (cfa-inline-param-calls a param-var lam-params lam-body)) (cdr expr))))))

(define (cfa-lookup-lam-in-env sym local-lam-env)
  (cond
    ((pair? sym)
     (and (eq? (car sym) 'lambda) (cfa-register-lambda-node! sym #f)))
    ((symbol? sym)
     (let ((loc (assq sym local-lam-env)))
       (cond
         (loc (cdr loc))
         (else
          (let ((tid (get-cfa-singleton-target sym)))
            (and tid (get-cfa-lambda-info tid)))))))
    (else #f)))

(define (cfa-collect-entry-arg-lambdas expr fn-name p-idx local-lam-env acc-box)
  (cond
    ((not (pair? expr)) #f)
    ((or (eq? (car expr) 'quote) (eq? (car expr) 'declare)) #f)
    ((and (eq? (car expr) 'lambda) (pair? (cdr expr)))
     (let ((fs (cp0-lambda-formal-syms (cadr expr))))
       (if (not (memq fn-name fs))
           (let ((filtered-env
                  (let fl ((e local-lam-env) (acc '()))
                    (if (null? e) (reverse acc)
                        (if (memq (caar e) fs) (fl (cdr e) acc) (fl (cdr e) (cons (car e) acc)))))))
             (for-each (lambda (b) (cfa-collect-entry-arg-lambdas b fn-name p-idx filtered-env acc-box))
                       (cddr expr))))))
    ((and (eq? (car expr) 'let) (pair? (cdr expr)) (list? (cadr expr)) (pair? (cddr expr)))
     (let loop ((bs (cadr expr)) (env local-lam-env))
       (if (null? bs)
           (if (not (memq fn-name (map car* (cadr expr))))
               (cfa-collect-entry-arg-lambdas (caddr expr) fn-name p-idx env acc-box))
           (let* ((b (car bs))
                  (var (car b))
                  (rhs (cadr b)))
             (cfa-collect-entry-arg-lambdas rhs fn-name p-idx local-lam-env acc-box)
             (let ((linfo
                    (cond
                      ((and (pair? rhs) (eq? (car rhs) 'lambda))
                       (get-cfa-lambda-info (cfa-register-lambda-node! rhs var)))
                      ((symbol? rhs)
                       (cfa-lookup-lam-in-env rhs env))
                      (else #f))))
               (loop (cdr bs) (if linfo (cons (cons var linfo) env) env)))))))
    ((and (eq? (car expr) 'letrec) (pair? (cdr expr)) (list? (cadr expr)))
     (if (not (memq fn-name (map car* (cadr expr))))
         (begin
           (for-each (lambda (b) (cfa-collect-entry-arg-lambdas (cadr b) fn-name p-idx local-lam-env acc-box)) (cadr expr))
           (for-each (lambda (b) (cfa-collect-entry-arg-lambdas b fn-name p-idx local-lam-env acc-box)) (cddr expr)))))
    ((eq? (car expr) fn-name)
     (let ((args (cdr expr)))
       (if (> (length args) p-idx)
           (let* ((a (list-ref args p-idx))
                  (linfo (cfa-lookup-lam-in-env a local-lam-env)))
             (set-car! acc-box (cons linfo (car acc-box))))
           (set-car! acc-box (cons #f (car acc-box))))
       (cfa-every-subexpr?
         (lambda (x)
           (cfa-collect-entry-arg-lambdas x fn-name p-idx local-lam-env acc-box)
           #t)
         args)))
    (else
     (cfa-collect-entry-arg-lambdas (car expr) fn-name p-idx local-lam-env acc-box)
     (cfa-every-subexpr?
       (lambda (x)
         (cfa-collect-entry-arg-lambdas x fn-name p-idx local-lam-env acc-box)
         #t)
       (cdr expr)))))

(define (cfa-prune-dead-lambda-lets expr)
  (cond
    ((not (pair? expr)) expr)
    ((or (eq? (car expr) 'quote) (eq? (car expr) 'declare)) expr)
    ((and (eq? (car expr) 'let) (pair? (cdr expr)) (list? (cadr expr)) (pair? (cddr expr)))
     (let* ((new-body (cfa-prune-dead-lambda-lets (caddr expr)))
            (live-bs
             (let loop ((bs (cadr expr)) (acc '()))
               (if (null? bs)
                   (reverse acc)
                   (let* ((b (car bs))
                          (v (car b))
                          (rhs (cfa-prune-dead-lambda-lets (cadr b))))
                     (if (and (pair? rhs)
                              (eq? (car rhs) 'lambda)
                              (not (occurs-in? v new-body)))
                         (loop (cdr bs) acc)
                         (loop (cdr bs) (cons (list v rhs) acc))))))))
       (if (null? live-bs)
           new-body
           (list 'let live-bs new-body))))
    ((and (eq? (car expr) 'letrec) (pair? (cdr expr)) (list? (cadr expr)))
     (cons 'letrec
           (cons (map (lambda (b) (list (car b) (cfa-prune-dead-lambda-lets (cadr b)))) (cadr expr))
                 (cfa-map-subexprs cfa-prune-dead-lambda-lets (cddr expr)))))
    ((and (eq? (car expr) 'lambda) (pair? (cdr expr)))
     (cons 'lambda (cons (cadr expr) (cfa-map-subexprs cfa-prune-dead-lambda-lets (cddr expr)))))
    ((eq? (car expr) '%program)
     (list '%program
           (map cfa-prune-dead-lambda-lets (cadr expr))
           (cfa-prune-dead-lambda-lets (caddr expr))))
    (else
     (cons (cfa-prune-dead-lambda-lets (car expr))
           (cfa-map-subexprs cfa-prune-dead-lambda-lets (cdr expr))))))

(define (cfa-try-specialize-letrec-loop bindings body clone-budget-box local-lam-env)
  (if (or (not (= (length bindings) 1))
          (not (pair? (car bindings)))
          (not (pair? (cadar bindings)))
          (not (eq? (caadar bindings) 'lambda))
          (<= (car clone-budget-box) 0))
      #f
      (let* ((b (car bindings))
             (fn-name (car b))
             (fn-lam (cadr b))
             (params (cadr fn-lam))
             (lbody (caddr fn-lam)))
        (if (or (not (cp0-proper-formal-list? params))
                (memq fn-name (car *cfa-mutated-vars*)))
            #f
            (let param-loop ((ps params) (idx 0))
              (if (null? ps)
                  #f
                  (let ((p (car ps)))
                    (if (memq p (car *cfa-mutated-vars*))
                        (param-loop (cdr ps) (+ idx 1))
                        (let ((call-linfos-box (cons '() '())))
                      (cfa-collect-entry-arg-lambdas body fn-name idx local-lam-env call-linfos-box)
                      (let* ((linfos (car call-linfos-box))
                             (first-info (and (pair? linfos) (car linfos)))
                             (all-same-lam?
                              (and first-info
                                   (let loop ((ls (cdr linfos)))
                                     (or (null? ls)
                                         (and (car ls)
                                              (eq? (cfa-lam-id (car ls)) (cfa-lam-id first-info))
                                              (loop (cdr ls))))))))
                        (if (and all-same-lam?
                                 (cfa-specializable-lambda-info? first-info (cons fn-name params))
                                 (cfa-self-calls-preserve-param? fn-name idx lbody p)
                                 (cfa-var-only-called-with-arity? p (cfa-lam-arity first-info) lbody fn-name idx))
                            (let* ((lparams (cfa-lam-params first-info))
                                   (lam-body (cfa-strip-leading-safepoint (cfa-lam-body first-info) lbody))
                                   (inlined-body (cfa-inline-param-calls lbody p lparams lam-body))
                                   (stripped-body (cfa-subst-drop-arg inlined-body fn-name idx fn-name))
                                   (anf-body (anf-expr-depth stripped-body 0))
                                   (new-params (cfa-remove-nth-elem params idx))
                                   (raw-entry (cfa-subst-drop-arg body fn-name idx fn-name))
                                   (clean-entry (cfa-prune-dead-lambda-lets raw-entry))
                                   (anf-entry (anf-expr-depth clean-entry 0)))
                              (set-car! clone-budget-box (- (car clone-budget-box) 1))
                              (list 'letrec
                                    (list (list fn-name (list 'lambda new-params anf-body)))
                                    anf-entry))
                            (param-loop (cdr ps) (+ idx 1)))))))))))))

(define (cfa-hof-candidate-param-indices fn-name params lbody)
  (let loop ((ps params) (idx 0) (acc '()))
    (if (null? ps)
        (reverse acc)
        (let ((p (car ps)))
          (if (and (occurs-in? p lbody)
                   (cfa-self-calls-preserve-param? fn-name idx lbody p)
                   (cfa-var-only-called-with-arity? p #f lbody fn-name idx))
              (loop (cdr ps) (+ idx 1) (cons idx acc))
              (loop (cdr ps) (+ idx 1) acc))))))

(define (cfa-frees-all-global-or-prim? frees top-lam-env all-def-names)
  (let loop ((fs frees))
    (if (null? fs)
        #t
        (let ((fv (car fs)))
          (and (or (cfa-known-prim-op? fv)
                   (memq fv '(%synapse-safepoint-poll! %safepoint-poll! begin))
                   (assq fv top-lam-env)
                   (memq fv all-def-names))
               (loop (cdr fs)))))))

(define (cfa-mono-expr expr top-hofs top-lam-env all-def-names local-lam-env clone-cache clones-per-fn total-budget-box top-defs-box)
  (cond
    ((not (pair? expr)) expr)
    ((or (eq? (car expr) 'quote) (eq? (car expr) 'declare)) expr)
    ((and (eq? (car expr) 'let) (pair? (cdr expr)) (list? (cadr expr)) (pair? (cddr expr)))
     (let* ((bindings (cadr expr))
            (body (caddr expr))
            (ext-env-box (cons local-lam-env '()))
            (new-bs
             (map (lambda (b)
                    (let* ((v (car b))
                           (nrhs (cfa-mono-expr (cadr b) top-hofs top-lam-env all-def-names local-lam-env clone-cache clones-per-fn total-budget-box top-defs-box)))
                      (cond
                        ((and (pair? nrhs) (eq? (car nrhs) 'lambda))
                         (let ((linfo (get-cfa-lambda-info (cfa-register-lambda-node! nrhs v))))
                           (if linfo (set-car! ext-env-box (cons (cons v linfo) (car ext-env-box))))))
                        ((symbol? nrhs)
                         (let ((linfo (cfa-lookup-lam-in-env nrhs (car ext-env-box))))
                           (if linfo (set-car! ext-env-box (cons (cons v linfo) (car ext-env-box)))))))
                      (list v nrhs)))
                  bindings))
            (new-body (cfa-mono-expr body top-hofs top-lam-env all-def-names (car ext-env-box) clone-cache clones-per-fn total-budget-box top-defs-box)))
       (if (and (equal? new-bs bindings) (eq? new-body body))
           expr
           (cfa-prune-dead-lambda-lets (list 'let new-bs new-body)))))
    ((and (eq? (car expr) 'letrec) (pair? (cdr expr)) (list? (cadr expr)) (pair? (cddr expr)))
     (let* ((bindings (cadr expr))
            (body (caddr expr))
            (spec (cfa-try-specialize-letrec-loop bindings body total-budget-box local-lam-env)))
       (if spec
           (let ((respec (cfa-mono-expr spec top-hofs top-lam-env all-def-names local-lam-env clone-cache clones-per-fn total-budget-box top-defs-box)))
             respec)
           (let ((new-bs
                  (map (lambda (b)
                         (list (car b) (cfa-mono-expr (cadr b) top-hofs top-lam-env all-def-names local-lam-env clone-cache clones-per-fn total-budget-box top-defs-box)))
                       bindings))
                 (new-body (cfa-mono-expr body top-hofs top-lam-env all-def-names local-lam-env clone-cache clones-per-fn total-budget-box top-defs-box)))
             (if (and (equal? new-bs bindings) (eq? new-body body))
                 expr
                 (list 'letrec new-bs new-body))))))
    ((and (eq? (car expr) 'lambda) (pair? (cdr expr)) (pair? (cddr expr)))
     (let ((new-bodies (map (lambda (b) (cfa-mono-expr b top-hofs top-lam-env all-def-names local-lam-env clone-cache clones-per-fn total-budget-box top-defs-box))
                            (cddr expr))))
       (if (equal? new-bodies (cddr expr))
           expr
           (cons 'lambda (cons (cadr expr) new-bodies)))))
    ((and (eq? (car expr) 'if) (pair? (cdr expr)) (pair? (cddr expr)))
     (let ((nt (cfa-mono-expr (cadr expr) top-hofs top-lam-env all-def-names local-lam-env clone-cache clones-per-fn total-budget-box top-defs-box))
           (nth (cfa-mono-expr (caddr expr) top-hofs top-lam-env all-def-names local-lam-env clone-cache clones-per-fn total-budget-box top-defs-box))
           (nel (if (null? (cdddr expr)) #f
                    (cfa-mono-expr (cadddr expr) top-hofs top-lam-env all-def-names local-lam-env clone-cache clones-per-fn total-budget-box top-defs-box))))
       (if (null? (cdddr expr))
           (list 'if nt nth)
           (list 'if nt nth nel))))
    ((eq? (car expr) 'begin)
     (cons 'begin (map (lambda (e) (cfa-mono-expr e top-hofs top-lam-env all-def-names local-lam-env clone-cache clones-per-fn total-budget-box top-defs-box))
                       (cdr expr))))
    ((not (list? expr)) expr)
    (else
     (let* ((op (car expr))
            (args (map (lambda (a) (cfa-mono-expr a top-hofs top-lam-env all-def-names local-lam-env clone-cache clones-per-fn total-budget-box top-defs-box))
                       (cdr expr)))
            (hof-entry (and (symbol? op) (assq op top-hofs))))
       (if (and hof-entry
                (let ((params (cadr hof-entry)))
                  (= (length args) (length params))))
           (let* ((params (cadr hof-entry))
                  (hbody (caddr hof-entry))
                  (cand-idxs (cadddr hof-entry))
                  (match-slot
                   (let loop ((idxs cand-idxs))
                     (if (null? idxs)
                         #f
                         (let* ((idx (car idxs))
                                (p (list-ref params idx))
                                (arg (list-ref args idx))
                                (linfo (cfa-lookup-lam-in-env arg local-lam-env)))
                           (if (and linfo
                                    (cfa-frees-all-global-or-prim? (cfa-lam-frees linfo) top-lam-env all-def-names)
                                    (cfa-specializable-lambda-info? linfo (cons op params))
                                    (cfa-var-only-called-with-arity? p (cfa-lam-arity linfo) hbody op idx))
                               (list idx p linfo)
                               (loop (cdr idxs))))))))
             (if match-slot
                 (let* ((idx (car match-slot))
                        (p (cadr match-slot))
                        (linfo (caddr match-slot))
                        (cache-key (list op idx (cfa-lam-id linfo)))
                        (cached (assoc cache-key (car clone-cache))))
                   (if cached
                       (cons (cdr cached) (cfa-remove-nth-elem args idx))
                       (let* ((fn-cnt-entry (assq op (car clones-per-fn)))
                              (fn-cnt (if fn-cnt-entry (cdr fn-cnt-entry) 0)))
                         (if (and (< fn-cnt *cfa-max-clones-per-fn*)
                                  (> (car total-budget-box) 0))
                             (let* ((clone-name (unique-symbol (string-append (symbol->string op) "__mono_")))
                                    (sbody (cfa-strip-leading-safepoint (cfa-lam-body linfo) hbody))
                                    (inlined-b (cfa-inline-param-calls hbody p (cfa-lam-params linfo) sbody))
                                    (rebound-b (cfa-subst-drop-arg inlined-b op idx clone-name))
                                    (anf-b (anf-expr-depth rebound-b 0))
                                    (clone-params (cfa-remove-nth-elem params idx))
                                    (clone-def (list 'define clone-name (list 'lambda clone-params anf-b))))
                               (set-car! total-budget-box (- (car total-budget-box) 1))
                               (if fn-cnt-entry
                                   (set-cdr! fn-cnt-entry (+ fn-cnt 1))
                                   (set-car! clones-per-fn (cons (cons op 1) (car clones-per-fn))))
                               (set-car! clone-cache (cons (cons cache-key clone-name) (car clone-cache)))
                               (set-car! top-defs-box (cons clone-def (car top-defs-box)))
                               (cons clone-name (cfa-remove-nth-elem args idx)))
                             (cons op args)))))
                 (cons op args)))
           (cons op args))))))

(define (cfa-monomorphize-all form)
  (cond
    ((not (pair? form)) form)
    ((eq? (car form) '%program)
     (let* ((defs (cadr form))
            (main (caddr form))
            (total-budget-box (cons *cfa-max-total-clones* '()))
            (clone-cache (cons '() '()))
            (clones-per-fn (cons '() '()))
            (top-defs-box (cons '() '()))
            (all-def-names
             (let loop ((ds defs) (acc '()))
               (if (null? ds)
                   acc
                   (let ((d (car ds)))
                     (if (and (pair? d) (eq? (car d) 'define) (symbol? (cadr d)))
                         (loop (cdr ds) (cons (cadr d) acc))
                         (loop (cdr ds) acc))))))
            ;; Index top-level HOFs eligible for specialization
            (top-hofs
             (let loop ((ds defs) (acc '()))
               (if (null? ds)
                   (reverse acc)
                   (let ((d (car ds)))
                     (if (and (pair? d) (eq? (car d) 'define) (symbol? (cadr d))
                              (pair? (cddr d)) (pair? (caddr d)) (eq? (caaddr d) 'lambda)
                              (pair? (cdr (caddr d))) (pair? (cddr (caddr d))))
                         (let* ((fname (cadr d))
                                (flam (caddr d))
                                (params (cadr flam))
                                (fbody (caddr flam))
                                (cost (and (cp0-proper-formal-list? params)
                                           (not (cp0-has-unsafe-inline-op? fbody))
                                           (cp0-expr-cost fbody *cfa-max-inline-body-cost*)))
                                (cand-idxs (if cost (cfa-hof-candidate-param-indices fname params fbody) '())))
                           (if (pair? cand-idxs)
                               (loop (cdr ds) (cons (list fname params fbody cand-idxs) acc))
                               (loop (cdr ds) acc)))
                         (loop (cdr ds) acc))))))
            (top-lam-env
             (let loop ((ds defs) (acc '()))
               (if (null? ds)
                   (reverse acc)
                   (let ((d (car ds)))
                     (if (and (pair? d) (eq? (car d) 'define) (symbol? (cadr d))
                              (pair? (cddr d)) (pair? (caddr d)) (eq? (caaddr d) 'lambda))
                         (let* ((lid (cfa-lookup-expr-lam-id (caddr d)))
                                (linfo (and lid (get-cfa-lambda-info lid))))
                           (loop (cdr ds) (if linfo (cons (cons (cadr d) linfo) acc) acc)))
                         (loop (cdr ds) acc))))))
            (new-defs
             (map (lambda (d)
                    (if (and (pair? d) (eq? (car d) 'define) (pair? (cddr d)))
                        (let* ((nv (cfa-mono-expr (caddr d) top-hofs top-lam-env all-def-names top-lam-env clone-cache clones-per-fn total-budget-box top-defs-box)))
                          (if (eq? nv (caddr d)) d (list 'define (cadr d) nv)))
                        (cfa-mono-expr d top-hofs top-lam-env all-def-names top-lam-env clone-cache clones-per-fn total-budget-box top-defs-box)))
                  defs))
            (new-main (cfa-mono-expr main top-hofs top-lam-env all-def-names top-lam-env clone-cache clones-per-fn total-budget-box top-defs-box))
            (extra-defs (reverse (car top-defs-box))))
       (if (and (equal? new-defs defs) (eq? new-main main) (null? extra-defs))
           form
           (let ((raw-prog (list '%program (append new-defs extra-defs) new-main)))
             (cfa-prune-dead-lambda-lets raw-prog)))))
    (else
     (let ((clone-cache (cons '() '()))
           (clones-per-fn (cons '() '()))
           (total-budget-box (cons *cfa-max-clones-per-fn* '()))
           (top-defs-box (cons '() '())))
       (let ((res (cfa-mono-expr form '() '() '() '() clone-cache clones-per-fn total-budget-box top-defs-box)))
         (if (equal? res form) form res))))))

(define (annotate-run-type-walk form-or-forms)
  (cond
    ((null? form-or-forms) '())
    ((not (pair? form-or-forms))
     (abstract-eval-expr form-or-forms '())
     form-or-forms)
    ((eq? (car form-or-forms) '%program)
     (let ((defs (cadr form-or-forms))
           (main (caddr form-or-forms)))
       (let rec ((ds defs))
         (if (pair? ds)
             (begin
               (annotate-form (car ds))
               (rec (cdr ds)))))
       (abstract-eval-expr main '())
       form-or-forms))
    ((eq? (car form-or-forms) 'define)
     (annotate-form form-or-forms))
    ((eq? (car form-or-forms) 'letrec)
     (let ((bindings (cadr form-or-forms))
           (body (cddr form-or-forms)))
       (if (= (length bindings) 1)
           (abstract-eval-expr form-or-forms '())
           (let rec ((bs bindings))
             (if (pair? bs)
                 (let* ((b (car bs))
                        (var (car b))
                        (val (cadr b)))
                   (if (and (pair? val) (eq? (car val) 'lambda))
                       (let* ((params (cadr val))
                              (param-types (map (lambda (p) (type-top)) params)))
                         (record-var-type! var (type-closure var params (type-top))))
                       (record-var-type! var (type-top)))
                   (rec (cdr bs))))))
       form-or-forms))
    (else
     (abstract-eval-expr form-or-forms '())
     form-or-forms)))

(define (annotate-all form-or-forms)
  (reset-type-annotations!)
  (if (>= (pipeline-opt-level) 2)
      (begin
        (cfa-analyze-program form-or-forms)
        (let ((spec (cfa-monomorphize-all form-or-forms)))
          (if (not (eq? spec form-or-forms))
              (begin
                (reset-type-annotations!)
                (cfa-analyze-program spec)
                (annotate-run-type-walk spec))
              (annotate-run-type-walk form-or-forms))))
      (annotate-run-type-walk form-or-forms)))
