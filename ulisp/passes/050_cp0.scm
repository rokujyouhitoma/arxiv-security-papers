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

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass: cp0-opt
;;; Bottom-up CP0 optimization: Constant Folding, Branch Pruning, and DCE
;;; -----------------------------------------------------------------------
(define-pass cp0-opt : L_core (ir) -> L_core ()
  (definitions
    (define (flatten-begin-list es)
      (let loop ((rest es) (acc '()))
        (cond
          ((null? rest) (reverse acc))
          ((and (pair? (car rest)) (eq? (caar rest) 'begin))
           (loop (append (cdar rest) (cdr rest)) acc))
          (else (loop (cdr rest) (cons (car rest) acc))))))
    (define (zip-bindings xs es)
      (let loop ((x xs) (e es) (acc '()))
        (if (or (null? x) (null? e))
            (reverse acc)
            (loop (cdr x) (cdr e) (cons (list (car x) (car e)) acc))))))
  (Expr : Expr (ir) -> Expr ()
    ((quote ,datum)
     ir)
    ((if ,test ,then ,else-val)
     (let ((opt-test (Expr test))
           (opt-then (Expr then))
           (opt-else (Expr else-val)))
       (if (const? opt-test)
           (let ((v (extract-const-val opt-test)))
             (if (eq? v #f) opt-else opt-then))
           (list 'if opt-test opt-then opt-else))))
    ((if ,test ,then)
     (let ((opt-test (Expr test))
           (opt-then (Expr then)))
       (if (const? opt-test)
           (let ((v (extract-const-val opt-test)))
             (if (eq? v #f) #f opt-then))
           (list 'if opt-test opt-then #f))))
    ((begin ,es ...)
     (let* ((opt-es (map Expr es))
            (flat (flatten-begin-list opt-es)))
       (cond
         ((null? flat) #f)
         ((null? (cdr flat)) (car flat))
         (else (cons 'begin flat)))))
    ((let ((,x* ,e*) ...) ,body)
     (let* ((opt-e* (map Expr e*))
            (opt-body (Expr body))
            (opt-bindings (zip-bindings x* opt-e*))
            (body-frees (free-vars opt-body '()))
            (kept-bindings
             (filter (lambda (b)
                       (or (not (pure-expr? (cadr b)))
                           (memq (car b) body-frees)))
                     opt-bindings)))
       (if (null? kept-bindings)
           opt-body
           (list 'let kept-bindings opt-body))))
    ((letrec ((,x* ,e*) ...) ,body)
     (let* ((opt-e* (map Expr e*))
            (opt-body (Expr body))
            (opt-bindings (zip-bindings x* opt-e*)))
       (dce-letrec opt-bindings opt-body)))
    ((lambda (,params ...) ,body)
     (list 'lambda params (Expr body)))
    ((%make-closure ,tag ,es ...)
     (cons '%make-closure (cons tag (map Expr es))))
    ((%make-closure-env ,tag ,es ...)
     (cons '%make-closure-env (cons tag (map Expr es))))
    ((%with-handler ,h ,body)
     (list '%with-handler (Expr h) (Expr body)))
    ((%raw-call/cc ,arg)
     (list '%raw-call/cc (Expr arg)))
    ((%call-with-values ,producer ,consumer)
     (let ((p (Expr producer))
           (c (Expr consumer)))
       (cond
         ((and (pair? p) (eq? (car p) 'lambda) (null? (cadr p))
               (pair? (caddr p)) (memq (car (caddr p)) '(%values values))
               (pair? c) (eq? (car c) 'lambda) (list? (cadr c))
               (= (length (cdr (caddr p))) (length (cadr c))))
          (let* ((vals (cdr (caddr p)))
                 (vars (cadr c))
                 (cbody (caddr c))
                 (bindings (zip-bindings vars vals)))
            (Expr (list 'let bindings cbody))))
         ((and (pair? p) (eq? (car p) 'lambda) (null? (cadr p))
               (not (and (pair? (caddr p)) (memq (car (caddr p)) '(%values values))))
               (pair? c) (eq? (car c) 'lambda) (list? (cadr c))
               (= (length (cadr c)) 1))
          (let ((val (caddr p))
                (var (car (cadr c)))
                (cbody (caddr c)))
            (Expr (list 'let (list (list var val)) cbody))))
         (else
          (list '%call-with-values p c)))))
    ((%values ,es ...)
     (cons '%values (map Expr es)))
    ((,op ,args ...)
     (let* ((opt-op (if (symbol? op) op (Expr op)))
            (opt-args (map Expr args)))
       (or (and (symbol? opt-op) (fold-const-op opt-op opt-args))
           (cons opt-op opt-args))))))

(define (cp0-expr expr)
  (cp0-opt expr))

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
