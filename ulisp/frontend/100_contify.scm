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

;;; -----------------------------------------------------------------------
;;; First-Class Femtopass & Picopass Rules for Contification (DSN-33-01 T5.2)
;;; -----------------------------------------------------------------------

(define-femtopass femto-contifiable?
  :reads '(lambda)
  (Expr
    ((letrec ((,x* ,e*) ...) ,body)
     (let loop ((xs x*) (es e*) (acc '()))
       (if (null? xs)
           (reverse acc)
           (let ((v (car xs))
                 (val (car es)))
             (if (contifiable-binding? v val body)
                 (loop (cdr xs) (cdr es) (cons v acc))
                 (loop (cdr xs) (cdr es) acc))))))))

(define (contify-letrec-reducible? ir x* body)
  (and (= (length x*) 1)
       (has-call? (car x*) body)
       (pair? (femto-contifiable? ir))))

(define-picopass rule-contify-letrec
  :reads '(letrec) :writes '(%cont-fun)
  (Expr
    ((letrec ((,x* ,e*) ...) ,body) (guard (contify-letrec-reducible? ir x* body))
     (let* ((contifiable-vars (femto-contifiable? ir))
            (var (car contifiable-vars))
            (val (car e*))
            (params (cadr val))
            (lbody (caddr val))
            (opt-lbody (contify-calls var lbody))
            (opt-body (contify-calls var body)))
       (list '%cont-fun var params opt-lbody opt-body)))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass: contify-opt
;;; Bottom-up Contification using fused Picopass + Femtopass cache (DSN-33-01)
;;; -----------------------------------------------------------------------
(define-pass contify-opt : L_core (ir) -> L_core ()
  (Expr : Expr (ir) -> Expr ()
    (fuse-rules :order post
      rule-contify-letrec)))

(define (contify-expr expr)
  (contify-opt expr))

;;; Pass 4c Entrypoint: Contification & local closure elimination across all expressions.
(define (contify-all form)
  (contify-opt form))
