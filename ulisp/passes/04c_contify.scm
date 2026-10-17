;;; =======================================================================
;;; ULisp Compiler Pass 4c: Contification & Local Closure Elimination Nanopass
;;; Conforms to DSN-33 Architecture Specification & Issue #522
;;; Note: Identifies local functions whose call sites are dominated by a
;;;       common continuation context and transforms them into local control
;;;       flow (%cont-fun / %cont-call), eliminating flat closure allocation
;;;       and indirect calls completely.
;;; =======================================================================

;;; Substitutes call sites of `var` into `(%cont-call var . args)` within `expr`.
(define (contify-calls var expr)
  (cond
    ((not (pair? expr)) expr)
    (else
     (let ((op (car expr)))
       (case op
         ((quote) expr)
         ((if)
          (list 'if
                (contify-calls var (cadr expr))
                (contify-calls var (caddr expr))
                (if (null? (cdddr expr)) #f (contify-calls var (cadddr expr)))))
         ((begin)
          (cons 'begin (map (lambda (e) (contify-calls var e)) (cdr expr))))
         ((let)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (list 'let
                  (map (lambda (b) (list (car b) (contify-calls var (cadr b)))) bindings)
                  (if (assq var bindings)
                      body  ; shadowed
                      (contify-calls var body)))))
         ((letrec)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (if (assq var bindings)
                expr ; shadowed
                (list 'letrec
                      (map (lambda (b) (list (car b) (contify-calls var (cadr b)))) bindings)
                      (contify-calls var body)))))
         ((lambda)
          expr) ; Do not cross lambda boundaries into separate procedure CFGs
         ((%cont-fun)
          (let ((f-name (cadr expr))
                (params (caddr expr))
                (f-body (cadddr expr))
                (in-body (cadr (cdddr expr))))
            (if (eq? f-name var)
                expr ; shadowed
                (list '%cont-fun f-name params
                      (contify-calls var f-body)
                      (contify-calls var in-body)))))
         ((%cont-call)
          (cons '%cont-call
                (cons (cadr expr)
                      (map (lambda (e) (contify-calls var e)) (cddr expr)))))
         (else
          (if (eq? op var)
              (cons '%cont-call (cons var (map (lambda (e) (contify-calls var e)) (cdr expr))))
              (map (lambda (e) (contify-calls var e)) expr))))))))

;;; Recursively transforms an expression, converting eligible letrec bindings into %cont-fun.
(define (contify-expr expr)
  (cond
    ((not (pair? expr)) expr)
    (else
     (let ((op (car expr)))
       (case op
         ((quote) expr)
         ((if)
          (list 'if
                (contify-expr (cadr expr))
                (contify-expr (caddr expr))
                (if (null? (cdddr expr)) #f (contify-expr (cadddr expr)))))
         ((begin)
          (cons 'begin (map contify-expr (cdr expr))))
         ((let)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (list 'let
                  (map (lambda (b) (list (car b) (contify-expr (cadr b)))) bindings)
                  (contify-expr body))))
         ((letrec)
          (let* ((bindings (cadr expr))
                 (body (caddr expr)))
            (contify-letrec bindings body)))
         ((lambda)
          (let ((params (cadr expr))
                (body (caddr expr)))
            (list 'lambda params (contify-expr body))))
         ((%cont-fun)
          (list '%cont-fun
                (cadr expr)
                (caddr expr)
                (contify-expr (cadddr expr))
                (contify-expr (cadr (cdddr expr)))))
         ((%cont-call)
          (cons '%cont-call
                (cons (cadr expr)
                      (map contify-expr (cddr expr)))))
         (else
          (map contify-expr expr)))))))

(define (occurs-in? var expr)
  (cond
    ((symbol? expr) (eq? expr var))
    ((not (pair? expr)) #f)
    (else
     (or (occurs-in? var (car expr))
         (occurs-in? var (cdr expr))))))

(define (occurs-in-other-bindings? var bindings)
  (let loop ((bs bindings))
    (if (null? bs)
        #f
        (let ((b (car bs)))
          (if (eq? (car b) var)
              (loop (cdr bs))
              (if (occurs-in? var (cadr b))
                  #t
                  (loop (cdr bs))))))))

(define (has-call? var expr)
  (cond
    ((not (pair? expr)) #f)
    (else
     (if (eq? (car expr) var)
         #t
         (let loop ((es expr))
           (and (pair? es)
                (or (has-call? var (car es))
                    (loop (cdr es)))))))))

;;; Processes a letrec form, lifting contifiable local bindings into %cont-fun wrappers.
(define (contify-letrec bindings orig-body)
  (if (= (length bindings) 1)
      (let* ((b (car bindings))
             (var (car b))
             (val (cadr b)))
        (if (and (has-call? var orig-body)
                 (contifiable-binding? var val orig-body))
            (let* ((params (cadr val))
                   (lbody (caddr val))
                   (opt-lbody (contify-calls var lbody))
                   (opt-body (contify-calls var orig-body)))
              (list '%cont-fun var params
                    (contify-expr opt-lbody)
                    (contify-expr opt-body)))
            (list 'letrec
                  (list (list var (contify-expr val)))
                  (contify-expr orig-body))))
      ;; Multi-binding letrec (top-level procedures or mutual recursion):
      ;; Preserve letrec structure to maintain inter-procedure references,
      ;; while recursively contifying local loops inside each procedure body.
      (list 'letrec
            (map (lambda (b) (list (car b) (contify-expr (cadr b)))) bindings)
            (contify-expr orig-body))))

;;; Pass 4c Entrypoint: Contification & local closure elimination across all expressions.
(define (contify-all form)
  (cond
    ((not (pair? form)) form)
    ((eq? (car form) '%program)
     (let ((defs (cadr form))
           (main (caddr form)))
       (list '%program
             (map (lambda (d)
                    (if (and (pair? d) (eq? (car d) 'define))
                        (list 'define (cadr d) (contify-expr (caddr d)))
                        (contify-expr d)))
                  defs)
             (contify-expr main))))
    (else
     (contify-expr form))))
