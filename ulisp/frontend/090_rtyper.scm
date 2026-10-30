;;; =======================================================================
;;; ULisp Compiler Pass 5b: S-RTyper (Representation Typer & Unboxing Lowering)
;;; Conforms to DSN-33 Architecture Specification & Issue #518
;;; Note: Lowers high-level abstract types (inferred by S-Annotator Pass 4b)
;;;       to concrete hardware representations (%raw-i64, untagged registers).
;;;       Eliminates sar/sal tagging overhead in pure arithmetic loops and
;;;       inserts explicit boxing/unboxing boundaries at Scheme dynamic edges.
;;; =======================================================================

(define *unboxed-functions* (cons '() '()))
(define *unboxed-ret-functions* (cons '() '()))
(define *rtyper-facts* (cons '() '()))

(define (reset-rtyper!)
  (set-car! *unboxed-functions* '())
  (set-car! *unboxed-ret-functions* '())
  (set-car! *rtyper-facts* '()))

(define (record-rtyper-fact! var fact)
  (set-car! *rtyper-facts* (cons (cons var fact) (car *rtyper-facts*))))

(define (get-rtyper-fact var)
  (let ((e (assq var (car *rtyper-facts*))))
    (if e (cdr e) #f)))

(define (record-unboxed-fn! name)
  (set-car! *unboxed-functions* (cons name (car *unboxed-functions*))))

(define (unboxed-fn? name)
  (memq name (car *unboxed-functions*)))

(define (record-unboxed-ret-fn! name)
  (set-car! *unboxed-ret-functions* (cons name (car *unboxed-ret-functions*))))

(define (unboxed-ret-fn? name)
  (memq name (car *unboxed-ret-functions*)))

(define (unboxed-box-ret-call? op unboxed-fns)
  (let loop ((fs unboxed-fns))
    (cond
      ((null? fs) #f)
      ((and (pair? (car fs)) (eq? (caar fs) '%box-ret) (eq? (cdar fs) op)) #t)
      (else (loop (cdr fs))))))

(define (rtyper-raw-value-expr? expr raw-env)
  (cond
    ((symbol? expr) (raw-var? expr raw-env))
    ((not (pair? expr)) #f)
    ((memq (car expr) '(%raw-add %raw-sub %raw-mul %unbox-fixnum)) #t)
    ((and (symbol? (car expr)) (unboxed-ret-fn? (car expr))) #t)
    ((eq? (car expr) 'let)
     (rtyper-raw-value-expr? (caddr expr) raw-env))
    ((eq? (car expr) 'if)
     (and (rtyper-raw-value-expr? (caddr expr) raw-env)
          (pair? (cdddr expr))
          (rtyper-raw-value-expr? (cadddr expr) raw-env)))
    ((eq? (car expr) 'begin)
     (let loop ((es (cdr expr)))
       (if (null? (cdr es))
           (rtyper-raw-value-expr? (car es) raw-env)
           (loop (cdr es)))))
    (else #f)))

(define (raw-var? var raw-env)
  (memq var raw-env))

(define (fixnum-test-var test)
  (cond
    ((symbol? test)
     (let ((fact (get-rtyper-fact test)))
       (if fact (fixnum-test-var fact) #f)))
    ((and (pair? test) (memq (car test) '(fixnum? integer? number?)) (pair? (cdr test)) (symbol? (cadr test)))
     (cadr test))
    (else #f)))

(define (fold-type-pred op arg)
  (case op
    ((fixnum? integer? number?)
     (cond ((integer? arg) #t)
           ((or (string? arg) (boolean? arg) (null? arg) (pair? arg)) #f)
           (else 'unknown)))
    ((string?)
     (cond ((string? arg) #t)
           ((or (integer? arg) (boolean? arg) (null? arg) (pair? arg)) #f)
           (else 'unknown)))
    ((boolean?)
     (cond ((boolean? arg) #t)
           ((or (integer? arg) (string? arg) (null? arg) (pair? arg)) #f)
           (else 'unknown)))
    ((null?)
     (cond ((null? arg) #t)
           ((or (integer? arg) (string? arg) (boolean? arg) (pair? arg)) #f)
           (else 'unknown)))
    ((pair?)
     (cond ((pair? arg) #t)
           ((or (integer? arg) (string? arg) (boolean? arg) (null? arg)) #f)
           (else 'unknown)))
    ((zero?)
     (cond ((integer? arg) (if (= arg 0) #t #f))
           (else 'unknown)))
    (else 'unknown)))

(define (specialize-var-in-body body var val)
  (cond
    ((eq? body var) val)
    ((not (pair? body)) body)
    ((eq? (car body) 'quote) body)
    ;; Type predicate test on var
    ((and (memq (car body) '(fixnum? integer? number? string? boolean? null? pair? zero?))
          (pair? (cdr body))
          (eq? (cadr body) var))
     (let ((folded (fold-type-pred (car body) val)))
       (if (eq? folded 'unknown)
           (list (car body) (specialize-var-in-body (cadr body) var val))
           folded)))
    ;; Conditional branch pruning
    ((eq? (car body) 'if)
     (let* ((test (specialize-var-in-body (cadr body) var val))
            (then (specialize-var-in-body (caddr body) var val))
            (else-part (if (null? (cdddr body)) #f (specialize-var-in-body (cadddr body) var val))))
       (cond
         ((eq? test #t) then)
         ((eq? test #f) else-part)
         (else (list 'if test then else-part)))))
    (else
     (cons (specialize-var-in-body (car body) var val)
           (specialize-var-in-body (cdr body) var val)))))

(define (all-fixnum-params? params)
  (let loop ((ps params))
    (if (null? ps)
        #t
        (let ((t (get-var-type (car ps))))
          (if (and t (type-fixnum? t))
              (loop (cdr ps))
              #f)))))

;;; Checks whether fn-name is invoked in a non-tail position within expr
(define (non-tail-call-to? fn-name expr)
  (cond
    ((not (pair? expr)) #f)
    ((eq? (car expr) 'quote) #f)
    ((eq? (car expr) 'let)
     (or (occurs-in? fn-name (cadr expr))
         (non-tail-call-to? fn-name (caddr expr))))
    ((eq? (car expr) 'if)
     (let ((test (cadr expr))
           (then (caddr expr))
           (else-opt (if (null? (cdddr expr)) '() (cadddr expr))))
       (or (occurs-in? fn-name test)
           (non-tail-call-to? fn-name then)
           (if (null? else-opt) #f (non-tail-call-to? fn-name else-opt)))))
    ((eq? (car expr) 'begin)
     (let loop ((es (cdr expr)))
       (cond
         ((null? es) #f)
         ((null? (cdr es)) (non-tail-call-to? fn-name (car es)))
         (else (or (occurs-in? fn-name (car es))
                   (loop (cdr es)))))))
    (else
     (occurs-in? fn-name (cdr expr)))))

;;; Fast O(1) detection of pure tail-recursive loops (maximum depth 30)
(define (pure-tail-loop? fn-name lbody)
  (and (not (non-tail-call-to? fn-name lbody))
       (let loop-chk ((e lbody) (depth 0))
         (cond
           ((> depth 30) #f)
           ((not (pair? e)) #f)
           ((eq? (car e) fn-name) #t)
           ((eq? (car e) 'let)
            (loop-chk (caddr e) (+ depth 1)))
           ((eq? (car e) 'if)
            (let ((test (cadr e))
                  (then (caddr e))
                  (else-opt (if (null? (cdddr e)) '() (cadddr e))))
              (and (not (and (pair? test) (eq? (car test) fn-name)))
                   (or (loop-chk then (+ depth 1))
                       (if (null? else-opt) #f (loop-chk else-opt (+ depth 1)))))))
           (else #f)))))

;;; Pure integer recursive function analysis (Interprocedural Unboxing: int64_t -> int64_t)
(define (pure-int-atom? e int-vars)
  (or (integer? e)
      (and (symbol? e) (memq e int-vars))))

(define (pure-int-cmp-expr? e int-vars)
  (and (pair? e)
       (cond
         ((memq (car e) '(= < <= > >=))
          (and (= (length e) 3)
               (pure-int-atom? (cadr e) int-vars)
               (pure-int-atom? (caddr e) int-vars)))
         ((eq? (car e) 'zero?)
          (and (= (length e) 2)
               (pure-int-atom? (cadr e) int-vars)))
         (else #f))))

(define (pure-int-expr? expr fn-name int-vars bool-vars depth)
  (cond
    ((> depth 40) #f)
    ((integer? expr) #t)
    ((symbol? expr) (memq expr int-vars))
    ((not (pair? expr)) #f)
    (else
     (let ((op (car expr)))
       (cond
         ((eq? op 'if)
          (let ((test (cadr expr))
                (then (caddr expr))
                (else-opt (cdddr expr)))
            (and (pair? else-opt)
                 (or (and (symbol? test) (memq test bool-vars))
                     (pure-int-cmp-expr? test int-vars))
                 (pure-int-expr? then fn-name int-vars bool-vars (+ depth 1))
                 (pure-int-expr? (car else-opt) fn-name int-vars bool-vars (+ depth 1)))))
         ((eq? op 'let)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (let loop ((bs bindings) (ivs int-vars) (bvs bool-vars))
              (if (null? bs)
                  (pure-int-expr? body fn-name ivs bvs (+ depth 1))
                  (let* ((b (car bs))
                         (v (car b))
                         (rhs (cadr b)))
                    (cond
                      ((pure-int-cmp-expr? rhs ivs)
                       (loop (cdr bs) ivs (cons v bvs)))
                      ((pure-int-expr? rhs fn-name ivs bvs (+ depth 1))
                       (loop (cdr bs) (cons v ivs) bvs))
                      (else #f)))))))
         ((memq op '(+ - * %raw-add %raw-sub %raw-mul))
          (and (= (length expr) 3)
               (pure-int-expr? (cadr expr) fn-name int-vars bool-vars (+ depth 1))
               (pure-int-expr? (caddr expr) fn-name int-vars bool-vars (+ depth 1))))
         ((eq? op fn-name)
          (let loop ((as (cdr expr)))
            (if (null? as)
                #t
                (and (pure-int-expr? (car as) fn-name int-vars bool-vars (+ depth 1))
                     (loop (cdr as))))))
         (else #f))))))

(define (fn-escapes-in-expr? fn-name expr)
  (cond
    ((symbol? expr) (eq? expr fn-name))
    ((not (pair? expr)) #f)
    ((eq? (car expr) 'quote) #f)
    ((eq? (car expr) 'let)
     (or (let loop ((bs (cadr expr)))
           (if (null? bs) #f
               (or (fn-escapes-in-expr? fn-name (cadar bs))
                   (loop (cdr bs)))))
         (if (memq fn-name (map car* (cadr expr)))
             #f
             (fn-escapes-in-expr? fn-name (caddr expr)))))
    ((eq? (car expr) 'if)
     (or (fn-escapes-in-expr? fn-name (cadr expr))
         (fn-escapes-in-expr? fn-name (caddr expr))
         (if (null? (cdddr expr)) #f (fn-escapes-in-expr? fn-name (cadddr expr)))))
    ((eq? (car expr) 'begin)
     (let loop ((es (cdr expr)))
       (if (null? es) #f
           (or (fn-escapes-in-expr? fn-name (car es))
               (loop (cdr es))))))
    ((eq? (car expr) 'lambda)
     (if (memq fn-name (cadr expr))
         #f
         (occurs-in? fn-name (caddr expr))))
    (else
     (if (eq? (car expr) fn-name)
         (let loop ((as (cdr expr)))
           (if (null? as) #f
               (or (fn-escapes-in-expr? fn-name (car as))
                   (loop (cdr as)))))
         (or (fn-escapes-in-expr? fn-name (car expr))
             (let loop ((as (cdr expr)))
               (if (null? as) #f
                   (or (fn-escapes-in-expr? fn-name (car as))
                       (loop (cdr as))))))))))

(define (pure-int-recursive-fn? fn-name params lbody body)
  (and (pair? params)
       (all-fixnum-params? params)
       (occurs-in? fn-name lbody)
       (not (fn-escapes-in-expr? fn-name lbody))
       (not (fn-escapes-in-expr? fn-name body))
       (pure-int-expr? lbody fn-name params '() 0)))

;;; Ensures integer constants at exit branches of an unboxed-return function are raw
(define (unbox-const-exit expr)
  (cond
    ((integer? expr)
     (list '%unbox-fixnum expr))
    ((not (pair? expr))
     expr)
    ((eq? (car expr) 'if)
     (let ((test (cadr expr))
           (then (caddr expr))
           (else-part (if (null? (cdddr expr)) '() (cadddr expr))))
       (list 'if test
             (unbox-const-exit then)
             (if (null? else-part) '() (unbox-const-exit else-part)))))
    ((eq? (car expr) 'let)
     (list 'let (cadr expr) (unbox-const-exit (caddr expr))))
    ((eq? (car expr) 'begin)
     (let loop ((rest (cdr expr)) (acc '()))
       (if (null? (cdr rest))
           (cons 'begin (append (reverse acc) (list (unbox-const-exit (car rest)))))
           (loop (cdr rest) (cons (car rest) acc)))))
    (else expr)))

;;; Traverses loop body to box any raw loop-variable returned at loop exit boundaries
(define (box-raw-exit expr raw-vars fn-name)
  (cond
    ((not (pair? expr))
     (if (and (symbol? expr) (memq expr raw-vars))
         (list '%box-fixnum expr)
         expr))
    ((eq? (car expr) fn-name)
     ;; Tail-recursive loop jump: keep unboxed raw integers
     expr)
    ((eq? (car expr) '%box-fixnum)
     expr)
    ((memq (car expr) '(%raw-add %raw-sub %raw-mul))
     (list '%box-fixnum expr))
    ((eq? (car expr) 'if)
     (let ((test (cadr expr))
           (then (caddr expr))
           (else-part (if (null? (cdddr expr)) '() (cadddr expr))))
       (list 'if test
             (box-raw-exit then raw-vars fn-name)
             (if (null? else-part) '() (box-raw-exit else-part raw-vars fn-name)))))
    ((eq? (car expr) 'let)
     (let ((bindings (cadr expr))
           (body (caddr expr)))
       (list 'let bindings (box-raw-exit body raw-vars fn-name))))
    ((eq? (car expr) 'begin)
     (let ((stmts (cdr expr)))
       (let loop ((rest stmts) (acc '()))
         (if (null? (cdr rest))
             (cons 'begin (append (reverse acc) (list (box-raw-exit (car rest) raw-vars fn-name))))
             (loop (cdr rest) (cons (car rest) acc))))))
    (else
     expr)))

;;; Lowers binary arithmetic operators to raw integer primitives when operands are raw
(define (rtyper-binop op e1 e2 raw-env)
  (cond
    ((memq op '(+ - *))
     (let ((raw1? (or (integer? e1) (and (symbol? e1) (raw-var? e1 raw-env))))
           (raw2? (or (integer? e2) (and (symbol? e2) (raw-var? e2 raw-env)))))
       (if (and raw1? raw2?)
           (case op
             ((+) (list '%raw-add e1 e2))
             ((-) (list '%raw-sub e1 e2))
             ((*) (list '%raw-mul e1 e2)))
           (list op e1 e2))))
    ((memq op '(= < <= > >=))
     (let ((raw1? (and (symbol? e1) (raw-var? e1 raw-env)))
           (raw2? (and (symbol? e2) (raw-var? e2 raw-env))))
       (cond
         ((and raw1? (integer? e2))
          (list op e1 (list '%unbox-fixnum e2)))
         ((and (integer? e1) raw2?)
          (list op (list '%unbox-fixnum e1) e2))
         (else
          (list op e1 e2)))))
    (else
     (list op e1 e2))))

;;; Recursively rewrites ANF AST to Typed LIR representation
(define (rtyper-expr-scoped expr raw-env unboxed-fns)
    (cond
      ((not (pair? expr)) expr)
    (else
     (let ((op (car expr)))
       (cond
         ((eq? op 'quote) expr)
         ((eq? op 'if)
          (let* ((test (cadr expr))
                 (then (caddr expr))
                 (else-expr (if (null? (cdddr expr)) '() (cadddr expr)))
                 (fvar (fixnum-test-var test)))
            (if (and fvar (not (raw-var? fvar raw-env)) (expr-has-arithmetic-on-var? then fvar))
                ;; Flow-sensitive narrowing: fvar is proven to be Fixnum in then-branch!
                ;; Unbox fvar at the then-branch boundary and lower internal arithmetic to raw ops.
                (let* ((then-raw-env (cons fvar raw-env))
                       (lowered-then (rtyper-expr-scoped then then-raw-env unboxed-fns))
                       (boxed-then (if (and (pair? lowered-then)
                                            (memq (car lowered-then) '(%raw-add %raw-sub %raw-mul)))
                                       (list '%box-fixnum lowered-then)
                                       (box-raw-exit lowered-then (list fvar) '%no-fn)))
                       (unboxed-then (list 'let (list (list fvar (list '%unbox-fixnum fvar))) boxed-then))
                       (r-test (rtyper-expr-scoped test raw-env unboxed-fns))
                       (r-else (if (null? else-expr) '() (rtyper-expr-scoped else-expr raw-env unboxed-fns))))
                  (if (null? r-else)
                      (list 'if r-test unboxed-then)
                      (list 'if r-test unboxed-then r-else)))
                ;; Standard if
                (let ((r-test (rtyper-expr-scoped test raw-env unboxed-fns))
                      (r-then (rtyper-expr-scoped then raw-env unboxed-fns))
                      (r-else (if (null? else-expr) '() (rtyper-expr-scoped else-expr raw-env unboxed-fns))))
                  (if (null? r-else)
                      (list 'if r-test r-then)
                      (list 'if r-test r-then r-else))))))
         ((eq? op 'begin)
          (cons 'begin (map (lambda (e) (rtyper-expr-scoped e raw-env unboxed-fns)) (cdr expr))))
         ((memq op '(let letrec))
          (let* ((bindings (cadr expr))
                 (body (caddr expr)))
            (cond
              ;; Path Splitting (合流点メッセージ分割 / Chambers & Ungar 1989):
              ;; When single binding is (v (if cond e1 e2)) and body has conditional/pred on v:
              ((and (eq? op 'let)
                    (= (length bindings) 1)
                    (pair? (cadar bindings))
                    (eq? (car (cadar bindings)) 'if)
                    (<= (expr-size body) 40)
                    (let ((var (caar bindings)))
                      (expr-has-conditional-or-pred-on-var? body var)))
               (let* ((b (car bindings))
                      (var (car b))
                      (if-expr (cadr b))
                      (cond-part (cadr if-expr))
                      (e1 (caddr if-expr))
                      (e2 (if (null? (cdddr if-expr)) #f (cadddr if-expr)))
                      ;; Specialize body along both paths
                      (spec-then (specialize-var-in-body body var e1))
                      (spec-else (specialize-var-in-body body var e2))
                      (split-then (rtyper-expr-scoped (list 'let (list (list var e1)) spec-then) raw-env unboxed-fns))
                      (split-else (rtyper-expr-scoped (list 'let (list (list var e2)) spec-else) raw-env unboxed-fns)))
                 (list 'if (rtyper-expr-scoped cond-part raw-env unboxed-fns) split-then split-else)))
              ((and (= (length bindings) 1)
                    (let* ((b (car bindings))
                           (val (cadr b)))
                      (and (pair? val)
                           (eq? (car val) 'lambda)
                           (pair? (cadr val))
                           (all-fixnum-params? (cadr val))
                           (pure-tail-loop? (car b) (caddr val)))))
               ;; Named-let loop with 100% fixnum parameters and pure tail-recursion:
               ;; Lower all loop variables to raw %raw-i64 hardware representation.
               ;; Lexically scope fn-name to its definition body and continuation.
               (let* ((b (car bindings))
                      (fn-name (car b))
                      (fn-val (cadr b))
                      (params (cadr fn-val))
                      (lbody (caddr fn-val))
                      (loop-raw-env (append params raw-env))
                      (inner-unboxed-fns (cons fn-name unboxed-fns)))
                 (record-unboxed-fn! fn-name)
                 (let* ((typed-lbody (rtyper-expr-scoped lbody loop-raw-env inner-unboxed-fns))
                        (boxed-lbody (box-raw-exit typed-lbody params fn-name))
                        (new-fn-val (list 'lambda params boxed-lbody))
                        (new-body (rtyper-expr-scoped body raw-env inner-unboxed-fns)))
                   (list op (list (list fn-name new-fn-val)) new-body))))
              ((and (eq? op 'letrec)
                    (= (length bindings) 1)
                    (let* ((b (car bindings))
                           (val (cadr b)))
                      (and (pair? val)
                           (eq? (car val) 'lambda)
                           (pure-int-recursive-fn? (car b) (cadr val) (caddr val) body))))
               ;; Interprocedural Unboxing (int64_t -> int64_t) for general pure integer recursive functions (e.g. fib, ack)
               (let* ((b (car bindings))
                      (fn-name (car b))
                      (fn-val (cadr b))
                      (params (cadr fn-val))
                      (lbody (caddr fn-val))
                      (loop-raw-env (append params raw-env))
                      (inner-unboxed-fns (cons fn-name unboxed-fns)))
                 (record-unboxed-fn! fn-name)
                 (record-unboxed-ret-fn! fn-name)
                 (let* ((typed-lbody (rtyper-expr-scoped lbody loop-raw-env inner-unboxed-fns))
                        (raw-lbody (unbox-const-exit typed-lbody))
                        (new-fn-val (list 'lambda params raw-lbody))
                        (ext-unboxed-fns (cons (cons '%box-ret fn-name) unboxed-fns))
                        (new-body (rtyper-expr-scoped body raw-env ext-unboxed-fns)))
                   (list op (list (list fn-name new-fn-val)) new-body))))
              (else
               ;; Standard let bindings: propagate raw variables and record facts
               (let* ((new-bindings
                       (map (lambda (b)
                              (let ((v (car b)) (rhs (cadr b)))
                                (if (and (pair? rhs) (memq (car rhs) '(fixnum? integer? number?))
                                         (pair? (cdr rhs)) (symbol? (cadr rhs)))
                                    (record-rtyper-fact! v (cadr rhs)))
                                (list v (rtyper-expr-scoped rhs raw-env unboxed-fns))))
                            bindings))
                      ;; Extend raw-env with newly bound variables that hold raw values
                      (extended-raw-env
                       (let loop ((bs new-bindings) (acc raw-env))
                         (if (null? bs) acc
                             (let* ((b (car bs))
                                    (var (car b))
                                    (val (cadr b)))
                               (if (rtyper-raw-value-expr? val acc)
                                   (loop (cdr bs) (cons var acc))
                                   (loop (cdr bs) acc))))))
                      (new-body (rtyper-expr-scoped body extended-raw-env unboxed-fns)))
                 (list op new-bindings new-body))))))
         ((eq? op '-)
          (if (null? (cddr expr))
              (list '- (rtyper-expr-scoped (cadr expr) raw-env unboxed-fns))
              (rtyper-binop op (rtyper-expr-scoped (cadr expr) raw-env unboxed-fns) (rtyper-expr-scoped (caddr expr) raw-env unboxed-fns) raw-env)))
         ((binop-prim? op)
          (rtyper-binop op (rtyper-expr-scoped (cadr expr) raw-env unboxed-fns) (rtyper-expr-scoped (caddr expr) raw-env unboxed-fns) raw-env))
         ((unboxed-box-ret-call? op unboxed-fns)
          ;; External boundary call into an unboxed-return function: unbox args and box result
          (let ((args (cdr expr)))
            (list '%box-fixnum
                  (cons op
                        (map (lambda (arg)
                               (if (and (symbol? arg) (raw-var? arg raw-env))
                                   arg
                                   (list '%unbox-fixnum (rtyper-expr-scoped arg raw-env unboxed-fns))))
                             args)))))
         ((memq op unboxed-fns)
          ;; Boundary call into an unboxed loop: unbox non-raw arguments at entry
          (let ((args (cdr expr)))
            (cons op
                  (map (lambda (arg)
                         (if (and (symbol? arg) (raw-var? arg raw-env))
                             arg
                             (list '%unbox-fixnum (rtyper-expr-scoped arg raw-env unboxed-fns))))
                       args))))
         (else
          ;; General procedure call or syntax
          (cons op (map (lambda (e) (rtyper-expr-scoped e raw-env unboxed-fns)) (cdr expr)))))))))


(define (rtyper-expr expr raw-env)
  (rtyper-expr-scoped expr raw-env '()))

;;; Pass 5b Entrypoint: Transforms S-Annotated AST into Lowered Typed AST
(define (rtyper-all form-or-forms)
  (reset-rtyper!)
  (cond
    ((null? form-or-forms) '())
    ((not (pair? form-or-forms)) form-or-forms)
    ((eq? (car form-or-forms) '%program)
     (let ((defs (cadr form-or-forms))
           (main (caddr form-or-forms)))
       (list '%program
             (map (lambda (d)
                    (if (and (pair? d) (eq? (car d) 'define))
                        (list 'define (cadr d) (rtyper-expr-scoped (caddr d) '() '()))
                        (rtyper-expr-scoped d '() '())))
                  defs)
             (rtyper-expr-scoped main '() '()))))
    ((eq? (car form-or-forms) 'define)
     (let ((head (cadr form-or-forms))
           (body (cddr form-or-forms)))
       (cons 'define
             (cons head
                   (map (lambda (e) (rtyper-expr-scoped e '() '())) body)))))
    (else
     (rtyper-expr-scoped form-or-forms '() '()))))
