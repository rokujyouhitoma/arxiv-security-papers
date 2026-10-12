;;; =======================================================================
;;; ULisp Compiler Pass 3: CP0 Source-Level Optimization Nanopass
;;; Conforms to DSN-33 Architecture Specification
;;; Note: Performs Constant Folding, Dead Branch Pruning, and Dead Let
;;;       Elimination on Canonical Core AST.
;;; =======================================================================

;;; Note: extract-const-val, val->ast-const, pure-expr?, and fold-const-op
;;;       are provided canonically by passes/00_helpers.scm.

;;; Bottom-up CP0 optimization of a single expression
(define (cp0-expr expr)
  (cond
    ((not (pair? expr)) expr)
    (else
     (let ((op (car expr)))
       (case op
         ((quote) expr)
         ((if)
          (let* ((test (cp0-expr (cadr expr)))
                 (then (cp0-expr (caddr expr)))
                 (else-val (if (null? (cdddr expr)) #f (cp0-expr (cadddr expr)))))
            (cond
              ;; Dead branch pruning
              ((const? test)
               (let ((v (extract-const-val test)))
                 (if (eq? v #f) else-val then)))
              (else
               (list 'if test then else-val)))))
         ((begin)
          (let* ((body (map cp0-expr (cdr expr)))
                 ;; Flatten nested begins
                 (flat-body
                  (let loop ((es body) (acc '()))
                    (cond
                      ((null? es) (reverse acc))
                      ((and (pair? (car es)) (eq? (caar es) 'begin))
                       (loop (append (cdar es) (cdr es)) acc))
                      (else (loop (cdr es) (cons (car es) acc)))))))
            (cond
              ((null? flat-body) #f)
              ((null? (cdr flat-body)) (car flat-body))
              (else (cons 'begin flat-body)))))
         ((let)
          (let* ((bindings (cadr expr))
                 (body (cp0-expr (caddr expr)))
                 (opt-bindings
                  (map (lambda (b) (list (car b) (cp0-expr (cadr b)))) bindings)))
            ;; Dead let elimination for single pure binding
            (if (and (= (length opt-bindings) 1)
                     (pure-expr? (cadar opt-bindings))
                     (not (memq (caar opt-bindings) (free-vars body '()))))
                body
                (list 'let opt-bindings body))))
         ((letrec)
          (let* ((bindings (cadr expr))
                 (body (cp0-expr (caddr expr)))
                 (opt-bindings
                  (map (lambda (b) (list (car b) (cp0-expr (cadr b)))) bindings)))
            (list 'letrec opt-bindings body)))
         ((lambda)
          (let ((params (cadr expr))
                (body (cp0-expr (caddr expr))))
            (list 'lambda params body)))
         ((%make-closure)
          (cons '%make-closure (cons (cadr expr) (map cp0-expr (cddr expr)))))
         (else
          ;; Primitive or application: optimize arguments first (bottom-up)
          (let* ((opt-op (if (symbol? op) op (cp0-expr op)))
                 (opt-args (map cp0-expr (cdr expr))))
            (or (and (symbol? opt-op) (fold-const-op opt-op opt-args))
                (cons opt-op opt-args)))))))))

;;; Top-level entrypoint for CP0 optimization
(define (cp0-optimize form)
  (cond
    ((not (pair? form)) form)
    ((eq? (car form) '%program)
     (let ((defs (cadr form))
           (main (caddr form)))
       (list '%program
             (map (lambda (d)
                    (if (and (pair? d) (eq? (car d) 'define))
                        (list 'define (cadr d) (cp0-expr (caddr d)))
                        (cp0-expr d)))
                  defs)
             (cp0-expr main))))
    ((eq? (car form) 'define)
     (list 'define (cadr form) (cp0-expr (caddr form))))
    (else
     (cp0-expr form))))
