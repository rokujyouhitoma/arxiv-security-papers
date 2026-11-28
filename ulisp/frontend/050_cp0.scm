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

(define (cp0-fold-expr-boxed op args)
  (let ((boxed (fold-const-op-boxed op args)))
    (if boxed
        boxed
        (if (and (symbol? op) (cp0-all-const-args? args) (ctfe-pure-prim? op))
            (let ((r (eval-in-language 'L_core (cons op args))))
              (if r (list r) #f))
            #f))))

(define (cp0-fold-expr op args)
  (let ((boxed (cp0-fold-expr-boxed op args)))
    (if boxed (car boxed) #f)))

(define-picopass rule-cp0-const-fold
  :reads '() :writes '()
  (Expr
    ((,op ,args ...) (guard (and (symbol? op) (cp0-fold-expr-boxed op args)))
     (car (cp0-fold-expr-boxed op args)))))

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

(define (cp0-str-has-substr? str sub)
  (let ((slen (string-length str))
        (sublen (string-length sub)))
    (if (> sublen slen)
        #f
        (let loop ((i 0))
          (if (> (+ i sublen) slen)
              #f
              (let cmp ((j 0))
                (cond
                  ((= j sublen) #t)
                  ((char=? (string-ref str (+ i j)) (string-ref sub j)) (cmp (+ j 1)))
                  (else (loop (+ i 1))))))))))

(define (cp0-asm-or-runtime-stub-name? sym)
  (if (not (symbol? sym))
      #f
      (let ((s (symbol->string sym)))
        (or (cp0-str-has-substr? s "%asm-")
            (cp0-str-has-substr? s "%sys-")
            (cp0-str-has-substr? s "%init-worker-tls")
            (cp0-str-has-substr? s "%synapse-safepoint-poll!")
            (cp0-str-has-substr? s "%safepoint-poll!")))))

(define (cp0-inlineable-lambda? name rhs mutated-vars dup-defs)
  (and (symbol? name)
       (not (cp0-asm-or-runtime-stub-name? name))
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
              (cost (and single-body
                         (pair? single-body)
                         (cp0-accessor-cost single-body params name))))
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

;;; -----------------------------------------------------------------------
;;; General Cost/Use-Count Inliner & Hygienic Beta-Reduction (Issue #971)
;;; -----------------------------------------------------------------------

(define *cp0-inline-forced-max-cost* 4)
(define *cp0-inline-max-cost* 12)
(define *cp0-inline-single-use-max-cost* 36)
(define *cp0-inline-max-total-growth* 24)
(define *cp0-inline-unroll-max-cost* 16)

(define (cp0-proper-formal-list? params)
  (and (list? params)
       (<= (length params) 8)
       (let loop ((ps params) (seen '()))
         (cond
           ((null? ps) #t)
           ((and (symbol? (car ps)) (not (memq (car ps) seen)))
            (loop (cdr ps) (cons (car ps) seen)))
           (else #f)))))

(define (cp0-has-unsafe-inline-op? expr)
  (cond
    ((symbol? expr)
     (or (eq? expr '%num-args)
         (eq? expr '%get-rsp)
         (eq? expr '%get-rbp)
         (cp0-asm-or-runtime-stub-name? expr)))
    ((not (pair? expr)) #f)
    ((or (eq? (car expr) 'quote) (eq? (car expr) 'declare)) #f)
    ((memq (car expr)
           '(set! %num-args %get-rsp %get-rbp gc-collect! gc-minor-collect!
             call/cc %raw-call/cc dynamic-wind %with-handler
             with-exception-handler guard %cont-fun %cont-call
             %make-closure %make-closure-env %inline-asm error raise))
     #t)
    ((and (symbol? (car expr)) (cp0-asm-or-runtime-stub-name? (car expr)))
     #t)
    (else
     (or (cp0-has-unsafe-inline-op? (car expr))
         (cp0-has-unsafe-inline-op? (cdr expr))))))

(define (cp0-expr-cost-acc expr acc max-budget)
  (cond
    ((not acc) #f)
    ((> acc max-budget) #f)
    ((symbol? expr) acc)
    ((not (pair? expr)) acc)
    ((eq? (car expr) 'declare) acc)
    ((eq? (car expr) 'quote)
     (if (and (pair? (cdr expr))
              (or (null? (cadr expr))
                  (symbol? (cadr expr))
                  (boolean? (cadr expr))
                  (number? (cadr expr))
                  (char? (cadr expr))))
         acc
         (let ((na (+ acc 1)))
           (if (> na max-budget) #f na))))
    ((eq? (car expr) 'if)
     (let ((c1 (cp0-expr-cost-acc (cadr expr) (+ acc 1) max-budget)))
       (if (not c1)
           #f
           (let ((c2 (cp0-expr-cost-acc (caddr expr) c1 max-budget)))
             (if (not c2)
                 #f
                 (if (null? (cdddr expr))
                     c2
                     (cp0-expr-cost-acc (cadddr expr) c2 max-budget)))))))
    ((eq? (car expr) 'begin)
     (let loop ((es (cdr expr)) (cur acc))
       (cond
         ((not cur) #f)
         ((null? es) cur)
         (else (loop (cdr es) (cp0-expr-cost-acc (car es) cur max-budget))))))
    ((memq (car expr) '(let letrec))
     (if (and (pair? (cdr expr)) (list? (cadr expr)) (pair? (cddr expr)))
         (let* ((bs (cadr expr))
                (base (+ acc (length bs))))
           (if (> base max-budget)
               #f
               (let loop ((rem bs) (cur base))
                 (cond
                   ((not cur) #f)
                   ((null? rem)
                    (cp0-expr-cost-acc (caddr expr) cur max-budget))
                   (else
                    (loop (cdr rem)
                          (cp0-expr-cost-acc (cadar rem) cur max-budget)))))))
         #f))
    ((eq? (car expr) 'lambda)
     (if (and (pair? (cdr expr)) (pair? (cddr expr)))
         (let ((base (+ acc 4)))
           (if (> base max-budget)
               #f
               (cp0-expr-cost-acc (caddr expr) base max-budget)))
         #f))
    (else
     (let loop ((xs expr) (cur (+ acc 1)))
       (cond
         ((not cur) #f)
         ((> cur max-budget) #f)
         ((null? xs) cur)
         ((pair? xs)
          (loop (cdr xs) (cp0-expr-cost-acc (car xs) cur max-budget)))
         (else cur))))))

(define (cp0-expr-cost expr max-budget)
  (cp0-expr-cost-acc expr 0 max-budget))

(define (cp0-make-hash-table)
  (make-vector 512 '()))

(define (cp0-ht-idx sym)
  (modulo (symbol->hash-idx sym) 512))

(define (cp0-ht-ref ht sym)
  (let ((entry (assq sym (vector-ref ht (cp0-ht-idx sym)))))
    (if entry (cdr entry) #f)))

(define (cp0-ht-set! ht sym val)
  (let* ((idx (cp0-ht-idx sym))
         (bucket (vector-ref ht idx))
         (entry (assq sym bucket)))
    (if entry
        (set-cdr! entry val)
        (vector-set! ht idx (cons (cons sym val) bucket)))))

(define (cp0-ht-inc-stat! ht sym call-pos?)
  (let* ((idx (cp0-ht-idx sym))
         (bucket (vector-ref ht idx))
         (entry (assq sym bucket)))
    (if entry
        (let ((pair-val (cdr entry)))
          (set-car! pair-val (+ (car pair-val) 1))
          (if call-pos?
              (set-cdr! pair-val (+ (cdr pair-val) 1))))
        (vector-set! ht idx (cons (cons sym (cons 1 (if call-pos? 1 0))) bucket)))))

(define (cp0-collect-use-stats-walk expr ht call-pos?)
  (cond
    ((symbol? expr)
     (cp0-ht-inc-stat! ht expr call-pos?))
    ((not (pair? expr)) #f)
    ((or (eq? (car expr) 'quote) (eq? (car expr) 'declare)) #f)
    ((and (eq? (car expr) '%program) (pair? (cdr expr)) (pair? (cddr expr)))
     (for-each
       (lambda (d)
         (if (and (pair? d) (eq? (car d) 'define) (pair? (cdr d)) (pair? (cddr d)))
             (cp0-collect-use-stats-walk (caddr d) ht #f)
             (cp0-collect-use-stats-walk d ht #f)))
       (cadr expr))
     (cp0-collect-use-stats-walk (caddr expr) ht #f))
    ((and (eq? (car expr) 'lambda) (pair? (cdr expr)))
     (for-each (lambda (e) (cp0-collect-use-stats-walk e ht #f)) (cddr expr)))
    ((and (memq (car expr) '(let letrec)) (pair? (cdr expr)) (list? (cadr expr)) (pair? (cddr expr)))
     (for-each (lambda (b) (cp0-collect-use-stats-walk (cadr b) ht #f)) (cadr expr))
     (for-each (lambda (e) (cp0-collect-use-stats-walk e ht #f)) (cddr expr)))
    ((and (eq? (car expr) 'set!) (pair? (cdr expr)) (pair? (cddr expr)))
     (cp0-ht-inc-stat! ht (cadr expr) #f)
     (cp0-collect-use-stats-walk (caddr expr) ht #f))
    ((memq (car expr) '(if begin))
     (for-each (lambda (e) (cp0-collect-use-stats-walk e ht #f)) (cdr expr)))
    (else
     (if (symbol? (car expr))
         (cp0-ht-inc-stat! ht (car expr) #t)
         (cp0-collect-use-stats-walk (car expr) ht #f))
     (for-each (lambda (e) (cp0-collect-use-stats-walk e ht #f)) (cdr expr)))))

(define (cp0-collect-use-counts expr)
  (let ((ht (cp0-make-hash-table)))
    (cp0-collect-use-stats-walk expr ht #f)
    ht))

(define (cp0-use-stat-total ht sym)
  (let ((p (cp0-ht-ref ht sym)))
    (if p (car p) 0)))

(define (cp0-use-stat-calls ht sym)
  (let ((p (cp0-ht-ref ht sym)))
    (if p (cdr p) 0)))

(define (cp0-collect-dup-defs-ht defs)
  (let ((seen (cp0-make-hash-table)))
    (let loop ((ds defs) (dups '()))
      (if (null? ds)
          dups
          (let ((d (car ds)))
            (if (and (pair? d) (eq? (car d) 'define) (pair? (cdr d)) (symbol? (cadr d)))
                (let ((name (cadr d)))
                  (if (cp0-ht-ref seen name)
                      (loop (cdr ds) (if (memq name dups) dups (cons name dups)))
                      (begin
                        (cp0-ht-set! seen name #t)
                        (loop (cdr ds) dups))))
                (loop (cdr ds) dups)))))))

(define (cp0-count-var-occurrences var expr)
  (cond
    ((symbol? expr) (if (eq? expr var) 1 0))
    ((not (pair? expr)) 0)
    ((or (eq? (car expr) 'quote) (eq? (car expr) 'declare)) 0)
    (else
     (+ (cp0-count-var-occurrences var (car expr))
        (cp0-count-var-occurrences var (cdr expr))))))

(define (cp0-collect-free-syms expr bound acc)
  (cond
    ((symbol? expr)
     (if (or (memq expr bound) (memq expr acc))
         acc
         (cons expr acc)))
    ((not (pair? expr)) acc)
    ((or (eq? (car expr) 'quote) (eq? (car expr) 'declare)) acc)
    ((and (eq? (car expr) 'lambda) (pair? (cdr expr)))
     (let ((nb (append (cp0-lambda-formal-syms (cadr expr)) bound)))
       (let loop ((es (cddr expr)) (cur acc))
         (if (null? es)
             cur
             (loop (cdr es) (cp0-collect-free-syms (car es) nb cur))))))
    ((and (eq? (car expr) 'let) (pair? (cdr expr)) (list? (cadr expr)))
     (let* ((bs (cadr expr))
            (cur1 (let loop ((xs bs) (cur acc))
                    (if (null? xs)
                        cur
                        (loop (cdr xs) (cp0-collect-free-syms (cadar xs) bound cur)))))
            (nb (append (map car* bs) bound)))
       (let loop ((es (cddr expr)) (cur cur1))
         (if (null? es)
             cur
             (loop (cdr es) (cp0-collect-free-syms (car es) nb cur))))))
    ((and (eq? (car expr) 'letrec) (pair? (cdr expr)) (list? (cadr expr)))
     (let* ((bs (cadr expr))
            (nb (append (map car* bs) bound))
            (cur1 (let loop ((xs bs) (cur acc))
                    (if (null? xs)
                        cur
                        (loop (cdr xs) (cp0-collect-free-syms (cadar xs) nb cur))))))
       (let loop ((es (cddr expr)) (cur cur1))
         (if (null? es)
             cur
             (loop (cdr es) (cp0-collect-free-syms (car es) nb cur))))))
    (else
     (let loop ((xs expr) (cur acc))
       (cond
         ((null? xs) cur)
         ((pair? xs)
          (loop (cdr xs) (cp0-collect-free-syms (car xs) bound cur)))
         (else
          (cp0-collect-free-syms xs bound cur)))))))

(define (cp0-fresh-inl-sym orig)
  (unique-symbol "__inl_v_"))

(define (cp0-alpha-rename-expr expr env)
  (cond
    ((symbol? expr)
     (let ((e (assq expr env)))
       (if e (cdr e) expr)))
    ((not (pair? expr)) expr)
    ((or (eq? (car expr) 'quote) (eq? (car expr) 'declare)) expr)
    ((and (eq? (car expr) 'lambda) (pair? (cdr expr)))
     (let* ((formals (cadr expr))
            (bodies (cddr expr))
            (ext-cell (cons env '()))
            (new-formals
             (let walk-f ((f formals))
               (cond
                 ((null? f) '())
                 ((symbol? f)
                  (let ((nf (cp0-fresh-inl-sym f)))
                    (set-car! ext-cell (cons (cons f nf) (car ext-cell)))
                    nf))
                 ((pair? f)
                  (let* ((p (car f))
                         (np (if (symbol? p) (cp0-fresh-inl-sym p) p)))
                    (if (symbol? p)
                        (set-car! ext-cell (cons (cons p np) (car ext-cell))))
                    (cons np (walk-f (cdr f)))))
                 (else f))))
            (nenv (car ext-cell))
            (new-bodies (map (lambda (e) (cp0-alpha-rename-expr e nenv)) bodies)))
       (cons 'lambda (cons new-formals new-bodies))))
    ((and (eq? (car expr) 'let) (pair? (cdr expr)) (list? (cadr expr)))
     (let* ((bindings (cadr expr))
            (bodies (cddr expr))
            (renamed-rhs (map (lambda (b) (cp0-alpha-rename-expr (cadr b) env)) bindings))
            (new-pairs (map (lambda (b) (cons (car b) (cp0-fresh-inl-sym (car b)))) bindings))
            (nenv (append new-pairs env))
            (new-bs (let bzip ((ps new-pairs) (rs renamed-rhs) (acc '()))
                      (if (null? ps)
                          (reverse acc)
                          (bzip (cdr ps) (cdr rs)
                                (cons (list (cdar ps) (car rs)) acc)))))
            (new-bodies (map (lambda (e) (cp0-alpha-rename-expr e nenv)) bodies)))
       (cons 'let (cons new-bs new-bodies))))
    ((and (eq? (car expr) 'letrec) (pair? (cdr expr)) (list? (cadr expr)))
     (let* ((bindings (cadr expr))
            (bodies (cddr expr))
            (new-pairs (map (lambda (b) (cons (car b) (cp0-fresh-inl-sym (car b)))) bindings))
            (nenv (append new-pairs env))
            (new-bs (let bzip ((ps new-pairs) (bs bindings) (acc '()))
                      (if (null? ps)
                          (reverse acc)
                          (bzip (cdr ps) (cdr bs)
                                (cons (list (cdar ps) (cp0-alpha-rename-expr (cadar bs) nenv)) acc)))))
            (new-bodies (map (lambda (e) (cp0-alpha-rename-expr e nenv)) bodies)))
       (cons 'letrec (cons new-bs new-bodies))))
    ((and (eq? (car expr) 'set!) (pair? (cdr expr)) (pair? (cddr expr)))
     (let* ((v (cadr expr))
            (e (assq v env))
            (nv (if e (cdr e) v)))
       (list 'set! nv (cp0-alpha-rename-expr (caddr expr) env))))
    (else
     (cons (cp0-alpha-rename-expr (car expr) env)
           (cp0-alpha-rename-expr (cdr expr) env)))))

(define (cp0-subst-expr expr subst)
  (if (null? subst)
      expr
      (cond
        ((symbol? expr)
         (let ((e (assq expr subst)))
           (if e (cdr e) expr)))
        ((not (pair? expr)) expr)
        ((or (eq? (car expr) 'quote) (eq? (car expr) 'declare)) expr)
        (else
         (cons (cp0-subst-expr (car expr) subst)
               (cp0-subst-expr (cdr expr) subst))))))

(define (cp0-expand-beta-call params body args)
  (if (or (not (cp0-proper-formal-list? params))
          (not (= (length params) (length args)))
          (cp0-has-unsafe-inline-op? body))
      #f
      (let* ((param-map (map (lambda (p) (cons p (cp0-fresh-inl-sym p))) params))
             (renamed-body (cp0-alpha-rename-expr body param-map))
             (atomic-all? (cp0-all-atomic-exprs? args)))
        (let loop ((pm param-map) (as args) (subst '()) (bindings '()))
          (if (null? pm)
              (let ((body-sub (cp0-subst-expr renamed-body subst)))
                (if (null? bindings)
                    body-sub
                    (list 'let (reverse bindings) body-sub)))
              (let ((fp (cdar pm))
                    (arg (car as)))
                (cond
                  ((const? arg)
                   (loop (cdr pm) (cdr as) (cons (cons fp arg) subst) bindings))
                  ((and atomic-all?
                        (symbol? arg)
                        (<= (cp0-count-var-occurrences fp renamed-body) 1))
                   (loop (cdr pm) (cdr as) (cons (cons fp arg) subst) bindings))
                  (else
                   (loop (cdr pm) (cdr as) subst (cons (list fp arg) bindings))))))))))

(define (cp0-beta-reduce-walk expr)
  (cond
    ((not (pair? expr)) expr)
    ((or (eq? (car expr) 'quote) (eq? (car expr) 'declare)) expr)
    ((and (eq? (car expr) 'lambda) (pair? (cdr expr)))
     (let* ((formals (cadr expr))
            (bodies (cddr expr))
            (nbodies (cp0-map-preserve-eq cp0-beta-reduce-walk bodies)))
       (if (eq? nbodies bodies)
           expr
           (cons 'lambda (cons formals nbodies)))))
    ((and (memq (car expr) '(let letrec)) (pair? (cdr expr)) (list? (cadr expr)))
     (let* ((tag (car expr))
            (bs (cadr expr))
            (bodies (cddr expr))
            (nbs (cp0-map-preserve-eq
                   (lambda (b)
                     (let ((nv (cp0-beta-reduce-walk (cadr b))))
                       (if (eq? nv (cadr b)) b (list (car b) nv))))
                   bs))
            (nbodies (cp0-map-preserve-eq cp0-beta-reduce-walk bodies)))
       (if (and (eq? nbs bs) (eq? nbodies bodies))
           expr
           (cons tag (cons nbs nbodies)))))
    ((and (eq? (car expr) 'define) (pair? (cdr expr)) (pair? (cddr expr)))
     (let ((nv (cp0-beta-reduce-walk (caddr expr))))
       (if (eq? nv (caddr expr))
           expr
           (list 'define (cadr expr) nv))))
    ((and (eq? (car expr) '%program) (pair? (cdr expr)) (pair? (cddr expr)))
     (let* ((defs (cadr expr))
            (main (caddr expr))
            (ndefs (cp0-map-preserve-eq cp0-beta-reduce-walk defs))
            (nmain (cp0-beta-reduce-walk main)))
       (if (and (eq? ndefs defs) (eq? nmain main))
           expr
           (list '%program ndefs nmain))))
    (else
     (let* ((nop (cp0-beta-reduce-walk (car expr)))
            (nargs (cp0-map-preserve-eq cp0-beta-reduce-walk (cdr expr))))
       (if (and (pair? nop)
                (eq? (car nop) 'lambda)
                (pair? (cdr nop))
                (cp0-proper-formal-list? (cadr nop))
                (pair? (cddr nop))
                (null? (cdddr nop)))
           (let ((reduced (cp0-expand-beta-call (cadr nop) (caddr nop) nargs)))
             (if reduced
                 (cp0-beta-reduce-walk reduced)
                 (if (and (eq? nop (car expr)) (eq? nargs (cdr expr)))
                     expr
                     (cons nop nargs))))
           (if (and (eq? nop (car expr)) (eq? nargs (cdr expr)))
               expr
               (cons nop nargs)))))))

(define (cp0-map-preserve-eq fn lst)
  (let loop ((rem lst) (rev '()) (changed? #f))
    (if (null? rem)
        (if changed? (reverse rev) lst)
        (let* ((item (car rem))
               (nitem (fn item)))
          (loop (cdr rem) (cons nitem rev) (or changed? (not (eq? nitem item))))))))

(define (cp0-beta-reduce form)
  (cp0-beta-reduce-walk form))

(define (cp0-strip-body-declares raw-body)
  (let strip ((es raw-body))
    (if (and (pair? es) (cp0-declare-form? (car es)))
        (strip (cdr es))
        es)))

(define (cp0-self-tail-only-loop? fn-name params expr)
  (let ((body-expr (if (and (pair? expr) (null? (cdr expr))) (car expr) expr)))
    (and (occurs-in? fn-name expr)
         (let loop-check ((e expr) (tail? #t))
           (cond
             ((symbol? e) (not (eq? e fn-name)))
             ((not (pair? e)) #t)
             ((or (eq? (car e) 'quote) (eq? (car e) 'declare)) #t)
             ((eq? (car e) 'if)
              (and (loop-check (cadr e) #f)
                   (loop-check (caddr e) tail?)
                   (if (null? (cdddr e)) #t (loop-check (cadddr e) tail?))))
             ((eq? (car e) 'begin)
              (let bl ((es (cdr e)))
                (cond
                  ((null? es) #t)
                  ((null? (cdr es)) (loop-check (car es) tail?))
                  (else (and (loop-check (car es) #f) (bl (cdr es)))))))
             ((eq? (car e) 'let)
              (and (let bl ((bs (cadr e)))
                     (or (null? bs)
                         (and (loop-check (cadar bs) #f) (bl (cdr bs)))))
                   (if (memq fn-name (map car* (cadr e)))
                       #t
                       (loop-check (caddr e) tail?))))
             ((eq? (car e) 'lambda)
              (if (memq fn-name (cp0-lambda-formal-syms (cadr e)))
                  #t
                  (not (occurs-in? fn-name (cddr e)))))
             ((eq? (car e) fn-name)
              (and tail?
                   (let al ((as (cdr e)))
                     (or (null? as)
                         (and (loop-check (car as) #f) (al (cdr as)))))))
             (else
              (and (loop-check (car e) #f)
                   (let al ((as (cdr e)))
                     (or (null? as)
                         (and (loop-check (car as) #f) (al (cdr as))))))))))))

(define (cp0-general-inline-candidate name rhs mutated-vars dup-defs use-table local-scope?)
  (and (symbol? name)
       (not (cp0-asm-or-runtime-stub-name? name))
       (not (memq name mutated-vars))
       (not (memq name dup-defs))
       (pair? rhs)
       (eq? (car rhs) 'lambda)
       (pair? (cdr rhs))
       (cp0-proper-formal-list? (cadr rhs))
       (pair? (cddr rhs))
       (let* ((params (cadr rhs))
              (clean-list (cp0-strip-body-declares (cddr rhs)))
              (single-body (if (and (pair? clean-list) (null? (cdr clean-list)))
                               (cp0-unwrap-accessor-body (car clean-list))
                               #f)))
         (and single-body
              ;; Avoid inlining bare constant/identity placeholder stubs at top-level
              (or local-scope? (pair? single-body))
              (not (cp0-has-unsafe-inline-op? single-body))
              (let ((cost (cp0-expr-cost single-body *cp0-inline-single-use-max-cost*)))
                (and cost
                     (let* ((self-rec? (occurs-in? name single-body))
                            (u-total (cp0-use-stat-total use-table name))
                            (u-calls (cp0-use-stat-calls use-table name))
                            (frees (cp0-collect-free-syms single-body
                                                         (if self-rec? (cons name params) params)
                                                         '())))
                       (cond
                         (self-rec?
                          (and (<= cost *cp0-inline-unroll-max-cost*)
                               (not (and local-scope? (cp0-self-tail-only-loop? name params single-body)))
                               (list name params single-body frees 'recursive-1step cost)))
                         ((or (<= cost *cp0-inline-forced-max-cost*)
                              (and (= u-total 1) (= u-calls 1)
                                   (<= cost *cp0-inline-single-use-max-cost*))
                              (and (= u-calls 1) (not local-scope?)
                                   (<= cost *cp0-inline-single-use-max-cost*))
                              (and (>= u-calls 1)
                                   (<= u-calls 4)
                                   (<= cost *cp0-inline-max-cost*)
                                   (<= (* (- u-calls 1) cost) *cp0-inline-max-total-growth*)))
                          (list name params single-body frees 'normal cost))
                         (else #f)))))))))

(define (cp0-harvest-general-top-env defs mutated-vars dup-defs use-table)
  (let ((ht (cp0-make-hash-table)))
    (for-each
      (lambda (d)
        (if (and (pair? d) (eq? (car d) 'define) (pair? (cdr d)) (pair? (cddr d)) (symbol? (cadr d)))
            (let ((info (cp0-general-inline-candidate (cadr d) (caddr d) mutated-vars dup-defs use-table #f)))
              (if info
                  (cp0-ht-set! ht (cadr d) info)))))
      defs)
    ht))

(define (cp0-has-any-const-arg? args)
  (let loop ((as args))
    (and (pair? as)
         (or (const? (car as))
             (loop (cdr as))))))

(define (cp0-try-expand-general-entry entry args shadowed expanding-stack)
  (let ((name (car entry))
        (params (cadr entry))
        (body (caddr entry))
        (frees (cadddr entry))
        (mode (car (cddddr entry))))
    (cond
      ((memq name expanding-stack) #f)
      ((cp0-any-memq? frees shadowed) #f)
      ((eq? mode 'normal)
       (cp0-expand-beta-call params body args))
      ((and (eq? mode 'recursive-1step)
            (cp0-has-any-const-arg? args))
       (let ((trial (cp0-expand-beta-call params body args)))
         (if trial
             (let* ((simplified (cp0-opt trial))
                    (rec-count (cp0-count-var-occurrences name simplified)))
               (cond
                 ((= rec-count 0) simplified)
                 ((and (= rec-count 1) (cp0-all-const-args? args)) simplified)
                 (else #f)))
             #f)))
      (else #f))))

(define (cp0-general-lookup name local-env prog-ht shadowed)
  (and (symbol? name)
       (or (let ((loc (assq name local-env)))
             (and loc (cdr loc)))
           (and (not (memq name shadowed))
                prog-ht
                (cp0-ht-ref prog-ht name)))))

(define (cp0-general-inline-walk-list es local-env prog-ht shadowed use-table expanding)
  (cp0-map-preserve-eq
    (lambda (e) (cp0-general-inline-walk e local-env prog-ht shadowed use-table expanding))
    es))

(define (cp0-general-inline-walk expr local-env prog-ht shadowed use-table expanding)
  (cond
    ((not (pair? expr)) expr)
    ((const? expr) expr)
    (else
     (let ((head (car expr)))
       (cond
         ((or (eq? head 'quote) (eq? head 'declare)) expr)
         ((and (eq? head '%program) (pair? (cdr expr)) (pair? (cddr expr)))
          (let* ((defs (cadr expr))
                 (main-body (caddr expr))
                 (mutated (cp0-collect-set!-vars main-body (cp0-collect-set!-vars defs '())))
                 (dups (cp0-collect-dup-defs-ht defs))
                 (cur-use-table (cp0-collect-use-counts expr))
                 (cur-prog-ht (cp0-harvest-general-top-env defs mutated dups cur-use-table))
                 (new-defs
                  (cp0-map-preserve-eq
                    (lambda (d)
                      (if (and (pair? d) (eq? (car d) 'define) (pair? (cdr d)) (pair? (cddr d)))
                          (let* ((name (cadr d))
                                 (rhs (caddr d))
                                 ;; Conservative stack-root GC boundaries (%get-rsp) rely on callee stack frame deallocation
                                 (rhs-prog-ht (if (occurs-in? '%get-rsp rhs) #f cur-prog-ht))
                                 (rhs-loc-env (if (occurs-in? '%get-rsp rhs) '() local-env))
                                 (nrhs (cp0-general-inline-walk rhs rhs-loc-env rhs-prog-ht shadowed cur-use-table (list name))))
                            (if (eq? nrhs rhs) d (list 'define name nrhs)))
                          (cp0-general-inline-walk d local-env cur-prog-ht shadowed cur-use-table expanding)))
                    defs))
                 (new-main (cp0-general-inline-walk main-body local-env cur-prog-ht shadowed cur-use-table expanding)))
            (if (and (eq? new-defs defs) (eq? new-main main-body))
                expr
                (list '%program new-defs new-main))))
         ((and (eq? head 'lambda) (pair? (cdr expr)))
          (let* ((formals (cadr expr))
                 (bodies (cddr expr))
                 (f-syms (cp0-lambda-formal-syms formals))
                 (inner-loc-env (cp0-filter-shadowed-env local-env f-syms))
                 (inner-shadow (append f-syms shadowed))
                 (new-bodies (cp0-general-inline-walk-list bodies inner-loc-env prog-ht inner-shadow use-table expanding)))
            (if (eq? new-bodies bodies)
                expr
                (cons 'lambda (cons formals new-bodies)))))
         ((and (eq? head 'let) (pair? (cdr expr)) (list? (cadr expr)) (pair? (cddr expr)))
          (let* ((bindings (cadr expr))
                 (bodies (cddr expr))
                 (new-bindings
                  (cp0-map-preserve-eq
                    (lambda (b)
                      (let ((nrhs (cp0-general-inline-walk (cadr b) local-env prog-ht shadowed use-table expanding)))
                        (if (eq? nrhs (cadr b)) b (list (car b) nrhs))))
                    bindings))
                 (bound-vars (map car* bindings))
                 (inner-shadow (append bound-vars shadowed))
                 (mutated (cp0-collect-set!-vars bodies '()))
                 (loc-use-table (if use-table use-table (cp0-collect-use-counts expr)))
                 (new-loc-entries
                  (let loop ((bs new-bindings) (acc '()))
                    (if (null? bs)
                        acc
                        (let* ((b (car bs))
                               (info (cp0-general-inline-candidate (car b) (cadr b) mutated '() loc-use-table #t)))
                          (if info
                              (loop (cdr bs) (cons (cons (car b) info) acc))
                              (loop (cdr bs) acc))))))
                 (inner-loc-env (append new-loc-entries (cp0-filter-shadowed-env local-env bound-vars)))
                 (new-bodies (cp0-general-inline-walk-list bodies inner-loc-env prog-ht inner-shadow loc-use-table expanding)))
            (if (and (eq? new-bindings bindings) (eq? new-bodies bodies))
                expr
                (cons 'let (cons new-bindings new-bodies)))))
         ((and (eq? head 'letrec) (pair? (cdr expr)) (list? (cadr expr)) (pair? (cddr expr)))
          (let* ((bindings (cadr expr))
                 (bodies (cddr expr))
                 (bound-vars (map car* bindings))
                 (inner-shadow (append bound-vars shadowed))
                 (mutated (cp0-collect-set!-vars bodies (cp0-collect-set!-vars bindings '())))
                 (loc-use-table (if use-table use-table (cp0-collect-use-counts expr)))
                 (new-loc-entries
                  (let loop ((bs bindings) (acc '()))
                    (if (null? bs)
                        acc
                        (let* ((b (car bs))
                               (info (cp0-general-inline-candidate (car b) (cadr b) mutated '() loc-use-table #t)))
                          (if info
                              (loop (cdr bs) (cons (cons (car b) info) acc))
                              (loop (cdr bs) acc))))))
                 (inner-loc-env (append new-loc-entries (cp0-filter-shadowed-env local-env bound-vars)))
                 (new-bindings
                  (cp0-map-preserve-eq
                    (lambda (b)
                      (let* ((bname (car b))
                             (nrhs (cp0-general-inline-walk (cadr b) inner-loc-env prog-ht inner-shadow loc-use-table (cons bname expanding))))
                        (if (eq? nrhs (cadr b)) b (list bname nrhs))))
                    bindings))
                 (new-bodies (cp0-general-inline-walk-list bodies inner-loc-env prog-ht inner-shadow loc-use-table expanding)))
            (if (and (eq? new-bindings bindings) (eq? new-bodies bodies))
                expr
                (cons 'letrec (cons new-bindings new-bodies)))))
         ((and (eq? head 'set!) (pair? (cdr expr)) (pair? (cddr expr)))
          (let ((nval (cp0-general-inline-walk (caddr expr) local-env prog-ht shadowed use-table expanding)))
            (if (eq? nval (caddr expr))
                expr
                (list 'set! (cadr expr) nval))))
         ((memq head '(if begin))
          (let ((new-rest (cp0-general-inline-walk-list (cdr expr) local-env prog-ht shadowed use-table expanding)))
            (if (eq? new-rest (cdr expr))
                expr
                (cons head new-rest))))
         (else
          (let* ((new-op (if (symbol? head) head (cp0-general-inline-walk head local-env prog-ht shadowed use-table expanding)))
                 (new-args (cp0-general-inline-walk-list (cdr expr) local-env prog-ht shadowed use-table expanding)))
            (cond
              ;; Direct lambda beta-reduction: ((lambda (p ...) body) arg ...)
              ((and (pair? new-op)
                    (eq? (car new-op) 'lambda)
                    (pair? (cdr new-op))
                    (cp0-proper-formal-list? (cadr new-op))
                    (pair? (cddr new-op))
                    (null? (cdddr new-op)))
               (let ((reduced (cp0-expand-beta-call (cadr new-op) (caddr new-op) new-args)))
                 (if reduced
                     (cp0-general-inline-walk reduced local-env prog-ht shadowed use-table expanding)
                     (if (and (eq? new-op head) (eq? new-args (cdr expr)))
                         expr
                         (cons new-op new-args)))))
              ;; Named procedure inlining / 1-step constant recursion unroll
              ((symbol? head)
               (let* ((entry (cp0-general-lookup head local-env prog-ht shadowed))
                      (expanded (and entry (cp0-try-expand-general-entry entry new-args shadowed expanding))))
                 (cond
                   (expanded
                    (cp0-general-inline-walk expanded local-env prog-ht shadowed use-table (cons head expanding)))
                   ((and (eq? new-op head) (eq? new-args (cdr expr))) expr)
                   (else (cons new-op new-args)))))
              ((and (eq? new-op head) (eq? new-args (cdr expr))) expr)
              (else (cons new-op new-args))))))))))

(define (frontend-inline-pass form)
  (if (or (not (pair? form)) (const? form))
      form
      (let ((use-table (if (eq? (car form) '%program) #f (cp0-collect-use-counts form))))
        (cp0-general-inline-walk form '() #f '() use-table '()))))
