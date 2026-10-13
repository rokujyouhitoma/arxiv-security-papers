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

(define (string-equal? s1 s2)
  (and (string? s1) (string? s2)
       (not (boolean? s1)) (not (boolean? s2))
       (= (string-length s1) (string-length s2))
       (let loop ((i 0) (len (string-length s1)))
         (if (= i len)
             #t
             (if (char=? (string-ref s1 i) (string-ref s2 i))
                 (loop (+ i 1) len)
                 #f)))))

(define (equal? a b)
  (cond
    ((eq? a b) #t)
    ((and (number? a) (number? b)) (= a b))
    ((and (string? a) (string? b)) (string-equal? a b))
    ((and (char? a) (char? b)) (char=? a b))
    ((and (pair? a) (pair? b))
     (and (equal? (car a) (car b))
          (equal? (cdr a) (cdr b))))
    (else #f)))

(define (assoc item ls)
  (cond
    ((not (pair? ls)) #f)
    ((not (pair? (car ls))) (assoc item (cdr ls)))
    ((equal? (caar ls) item) (car ls))
    (else (assoc item (cdr ls)))))

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
  (let loop ((cur ls) (acc '()))
    (if (null? cur)
        (reverse acc)
        (loop (cdr cur) (cons (f (car cur)) acc)))))

(define (for-each proc ls)
  (let loop ((cur ls))
    (if (not (null? cur))
        (begin
          (proc (car cur))
          (loop (cdr cur))))))

(define (filter pred ls)
  (let loop ((cur ls) (acc '()))
    (cond
      ((null? cur) (reverse acc))
      ((pred (car cur)) (loop (cdr cur) (cons (car cur) acc)))
      (else (loop (cdr cur) acc)))))

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
  (memq op '(read-char peek-char eof-object flush-output-port ulisp-flush %get-rsp %get-heap-ptr %get-gc-state-ptr %get-stackmap-table)))

(define (unary-prim? op)
  (memq op '(fxadd1 fxsub1 fixnum->char char->fixnum integer->char char->integer
             integer->symbol symbol->integer
             zero? fixnum? integer? number? boolean? char? null? not symbol?
             car cdr pair? procedure? string?
             write-char write-string flush-output-port ulisp-flush eof-object?
             make-string string-length
             %set-heap-ptr! %ptr-tag %ptr-untag
             %to-raw %to-fixnum
             %box-fixnum %unbox-fixnum)))

(define (binop-prim? op)
  (memq op '(+ - * = < <= > >= modulo quotient / string-ref cons set-car! set-cdr! eq? char=?
             %raw-load %ptr-add %ptr-tag-add bitwise-and bitwise-ior bitwise-arithmetic-shift
             %raw-add %raw-sub %raw-mul %raw-cmp)))

(define (triop-prim? op)
  (memq op '(string-set! %raw-store!)))

(define (septop-prim? op)
  (memq op '(%raw-syscall)))

(define (closure-prim? op)
  (memq op '(%make-closure %closure-ref %closure-set!)))

(define (pure-prim? op)
  (memq op '(fxadd1 fxsub1 fixnum->char char->fixnum integer->char char->integer
             integer->symbol symbol->integer
             zero? fixnum? integer? number? boolean? char? null? not symbol?
             car cdr pair? procedure? string? string-length %ptr-add %ptr-tag %ptr-untag %ptr-tag-add
             %to-raw %to-fixnum %box-fixnum %unbox-fixnum
             + - * = < <= > >= modulo quotient / eq? char=? cons %closure-ref
             %raw-add %raw-sub %raw-mul %raw-cmp)))

(define (const? x)
  (or (number? x)
      (boolean? x)
      (char? x)
      (null? x)
      (and (pair? x) (eq? (car x) 'quote))))

(define (atomic-expr? expr)
  (or (symbol? expr)
      (const? expr)))

(define (extract-const-val c)
  (if (and (pair? c) (eq? (car c) 'quote))
      (cadr c)
      c))

(define (val->ast-const v)
  (cond
    ((number? v) v)
    ((boolean? v) v)
    ((char? v) v)
    ((null? v) '(quote ()))
    (else (list 'quote v))))

(define (commutative-op? op)
  (memq op '(+ * = eq? char=?)))

(define (type-predicate-op? op)
  (memq op '(fixnum? integer? number? pair? null? boolean? char? symbol? zero? procedure? string?)))

(define (pure-accessor-op? op)
  (memq op '(car cdr)))

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
         ((letrec)
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
           (else #f))))
      (else #f))))

;;; Symbol table for interned symbols
(define *symbol-table* (cons '() '()))
(define (reset-symbol-table!)
  (set-car! *symbol-table* '()))

(define (symbol-hash-str str)
  (let ((len (string-length str)))
    (let loop ((i 0) (h 5381))
      (if (= i len)
          (modulo h 16777213)
          (let ((c (char->integer (string-ref str i))))
            (loop (+ i 1)
                  (modulo (+ (* h 33) c) 16777213)))))))

(define (intern-symbol sym)
  (let ((entry (assq sym (car *symbol-table*))))
    (if entry
        (cadr entry)
        (let* ((str (symbol->string sym))
               (h (symbol-hash-str str))
               (id (+ (* h 256) 2)))
          (set-car! *symbol-table* (cons (list sym id str) (car *symbol-table*)))
          id))))

(define (symbol->raw-name sym)
  (let ((entry (assq sym (car *symbol-table*))))
    (if (and entry (pair? (cdr entry)) (pair? (cddr entry)))
        (caddr entry)
        (symbol->string sym))))

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
          '())
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
            ((or (unary-prim? op) (or (binop-prim? op) (or (triop-prim? op) (septop-prim? op))))
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

;;; Note: extract-const-val, val->ast-const, pure-expr?, and fold-const-op
;;;       are provided canonically by passes/00_helpers.scm.

;;; Top-level & nested letrec Dead Code Elimination (DCE) based on Reachability Call Graph
(define (dce-letrec bindings body)
  (let* ((rec-vars (map car* bindings))
         (rec-filter (lambda (vars)
                       (filter (lambda (v) (memq v rec-vars)) vars)))
         ;; Map each binding var to its immediate dependencies within rec-vars
         (dep-alist (map (lambda (b)
                           (cons (car b) (rec-filter (free-vars (cadr b) '()))))
                         bindings))
         ;; Root variables:
         ;; 1. Variables in rec-vars that appear free in the body
         (body-roots (rec-filter (free-vars body '())))
         ;; 2. Variables in rec-vars whose initialization is impure (has side effects)
         (impure-roots (let loop ((bs bindings) (acc '()))
                         (cond
                           ((null? bs) acc)
                           ((not (pure-expr? (cadar bs)))
                            (loop (cdr bs) (cons (caar bs) acc)))
                           (else
                            (loop (cdr bs) acc)))))
         (initial-roots (set-union body-roots impure-roots)))
    ;; Transitive closure via worklist
    (let ((reachable
           (let loop ((worklist initial-roots) (visited '()))
             (if (null? worklist)
                 visited
                 (let ((v (car worklist))
                       (rest (cdr worklist)))
                   (if (memq v visited)
                       (loop rest visited)
                       (let* ((v-deps (let ((entry (assq v dep-alist)))
                                        (if entry (cdr entry) '())))
                              (new-worklist (append v-deps rest)))
                         (loop new-worklist (cons v visited)))))))))
      ;; Retain only bindings in reachable set
      (let ((kept-bindings (filter (lambda (b) (memq (car b) reachable)) bindings)))
        (if (null? kept-bindings)
            body
            (list 'letrec kept-bindings body))))))

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
                  (map (lambda (b) (list (car b) (cp0-expr (cadr b)))) bindings))
                 (body-frees (free-vars body '()))
                 (kept-bindings
                  (filter (lambda (b)
                            (or (not (pure-expr? (cadr b)))
                                (memq (car b) body-frees)))
                          opt-bindings)))
            (if (null? kept-bindings)
                body
                (list 'let kept-bindings body))))
         ((letrec)
          (let* ((bindings (cadr expr))
                 (body (cp0-expr (caddr expr)))
                 (opt-bindings
                  (map (lambda (b) (list (car b) (cp0-expr (cadr b)))) bindings)))
            (dce-letrec opt-bindings body)))
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
           ((= eq? char=?)
            (cond
              ;; (= x x) -> #t, (eq? x x) -> #t
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
;;; 2. Lattice Join (Least Upper Bound: LUB, \sqcup)
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

;;; -----------------------------------------------------------------------
;;; 3. Type Environment Management
;;; -----------------------------------------------------------------------

(define (type-env-lookup var env)
  (let ((entry (assq var env)))
    (if entry
        (cdr entry)
        (type-top))))

(define (type-env-extend var type env)
  (cons (cons var type) env))

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
               (t1 (cdar rest))
               (t2 (type-env-lookup var env2)))
          (loop (cdr rest) (cons (cons var (type-lub t1 t2)) acc))))))

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
    ((memq op '(= < <= > >= eq? char=? zero? fixnum? integer? number? boolean? char? null? not symbol? pair? procedure? string? eof-object?))
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
    ((eq? op 'string-length)
     (type-fixnum))
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
         ;; Conditional branching
         ((if)
          (let* ((then-t (abstract-eval-expr (caddr expr) env))
                 (else-t (if (null? (cdddr expr))
                             (type-boolean)
                             (abstract-eval-expr (cadddr expr) env))))
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
                                           (val-t (abstract-eval-expr (cadr b) env)))
                                      (if (not (temp-var? var))
                                          (record-var-type! var val-t))
                                      (bind-loop (cdr bs) (type-env-extend var val-t e)))))))
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
;;; =======================================================================
;;; ULisp Compiler Pass 5b: S-RTyper (Representation Typer & Unboxing Lowering)
;;; Conforms to DSN-33 Architecture Specification & Issue #518
;;; Note: Lowers high-level abstract types (inferred by S-Annotator Pass 4b)
;;;       to concrete hardware representations (%raw-i64, untagged registers).
;;;       Eliminates sar/sal tagging overhead in pure arithmetic loops and
;;;       inserts explicit boxing/unboxing boundaries at Scheme dynamic edges.
;;; =======================================================================

(define *unboxed-functions* (cons '() '()))

(define (reset-rtyper!)
  (set-car! *unboxed-functions* '()))

(define (record-unboxed-fn! name)
  (set-car! *unboxed-functions* (cons name (car *unboxed-functions*))))

(define (unboxed-fn? name)
  (memq name (car *unboxed-functions*)))

(define (raw-var? var raw-env)
  (memq var raw-env))

(define (all-fixnum-params? params)
  (let loop ((ps params))
    (if (null? ps)
        #t
        (let ((t (get-var-type (car ps))))
          (if (and t (type-fixnum? t))
              (loop (cdr ps))
              #f)))))

;;; Fast O(1) detection of pure tail-recursive loops (maximum depth 30)
(define (pure-tail-loop? fn-name lbody)
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
      (else #f))))

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
    (else
     (list op e1 e2))))

;;; Recursively rewrites ANF AST to Typed LIR representation
(define (rtyper-expr expr raw-env)
  (cond
    ((not (pair? expr)) expr)
    (else
     (let ((op (car expr)))
       (cond
         ((eq? op 'quote) expr)
         ((eq? op 'if)
          (let ((test (rtyper-expr (cadr expr) raw-env))
                (then (rtyper-expr (caddr expr) raw-env))
                (else-expr (if (null? (cdddr expr)) '() (rtyper-expr (cadddr expr) raw-env))))
            (if (null? else-expr)
                (list 'if test then)
                (list 'if test then else-expr))))
         ((eq? op 'begin)
          (cons 'begin (map (lambda (e) (rtyper-expr e raw-env)) (cdr expr))))
         ((memq op '(let letrec))
          (let* ((bindings (cadr expr))
                 (body (caddr expr)))
            (if (and (= (length bindings) 1)
                     (let* ((b (car bindings))
                            (val (cadr b)))
                       (and (pair? val)
                            (eq? (car val) 'lambda)
                            (pair? (cadr val))
                            (all-fixnum-params? (cadr val))
                            (pure-tail-loop? (car b) (caddr val)))))
                ;; Named-let loop with 100% fixnum parameters and pure tail-recursion:
                ;; Lower all loop variables to raw %raw-i64 hardware representation.
                (let* ((b (car bindings))
                       (fn-name (car b))
                       (fn-val (cadr b))
                       (params (cadr fn-val))
                       (lbody (caddr fn-val))
                       (loop-raw-env (append params raw-env)))
                  (record-unboxed-fn! fn-name)
                  (let* ((typed-lbody (rtyper-expr lbody loop-raw-env))
                         (boxed-lbody (box-raw-exit typed-lbody params fn-name))
                         (new-fn-val (list 'lambda params boxed-lbody))
                         (new-body (rtyper-expr body raw-env)))
                    (list op (list (list fn-name new-fn-val)) new-body)))
                ;; Standard let bindings: propagate raw variables
                (let* ((new-bindings
                        (map (lambda (b)
                               (list (car b) (rtyper-expr (cadr b) raw-env)))
                             bindings))
                       ;; Extend raw-env with newly bound variables that hold raw values
                       (extended-raw-env
                        (let loop ((bs new-bindings) (acc raw-env))
                          (if (null? bs) acc
                              (let* ((b (car bs))
                                     (var (car b))
                                     (val (cadr b)))
                                (if (and (pair? val)
                                         (memq (car val) '(%raw-add %raw-sub %raw-mul %unbox-fixnum)))
                                    (loop (cdr bs) (cons var acc))
                                    (loop (cdr bs) acc))))))
                       (new-body (rtyper-expr body extended-raw-env)))
                  (list op new-bindings new-body)))))
         ((eq? op '-)
          (if (null? (cddr expr))
              (list '- (rtyper-expr (cadr expr) raw-env))
              (rtyper-binop op (rtyper-expr (cadr expr) raw-env) (rtyper-expr (caddr expr) raw-env) raw-env)))
         ((binop-prim? op)
          (rtyper-binop op (rtyper-expr (cadr expr) raw-env) (rtyper-expr (caddr expr) raw-env) raw-env))
         ((unboxed-fn? op)
          ;; Boundary call into an unboxed loop: unbox non-raw arguments at entry
          (let ((args (cdr expr)))
            (cons op
                  (map (lambda (arg)
                         (if (and (symbol? arg) (raw-var? arg raw-env))
                             arg
                             (list '%unbox-fixnum (rtyper-expr arg raw-env))))
                       args))))
         (else
          ;; General procedure call or syntax
          (cons op (map (lambda (e) (rtyper-expr e raw-env)) (cdr expr)))))))))

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
             (map (lambda (d) (rtyper-expr d '())) defs)
             (rtyper-expr main '()))))
    ((eq? (car form-or-forms) 'define)
     (let ((head (cadr form-or-forms))
           (body (cddr form-or-forms)))
       (cons 'define
             (cons head
                   (map (lambda (e) (rtyper-expr e '())) body)))))
    (else
     (rtyper-expr form-or-forms '()))))
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
          expr)
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
(define *lir-safepoints* (cons '() '()))
(define *safepoint-counter* (cons 0 '()))

(define (reset-safepoints!)
  (set-car! *lir-safepoints* '())
  (set-car! *safepoint-counter* 0))

(define (new-safepoint-label!)
  (let* ((cnt (+ (car *safepoint-counter*) 1))
         (lbl-sym (string->symbol (string-append "__safepoint_" (number->string cnt)))))
    (set-car! *safepoint-counter* cnt)
    lbl-sym))

(define (record-safepoint! lbl frame-size bitmap)
  (set-car! *lir-safepoints*
            (cons (list lbl frame-size bitmap) (car *lir-safepoints*))))

(define (power-of-2 k)
  (let loop ((i 0) (acc 1))
    (if (< i k)
        (loop (+ i 1) (* acc 2))
        acc)))

(define (get-raw-vars env)
  (let ((entry (assq '%raw-vars env)))
    (if entry (cdr entry) '())))

(define (set-raw-vars rvars env)
  (cons (cons '%raw-vars rvars) env))

(define (raw-expr? expr raw-env)
  (cond
    ((not (pair? expr))
     (and (symbol? expr) (memq expr raw-env)))
    ((memq (car expr) '(%raw-add %raw-sub %raw-mul %raw-cmp %raw-load %raw-syscall %to-raw %unbox-fixnum))
     #t)
    (else #f)))

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
      ((%get-rsp)
       (emit-lir! '(%mov %rax %rsp)))
      ((%get-heap-ptr)
       (emit-lir! '(%mov %rax %r12)))
      ((%get-gc-state-ptr)
       (emit-lir! (list '%code-ref '%rax "ulisp_gc_state")))
      ((%get-stackmap-table)
       (emit-lir! (list '%code-ref '%rax "__ulisp_stackmap_table")))
      ((eof-object)
       (emit-lir! '(%mov %rax 79)))
      ((read-char)
       (emit-lir! (list '%c-call "ulisp_read_char" frame-shift)))
      ((peek-char)
       (emit-lir! (list '%c-call "ulisp_peek_char" frame-shift)))
      ((flush-output-port ulisp-flush)
       (emit-lir! (list '%c-call "ulisp_flush" frame-shift))))))

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
     (emit-lir! '(%bit-and %rax 7))
     (emit-lir! '(%cmp %rax 3))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((write-char)
     (let ((frame-shift (align-frame-shift (- si))))
       (emit-lir! '(%mov %rdi %rax))
       (emit-lir! (list '%c-call "ulisp_write_char" frame-shift))))
    ((write-string)
     (let ((frame-shift (align-frame-shift (- si))))
       (emit-lir! '(%mov %rdi %rax))
       (emit-lir! (list '%c-call "ulisp_write_string" frame-shift))))
    ((flush-output-port ulisp-flush)
     (let ((frame-shift (align-frame-shift (- si))))
       (emit-lir! (list '%c-call "ulisp_flush" frame-shift))))
    ((eof-object?)
     (emit-lir! '(%cmp %rax 79))
     (emit-lir! '(%set-boolean %rax "sete")))
    ((%set-heap-ptr!)
     (emit-lir! '(%mov %r12 %rax)))
    ((%ptr-tag)
     (emit-lir! '(%bit-and %rax 3))
     (emit-lir! '(%shl %rax 2)))
    ((%ptr-untag)
     (emit-lir! '(%bit-and %rax -8)))
    ((%to-raw)
     (emit-lir! '(%sar %rax 2)))
    ((%to-fixnum)
     (emit-lir! '(%shl %rax 2)))
    ((%box-fixnum)
     (emit-lir! '(%box-fixnum %rax %rax)))
    ((%unbox-fixnum)
     (emit-lir! '(%unbox-fixnum %rax %rax)))
    ((make-string)
     (emit-lir! '(%sar %rax 2))
     (emit-lir! '(%mov %rcx %rax))
     (emit-lir! '(%add %rax 8))
     (emit-lir! '(%bit-and %rax -8))
     (emit-lir! '(%mov %rdx %rax))
     (emit-lir! '(%shl %rdx 16))
     (emit-lir! '(%bit-or %rdx 3))
      (emit-lir! '(%shl %rdx 2))
     (emit-lir! '(%store %r12 0 %rdx))
     (emit-lir! '(%mov %rdx %r12))
     (emit-lir! '(%add %rdx 8))
     (emit-lir! '(%add %rax 8))
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

(define (lir-compile-operand-for-op op e si env)
  (if (and (integer? e) (memq op '(%raw-add %raw-sub %raw-mul %raw-cmp)))
      (emit-lir! (list '%mov '%rax e))
      (lir-compile-expr e si env #f)))

(define (lir-compile-binop op e1 e2 si env)
  (track-lir-si! si)
  (lir-compile-operand-for-op op e1 si env)
  (emit-lir! (list '%store '%rsp si '%rax))
  (track-lir-si! (- si 8))
  (lir-compile-operand-for-op op e2 (- si 8) env)
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
    ((%raw-add)
     (emit-lir! (list '%raw-add '%rax (list '%stack si))))
    ((%raw-sub)
     (emit-lir! (list '%mov '%rdx (list '%stack si)))
     (emit-lir! '(%raw-sub %rdx %rax))
     (emit-lir! '(%mov %rax %rdx)))
    ((%raw-mul)
     (emit-lir! (list '%raw-mul '%rax (list '%stack si))))
    ((%raw-cmp)
     (emit-lir! (list '%raw-cmp (list '%stack si) '%rax)))
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
    ((bitwise-and)
     (emit-lir! (list '%bit-and '%rax (list '%stack si))))
    ((bitwise-ior)
     (emit-lir! (list '%bit-or '%rax (list '%stack si))))
    ((%raw-load)
     (emit-lir! '(%sar %rax 2))
     (emit-lir! (list '%load '%rdx '%rsp si))
     (emit-lir! '(%add %rdx %rax))
     (emit-lir! '(%load %rax %rdx 0)))
    ((%ptr-add %ptr-tag-add)
     (emit-lir! '(%sar %rax 2))
     (emit-lir! (list '%add '%rax (list '%stack si))))
    ((cons)
     (emit-lir! (list '%store '%rsp (- si 8) '%rax))
     (emit-lir! (list '%load '%rax '%rsp si))
     (emit-lir! '(%mov %rdx 4196356))
     (emit-lir! '(%store %r12 0 %rdx))
     (emit-lir! '(%store %r12 8 %rax))
     (emit-lir! (list '%load '%rax '%rsp (- si 8)))
     (emit-lir! '(%store %r12 16 %rax))
     (emit-lir! '(%alloc %rax 24 9)))
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
     (emit-lir! '(%mov %rax 63)))
    ((%raw-store!)
     (emit-lir! '(%mov %r10 %rax))
     (emit-lir! (list '%load '%rcx '%rsp (- si 8)))
     (emit-lir! '(%sar %rcx 2))
     (emit-lir! (list '%load '%rdx '%rsp si))
     (emit-lir! '(%add %rdx %rcx))
     (emit-lir! '(%store %rdx 0 %r10))
     (emit-lir! '(%mov %rax 63)))))

(define (lir-compile-raw-syscall args si env)
  (let ((num (car args))
        (a1 (car (cdr args)))
        (a2 (car (cdr (cdr args))))
        (a3 (car (cdr (cdr (cdr args)))))
        (a4 (car (cdr (cdr (cdr (cdr args))))))
        (a5 (car (cdr (cdr (cdr (cdr (cdr args)))))))
        (a6 (car (cdr (cdr (cdr (cdr (cdr (cdr args)))))))))
    (track-lir-si! si)
    (lir-compile-expr num si env #f)
    (emit-lir! (list '%store '%rsp si '%rax))
    (track-lir-si! (- si 8))
    (lir-compile-expr a1 (- si 8) env #f)
    (emit-lir! (list '%store '%rsp (- si 8) '%rax))
    (track-lir-si! (- si 16))
    (lir-compile-expr a2 (- si 16) env #f)
    (emit-lir! (list '%store '%rsp (- si 16) '%rax))
    (track-lir-si! (- si 24))
    (lir-compile-expr a3 (- si 24) env #f)
    (emit-lir! (list '%store '%rsp (- si 24) '%rax))
    (track-lir-si! (- si 32))
    (lir-compile-expr a4 (- si 32) env #f)
    (emit-lir! (list '%store '%rsp (- si 32) '%rax))
    (track-lir-si! (- si 40))
    (lir-compile-expr a5 (- si 40) env #f)
    (emit-lir! (list '%store '%rsp (- si 40) '%rax))
    (track-lir-si! (- si 48))
    (lir-compile-expr a6 (- si 48) env #f)
    (emit-lir! (list '%store '%rsp (- si 48) '%rax))
    (emit-lir! (list '%load '%rax '%rsp si))
    (emit-lir! (list '%load '%rdi '%rsp (- si 8)))
    (emit-lir! (list '%load '%rsi '%rsp (- si 16)))
    (emit-lir! (list '%load '%rdx '%rsp (- si 24)))
    (emit-lir! (list '%load '%r10 '%rsp (- si 32)))
    (emit-lir! (list '%load '%r8 '%rsp (- si 40)))
    (emit-lir! (list '%load '%r9 '%rsp (- si 48)))
    (emit-lir! '(%syscall))))

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
    ;; 2. Allocate closure with 8B prefix header on heap at runtime (%r12)
    (let* ((hdr-val (+ (* aligned-size 65536) (* (+ num-args 1) 256) 2))
           (hdr-fixnum (* hdr-val 4)))
      (emit-lir! (list '%mov '%rdx hdr-fixnum))
      (emit-lir! '(%store %r12 0 %rdx)))
    (emit-lir! (list '%code-ref '%rax label-sym))
    (emit-lir! '(%store %r12 8 %rax))
    ;; 3. Copy captured arguments from stack to heap [%r12 + 8 + 8 * i]
    (let loop ((i 1) (curr-si si))
      (if (<= i num-args)
          (begin
            (emit-lir! (list '%load '%rax '%rsp curr-si))
            (emit-lir! (list '%store '%r12 (+ 8 (* i 8)) '%rax))
            (loop (+ i 1) (- curr-si 8)))))
    ;; 4. Tag closure pointer with 0x01 (offset +8 from header)
    (emit-lir! (list '%alloc '%rax (+ aligned-size 8) 9))))

(define (compute-stackmap-bitmap frame-shift aligned-si args env)
  (let* ((slot-count (quotient frame-shift 8))
         (rvars (get-raw-vars env)))
    (let loop ((k 0) (bitmap 0))
      (if (or (>= k slot-count) (>= k 60))
          bitmap
          (let* ((slot-offset (- (* k 8) frame-shift))
                 (is-ptr
                  (if (= slot-offset -8)
                      #t
                      (let ((arg-res
                             (let check-arg ((cur-args args) (i 0))
                               (if (null? cur-args)
                                   #f
                                   (let ((arg-si (- aligned-si (* i 8))))
                                     (if (= slot-offset arg-si)
                                         (cons #t (not (raw-expr? (car cur-args) rvars)))
                                         (check-arg (cdr cur-args) (+ i 1))))))))
                        (if arg-res
                            (cdr arg-res)
                            (let ((var-res
                                   (let check-var ((e env))
                                     (if (null? e)
                                         #f
                                         (let ((entry (car e)))
                                           (if (and (pair? entry)
                                                    (not (eq? (car entry) '%num-params))
                                                    (not (eq? (car entry) '%raw-vars)))
                                               (let ((v (car entry))
                                                     (info (cdr entry)))
                                                 (if (and (number? info) (= info slot-offset))
                                                     (cons #t (not (memq v rvars)))
                                                     (if (and (pair? info) (eq? (car info) 'param) (= (cdr info) slot-offset))
                                                         (cons #t (not (memq v rvars)))
                                                         (check-var (cdr e)))))
                                               (check-var (cdr e))))))))
                              (if var-res
                                  (cdr var-res)
                                  #f)))))))
            (loop (+ k 1)
                  (if is-ptr (+ bitmap (power-of-2 k)) bitmap)))))))

(define (lir-compile-let bindings body si env tail?)
  (let loop ((bs bindings)
             (curr-si si)
             (new-env env))
    (if (null? bs)
        (lir-compile-expr body curr-si new-env tail?)
        (let* ((b (car bs))
               (var (car b))
               (val (cadr b))
               (rvars (get-raw-vars new-env))
               (is-raw (raw-expr? val rvars))
               (next-rvars (if is-raw (cons var rvars) rvars)))
          (track-lir-si! curr-si)
          (lir-compile-expr val curr-si env #f)
          (emit-lir! (list '%store '%rsp curr-si '%rax))
          (loop (cdr bs)
                (- curr-si 8)
                (cons (cons var curr-si) (set-raw-vars next-rvars new-env)))))))

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
          (let* ((bitmap (compute-stackmap-bitmap frame-shift aligned-si args env))
                 (safepoint-lbl (new-safepoint-label!)))
            (record-safepoint! safepoint-lbl frame-shift bitmap)
            (emit-lir! (list '%call-closure frame-shift safepoint-lbl)))))))

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
         ((septop-prim? op)
          (lir-compile-raw-syscall (cdr expr) si env))
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
         (num-params (length params))
         (initial-raw-vars (if (unboxed-fn? label) params '())))
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
                             (cons (cons '%raw-vars initial-raw-vars)
                                   (append self-env param-env))))
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
  (reset-safepoints!)
  (reset-symbol-table!)
  (let ((funcs (cadr prog))
        (main-expr (caddr prog)))
    (reset-lir!)
    (track-lir-si! -8)
    (lir-compile-expr main-expr -8 (list (cons '%raw-vars '())) #f)
    (emit-lir! '(%return))
    (let* ((main-insts (reverse (car *lir-instructions*)))
           (main-frame (align-frame-shift (- 0 (car *lir-min-si*))))
           (lir-main (list '%lir-main
                           (list 'frame-size main-frame)
                           (cons 'body main-insts)))
           (lir-funcs (map lir-compile-function funcs))
           (safepoints (reverse (car *lir-safepoints*))))
      (list '%lir-program
            (list 'strings (car *strings*))
            (list 'stackmaps safepoints)
            (cons '%lir-functions lir-funcs)
            lir-main))))
;;; =======================================================================
;;; ULisp Compiler Pass 7: Native x86-64 Backend Code Generator
;;; Conforms to DSN-33 Architecture Specification & ulisp/docs/lir_specification.md
;;; Consumes Pass 6 %lir-program and emits pure GNU x86-64 Intel-syntax assembly.
;;; =======================================================================

(define (emit line)
  (write-string line)
  (write-char #\newline))

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
    ((%rsi) "rsi")
    ((%r8)  "r8")
    ((%r9)  "r9")
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

      ((%syscall)
       (emit "    syscall"))

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

      ((%raw-add)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    add " (operand->str dst) ", " (operand->str src)))))

      ((%sub)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    sub " (operand->str dst) ", " (operand->str src)))))

      ((%raw-sub)
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

      ((%raw-mul)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    imul " (operand->str dst) ", " (operand->str src)))))

      ((%box-fixnum)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (not (eq? dst src))
             (emit (string-append "    mov " (operand->str dst) ", " (operand->str src))))
         (emit (string-append "    shl " (operand->str dst) ", 2"))))

      ((%unbox-fixnum)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (not (eq? dst src))
             (emit (string-append "    mov " (operand->str dst) ", " (operand->str src))))
         (emit (string-append "    sar " (operand->str dst) ", 2"))))

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

      ((%cmp %raw-cmp)
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
           (emit (string-append "    lea " (operand->str dst) ", [rip + " lbl-str "]"))
           (emit (string-append "    add " (operand->str dst) ", 3")))))

      ((%c-call)
       (let ((func (cadr inst))
             (frame-shift (caddr inst)))
         (let ((fname (if (symbol? func) (symbol->raw-name func) func)))
           (emit (string-append "    sub rsp, " (number->string frame-shift)))
           (emit (string-append "    call " fname))
           (emit (string-append "    add rsp, " (number->string frame-shift))))))

      ((%call-closure)
       (let ((frame-shift (cadr inst))
             (safepoint (if (pair? (cddr inst)) (caddr inst) #f)))
         (if (> frame-shift 0)
             (emit (string-append "    sub rsp, " (number->string frame-shift))))
         (emit "    mov rdx, [r10 - 1]")
         (emit "    call rdx")
         (if safepoint
             (emit (string-append (if (symbol? safepoint) (symbol->string safepoint) safepoint) ":")))
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
    (emit "    .globl _start")
    (emit "    .weak _start")
    (emit "    .type _start, @function")
    (emit "_start:")
    (emit "    mov r14, [rsp]")                ; argc
    (emit "    cmp r14, 1")
    (emit "    jle .L_start_no_args")
    (emit "    mov rdi, [rsp + 16]")           ; argv[1]
    (emit "    xor rsi, rsi")                  ; O_RDONLY = 0
    (emit "    xor rdx, rdx")
    (emit "    mov rax, 2")                    ; sys_open
    (emit "    syscall")
    (emit "    test rax, rax")
    (emit "    js .L_start_no_args")
    (emit "    mov rdi, rax")
    (emit "    xor rsi, rsi")                  ; stdin (0)
    (emit "    mov rax, 33")                   ; sys_dup2
    (emit "    syscall")
    (emit ".L_start_no_args:")
    (emit "    mov rbp, rsp")
    (emit "    and rsp, -16")
    (emit "    mov rax, 9")                     ; sys_mmap
    (emit "    xor rdi, rdi")                   ; addr = NULL
    (emit "    mov rsi, 12884901888")           ; 12GB heap (0x300000000)
    (emit "    mov rdx, 3")                     ; PROT_READ|PROT_WRITE
    (emit "    mov r10, 34")                    ; MAP_PRIVATE|MAP_ANONYMOUS
    (emit "    mov r8, -1")                     ; fd = -1
    (emit "    xor r9, r9")                     ; offset = 0
    (emit "    syscall")
    (emit "    test rax, rax")
    (emit "    js .L_start_exit")
    (emit "    mov rdi, rax")                   ; rdi = heap_base
    (emit "    call scheme_entry")
    (emit "    mov r15, rax")
    (emit "    cmp r14, 1")
    (emit "    jg .L_start_exit")
    (emit "    mov rdi, r15")
    (emit "    call ulisp_print_value")
    (emit "    mov dil, 10")
    (emit "    call ulisp_emit_byte")
    (emit ".L_start_exit:")
    (emit "    call ulisp_flush")
    (emit "    xor rdi, rdi")
    (emit "    mov rax, 60")
    (emit "    syscall")
    (emit "")
    (emit "    .globl scheme_entry")
    (emit "    .type scheme_entry, @function")
    (emit "scheme_entry:")
    (emit "    push r12")
    (emit "    sub rsp, 8")
    (emit "    mov r12, rdi")          ; rdi contains heap_base
    (for-each (lambda (inst)
                (if (not (eq? (car inst) '%return))
                    (emit-lir-instruction inst)))
              main-body)
    (emit "    add rsp, 8")
    (emit "    pop r12")
    (emit "    ret")
    ;; Emit all lifted procedure definitions in sequence
    (for-each emit-x86-function funcs)
    ;; Emit freestanding zero-libc runtime routines
    (emit-freestanding-runtime)
    ;; Emit stackmap metadata table in .rodata section
    (let* ((stackmaps-clause (assq 'stackmaps (cdr prog)))
           (safepoints (if stackmaps-clause (cadr stackmaps-clause) '())))
      (emit "    .section .rodata")
      (emit "    .p2align 3")
      (emit "    .globl __ulisp_stackmap_table")
      (emit "__ulisp_stackmap_table:")
      (emit (string-append "    .quad " (number->string (length safepoints))))
      (for-each (lambda (sp)
                  (let ((lbl (car sp))
                        (frame-size (cadr sp))
                        (bitmap (caddr sp)))
                    (emit (string-append "    .quad " (if (symbol? lbl) (symbol->string lbl) lbl)))
                    (emit (string-append "    .quad " (number->string frame-size)))
                    (emit (string-append "    .quad " (number->string bitmap)))))
                safepoints))
    ;; Emit all string literals in .rodata section
    (if (not (null? (car *strings*)))
        (let loop ((ss (reverse (car *strings*))))
          (if (not (null? ss))
              (let ((entry (car ss)))
                (emit "    .p2align 3")
                (emit (string-append (car entry) ":"))
                (emit (string-append "    .asciz \"" (escape-gas-string (cdr entry)) "\""))
                (loop (cdr ss))))))
    (emit "    .bss")
    (emit "    .align 8")
    (emit "    .globl ulisp_gc_state")
    (emit "ulisp_gc_state:")
    (emit "    .space 64")
    (emit "ulisp_peek_buf:")
    (emit "    .byte 0")
    (emit "ulisp_has_peek:")
    (emit "    .byte 0")
    (emit "    .align 8")
    (emit "ulisp_out_buf_len:")
    (emit "    .quad 0")
    (emit "ulisp_out_buf:")
    (emit "    .space 4096")
    (emit "ulisp_io_buf:")
    (emit "    .space 32")
    (emit "    .section .note.GNU-stack,\"\",@progbits")))

(define (emit-freestanding-runtime)
  ;; 1. I/O primitives: ulisp_read_char, ulisp_peek_char, ulisp_write_char
  (emit "    .globl ulisp_read_char")
  (emit "    .type ulisp_read_char, @function")
  (emit "ulisp_read_char:")
  (emit "    lea rdx, [rip + ulisp_has_peek]")
  (emit "    cmp byte ptr [rdx], 0")
  (emit "    je .L_read_direct")
  (emit "    mov byte ptr [rdx], 0")
  (emit "    lea rdx, [rip + ulisp_peek_buf]")
  (emit "    movzx rax, byte ptr [rdx]")
  (emit "    shl rax, 8")
  (emit "    or rax, 14")              ; CHAR_TAG
  (emit "    ret")
  (emit ".L_read_direct:")
  (emit "    xor rax, rax")            ; sys_read
  (emit "    xor rdi, rdi")            ; stdin
  (emit "    lea rsi, [rip + ulisp_io_buf]")
  (emit "    mov rdx, 1")
  (emit "    syscall")
  (emit "    test rax, rax")
  (emit "    jle .L_read_eof")
  (emit "    lea rdx, [rip + ulisp_io_buf]")
  (emit "    movzx rax, byte ptr [rdx]")
  (emit "    shl rax, 8")
  (emit "    or rax, 14")
  (emit "    ret")
  (emit ".L_read_eof:")
  (emit "    mov rax, 79")             ; EOF_OBJECT
  (emit "    ret")
  (emit "")
  (emit "    .globl ulisp_peek_char")
  (emit "    .type ulisp_peek_char, @function")
  (emit "ulisp_peek_char:")
  (emit "    lea rdx, [rip + ulisp_has_peek]")
  (emit "    cmp byte ptr [rdx], 0")
  (emit "    jne .L_peek_buf_ready")
  (emit "    xor rax, rax")            ; sys_read
  (emit "    xor rdi, rdi")            ; stdin
  (emit "    lea rsi, [rip + ulisp_peek_buf]")
  (emit "    mov rdx, 1")
  (emit "    syscall")
  (emit "    test rax, rax")
  (emit "    jle .L_peek_eof")
  (emit "    lea rdx, [rip + ulisp_has_peek]")
  (emit "    mov byte ptr [rdx], 1")
  (emit ".L_peek_buf_ready:")
  (emit "    lea rdx, [rip + ulisp_peek_buf]")
  (emit "    movzx rax, byte ptr [rdx]")
  (emit "    shl rax, 8")
  (emit "    or rax, 14")
  (emit "    ret")
  (emit ".L_peek_eof:")
  (emit "    mov rax, 79")
  (emit "    ret")
  (emit "")
  (emit "    .globl ulisp_flush")
  (emit "    .type ulisp_flush, @function")
  (emit "ulisp_flush:")
  (emit "    lea rcx, [rip + ulisp_out_buf_len]")
  (emit "    mov rdx, [rcx]")
  (emit "    test rdx, rdx")
  (emit "    jle .L_flush_done")
  (emit "    mov qword ptr [rcx], 0")
  (emit "    mov rax, 1")              ; sys_write
  (emit "    mov rdi, 1")              ; stdout
  (emit "    lea rsi, [rip + ulisp_out_buf]")
  (emit "    syscall")
  (emit ".L_flush_done:")
  (emit "    mov rax, 111")            ; #t (0x6F)
  (emit "    ret")
  (emit "")
  (emit "    .globl ulisp_emit_byte")
  (emit "    .type ulisp_emit_byte, @function")
  (emit "ulisp_emit_byte:")
  (emit "    lea rcx, [rip + ulisp_out_buf_len]")
  (emit "    mov rdx, [rcx]")
  (emit "    lea rsi, [rip + ulisp_out_buf]")
  (emit "    mov byte ptr [rsi + rdx], dil")
  (emit "    inc rdx")
  (emit "    mov [rcx], rdx")
  (emit "    cmp rdx, 4096")
  (emit "    jl .L_emit_byte_ret")
  (emit "    sub rsp, 8")
  (emit "    call ulisp_flush")
  (emit "    add rsp, 8")
  (emit ".L_emit_byte_ret:")
  (emit "    mov rax, 111")
  (emit "    ret")
  (emit "")
  (emit "    .globl ulisp_write_char")
  (emit "    .type ulisp_write_char, @function")
  (emit "ulisp_write_char:")
  (emit "    sar rdi, 8")
  (emit "    jmp ulisp_emit_byte")
  (emit "")
  (emit "    .globl ulisp_emit_str")
  (emit "    .type ulisp_emit_str, @function")
  (emit "ulisp_emit_str:")
  (emit "    push rbx")
  (emit "    sub rsp, 8")
  (emit "    mov rbx, rdi")
  (emit ".L_strlen_loop:")
  (emit "    movzx rdi, byte ptr [rbx]")
  (emit "    test dil, dil")
  (emit "    jz .L_strlen_done")
  (emit "    call ulisp_emit_byte")
  (emit "    inc rbx")
  (emit "    jmp .L_strlen_loop")
  (emit ".L_strlen_done:")
  (emit "    add rsp, 8")
  (emit "    pop rbx")
  (emit "    mov rax, 111")
  (emit "    ret")
  (emit "")
  (emit "    .globl ulisp_write_string")
  (emit "    .type ulisp_write_string, @function")
  (emit "ulisp_write_string:")
  (emit "    sub rdi, 3")              ; untag string (tag 3)
  (emit "    jmp ulisp_emit_str")
  (emit "")
  ;; 3. Scheme Value Printer: ulisp_print_value
  (emit "    .globl ulisp_print_value")
  (emit "    .type ulisp_print_value, @function")
  (emit "ulisp_print_value:")
  (emit "    push rbx")
  (emit "    push r12")
  (emit "    push r13")
  (emit "    mov rbx, rdi")
  (emit "    test rbx, 3")
  (emit "    jnz .L_pv_not_fixnum")
  (emit "    sar rbx, 2")
  (emit "    mov rdi, rbx")
  (emit "    call ulisp_print_fixnum")
  (emit "    jmp .L_pv_done")
  (emit ".L_pv_not_fixnum:")
  (emit "    cmp rbx, 47")              ; #f
  (emit "    jne .L_pv_not_false")
  (emit "    lea rdi, [rip + .L_str_false]")
  (emit "    call ulisp_emit_str")
  (emit "    jmp .L_pv_done")
  (emit ".L_pv_not_false:")
  (emit "    cmp rbx, 111")             ; #t
  (emit "    jne .L_pv_not_true")
  (emit "    lea rdi, [rip + .L_str_true]")
  (emit "    call ulisp_emit_str")
  (emit "    jmp .L_pv_done")
  (emit ".L_pv_not_true:")
  (emit "    cmp rbx, 63")              ; ()
  (emit "    jne .L_pv_not_nil")
  (emit "    lea rdi, [rip + .L_str_nil]")
  (emit "    call ulisp_emit_str")
  (emit "    jmp .L_pv_done")
  (emit ".L_pv_not_nil:")
  (emit "    cmp rbx, 79")              ; eof
  (emit "    jne .L_pv_not_eof")
  (emit "    lea rdi, [rip + .L_str_eof]")
  (emit "    call ulisp_emit_str")
  (emit "    jmp .L_pv_done")
  (emit ".L_pv_not_eof:")
  (emit "    mov rax, rbx")
  (emit "    and rax, 255")
  (emit "    cmp rax, 14")              ; char tag
  (emit "    jne .L_pv_not_char")
  (emit "    mov rdi, rbx")
  (emit "    sar rdi, 8")
  (emit "    call ulisp_print_char")
  (emit "    jmp .L_pv_done")
  (emit ".L_pv_not_char:")
  (emit "    mov rax, rbx")
  (emit "    and rax, 3")
  (emit "    cmp rax, 3")              ; string tag
  (emit "    jne .L_pv_not_string")
  (emit "    mov rdi, 34")             ; '\"'
  (emit "    call ulisp_emit_byte")
  (emit "    mov rdi, rbx")
  (emit "    sub rdi, 3")
  (emit "    call ulisp_emit_str")
  (emit "    mov rdi, 34")
  (emit "    call ulisp_emit_byte")
  (emit "    jmp .L_pv_done")
  (emit ".L_pv_not_string:")
  (emit "    cmp rax, 1")              ; pair tag
  (emit "    jne .L_pv_not_pair")
  (emit "    mov rdi, rbx")
  (emit "    call ulisp_print_pair")
  (emit "    jmp .L_pv_done")
  (emit ".L_pv_not_pair:")
  (emit "    mov rax, rbx")
  (emit "    and rax, 255")
  (emit "    cmp rax, 2")              ; symbol tag
  (emit "    jne .L_pv_unknown")
  (emit "    lea rdi, [rip + .L_str_symbol]")
  (emit "    call ulisp_emit_str")
  (emit "    jmp .L_pv_done")
  (emit ".L_pv_unknown:")
  (emit "    lea rdi, [rip + .L_str_unknown]")
  (emit "    call ulisp_emit_str")
  (emit ".L_pv_done:")
  (emit "    pop r13")
  (emit "    pop r12")
  (emit "    pop rbx")
  (emit "    ret")
  (emit "")
  (emit "ulisp_print_fixnum:")
  (emit "    push rbx")
  (emit "    push r12")
  (emit "    mov rbx, rdi")
  (emit "    test rbx, rbx")
  (emit "    jnz .L_pn_not_zero")
  (emit "    mov rdi, 48")             ; '0'
  (emit "    call ulisp_emit_byte")
  (emit "    pop r12")
  (emit "    pop rbx")
  (emit "    ret")
  (emit ".L_pn_not_zero:")
  (emit "    jns .L_pn_pos")
  (emit "    mov rdi, 45")             ; '-'
  (emit "    call ulisp_emit_byte")
  (emit "    neg rbx")
  (emit ".L_pn_pos:")
  (emit "    sub rsp, 32")
  (emit "    xor r12, r12")
  (emit "    mov rax, rbx")
  (emit "    mov rcx, 10")
  (emit ".L_pn_loop:")
  (emit "    test rax, rax")
  (emit "    jz .L_pn_emit_digits")
  (emit "    xor rdx, rdx")
  (emit "    div rcx")
  (emit "    add dl, 48")
  (emit "    mov [rsp + r12], dl")
  (emit "    inc r12")
  (emit "    jmp .L_pn_loop")
  (emit ".L_pn_emit_digits:")
  (emit "    test r12, r12")
  (emit "    jz .L_pn_fin")
  (emit "    dec r12")
  (emit "    movzx rdi, byte ptr [rsp + r12]")
  (emit "    call ulisp_emit_byte")
  (emit "    jmp .L_pn_emit_digits")
  (emit ".L_pn_fin:")
  (emit "    add rsp, 32")
  (emit "    pop r12")
  (emit "    pop rbx")
  (emit "    ret")
  (emit "")
  (emit "ulisp_print_char:")
  (emit "    push rbx")
  (emit "    mov rbx, rdi")
  (emit "    lea rdi, [rip + .L_str_char_prefix]")
  (emit "    call ulisp_emit_str")
  (emit "    cmp rbx, 10")
  (emit "    jne .L_pc_not_nl")
  (emit "    lea rdi, [rip + .L_str_newline]")
  (emit "    call ulisp_emit_str")
  (emit "    pop rbx")
  (emit "    ret")
  (emit ".L_pc_not_nl:")
  (emit "    cmp rbx, 32")
  (emit "    jne .L_pc_not_sp")
  (emit "    lea rdi, [rip + .L_str_space]")
  (emit "    call ulisp_emit_str")
  (emit "    pop rbx")
  (emit "    ret")
  (emit ".L_pc_not_sp:")
  (emit "    cmp rbx, 9")
  (emit "    jne .L_pc_raw")
  (emit "    lea rdi, [rip + .L_str_tab]")
  (emit "    call ulisp_emit_str")
  (emit "    pop rbx")
  (emit "    ret")
  (emit ".L_pc_raw:")
  (emit "    mov rdi, rbx")
  (emit "    call ulisp_emit_byte")
  (emit "    pop rbx")
  (emit "    ret")
  (emit "")
  (emit "ulisp_print_pair:")
  (emit "    push rbx")
  (emit "    push r12")
  (emit "    mov rbx, rdi")
  (emit "    mov rdi, 40")             ; '('
  (emit "    call ulisp_emit_byte")
  (emit "    mov r12, 1")
  (emit ".L_pair_loop:")
  (emit "    test r12, r12")
  (emit "    jnz .L_pair_no_space")
  (emit "    mov rdi, 32")             ; ' '
  (emit "    call ulisp_emit_byte")
  (emit ".L_pair_no_space:")
  (emit "    xor r12, r12")
  (emit "    mov rdi, [rbx - 1]")      ; car
  (emit "    call ulisp_print_value")
  (emit "    mov rbx, [rbx + 7]")      ; cdr
  (emit "    cmp rbx, 63")             ; EMPTY_LIST
  (emit "    je .L_pair_done")
  (emit "    mov rax, rbx")
  (emit "    and rax, 3")
  (emit "    cmp rax, 1")              ; PAIR_TAG
  (emit "    je .L_pair_loop")
  (emit "    lea rdi, [rip + .L_str_dot]")
  (emit "    call ulisp_emit_str")
  (emit "    mov rdi, rbx")
  (emit "    call ulisp_print_value")
  (emit ".L_pair_done:")
  (emit "    mov rdi, 41")             ; ')'
  (emit "    call ulisp_emit_byte")
  (emit "    pop r12")
  (emit "    pop rbx")
  (emit "    ret")
  (emit "")
  (emit ".L_str_false: .asciz \"#f\"")
  (emit ".L_str_true: .asciz \"#t\"")
  (emit ".L_str_nil: .asciz \"()\"")
  (emit ".L_str_eof: .asciz \"#<eof>\"")
  (emit ".L_str_char_prefix: .asciz \"#\\\\\"")
  (emit ".L_str_newline: .asciz \"newline\"")
  (emit ".L_str_space: .asciz \"space\"")
  (emit ".L_str_tab: .asciz \"tab\"")
  (emit ".L_str_dot: .asciz \" . \"")
  (emit ".L_str_symbol: .asciz \"#<symbol>\"")
  (emit ".L_str_unknown: .asciz \"#<unknown>\"")
  (emit ""))
;;; =======================================================================
;;; ULisp Compiler Pass 7: Native AArch64 (ARM64) Backend Code Generator
;;; Conforms to DSN-33 Architecture Specification & Issue #503
;;; Consumes Pass 6 %lir-program and emits pure GNU AArch64 assembly.
;;; =======================================================================

(define (arm-reg->str reg)
  (case reg
    ((%rax) "x0")
    ((%rdx) "x1")
    ((%rcx) "x2")
    ((%rbx) "x3")
    ((%rdi) "x0")
    ((%rsi) "x1")
    ((%r10) "x10")
    ((%r12) "x19")
    ((%rsp) "sp")
    ((%al)  "w0")
    (else (symbol->string reg))))

(define (arm-w-reg->str reg)
  (case reg
    ((%rax x0) "w0")
    ((%rdx x1) "w1")
    ((%rcx x2) "w2")
    ((%rbx x3) "w3")
    ((%r10 x10) "w10")
    ((%r12 x19) "w19")
    ((%al)  "w0")
    (else
     (let ((s (if (symbol? reg) (symbol->string reg) reg)))
       (if (and (> (string-length s) 1) (char=? (string-ref s 0) #\x))
           (string-append "w" (substring s 1 (string-length s)))
           s)))))

(define (arm-mem-op->str base offset)
  (let ((base-str (arm-reg->str base)))
    (if (symbol? offset)
        (string-append "[" base-str ", " (arm-reg->str offset) "]")
        (string-append "[" base-str ", #" (number->string offset) "]"))))

(define (arm-operand->str opnd)
  (cond
    ((symbol? opnd)
     (arm-reg->str opnd))
    ((integer? opnd)
     (string-append "#" (number->string opnd)))
    ((pair? opnd)
     (let ((tag (car opnd)))
       (case tag
         ((%stack)
          (string-append "[sp, #" (number->string (cadr opnd)) "]"))
         ((%mem)
          (arm-mem-op->str (cadr opnd) (caddr opnd)))
         (else
          (error "Unknown operand in AArch64 backend:" opnd)))))
    (else
     (error "Invalid operand type in AArch64 backend:" opnd))))

(define (arm-condition-code set-inst)
  (cond
    ((string=? set-inst "sete")  "eq")
    ((string=? set-inst "setl")  "lt")
    ((string=? set-inst "setle") "le")
    ((string=? set-inst "setg")  "gt")
    ((string=? set-inst "setge") "ge")
    ((string=? set-inst "setne") "ne")
    (else (error "Unknown set-cc in AArch64 backend:" set-inst))))

(define (emit-arm-boolean-from-set set-inst)
  (let ((cond (arm-condition-code set-inst)))
    (emit (string-append "    cset x0, " cond))
    (emit "    lsl x0, x0, 6")
    (emit "    add x0, x0, 0x2F")))

;;; Emits a single LIR instruction to AArch64 assembly
(define (emit-arm-lir-instruction inst)
  (let ((op (car inst)))
    (case op
      ((%label)
       (let ((lbl (cadr inst)))
         (emit (string-append (if (symbol? lbl) (symbol->string lbl) lbl) ":"))))

      ((%jump)
       (let ((lbl (cadr inst)))
         (if (and (symbol? lbl)
                  (memq lbl '(%rax %rdx %rcx %rbx %r10 %r12 x0 x1 x2 x3 x10 x19)))
             (emit (string-append "    br " (arm-reg->str lbl)))
             (emit (string-append "    b " (if (symbol? lbl) (symbol->string lbl) lbl))))))

      ((%jump-if-false)
       (let ((reg (cadr inst))
             (lbl (caddr inst)))
         (emit (string-append "    cmp " (arm-reg->str reg) ", #0x2F"))
         (emit (string-append "    b.eq " (if (symbol? lbl) (symbol->string lbl) lbl)))))

      ((%jump-if-zero)
       (let ((lbl (cadr inst)))
         (emit (string-append "    b.eq " (if (symbol? lbl) (symbol->string lbl) lbl)))))

      ((%return)
       (emit "    ret"))

      ((%mov)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (cond
           ((integer? src)
            (if (and (>= src -65535) (<= src 65535))
                (emit (string-append "    mov " (arm-reg->str dst) ", #" (number->string src)))
                (emit (string-append "    ldr " (arm-reg->str dst) ", =" (number->string src)))))
           ((pair? src)
            (emit (string-append "    ldr " (arm-reg->str dst) ", " (arm-operand->str src))))
           (else
            (emit (string-append "    mov " (arm-reg->str dst) ", " (arm-reg->str src)))))))

      ((%load)
       (let ((dst (cadr inst))
             (base (caddr inst))
             (offset (cadddr inst)))
         (emit (string-append "    ldr " (arm-reg->str dst) ", " (arm-mem-op->str base offset)))))

      ((%store)
       (let ((base (cadr inst))
             (offset (caddr inst))
             (src (cadddr inst)))
         (emit (string-append "    str " (arm-reg->str src) ", " (arm-mem-op->str base offset)))))

      ((%store-byte)
       (let ((base (cadr inst))
             (offset (caddr inst))
             (src (cadddr inst)))
         (cond
           ((and (number? src) (= src 0))
            (emit (string-append "    strb wzr, " (arm-mem-op->str base offset))))
           ((number? src)
            (emit (string-append "    mov w9, #" (number->string src)))
            (emit (string-append "    strb w9, " (arm-mem-op->str base offset))))
           (else
            (emit (string-append "    strb " (arm-w-reg->str src) ", " (arm-mem-op->str base offset)))))))

      ((%load-byte-zx)
       (let ((dst (cadr inst))
             (base (caddr inst))
             (offset (cadddr inst)))
         (emit (string-append "    ldrb " (arm-w-reg->str dst) ", " (arm-mem-op->str base offset)))))

      ((%add %raw-add)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (number? src)
             (if (and (>= src 0) (<= src 4095))
                 (emit (string-append "    add " (arm-reg->str dst) ", " (arm-reg->str dst) ", #" (number->string src)))
                 (begin
                   (emit (string-append "    ldr x9, =" (number->string src)))
                   (emit (string-append "    add " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9"))))
             (emit (string-append "    add " (arm-reg->str dst) ", " (arm-reg->str dst) ", " (arm-operand->str src))))))

      ((%sub %raw-sub)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (number? src)
             (if (and (>= src 0) (<= src 4095))
                 (emit (string-append "    sub " (arm-reg->str dst) ", " (arm-reg->str dst) ", #" (number->string src)))
                 (begin
                   (emit (string-append "    ldr x9, =" (number->string src)))
                   (emit (string-append "    sub " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9"))))
             (emit (string-append "    sub " (arm-reg->str dst) ", " (arm-reg->str dst) ", " (arm-operand->str src))))))

      ((%neg)
       (let ((dst (cadr inst)))
         (emit (string-append "    neg " (arm-reg->str dst) ", " (arm-reg->str dst)))))

      ((%imul %raw-mul)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (cond
           ((pair? src)
            (emit (string-append "    ldr x9, " (arm-operand->str src)))
            (emit (string-append "    mul " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9")))
           ((number? src)
            (emit (string-append "    ldr x9, =" (number->string src)))
            (emit (string-append "    mul " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9")))
           (else
            (emit (string-append "    mul " (arm-reg->str dst) ", " (arm-reg->str dst) ", " (arm-reg->str src)))))))

      ((%box-fixnum)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    lsl " (arm-reg->str dst) ", " (arm-reg->str src) ", #2"))))

      ((%unbox-fixnum)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    asr " (arm-reg->str dst) ", " (arm-reg->str src) ", #2"))))

      ((%cqo)
       ;; In AArch64, 64-bit sdiv does not require cqo sign extension; no-op.
       #f)

      ((%idiv)
       (let ((src (cadr inst)))
         (let ((src-str (arm-operand->str src)))
           (emit (string-append "    sdiv x9, x0, " src-str))
           (emit (string-append "    msub x1, x9, " src-str ", x0"))
           (emit "    mov x0, x9"))))

      ((%inc)
       (let ((dst (cadr inst)))
         (emit (string-append "    add " (arm-reg->str dst) ", " (arm-reg->str dst) ", #1"))))

      ((%shl)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    lsl " (arm-reg->str dst) ", " (arm-reg->str dst) ", #" (number->string count)))))

      ((%shr)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    lsr " (arm-reg->str dst) ", " (arm-reg->str dst) ", #" (number->string count)))))

      ((%sar)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    asr " (arm-reg->str dst) ", " (arm-reg->str dst) ", #" (number->string count)))))

      ((%bit-and)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (number? src)
             (begin
               (emit (string-append "    ldr x9, =" (number->string src)))
               (emit (string-append "    and " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9")))
             (emit (string-append "    and " (arm-reg->str dst) ", " (arm-reg->str dst) ", " (arm-reg->str src))))))

      ((%bit-or)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (number? src)
             (begin
               (emit (string-append "    ldr x9, =" (number->string src)))
               (emit (string-append "    orr " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9")))
             (emit (string-append "    orr " (arm-reg->str dst) ", " (arm-reg->str dst) ", " (arm-reg->str src))))))

      ((%bit-xor)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (number? src)
             (begin
               (emit (string-append "    ldr x9, =" (number->string src)))
               (emit (string-append "    eor " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9")))
             (emit (string-append "    eor " (arm-reg->str dst) ", " (arm-reg->str dst) ", " (arm-reg->str src))))))

      ((%cmp %raw-cmp)
       (let ((s1 (cadr inst))
             (s2 (caddr inst)))
         (if (number? s2)
             (if (and (>= s2 0) (<= s2 4095))
                 (emit (string-append "    cmp " (arm-reg->str s1) ", #" (number->string s2)))
                 (begin
                   (emit (string-append "    ldr x9, =" (number->string s2)))
                   (emit (string-append "    cmp " (arm-reg->str s1) ", x9"))))
             (emit (string-append "    cmp " (arm-reg->str s1) ", " (arm-operand->str s2))))))

      ((%set-boolean)
       (let ((cc (caddr inst)))
         (emit-arm-boolean-from-set cc)))

      ((%alloc)
       (let ((dst (cadr inst))
             (bytes (caddr inst))
             (tag (cadddr inst)))
         (if (= tag 0)
             (emit (string-append "    mov " (arm-reg->str dst) ", x19"))
             (emit (string-append "    add " (arm-reg->str dst) ", x19, #" (number->string tag))))
         (emit (string-append "    add x19, x19, #" (number->string bytes)))))

      ((%code-ref)
       (let ((dst (cadr inst))
             (lbl (caddr inst)))
         (let ((lbl-str (if (symbol? lbl) (symbol->string lbl) lbl))
               (dst-str (arm-reg->str dst)))
           (emit (string-append "    adrp " dst-str ", " lbl-str))
           (emit (string-append "    add " dst-str ", " dst-str ", :lo12:" lbl-str)))))

      ((%str-ref)
       (let ((dst (cadr inst))
             (lbl (caddr inst)))
         (let ((lbl-str (if (symbol? lbl) (symbol->string lbl) lbl))
               (dst-str (arm-reg->str dst)))
           (emit (string-append "    adrp " dst-str ", " lbl-str))
           (emit (string-append "    add " dst-str ", " dst-str ", :lo12:" lbl-str))
           (emit (string-append "    add " dst-str ", " dst-str ", #3")))))

      ((%c-call)
       (let* ((func (cadr inst))
              (frame-shift (caddr inst))
              (total-shift (+ frame-shift 8)))
         (emit (string-append "    sub sp, sp, #" (number->string total-shift)))
         (emit "    str x30, [sp]")
         (emit (string-append "    bl " (if (symbol? func) (symbol->raw-name func) func)))
         (emit "    ldr x30, [sp]")
         (emit (string-append "    add sp, sp, #" (number->string total-shift)))))

      ((%call-closure)
       (let* ((frame-shift (cadr inst))
              (safepoint (if (pair? (cddr inst)) (caddr inst) #f))
              (total-shift (+ frame-shift 8)))
         (emit (string-append "    sub sp, sp, #" (number->string total-shift)))
         (emit "    str x30, [sp]")
         (emit "    ldr x1, [x10, #-1]")
         (emit "    blr x1")
         (if safepoint
             (emit (string-append (if (symbol? safepoint) (symbol->string safepoint) safepoint) ":")))
         (emit "    ldr x30, [sp]")
         (emit (string-append "    add sp, sp, #" (number->string total-shift)))))

      (else
       (error "Unknown LIR opcode in AArch64 backend:" inst)))))

;;; Emits assembly for a single %lir-function
(define (emit-arm-function fn)
  (let* ((label (cadr fn))
         (label-str (if (symbol? label) (symbol->string label) label))
         (body (cdr (assq 'body (cddr fn)))))
    (emit "    .p2align 2")
    (emit (string-append label-str ":"))
    ;; Callee prologue: self closure pointer was in x10
    ;; Store self closure pointer at [sp, #-8]
    (emit "    str x10, [sp, #-8]")
    (for-each emit-arm-lir-instruction body)))

;;; Pass 7 Entrypoint: Takes %lir-program and emits complete GNU AArch64 assembly
(define (emit-aarch64 prog)
  (let* ((funcs-clause (assq '%lir-functions (cdr prog)))
         (funcs (if funcs-clause (cdr funcs-clause) '()))
         (main-clause (assq '%lir-main (cdr prog)))
         (main-body (cdr (assq 'body (cdr main-clause)))))
    (emit "    .text")
    (emit "    .globl scheme_entry")
    (emit "    .type scheme_entry, @function")
    (emit "scheme_entry:")
    (emit "    stp x29, x30, [sp, #-32]!")
    (emit "    mov x29, sp")
    (emit "    str x19, [sp, #16]")
    (emit "    mov x19, x0")          ; x0 contains heap_base from C runtime
    (for-each (lambda (inst)
                (if (not (eq? (car inst) '%return))
                    (emit-arm-lir-instruction inst)))
              main-body)
    (emit "    ldr x19, [sp, #16]")
    (emit "    ldp x29, x30, [sp], #32")
    (emit "    ret")
    ;; Emit all lifted procedure definitions in sequence
    (for-each emit-arm-function funcs)
    ;; Emit stackmap metadata table in .rodata section
    (let* ((stackmaps-clause (assq 'stackmaps (cdr prog)))
           (safepoints (if stackmaps-clause (cadr stackmaps-clause) '())))
      (emit "    .section .rodata")
      (emit "    .p2align 3")
      (emit "    .globl __ulisp_stackmap_table")
      (emit "__ulisp_stackmap_table:")
      (emit (string-append "    .xword " (number->string (length safepoints))))
      (for-each (lambda (sp)
                  (let ((lbl (car sp))
                        (frame-size (cadr sp))
                        (bitmap (caddr sp)))
                    (emit (string-append "    .xword " (if (symbol? lbl) (symbol->string lbl) lbl)))
                    (emit (string-append "    .xword " (number->string frame-size)))
                    (emit (string-append "    .xword " (number->string bitmap)))))
                safepoints))
    ;; Emit all string literals in .rodata section
    (if (not (null? (car *strings*)))
        (let loop ((ss (reverse (car *strings*))))
          (if (not (null? ss))
              (let ((entry (car ss)))
                (emit "    .p2align 3")
                (emit (string-append (car entry) ":"))
                (emit (string-append "    .asciz \"" (escape-gas-string (cdr entry)) "\""))
                (loop (cdr ss))))))
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

      ((%raw-add)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " += " (c-operand->str src) ";"))))

      ((%sub)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " -= " (c-operand->str src) ";"))))

      ((%raw-sub)
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

      ((%raw-mul)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " = (uint64_t)((int64_t)" (c-operand->str dst) " * (int64_t)" (c-operand->str src) ");"))))

      ((%box-fixnum)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " = ((uint64_t)" (c-operand->str src) ") << 2;"))))

      ((%unbox-fixnum)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    " (c-operand->str dst) " = (uint64_t)(((int64_t)" (c-operand->str src) ") >> 2);"))))

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

      ((%cmp %raw-cmp)
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
       (let* ((func (cadr inst))
              (frame-shift (caddr inst))
              (fname (if (symbol? func) (symbol->raw-name func) func)))
         (cond
           ((or (eq? func 'ulisp_read_char) (string=? fname "ulisp_read_char"))
            (if (> frame-shift 0) (emit (string-append "    reg_rsp -= " (number->string frame-shift) ";")))
            (emit "    reg_rax = ulisp_read_char();")
            (if (> frame-shift 0) (emit (string-append "    reg_rsp += " (number->string frame-shift) ";"))))
           ((or (eq? func 'ulisp_peek_char) (string=? fname "ulisp_peek_char"))
            (if (> frame-shift 0) (emit (string-append "    reg_rsp -= " (number->string frame-shift) ";")))
            (emit "    reg_rax = ulisp_peek_char();")
            (if (> frame-shift 0) (emit (string-append "    reg_rsp += " (number->string frame-shift) ";"))))
           ((or (eq? func 'ulisp_write_char) (string=? fname "ulisp_write_char"))
            (if (> frame-shift 0) (emit (string-append "    reg_rsp -= " (number->string frame-shift) ";")))
            (emit "    reg_rax = ulisp_write_char(reg_rdi);")
            (if (> frame-shift 0) (emit (string-append "    reg_rsp += " (number->string frame-shift) ";"))))
           (else
            (if (> frame-shift 0) (emit (string-append "    reg_rsp -= " (number->string frame-shift) ";")))
            (emit (string-append "    reg_rax = " fname "();"))
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
    (emit "uint64_t __ulisp_stackmap_table[1] = {0};")
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
             (ast2b (lvn-all ast2))
             (ast3 (anf-all ast2b))
             (ast3b (annotate-all ast3))
             (ast3c (rtyper-all ast3b))
             (ast4 (closure-convert ast3c))
             (lir  (generate-lir ast4)))
        (cond
          ((eq? target 'c)
           (emit-c lir))
          ((eq? target 'aarch64)
           (emit-aarch64 lir))
          (else
           (emit-x86-64 lir))))))
