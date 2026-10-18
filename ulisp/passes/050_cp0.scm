;;; =======================================================================
;;; ULisp Compiler Pass 3: CP0 Source-Level Optimization Nanopass
;;; Conforms to DSN-33 Architecture Specification
;;; Note: Performs Constant Folding, Dead Branch Pruning, and Dead Let
;;;       Elimination on Canonical Core AST.
;;; =======================================================================

;;; Note: extract-const-val, val->ast-const, pure-expr?, and fold-const-op
;;;       are provided canonically by passes/00_helpers.scm.

;;; Top-level & nested letrec Dead Code Elimination (DCE) based on Reachability Call Graph
(define (dce-letrec bindings body)
  (let* ((rec-vars (map car* bindings))
         (rec-filter (lambda (vars)
                       (filter (lambda (v) (memq v rec-vars)) vars)))
         ;; Map each binding var to its immediate dependencies within rec-vars
         (dep-alist (map (lambda (b)
                           (cons (car b) (rec-filter (free-vars (cadr b) '()))))
                         bindings))
         ;; Root variables:
         ;; 1. Variables in rec-vars that appear free in the body
         (body-roots (rec-filter (free-vars body '())))
         ;; 2. Variables in rec-vars whose initialization is impure (has side effects)
         (impure-roots (let loop ((bs bindings) (acc '()))
                         (cond
                           ((null? bs) acc)
                           ((not (pure-expr? (cadar bs)))
                            (loop (cdr bs) (cons (caar bs) acc)))
                           (else
                            (loop (cdr bs) acc)))))
         (initial-roots (set-union body-roots impure-roots)))
    ;; Transitive closure via worklist
    (let ((reachable
           (let loop ((worklist initial-roots) (visited '()))
             (if (null? worklist)
                 visited
                 (let ((v (car worklist))
                       (rest (cdr worklist)))
                   (if (memq v visited)
                       (loop rest visited)
                       (let* ((v-deps (let ((entry (assq v dep-alist)))
                                        (if entry (cdr entry) '())))
                              (new-worklist (append v-deps rest)))
                         (loop new-worklist (cons v visited)))))))))
      ;; Retain only bindings in reachable set
      (let ((kept-bindings (filter (lambda (b) (memq (car b) reachable)) bindings)))
        (if (null? kept-bindings)
            body
            (list 'letrec kept-bindings body))))))

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
                  (map (lambda (b) (list (car b) (cp0-expr (cadr b)))) bindings))
                 (body-frees (free-vars body '()))
                 (kept-bindings
                  (filter (lambda (b)
                            (or (not (pure-expr? (cadr b)))
                                (memq (car b) body-frees)))
                          opt-bindings)))
            (if (null? kept-bindings)
                body
                (list 'let kept-bindings body))))
         ((letrec)
          (let* ((bindings (cadr expr))
                 (body (cp0-expr (caddr expr)))
                 (opt-bindings
                  (map (lambda (b) (list (car b) (cp0-expr (cadr b)))) bindings)))
            (dce-letrec opt-bindings body)))
         ((lambda)
          (let ((params (cadr expr))
                (body (cp0-expr (caddr expr))))
            (list 'lambda params body)))
         ((%make-closure)
          (cons '%make-closure (cons (cadr expr) (map cp0-expr (cddr expr)))))
         ((%with-handler)
          (list '%with-handler (cp0-expr (cadr expr)) (cp0-expr (caddr expr))))
         ((%raw-call/cc)
          (list '%raw-call/cc (cp0-expr (cadr expr))))
         ((%call-with-values)
          (list '%call-with-values (cp0-expr (cadr expr)) (cp0-expr (caddr expr))))
         ((%values)
          (cons '%values (map cp0-expr (cdr expr))))
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
