;;; =======================================================================
;;; ULisp Compiler Pass 1: Syntax Desugaring & Normalization Pass
;;; Conforms to DSN-33 Architecture Specification
;;; =======================================================================

(define (desugar-list args)
  (if (null? args)
      ''()
      (cons 'cons (cons (car args) (cons (desugar-list (cdr args)) '())))))

(define (desugar-string-append args)
  (cond
    ((null? args) "")
    ((null? (cdr args)) (car args))
    (else
     (list 'string-append2 (car args) (desugar-string-append (cdr args))))))

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

(define (desugar-case key clauses)
  (let ((k-var (unique-symbol "case_key_")))
    (list 'let (list (list k-var key))
          (let loop ((cls clauses))
            (if (null? cls)
                #f
                (let ((c (car cls)))
                  (if (eq? (car c) 'else)
                      (cons 'begin (cdr c))
                      (list 'if (list 'memq k-var (list 'quote (car c)))
                            (cons 'begin (cdr c))
                            (loop (cdr cls))))))))))

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

(define (desugar-named-let expr)
  (let* ((name (cadr expr))
         (bindings (caddr expr))
         (bodies (cdddr expr))
         (params (map car* bindings))
         (inits (map cadr bindings)))
    (list 'letrec
          (list (list name (cons 'lambda (cons params bodies))))
          (cons name inits))))

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

(define (rewrite-top-level forms)
  (let loop ((fs forms) (bindings '()) (bodies '()))
    (if (null? fs)
        (if (null? bindings)
            (make-body-expr (reverse bodies))
            (list 'letrec (reverse bindings) (make-body-expr (reverse bodies))))
        (let ((f (car fs)))
          (if (and (pair? f) (eq? (car f) 'define))
              (let ((def-spec (cadr f)))
                (if (pair? def-spec)
                    ;; (define (name . params) . body)
                    (let ((name (car def-spec))
                          (params (cdr def-spec))
                          (lbody (cddr f)))
                      (loop (cdr fs)
                            (cons (list name (cons 'lambda (cons params lbody))) bindings)
                            bodies))
                    ;; (define name val)
                    (let ((name def-spec)
                          (val (caddr f)))
                      (loop (cdr fs)
                            (cons (list name val) bindings)
                            bodies))))
              ;; Normal expression
              (loop (cdr fs) bindings (cons f bodies)))))))

;;; Pass 1: Canonical AST Desugaring Pass
;;; Recursively transforms an AST so that all high-level syntactic sugar
;;; (cond, case, let*, named-let, and, or, string-append, list) is expanded
;;; into canonical Core Scheme constructs (if, let, letrec, lambda, begin, primitives).
(define (desugar-all expr)
  (cond
    ((not (pair? expr)) expr)
    (else
     (let ((op (car expr)))
       (case op
         ((quote)
          expr)
         ((cond)
          (desugar-all (desugar-cond (cdr expr))))
         ((case)
          (desugar-all (desugar-case (cadr expr) (cddr expr))))
         ((let*)
          (desugar-all (desugar-let* (cadr expr) (cddr expr))))
         ((string-append)
          (desugar-all (desugar-string-append (cdr expr))))
         ((list)
          (desugar-all (desugar-list (cdr expr))))
         ((and)
          (desugar-all (desugar-and (cdr expr))))
         ((or)
          (desugar-all (desugar-or (cdr expr))))
         ((guard)
          (desugar-all (desugar-guard (cadr expr) (cddr expr))))
         ((let-values)
          (desugar-all (desugar-let-values (cadr expr) (cddr expr))))
         ((let*-values)
          (desugar-all (desugar-let*-values (cadr expr) (cddr expr))))
         ((%raw-call/cc)
          (list '%raw-call/cc (desugar-all (cadr expr))))
         ((call-with-values %call-with-values)
          (list '%call-with-values (desugar-all (cadr expr)) (desugar-all (caddr expr))))
         ((values)
          (let ((args (cdr expr)))
            (cond
              ((null? args)
               (list '%values))
              ((null? (cdr args))
               (desugar-all (car args)))
              (else
               (cons '%values (map desugar-all args))))))
         ((%values)
          (cons '%values (map desugar-all (cdr expr))))
         ((error)
          (let ((msg (cadr expr))
                (irritants (cddr expr)))
            (desugar-all (list 'raise (cons 'list (cons ''error-object (cons msg irritants)))))))
         ((%with-handler with-exception-handler)
          (list '%with-handler (desugar-all (cadr expr)) (desugar-all (caddr expr))))
         ((caar)
          (desugar-all (list 'car (list 'car (cadr expr)))))
         ((cadr)
          (desugar-all (list 'car (list 'cdr (cadr expr)))))
         ((cdar)
          (desugar-all (list 'cdr (list 'car (cadr expr)))))
         ((cddr)
          (desugar-all (list 'cdr (list 'cdr (cadr expr)))))
         ((caddr)
          (desugar-all (list 'car (list 'cdr (list 'cdr (cadr expr))))))
         ((cadddr)
          (desugar-all (list 'car (list 'cdr (list 'cdr (list 'cdr (cadr expr)))))))
         ((let)
          (if (symbol? (cadr expr))
              (desugar-all (desugar-named-let expr))
              (let ((bindings (cadr expr))
                    (bodies (cddr expr)))
                (list 'let
                      (map (lambda (b) (list (car b) (desugar-all (cadr b)))) bindings)
                      (desugar-all (make-body-expr bodies))))))
         ((letrec)
          (let ((bindings (cadr expr))
                (bodies (cddr expr)))
            (list 'letrec
                  (map (lambda (b) (list (car b) (desugar-all (cadr b)))) bindings)
                  (desugar-all (make-body-expr bodies)))))
         ((lambda)
          (let ((params (cadr expr))
                (bodies (cddr expr)))
            (list 'lambda params (desugar-all (make-body-expr bodies)))))
         ((if)
          (let ((test (desugar-all (cadr expr)))
                (then (desugar-all (caddr expr)))
                (else-expr (if (null? (cdddr expr))
                               #f
                               (desugar-all (cadddr expr)))))
            (list 'if test then else-expr)))
         ((begin)
          (cons 'begin (map desugar-all (cdr expr))))
         (else
          (cons (desugar-all op) (map desugar-all (cdr expr)))))))))
