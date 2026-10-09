;;; =======================================================================
;;; ULisp Compiler Pass 4: ANF (A-Normal Form) Normalization Nanopass
;;; Conforms to DSN-33 Architecture Specification
;;; Note: Normalizes complex expressions so that all function/primitive
;;;       arguments are atomic (symbols or immediate constants).
;;;       Uses a scoped temporary variable pool (%t0..%t8) to eliminate
;;;       string->symbol heap allocation overhead during bootstrap.
;;; =======================================================================

;;; Fixed pool of temporary variables by nesting depth (Zero heap allocation)
(define (%t-var depth)
  (case depth
    ((0) '%t0)
    ((1) '%t1)
    ((2) '%t2)
    ((3) '%t3)
    ((4) '%t4)
    ((5) '%t5)
    ((6) '%t6)
    ((7) '%t7)
    (else '%t8)))

;;; Collects bindings for non-atomic expressions among a list of arguments.
;;; Returns a pair (bindings . atomic-args).
(define (anf-flatten-args args depth)
  (let loop ((rest args) (d depth) (bindings '()) (atom-args '()))
    (if (null? rest)
        (cons (reverse bindings) (reverse atom-args))
        (let ((arg (car rest)))
          (if (atomic-expr? arg)
              (loop (cdr rest) d bindings (cons arg atom-args))
              (let* ((flat-arg (anf-expr-depth arg (+ d 1)))
                     (tmp (%t-var d)))
                (loop (cdr rest)
                      (+ d 1)
                      (cons (list tmp flat-arg) bindings)
                      (cons tmp atom-args))))))))

;;; Wraps an expression with let-bindings if any exist
(define (anf-wrap-bindings bindings body)
  (if (null? bindings)
      body
      (list 'let bindings body)))

;;; Recursively normalizes an arbitrary expression into A-Normal Form with nesting depth tracking
(define (anf-expr-depth expr depth)
  (cond
    ((atomic-expr? expr) expr)
    ((pair? expr)
     (let ((op (car expr)))
       (case op
         ((quote) expr)
         ((if)
          (let ((test (cadr expr))
                (then (caddr expr))
                (else-val (if (null? (cdddr expr)) #f (cadddr expr))))
            (if (atomic-expr? test)
                (list 'if test (anf-expr-depth then depth) (anf-expr-depth else-val depth))
                (let* ((flat-test (anf-expr-depth test (+ depth 1)))
                       (tmp (%t-var depth)))
                  (list 'let (list (list tmp flat-test))
                        (list 'if tmp (anf-expr-depth then depth) (anf-expr-depth else-val depth)))))))
         ((begin)
          (let ((body (cdr expr)))
            (cond
              ((null? body) #f)
              ((null? (cdr body)) (anf-expr-depth (car body) depth))
              (else (cons 'begin (map (lambda (e) (anf-expr-depth e depth)) body))))))
         ((let)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (list 'let
                  (map (lambda (b) (list (car b) (anf-expr-depth (cadr b) depth))) bindings)
                  (anf-expr-depth body depth))))
         ((letrec)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (list 'letrec
                  (map (lambda (b) (list (car b) (anf-expr-depth (cadr b) depth))) bindings)
                  (anf-expr-depth body depth))))
         ((lambda)
          (let ((params (cadr expr))
                (body (caddr expr)))
            (list 'lambda params (anf-expr-depth body 0))))
         ((%make-closure)
          (let* ((label (cadr expr))
                 (env-args (cddr expr))
                 (res (anf-flatten-args env-args depth))
                 (bindings (car res))
                 (atom-env (cdr res)))
            (anf-wrap-bindings bindings (cons '%make-closure (cons label atom-env)))))
         (else
          ;; Primitive or function application: (op e1 e2 ...)
          (let* ((args-res (anf-flatten-args (cdr expr) depth))
                 (args-bindings (car args-res))
                 (atom-args (cdr args-res))
                 (flat-op (if (atomic-expr? op) op (anf-expr-depth op (+ depth (length args-bindings)))))
                 (call (cons flat-op atom-args)))
            (anf-wrap-bindings args-bindings call))))))
    (else expr)))

;;; Top-level entrypoint for ANF normalization
(define (anf-all form)
  (cond
    ((not (pair? form)) form)
    ((eq? (car form) '%program)
     (let ((defs (cadr form))
           (main (caddr form)))
       (list '%program
             (map (lambda (d)
                    (if (and (pair? d) (eq? (car d) 'define))
                        (list 'define (cadr d) (anf-expr-depth (caddr d) 0))
                        (anf-expr-depth d 0)))
                  defs)
             (anf-expr-depth main 0))))
    ((eq? (car form) 'define)
     (list 'define (cadr form) (anf-expr-depth (caddr form) 0)))
    (else
     (anf-expr-depth form 0))))
