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

;;; Global Type Tables for Whole-Program Traceability
(define *global-type-env* (cons '() '()))
(define *expr-type-table* (cons '() '()))

(define (reset-type-annotations!)
  (set-car! *global-type-env* '())
  (set-car! *expr-type-table* '()))

(define (record-var-type! var type)
  (set-car! *global-type-env* (cons (cons var type) (car *global-type-env*))))

(define (get-var-type var)
  (type-env-lookup var (car *global-type-env*)))

(define (record-expr-type! expr-id type)
  (set-car! *expr-type-table* (cons (cons expr-id type) (car *expr-type-table*))))

(define (get-expr-type expr-id)
  (type-env-lookup expr-id (car *expr-type-table*)))

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
            (case op
              ((+) (type-fixnum-range (+ min1 min2) (+ max1 max2)))
              ((-) (type-fixnum-range (- min1 max2) (- max1 min2)))
              ((*) (type-fixnum))
              (else (type-fixnum))))
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
    ((memq op '(string-length bytevector-length bytevector-u8-ref vector-length))
     (type-fixnum))
    ((memq op '(bytevector? vector?))
     (type-boolean))
    ((memq op '(make-string string-ref))
     (if (eq? op 'make-string) (type-string) (type-char)))
    ((memq op '(%get-rsp %get-heap-ptr %get-gc-state-ptr %raw-load %ptr-add %ptr-tag-add))
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
                 (body-expr (if (null? (cddr expr)) #f (caddr expr))))
            (if (and (= (length bindings) 1)
                     (let* ((b (car bindings))
                            (val (cadr b)))
                       (and (pair? val) (eq? (car val) 'lambda)))
                     (pair? body-expr)
                     (eq? (car body-expr) (caar bindings))
                     (let check-nums ((is (cdr body-expr)))
                       (if (null? is) #t
                           (if (number? (car is))
                               (check-nums (cdr is))
                               #f))))
                ;; Desugared named-let loop
                (let* ((b (car bindings))
                       (fn-name (car b))
                       (fn-val (cadr b))
                       (params (cadr fn-val))
                       (lbodies (cddr fn-val))
                       (inits (cdr body-expr))
                       (named-bindings (let make-bs ((ps params) (is inits) (acc '()))
                                         (if (or (null? ps) (null? is))
                                             (reverse acc)
                                             (make-bs (cdr ps) (cdr is) (cons (list (car ps) (car is)) acc))))))
                  (abstract-eval-named-let fn-name named-bindings lbodies env))
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

(define (annotate-all form-or-forms)
  (reset-type-annotations!)
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
