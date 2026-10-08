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
