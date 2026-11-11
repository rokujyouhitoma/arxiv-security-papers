;;; =======================================================================
;;; ULisp Compiler Pass 027: Conditionals Desugaring Pass
;;; Conforms to DSN-33 Architecture Specification & Nanopass Standard
;;; Desugars conditional branching constructs (cond, case, and, or, chain comparisons, cond-expand)
;;; Refactored to define-picopass + fuse-rules per Issue #762 (DSN-33-01 T4.1)
;;; =======================================================================

(define (desugar-cond clauses)
  (if (or (null? clauses) (not (pair? clauses)))
      #f
      (let ((c (car clauses)))
        (cond
          ((not (pair? c))
           (desugar-cond (cdr clauses)))
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
    ((not (pair? datum-list))
     (list 'eqv? k-var (list 'quote datum-list)))
    ((null? (cdr datum-list))
     (list 'eqv? k-var (list 'quote (car datum-list))))
    (else
     (cons 'or (map (lambda (d) (list 'eqv? k-var (list 'quote d))) datum-list)))))

(define (desugar-case key clauses)
  (let ((k-var (unique-symbol "case_key_")))
    (list 'let (list (list k-var key))
          (let loop ((cls clauses))
            (if (or (null? cls) (not (pair? cls)))
                #f
                (let ((c (car cls)))
                  (if (not (pair? c))
                      (loop (cdr cls))
                      (if (eq? (car c) 'else)
                          (cons 'begin (cdr c))
                          (list 'if (desugar-case-test k-var (car c))
                                (cons 'begin (cdr c))
                                (loop (cdr cls)))))))))))

(define (desugar-and args)
  (cond
    ((null? args) #t)
    ((not (pair? args)) args)
    ((null? (cdr args)) (car args))
    (else
     (list 'if (car args) (desugar-and (cdr args)) #f))))

(define (desugar-or args)
  (cond
    ((null? args) #f)
    ((not (pair? args)) args)
    ((null? (cdr args)) (car args))
    (else
     (let ((tmp (unique-symbol "or_tmp_")))
       (list 'let (list (list tmp (car args)))
             (list 'if tmp tmp (desugar-or (cdr args))))))))

(define (desugar-chain-cmp op args)
  (cond
    ((null? args) #t)
    ((not (pair? args)) #t)
    ((null? (cdr args)) #t)
    ((null? (cddr args))
     (cons op args))
    (else
     (let* ((vars (map (lambda (a) (unique-symbol "cmp_")) args))
            (bindings (let b-loop ((vs vars) (as args))
                        (if (or (null? vs) (not (pair? vs)))
                            '()
                            (cons (list (car vs) (car as))
                                  (b-loop (cdr vs) (cdr as))))))
            (pairs (let loop ((vs vars))
                     (if (or (null? (cdr vs)) (not (pair? (cdr vs))))
                         '()
                         (cons (list op (car vs) (cadr vs))
                               (loop (cdr vs)))))))
        (list 'let bindings
              (cons 'and pairs))))))

(define (desugar-cond-expand clauses)
  (let ((matched (expand-cond-expand clauses)))
    (cond
      ((null? matched) #f)
      ((null? (cdr matched)) (car matched))
      (else (cons 'begin matched)))))

;;; -----------------------------------------------------------------------
;;; Pass 027 Picopass Rule Definitions (DSN-33-01 T4.1)
;;; -----------------------------------------------------------------------

(define-picopass rule-desugar-cond-expand
  (Expr
    ((cond-expand ,clauses ...) (desugar-cond-expand clauses))
    ((cond-expand . ,clauses) (desugar-cond-expand clauses))))

(define-picopass rule-desugar-cond
  (Expr
    ((cond ,clauses ...) (desugar-cond clauses))
    ((cond . ,clauses) (desugar-cond clauses))))

(define-picopass rule-desugar-case
  (Expr
    ((case ,key ,clauses ...) (desugar-case key clauses))
    ((case ,key . ,clauses) (desugar-case key clauses))))

(define-picopass rule-desugar-and
  (Expr
    ((and ,args ...) (desugar-and args))
    ((and . ,args) (desugar-and args))))

(define-picopass rule-desugar-or
  (Expr
    ((or ,args ...) (desugar-or args))
    ((or . ,args) (desugar-or args))))

(define-picopass rule-desugar-chain-cmp
  (Expr
    ((char<? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'char<? (cons a1 (cons a2 (cons a3 rest)))))
    ((char<=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'char<=? (cons a1 (cons a2 (cons a3 rest)))))
    ((char>? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'char>? (cons a1 (cons a2 (cons a3 rest)))))
    ((char>=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'char>=? (cons a1 (cons a2 (cons a3 rest)))))
    ((char=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'char=? (cons a1 (cons a2 (cons a3 rest)))))
    ((char-ci<? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'char-ci<? (cons a1 (cons a2 (cons a3 rest)))))
    ((char-ci<=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'char-ci<=? (cons a1 (cons a2 (cons a3 rest)))))
    ((char-ci>? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'char-ci>? (cons a1 (cons a2 (cons a3 rest)))))
    ((char-ci>=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'char-ci>=? (cons a1 (cons a2 (cons a3 rest)))))
    ((char-ci=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'char-ci=? (cons a1 (cons a2 (cons a3 rest)))))
    ((string<? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'string<? (cons a1 (cons a2 (cons a3 rest)))))
    ((string<=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'string<=? (cons a1 (cons a2 (cons a3 rest)))))
    ((string>? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'string>? (cons a1 (cons a2 (cons a3 rest)))))
    ((string>=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'string>=? (cons a1 (cons a2 (cons a3 rest)))))
    ((string=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'string=? (cons a1 (cons a2 (cons a3 rest)))))
    ((string-ci<? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'string-ci<? (cons a1 (cons a2 (cons a3 rest)))))
    ((string-ci<=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'string-ci<=? (cons a1 (cons a2 (cons a3 rest)))))
    ((string-ci>? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'string-ci>? (cons a1 (cons a2 (cons a3 rest)))))
    ((string-ci>=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'string-ci>=? (cons a1 (cons a2 (cons a3 rest)))))
    ((string-ci=? ,a1 ,a2 ,a3 . ,rest) (desugar-chain-cmp 'string-ci=? (cons a1 (cons a2 (cons a3 rest)))))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass Definition: Desugar Conditionals (fuse-rules)
;;; -----------------------------------------------------------------------
(define-pass desugar-conditionals : L_src (ir) -> L_core ()
  (fuse-rules
    rule-desugar-cond-expand
    rule-desugar-cond
    rule-desugar-case
    rule-desugar-and
    rule-desugar-or
    rule-desugar-chain-cmp))
