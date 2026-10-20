;;; =======================================================================
;;; ULisp Compiler Pass 027: Conditionals Desugaring Pass
;;; Conforms to DSN-33 Architecture Specification & Nanopass Standard
;;; Desugars conditional branching constructs (cond, case, and, or, chain comparisons)
;;; =======================================================================

(define (desugar-cond clauses)
  (if (null? clauses)
      #f
      (let ((c (car clauses)))
        (cond
          ((eq? (car c) 'else)
           (cons 'begin (cdr c)))
          ((and (pair? (cdr c)) (eq? (cadr c) '=>))
           (let ((tmp (unique-symbol "cond_tmp_")))
             (list 'let (list (list tmp (car c)))
                   (list 'if tmp
                         (list (caddr c) tmp)
                         (desugar-cond (cdr clauses))))))
          (else
           (list 'if (car c)
                 (cons 'begin (cdr c))
                 (desugar-cond (cdr clauses))))))))

(define (desugar-case-test k-var datum-list)
  (cond
    ((null? datum-list) #f)
    ((null? (cdr datum-list))
     (list 'eqv? k-var (list 'quote (car datum-list))))
    (else
     (cons 'or (map (lambda (d) (list 'eqv? k-var (list 'quote d))) datum-list)))))

(define (desugar-case key clauses)
  (let ((k-var (unique-symbol "case_key_")))
    (list 'let (list (list k-var key))
          (let loop ((cls clauses))
            (if (null? cls)
                #f
                (let ((c (car cls)))
                  (if (eq? (car c) 'else)
                      (cons 'begin (cdr c))
                      (list 'if (desugar-case-test k-var (car c))
                            (cons 'begin (cdr c))
                            (loop (cdr cls))))))))))

(define (desugar-and args)
  (cond
    ((null? args) #t)
    ((null? (cdr args)) (car args))
    (else
     (list 'if (car args) (desugar-and (cdr args)) #f))))

(define (desugar-or args)
  (cond
    ((null? args) #f)
    ((null? (cdr args)) (car args))
    (else
     (let ((tmp (unique-symbol "or_tmp_")))
       (list 'let (list (list tmp (car args)))
             (list 'if tmp tmp (desugar-or (cdr args))))))))

(define (desugar-chain-cmp op args)
  (cond
    ((null? args) #t)
    ((null? (cdr args)) #t)
    ((null? (cddr args))
     (cons op (map desugar-all args)))
    (else
     (let* ((vars (map (lambda (a) (unique-symbol "cmp_")) args))
            (bindings (let b-loop ((vs vars) (as args))
                        (if (null? vs)
                            '()
                            (cons (list (car vs) (desugar-all (car as)))
                                  (b-loop (cdr vs) (cdr as))))))
            (pairs (let loop ((vs vars))
                     (if (null? (cdr vs))
                         '()
                         (cons (list op (car vs) (cadr vs))
                               (loop (cdr vs)))))))
       (list 'let bindings
             (cons 'and pairs))))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass Definition: Desugar Conditionals
;;; -----------------------------------------------------------------------
(define-pass desugar-conditionals : L_src (ir) -> L_core ()
  (Expr : Expr (ir) -> Expr ()
    ((cond . ,clauses) (Expr (desugar-cond clauses)))
    ((case ,key . ,clauses) (Expr (desugar-case key clauses)))
    ((and . ,args) (Expr (desugar-and args)))
    ((or . ,args) (Expr (desugar-or args)))))
