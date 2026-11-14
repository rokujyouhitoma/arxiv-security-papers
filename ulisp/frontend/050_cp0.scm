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
;;; Top-level helpers for CP0 optimization
;;; -----------------------------------------------------------------------
(define (cp0-flatten-begin-list es)
  (let loop ((rest es) (acc '()))
    (cond
      ((null? rest) (reverse acc))
      ((and (pair? (car rest)) (eq? (caar rest) 'begin))
       (loop (append (cdar rest) (cdr rest)) acc))
      (else (loop (cdr rest) (cons (car rest) acc))))))

(define (cp0-zip-bindings xs es)
  (let loop ((x xs) (e es) (acc '()))
    (if (or (null? x) (null? e))
        (reverse acc)
        (loop (cdr x) (cdr e) (cons (list (car x) (car e)) acc)))))

;;; -----------------------------------------------------------------------
;;; Guard predicates for CP0 Picopass rules (preserving eq? sharing)
;;; -----------------------------------------------------------------------
(define (cp0-can-flatten-begin? es)
  (and (pair? es)
       (or (null? (cdr es))
           (let loop ((rest es))
             (and (pair? rest)
                  (or (and (pair? (car rest)) (eq? (caar rest) 'begin))
                      (loop (cdr rest))))))))

(define (cp0-has-dead-let-binding? x* e* body)
  (or (null? x*)
      (and (let has-pure? ((es e*))
             (and (pair? es)
                  (or (pure-expr? (car es))
                      (has-pure? (cdr es)))))
           (let ((body-frees (free-vars body '())))
             (let loop ((xs x*) (es e*))
               (and (pair? xs) (pair? es)
                    (or (and (pure-expr? (car es))
                             (not (memq (car xs) body-frees)))
                        (loop (cdr xs) (cdr es)))))))))

(define (cp0-has-dead-letrec-binding? x* e* body)
  (if (and (pair? x*)
           (null? (cdr x*))
           (pair? body)
           (eq? (car body) (car x*)))
      #f
      (let* ((bindings (cp0-zip-bindings x* e*))
             (reduced (dce-letrec bindings body)))
        (not (and (pair? reduced)
                  (eq? (car reduced) 'letrec)
                  (eq? (caddr reduced) body)
                  (= (length (cadr reduced)) (length bindings)))))))

(define (cp0-inlineable-unary-lambda? fn)
  (and (pair? fn)
       (eq? (car fn) 'lambda)
       (pair? (cdr fn))
       (pair? (cadr fn))
       (symbol? (caadr fn))
       (null? (cdadr fn))
       (pair? (cddr fn))
       (null? (cdddr fn))))

(define (cp0-call-values-reducible? p c)
  (or (and (pair? p) (eq? (car p) 'lambda) (null? (cadr p))
           (pair? (caddr p)) (memq (car (caddr p)) '(%values values))
           (pair? c) (eq? (car c) 'lambda) (list? (cadr c))
           (= (length (cdr (caddr p))) (length (cadr c))))
      (and (pair? p) (eq? (car p) 'lambda) (null? (cadr p))
           (not (and (pair? (caddr p)) (memq (car (caddr p)) '(%values values))))
           (pair? c) (eq? (car c) 'lambda) (list? (cadr c))
           (= (length (cadr c)) 1))))

;;; -----------------------------------------------------------------------
;;; First-Class Picopass Rules for CP0 Optimization (DSN-33-01 T5.2)
;;; -----------------------------------------------------------------------

(define-picopass rule-cp0-prune-if-3
  :reads '(if) :writes '(if)
  (Expr
    ((if ,test ,then ,else-val) (guard (const? test))
     (let ((v (extract-const-val test)))
       (if (eq? v #f) else-val then)))))

(define-picopass rule-cp0-prune-if-2
  :reads '(if) :writes '(if)
  (Expr
    ((if ,test ,then)
     (if (const? test)
         (let ((v (extract-const-val test)))
           (if (eq? v #f) #f then))
         (list 'if test then #f)))))

(define-picopass rule-cp0-flatten-begin
  :reads '(begin) :writes '(begin)
  (Expr
    ((begin ,es ...) (guard (cp0-can-flatten-begin? es))
     (let ((flat (cp0-flatten-begin-list es)))
       (cond
         ((null? flat) '(begin))
         ((null? (cdr flat)) (car flat))
         (else (cons 'begin flat)))))))

(define-picopass rule-cp0-dead-let
  :reads '(let) :writes '(let)
  (Expr
    ((let ((,x* ,e*) ...) ,body) (guard (cp0-has-dead-let-binding? x* e* body))
     (let* ((bindings (cp0-zip-bindings x* e*))
            (body-frees (free-vars body '()))
            (kept (filter (lambda (b)
                            (or (not (pure-expr? (cadr b)))
                                (memq (car b) body-frees)))
                          bindings)))
       (if (null? kept)
           body
           (list 'let kept body))))))

(define-picopass rule-cp0-dead-letrec
  :reads '(letrec) :writes '(letrec)
  (Expr
    ((letrec ((,x* ,e*) ...) ,body) (guard (cp0-has-dead-letrec-binding? x* e* body))
     (let ((bindings (cp0-zip-bindings x* e*)))
       (dce-letrec bindings body)))))

(define-picopass rule-cp0-call-values
  :reads '(%call-with-values) :writes '(let)
  (Expr
    ((%call-with-values ,producer ,consumer) (guard (cp0-call-values-reducible? producer consumer))
     (let ((p producer) (c consumer))
       (if (and (pair? (caddr p)) (memq (car (caddr p)) '(%values values)))
           (let* ((vals (cdr (caddr p)))
                  (vars (cadr c))
                  (cbody (caddr c))
                  (bindings (cp0-zip-bindings vars vals)))
             (list 'let bindings cbody))
           (let ((val (caddr p))
                 (var (car (cadr c)))
                 (cbody (caddr c)))
             (list 'let (list (list var val)) cbody)))))))

(define-picopass rule-cp0-const-fold
  :reads '() :writes '()
  (Expr
    ((,op ,args ...) (guard (and (symbol? op) (fold-const-op op args)))
     (fold-const-op op args))))

(define-picopass rule-cp0-inline-map-for-each
  :reads '(map for-each lambda) :writes '(letrec lambda if let begin)
  (Expr
    ((map ,fn ,ls) (guard (cp0-inlineable-unary-lambda? fn))
     (let ((param (caadr fn))
           (fbody (caddr fn))
           (loop-sym (unique-symbol "__cp0_map_loop_"))
           (cur-sym (unique-symbol "__cp0_map_cur_"))
           (acc-sym (unique-symbol "__cp0_map_acc_"))
           (val-sym (unique-symbol "__cp0_map_val_")))
       (list 'letrec
             (list (list loop-sym
                         (list 'lambda (list cur-sym acc-sym)
                               (list 'if (list 'pair? cur-sym)
                                     (list 'let (list (list val-sym (list 'let (list (list param (list 'car cur-sym))) fbody)))
                                           (list loop-sym (list 'cdr cur-sym) (list 'cons val-sym acc-sym)))
                                     (list 'reverse acc-sym)))))
             (list loop-sym ls ''()))))
    ((for-each ,fn ,ls) (guard (cp0-inlineable-unary-lambda? fn))
     (let ((param (caadr fn))
           (fbody (caddr fn))
           (loop-sym (unique-symbol "__cp0_fe_loop_"))
           (cur-sym (unique-symbol "__cp0_fe_cur_")))
       (list 'letrec
             (list (list loop-sym
                         (list 'lambda (list cur-sym)
                               (list 'if (list 'pair? cur-sym)
                                     (list 'begin
                                           (list 'let (list (list param (list 'car cur-sym))) fbody)
                                           (list loop-sym (list 'cdr cur-sym)))
                                     #f))))
             (list loop-sym ls))))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass: cp0-opt
;;; Bottom-up CP0 optimization: Constant Folding, Branch Pruning, and DCE
;;; -----------------------------------------------------------------------
(define-pass cp0-opt : L_core (ir) -> L_core ()
  (Expr : Expr (ir) -> Expr ()
    (fuse-rules :order post
      rule-cp0-prune-if-3
      rule-cp0-prune-if-2
      rule-cp0-flatten-begin
      rule-cp0-dead-let
      rule-cp0-dead-letrec
      rule-cp0-call-values
      rule-cp0-inline-map-for-each
      rule-cp0-const-fold)))

(define (cp0-expr expr)
  (cp0-opt expr))

;;; Top-level entrypoint for CP0 optimization
(define (cp0-optimize form)
  (cp0-opt form))
