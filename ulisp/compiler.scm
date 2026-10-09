;;; =======================================================================
;;; ULisp Compiler Pass 0: Common Helpers & Primitive Predicates
;;; Conforms to DSN-33 Architecture Specification
;;; =======================================================================

;;; Standard Helper Procedures (Self-hosting primitives)
(define (fixnum->char n) (integer->char n))
(define (char->fixnum c) (char->integer c))
(define (safe-car x) (if (pair? x) (car x) '()))
(define (safe-cdr x) (if (pair? x) (cdr x) '()))

(define (car* x) (car x))
(define (cadr x) (safe-car (safe-cdr x)))
(define (cddr x) (safe-cdr (safe-cdr x)))
(define (cdar x) (safe-cdr (safe-car x)))
(define (caar x) (safe-car (safe-car x)))
(define (caddr x) (safe-car (safe-cdr (safe-cdr x))))
(define (cdddr x) (safe-cdr (safe-cdr (safe-cdr x))))
(define (cadar x) (safe-car (safe-cdr (safe-car x))))
(define (cadddr x) (safe-car (safe-cdr (safe-cdr (safe-cdr x)))))

(define (memq item ls)
  (cond
    ((not (pair? ls)) #f)
    ((eq? (car ls) item) ls)
    (else (memq item (cdr ls)))))

(define (assq item ls)
  (cond
    ((not (pair? ls)) #f)
    ((not (pair? (car ls))) (assq item (cdr ls)))
    ((eq? (caar ls) item) (car ls))
    (else (assq item (cdr ls)))))

(define (length ls)
  (let loop ((l ls) (n 0))
    (if (null? l)
        n
        (loop (cdr l) (+ n 1)))))

(define (reverse ls)
  (let loop ((l ls) (acc '()))
    (if (null? l)
        acc
        (loop (cdr l) (cons (car l) acc)))))

(define (append l1 l2)
  (if (null? l1)
      l2
      (cons (car l1) (append (cdr l1) l2))))

(define (map f ls)
  (if (null? ls)
      '()
      (cons (f (car ls)) (map f (cdr ls)))))

(define (for-each proc ls)
  (if (not (null? ls))
      (begin
        (proc (car ls))
        (for-each proc (cdr ls)))))

(define (filter pred ls)
  (cond
    ((null? ls) '())
    ((pred (car ls)) (cons (car ls) (filter pred (cdr ls))))
    (else (filter pred (cdr ls)))))

(define (error msg val)
  (display msg)
  (display " ")
  (display val)
  (newline)
  val)

;;; Deterministic symbol counter for unique variable generation
(define *symbol-counter* (cons 0 '()))
(define (unique-symbol prefix)
  (let ((s (string->symbol (string-append prefix (number->string (car *symbol-counter*))))))
    (set-car! *symbol-counter* (+ (car *symbol-counter*) 1))
    s))

;;; Deterministic label counter for assembly and lifted function labels
(define *label-counter* (cons 0 '()))
(define (unique-label prefix)
  (let ((l (string-append "." prefix "_" (number->string (car *label-counter*)))))
    (set-car! *label-counter* (+ (car *label-counter*) 1))
    l))
(define (unique-label-sym prefix)
  (string->symbol (unique-label prefix)))

;;; Set operations for variable scope analysis
(define (set-diff s1 s2)
  (cond
    ((null? s1) '())
    ((memq (car s1) s2) (set-diff (cdr s1) s2))
    (else (cons (car s1) (set-diff (cdr s1) s2)))))

(define (set-union s1 s2)
  (cond
    ((null? s1) s2)
    ((memq (car s1) s2) (set-union (cdr s1) s2))
    (else (cons (car s1) (set-union (cdr s1) s2)))))

(define (has-symbol? datum)
  (cond
    ((symbol? datum) #t)
    ((pair? datum)
     (or (has-symbol? (car datum))
         (has-symbol? (cdr datum))))
    (else #f)))

;;; Primitive procedure categorization predicates
(define (zero-arg-prim? op)
  (memq op '(read-char peek-char)))

(define (unary-prim? op)
  (memq op '(fxadd1 fxsub1 fixnum->char char->fixnum integer->char char->integer
             integer->symbol symbol->integer
             zero? fixnum? integer? number? boolean? char? null? not symbol?
             car cdr pair? procedure? string?
             write-char eof-object?
             make-string string-length)))

(define (binop-prim? op)
  (memq op '(+ - * = < <= > >= modulo quotient / string-ref cons set-car! set-cdr! eq? char=? %closure-ref)))

(define (triop-prim? op)
  (memq op '(string-set! %closure-set!)))

(define (closure-prim? op)
  (memq op '(%make-closure %closure-ref %closure-set!)))

(define (pure-prim? op)
  (memq op '(fxadd1 fxsub1 fixnum->char char->fixnum integer->char char->integer
             integer->symbol symbol->integer
             zero? fixnum? integer? number? boolean? char? null? not symbol?
             car cdr pair? procedure? string? string-length
             + - * = < <= > >= modulo quotient / eq? char=? %closure-ref)))

(define (const? x)
  (or (number? x)
      (boolean? x)
      (char? x)
      (null? x)
      (and (pair? x) (eq? (car x) 'quote))))

(define (atomic-expr? expr)
  (or (symbol? expr)
      (const? expr)))
;;; =======================================================================
;;; ULisp Compiler Pass 1: Syntax Desugaring & Normalization Pass
;;; Conforms to DSN-33 Architecture Specification
;;; =======================================================================

(define (desugar-list args)
  (if (null? args)
      ''()
      (cons 'cons (cons (car args) (cons (desugar-list (cdr args)) '())))))

(define (desugar-string-append args)
  (cond
    ((null? args) "")
    ((null? (cdr args)) (car args))
    (else
     (list 'string-append2 (car args) (desugar-string-append (cdr args))))))

(define (desugar-cond clauses)
  (if (null? clauses)
      #f
      (let ((c (car clauses)))
        (if (eq? (car c) 'else)
            (cons 'begin (cdr c))
            (list 'if (car c)
                  (cons 'begin (cdr c))
                  (desugar-cond (cdr clauses)))))))

(define (desugar-case key clauses)
  (let ((k-var (unique-symbol "case_key_")))
    (list 'let (list (list k-var key))
          (let loop ((cls clauses))
            (if (null? cls)
                #f
                (let ((c (car cls)))
                  (if (eq? (car c) 'else)
                      (cons 'begin (cdr c))
                      (list 'if (list 'memq k-var (list 'quote (car c)))
                            (cons 'begin (cdr c))
                            (loop (cdr cls))))))))))

(define (make-body-expr bodies)
  (cond
    ((null? bodies) (list 'begin))
    ((null? (cdr bodies)) (car bodies))
    (else (cons 'begin bodies))))

(define (desugar-let* bindings bodies)
  (if (null? bindings)
      (make-body-expr bodies)
      (list 'let (list (car bindings))
            (desugar-let* (cdr bindings) bodies))))

(define (desugar-named-let expr)
  (let* ((name (cadr expr))
         (bindings (caddr expr))
         (bodies (cdddr expr))
         (params (map car* bindings))
         (inits (map cadr bindings)))
    (list 'letrec
          (list (list name (cons 'lambda (cons params bodies))))
          (cons name inits))))

(define (desugar-and args)
  (cond
    ((null? args) #t)
    ((null? (cdr args)) (car args))
    (else
     (list 'if (car args) (desugar-and (cdr args)) #f))))

(define (desugar-or args)
  (cond
    ((null? args) #f)
    ((null? (cdr args)) (car args))
    (else
     (let ((tmp (unique-symbol "or_tmp_")))
       (list 'let (list (list tmp (car args)))
             (list 'if tmp tmp (desugar-or (cdr args))))))))

(define (rewrite-top-level forms)
  (let loop ((fs forms) (bindings '()) (bodies '()))
    (if (null? fs)
        (if (null? bindings)
            (make-body-expr (reverse bodies))
            (list 'letrec (reverse bindings) (make-body-expr (reverse bodies))))
        (let ((f (car fs)))
          (if (and (pair? f) (eq? (car f) 'define))
              (let ((def-spec (cadr f)))
                (if (pair? def-spec)
                    ;; (define (name . params) . body)
                    (let ((name (car def-spec))
                          (params (cdr def-spec))
                          (lbody (cddr f)))
                      (loop (cdr fs)
                            (cons (list name (cons 'lambda (cons params lbody))) bindings)
                            bodies))
                    ;; (define name val)
                    (let ((name def-spec)
                          (val (caddr f)))
                      (loop (cdr fs)
                            (cons (list name val) bindings)
                            bodies))))
              ;; Normal expression
              (loop (cdr fs) bindings (cons f bodies)))))))

;;; Pass 1: Canonical AST Desugaring Pass
;;; Recursively transforms an AST so that all high-level syntactic sugar
;;; (cond, case, let*, named-let, and, or, string-append, list) is expanded
;;; into canonical Core Scheme constructs (if, let, letrec, lambda, begin, primitives).
(define (desugar-all expr)
  (cond
    ((not (pair? expr)) expr)
    (else
     (let ((op (car expr)))
       (case op
         ((quote)
          expr)
         ((cond)
          (desugar-all (desugar-cond (cdr expr))))
         ((case)
          (desugar-all (desugar-case (cadr expr) (cddr expr))))
         ((let*)
          (desugar-all (desugar-let* (cadr expr) (cddr expr))))
         ((string-append)
          (desugar-all (desugar-string-append (cdr expr))))
         ((list)
          (desugar-all (desugar-list (cdr expr))))
         ((and)
          (desugar-all (desugar-and (cdr expr))))
         ((or)
          (desugar-all (desugar-or (cdr expr))))
         ((let)
          (if (symbol? (cadr expr))
              (desugar-all (desugar-named-let expr))
              (let ((bindings (cadr expr))
                    (bodies (cddr expr)))
                (list 'let
                      (map (lambda (b) (list (car b) (desugar-all (cadr b)))) bindings)
                      (desugar-all (make-body-expr bodies))))))
         ((letrec)
          (let ((bindings (cadr expr))
                (bodies (cddr expr)))
            (list 'letrec
                  (map (lambda (b) (list (car b) (desugar-all (cadr b)))) bindings)
                  (desugar-all (make-body-expr bodies)))))
         ((lambda)
          (let ((params (cadr expr))
                (bodies (cddr expr)))
            (list 'lambda params (desugar-all (make-body-expr bodies)))))
         ((if)
          (let ((test (desugar-all (cadr expr)))
                (then (desugar-all (caddr expr)))
                (else-expr (if (null? (cdddr expr))
                               #f
                               (desugar-all (cadddr expr)))))
            (list 'if test then else-expr)))
         ((begin)
          (cons 'begin (map desugar-all (cdr expr))))
         (else
          (cons (desugar-all op) (map desugar-all (cdr expr)))))))))
;;; =======================================================================
;;; ULisp Compiler Pass 2: Static Scope & Free-Variable Analysis Pass
;;; Conforms to DSN-33 Architecture Specification
;;; Note: Operates strictly on Canonical Core AST produced by Pass 1 (desugar-all)
;;; =======================================================================

;;; Extracts the list of free variables in canonical `expr` given currently bound variables `bound`.
(define (free-vars expr bound)
  (cond
    ((symbol? expr)
     (if (memq expr bound) '() (list expr)))
    ((pair? expr)
     (let ((op (car expr)))
       (case op
         ((quote)
          (if (has-symbol? (cadr expr))
              (if (memq 'string->symbol bound) '() '(string->symbol))
              '()))
         ((if)
          (set-union (free-vars (cadr expr) bound)
                     (set-union (free-vars (caddr expr) bound)
                                (if (null? (cdddr expr)) '() (free-vars (cadddr expr) bound)))))
         ((begin)
          (let loop ((es (cdr expr)) (acc '()))
            (if (null? es) acc
                (loop (cdr es) (set-union acc (free-vars (car es) bound))))))
         ((let)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 (new-bound (set-union (map car* bindings) bound))
                 (val-frees (let loop ((bs bindings) (acc '()))
                              (if (null? bs) acc
                                  (loop (cdr bs) (set-union acc (free-vars (cadar bs) bound)))))))
            (set-union val-frees (free-vars body new-bound))))
         ((letrec)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 (new-bound (set-union (map car* bindings) bound)))
            (let loop ((bs bindings) (acc (free-vars body new-bound)))
              (if (null? bs) acc
                  (loop (cdr bs) (set-union acc (free-vars (cadar bs) new-bound)))))))
         ((lambda)
          (let* ((params (cadr expr))
                 (body (caddr expr))
                 (new-bound (set-union params bound)))
            (free-vars body new-bound)))
         ((%make-closure)
          (let loop ((es (cddr expr)) (acc '()))
            (if (null? es) acc
                (loop (cdr es) (set-union acc (free-vars (car es) bound))))))
         (else
          (cond
            ((zero-arg-prim? op) '())
            ((or (unary-prim? op) (or (binop-prim? op) (triop-prim? op)))
             (let loop ((es (cdr expr)) (acc '()))
               (if (null? es) acc
                   (loop (cdr es) (set-union acc (free-vars (car es) bound))))))
            (else
             (let loop ((es expr) (acc '()))
               (if (null? es) acc
                   (loop (cdr es) (set-union acc (free-vars (car es) bound)))))))))))
    (else '())))
;;; =======================================================================
;;; ULisp Compiler Pass 3: CP0 Source-Level Optimization Nanopass
;;; Conforms to DSN-33 Architecture Specification
;;; Note: Performs Constant Folding, Dead Branch Pruning, and Dead Let
;;;       Elimination on Canonical Core AST.
;;; =======================================================================

;;; Extracts the literal constant value from a constant AST node
(define (extract-const-val c)
  (if (and (pair? c) (eq? (car c) 'quote))
      (cadr c)
      c))

;;; Wraps a literal value back into a canonical constant AST node
(define (val->ast-const v)
  (cond
    ((number? v) v)
    ((boolean? v) v)
    ((char? v) v)
    ((null? v) '(quote ()))
    (else (list 'quote v))))

;;; Checks if an expression is completely side-effect free (pure)
(define (pure-expr? expr)
  (cond
    ((atomic-expr? expr) #t)
    ((pair? expr)
     (let ((op (car expr)))
       (case op
         ((quote) #t)
         ((lambda) #t)
         ((if) (and (pure-expr? (cadr expr))
                    (pure-expr? (caddr expr))
                    (if (null? (cdddr expr)) #t (pure-expr? (cadddr expr)))))
         ((begin)
          (let loop ((es (cdr expr)))
            (if (null? es) #t
                (and (pure-expr? (car es)) (loop (cdr es))))))
         ((let)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (and (let loop ((bs bindings))
                   (if (null? bs) #t
                       (and (pure-expr? (cadar bs)) (loop (cdr bs)))))
                 (pure-expr? body))))
         (else
          (and (pure-prim? op)
               (let loop ((args (cdr expr)))
                 (if (null? args) #t
                     (and (pure-expr? (car args)) (loop (cdr args))))))))))
    (else #f)))

;;; Tries to fold a constant binary or unary operation
(define (fold-const-op op args)
  (let ((nargs (length args)))
    (cond
      ;; Unary arithmetic / predicates
      ((and (= nargs 1) (const? (car args)))
       (let ((v (extract-const-val (car args))))
         (case op
           ((fxadd1) (if (number? v) (val->ast-const (+ v 1)) #f))
           ((fxsub1) (if (number? v) (val->ast-const (- v 1)) #f))
           ((zero?) (if (number? v) (val->ast-const (= v 0)) #f))
           ((not) (val->ast-const (if (eq? v #f) #t #f)))
           ((null?) (val->ast-const (null? v)))
           ((pair?) (val->ast-const (pair? v)))
           ((number? fixnum? integer?) (val->ast-const (number? v)))
           ((boolean?) (val->ast-const (boolean? v)))
           ((char?) (val->ast-const (char? v)))
           ((symbol?) (val->ast-const (symbol? v)))
           ((car) (if (pair? v) (val->ast-const (car v)) #f))
           ((cdr) (if (pair? v) (val->ast-const (cdr v)) #f))
           (else #f))))
      ;; Binary arithmetic / predicates
      ((and (= nargs 2) (const? (car args)) (const? (cadr args)))
       (let ((v1 (extract-const-val (car args)))
             (v2 (extract-const-val (cadr args))))
         (case op
           ((+) (if (and (number? v1) (number? v2)) (val->ast-const (+ v1 v2)) #f))
           ((-) (if (and (number? v1) (number? v2)) (val->ast-const (- v1 v2)) #f))
           ((*) (if (and (number? v1) (number? v2)) (val->ast-const (* v1 v2)) #f))
           ((quotient /)
            (if (and (number? v1) (number? v2) (not (= v2 0)))
                (val->ast-const (quotient v1 v2))
                #f))
           ((modulo)
            (if (and (number? v1) (number? v2) (not (= v2 0)))
                (val->ast-const (modulo v1 v2))
                #f))
           ((=) (if (and (number? v1) (number? v2)) (val->ast-const (= v1 v2)) #f))
           ((<) (if (and (number? v1) (number? v2)) (val->ast-const (< v1 v2)) #f))
           ((<=) (if (and (number? v1) (number? v2)) (val->ast-const (<= v1 v2)) #f))
           ((>) (if (and (number? v1) (number? v2)) (val->ast-const (> v1 v2)) #f))
           ((>=) (if (and (number? v1) (number? v2)) (val->ast-const (>= v1 v2)) #f))
           ((eq?) (val->ast-const (eq? v1 v2)))
           ((char=?) (if (and (char? v1) (char? v2)) (val->ast-const (char=? v1 v2)) #f))
           ((cons) (val->ast-const (cons v1 v2)))
           (else #f))))
      (else #f))))

;;; Bottom-up CP0 optimization of a single expression
(define (cp0-expr expr)
  (cond
    ((not (pair? expr)) expr)
    (else
     (let ((op (car expr)))
       (case op
         ((quote) expr)
         ((if)
          (let* ((test (cp0-expr (cadr expr)))
                 (then (cp0-expr (caddr expr)))
                 (else-val (if (null? (cdddr expr)) #f (cp0-expr (cadddr expr)))))
            (cond
              ;; Dead branch pruning
              ((const? test)
               (let ((v (extract-const-val test)))
                 (if (eq? v #f) else-val then)))
              (else
               (list 'if test then else-val)))))
         ((begin)
          (let* ((body (map cp0-expr (cdr expr)))
                 ;; Flatten nested begins
                 (flat-body
                  (let loop ((es body) (acc '()))
                    (cond
                      ((null? es) (reverse acc))
                      ((and (pair? (car es)) (eq? (caar es) 'begin))
                       (loop (append (cdar es) (cdr es)) acc))
                      (else (loop (cdr es) (cons (car es) acc)))))))
            (cond
              ((null? flat-body) #f)
              ((null? (cdr flat-body)) (car flat-body))
              (else (cons 'begin flat-body)))))
         ((let)
          (let* ((bindings (cadr expr))
                 (body (cp0-expr (caddr expr)))
                 (opt-bindings
                  (map (lambda (b) (list (car b) (cp0-expr (cadr b)))) bindings)))
            ;; Dead let elimination for single pure binding
            (if (and (= (length opt-bindings) 1)
                     (pure-expr? (cadar opt-bindings))
                     (not (memq (caar opt-bindings) (free-vars body '()))))
                body
                (list 'let opt-bindings body))))
         ((letrec)
          (let* ((bindings (cadr expr))
                 (body (cp0-expr (caddr expr)))
                 (opt-bindings
                  (map (lambda (b) (list (car b) (cp0-expr (cadr b)))) bindings)))
            (list 'letrec opt-bindings body)))
         ((lambda)
          (let ((params (cadr expr))
                (body (cp0-expr (caddr expr))))
            (list 'lambda params body)))
         ((%make-closure)
          (cons '%make-closure (cons (cadr expr) (map cp0-expr (cddr expr)))))
         (else
          ;; Primitive or application: optimize arguments first (bottom-up)
          (let* ((opt-op (if (symbol? op) op (cp0-expr op)))
                 (opt-args (map cp0-expr (cdr expr))))
            (or (and (symbol? opt-op) (fold-const-op opt-op opt-args))
                (cons opt-op opt-args)))))))))

;;; Top-level entrypoint for CP0 optimization
(define (cp0-optimize form)
  (cond
    ((not (pair? form)) form)
    ((eq? (car form) '%program)
     (let ((defs (cadr form))
           (main (caddr form)))
       (list '%program
             (map (lambda (d)
                    (if (and (pair? d) (eq? (car d) 'define))
                        (list 'define (cadr d) (cp0-expr (caddr d)))
                        (cp0-expr d)))
                  defs)
             (cp0-expr main))))
    ((eq? (car form) 'define)
     (list 'define (cadr form) (cp0-expr (caddr form))))
    (else
     (cp0-expr form))))
;;; =======================================================================
;;; ULisp Compiler Pass 4: ANF (A-Normal Form) Normalization Nanopass
;;; Conforms to DSN-33 Architecture Specification
;;; Note: Normalizes complex expressions so that all function/primitive
;;;       arguments are atomic (symbols or immediate constants).
;;;       Uses a scoped temporary variable pool (%t0..%t8) to eliminate
;;;       string->symbol heap allocation overhead during bootstrap.
;;; =======================================================================

;;; Fixed pool of temporary variables by nesting depth (Zero heap allocation)
(define (%t-var depth)
  (case depth
    ((0) '%t0)
    ((1) '%t1)
    ((2) '%t2)
    ((3) '%t3)
    ((4) '%t4)
    ((5) '%t5)
    ((6) '%t6)
    ((7) '%t7)
    (else '%t8)))

;;; Collects bindings for non-atomic expressions among a list of arguments.
;;; Returns a pair (bindings . atomic-args).
(define (anf-flatten-args args depth)
  (let loop ((rest args) (d depth) (bindings '()) (atom-args '()))
    (if (null? rest)
        (cons (reverse bindings) (reverse atom-args))
        (let ((arg (car rest)))
          (if (atomic-expr? arg)
              (loop (cdr rest) d bindings (cons arg atom-args))
              (let* ((flat-arg (anf-expr-depth arg (+ d 1)))
                     (tmp (%t-var d)))
                (loop (cdr rest)
                      (+ d 1)
                      (cons (list tmp flat-arg) bindings)
                      (cons tmp atom-args))))))))

;;; Wraps an expression with let-bindings if any exist
(define (anf-wrap-bindings bindings body)
  (if (null? bindings)
      body
      (list 'let bindings body)))

;;; Recursively normalizes an arbitrary expression into A-Normal Form with nesting depth tracking
(define (anf-expr-depth expr depth)
  (cond
    ((atomic-expr? expr) expr)
    ((pair? expr)
     (let ((op (car expr)))
       (case op
         ((quote) expr)
         ((if)
          (let ((test (cadr expr))
                (then (caddr expr))
                (else-val (if (null? (cdddr expr)) #f (cadddr expr))))
            (if (atomic-expr? test)
                (list 'if test (anf-expr-depth then depth) (anf-expr-depth else-val depth))
                (let* ((flat-test (anf-expr-depth test (+ depth 1)))
                       (tmp (%t-var depth)))
                  (list 'let (list (list tmp flat-test))
                        (list 'if tmp (anf-expr-depth then depth) (anf-expr-depth else-val depth)))))))
         ((begin)
          (let ((body (cdr expr)))
            (cond
              ((null? body) #f)
              ((null? (cdr body)) (anf-expr-depth (car body) depth))
              (else (cons 'begin (map (lambda (e) (anf-expr-depth e depth)) body))))))
         ((let)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (list 'let
                  (map (lambda (b) (list (car b) (anf-expr-depth (cadr b) depth))) bindings)
                  (anf-expr-depth body depth))))
         ((letrec)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (list 'letrec
                  (map (lambda (b) (list (car b) (anf-expr-depth (cadr b) depth))) bindings)
                  (anf-expr-depth body depth))))
         ((lambda)
          (let ((params (cadr expr))
                (body (caddr expr)))
            (list 'lambda params (anf-expr-depth body 0))))
         ((%make-closure)
          (let* ((label (cadr expr))
                 (env-args (cddr expr))
                 (res (anf-flatten-args env-args depth))
                 (bindings (car res))
                 (atom-env (cdr res)))
            (anf-wrap-bindings bindings (cons '%make-closure (cons label atom-env)))))
         (else
          ;; Primitive or function application: (op e1 e2 ...)
          (let* ((args-res (anf-flatten-args (cdr expr) depth))
                 (args-bindings (car args-res))
                 (atom-args (cdr args-res))
                 (flat-op (if (atomic-expr? op) op (anf-expr-depth op (+ depth (length args-bindings)))))
                 (call (cons flat-op atom-args)))
            (anf-wrap-bindings args-bindings call))))))
    (else expr)))

;;; Top-level entrypoint for ANF normalization
(define (anf-all form)
  (cond
    ((not (pair? form)) form)
    ((eq? (car form) '%program)
     (let ((defs (cadr form))
           (main (caddr form)))
       (list '%program
             (map (lambda (d)
                    (if (and (pair? d) (eq? (car d) 'define))
                        (list 'define (cadr d) (anf-expr-depth (caddr d) 0))
                        (anf-expr-depth d 0)))
                  defs)
             (anf-expr-depth main 0))))
    ((eq? (car form) 'define)
     (list 'define (cadr form) (anf-expr-depth (caddr form) 0)))
    (else
     (anf-expr-depth form 0))))
;;; =======================================================================
;;; ULisp Compiler Pass 3: Explicit Closure Conversion Nanopass
;;; Conforms to DSN-33 Architecture Specification
;;; Note: Lifts nested lambdas to flat %function definitions, transforms
;;;       closure instantiation to %make-closure, free variable accesses
;;;       to %closure-ref, and mutual recursion (letrec) to %closure-set!.
;;; =======================================================================

;;; Boxed global accumulator for lambda-lifted procedure definitions
(define *lifted-functions* (cons '() '()))

(define (reset-lifted-functions!)
  (set-car! *lifted-functions* '()))

(define (add-lifted-function! fn)
  (set-car! *lifted-functions* (cons fn (car *lifted-functions*))))

;;; Variable environment lookup (linear alist, latest bindings shadow older ones)
(define (lookup-var var var-map)
  (let ((entry (assq var var-map)))
    (if entry (cdr entry) var)))

;;; Forward declarations / helpers for mutual recursion in closure conversion
(define (convert-expr expr var-map)
  (cond
    ((symbol? expr)
     (lookup-var expr var-map))
    ((not (pair? expr))
     expr)
    (else
     (let ((op (car expr)))
       (case op
         ((quote)
          (let ((datum (cadr expr)))
            (cond
              ((symbol? datum)
               (convert-expr (list 'string->symbol (symbol->string datum)) var-map))
              ((and (pair? datum) (has-symbol? datum))
               (convert-expr (list 'cons
                                   (list 'quote (car datum))
                                   (list 'quote (cdr datum)))
                             var-map))
              (else
               expr))))
         ((if)
          (let ((test (convert-expr (cadr expr) var-map))
                (then (convert-expr (caddr expr) var-map))
                (else-expr (if (null? (cdddr expr))
                               #f
                               (convert-expr (cadddr expr) var-map))))
            (list 'if test then else-expr)))
         ((begin)
          (cons 'begin (map (lambda (e) (convert-expr e var-map)) (cdr expr))))
         ((let)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 (new-bindings
                  (map (lambda (b)
                         (list (car b) (convert-expr (cadr b) var-map)))
                       bindings))
                 ;; Shadow let-bound variables in body by pushing identity mappings
                 (body-var-map
                  (let loop ((bs bindings) (acc var-map))
                    (if (null? bs) acc
                        (let ((v (caar bs)))
                          (loop (cdr bs) (cons (cons v v) acc))))))
                 (new-body (convert-expr body body-var-map)))
            (list 'let new-bindings new-body)))
         ((letrec)
          (convert-letrec (cadr expr) (caddr expr) var-map))
         ((lambda)
          (convert-lambda #f (cadr expr) (caddr expr) var-map))
         (else
          (cons (convert-expr op var-map)
                (map (lambda (e) (convert-expr e var-map)) (cdr expr)))))))))

;;; Convert a lambda expression, lift it as a top-level %function, and return %make-closure
(define (convert-lambda self-name params body var-map)
  (let* ((bound-vars (if self-name (cons self-name params) params))
         (frees (free-vars body bound-vars))
         (label (unique-label-sym "L_lambda"))
         ;; Build callee inner var-map:
         ;; 1. Params shadow outer bindings (map to themselves)
         (env-p (let loop ((ps params) (acc '()))
                  (if (null? ps) acc
                      (loop (cdr ps) (cons (cons (car ps) (car ps)) acc)))))
         ;; 2. Self name (if recursive) maps to %self
         (env-s (if self-name
                    (cons (cons self-name '%self) env-p)
                    env-p))
         ;; 3. Free variables map to (%closure-ref %self idx)
         (inner-var-map
          (let loop ((fs frees) (idx 1) (acc env-s))
            (if (null? fs)
                acc
                (let ((fv (car fs)))
                  (loop (cdr fs) (+ idx 1)
                        (cons (cons fv (list '%closure-ref '%self idx)) acc))))))
         (new-body (convert-expr body inner-var-map))
         (fn-def (list '%function label params new-body)))
    (add-lifted-function! fn-def)
    ;; Instantiation expression: (%make-closure 'label captured-args...)
    (let ((captured-args
           (map (lambda (fv) (convert-expr fv var-map)) frees)))
      (cons '%make-closure (cons label captured-args)))))

;;; Convert letrec expression into let + %make-closure + backpatching %closure-set!
(define (convert-letrec bindings body var-map)
  (let* ((rec-vars (map car* bindings))
         ;; Shadow rec-vars in outer-var-map by binding them to themselves
         (outer-var-map
          (let loop ((rvs rec-vars) (acc var-map))
            (if (null? rvs) acc
                (loop (cdr rvs) (cons (cons (car rvs) (car rvs)) acc)))))
         (processed-bindings
          (map (lambda (b)
                 (let ((var (car b))
                       (val (cadr b)))
                   (if (and (pair? val) (eq? (car val) 'lambda))
                       (let* ((params (cadr val))
                              (lbody (caddr val))
                              (bound (cons var params))
                              (frees (free-vars lbody bound))
                              (label (unique-label-sym "L_lambda"))
                              ;; Callee inner environment:
                              ;; Params map to themselves
                              (env-p (let loop ((ps params) (acc '()))
                                       (if (null? ps) acc
                                           (loop (cdr ps) (cons (cons (car ps) (car ps)) acc)))))
                              ;; Self-name maps to %self
                              (env-s (cons (cons var '%self) env-p))
                              ;; Free variables map to (%closure-ref %self idx)
                              (inner-var-map
                               (let loop ((fs frees) (idx 1) (acc env-s))
                                 (if (null? fs) acc
                                     (let ((fv (car fs)))
                                       (loop (cdr fs) (+ idx 1)
                                             (cons (cons fv (list '%closure-ref '%self idx)) acc))))))
                              (new-lbody (convert-expr lbody inner-var-map))
                              (fn-def (list '%function label params new-lbody)))
                         (add-lifted-function! fn-def)
                         (let ((init-args
                                (map (lambda (fv)
                                       (if (memq fv rec-vars)
                                           #f
                                           (convert-expr fv outer-var-map)))
                                     frees)))
                           (list var
                                 (cons '%make-closure (cons label init-args))
                                 frees)))
                       (list var (convert-expr val outer-var-map) '()))))
               bindings))
         (let-bindings
          (map (lambda (pb) (list (car pb) (cadr pb))) processed-bindings))
         (backpatches
          (let loop-b ((pbs processed-bindings) (acc '()))
            (if (null? pbs)
                (reverse acc)
                (let* ((pb (car pbs))
                       (var (car pb))
                       (frees (caddr pb))
                       (patches
                        (let loop-f ((fs frees) (idx 1) (p-acc '()))
                          (if (null? fs)
                              (reverse p-acc)
                              (let ((fv (car fs)))
                                (if (memq fv rec-vars)
                                    (loop-f (cdr fs) (+ idx 1)
                                            (cons (list '%closure-set! var idx fv) p-acc))
                                    (loop-f (cdr fs) (+ idx 1) p-acc)))))))
                  (loop-b (cdr pbs) (append (reverse patches) acc))))))
         (new-body (convert-expr body outer-var-map)))
    (if (null? backpatches)
        (list 'let let-bindings new-body)
        (list 'let let-bindings
              (cons 'begin (append backpatches (list new-body)))))))

;;; Pass 3 Entrypoint: Takes Canonical Core AST, returns (%program functions main-expr)
(define (closure-convert ast)
  (reset-lifted-functions!)
  (let ((main-expr (convert-expr ast '())))
    (list '%program (reverse (car *lifted-functions*)) main-expr)))
;;; =======================================================================
;;; ULisp Compiler Pass 4: Low-Level Assembly Emitter & Symbol/String Tables
;;; Conforms to DSN-33 Architecture Specification
;;; =======================================================================

(define *symbol-table* (cons '() '()))
(define (intern-symbol sym)
  (let ((entry (assq sym (car *symbol-table*))))
    (if entry
        (cdr entry)
        (let ((id (+ (* (length (car *symbol-table*)) 256) 2)))
          (set-car! *symbol-table* (cons (cons sym id) (car *symbol-table*)))
          id))))

(define *string-counter* (cons 0 '()))
(define *strings* (cons '() '()))
(define (intern-string str)
  (let ((label (string-append ".L_str_" (number->string (car *string-counter*)))))
    (set-car! *string-counter* (+ (car *string-counter*) 1))
    (set-car! *strings* (cons (cons label str) (car *strings*)))
    label))

(define (emit-string-literal str)
  (let ((label (intern-string str)))
    (emit (string-append "    lea rax, [rip + " label " + 3]"))))

(define (emit line)
  (display line)
  (newline))

(define (emit-boolean-from-set set-inst)
  (emit (string-append "    " set-inst " al"))
  (emit "    movzx eax, al")
  (emit "    shl rax, 6")
  (emit "    add rax, 0x2F"))

(define (emit-boolean)
  (emit-boolean-from-set "sete"))

(define (offset->string offset)
  (if (< offset 0)
      (string-append "- " (number->string (- 0 offset)))
      (string-append "+ " (number->string offset))))

(define (align-frame-shift needed)
  (if (= (modulo needed 16) 8)
      needed
      (+ needed 8)))
;;; =======================================================================
;;; ULisp Compiler Pass 5: Native x86-64 Code Generation Pass
;;; Conforms to DSN-33 Architecture Specification
;;; Note: Codegen is purely a straightforward instruction emitter for flat
;;;       %function definitions and canonical primitive expressions.
;;; =======================================================================

(define (immediate? expr)
  (or (integer? expr)
      (boolean? expr)
      (char? expr)
      (null? expr)
      (string? expr)))

(define (emit-immediate expr)
  (cond
    ((integer? expr)
     (emit (string-append "    mov rax, " (number->string (* expr 4)))))
    ((boolean? expr)
     (if expr
         (emit "    mov rax, 0x6F")   ; #t
         (emit "    mov rax, 0x2F")))  ; #f
    ((char? expr)
     (let ((code (+ (* (char->integer expr) 256) 14)))
       (emit (string-append "    mov rax, " (number->string code)))))
    ((null? expr)
     (emit "    mov rax, 0x3F"))      ; '()
    ((string? expr)
     (emit-string-literal expr))))

(define (compile-zero-arg op si env)
  (let ((frame-shift (align-frame-shift (- si))))
    (case op
      ((read-char)
       (emit (string-append "    sub rsp, " (number->string frame-shift)))
       (emit "    call ulisp_read_char")
       (emit (string-append "    add rsp, " (number->string frame-shift))))
      ((peek-char)
       (emit (string-append "    sub rsp, " (number->string frame-shift)))
       (emit "    call ulisp_peek_char")
       (emit (string-append "    add rsp, " (number->string frame-shift)))))))

(define (compile-unary op arg si env)
  (compile-expr arg si env #f)
  (case op
    ((-)
     (emit "    neg rax"))
    ((fxadd1)
     (emit "    add rax, 4"))
    ((fxsub1)
     (emit "    sub rax, 4"))
    ((fixnum->char integer->char)
     (emit "    shl rax, 6")
     (emit "    or rax, 14"))
    ((char->fixnum char->integer)
     (emit "    shr rax, 6"))
    ((integer->symbol)
     (emit "    shl rax, 6")
     (emit "    or rax, 2"))
    ((symbol->integer)
     (emit "    shr rax, 6"))
    ((zero?)
     (emit "    cmp rax, 0")
     (emit-boolean))
    ((fixnum? integer? number?)
     (emit "    and al, 3")
     (emit "    cmp al, 0")
     (emit-boolean))
    ((boolean?)
     (emit "    mov rdx, rax")
     (emit "    xor rdx, 0x2F")
     (emit "    and rdx, -65")
     (emit "    cmp rdx, 0")
     (emit-boolean))
    ((char?)
     (emit "    and al, 0xFF")
     (emit "    cmp al, 14")
     (emit-boolean))
    ((null?)
     (emit "    cmp rax, 0x3F")
     (emit-boolean))
    ((not)
     (emit "    cmp rax, 0x2F")
     (emit-boolean))
    ((symbol?)
     (emit "    and al, 0xFF")
     (emit "    cmp al, 2")
     (emit-boolean))
    ((car)
     (emit "    mov rax, [rax - 1]"))
    ((cdr)
     (emit "    mov rax, [rax + 7]"))
    ((pair?)
     (emit "    and al, 3")
     (emit "    cmp al, 1")
     (emit-boolean))
    ((procedure?)
     ;; Heap object (tag 1)
     (emit "    and al, 3")
     (emit "    cmp al, 1")
     (emit-boolean))
    ((string?)
     (emit "    and al, 3")
     (emit "    cmp al, 3")
     (emit-boolean))
    ((write-char)
     (let ((frame-shift (align-frame-shift (- si))))
       (emit "    mov rdi, rax")
       (emit (string-append "    sub rsp, " (number->string frame-shift)))
       (emit "    call ulisp_write_char")
       (emit (string-append "    add rsp, " (number->string frame-shift)))))
    ((eof-object?)
     (emit "    cmp rax, 0x4F")
     (emit-boolean))

    ((make-string)
     (emit "    sar rax, 2")
     (emit "    mov rcx, rax")
     (emit "    add rax, 8")
     (emit "    and rax, -8")
     (emit "    mov rdx, r12")
     (emit "    add r12, rax")
     (emit "    mov byte ptr [rdx + rcx], 0")
     (emit "    lea rax, [rdx + 3]"))
    ((string-length)
     (let ((l-loop (unique-label "strlen_loop"))
           (l-done (unique-label "strlen_done")))
       (emit "    mov rdx, rax")
       (emit "    sub rdx, 3")
       (emit "    xor rax, rax")
       (emit (string-append l-loop ":"))
       (emit "    cmp byte ptr [rdx + rax], 0")
       (emit (string-append "    je " l-done))
       (emit "    inc rax")
       (emit (string-append "    jmp " l-loop))
       (emit (string-append l-done ":"))
       (emit "    shl rax, 2")))))

(define (compile-binop op e1 e2 si env)
  (compile-expr e1 si env #f)
  (emit (string-append "    mov [rsp " (offset->string si) "], rax"))
  (compile-expr e2 (- si 8) env #f)
  (case op
    ((+)
     (emit (string-append "    add rax, [rsp " (offset->string si) "]")))
    ((-)
     (emit (string-append "    mov rdx, [rsp " (offset->string si) "]"))
     (emit "    sub rdx, rax")
     (emit "    mov rax, rdx"))
    ((*)
     (emit "    sar rax, 2")
     (emit (string-append "    imul rax, [rsp " (offset->string si) "]")))
    ((modulo)
     (emit "    mov rcx, rax")
     (emit (string-append "    mov rax, [rsp " (offset->string si) "]"))
     (emit "    sar rax, 2")
     (emit "    sar rcx, 2")
     (emit "    cqo")
     (emit "    idiv rcx")
     (emit "    mov rax, rdx")
     (emit "    shl rax, 2"))
    ((quotient /)
     (emit "    mov rcx, rax")
     (emit (string-append "    mov rax, [rsp " (offset->string si) "]"))
     (emit "    sar rax, 2")
     (emit "    sar rcx, 2")
     (emit "    cqo")
     (emit "    idiv rcx")
     (emit "    shl rax, 2"))
    ((string-ref)
     (emit "    sar rax, 2")
     (emit (string-append "    mov rdx, [rsp " (offset->string si) "]"))
     (emit "    sub rdx, 3")
     (emit "    movzx rax, byte ptr [rdx + rax]")
     (emit "    shl rax, 8")
     (emit "    or rax, 14"))
    ((=)
     (emit (string-append "    cmp [rsp " (offset->string si) "], rax"))
     (emit-boolean-from-set "sete"))
    ((<)
     (emit (string-append "    cmp [rsp " (offset->string si) "], rax"))
     (emit-boolean-from-set "setl"))
    ((<=)
     (emit (string-append "    cmp [rsp " (offset->string si) "], rax"))
     (emit-boolean-from-set "setle"))
    ((>)
     (emit (string-append "    cmp [rsp " (offset->string si) "], rax"))
     (emit-boolean-from-set "setg"))
    ((>=)
     (emit (string-append "    cmp [rsp " (offset->string si) "], rax"))
     (emit-boolean-from-set "setge"))
    ((cons)
     (emit (string-append "    mov [rsp " (offset->string (- si 8)) "], rax"))
     (emit (string-append "    mov rax, [rsp " (offset->string si) "]"))
     (emit "    mov [r12], rax")
     (emit (string-append "    mov rax, [rsp " (offset->string (- si 8)) "]"))
     (emit "    mov [r12 + 8], rax")
     (emit "    lea rax, [r12 + 1]")
     (emit "    add r12, 16"))
    ((set-car!)
     (emit (string-append "    mov rdx, [rsp " (offset->string si) "]"))
     (emit "    mov [rdx - 1], rax")
     (emit "    mov rax, 0x3F"))
    ((set-cdr!)
     (emit (string-append "    mov rdx, [rsp " (offset->string si) "]"))
     (emit "    mov [rdx + 7], rax")
     (emit "    mov rax, 0x3F"))
    ((eq? char=?)
     (emit (string-append "    cmp [rsp " (offset->string si) "], rax"))
     (emit-boolean))
    ((%closure-ref)
     (let ((idx e2))
       (let ((offset (- (* idx 8) 1)))
         (emit (string-append "    mov rax, [rsp " (offset->string si) "]"))
         (emit (string-append "    mov rax, [rax + " (number->string offset) "]")))))))

(define (compile-triop op e1 e2 e3 si env)
  (compile-expr e1 si env #f)
  (emit (string-append "    mov [rsp " (offset->string si) "], rax"))
  (compile-expr e2 (- si 8) env #f)
  (emit (string-append "    mov [rsp " (offset->string (- si 8)) "], rax"))
  (compile-expr e3 (- si 16) env #f)
  (case op
    ((string-set!)
     (emit "    shr rax, 8")
     (emit (string-append "    mov rdx, [rsp " (offset->string si) "]"))
     (emit "    sub rdx, 3")
     (emit (string-append "    mov rcx, [rsp " (offset->string (- si 8)) "]"))
     (emit "    sar rcx, 2")
     (emit "    mov [rdx + rcx], al")
     (emit "    mov rax, 0x3F"))
    ((%closure-set!)
     (let ((idx-offset (- (* e2 8) 1)))
       (emit (string-append "    mov rdx, [rsp " (offset->string si) "]"))
       (emit (string-append "    mov [rdx + " (number->string idx-offset) "], rax"))
       (emit "    mov rax, 0x3F")))))

(define (compile-make-closure expr si env)
  (let* ((label-arg (cadr expr))
         (label-str (if (and (pair? label-arg) (eq? (car label-arg) 'quote))
                        (symbol->string (cadr label-arg))
                        (if (symbol? label-arg)
                            (symbol->string label-arg)
                            (error "Invalid closure label:" label-arg))))
         (args (cddr expr))
         (num-args (length args))
         (closure-size (* (+ num-args 1) 8))
         (aligned-size (if (= (modulo closure-size 16) 0) closure-size (+ closure-size 8))))
    ;; 1. Evaluate arguments sequentially and place into temporary stack slots
    (let loop ((as args) (curr-si si))
      (if (not (null? as))
          (begin
            (compile-expr (car as) curr-si env #f)
            (emit (string-append "    mov [rsp " (offset->string curr-si) "], rax"))
            (loop (cdr as) (- curr-si 8)))))
    ;; 2. Allocate closure on heap at runtime (r12)
    ;; Store code pointer label into [r12]
    (emit (string-append "    lea rax, [rip + " label-str "]"))
    (emit "    mov [r12], rax")
    ;; 3. Copy captured arguments from stack to heap [r12 + 8 * i]
    (let loop ((i 1) (curr-si si))
      (if (<= i num-args)
          (begin
            (emit (string-append "    mov rax, [rsp " (offset->string curr-si) "]"))
            (emit (string-append "    mov [r12 + " (number->string (* i 8)) "], rax"))
            (loop (+ i 1) (- curr-si 8)))))
    ;; 4. Tag closure pointer with 0x01 (Heap object tag)
    (emit "    lea rax, [r12 + 1]")
    (emit (string-append "    add r12, " (number->string aligned-size)))))

(define (compile-closure-ref-expr expr si env)
  (let ((c-expr (cadr expr))
        (idx (caddr expr)))
    (compile-expr c-expr si env #f)
    (let ((offset (- (* idx 8) 1)))
      (emit (string-append "    mov rax, [rax + " (number->string offset) "]")))))

(define (compile-closure-set-expr expr si env)
  (let ((c-expr (cadr expr))
        (idx (caddr expr))
        (val-expr (cadddr expr)))
    ;; 1. Evaluate closure expression -> stack
    (compile-expr c-expr si env #f)
    (emit (string-append "    mov [rsp " (offset->string si) "], rax"))
    ;; 2. Evaluate val-expr -> rax
    (compile-expr val-expr (- si 8) env #f)
    ;; 3. Store into closure heap slot
    (let ((offset (- (* idx 8) 1)))
      (emit (string-append "    mov rdx, [rsp " (offset->string si) "]"))
      (emit (string-append "    mov [rdx + " (number->string offset) "], rax"))
      (emit "    mov rax, 0x3F"))))

(define (compile-variable var env)
  (let ((binding (assq var env)))
    (if (not binding)
        (error "Unbound variable:" var)
        (let ((info (cdr binding)))
          (cond
            ((number? info)
             ;; Standard stack offset
             (emit (string-append "    mov rax, [rsp " (offset->string info) "]")))
            ((and (pair? info) (eq? (car info) 'param))
             ;; Lambda param offset (positive: +8, +16, ...)
             (emit (string-append "    mov rax, [rsp + " (number->string (cdr info)) "]")))
            ((and (pair? info) (eq? (car info) 'self))
             ;; Self closure reference in recursion
             (emit (string-append "    mov rax, [rsp " (offset->string (cdr info)) "]")))
            (else
             (error "Invalid binding format:" binding)))))))

(define (compile-let bindings body si env tail?)
  (let loop ((bs bindings)
             (curr-si si)
             (new-env env))
    (if (null? bs)
        (compile-expr body curr-si new-env tail?)
        (let* ((b (car bs))
               (var (car b))
               (val (cadr b)))
          (compile-expr val curr-si env #f)
          (emit (string-append "    mov [rsp " (offset->string curr-si) "], rax"))
          (loop (cdr bs)
                (- curr-si 8)
                (cons (cons var curr-si) new-env))))))

(define (compile-if test then else-opt si env tail?)
  (let ((else-label (unique-label "L_else"))
        (end-label (unique-label "L_end")))
    (compile-expr test si env #f)
    (emit "    cmp rax, 0x2F")
    (emit (string-append "    je " else-label))
    (compile-expr then si env tail?)
    (emit (string-append "    jmp " end-label))
    (emit (string-append else-label ":"))
    (if (null? else-opt)
        (emit "    mov rax, 0x2F")
        (compile-expr (car else-opt) si env tail?))
    (emit (string-append end-label ":"))))

(define (compile-begin exprs si env tail?)
  (if (null? exprs)
      (emit "    mov rax, 0x3F")
      (let loop ((es exprs))
        (if (null? (cdr es))
            (compile-expr (car es) si env tail?)
            (begin
              (compile-expr (car es) si env #f)
              (loop (cdr es)))))))

(define (compile-quote datum si env)
  (cond
    ((immediate? datum)
     (emit-immediate datum))
    ((pair? datum)
     (compile-expr (list 'cons
                         (list 'quote (car datum))
                         (list 'quote (cdr datum)))
                   si env #f))
    (else
     (error "Invalid quoted datum in codegen:" datum))))

;;; General Procedure Call (Tail Call vs Non-tail Call)
(define (compile-call proc args si env tail?)
  (let* ((num-args (length args))
         (cur-params-entry (assq '%num-params env))
         (cur-num-params (if cur-params-entry (cdr cur-params-entry) #f))
         (can-tco? (and tail? (if cur-num-params (= cur-num-params num-args) #f)))
         (frame-shift (align-frame-shift (if (= num-args 0)
                                             (- 0 si)
                                             (- (* 8 (- num-args 1)) si))))
         (aligned-si (if (= num-args 0)
                         (- 0 frame-shift)
                         (- (* 8 (- num-args 1)) frame-shift))))
    ;; 1. Evaluate arguments sequentially and place into temporary stack slots
    (let loop ((as args) (curr-si aligned-si))
      (if (not (null? as))
          (begin
            (compile-expr (car as) curr-si env #f)
            (emit (string-append "    mov [rsp " (offset->string curr-si) "], rax"))
            (loop (cdr as) (- curr-si 8)))))

    (let ((end-args-si (- aligned-si (* num-args 8))))
      ;; 2. Evaluate procedure expression -> RAX
      (compile-expr proc end-args-si env #f)
      (emit "    mov r10, rax") ; closure pointer into r10

      (if can-tco?
          ;; --- TAIL CALL OPTIMIZATION (TCO) ---
          ;; Overwrite current frame's parameter slots [rsp + 8 * (num-args - i)]
          (begin
            (let loop ((i 0))
              (if (< i num-args)
                  (let ((temp-offset (- aligned-si (* i 8)))
                        (param-offset (* 8 (- num-args i))))
                    (emit (string-append "    mov rdx, [rsp " (offset->string temp-offset) "]"))
                    (emit (string-append "    mov [rsp + " (number->string param-offset) "], rdx"))
                    (loop (+ i 1)))))
            (emit "    mov rdx, [r10 - 1]") ; extract code pointer from closure
            (emit "    jmp rdx"))          ; tail jump without new stack frame!

          ;; --- NON-TAIL CALL ---
          (begin
            (if (> frame-shift 0)
                (emit (string-append "    sub rsp, " (number->string frame-shift))))
            (emit "    mov rdx, [r10 - 1]")
            (emit "    call rdx")
            (if (> frame-shift 0)
                (emit (string-append "    add rsp, " (number->string frame-shift)))))))))

(define (compile-expr expr si env tail?)
  (cond
    ((immediate? expr)
     (emit-immediate expr))
    ((symbol? expr)
     (compile-variable expr env))
    ((pair? expr)
     (let ((op (car expr)))
       (cond
         ((zero-arg-prim? op)
          (compile-zero-arg op si env))
         ((eq? op '-)
          (if (null? (cddr expr))
              (compile-unary '- (cadr expr) si env)
              (compile-binop '- (cadr expr) (caddr expr) si env)))
         ((unary-prim? op)
          (compile-unary op (cadr expr) si env))
         ((binop-prim? op)
          (compile-binop op (cadr expr) (caddr expr) si env))
         ((triop-prim? op)
          (compile-triop op (cadr expr) (caddr expr) (cadddr expr) si env))
         ((eq? op '%make-closure)
          (compile-make-closure expr si env))
         ((eq? op '%closure-ref)
          (compile-closure-ref-expr expr si env))
         ((eq? op '%closure-set!)
          (compile-closure-set-expr expr si env))
         ((eq? op 'let)
          (compile-let (cadr expr) (caddr expr) si env tail?))
         ((eq? op 'if)
          (compile-if (cadr expr) (caddr expr) (cdddr expr) si env tail?))
         ((eq? op 'begin)
          (compile-begin (cdr expr) si env tail?))
         ((eq? op 'quote)
          (compile-quote (cadr expr) si env))
         (else
          ;; General procedure call
          (compile-call op (cdr expr) si env tail?)))))
    (else
     (error "Invalid syntax:" expr))))

;;; Compiles a single lifted %function definition
(define (compile-function fn)
  (let* ((label (cadr fn))
         (label-str (if (symbol? label) (symbol->string label) label))
         (params (caddr fn))
         (body (cadddr fn))
         (num-params (length params)))
    (emit "    .p2align 3")
    (emit (string-append label-str ":"))
    ;; Callee prologue: self closure pointer was in r10
    ;; Store self closure pointer at [rsp - 8]
    (emit "    mov [rsp - 8], r10")
    ;; Build callee env:
    ;; %self at [rsp - 8]
    ;; params at [rsp + 8 * (num-params - i)]
    (let* ((self-env (list (cons '%self (cons 'self -8))))
           (param-env
            (let loop ((ps params) (i 0) (acc '()))
              (if (null? ps) acc
                  (let ((offset (* 8 (- num-params i))))
                    (loop (cdr ps) (+ i 1)
                          (cons (cons (car ps) (cons 'param offset)) acc))))))
           (callee-env (cons (cons '%num-params num-params)
                             (append self-env param-env)))
           (callee-si -16))
      (compile-expr body callee-si callee-env #t)
      (emit "    ret"))))

(define (compile-program prog)
  (let ((funcs (cadr prog))
        (main-expr (caddr prog)))
    (set-car! *label-counter* 0)
    (set-car! *symbol-counter* 0)
    (set-car! *symbol-table* '())
    (set-car! *string-counter* 0)
    (set-car! *strings* '())
    (emit "    .intel_syntax noprefix")
    (emit "    .text")
    (emit "    .globl scheme_entry")
    (emit "    .type scheme_entry, @function")
    (emit "scheme_entry:")
    (emit "    push r12")
    (emit "    sub rsp, 8")
    (emit "    mov r12, rdi")          ; rdi contains heap_base from C runtime
    (compile-expr main-expr -8 '() #f)
    (emit "    add rsp, 8")
    (emit "    pop r12")
    (emit "    ret")
    ;; Emit all lifted procedure definitions in sequence
    (for-each compile-function funcs)
    ;; Emit all string literals in .rodata section
    (if (not (null? (car *strings*)))
        (begin
          (emit "    .section .rodata")
          (let loop ((ss (reverse (car *strings*))))
            (if (not (null? ss))
                (let ((entry (car ss)))
                  (emit "    .p2align 3")
                  (emit (string-append (car entry) ":"))
                  (emit (string-append "    .asciz \"" (escape-gas-string (cdr entry)) "\""))
                  (loop (cdr ss)))))))
    (emit "    .section .note.GNU-stack,\"\",@progbits")))
;;; =======================================================================
;;; ULisp Compiler Pass 8: Compilation Driver & CLI Entrypoint
;;; Conforms to DSN-33 Architecture Specification
;;; =======================================================================

(define (read-all-forms)
  (let loop ((acc '()))
    (let ((expr (read)))
      (if (eof-object? expr)
          (reverse acc)
          (loop (cons expr acc))))))

;;; Entry point: read all S-expressions from standard input and compile through serial pipeline
(let ((forms (read-all-forms)))
  (if (not (null? forms))
      (let* ((ast0 (rewrite-top-level forms))
             (ast1 (desugar-all ast0))
             (ast2 (cp0-optimize ast1))
             (ast3 (anf-all ast2))
             (ast4 (closure-convert ast3)))
        (compile-program ast4))))
