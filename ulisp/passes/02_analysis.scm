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
         ((%cont-fun)
          (let* ((params (caddr expr))
                 (f-body (cadddr expr))
                 (in-body (cadr (cdddr expr)))
                 (f-bound (set-union params bound)))
            (set-union (free-vars f-body f-bound)
                       (free-vars in-body bound))))
         ((%cont-call)
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

;;; Checks whether `var` escapes (appears in non-operator position) within `expr`.
(define (escapes? var expr)
  (cond
    ((symbol? expr)
     (eq? expr var))
    ((not (pair? expr))
     #f)
    (else
     (let ((op (car expr)))
       (case op
         ((quote) #f)
         ((if)
          (or (escapes? var (cadr expr))
              (or (escapes? var (caddr expr))
                  (if (null? (cdddr expr)) #f (escapes? var (cadddr expr))))))
         ((begin)
          (let loop ((es (cdr expr)))
            (and (pair? es)
                 (or (escapes? var (car es))
                     (loop (cdr es))))))
         ((let)
          (let* ((bindings (cadr expr))
                 (body (caddr expr)))
            (or (let loop ((bs bindings))
                  (and (pair? bs)
                       (or (escapes? var (cadar bs))
                           (loop (cdr bs)))))
                (if (assq var bindings)
                    #f
                    (escapes? var body)))))
         ((letrec)
          (let* ((bindings (cadr expr))
                 (body (caddr expr)))
            (if (assq var bindings)
                #f
                (or (let loop ((bs bindings))
                      (and (pair? bs)
                           (or (escapes? var (cadar bs))
                               (loop (cdr bs)))))
                    (escapes? var body)))))
         ((lambda)
          (let ((params (cadr expr))
                (body (caddr expr)))
            (if (memq var params)
                #f
                ;; Crossing lambda boundary requires closure capture, thus escapes local CFG
                (if (memq var (free-vars body params))
                    #t
                    (escapes? var body)))))
         ((%make-closure)
          (let loop ((es (cddr expr)))
            (and (pair? es)
                 (or (escapes? var (car es))
                     (loop (cdr es))))))
         (else
          (if (eq? op var)
              ;; Operator position is safe; check arguments
              (let loop ((args (cdr expr)))
                (and (pair? args)
                     (or (escapes? var (car args))
                         (loop (cdr args)))))
              ;; Non-var operator: check operator and arguments
              (or (escapes? var op)
                  (let loop ((args (cdr expr)))
                    (and (pair? args)
                         (or (escapes? var (car args))
                             (loop (cdr args)))))))))))))

;;; Checks whether all call sites of `var` in `expr` are in tail position.
(define (tail-calls-only? var expr)
  (let check ((e expr) (tail? #t))
    (cond
      ((not (pair? e)) #t)
      (else
       (let ((op (car e)))
         (case op
           ((quote) #t)
           ((if)
            (and (check (cadr e) #f)
                 (check (caddr e) tail?)
                 (if (null? (cdddr e)) #t (check (cadddr e) tail?))))
           ((begin)
            (let loop ((es (cdr e)))
              (cond
                ((null? es) #t)
                ((null? (cdr es)) (check (car es) tail?))
                (else (and (check (car es) #f) (loop (cdr es)))))))
           ((let)
            (let ((bindings (cadr e))
                  (body (caddr e)))
              (and (let loop ((bs bindings))
                     (or (null? bs)
                         (and (check (cadar bs) #f) (loop (cdr bs)))))
                   (if (assq var bindings) #t (check body tail?)))))
           ((letrec)
            (let ((bindings (cadr e))
                  (body (caddr e)))
              (if (assq var bindings)
                  #t
                  (and (let loop ((bs bindings))
                         (or (null? bs)
                             (and (check (cadar bs) #f) (loop (cdr bs)))))
                       (check body tail?)))))
           ((lambda)
            (let ((params (cadr e))
                  (body (caddr e)))
              (if (memq var params) #t (check body #t))))
           (else
            (if (eq? op var)
                ;; Call site of var: must be in tail position
                (and tail?
                     (let loop ((args (cdr e)))
                       (or (null? args)
                           (and (check (car args) #f) (loop (cdr args))))))
                ;; Other call: operator and arguments are not in tail position
                (and (check op #f)
                     (let loop ((args (cdr e)))
                       (or (null? args)
                           (and (check (car args) #f) (loop (cdr args))))))))))))))

;;; Checks whether a binding `(var val)` in `(letrec ... body)` is contifiable.
(define (contifiable-binding? var val body)
  (and (pair? val)
       (eq? (car val) 'lambda)
       (pair? (cdr val))
       (pair? (cddr val))
       (not (escapes? var body))
       (not (escapes? var (caddr val)))
       (tail-calls-only? var body)
       (tail-calls-only? var (caddr val))))

