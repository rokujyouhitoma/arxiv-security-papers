;;; =======================================================================
;;; ULisp Compiler Pass 029: Dynamic Environment & Multiple Values Desugaring Pass
;;; Conforms to DSN-33 Architecture Specification & Nanopass Standard
;;; Desugars let-values, let*-values, define-values, guard, parameterize,
;;; delay, delay-force, make-parameter, values, error, assume, syntax-error
;;; Refactored to define-picopass + fuse-rules per Issue #762 (DSN-33-01 T4.1)
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

(define (desugar-define-values formals expr rest)
  (if (null? rest)
      (list 'call-with-values
            (list 'lambda '() expr)
            (list 'lambda (if (list? formals) formals (list formals)) #f))
      (list 'let-values
            (list (list formals expr))
            (make-body-expr rest))))

(define (desugar-delay expr)
  (let ((body (if (null? (cddr expr))
                  (cadr expr)
                  (cons 'begin (cdr expr)))))
    (list '%%make-promise ''lazy (list 'lambda '() (list '%%make-promise ''eager body)))))

(define (desugar-delay-force expr)
  (let ((body (if (null? (cddr expr))
                  (cadr expr)
                  (cons 'begin (cdr expr)))))
    (list '%%make-promise ''lazy (list 'lambda '() body))))

(define (desugar-make-parameter args)
  (if (null? (cdr args))
      (list 'make-parameter-1 (car args))
      (list 'make-parameter-2 (car args) (cadr args))))

(define (desugar-values args)
  (cond
    ((null? args) (list '%values))
    ((null? (cdr args)) (car args))
    (else (cons '%values args))))

(define (desugar-error expr)
  (let ((msg (cadr expr))
        (irritants (cddr expr)))
    (list 'raise (cons 'list (cons ''error-object (cons msg irritants))))))

(define (desugar-syntax-error expr)
  (let ((msg (if (and (pair? (cdr expr)) (string? (cadr expr)))
                 (cadr expr)
                 "invalid syntax"))
        (irritants (if (and (pair? (cdr expr)) (string? (cadr expr)))
                       (cddr expr)
                       (cdr expr))))
    (error (string-append "syntax-error [R7RS §4.3.1]: " msg) irritants)))

(define (desugar-assume expr)
  (let ((condition (cadr expr))
        (rest (cddr expr)))
    (let ((tmp (unique-symbol "assume_tmp_")))
      (let* ((msg (if (pair? rest) (car rest) "invalid assumption [SRFI 145]"))
             (objs (if (pair? rest) (cdr rest) '()))
             (err-call (cons 'error (cons msg (cons (list 'quote condition) objs)))))
        (list 'let (list (list tmp condition))
              (list 'if tmp
                    tmp
                    err-call))))))

;;; -----------------------------------------------------------------------
;;; Pass 029 Picopass & Attopass Rule Definitions (DSN-33-01 T4.1)
;;; -----------------------------------------------------------------------

(define-picopass rule-desugar-let-values
  (Expr
    ((let-values ,bindings . ,bodies) (desugar-let-values bindings bodies))
    ((let*-values ,bindings . ,bodies) (desugar-let*-values bindings bodies))))

(define-picopass rule-desugar-define-values
  (Expr
    ((begin (define-values ,formals ,expr) . ,rest)
      (desugar-define-values formals expr rest))
    ((define-values ,formals ,expr)
      (desugar-define-values formals expr '()))))

(define-picopass rule-desugar-guard
  (Expr
    ((guard ,spec . ,bodies) (desugar-guard spec bodies))))

(define-picopass rule-desugar-parameterize
  (Expr
    ((parameterize ,bindings . ,bodies) (desugar-parameterize bindings bodies))))

(define-picopass rule-desugar-delay
  (Expr
    ((delay . ,args) (desugar-delay (cons 'delay args)))
    ((delay-force . ,args) (desugar-delay-force (cons 'delay-force args)))))

(define-picopass rule-desugar-parameter-ops
  (Expr
    ((make-parameter . ,args) (desugar-make-parameter args))))

(define-picopass rule-desugar-values
  (Expr
    ((values . ,args) (desugar-values args))))

(define-picopass rule-desugar-error-assume
  (Expr
    ((error . ,args) (desugar-error (cons 'error args)))
    ((assume . ,args) (desugar-assume (cons 'assume args)))
    ((assert . ,args) (desugar-assume (cons 'assert args)))
    ((syntax-error . ,args) (desugar-syntax-error (cons 'syntax-error args)))))

;; 未展開の let-syntax / letrec-syntax を拒絶する不変条件 Attopass
(define-attopass atto-no-unexpanded-let-syntax
  (Expr
    ((let-syntax . ,args)
      (error "syntax-error [R7RS §4.3.1]: unexpanded let-syntax encountered in desugar" args))
    ((letrec-syntax . ,args)
      (error "syntax-error [R7RS §4.3.1]: unexpanded let-syntax encountered in desugar" args))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass Definition: Desugar Dynamic (fuse-rules)
;;; -----------------------------------------------------------------------
(define-pass desugar-dynamic : L_src (ir) -> L_core ()
  (fuse-rules
    rule-desugar-let-values
    rule-desugar-define-values
    rule-desugar-guard
    rule-desugar-parameterize
    rule-desugar-delay
    rule-desugar-parameter-ops
    rule-desugar-values
    rule-desugar-error-assume
    atto-no-unexpanded-let-syntax))
