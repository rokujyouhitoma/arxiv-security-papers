;;; =======================================================================
;;; ULisp Compiler Pass 029: Dynamic Environment & Multiple Values Desugaring Pass
;;; Conforms to DSN-33 Architecture Specification & Nanopass Standard
;;; Desugars let-values, let*-values, guard, and parameterize constructs
;;; =======================================================================

(define (desugar-guard-clauses var clauses)
  (let loop ((cls clauses))
    (cond
      ((null? cls)
       (list (list 'else (list 'raise var))))
      ((eq? (caar cls) 'else)
       cls)
      (else
       (cons (car cls) (loop (cdr cls)))))))

(define (desugar-guard spec bodies)
  (let ((var (car spec))
        (clauses (cdr spec)))
    (list '%with-handler
          (list 'lambda (list var)
                (cons 'cond (desugar-guard-clauses var clauses)))
          (cons 'lambda (cons '() bodies)))))

(define (desugar-let-values bindings bodies)
  (if (null? bindings)
      (make-body-expr bodies)
      (let ((b (car bindings)))
        (list 'call-with-values
              (list 'lambda '() (cadr b))
              (list 'lambda (car b)
                    (desugar-let-values (cdr bindings) bodies))))))

(define (desugar-let*-values bindings bodies)
  (if (null? bindings)
      (make-body-expr bodies)
      (desugar-let-values (list (car bindings))
                          (list (desugar-let*-values (cdr bindings) bodies)))))

(define (desugar-parameterize bindings bodies)
  (if (null? bindings)
      (make-body-expr bodies)
      (let loop ((rest bindings)
                 (let-bindings '())
                 (save-and-set '())
                 (restore '()))
        (if (null? rest)
            (let* ((before-thunk
                    (list 'lambda '() (cons 'begin (reverse save-and-set))))
                   (after-thunk
                    (list 'lambda '() (cons 'begin (reverse restore))))
                   (exc-sym (unique-symbol "exc_"))
                   (body-expr
                    (list 'guard (list exc-sym (list 'else (cons 'begin (append (reverse restore) (list (list 'raise exc-sym))))))
                          (make-body-expr bodies)))
                   (body-thunk
                    (list 'lambda '() body-expr)))
              (list 'let (reverse let-bindings)
                    (list 'dynamic-wind before-thunk body-thunk after-thunk)))
            (let* ((b (car rest))
                   (param-expr (car b))
                   (val-expr (cadr b))
                   (p-sym (unique-symbol "param_"))
                   (v-sym (unique-symbol "newval_"))
                   (old-sym (unique-symbol "oldcell_")))
              (loop (cdr rest)
                    (cons (list old-sym (list 'cons #f ''()))
                          (cons (list v-sym val-expr)
                                (cons (list p-sym param-expr)
                                      let-bindings)))
                    (cons (list p-sym v-sym)
                          (cons (list 'set-car! old-sym (list p-sym))
                                save-and-set))
                    (cons (list p-sym (list 'car old-sym))
                          restore)))))))
