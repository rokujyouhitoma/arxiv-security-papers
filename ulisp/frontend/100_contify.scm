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

(define (contify-prefix-make-begin es)
  (cond
    ((null? es) '(begin))
    ((null? (cdr es)) (car es))
    (else (cons 'begin es))))

(define (contify-prefix-rewrite var params lbody expr)
  (cond
    ((not (pair? expr)) #f)
    ((and (eq? (car expr) var)
          (not (occurs-in? var (cdr expr))))
     (list '%cont-fun var params (contify-calls var lbody)
           (cons '%cont-call (cons var (cdr expr)))))
    ((and (eq? (car expr) 'begin) (pair? (cdr expr)))
     (let ((e1 (cadr expr))
           (rest (cddr expr)))
       (cond
         ((null? rest)
          (contify-prefix-rewrite var params lbody e1))
         ((not (occurs-in? var rest))
          (let ((rw1 (contify-prefix-rewrite var params lbody e1)))
            (if rw1 (cons 'begin (cons rw1 rest)) #f)))
         ((not (occurs-in? var e1))
          (let ((rw-rest (contify-prefix-rewrite var params lbody (contify-prefix-make-begin rest))))
            (if rw-rest (list 'begin e1 rw-rest) #f)))
         (else #f))))
    ((and (eq? (car expr) 'let)
          (= (length (cadr expr)) 1)
          (pair? (cddr expr)))
     (let* ((b (car (cadr expr)))
            (bvar (car b))
            (rhs (cadr b))
            (let-body (caddr expr)))
       (if (eq? bvar var)
           #f
           (cond
             ((and (occurs-in? var rhs) (not (occurs-in? var let-body)))
              (let ((rw-rhs (contify-prefix-rewrite var params lbody rhs)))
                (if rw-rhs
                    (list 'let (list (list bvar rw-rhs)) let-body)
                    #f)))
             ((and (not (occurs-in? var rhs)) (occurs-in? var let-body))
              (let ((rw-body (contify-prefix-rewrite var params lbody let-body)))
                (if rw-body
                    (list 'let (list b) rw-body)
                    #f)))
             (else #f)))))
    ((and (eq? (car expr) '%cont-fun) (>= (length expr) 5))
     (let ((inner-f (cadr expr))
           (inner-ps (caddr expr))
           (inner-fb (cadddr expr))
           (inner-in (cadr (cdddr expr))))
       (if (and (not (eq? inner-f var))
                (not (memq var inner-ps))
                (not (occurs-in? var inner-fb)))
           (let ((rw-in (contify-prefix-rewrite var params lbody inner-in)))
             (if rw-in
                 (list '%cont-fun inner-f inner-ps inner-fb rw-in)
                 #f))
           #f)))
    (else #f)))

(define (contify-letrec-prefix-candidate ir x* e* body)
  (and (= (length x*) 1)
       (has-call? (car x*) body)
       (let ((var (car x*))
             (val (car e*)))
         (and (pair? val)
              (eq? (car val) 'lambda)
              (pair? (cdr val))
              (pair? (cddr val))
              (not (occurs-in? 'cons (caddr val)))
              (not (escapes? var body))
              (not (escapes? var (caddr val)))
              (tail-calls-only? var (caddr val))
              (contify-prefix-rewrite var (cadr val) (caddr val) body)))))

(define (contify-find-peelable-binding bindings)
  (let ((all-vars (map car* bindings)))
    (let loop ((bs bindings))
      (if (null? bs)
          #f
          (let* ((b (car bs))
                 (var (car b))
                 (val (cadr b))
                 (other-vars (let fl ((vs all-vars) (acc '()))
                               (if (null? vs) (reverse acc)
                                   (fl (cdr vs) (if (eq? (car vs) var) acc (cons (car vs) acc)))))))
            (if (and (pair? val)
                     (eq? (car val) 'lambda)
                     (pair? (cdr val))
                     (pair? (cddr val))
                     (not (occurs-in? 'cons (caddr val)))
                     (not (occurs-in? 'car (caddr val)))
                     (not (occurs-in? 'cdr (caddr val)))
                     (not (occurs-in-other-bindings? var bindings))
                     (not (let uloop ((vs other-vars))
                            (and (pair? vs)
                                 (or (occurs-in? (car vs) val)
                                     (uloop (cdr vs)))))))
                b
                (loop (cdr bs))))))))

(define-picopass rule-contify-letrec
  :reads '(letrec) :writes '(%cont-fun)
  (Expr
    ((letrec ((,x* ,e*) ...) ,body) (guard (and (>= (length x*) 2)
                                                 (contify-find-peelable-binding
                                                  (let zloop ((xs x*) (es e*) (acc '()))
                                                    (if (or (null? xs) (null? es))
                                                        (reverse acc)
                                                        (zloop (cdr xs) (cdr es) (cons (list (car xs) (car es)) acc)))))))
     (let* ((bindings (let zloop ((xs x*) (es e*) (acc '()))
                        (if (or (null? xs) (null? es))
                            (reverse acc)
                            (zloop (cdr xs) (cdr es) (cons (list (car xs) (car es)) acc)))))
            (peel (contify-find-peelable-binding bindings))
            (peel-var (car peel))
            (rest-bindings (let rloop ((bs bindings) (acc '()))
                             (if (null? bs) (reverse acc)
                                 (rloop (cdr bs) (if (eq? (caar bs) peel-var) acc (cons (car bs) acc))))))
            (rest-expr (if (null? rest-bindings) body (list 'letrec rest-bindings body)))
            (opt-rest (if (null? rest-bindings) body (contify-opt rest-expr)))
            (peel-val (cadr peel)))
       (or (and (pair? peel-val)
                (eq? (car peel-val) 'lambda)
                (pair? (cdr peel-val))
                (pair? (cddr peel-val))
                (contifiable-binding? peel-var peel-val opt-rest)
                (list '%cont-fun peel-var (cadr peel-val)
                      (contify-calls peel-var (caddr peel-val))
                      (contify-calls peel-var opt-rest)))
           (and (pair? peel-val)
                (eq? (car peel-val) 'lambda)
                (pair? (cdr peel-val))
                (pair? (cddr peel-val))
                (not (escapes? peel-var opt-rest))
                (not (escapes? peel-var (caddr peel-val)))
                (tail-calls-only? peel-var (caddr peel-val))
                (contify-prefix-rewrite peel-var (cadr peel-val) (caddr peel-val) opt-rest))
           (list 'letrec (list peel) opt-rest))))
    ((letrec ((,x* ,e*) ...) ,body) (guard (contify-letrec-reducible? ir x* body))
     (let* ((contifiable-vars (femto-contifiable? ir))
            (var (car contifiable-vars))
            (val (car e*))
            (params (cadr val))
            (lbody (caddr val))
            (opt-lbody (contify-calls var lbody))
            (opt-body (contify-calls var body)))
       (list '%cont-fun var params opt-lbody opt-body)))
    ((letrec ((,x* ,e*) ...) ,body) (guard (contify-letrec-prefix-candidate ir x* e* body))
     (contify-letrec-prefix-candidate ir x* e* body))))

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
