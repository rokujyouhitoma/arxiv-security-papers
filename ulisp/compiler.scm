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
  (memq op '(+ - * = < <= > >= modulo quotient / string-ref cons set-car! set-cdr! eq? char=?)))

(define (triop-prim? op)
  (memq op '(string-set!)))

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

;;; Symbol table for interned symbols
(define *symbol-table* (cons '() '()))
(define (intern-symbol sym)
  (let ((entry (assq sym (car *symbol-table*))))
    (if entry
        (cdr entry)
        (let ((id (+ (* (length (car *symbol-table*)) 256) 2)))
          (set-car! *symbol-table* (cons (cons sym id) (car *symbol-table*)))
          id))))

;;; String table for interned string literals
(define *string-counter* (cons 0 '()))
(define *strings* (cons '() '()))
(define (intern-string str)
  (let ((label (string-append ".L_str_" (number->string (car *string-counter*)))))
    (set-car! *string-counter* (+ (car *string-counter*) 1))
    (set-car! *strings* (cons (cons label str) (car *strings*)))
    label))

(define (offset->string offset)
  (if (< offset 0)
      (string-append "- " (number->string (- 0 offset)))
      (string-append "+ " (number->string offset))))

(define (align-frame-shift needed)
  (if (= (modulo needed 16) 8)
      needed
      (+ needed 8)))
;;; =======================================================================
;;; ULisp Compiler Pass 0b: Metacircular Macro Expander
;;; Conforms to DSN-33 Architecture Specification & Issue #500
;;;
;;; Provides self-contained compile-time macro expansion without relying
;;; on host runtime `eval`. Fully operational in both host Scheme (ILisp)
;;; and self-hosted native AOT binaries (Stage 1/2/3).
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Macro Environment Operations
;;; -----------------------------------------------------------------------

(define (macro-env-lookup sym env)
  (let ((pair (assq sym env)))
    (if pair (cdr pair) 'unbound)))

(define (macro-bind-params params args env)
  (cond
    ((null? params)
     (if (null? args)
         env
         (error "macro-bind-params: too many arguments" args)))
    ((symbol? params)
     (cons (cons params args) env))
    ((pair? params)
     (if (null? args)
         (error "macro-bind-params: too few arguments" params)
         (macro-bind-params (cdr params) (cdr args)
                            (cons (cons (car params) (car args)) env))))
    (else env)))

;;; Closure representation: ('macro-closure params body env)
(define (macro-closure? obj)
  (and (pair? obj) (eq? (car obj) 'macro-closure)))

;;; -----------------------------------------------------------------------
;;; 2. Built-in Primitive Procedures for Compile-time Evaluation
;;; -----------------------------------------------------------------------

(define (macro-prim? op)
  (memq op '(cons car cdr pair? null? list append eq? equal? not
             + - * = < > <= >= symbol? number? boolean? string?
             reverse length cadr cddr cdar caar caddr cdddr)))

(define (macro-equal? a b)
  (cond
    ((eq? a b) #t)
    ((and (pair? a) (pair? b))
     (and (macro-equal? (car a) (car b))
          (macro-equal? (cdr a) (cdr b))))
    (else #f)))

(define (macro-apply-prim op args)
  (case op
    ((cons)
     (cons (car args) (cadr args)))
    ((car)
     (car (car args)))
    ((cdr)
     (cdr (car args)))
    ((pair?)
     (pair? (car args)))
    ((null?)
     (null? (car args)))
    ((list)
     args)
    ((append)
     (if (null? args)
         '()
         (if (null? (cdr args))
             (car args)
             (append (car args) (cadr args)))))
    ((eq?)
     (eq? (car args) (cadr args)))
    ((equal?)
     (macro-equal? (car args) (cadr args)))
    ((not)
     (not (car args)))
    ((+)
     (if (null? args)
         0
         (if (null? (cdr args))
             (car args)
             (+ (car args) (cadr args)))))
    ((-)
     (if (null? (cdr args))
         (- 0 (car args))
         (- (car args) (cadr args))))
    ((*)
     (if (null? args)
         1
         (if (null? (cdr args))
             (car args)
             (* (car args) (cadr args)))))
    ((=)
     (= (car args) (cadr args)))
    ((<)
     (< (car args) (cadr args)))
    ((>)
     (> (car args) (cadr args)))
    ((<=)
     (<= (car args) (cadr args)))
    ((>=)
     (>= (car args) (cadr args)))
    ((symbol?)
     (symbol? (car args)))
    ((number?)
     (number? (car args)))
    ((boolean?)
     (boolean? (car args)))
    ((string?)
     (string? (car args)))
    ((reverse)
     (reverse (car args)))
    ((length)
     (length (car args)))
    ((cadr)
     (cadr (car args)))
    ((cddr)
     (cddr (car args)))
    ((cdar)
     (cdar (car args)))
    ((caar)
     (caar (car args)))
    ((caddr)
     (caddr (car args)))
    ((cdddr)
     (cdddr (car args)))
    (else
     (error "macro-apply-prim: unsupported primitive" op))))

;;; -----------------------------------------------------------------------
;;; 3. Metacircular Evaluator for Macro Transformations
;;; -----------------------------------------------------------------------

(define (eval-macro-sequence exprs env)
  (cond
    ((null? exprs) '())
    ((null? (cdr exprs)) (eval-macro-expr (car exprs) env))
    (else
     (eval-macro-expr (car exprs) env)
     (eval-macro-sequence (cdr exprs) env))))

(define (apply-macro-proc proc args)
  (cond
    ((symbol? proc)
     (if (macro-prim? proc)
         (macro-apply-prim proc args)
         (error "apply-macro-proc: unknown primitive symbol" proc)))
    ((macro-closure? proc)
     (let ((params (cadr proc))
           (body (caddr proc))
           (env (cadddr proc)))
       (let ((call-env (macro-bind-params params args env)))
         (eval-macro-sequence body call-env))))
    (else
     (error "apply-macro-proc: object is not applicable" proc))))

(define (eval-macro-expr expr env)
  (cond
    ((number? expr) expr)
    ((boolean? expr) expr)
    ((char? expr) expr)
    ((string? expr) expr)
    ((null? expr) '())
    ((symbol? expr)
     (let ((val (macro-env-lookup expr env)))
       (if (eq? val 'unbound)
           (error "eval-macro-expr: unbound variable in macro definition" expr)
           val)))
    ((not (pair? expr)) expr)
    (else
     (let ((op (car expr)))
       (case op
         ((quote)
          (cadr expr))
         ((if)
          (let ((test-val (eval-macro-expr (cadr expr) env)))
            (if test-val
                (eval-macro-expr (caddr expr) env)
                (if (pair? (cdddr expr))
                    (eval-macro-expr (cadddr expr) env)
                    #f))))
         ((begin)
          (eval-macro-sequence (cdr expr) env))
         ((let)
          (if (symbol? (cadr expr))
              (error "eval-macro-expr: named let not supported in macro transformer" expr)
              (let* ((bindings (cadr expr))
                     (body (cddr expr))
                     (vars (map car* bindings))
                     (vals (map (lambda (b) (eval-macro-expr (cadr b) env)) bindings))
                     (new-env (macro-bind-params vars vals env)))
                (eval-macro-sequence body new-env))))
         ((let*)
          (let ((bindings (cadr expr))
                (body (cddr expr)))
            (let loop ((bs bindings) (e env))
              (if (null? bs)
                  (eval-macro-sequence body e)
                  (let* ((b (car bs))
                         (var (car b))
                         (val (eval-macro-expr (cadr b) e)))
                    (loop (cdr bs) (cons (cons var val) e)))))))
         ((lambda)
          (let ((params (cadr expr))
                (body (cddr expr)))
            (list 'macro-closure params body env)))
         (else
          (let ((proc (if (symbol? op)
                          (if (macro-prim? op)
                              op
                              (eval-macro-expr op env))
                          (eval-macro-expr op env))))
            (let ((args (map (lambda (a) (eval-macro-expr a env)) (cdr expr))))
              (apply-macro-proc proc args)))))))))

;;; -----------------------------------------------------------------------
;;; 4. Macro Definition Parsing and Expansion
;;; -----------------------------------------------------------------------

(define (macro-def? form)
  (and (pair? form)
       (or (eq? (car form) 'define-macro)
           (eq? (car form) 'defmacro))))

(define (parse-macro-def form)
  (let ((op (car form))
        (spec (cadr form)))
    (cond
      ((pair? spec)
       ;; (define-macro (name . params) body ...)
       ;; (defmacro (name . params) body ...)
       (let ((name (car spec))
             (params (cdr spec))
             (body (cddr form)))
         (cons name (list 'macro-closure params body '()))))
      ((symbol? spec)
       ;; (defmacro name params body ...)
       (if (eq? op 'defmacro)
           (let ((name spec)
                 (params (caddr form))
                 (body (cdddr form)))
             (cons name (list 'macro-closure params body '())))
           ;; (define-macro name (lambda params body ...))
           (let* ((name spec)
                  (val-expr (caddr form))
                  (closure (eval-macro-expr val-expr '())))
             (cons name closure))))
      (else
       (error "parse-macro-def: invalid macro syntax" form)))))

(define (macro-expand-1 expr macro-table)
  (if (and (pair? expr) (symbol? (car expr)))
      (let ((entry (assq (car expr) macro-table)))
        (if entry
            (let ((closure (cdr entry))
                  (args (cdr expr)))
              (cons #t (apply-macro-proc closure args)))
            (cons #f expr)))
      (cons #f expr)))

(define (macro-expand-top-expr expr macro-table)
  (let ((res (macro-expand-1 expr macro-table)))
    (if (car res)
        (macro-expand-top-expr (cdr res) macro-table)
        (cdr res))))

(define (macro-expand-all expr macro-table)
  (let ((expanded (macro-expand-top-expr expr macro-table)))
    (cond
      ((not (pair? expanded))
       expanded)
      ((eq? (car expanded) 'quote)
       expanded)
      (else
       (map (lambda (sub) (macro-expand-all sub macro-table)) expanded)))))

;;; Expand all macro definitions and usages in top-level forms
(define (expand-macros-in-forms forms)
  (let loop ((fs forms) (macro-table '()) (res '()))
    (if (null? fs)
        (reverse res)
        (let ((f (car fs)))
          (if (macro-def? f)
              (let ((entry (parse-macro-def f)))
                (loop (cdr fs) (cons entry macro-table) res))
              (let ((exp-f (macro-expand-all f macro-table)))
                (loop (cdr fs) macro-table (cons exp-f res))))))))
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
;;; ULisp Compiler Pass 6: Low-Level Intermediate Representation (LIR) Generator
;;; Conforms to DSN-33 Architecture Specification & ulisp/docs/lir_specification.md
;;; =======================================================================

;;; Boxed accumulators for LIR instructions and stack tracking
(define *lir-instructions* (cons '() '()))
(define *lir-min-si* (cons 0 '()))

(define (reset-lir!)
  (set-car! *lir-instructions* '())
  (set-car! *lir-min-si* 0))

(define (emit-lir! inst)
  (set-car! *lir-instructions* (cons inst (car *lir-instructions*))))

(define (track-lir-si! si)
  (if (< si (car *lir-min-si*))
      (set-car! *lir-min-si* si)))

(define (immediate? expr)
  (or (integer? expr)
      (boolean? expr)
      (char? expr)
      (null? expr)
      (string? expr)))

(define (lir-immediate expr)
  (cond
    ((integer? expr)
     (* expr 4))
    ((boolean? expr)
     (if expr 111 47))   ; 0x6F: #t, 0x2F: #f
    ((char? expr)
     (+ (* (char->integer expr) 256) 14))
    ((null? expr)
     63)                 ; 0x3F: '()
    ((string? expr)
     (let ((label (intern-string expr)))
       (list '%string-ref label)))))

(define (lir-compile-variable var env)
  (let ((binding (assq var env)))
    (if (not binding)
        (error "Unbound variable in LIR:" var)
        (let ((info (cdr binding)))
          (cond
            ((number? info)
             (emit-lir! (list '%load '%rax '%rsp info)))
            ((and (pair? info) (eq? (car info) 'param))
             (emit-lir! (list '%load '%rax '%rsp (cdr info))))
            ((and (pair? info) (eq? (car info) 'self))
             (emit-lir! (list '%load '%rax '%rsp (cdr info))))
            (else
             (error "Invalid binding format in LIR:" binding)))))))

(define (lir-compile-zero-arg op si env)
  (let ((frame-shift (align-frame-shift (- si))))
    (case op
      ((read-char)
       (emit-lir! (list '%c-call 'ulisp_read_char frame-shift)))
      ((peek-char)
       (emit-lir! (list '%c-call 'ulisp_peek_char frame-shift))))))

(define (lir-compile-unary op arg si env)
  (lir-compile-expr arg si env #f)
  (case op
    ((-)
     (emit-lir! '(%neg %rax)))
    ((fxadd1)
     (emit-lir! '(%add %rax 4)))
    ((fxsub1)
     (emit-lir! '(%sub %rax 4)))
    ((fixnum->char integer->char)
     (emit-lir! '(%shl %rax 6))
     (emit-lir! '(%bit-or %rax 14)))
    ((char->fixnum char->integer)
     (emit-lir! '(%sar %rax 6)))
    ((integer->symbol)
     (emit-lir! '(%shl %rax 6))
     (emit-lir! '(%bit-or %rax 2)))
    ((symbol->integer)
     (emit-lir! '(%sar %rax 6)))
    ((zero?)
     (emit-lir! '(%cmp %rax 0))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((fixnum? integer? number?)
     (emit-lir! '(%bit-and %rax 3))
     (emit-lir! '(%cmp %rax 0))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((boolean?)
     (emit-lir! '(%mov %rdx %rax))
     (emit-lir! '(%bit-xor %rdx 47))
     (emit-lir! '(%bit-and %rdx -65))
     (emit-lir! '(%cmp %rdx 0))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((char?)
     (emit-lir! '(%bit-and %rax 255))
     (emit-lir! '(%cmp %rax 14))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((null?)
     (emit-lir! '(%cmp %rax 63))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((not)
     (emit-lir! '(%cmp %rax 47))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((symbol?)
     (emit-lir! '(%bit-and %rax 255))
     (emit-lir! '(%cmp %rax 2))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((car)
     (emit-lir! '(%load %rax %rax -1)))
    ((cdr)
     (emit-lir! '(%load %rax %rax 7)))
    ((pair? procedure?)
     (emit-lir! '(%bit-and %rax 3))
     (emit-lir! '(%cmp %rax 1))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((string?)
     (emit-lir! '(%bit-and %rax 3))
     (emit-lir! '(%cmp %rax 3))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((write-char)
     (let ((frame-shift (align-frame-shift (- si))))
       (emit-lir! '(%mov %rdi %rax))
       (emit-lir! (list '%c-call 'ulisp_write_char frame-shift))))
    ((eof-object?)
     (emit-lir! '(%cmp %rax 79))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((make-string)
     (emit-lir! '(%sar %rax 2))
     (emit-lir! '(%mov %rcx %rax))
     (emit-lir! '(%add %rax 8))
     (emit-lir! '(%bit-and %rax -8))
     (emit-lir! '(%mov %rdx %r12))
     (emit-lir! '(%add %r12 %rax))
     (emit-lir! '(%store-byte %rdx %rcx 0))
     (emit-lir! '(%add %rdx 3))
     (emit-lir! '(%mov %rax %rdx)))
    ((string-length)
     (let ((l-loop (unique-label-sym "strlen_loop"))
           (l-done (unique-label-sym "strlen_done")))
       (emit-lir! '(%mov %rdx %rax))
       (emit-lir! '(%sub %rdx 3))
       (emit-lir! '(%mov %rax 0))
       (emit-lir! (list '%label l-loop))
       (emit-lir! '(%load-byte-zx %rcx %rdx %rax))
       (emit-lir! '(%cmp %rcx 0))
       (emit-lir! (list '%jump-if-zero l-done))
       (emit-lir! '(%inc %rax))
       (emit-lir! (list '%jump l-loop))
       (emit-lir! (list '%label l-done))
       (emit-lir! '(%shl %rax 2))))))

(define (lir-compile-binop op e1 e2 si env)
  (track-lir-si! si)
  (lir-compile-expr e1 si env #f)
  (emit-lir! (list '%store '%rsp si '%rax))
  (track-lir-si! (- si 8))
  (lir-compile-expr e2 (- si 8) env #f)
  (case op
    ((+)
     (emit-lir! (list '%add '%rax (list '%stack si))))
    ((-)
     (emit-lir! (list '%mov '%rdx (list '%stack si)))
     (emit-lir! '(%sub %rdx %rax))
     (emit-lir! '(%mov %rax %rdx)))
    ((*)
     (emit-lir! '(%sar %rax 2))
     (emit-lir! (list '%imul '%rax (list '%stack si))))
    ((modulo)
     (emit-lir! '(%mov %rcx %rax))
     (emit-lir! (list '%load '%rax '%rsp si))
     (emit-lir! '(%sar %rax 2))
     (emit-lir! '(%sar %rcx 2))
     (emit-lir! '(%cqo))
     (emit-lir! '(%idiv %rcx))
     (emit-lir! '(%mov %rax %rdx))
     (emit-lir! '(%shl %rax 2)))
    ((quotient /)
     (emit-lir! '(%mov %rcx %rax))
     (emit-lir! (list '%load '%rax '%rsp si))
     (emit-lir! '(%sar %rax 2))
     (emit-lir! '(%sar %rcx 2))
     (emit-lir! '(%cqo))
     (emit-lir! '(%idiv %rcx))
     (emit-lir! '(%shl %rax 2)))
    ((string-ref)
     (emit-lir! '(%sar %rax 2))
     (emit-lir! (list '%load '%rdx '%rsp si))
     (emit-lir! '(%sub %rdx 3))
     (emit-lir! (list '%load-byte-zx '%rax '%rdx '%rax))
     (emit-lir! '(%shl %rax 8))
     (emit-lir! '(%bit-or %rax 14)))
    ((=)
     (emit-lir! (list '%cmp (list '%stack si) '%rax))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((<)
     (emit-lir! (list '%cmp (list '%stack si) '%rax))
     (emit-lir! '(%set-boolean %rax "setl")))
    ((<=)
     (emit-lir! (list '%cmp (list '%stack si) '%rax))
     (emit-lir! '(%set-boolean %rax "setle")))
    ((>)
     (emit-lir! (list '%cmp (list '%stack si) '%rax))
     (emit-lir! '(%set-boolean %rax "setg")))
    ((>=)
     (emit-lir! (list '%cmp (list '%stack si) '%rax))
     (emit-lir! '(%set-boolean %rax "setge")))
    ((cons)
     (emit-lir! (list '%store '%rsp (- si 8) '%rax))
     (emit-lir! (list '%load '%rax '%rsp si))
     (emit-lir! '(%store %r12 0 %rax))
     (emit-lir! (list '%load '%rax '%rsp (- si 8)))
     (emit-lir! '(%store %r12 8 %rax))
     (emit-lir! '(%alloc %rax 16 1)))
    ((set-car!)
     (emit-lir! (list '%load '%rdx '%rsp si))
     (emit-lir! '(%store %rdx -1 %rax))
     (emit-lir! '(%mov %rax 63)))
    ((set-cdr!)
     (emit-lir! (list '%load '%rdx '%rsp si))
     (emit-lir! '(%store %rdx 7 %rax))
     (emit-lir! '(%mov %rax 63)))
    ((eq? char=?)
     (emit-lir! (list '%cmp (list '%stack si) '%rax))
     (emit-lir! '(%set-boolean %rax "sete")))))

(define (lir-compile-triop op e1 e2 e3 si env)
  (track-lir-si! si)
  (lir-compile-expr e1 si env #f)
  (emit-lir! (list '%store '%rsp si '%rax))
  (track-lir-si! (- si 8))
  (lir-compile-expr e2 (- si 8) env #f)
  (emit-lir! (list '%store '%rsp (- si 8) '%rax))
  (track-lir-si! (- si 16))
  (lir-compile-expr e3 (- si 16) env #f)
  (case op
    ((string-set!)
     (emit-lir! '(%shr %rax 8))
     (emit-lir! (list '%load '%rdx '%rsp si))
     (emit-lir! '(%sub %rdx 3))
     (emit-lir! (list '%load '%rcx '%rsp (- si 8)))
     (emit-lir! '(%sar %rcx 2))
     (emit-lir! '(%store-byte %rdx %rcx %al))
     (emit-lir! '(%mov %rax 63)))))

(define (lir-compile-make-closure expr si env)
  (let* ((label-arg (cadr expr))
         (label-sym (if (and (pair? label-arg) (eq? (car label-arg) 'quote))
                        (cadr label-arg)
                        label-arg))
         (args (cddr expr))
         (num-args (length args))
         (closure-size (* (+ num-args 1) 8))
         (aligned-size (if (= (modulo closure-size 16) 0) closure-size (+ closure-size 8))))
    ;; 1. Evaluate arguments sequentially and place into temporary stack slots
    (let loop ((as args) (curr-si si))
      (if (not (null? as))
          (begin
            (track-lir-si! curr-si)
            (lir-compile-expr (car as) curr-si env #f)
            (emit-lir! (list '%store '%rsp curr-si '%rax))
            (loop (cdr as) (- curr-si 8)))))
    ;; 2. Allocate closure on heap at runtime (%r12)
    (emit-lir! (list '%code-ref '%rax label-sym))
    (emit-lir! '(%store %r12 0 %rax))
    ;; 3. Copy captured arguments from stack to heap [%r12 + 8 * i]
    (let loop ((i 1) (curr-si si))
      (if (<= i num-args)
          (begin
            (emit-lir! (list '%load '%rax '%rsp curr-si))
            (emit-lir! (list '%store '%r12 (* i 8) '%rax))
            (loop (+ i 1) (- curr-si 8)))))
    ;; 4. Tag closure pointer with 0x01
    (emit-lir! (list '%alloc '%rax aligned-size 1))))

(define (lir-compile-let bindings body si env tail?)
  (let loop ((bs bindings)
             (curr-si si)
             (new-env env))
    (if (null? bs)
        (lir-compile-expr body curr-si new-env tail?)
        (let* ((b (car bs))
               (var (car b))
               (val (cadr b)))
          (track-lir-si! curr-si)
          (lir-compile-expr val curr-si env #f)
          (emit-lir! (list '%store '%rsp curr-si '%rax))
          (loop (cdr bs)
                (- curr-si 8)
                (cons (cons var curr-si) new-env))))))

(define (lir-compile-if test then else-opt si env tail?)
  (let ((else-label (unique-label-sym "L_else"))
        (end-label (unique-label-sym "L_end")))
    (lir-compile-expr test si env #f)
    (emit-lir! (list '%jump-if-false '%rax else-label))
    (lir-compile-expr then si env tail?)
    (emit-lir! (list '%jump end-label))
    (emit-lir! (list '%label else-label))
    (if (null? else-opt)
        (emit-lir! '(%mov %rax 47))
        (lir-compile-expr (car else-opt) si env tail?))
    (emit-lir! (list '%label end-label))))

(define (lir-compile-begin exprs si env tail?)
  (if (null? exprs)
      (emit-lir! '(%mov %rax 63))
      (let loop ((es exprs))
        (if (null? (cdr es))
            (lir-compile-expr (car es) si env tail?)
            (begin
              (lir-compile-expr (car es) si env #f)
              (loop (cdr es)))))))

(define (lir-compile-call proc args si env tail?)
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
            (track-lir-si! curr-si)
            (lir-compile-expr (car as) curr-si env #f)
            (emit-lir! (list '%store '%rsp curr-si '%rax))
            (loop (cdr as) (- curr-si 8)))))

    (let ((end-args-si (- aligned-si (* num-args 8))))
      (track-lir-si! end-args-si)
      ;; 2. Evaluate procedure expression -> RAX
      (lir-compile-expr proc end-args-si env #f)
      (emit-lir! '(%mov %r10 %rax))

      (if can-tco?
          ;; --- TAIL CALL OPTIMIZATION (TCO) ---
          (begin
            (let loop ((i 0))
              (if (< i num-args)
                  (let ((temp-offset (- aligned-si (* i 8)))
                        (param-offset (* 8 (- num-args i))))
                    (emit-lir! (list '%load '%rdx '%rsp temp-offset))
                    (emit-lir! (list '%store '%rsp param-offset '%rdx))
                    (loop (+ i 1)))))
            (emit-lir! '(%load %rdx %r10 -1))
            (emit-lir! '(%jump %rdx)))

          ;; --- NON-TAIL CALL ---
          (begin
            (emit-lir! (list '%call-closure frame-shift)))))))

(define (lir-compile-expr expr si env tail?)
  (cond
    ((immediate? expr)
     (let ((val (lir-immediate expr)))
       (if (and (pair? val) (eq? (car val) '%string-ref))
           (emit-lir! (list '%str-ref '%rax (cadr val)))
           (emit-lir! (list '%mov '%rax val)))))
    ((symbol? expr)
     (lir-compile-variable expr env))
    ((pair? expr)
     (let ((op (car expr)))
       (cond
         ((zero-arg-prim? op)
          (lir-compile-zero-arg op si env))
         ((eq? op '-)
          (if (null? (cddr expr))
              (lir-compile-unary '- (cadr expr) si env)
              (lir-compile-binop '- (cadr expr) (caddr expr) si env)))
         ((unary-prim? op)
          (lir-compile-unary op (cadr expr) si env))
         ((eq? op '%make-closure)
          (lir-compile-make-closure expr si env))
         ((eq? op '%closure-ref)
          (let* ((idx (caddr expr))
                 (offset (- (* idx 8) 1)))
            (lir-compile-expr (cadr expr) si env #f)
            (emit-lir! (list '%load '%rax '%rax offset))))
         ((eq? op '%closure-set!)
          (let* ((c-expr (cadr expr))
                 (idx (caddr expr))
                 (val-expr (cadddr expr))
                 (offset (- (* idx 8) 1)))
            (track-lir-si! si)
            (lir-compile-expr c-expr si env #f)
            (emit-lir! (list '%store '%rsp si '%rax))
            (track-lir-si! (- si 8))
            (lir-compile-expr val-expr (- si 8) env #f)
            (emit-lir! (list '%load '%rdx '%rsp si))
            (emit-lir! (list '%store '%rdx offset '%rax))
            (emit-lir! '(%mov %rax 63))))
         ((binop-prim? op)
          (lir-compile-binop op (cadr expr) (caddr expr) si env))
         ((triop-prim? op)
          (lir-compile-triop op (cadr expr) (caddr expr) (cadddr expr) si env))
         ((eq? op 'let)
          (lir-compile-let (cadr expr) (caddr expr) si env tail?))
         ((eq? op 'if)
          (lir-compile-if (cadr expr) (caddr expr) (cdddr expr) si env tail?))
         ((eq? op 'begin)
          (lir-compile-begin (cdr expr) si env tail?))
         ((eq? op 'quote)
          (let ((datum (cadr expr)))
            (cond
              ((symbol? datum)
               (let ((id (intern-symbol datum)))
                 (emit-lir! (list '%mov '%rax id))))
              ((immediate? datum)
               (let ((val (lir-immediate datum)))
                 (if (and (pair? val) (eq? (car val) '%string-ref))
                     (emit-lir! (list '%str-ref '%rax (cadr val)))
                     (emit-lir! (list '%mov '%rax val)))))
              ((pair? datum)
               (lir-compile-expr (list 'cons
                                       (list 'quote (car datum))
                                       (list 'quote (cdr datum)))
                                 si env #f))
              (else
               (error "Invalid quoted datum in LIR:" datum)))))
         (else
          ;; General procedure call
          (lir-compile-call op (cdr expr) si env tail?)))))
    (else
     (error "Invalid syntax in LIR compiler:" expr))))

;;; Compile a single lifted %function to LIR representation
(define (lir-compile-function fn)
  (let* ((label (cadr fn))
         (params (caddr fn))
         (body (cadddr fn))
         (num-params (length params)))
    (reset-lir!)
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
      (track-lir-si! -8)
      (track-lir-si! callee-si)
      (lir-compile-expr body callee-si callee-env #t)
      (emit-lir! '(%return))
      (let* ((needed-frame (- 0 (car *lir-min-si*)))
             (frame-size (align-frame-shift needed-frame))
             (insts (reverse (car *lir-instructions*))))
        (list '%lir-function
              label
              (list 'params params)
              (list 'frame-size frame-size)
              (cons 'body insts))))))

;;; Pass 6 Entrypoint: Transforms Pass 5 %program AST into %lir-program
(define (generate-lir prog)
  (let ((funcs (cadr prog))
        (main-expr (caddr prog)))
    (reset-lir!)
    (track-lir-si! -8)
    (lir-compile-expr main-expr -8 '() #f)
    (emit-lir! '(%return))
    (let* ((main-insts (reverse (car *lir-instructions*)))
           (main-frame (align-frame-shift (- 0 (car *lir-min-si*))))
           (lir-main (list '%lir-main
                           (list 'frame-size main-frame)
                           (cons 'body main-insts)))
           (lir-funcs (map lir-compile-function funcs)))
      (list '%lir-program
            (list 'strings (car *strings*))
            (cons '%lir-functions lir-funcs)
            lir-main))))
;;; =======================================================================
;;; ULisp Compiler Pass 7: Native x86-64 Backend Code Generator
;;; Conforms to DSN-33 Architecture Specification & ulisp/docs/lir_specification.md
;;; Consumes Pass 6 %lir-program and emits pure GNU x86-64 Intel-syntax assembly.
;;; =======================================================================

(define (emit line)
  (display line)
  (newline))

(define (emit-boolean-from-set set-inst)
  (emit (string-append "    " set-inst " al"))
  (emit "    movzx eax, al")
  (emit "    shl rax, 6")
  (emit "    add rax, 0x2F"))

(define (reg->str reg)
  (case reg
    ((%rax) "rax")
    ((%rdx) "rdx")
    ((%rcx) "rcx")
    ((%r10) "r10")
    ((%rdi) "rdi")
    ((%r12) "r12")
    ((%rsp) "rsp")
    ((%al)  "al")
    (else (symbol->string reg))))

(define (mem-op->str base offset)
  (let ((base-str (reg->str base)))
    (if (symbol? offset)
        (string-append "[" base-str " + " (reg->str offset) "]")
        (string-append "[" base-str " " (offset->string offset) "]"))))

(define (operand->str opnd)
  (cond
    ((symbol? opnd)
     (reg->str opnd))
    ((integer? opnd)
     (number->string opnd))
    ((pair? opnd)
     (let ((tag (car opnd)))
       (case tag
         ((%stack)
          (string-append "[rsp " (offset->string (cadr opnd)) "]"))
         ((%mem)
          (mem-op->str (cadr opnd) (caddr opnd)))
         (else
          (error "Unknown operand in x86-64 backend:" opnd)))))
    (else
     (error "Invalid operand type in x86-64 backend:" opnd))))

;;; Emits a single LIR instruction to x86-64 assembly
(define (emit-lir-instruction inst)
  (let ((op (car inst)))
    (case op
      ((%label)
       (let ((lbl (cadr inst)))
         (emit (string-append (if (symbol? lbl) (symbol->string lbl) lbl) ":"))))

      ((%jump)
       (let ((lbl (cadr inst)))
         (emit (string-append "    jmp " (reg->str lbl)))))

      ((%jump-if-false)
       (let ((reg (cadr inst))
             (lbl (caddr inst)))
         (emit (string-append "    cmp " (reg->str reg) ", 0x2F"))
         (emit (string-append "    je " (if (symbol? lbl) (symbol->string lbl) lbl)))))

      ((%jump-if-zero)
       (let ((lbl (cadr inst)))
         (emit (string-append "    je " (if (symbol? lbl) (symbol->string lbl) lbl)))))

      ((%return)
       (emit "    ret"))

      ((%mov)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    mov " (operand->str dst) ", " (operand->str src)))))

      ((%load)
       (let ((dst (cadr inst))
             (base (caddr inst))
             (offset (cadddr inst)))
         (emit (string-append "    mov " (reg->str dst) ", " (mem-op->str base offset)))))

      ((%store)
       (let ((base (cadr inst))
             (offset (caddr inst))
             (src (cadddr inst)))
         (emit (string-append "    mov " (mem-op->str base offset) ", " (operand->str src)))))

      ((%store-byte)
       (let ((base (cadr inst))
             (offset (caddr inst))
             (src (cadddr inst)))
         (let ((src-str (if (number? src) (number->string src) (reg->str src))))
           (emit (string-append "    mov byte ptr " (mem-op->str base offset) ", " src-str)))))

      ((%load-byte-zx)
       (let ((dst (cadr inst))
             (base (caddr inst))
             (offset (cadddr inst)))
         (emit (string-append "    movzx " (reg->str dst) ", byte ptr " (mem-op->str base offset)))))

      ((%add)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    add " (operand->str dst) ", " (operand->str src)))))

      ((%sub)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    sub " (operand->str dst) ", " (operand->str src)))))

      ((%neg)
       (let ((dst (cadr inst)))
         (emit (string-append "    neg " (operand->str dst)))))

      ((%imul)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    imul " (operand->str dst) ", " (operand->str src)))))

      ((%cqo)
       (emit "    cqo"))

      ((%idiv)
       (let ((src (cadr inst)))
         (emit (string-append "    idiv " (operand->str src)))))

      ((%inc)
       (let ((dst (cadr inst)))
         (emit (string-append "    inc " (operand->str dst)))))

      ((%shl)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    shl " (operand->str dst) ", " (number->string count)))))

      ((%shr)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    shr " (operand->str dst) ", " (number->string count)))))

      ((%sar)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    sar " (operand->str dst) ", " (number->string count)))))

      ((%bit-and)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    and " (operand->str dst) ", " (operand->str src)))))

      ((%bit-or)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    or " (operand->str dst) ", " (operand->str src)))))

      ((%bit-xor)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    xor " (operand->str dst) ", " (operand->str src)))))

      ((%cmp)
       (let ((s1 (cadr inst))
             (s2 (caddr inst)))
         (emit (string-append "    cmp " (operand->str s1) ", " (operand->str s2)))))

      ((%set-boolean)
       (let ((cc (caddr inst)))
         (emit-boolean-from-set cc)))

      ((%alloc)
       (let ((dst (cadr inst))
             (bytes (caddr inst))
             (tag (cadddr inst)))
         (emit (string-append "    lea " (operand->str dst) ", [r12 + " (number->string tag) "]"))
         (emit (string-append "    add r12, " (number->string bytes)))))

      ((%code-ref)
       (let ((dst (cadr inst))
             (lbl (caddr inst)))
         (let ((lbl-str (if (symbol? lbl) (symbol->string lbl) lbl)))
           (emit (string-append "    lea " (operand->str dst) ", [rip + " lbl-str "]")))))

      ((%str-ref)
       (let ((dst (cadr inst))
             (lbl (caddr inst)))
         (let ((lbl-str (if (symbol? lbl) (symbol->string lbl) lbl)))
           (emit (string-append "    lea " (operand->str dst) ", [rip + " lbl-str " + 3]")))))

      ((%c-call)
       (let ((func (cadr inst))
             (frame-shift (caddr inst)))
         (emit (string-append "    sub rsp, " (number->string frame-shift)))
         (emit (string-append "    call " (symbol->string func)))
         (emit (string-append "    add rsp, " (number->string frame-shift)))))

      ((%call-closure)
       (let ((frame-shift (cadr inst)))
         (if (> frame-shift 0)
             (emit (string-append "    sub rsp, " (number->string frame-shift))))
         (emit "    mov rdx, [r10 - 1]")
         (emit "    call rdx")
         (if (> frame-shift 0)
             (emit (string-append "    add rsp, " (number->string frame-shift))))))

      (else
       (error "Unknown LIR opcode in x86-64 backend:" inst)))))

;;; Emits assembly for a single %lir-function
(define (emit-x86-function fn)
  (let* ((label (cadr fn))
         (label-str (if (symbol? label) (symbol->string label) label))
         (body (cdr (assq 'body (cddr fn)))))
    (emit "    .p2align 3")
    (emit (string-append label-str ":"))
    ;; Callee prologue: self closure pointer was in r10
    ;; Store self closure pointer at [rsp - 8]
    (emit "    mov [rsp - 8], r10")
    (for-each emit-lir-instruction body)))

;;; Pass 7 Entrypoint: Takes %lir-program and emits complete GNU x86-64 assembly
(define (emit-x86-64 prog)
  (let* ((funcs-clause (assq '%lir-functions (cdr prog)))
         (funcs (if funcs-clause (cdr funcs-clause) '()))
         (main-clause (assq '%lir-main (cdr prog)))
         (main-body (cdr (assq 'body (cdr main-clause)))))
    (emit "    .intel_syntax noprefix")
    (emit "    .text")
    (emit "    .globl scheme_entry")
    (emit "    .type scheme_entry, @function")
    (emit "scheme_entry:")
    (emit "    push r12")
    (emit "    sub rsp, 8")
    (emit "    mov r12, rdi")          ; rdi contains heap_base from C runtime
    (for-each (lambda (inst)
                (if (not (eq? (car inst) '%return))
                    (emit-lir-instruction inst)))
              main-body)
    (emit "    add rsp, 8")
    (emit "    pop r12")
    (emit "    ret")
    ;; Emit all lifted procedure definitions in sequence
    (for-each emit-x86-function funcs)
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
;;; ULisp Compiler Pass 7b: Portable C / WebAssembly Backend Code Generator
;;; Conforms to DSN-33 Architecture Specification & Issue #504
;;; Consumes Pass 6 %lir-program and emits ANSI C99 source code.
;;; =======================================================================

(define (c-target-directive? form)
  (and (pair? form)
       (eq? (car form) '!target)
       (pair? (cdr form))
       (eq? (cadr form) 'c)))

(define (c-sanitize-label lbl)
  (let* ((str (if (symbol? lbl) (symbol->string lbl) lbl))
         (len (string-length str)))
    (if (and (> len 0) (char=? (string-ref str 0) #\.))
        (let ((res (make-string (+ len 5))))
          (string-set! res 0 #\u)
          (string-set! res 1 #\l)
          (string-set! res 2 #\i)
          (string-set! res 3 #\s)
          (string-set! res 4 #\p)
          (string-set! res 5 #\_)
          (let loop ((i 1))
            (if (< i len)
                (let ((c (string-ref str i)))
                  (string-set! res (+ i 5) (if (char=? c #\.) #\_ c))
                  (loop (+ i 1)))
                res)))
        str)))

(define (c-reg->str reg)
  (case reg
    ((%rax) "reg_rax")
    ((%rdx) "reg_rdx")
    ((%rcx) "reg_rcx")
    ((%r10) "reg_r10")
    ((%rdi) "reg_rdi")
    ((%r12) "reg_r12")
    ((%rsp) "reg_rsp")
    ((%al)  "((uint8_t)reg_rax)")
    (else (c-sanitize-label reg))))

(define (c-base-ptr-str base)
  (case base
    ((%rsp) "reg_rsp")
    ((%r12) "reg_r12")
    (else (string-append "((char *)(uintptr_t)" (c-reg->str base) ")"))))

(define (c-mem-ref base offset)
  (let ((base-str (c-base-ptr-str base))
        (off-str (if (number? offset) (number->string offset) (c-reg->str offset))))
    (string-append "(*(uint64_t *)(" base-str " + (" off-str ")))")))

(define (c-mem-byte-ref base offset)
  (let ((base-str (c-base-ptr-str base))
        (off-str (if (number? offset) (number->string offset) (c-reg->str offset))))
    (string-append "(*(uint8_t *)(" base-str " + (" off-str ")))")))

(define (c-operand->str opnd)
  (cond
    ((symbol? opnd)
     (c-reg->str opnd))
    ((integer? opnd)
     (number->string opnd))
    ((pair? opnd)
     (let ((tag (car opnd)))
       (case tag
         ((%stack)
          (c-mem-ref '%rsp (cadr opnd)))
         ((%mem)
          (c-mem-ref (cadr opnd) (caddr opnd)))
         (else
          (error "Unknown operand in C backend:" opnd)))))
    (else
     (error "Invalid operand type in C backend:" opnd))))

;;; Emits a single LIR instruction to ANSI C statement
(define (emit-c-instruction inst)
  (let ((op (car inst)))
    (case op
      ((%label)
       (let ((lbl (cadr inst)))
         (emit (string-append (c-sanitize-label lbl) ":;"))))

      ((%jump)
       (let ((lbl (cadr inst)))
         (if (or (eq? lbl '%rdx) (eq? lbl '%rax) (eq? lbl '%rcx))
             (emit (string-append "    ((void (*)(void))(uintptr_t)" (c-reg->str lbl) ")(); return;"))
             (emit (string-append "    goto " (c-sanitize-label lbl) ";")))))

      ((%jump-if-false)
       (let ((reg (cadr inst))
             (lbl (caddr inst)))
         (emit (string-append "    if (" (c-reg->str reg) " == 0x2F) goto " (c-sanitize-label lbl) ";"))))

      ((%jump-if-zero)
       (let ((lbl (cadr inst)))
         (emit (string-append "    if (cmp_s1 == cmp_s2) goto " (c-sanitize-label lbl) ";"))))

      ((%return)
       (emit "    return;"))

      ((%mov)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (cond
           ((eq? dst '%r12)
            (emit (string-append "    reg_r12 = (char *)(uintptr_t)(" (c-operand->str src) ");")))
           ((eq? dst '%rsp)
            (emit (string-append "    reg_rsp = (char *)(uintptr_t)(" (c-operand->str src) ");")))
           ((eq? src '%r12)
            (emit (string-append "    " (c-operand->str dst) " = (uint64_t)(uintptr_t)reg_r12;")))
           ((eq? src '%rsp)
            (emit (string-append "    " (c-operand->str dst) " = (uint64_t)(uintptr_t)reg_rsp;")))
           (else
            (emit (string-append "    " (c-operand->str dst) " = " (c-operand->str src) ";"))))))

      ((%load)
       (let ((dst (cadr inst))
             (base (caddr inst))
             (offset (cadddr inst)))
         (emit (string-append "    " (c-reg->str dst) " = " (c-mem-ref base offset) ";"))))

      ((%store)
       (let ((base (cadr inst))
             (offset (caddr inst))
             (src (cadddr inst)))
         (emit (string-append "    " (c-mem-ref base offset) " = " (c-operand->str src) ";"))))

      ((%store-byte)
       (let ((base (cadr inst))
             (offset (caddr inst))
             (src (cadddr inst)))
         (let ((src-str (if (number? src) (number->string src) (c-reg->str src))))
           (emit (string-append "    " (c-mem-byte-ref base offset) " = (uint8_t)(" src-str ");")))))

      ((%load-byte-zx)
       (let ((dst (cadr inst))
             (base (caddr inst))
             (offset (cadddr inst)))
         (emit (string-append "    " (c-reg->str dst) " = (uint64_t)(" (c-mem-byte-ref base offset) ");"))))

      ((%add)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (eq? dst '%r12)
             (emit (string-append "    reg_r12 += " (c-operand->str src) ";"))
             (emit (string-append "    " (c-operand->str dst) " += " (c-operand->str src) ";")))))

      ((%sub)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " -= " (c-operand->str src) ";"))))

      ((%neg)
       (let ((dst (cadr inst)))
         (emit (string-append "    " (c-operand->str dst) " = (uint64_t)(-(int64_t)" (c-operand->str dst) ");"))))

      ((%imul)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " = (uint64_t)((int64_t)" (c-operand->str dst) " * (int64_t)" (c-operand->str src) ");"))))

      ((%cqo)
       (emit "    /* cqo */"))

      ((%idiv)
       (let ((src (cadr inst)))
         (emit (string-append "    reg_rax = (uint64_t)((int64_t)reg_rax / (int64_t)" (c-operand->str src) ");"))))

      ((%inc)
       (let ((dst (cadr inst)))
         (emit (string-append "    " (c-operand->str dst) "++;"))))

      ((%shl)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " <<= " (number->string count) ";"))))

      ((%shr)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " >>= " (number->string count) ";"))))

      ((%sar)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " = (uint64_t)(((int64_t)" (c-operand->str dst) ") >> " (number->string count) ");"))))

      ((%bit-and)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " &= " (c-operand->str src) ";"))))

      ((%bit-or)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " |= " (c-operand->str src) ";"))))

      ((%bit-xor)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " ^= " (c-operand->str src) ";"))))

      ((%cmp)
       (let ((s1 (cadr inst))
             (s2 (caddr inst)))
         (emit (string-append "    cmp_s1 = " (c-operand->str s1) "; cmp_s2 = " (c-operand->str s2) ";"))))

      ((%set-boolean)
       (let ((dst (cadr inst))
             (cc (caddr inst)))
         (cond
           ((string=? cc "sete")
            (emit (string-append "    " (c-reg->str dst) " = (cmp_s1 == cmp_s2) ? 0x6F : 0x2F;")))
           ((string=? cc "setne")
            (emit (string-append "    " (c-reg->str dst) " = (cmp_s1 != cmp_s2) ? 0x6F : 0x2F;")))
           ((string=? cc "setl")
            (emit (string-append "    " (c-reg->str dst) " = ((int64_t)cmp_s1 < (int64_t)cmp_s2) ? 0x6F : 0x2F;")))
           ((string=? cc "setle")
            (emit (string-append "    " (c-reg->str dst) " = ((int64_t)cmp_s1 <= (int64_t)cmp_s2) ? 0x6F : 0x2F;")))
           ((string=? cc "setg")
            (emit (string-append "    " (c-reg->str dst) " = ((int64_t)cmp_s1 > (int64_t)cmp_s2) ? 0x6F : 0x2F;")))
           ((string=? cc "setge")
            (emit (string-append "    " (c-reg->str dst) " = ((int64_t)cmp_s1 >= (int64_t)cmp_s2) ? 0x6F : 0x2F;")))
           (else
            (error "Unknown condition code in C backend:" cc)))))

      ((%alloc)
       (let ((dst (cadr inst))
             (bytes (caddr inst))
             (tag (cadddr inst)))
         (emit (string-append "    " (c-operand->str dst) " = ((uint64_t)(uintptr_t)reg_r12) + " (number->string tag) ";"))
         (emit (string-append "    reg_r12 += " (number->string bytes) ";"))))

      ((%code-ref)
       (let ((dst (cadr inst))
             (lbl (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " = (uint64_t)(uintptr_t)" (c-sanitize-label lbl) ";"))))

      ((%str-ref)
       (let ((dst (cadr inst))
             (lbl (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " = ((uint64_t)(uintptr_t)" (c-sanitize-label lbl) ") + 3;"))))

      ((%c-call)
       (let ((func (cadr inst))
             (frame-shift (caddr inst)))
         (cond
           ((eq? func 'ulisp_read_char)
            (if (> frame-shift 0) (emit (string-append "    reg_rsp -= " (number->string frame-shift) ";")))
            (emit "    reg_rax = ulisp_read_char();")
            (if (> frame-shift 0) (emit (string-append "    reg_rsp += " (number->string frame-shift) ";"))))
           ((eq? func 'ulisp_peek_char)
            (if (> frame-shift 0) (emit (string-append "    reg_rsp -= " (number->string frame-shift) ";")))
            (emit "    reg_rax = ulisp_peek_char();")
            (if (> frame-shift 0) (emit (string-append "    reg_rsp += " (number->string frame-shift) ";"))))
           ((eq? func 'ulisp_write_char)
            (if (> frame-shift 0) (emit (string-append "    reg_rsp -= " (number->string frame-shift) ";")))
            (emit "    reg_rax = ulisp_write_char(reg_rdi);")
            (if (> frame-shift 0) (emit (string-append "    reg_rsp += " (number->string frame-shift) ";"))))
           (else
            (if (> frame-shift 0) (emit (string-append "    reg_rsp -= " (number->string frame-shift) ";")))
            (emit (string-append "    reg_rax = " (symbol->string func) "();"))
            (if (> frame-shift 0) (emit (string-append "    reg_rsp += " (number->string frame-shift) ";")))))))

      ((%call-closure)
       (let ((frame-shift (cadr inst)))
         (emit "    reg_rdx = *(uint64_t *)((char *)(uintptr_t)reg_r10 - 1);")
         (emit (string-append "    reg_rsp -= " (number->string (+ frame-shift 8)) ";"))
         (emit "    ((void (*)(void))(uintptr_t)reg_rdx)();")
         (emit (string-append "    reg_rsp += " (number->string (+ frame-shift 8)) ";"))))

      (else
       (error "Unknown LIR opcode in C backend:" inst)))))

;;; Emits C code for a single %lir-function
(define (emit-c-function fn)
  (let* ((label (cadr fn))
         (label-str (c-sanitize-label label))
         (body (cdr (assq 'body (cddr fn)))))
    (emit (string-append "static void " label-str "(void) {"))
    (emit "    *(uint64_t *)(reg_rsp - 8) = reg_r10;")
    (for-each emit-c-instruction body)
    (emit "}")
    (emit "")))

;;; Pass 7b Entrypoint: Takes %lir-program and emits complete ANSI C99 source
(define (emit-c prog)
  (let* ((funcs-clause (assq '%lir-functions (cdr prog)))
         (funcs (if funcs-clause (cdr funcs-clause) '()))
         (main-clause (assq '%lir-main (cdr prog)))
         (main-body (cdr (assq 'body (cdr main-clause)))))
    (emit "/* Generated by ULisp Portable C / WebAssembly Backend */")
    (emit "#include <stdint.h>")
    (emit "#include <stdio.h>")
    (emit "#include <stdlib.h>")
    (emit "")
    (emit "extern uint64_t ulisp_read_char(void);")
    (emit "extern uint64_t ulisp_peek_char(void);")
    (emit "extern uint64_t ulisp_write_char(uint64_t val);")
    (emit "#if defined(__GNUC__) || defined(__clang__)")
    (emit "#define ULISP_UNUSED __attribute__((unused))")
    (emit "#else")
    (emit "#define ULISP_UNUSED")
    (emit "#endif")
    (emit "")
    (emit "static uint64_t reg_rax ULISP_UNUSED;")
    (emit "static uint64_t reg_rdx ULISP_UNUSED;")
    (emit "static uint64_t reg_rcx ULISP_UNUSED;")
    (emit "static uint64_t reg_r10 ULISP_UNUSED;")
    (emit "static uint64_t reg_rdi ULISP_UNUSED;")
    (emit "static char *reg_r12 ULISP_UNUSED;")
    (emit "static char *reg_rsp ULISP_UNUSED;")
    (emit "static uint64_t cmp_s1 ULISP_UNUSED;")
    (emit "static uint64_t cmp_s2 ULISP_UNUSED;")
    (emit "static char stack_mem[64 * 1024 * 1024];")
    (emit "")
    ;; Forward declarations of lifted functions
    (for-each (lambda (fn)
                (let* ((lbl (cadr fn))
                       (lbl-str (c-sanitize-label lbl)))
                  (emit (string-append "static void " lbl-str "(void);"))))
              funcs)
    (emit "")
    ;; Emit string literals
    (if (not (null? (car *strings*)))
        (let loop ((ss (reverse (car *strings*))))
          (if (not (null? ss))
              (let* ((entry (car ss))
                     (lbl-str (c-sanitize-label (car entry)))
                     (escaped (escape-gas-string (cdr entry))))
                (emit (string-append "static const char " lbl-str "[] = \"" escaped "\";"))
                (loop (cdr ss))))))
    (emit "")
    ;; Emit lifted function bodies
    (for-each emit-c-function funcs)
    ;; Emit scheme_entry
    (emit "uint64_t scheme_entry(char *heap_base) {")
    (emit "    reg_r12 = heap_base;")
    (emit "    reg_rsp = stack_mem + sizeof(stack_mem) - 1024;")
    (for-each (lambda (inst)
                (if (not (eq? (car inst) '%return))
                    (emit-c-instruction inst)))
              main-body)
    (emit "    return reg_rax;")
    (emit "}")
    (emit "")))
;;; =======================================================================
;;; ULisp Compiler Pass 8: Compilation Driver & CLI Entrypoint
;;; Conforms to DSN-33 Architecture Specification & Issue #504
;;; =======================================================================

(define (read-all-forms)
  (let loop ((acc '()))
    (let ((expr (read)))
      (if (eof-object? expr)
          (reverse acc)
          (loop (cons expr acc))))))

(define (extract-target-and-forms raw-forms)
  (if (and (pair? raw-forms)
           (pair? (car raw-forms))
           (eq? (caar raw-forms) '!target))
      (cons (cadar raw-forms) (cdr raw-forms))
      (cons 'x86_64 raw-forms)))

;;; Entry point: read all S-expressions from standard input and compile through serial pipeline
(let* ((raw (read-all-forms))
       (target-and-forms (extract-target-and-forms raw))
       (target (car target-and-forms))
       (forms (cdr target-and-forms)))
  (if (not (null? forms))
      (let* ((macro-expanded (expand-macros-in-forms forms))
             (ast0 (rewrite-top-level macro-expanded))
             (ast1 (desugar-all ast0))
             (ast2 (cp0-optimize ast1))
             (ast3 (anf-all ast2))
             (ast4 (closure-convert ast3))
             (lir  (generate-lir ast4)))
        (if (eq? target 'c)
            (emit-c lir)
            (emit-x86-64 lir)))))
