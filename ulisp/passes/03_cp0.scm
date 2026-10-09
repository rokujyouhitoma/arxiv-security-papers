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
