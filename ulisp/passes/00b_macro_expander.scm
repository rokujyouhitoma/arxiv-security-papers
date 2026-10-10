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
