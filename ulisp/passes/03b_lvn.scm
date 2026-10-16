;;; =======================================================================
;;; ULisp Compiler Pass 3b: Extended Local Value Numbering (LVN) Nanopass
;;; Conforms to DSN-33 Architecture Specification (Section 8.2) & Issue #521
;;;
;;; Features:
;;; 1. Local Value Numbering (LVN) & Scoped Dominance (DVN) environment
;;; 2. Unified Constant Folding, Copy Propagation & Common Subexpression Elimination (CSE)
;;; 3. Immutable Pair Accessor Memoization (car/cdr deduplication & cons reduction)
;;; 4. Type Predicate Folding (fixnum?, pair?, null?, etc. in dominance scopes)
;;; 5. Algebraic Equivalence & Identity Normalization (+, -, *, =, eq?, char=?)
;;; 6. Sound Pair Mutation Invalidation (set-car!, set-cdr!)
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. LVN Environment Data Structure & Accessors
;;; -----------------------------------------------------------------------
;;; Environment layout: (list var-env tuple-env vn-env next-id)
;;;   var-env:   ((var . vn) ...)
;;;   tuple-env: ((canonical-tuple . vn) ...)
;;;   vn-env:    ((vn . (canonical-expr . info)) ...)
;;;   next-id:   integer (1, 2, 3...)

