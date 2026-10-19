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
