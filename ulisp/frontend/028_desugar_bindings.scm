;;; =======================================================================
;;; ULisp Compiler Pass 028: Local Bindings Desugaring Pass
;;; Conforms to DSN-33 Architecture Specification & Nanopass Standard
;;; Desugars local binding constructs (let*, named let) and body sequences
;;; =======================================================================

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

(define (desugar-do bindings exit-clause commands)
  (let* ((loop-sym (unique-symbol "do_loop_"))
         (init-bindings
          (map (lambda (b) (list (car b) (cadr b))) bindings))
         (test (car exit-clause))
         (res (cdr exit-clause))
         (then-expr
          (if (null? res)
              #f
              (make-body-expr res)))
         (step-exprs
          (map (lambda (b)
                 (if (pair? (cddr b))
                     (caddr b)
                     (car b)))
               bindings))
         (loop-call (cons loop-sym step-exprs))
         (else-expr
          (make-body-expr (append commands (list loop-call)))))
    (list 'let loop-sym init-bindings
          (list 'if test
                then-expr
                else-expr))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass Definition: Desugar Bindings
;;; -----------------------------------------------------------------------
(define-pass desugar-bindings : L_src (ir) -> L_core ()
  (Expr : Expr (ir) -> Expr ()
    ((let* ,bindings . ,bodies) (Expr (desugar-let* bindings bodies)))
    ((let ,name ,bindings . ,bodies) (guard (symbol? name))
     (Expr (desugar-named-let (cons 'let (cons name (cons bindings bodies))))))
    ((let ,bindings ,b1 ,b2 . ,rest) (guard (list? bindings))
     (Expr (list 'let bindings (cons 'begin (cons b1 (cons b2 rest))))))
    ((lambda ,params ,b1 ,b2 . ,rest)
     (Expr (list 'lambda params (cons 'begin (cons b1 (cons b2 rest))))))
    ((do ,bindings ,exit-clause . ,commands)
     (Expr (desugar-do bindings exit-clause commands)))))