(define (make-lvn-env)
  (list '() '() '() 1))

(define (lvn-env-vars env) (car env))
(define (lvn-env-tuples env) (cadr env))
(define (lvn-env-vns env) (caddr env))
(define (lvn-env-next-id env) (cadddr env))

(define (lvn-set-vars env vars)
  (list vars (cadr env) (caddr env) (cadddr env)))
(define (lvn-set-tuples env tuples)
  (list (car env) tuples (caddr env) (cadddr env)))
(define (lvn-set-vns env vns)
  (list (car env) (cadr env) vns (cadddr env)))

(define (lvn-alloc-vn env canon-expr info)
  (let* ((id (lvn-env-next-id env))
         (new-vns (cons (cons id (cons canon-expr info)) (lvn-env-vns env)))
         (new-env (list (lvn-env-vars env)
                        (lvn-env-tuples env)
                        new-vns
                        (+ id 1))))
    (cons id new-env)))

(define (tree-contains? tree sym)
  (cond
    ((eq? tree sym) #t)
    ((pair? tree)
     (or (tree-contains? (car tree) sym)
         (tree-contains? (cdr tree) sym)))
    (else #f)))

(define (lvn-bind-var env var vn)
  (let* ((vars (cons (cons var vn) (lvn-env-vars env)))
         (env1 (lvn-set-vars env vars))
         (vn-entry (assq vn (lvn-env-vns env1))))
    ;; If this VN does not have a canonical variable yet (or has a compound expr),
    ;; set its canonical representation to var
    (if (and vn-entry (not (symbol? (cadr vn-entry))))
        (let ((new-vns (cons (cons vn (cons var (cddr vn-entry)))
                             (lvn-env-vns env1))))
          (lvn-set-vns env1 new-vns))
        env1)))

(define (lvn-record-tuple env tuple vn)
  (lvn-set-tuples env (cons (cons tuple vn) (lvn-env-tuples env))))

(define (lvn-lookup-tuple env tuple)
  (let ((entry (assoc tuple (lvn-env-tuples env))))
    (if entry (cdr entry) #f)))

(define (lvn-vn-entry env vn)
  (assq vn (lvn-env-vns env)))

(define (lvn-vn-canon-expr env vn)
  (let ((e (lvn-vn-entry env vn)))
    (if e (cadr e) #f)))

(define (lvn-vn-info env vn)
  (let ((e (lvn-vn-entry env vn)))
    (if e (cddr e) '())))

(define (lvn-vn-is-const? env vn)
  (let ((info (lvn-vn-info env vn)))
    (and (pair? info) (eq? (car info) 'const))))

(define (lvn-vn-const-val env vn)
  (let ((info (lvn-vn-info env vn)))
    (if (and (pair? info) (eq? (car info) 'const))
        (cadr info)
        #f)))

(define (lvn-vn-is-pair? env vn)
  (let ((info (lvn-vn-info env vn)))
    (and (pair? info) (eq? (car info) 'pair))))

(define (lvn-vn-pair-car-vn env vn)
  (let ((info (lvn-vn-info env vn)))
    (if (and (pair? info) (eq? (car info) 'pair))
        (cadr info)
        #f)))

(define (lvn-vn-pair-cdr-vn env vn)
  (let ((info (lvn-vn-info env vn)))
    (if (and (pair? info) (eq? (car info) 'pair))
        (caddr info)
        #f)))

(define (lvn-invalidate-pairs env)
  (let* ((tuples (lvn-env-tuples env))
         (vns (lvn-env-vns env))
         (env1 (lvn-set-tuples env
                 (filter (lambda (entry)
                           (let ((key (car entry)))
                             (not (and (pair? key) (memq (car key) '(car cdr))))))
                         tuples)))
         (env2 (lvn-set-vns env1
                 (map (lambda (entry)
                        (let* ((vn (car entry))
                               (canon (cadr entry))
                               (info (cddr entry)))
                          (if (and (pair? info) (eq? (car info) 'pair))
                              (cons vn (cons canon '(type pair)))
                              entry)))
                      vns))))
    env2))

;;; -----------------------------------------------------------------------
;;; 2. Literal & Variable Value Evaluation
;;; -----------------------------------------------------------------------

(define (lvn-eval-const c env)
  (let* ((v (extract-const-val c))
         (key (list 'const v))
         (existing-vn (lvn-lookup-tuple env key)))
    (if existing-vn
        (list (val->ast-const v) existing-vn env)
        (let* ((alloc-res (lvn-alloc-vn env (val->ast-const v) (list 'const v)))
               (vn (car alloc-res))
               (env1 (cdr alloc-res))
               (env2 (lvn-record-tuple env1 key vn)))
          (list (val->ast-const v) vn env2)))))

(define (lvn-eval-var var env)
  (let ((entry (assq var (lvn-env-vars env))))
    (if entry
        (let* ((vn (cdr entry))
               (is-c (lvn-vn-is-const? env vn)))
          (if is-c
              ;; Constant propagation
              (list (val->ast-const (lvn-vn-const-val env vn)) vn env)
              (let ((canon-var (lvn-vn-canon-expr env vn)))
                ;; Copy propagation if canonical variable is currently in scope
                (if (and (symbol? canon-var)
                         (assq canon-var (lvn-env-vars env)))
                    (list canon-var vn env)
                    (list var vn env)))))
        ;; Unbound parameter / free variable entering scope
        (let* ((alloc-res (lvn-alloc-vn env var '()))
               (vn (car alloc-res))
               (env1 (cdr alloc-res))
               (env2 (lvn-bind-var env1 var vn)))
          (list var vn env2)))))

;;; -----------------------------------------------------------------------
;;; 3. Algebraic Simplification & Identity Normalization
;;; -----------------------------------------------------------------------

(define (lvn-try-algebraic-simplification op opt-args vn-args env)
  (let ((nargs (length opt-args)))
    (cond
      ((= nargs 2)
       (let* ((a1 (car opt-args))
              (a2 (cadr opt-args))
              (vn1 (car vn-args))
              (vn2 (cadr vn-args))
              (is-c1 (lvn-vn-is-const? env vn1))
              (c1 (if is-c1 (lvn-vn-const-val env vn1) #f))
              (is-c2 (lvn-vn-is-const? env vn2))
              (c2 (if is-c2 (lvn-vn-const-val env vn2) #f)))
         (case op
           ((+)
            (cond
              ;; (+ x 0) -> x
              ((and is-c2 (equal? c2 0))
               (list #t a1 vn1 env))
              ;; (+ 0 x) -> x
              ((and is-c1 (equal? c1 0))
               (list #t a2 vn2 env))
              (else (list #f #f #f env))))
           ((*)
            (cond
              ;; (* x 1) -> x
              ((and is-c2 (equal? c2 1))
               (list #t a1 vn1 env))
              ;; (* 1 x) -> x
              ((and is-c1 (equal? c1 1))
               (list #t a2 vn2 env))
              ;; (* x 0) -> 0
              ((and is-c2 (equal? c2 0))
               (let ((zero-res (lvn-eval-const 0 env)))
                 (list #t (car zero-res) (cadr zero-res) (caddr zero-res))))
              ;; (* 0 x) -> 0
              ((and is-c1 (equal? c1 0))
               (let ((zero-res (lvn-eval-const 0 env)))
                 (list #t (car zero-res) (cadr zero-res) (caddr zero-res))))
              (else (list #f #f #f env))))
           ((-)
            (cond
              ;; (- x 0) -> x
              ((and is-c2 (equal? c2 0))
               (list #t a1 vn1 env))
              ;; (- x x) -> 0
              ((= vn1 vn2)
               (let ((zero-res (lvn-eval-const 0 env)))
                 (list #t (car zero-res) (cadr zero-res) (caddr zero-res))))
              (else (list #f #f #f env))))
           ((= eq? eqv? char=? boolean=? symbol=?)
            (cond
              ;; (= x x) -> #t, (eq? x x) -> #t, (eqv? x x) -> #t
              ((= vn1 vn2)
               (let ((true-res (lvn-eval-const #t env)))
                 (list #t (car true-res) (cadr true-res) (caddr true-res))))
              (else (list #f #f #f env))))
           (else (list #f #f #f env)))))
      (else (list #f #f #f env)))))

;;; -----------------------------------------------------------------------
;;; 4. Immutable Pair Accessor Memoization
;;; -----------------------------------------------------------------------

(define (lvn-try-accessor-memoization op opt-args vn-args env)
  (let ((nargs (length opt-args)))
    (if (and (= nargs 1) (pure-accessor-op? op))
        (let* ((arg (car opt-args))
               (vn-p (car vn-args)))
          (cond
            ;; 1. Check if vn-p is known to be constructed by (cons vn-a vn-b)
            ((lvn-vn-is-pair? env vn-p)
             (let* ((target-vn (if (eq? op 'car)
                                   (lvn-vn-pair-car-vn env vn-p)
                                   (lvn-vn-pair-cdr-vn env vn-p)))
                    (canon (lvn-vn-canon-expr env target-vn)))
               (if (and (symbol? canon) (assq canon (lvn-env-vars env)))
                   (list #t canon target-vn env)
                   (if (lvn-vn-is-const? env target-vn)
                       (list #t (val->ast-const (lvn-vn-const-val env target-vn)) target-vn env)
                       (list #t canon target-vn env)))))
            ;; 2. Check if (op vn-p) was already memoized in this basic block / scope
            (else
             (let* ((tuple-key (list op vn-p))
                    (existing-vn (lvn-lookup-tuple env tuple-key)))
               (if existing-vn
                   (let ((canon (lvn-vn-canon-expr env existing-vn)))
                     (if (and (symbol? canon) (assq canon (lvn-env-vars env)))
                         (list #t canon existing-vn env)
                         (if (lvn-vn-is-const? env existing-vn)
                             (list #t (val->ast-const (lvn-vn-const-val env existing-vn)) existing-vn env)
                             (list #t (list op arg) existing-vn env))))
                   ;; Not yet memoized: allocate fresh VN and record (op vn-p)
                   (let* ((alloc-res (lvn-alloc-vn env (list op arg) '()))
                          (new-vn (car alloc-res))
                          (env1 (cdr alloc-res))
                          (env2 (lvn-record-tuple env1 tuple-key new-vn)))
                     (list #t (list op arg) new-vn env2)))))))
        (list #f #f #f env))))

;;; -----------------------------------------------------------------------
;;; 5. Type Predicate Folding
;;; -----------------------------------------------------------------------

(define (lvn-try-predicate-folding op opt-args vn-args env)
  (let ((nargs (length opt-args)))
    (if (and (= nargs 1) (type-predicate-op? op))
        (let* ((arg (car opt-args))
               (vn-x (car vn-args))
               (tuple-key (list op vn-x))
               (existing-vn (lvn-lookup-tuple env tuple-key)))
          (cond
            ;; 1. If (op vn-x) is already recorded as #t in dominance scope
            ((and existing-vn (equal? (lvn-vn-const-val env existing-vn) #t))
             (let ((true-res (lvn-eval-const #t env)))
               (list #t (car true-res) (cadr true-res) (caddr true-res))))
            ;; 2. Check if vn-x has known constant literal
            ((lvn-vn-is-const? env vn-x)
             (let* ((v (lvn-vn-const-val env vn-x))
                    (ans (case op
                           ((fixnum? integer? number?) (number? v))
                           ((pair?) (pair? v))
                           ((null?) (null? v))
                           ((boolean?) (boolean? v))
                           ((char?) (char? v))
                           ((symbol?) (symbol? v))
                           ((zero?) (and (number? v) (= v 0)))
                           (else #f)))
                    (ans-res (lvn-eval-const ans env)))
               (list #t (car ans-res) (cadr ans-res) (caddr ans-res))))
            ;; 3. Check if vn-x has known pair constructor
            ((lvn-vn-is-pair? env vn-x)
             (case op
               ((pair?)
                (let ((t-res (lvn-eval-const #t env)))
                  (list #t (car t-res) (cadr t-res) (caddr t-res))))
               ((null? fixnum? integer? number? boolean? char? symbol?)
                (let ((f-res (lvn-eval-const #f env)))
                  (list #t (car f-res) (cadr f-res) (caddr f-res))))
               (else (list #f #f #f env))))
            ;; 4. Check if producer was arithmetic (produces fixnum)
            ((let ((info (lvn-vn-info env vn-x)))
               (and (pair? info) (eq? (car info) 'type) (eq? (cadr info) 'fixnum)))
             (case op
               ((fixnum? integer? number?)
                (let ((t-res (lvn-eval-const #t env)))
                  (list #t (car t-res) (cadr t-res) (caddr t-res))))
               ((pair? null? boolean? char? symbol?)
                (let ((f-res (lvn-eval-const #f env)))
                  (list #t (car f-res) (cadr f-res) (caddr f-res))))
               (else (list #f #f #f env))))
            (else
             (list #f #f #f env))))
        (list #f #f #f env))))

;;; -----------------------------------------------------------------------
;;; 6. Call & Common Subexpression Elimination (CSE)
;;; -----------------------------------------------------------------------

(define (lvn-eval-call op opt-args vn-args env)
  ;; 1. Check if all args are constants -> Constant Folding via fold-const-op
  (let ((folded (if (let loop ((as opt-args))
                      (if (null? as) #t
                          (and (const? (car as)) (loop (cdr as)))))
                    (fold-const-op op opt-args)
                    #f)))
    (if folded
        (lvn-eval-const folded env)
        ;; 2. Try algebraic identities
        (let ((alg (lvn-try-algebraic-simplification op opt-args vn-args env)))
          (if (car alg)
              (cdr alg)
              ;; 3. Try accessor memoization
              (let ((acc (lvn-try-accessor-memoization op opt-args vn-args env)))
                (if (car acc)
                    (cdr acc)
                    ;; 4. Try type predicate folding
                    (let ((pred (lvn-try-predicate-folding op opt-args vn-args env)))
                      (if (car pred)
                          (cdr pred)
                          ;; 5. General CSE for pure primitives
                          (if (pure-prim? op)
                              (let* ((sorted-vns
                                      (if (and (commutative-op? op) (= (length vn-args) 2))
                                          (if (> (car vn-args) (cadr vn-args))
                                              (list (cadr vn-args) (car vn-args))
                                              vn-args)
                                          vn-args))
                                     (sorted-args
                                      (if (and (commutative-op? op) (= (length vn-args) 2))
                                          (if (> (car vn-args) (cadr vn-args))
                                              (list (cadr opt-args) (car opt-args))
                                              opt-args)
                                          opt-args))
                                     (tuple-key (cons op sorted-vns))
                                     (existing-vn (lvn-lookup-tuple env tuple-key)))
                                (if existing-vn
                                    (let ((canon (lvn-vn-canon-expr env existing-vn)))
                                      (if (and (symbol? canon) (assq canon (lvn-env-vars env)))
                                          (list canon existing-vn env)
                                          (if (lvn-vn-is-const? env existing-vn)
                                              (list (val->ast-const (lvn-vn-const-val env existing-vn)) existing-vn env)
                                              (list (cons op sorted-args) existing-vn env))))
                                    ;; Fresh pure tuple
                                    (let* ((ret-info
                                            (cond
                                              ((eq? op 'cons)
                                               (list 'pair (car sorted-vns) (cadr sorted-vns)))
                                              ((memq op '(+ - * modulo quotient fxadd1 fxsub1))
                                               (list 'type 'fixnum))
                                              (else '())))
                                           (alloc-res (lvn-alloc-vn env (cons op sorted-args) ret-info))
                                           (new-vn (car alloc-res))
                                           (env1 (cdr alloc-res))
                                           (env2 (if (eq? op 'cons)
                                                     env1
                                                     (lvn-record-tuple env1 tuple-key new-vn))))
                                      (list (cons op sorted-args) new-vn env2))))
                              ;; Non-pure or side-effecting call
                              (let* ((env1 (if (memq op '(set-car! set-cdr!))
                                               (lvn-invalidate-pairs env)
                                               env))
                                     (alloc-res (lvn-alloc-vn env1 (cons op opt-args) '()))
                                     (new-vn (car alloc-res))
                                     (env2 (cdr alloc-res)))
                                (list (cons op opt-args) new-vn env2))))))))))))

;;; -----------------------------------------------------------------------
;;; 7. Core Recursive Evaluator (lvn-eval)
;;; -----------------------------------------------------------------------
;;; Returns (list optimized-ast vn updated-env)

(define (lvn-eval expr env)
  (cond
    ((const? expr)
     (lvn-eval-const expr env))
    ((symbol? expr)
     (lvn-eval-var expr env))
    ((pair? expr)
     (let ((op (car expr)))
       (case op
         ((quote)
          (lvn-eval-const expr env))
         ((if)
          (let* ((test-res (lvn-eval (cadr expr) env))
                 (opt-test (car test-res))
                 (vn-test (cadr test-res))
                 (env-test (caddr test-res)))
            (cond
              ;; Constant condition pruning
              ((const? opt-test)
               (if (eq? (extract-const-val opt-test) #f)
                   (if (null? (cdddr expr))
                       (list #f vn-test env-test)
                       (lvn-eval (cadddr expr) env-test))
                   (lvn-eval (caddr expr) env-test)))
              (else
               ;; Branch-specialized dominance environment
               (let* ((then-env
                       (if (and (pair? opt-test) (type-predicate-op? (car opt-test)) (pair? (cdr opt-test)))
                           (let ((arg-entry (assq (cadr opt-test) (lvn-env-vars env-test))))
                             (if arg-entry
                                 (let* ((t-vn (cadr (lvn-eval-const #t env-test)))
                                        (e1 (lvn-record-tuple env-test (list (car opt-test) (cdr arg-entry)) t-vn)))
                                   (if (eq? (car opt-test) 'fixnum?)
                                       (let ((vns (cons (cons (cdr arg-entry) (cons (cadr opt-test) (list 'type 'fixnum)))
                                                        (filter (lambda (e) (not (eq? (car e) (cdr arg-entry))))
                                                                (lvn-env-vns e1)))))
                                         (lvn-set-vns e1 vns))
                                       e1))
                                 env-test))
                           env-test))
                      (then-res (lvn-eval (caddr expr) then-env))
                      (opt-then (car then-res))
                      (else-res (if (null? (cdddr expr))
                                    (list #f (cadr then-res) env-test)
                                    (lvn-eval (cadddr expr) env-test)))
                      (opt-else (car else-res))
                      (alloc-res (lvn-alloc-vn env-test (list 'if opt-test opt-then opt-else) '()))
                      (new-vn (car alloc-res))
                      (new-env (cdr alloc-res)))
                 (list (list 'if opt-test opt-then opt-else) new-vn new-env))))))
         ((let)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (cond
              ((null? bindings)
               (lvn-eval body env))
              ((= (length bindings) 1)
               (let* ((var (caar bindings))
                      (val (cadar bindings))
                      (val-res (lvn-eval val env))
                      (opt-val (car val-res))
                      (vn-val (cadr val-res))
                      (env-val (caddr val-res))
                      ;; Bind variable to vn-val
                      (env-body (lvn-bind-var env-val var vn-val))
                      (body-res (lvn-eval body env-body))
                      (opt-body (car body-res))
                      (vn-body (cadr body-res))
                      (orig-vars (lvn-env-vars env-val))
                      ;; Dead let elimination: pure binding whose var is unused in body
                      (dead? (and (atomic-expr? opt-val)
                                  (not (tree-contains? opt-body var)))))
                 (if dead?
                     (list opt-body vn-body (lvn-set-vars (caddr body-res) orig-vars))
                     (list (list 'let (list (list var opt-val)) opt-body)
                           vn-body
                           (lvn-set-vars (caddr body-res) orig-vars)))))
              (else
               ;; Multi-binding let: expand into nested single-binding lets
               (let ((nested-let
                      (let loop ((bs bindings))
                        (if (null? bs)
                            body
                            (list 'let (list (car bs)) (loop (cdr bs)))))))
                 (lvn-eval nested-let env))))))
         ((letrec)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 (opt-bindings
                  (map (lambda (b)
                         (list (car b) (lvn-expr (cadr b) (make-lvn-env))))
                       bindings))
                 (opt-body (lvn-expr body (make-lvn-env))))
            (list (list 'letrec opt-bindings opt-body) 0 env)))
         ((lambda)
          (let* ((params (cadr expr))
                 (body (caddr expr))
                 (child-env (let loop ((ps params) (cur-env (make-lvn-env)))
                              (if (null? ps)
                                  cur-env
                                  (let* ((p (car ps))
                                         (alloc (lvn-alloc-vn cur-env p '()))
                                         (vn (car alloc))
                                         (e1 (cdr alloc))
                                         (e2 (lvn-bind-var e1 p vn)))
                                    (loop (cdr ps) e2)))))
                 (body-res (lvn-eval body child-env))
                 (opt-body (car body-res))
                 (alloc-lam (lvn-alloc-vn env 'lambda-closure '()))
                 (lam-vn (car alloc-lam))
                 (env-lam (cdr alloc-lam)))
            (list (list 'lambda params opt-body) lam-vn env-lam)))
         ((begin)
          (let loop ((es (cdr expr)) (cur-env env) (acc '()))
            (if (null? es)
                (cond
                  ((null? acc) (list #f 0 cur-env))
                  ((null? (cdr acc)) (list (car acc) 0 cur-env))
                  (else (list (cons 'begin acc) 0 cur-env)))
                (let* ((res (lvn-eval (car es) cur-env))
                       (opt-e (car res))
                       (next-env (caddr res)))
                  (loop (cdr es) next-env (append acc (list opt-e)))))))
         ((%make-closure)
          (let* ((label (cadr expr))
                 (env-args (cddr expr))
                 (evaluated-args
                  (let loop ((as env-args) (cur-env env) (opt-acc '()) (vn-acc '()))
                    (if (null? as)
                        (list (reverse opt-acc) (reverse vn-acc) cur-env)
                        (let ((res (lvn-eval (car as) cur-env)))
                          (loop (cdr as)
                                (caddr res)
                                (cons (car res) opt-acc)
                                (cons (cadr res) vn-acc))))))
                 (opt-env-args (car evaluated-args))
                 (res-env (caddr evaluated-args))
                 (alloc-res (lvn-alloc-vn res-env '%make-closure '())))
            (list (cons '%make-closure (cons label opt-env-args))
                  (car alloc-res)
                  (cdr alloc-res))))
         (else
          ;; Primitive or function application: (op arg1 arg2 ...)
          (let* ((opt-op (if (symbol? op) op (car (lvn-eval op env))))
                 (args (cdr expr))
                 (evaluated-args
                  (let loop ((as args) (cur-env env) (opt-acc '()) (vn-acc '()))
                    (if (null? as)
                        (list (reverse opt-acc) (reverse vn-acc) cur-env)
                        (let ((res (lvn-eval (car as) cur-env)))
                          (loop (cdr as)
                                (caddr res)
                                (cons (car res) opt-acc)
                                (cons (cadr res) vn-acc))))))
                 (opt-args (car evaluated-args))
                 (vn-args (cadr evaluated-args))
                 (cur-env (caddr evaluated-args)))
            (if (symbol? opt-op)
                (lvn-eval-call opt-op opt-args vn-args cur-env)
                (let* ((call-expr (cons opt-op opt-args))
                       (alloc-res (lvn-alloc-vn cur-env call-expr '())))
                  (list call-expr (car alloc-res) (cdr alloc-res)))))))))
    (else
     (list expr 0 env))))

(define (lvn-expr expr env)
  (car (lvn-eval expr env)))

;;; -----------------------------------------------------------------------
;;; 8. Top-level Pass Entrypoint: lvn-all
;;; -----------------------------------------------------------------------

(define (lvn-all form)
  (cond
    ((not (pair? form)) form)
    ((eq? (car form) '%program)
     (let ((defs (cadr form))
           (main (caddr form)))
       (list '%program
             (map (lambda (d)
                    (if (and (pair? d) (eq? (car d) 'define))
                        (list 'define (cadr d) (lvn-expr (caddr d) (make-lvn-env)))
                        (lvn-expr d (make-lvn-env))))
                  defs)
             (lvn-expr main (make-lvn-env)))))
    ((eq? (car form) 'define)
     (list 'define (cadr form) (lvn-expr (caddr form) (make-lvn-env))))
    (else
     (lvn-expr form (make-lvn-env)))))
