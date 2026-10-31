;;; =======================================================================
;;; ULisp Compiler Pass 4c: Contification & Local Closure Elimination Nanopass
;;; Conforms to DSN-33 Architecture Specification & Issue #522
;;; Note: Identifies local functions whose call sites are dominated by a
;;;       common continuation context and transforms them into local control
;;;       flow (%cont-fun / %cont-call), eliminating flat closure allocation
;;;       and indirect calls completely.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass: contify-subst
;;; Substitutes call sites of `var` into `(%cont-call var . args)` within `expr`.
;;; -----------------------------------------------------------------------
(define-pass contify-subst : L_core (ir var) -> L_core ()
  (Expr : Expr (ir var) -> Expr ()
    ((quote ,datum)
     ir)
    ((lambda (,params ...) ,body)
     ir) ; Do not cross lambda boundaries into separate procedure CFGs
    ((let ((,x* ,e*) ...) ,body)
     (let ((opt-bindings (let loop ((xs x*) (es e*) (acc '()))
                           (if (or (null? xs) (null? es))
                               (reverse acc)
                               (loop (cdr xs) (cdr es) (cons (list (car xs) (Expr (car es) var)) acc))))))
       (if (memq var x*)
           (list 'let opt-bindings body) ; shadowed
           (list 'let opt-bindings (Expr body var)))))
    ((letrec ((,x* ,e*) ...) ,body)
     (if (memq var x*)
         ir ; shadowed
         (let ((opt-bindings (let loop ((xs x*) (es e*) (acc '()))
                               (if (or (null? xs) (null? es))
                                   (reverse acc)
                                   (loop (cdr xs) (cdr es) (cons (list (car xs) (Expr (car es) var)) acc))))))
           (list 'letrec opt-bindings (Expr body var)))))
    ((%cont-fun ,f-name (,params ...) ,f-body ,in-body)
     (if (eq? f-name var)
         ir ; shadowed
         (list '%cont-fun f-name params
               (Expr f-body var)
               (Expr in-body var))))
    ((%cont-call ,target ,es ...)
     (cons '%cont-call (cons target (map (lambda (e) (Expr e var)) es))))
    ((,op ,args ...)
     (if (eq? op var)
         (cons '%cont-call (cons var (map (lambda (e) (Expr e var)) args)))
         (cons (Expr op var) (map (lambda (e) (Expr e var)) args))))))

(define (contify-calls var expr)
  (contify-subst expr var))

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
