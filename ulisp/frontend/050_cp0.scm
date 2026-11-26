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

(define (cp0-eq-testable-const-list? lst)
  (let loop ((xs lst) (n 0))
    (cond
      ((null? xs) #t)
      ((> n 256) #f)
      ((not (pair? xs)) #f)
      (else
       (let ((k (car xs)))
         (and (or (symbol? k) (boolean? k) (null? k))
              (loop (cdr xs) (+ n 1))))))))

(define (cp0-build-eq-chain var lst)
  (let loop ((xs lst))
    (cond
      ((null? xs) #f)
      ((null? (cdr xs))
       (list 'eq? var (val->ast-const (car xs))))
      (else
       (list 'if
             (list 'eq? var (val->ast-const (car xs)))
             #t
             (loop (cdr xs)))))))

(define (cp0-lower-memq-bool expr lst then-expr else-expr)
  (cond
    ((const? expr)
     (if (memq (extract-const-val expr) lst)
         then-expr
         else-expr))
    ((null? lst)
     (if (pure-expr? expr)
         else-expr
         (list 'begin expr else-expr)))
    ((symbol? expr)
     (if (and (eq? then-expr #t) (eq? else-expr #f))
         (cp0-build-eq-chain expr lst)
         (list 'if (cp0-build-eq-chain expr lst) then-expr else-expr)))
    (else
     (let ((tmp (unique-symbol "__cp0_mq_")))
       (list 'let (list (list tmp expr))
             (if (and (eq? then-expr #t) (eq? else-expr #f))
                 (cp0-build-eq-chain tmp lst)
                 (list 'if (cp0-build-eq-chain tmp lst) then-expr else-expr)))))))

(define-picopass rule-cp0-memq-quoted-bool
  :reads '(if not memq) :writes '(if let begin eq?)
  (Expr
    ((if (memq ,expr (quote ,lst)) ,then ,else-val)
     (guard (cp0-eq-testable-const-list? lst))
     (cp0-lower-memq-bool expr lst then else-val))
    ((if (memq ,expr (quote ,lst)) ,then)
     (guard (cp0-eq-testable-const-list? lst))
     (cp0-lower-memq-bool expr lst then #f))
    ((not (memq ,expr (quote ,lst)))
     (guard (cp0-eq-testable-const-list? lst))
     (cp0-lower-memq-bool expr lst #f #t))))

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

(define (cp0-all-const-args? args)
  (let loop ((as args))
    (if (null? as)
        #t
        (and (const? (car as)) (loop (cdr as))))))

(define (cp0-fold-expr op args)
  (let ((folded (fold-const-op op args)))
    (if folded
        folded
        (if (and (symbol? op) (cp0-all-const-args? args) (ctfe-pure-prim? op))
            (eval-in-language 'L_core (cons op args))
            #f))))

(define-picopass rule-cp0-const-fold
  :reads '() :writes '()
  (Expr
    ((,op ,args ...) (guard (and (symbol? op) (cp0-fold-expr op args)))
     (cp0-fold-expr op args))))

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
      rule-cp0-memq-quoted-bool
      rule-cp0-flatten-begin
      rule-cp0-dead-let
      rule-cp0-dead-letrec
      rule-cp0-call-values
      rule-cp0-inline-map-for-each
      rule-cp0-const-fold)))

;;; -----------------------------------------------------------------------
;;; Small Accessor & Leaf Primitive Inlining (Issue #958)
;;; -----------------------------------------------------------------------

(define (cp0-collect-set!-vars expr acc)
  (cond
    ((not (pair? expr)) acc)
    ((eq? (car expr) 'quote) acc)
    ((and (eq? (car expr) 'set!) (pair? (cdr expr)) (symbol? (cadr expr)))
     (let ((acc1 (if (memq (cadr expr) acc) acc (cons (cadr expr) acc))))
       (if (pair? (cddr expr))
           (cp0-collect-set!-vars (caddr expr) acc1)
           acc1)))
    (else
     (cp0-collect-set!-vars (cdr expr) (cp0-collect-set!-vars (car expr) acc)))))

(define (cp0-collect-duplicate-defs defs)
  (let loop ((ds defs) (seen '()) (dups '()))
    (if (null? ds)
        dups
        (let ((d (car ds)))
          (if (and (pair? d) (eq? (car d) 'define) (pair? (cdr d)) (symbol? (cadr d)))
              (let ((name (cadr d)))
                (if (memq name seen)
                    (loop (cdr ds) seen (if (memq name dups) dups (cons name dups)))
                    (loop (cdr ds) (cons name seen) dups)))
              (loop (cdr ds) seen dups))))))

(define (cp0-declare-form? e)
  (and (pair? e) (eq? (car e) 'declare)))

(define (cp0-unwrap-accessor-body expr)
  (cond
    ((and (pair? expr) (eq? (car expr) 'begin) (pair? (cdr expr)))
     (let loop ((es (cdr expr)))
       (cond
         ((null? es) '(begin))
         ((cp0-declare-form? (car es)) (loop (cdr es)))
         ((null? (cdr es)) (cp0-unwrap-accessor-body (car es)))
         (else expr))))
    (else expr)))

(define (cp0-safe-accessor-prim? op)
  (case op
    ((car cdr caar cadr cdar cddr
      vector-ref vector-length string-length bytevector-length bytevector-u8-ref
      eq? eqv? pair? null? symbol? number? integer? fixnum? boolean?
      string? vector? bytevector? procedure? char? eof-object?
      not zero?)
     #t)
    (else #f)))

(define (cp0-proper-param-list? params)
  (and (list? params)
       (let ((n (length params)))
         (and (>= n 1) (<= n 2)))
       (let loop ((ps params))
         (or (null? ps)
             (and (symbol? (car ps))
                  (loop (cdr ps)))))))

(define (cp0-accessor-cost expr params self-name)
  (cond
    ((const? expr) 0)
    ((symbol? expr)
     (if (memq expr params) 0 #f))
    ((and (pair? expr) (list? expr))
     (let ((op (car expr)))
       (if (and (symbol? op)
                (not (eq? op self-name))
                (not (memq op params))
                (cp0-safe-accessor-prim? op))
           (let loop ((args (cdr expr)) (total 1))
             (cond
               ((> total 2) #f)
               ((null? args) total)
               (else
                (let ((c (cp0-accessor-cost (car args) params self-name)))
                  (if (or (not c) (> (+ total c) 2))
                      #f
                      (loop (cdr args) (+ total c)))))))
           #f)))
    (else #f)))

(define (cp0-collect-expr-ops expr acc)
  (cond
    ((const? expr) acc)
    ((symbol? expr) acc)
    ((pair? expr)
     (let ((op (car expr)))
       (let loop ((args (cdr expr))
                  (cur (if (and (symbol? op) (not (memq op acc)))
                           (cons op acc)
                           acc)))
         (if (null? args)
             cur
             (loop (cdr args) (cp0-collect-expr-ops (car args) cur))))))
    (else acc)))

(define (cp0-inlineable-lambda? name rhs mutated-vars dup-defs)
  (and (symbol? name)
       (not (memq name mutated-vars))
       (not (memq name dup-defs))
       (pair? rhs)
       (eq? (car rhs) 'lambda)
       (pair? (cdr rhs))
       (cp0-proper-param-list? (cadr rhs))
       (pair? (cddr rhs))
       (let* ((params (cadr rhs))
              (raw-body (cddr rhs))
              (clean-list (let strip ((es raw-body))
                            (if (and (pair? es) (cp0-declare-form? (car es)))
                                (strip (cdr es))
                                es)))
              (single-body (if (and (pair? clean-list) (null? (cdr clean-list)))
                               (cp0-unwrap-accessor-body (car clean-list))
                               #f))
              (cost (and single-body (cp0-accessor-cost single-body params name))))
         (and cost
              (<= cost 2)
              (list name params single-body (cp0-collect-expr-ops single-body '()))))))

(define (cp0-any-memq? needles haystack)
  (let loop ((ns needles))
    (and (pair? ns)
         (or (memq (car ns) haystack)
             (loop (cdr ns))))))

(define (cp0-filter-shadowed-env env names)
  (cond
    ((null? env) '())
    ((null? names) env)
    (else
     (let loop ((es env) (acc '()) (changed? #f))
       (cond
         ((null? es) (if changed? (reverse acc) env))
         ((memq (caar es) names) (loop (cdr es) acc #t))
         (else (loop (cdr es) (cons (car es) acc) changed?)))))))

(define (cp0-lambda-formal-syms formals)
  (let loop ((f formals) (acc '()))
    (cond
      ((null? f) acc)
      ((symbol? f) (cons f acc))
      ((pair? f)
       (if (symbol? (car f))
           (loop (cdr f) (cons (car f) acc))
           (loop (cdr f) acc)))
      (else acc))))

(define (cp0-subst-params expr subst)
  (cond
    ((const? expr) expr)
    ((symbol? expr)
     (let ((entry (assq expr subst)))
       (if entry (cdr entry) expr)))
    ((pair? expr)
     (cons (car expr)
           (map (lambda (a) (cp0-subst-params a subst)) (cdr expr))))
    (else expr)))

(define (cp0-all-atomic-exprs? args)
  (let loop ((as args))
    (or (null? as)
        (and (atomic-expr? (car as))
             (loop (cdr as))))))

(define (cp0-expand-accessor-call entry args shadowed)
  (let ((params (cadr entry))
        (body (caddr entry))
        (ops (cadddr entry)))
    (if (and (= (length args) (length params))
             (not (cp0-any-memq? ops shadowed)))
        (if (cp0-all-atomic-exprs? args)
            (cp0-subst-params body (let loop ((ps params) (as args) (acc '()))
                                     (if (null? ps)
                                         (reverse acc)
                                         (loop (cdr ps) (cdr as) (cons (cons (car ps) (car as)) acc)))))
            (let loop ((ps params) (as args) (bindings '()) (subst '()))
              (if (null? ps)
                  (let ((body-sub (cp0-subst-params body subst)))
                    (if (null? bindings)
                        body-sub
                        (list 'let (reverse bindings) body-sub)))
                  (let ((p (car ps))
                        (a (car as)))
                    (if (const? a)
                        (loop (cdr ps) (cdr as) bindings (cons (cons p a) subst))
                        (let ((tmp (unique-symbol "__cp0_inl_")))
                          (loop (cdr ps) (cdr as)
                                (cons (list tmp a) bindings)
                                (cons (cons p tmp) subst))))))))
        #f)))

(define (cp0-inline-walk-list es inline-env shadowed)
  (let loop ((rem es) (rev '()) (changed? #f))
    (if (null? rem)
        (if changed? (reverse rev) es)
        (let* ((e (car rem))
               (ne (cp0-inline-walk e inline-env shadowed)))
          (loop (cdr rem) (cons ne rev) (or changed? (not (eq? ne e))))))))

(define (cp0-harvest-defs defs base-env mutated-vars dup-defs shadowed)
  (let round-loop ((round 0) (cur-env base-env))
    (if (>= round 2)
        cur-env
        (let def-loop ((ds defs) (acc cur-env) (added? #f))
          (if (null? ds)
              (if added?
                  (round-loop (+ round 1) acc)
                  acc)
              (let ((d (car ds)))
                (if (and (pair? d) (eq? (car d) 'define) (pair? (cdr d)) (pair? (cddr d)) (symbol? (cadr d)))
                    (let ((name (cadr d))
                          (rhs (caddr d)))
                      (if (assq name acc)
                          (def-loop (cdr ds) acc added?)
                          (let* ((opt-rhs (cp0-inline-walk rhs acc shadowed))
                                 (info (cp0-inlineable-lambda? name opt-rhs mutated-vars dup-defs)))
                            (if info
                                (def-loop (cdr ds) (cons info acc) #t)
                                (def-loop (cdr ds) acc added?)))))
                    (def-loop (cdr ds) acc added?))))))))

(define (cp0-harvest-letrec-defs bindings base-env mutated-vars shadowed)
  (let loop ((bs bindings) (acc base-env))
    (if (null? bs)
        acc
        (let* ((b (car bs))
               (name (car b))
               (rhs (cadr b)))
          (if (or (memq name mutated-vars) (assq name acc))
              (loop (cdr bs) acc)
              (let* ((opt-rhs (cp0-inline-walk rhs acc shadowed))
                     (info (cp0-inlineable-lambda? name opt-rhs mutated-vars '())))
                (if info
                    (loop (cdr bs) (cons info acc))
                    (loop (cdr bs) acc))))))))

(define (cp0-inline-walk expr inline-env shadowed)
  (cond
    ((not (pair? expr)) expr)
    ((const? expr) expr)
    (else
     (let ((head (car expr)))
       (cond
         ((or (eq? head 'quote) (eq? head 'declare))
          expr)
         ((and (eq? head '%program) (pair? (cdr expr)) (pair? (cddr expr)))
          (let* ((defs (cadr expr))
                 (main-body (caddr expr))
                 (mutated (cp0-collect-set!-vars main-body (cp0-collect-set!-vars defs '())))
                 (dups (cp0-collect-duplicate-defs defs))
                 (prog-env (cp0-harvest-defs defs inline-env mutated dups shadowed))
                 (new-defs
                  (let dloop ((ds defs) (rev '()) (changed? #f))
                    (if (null? ds)
                        (if changed? (reverse rev) defs)
                        (let ((d (car ds)))
                          (if (and (pair? d) (eq? (car d) 'define) (pair? (cdr d)) (pair? (cddr d)))
                              (let* ((name (cadr d))
                                     (rhs (caddr d))
                                     (nrhs (cp0-inline-walk rhs prog-env shadowed))
                                     (nd (if (eq? nrhs rhs) d (list 'define name nrhs))))
                                (dloop (cdr ds) (cons nd rev) (or changed? (not (eq? nd d)))))
                              (let ((nd (cp0-inline-walk d prog-env shadowed)))
                                (dloop (cdr ds) (cons nd rev) (or changed? (not (eq? nd d))))))))))
                 (new-main (cp0-inline-walk main-body prog-env shadowed)))
            (if (and (eq? new-defs defs) (eq? new-main main-body))
                expr
                (list '%program new-defs new-main))))
         ((and (eq? head 'lambda) (pair? (cdr expr)))
          (let* ((formals (cadr expr))
                 (bodies (cddr expr))
                 (f-syms (cp0-lambda-formal-syms formals))
                 (inner-env (cp0-filter-shadowed-env inline-env f-syms))
                 (inner-shadow (append f-syms shadowed))
                 (new-bodies (cp0-inline-walk-list bodies inner-env inner-shadow)))
            (if (eq? new-bodies bodies)
                expr
                (cons 'lambda (cons formals new-bodies)))))
         ((and (eq? head 'let) (pair? (cdr expr)) (list? (cadr expr)) (pair? (cddr expr)))
          (let* ((bindings (cadr expr))
                 (bodies (cddr expr))
                 (new-bindings
                  (let bloop ((bs bindings) (rev '()) (changed? #f))
                    (if (null? bs)
                        (if changed? (reverse rev) bindings)
                        (let* ((b (car bs))
                               (nrhs (cp0-inline-walk (cadr b) inline-env shadowed))
                               (nb (if (eq? nrhs (cadr b)) b (list (car b) nrhs))))
                          (bloop (cdr bs) (cons nb rev) (or changed? (not (eq? nb b))))))))
                 (bound-vars (map car* bindings))
                 (inner-env (cp0-filter-shadowed-env inline-env bound-vars))
                 (inner-shadow (append bound-vars shadowed))
                 (new-bodies (cp0-inline-walk-list bodies inner-env inner-shadow)))
            (if (and (eq? new-bindings bindings) (eq? new-bodies bodies))
                expr
                (cons 'let (cons new-bindings new-bodies)))))
         ((and (eq? head 'letrec) (pair? (cdr expr)) (list? (cadr expr)) (pair? (cddr expr)))
          (let* ((bindings (cadr expr))
                 (bodies (cddr expr))
                 (bound-vars (map car* bindings))
                 (mutated (cp0-collect-set!-vars bodies (cp0-collect-set!-vars bindings '())))
                 (base-env (cp0-filter-shadowed-env inline-env bound-vars))
                 (inner-shadow (append bound-vars shadowed))
                 (rec-env (cp0-harvest-letrec-defs bindings base-env mutated inner-shadow))
                 (new-bindings
                  (let bloop ((bs bindings) (rev '()) (changed? #f))
                    (if (null? bs)
                        (if changed? (reverse rev) bindings)
                        (let* ((b (car bs))
                               (nrhs (cp0-inline-walk (cadr b) rec-env inner-shadow))
                               (nb (if (eq? nrhs (cadr b)) b (list (car b) nrhs))))
                          (bloop (cdr bs) (cons nb rev) (or changed? (not (eq? nb b))))))))
                 (new-bodies (cp0-inline-walk-list bodies rec-env inner-shadow)))
            (if (and (eq? new-bindings bindings) (eq? new-bodies bodies))
                expr
                (cons 'letrec (cons new-bindings new-bodies)))))
         ((and (eq? head 'set!) (pair? (cdr expr)) (pair? (cddr expr)))
          (let ((nval (cp0-inline-walk (caddr expr) inline-env shadowed)))
            (if (eq? nval (caddr expr))
                expr
                (list 'set! (cadr expr) nval))))
         ((memq head '(if begin))
          (let ((new-rest (cp0-inline-walk-list (cdr expr) inline-env shadowed)))
            (if (eq? new-rest (cdr expr))
                expr
                (cons head new-rest))))
         (else
          (let* ((new-op (if (symbol? head) head (cp0-inline-walk head inline-env shadowed)))
                 (new-args (cp0-inline-walk-list (cdr expr) inline-env shadowed))
                 (entry (and (symbol? head)
                             (assq head inline-env)))
                 (expanded (and entry (cp0-expand-accessor-call entry new-args shadowed))))
            (cond
              (expanded expanded)
              ((and (eq? new-op head) (eq? new-args (cdr expr))) expr)
              (else (cons new-op new-args))))))))))

(define (cp0-inline-accessors form)
  (cp0-inline-walk form '() '()))

(define (cp0-expr expr)
  (cp0-opt (cp0-inline-accessors expr)))

;;; Top-level entrypoint for CP0 optimization
(define (cp0-optimize form)
  (cp0-opt (cp0-inline-accessors form)))
