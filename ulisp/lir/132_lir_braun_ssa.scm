;;; =======================================================================
;;; ULisp Compiler Pass 132: Braun et al. (2013) SSA & Block Arguments Engine
;;; =======================================================================

;;; Conforms to DSN-33 Section 8.1, DSN-33-02 Section 6.1 & Issue #827
;;; =======================================================================

(define (make-braun-cfg)
  (list (cons 'blocks '())            ; (label . (insts ...))
        (cons 'order '())             ; (lbl1 lbl2 ...)
        (cons 'preds '())             ; (label . (pred1 pred2 ...))
        (cons 'succs '())             ; (label . (succ1 succ2 ...))
        (cons 'sealed '())            ; (lbl1 lbl2 ...)
        (cons 'params '())            ; (label . (p1 p2 ...))
        (cons 'defs '())              ; ((var . lbl) . val)
        (cons 'incomplete '())        ; (label . ((param . var) ...))
        (cons 'incoming '())          ; ((param . pred) . val)
        (cons 'replacements '())      ; (param . canonical-val)
        (cons 'terminators '())       ; (label . terminator-inst)
        (cons 'rep-types '())         ; (val/param . rep-type)
        (cons 'phi-users '())         ; (val . ((user-param . user-block-lbl) ...))
        (cons 'param-vars '())        ; (param . var)
        (cons 'current-block #f)))

;;; -----------------------------------------------------------------------
;;; Representation Type Lattice (Issue #618: bot <= raw-i64 <= top)
;;; -----------------------------------------------------------------------
(define (braun-rep-bot) 'bot)
(define (braun-rep-raw-i64) 'raw-i64)
(define (braun-rep-tagged-fixnum) 'tagged-fixnum)
(define (braun-rep-top) 'top)

(define (braun-rep-lub r1 r2)
  (cond
    ((eq? r1 'bot) r2)
    ((eq? r2 'bot) r1)
    ((eq? r1 r2) r1)
    (else 'top)))

(define (braun-set-rep-type! cfg val rep)
  (let* ((reps (braun-cfg-ref cfg 'rep-types))
         (entry (assoc val reps)))
    (if entry
        (set-cdr! entry rep)
        (braun-cfg-set! cfg 'rep-types (cons (cons val rep) reps)))))

(define (braun-get-rep-type cfg val)
  (let* ((reps (braun-cfg-ref cfg 'rep-types))
         (entry (assoc val reps)))
    (if entry (cdr entry) 'bot)))

(define (braun-infer-block-params-rep! cfg)
  (let ((order (braun-cfg-ref cfg 'order)))
    (for-each
     (lambda (block-lbl)
       (let ((params (braun-get-params cfg block-lbl))
             (preds (braun-get-preds cfg block-lbl)))
         (for-each
          (lambda (param)
            (let ((inferred-rep
                   (let loop ((ps preds) (acc 'bot))
                     (if (null? ps) acc
                         (let* ((pred (car ps))
                                (inc (braun-resolve-val cfg (braun-get-incoming cfg param pred)))
                                (inc-rep (braun-get-rep-type cfg inc)))
                           (loop (cdr ps) (braun-rep-lub acc inc-rep)))))))
              (if (not (eq? inferred-rep 'bot))
                  (braun-set-rep-type! cfg param inferred-rep))))
          params)))
     order)
    cfg))

(define (braun-get-raw-params cfg)
  (let* ((reps (braun-cfg-ref cfg 'rep-types)))
    (let loop ((rs reps) (acc '()))
      (if (null? rs) (reverse acc)
          (if (eq? (cdar rs) 'raw-i64)
              (loop (cdr rs) (cons (caar rs) acc))
              (loop (cdr rs) acc))))))

(define (braun-cfg-ref cfg key)
  (let ((entry (assq key cfg)))
    (if entry (cdr entry) '())))

(define (braun-cfg-set! cfg key val)
  (let ((entry (assq key cfg)))
    (if entry
        (set-cdr! entry val)
        (error "Unknown Braun CFG key:" key))))

(define (braun-new-block! cfg label)
  (let ((order (braun-cfg-ref cfg 'order))
        (blocks (braun-cfg-ref cfg 'blocks))
        (preds (braun-cfg-ref cfg 'preds))
        (succs (braun-cfg-ref cfg 'succs))
        (params (braun-cfg-ref cfg 'params))
        (incomplete (braun-cfg-ref cfg 'incomplete))
        (terms (braun-cfg-ref cfg 'terminators)))
    (braun-cfg-set! cfg 'order (append order (list label)))
    (braun-cfg-set! cfg 'blocks (cons (cons label '()) blocks))
    (braun-cfg-set! cfg 'preds (cons (cons label '()) preds))
    (braun-cfg-set! cfg 'succs (cons (cons label '()) succs))
    (braun-cfg-set! cfg 'params (cons (cons label '()) params))
    (braun-cfg-set! cfg 'incomplete (cons (cons label '()) incomplete))
    (braun-cfg-set! cfg 'terminators (cons (cons label #f) terms))
    (braun-cfg-set! cfg 'current-block label)
    label))

(define (braun-update-sealed-block-edge! cfg from-lbl to-lbl)
  (let ((params (braun-get-params cfg to-lbl)))
    (for-each
     (lambda (param)
       (let ((var (braun-get-param-var cfg param)))
         (if var
             (let ((val (braun-read-variable cfg var from-lbl)))
               (braun-set-incoming! cfg param from-lbl val)
               (braun-try-remove-trivial! cfg to-lbl param '())))))
     params)))

(define (braun-add-edge! cfg from-lbl to-lbl)
  (let* ((preds (braun-cfg-ref cfg 'preds))
         (p-entry (assq to-lbl preds))
         (succs (braun-cfg-ref cfg 'succs))
         (s-entry (assq from-lbl succs)))
    ;; Update preds
    (if p-entry
        (if (not (memq from-lbl (cdr p-entry)))
            (set-cdr! p-entry (append (cdr p-entry) (list from-lbl))))
        (braun-cfg-set! cfg 'preds (cons (list to-lbl from-lbl) preds)))
    ;; Update succs
    (if s-entry
        (if (not (memq to-lbl (cdr s-entry)))
            (set-cdr! s-entry (append (cdr s-entry) (list to-lbl))))
        (braun-cfg-set! cfg 'succs (cons (list from-lbl to-lbl) succs)))
    ;; If to-lbl is already sealed, dynamically update its block arguments
    (if (memq to-lbl (braun-cfg-ref cfg 'sealed))
        (braun-update-sealed-block-edge! cfg from-lbl to-lbl))))

(define (braun-get-preds cfg block-lbl)
  (let ((entry (assq block-lbl (braun-cfg-ref cfg 'preds))))
    (if entry (cdr entry) '())))

(define (braun-get-succs cfg block-lbl)
  (let ((entry (assq block-lbl (braun-cfg-ref cfg 'succs))))
    (if entry (cdr entry) '())))

(define (braun-get-params cfg block-lbl)
  (let ((entry (assq block-lbl (braun-cfg-ref cfg 'params))))
    (if entry (cdr entry) '())))

(define (braun-add-param! cfg block-lbl param)
  (let* ((params (braun-cfg-ref cfg 'params))
         (entry (assq block-lbl params)))
    (if entry
        (if (not (memq param (cdr entry)))
            (set-cdr! entry (append (cdr entry) (list param))))
        (braun-cfg-set! cfg 'params (cons (list block-lbl param) params)))))

(define (braun-set-param-var! cfg param var)
  (let* ((pvars (braun-cfg-ref cfg 'param-vars))
         (entry (assq param pvars)))
    (if entry
        (set-cdr! entry var)
        (braun-cfg-set! cfg 'param-vars (cons (cons param var) pvars)))))

(define (braun-get-param-var cfg param)
  (let ((entry (assq param (braun-cfg-ref cfg 'param-vars))))
    (if entry (cdr entry) #f)))

(define (braun-write-variable! cfg var block-lbl val)
  (let* ((defs (braun-cfg-ref cfg 'defs))
         (key (cons var block-lbl))
         (entry (assoc key defs)))
    (if entry
        (set-cdr! entry val)
        (braun-cfg-set! cfg 'defs (cons (cons key val) defs)))))

(define (braun-resolve-val cfg val)
  (let loop ((v val) (visited '()))
    (if (or (not (symbol? v)) (memq v visited))
        v
        (let* ((reps (braun-cfg-ref cfg 'replacements))
               (entry (assq v reps)))
          (if entry
              (loop (cdr entry) (cons v visited))
              v)))))

(define (braun-member? x lst)
  (let loop ((xs lst))
    (cond
      ((null? xs) #f)
      ((equal? (car xs) x) #t)
      (else (loop (cdr xs))))))

(define (braun-add-phi-user! cfg val param block-lbl)
  (if (symbol? val)
      (let* ((users-map (braun-cfg-ref cfg 'phi-users))
             (entry (assq val users-map))
             (item (cons param block-lbl)))
        (if entry
            (if (not (braun-member? item (cdr entry)))
                (set-cdr! entry (cons item (cdr entry))))
            (braun-cfg-set! cfg 'phi-users (cons (list val item) users-map))))))

(define (braun-get-phi-users cfg val)
  (let ((entry (assq val (braun-cfg-ref cfg 'phi-users))))
    (if entry (cdr entry) '())))

(define (braun-find-block-of-param cfg param)
  (let loop ((blocks (braun-cfg-ref cfg 'params)))
    (if (null? blocks) #f
        (if (memq param (cdar blocks))
            (caar blocks)
            (loop (cdr blocks))))))

(define (braun-set-incoming! cfg param pred val)
  (let* ((inc (braun-cfg-ref cfg 'incoming))
         (key (cons param pred))
         (entry (assoc key inc)))
    (if entry
        (set-cdr! entry val)
        (braun-cfg-set! cfg 'incoming (cons (cons key val) inc))))
  (let ((b-lbl (braun-find-block-of-param cfg param)))
    (if b-lbl (braun-add-phi-user! cfg val param b-lbl))))

(define (braun-get-incoming cfg param pred)
  (let* ((inc (braun-cfg-ref cfg 'incoming))
         (key (cons param pred))
         (entry (assoc key inc)))
    (if entry (cdr entry) #f)))

;;; Braun et al. (2013) Section 3.2: Recursive Trivial Phi Elimination
(define (braun-try-remove-trivial! cfg block-lbl param visited)
  (if (memq param visited)
        param ;; Cycle detected: break recursion safely (CWE-400 defense)
        (let* ((preds (braun-get-preds cfg block-lbl)))
          (let loop ((ps preds) (same #f) (trivial? #t))
            (if (null? ps)
                (if trivial?
                    (let ((replacement (if same same param)))
                      (if (not (equal? replacement param))
                          (begin
                            ;; 1. Register canonical replacement
                            (let ((reps (braun-cfg-ref cfg 'replacements)))
                              (braun-cfg-set! cfg 'replacements (cons (cons param replacement) reps)))
                            ;; 2. Remove param from block's parameter list
                            (let* ((params (braun-cfg-ref cfg 'params))
                                   (p-entry (assq block-lbl params)))
                              (if p-entry
                                  (set-cdr! p-entry (filter (lambda (p) (not (eq? p param))) (cdr p-entry)))))
                            ;; 3. Braun 2013: Recursively check all users of this phi
                            (let ((users (braun-get-phi-users cfg param))
                                  (new-visited (cons param visited)))
                              (for-each
                               (lambda (u-pair)
                                 (let ((user-param (car u-pair))
                                       (user-block (cdr u-pair)))
                                   (if (and user-block (memq user-param (braun-get-params cfg user-block)))
                                       (braun-try-remove-trivial! cfg user-block user-param new-visited))))
                               users))
                            replacement)
                          param))
                    param)
                (let* ((pred (car ps))
                       (raw-op (braun-get-incoming cfg param pred))
                       (op (if raw-op (braun-resolve-val cfg raw-op) param)))
                  (cond
                    ((or (equal? op param) (equal? op same))
                     ;; Unique value so far or self-reference: ignore
                     (loop (cdr ps) same trivial?))
                    ((eq? same #f)
                     ;; First non-self operand encountered
                     (loop (cdr ps) op trivial?))
                    (else
                     ;; Multiple distinct operands: non-trivial phi!
                     (loop '() same #f))))))))) 

(define (braun-add-arguments! cfg block-lbl param var)
  (let ((preds (braun-get-preds cfg block-lbl)))
    (for-each
     (lambda (pred)
       (let ((val (braun-read-variable cfg var pred)))
         (braun-set-incoming! cfg param pred val)))
     preds)
    (braun-try-remove-trivial! cfg block-lbl param '())))

(define (braun-read-variable-recursive cfg var block-lbl)
  (let* ((sealed (braun-cfg-ref cfg 'sealed))
         (is-sealed? (memq block-lbl sealed)))
    (if (not is-sealed?)
        ;; Incomplete CFG: block not sealed yet
        (let ((param (unique-label-sym (string-append "ba_" (symbol->string var) "_"))))
          (braun-add-param! cfg block-lbl param)
          (braun-set-param-var! cfg param var)
          (let* ((incomp (braun-cfg-ref cfg 'incomplete))
                 (entry (assq block-lbl incomp)))
            (if entry
                (set-cdr! entry (cons (cons param var) (cdr entry)))
                (braun-cfg-set! cfg 'incomplete (cons (list block-lbl (cons param var)) incomp))))
          (braun-write-variable! cfg var block-lbl param)
          param)
        ;; Sealed block
        (let ((preds (braun-get-preds cfg block-lbl)))
          (cond
            ((null? preds)
             var)
            ((and (null? (cdr preds)) (not (eq? (car preds) block-lbl)))
             ;; Single predecessor optimization: no block argument needed!
             (let ((val (braun-read-variable cfg var (car preds))))
               (braun-write-variable! cfg var block-lbl val)
               val))
            (else
             ;; Multiple predecessors: create block argument
             (let ((param (unique-label-sym (string-append "ba_" (symbol->string var) "_"))))
               (braun-add-param! cfg block-lbl param)
               (braun-set-param-var! cfg param var)
               (braun-write-variable! cfg var block-lbl param)
               (let ((resolved (braun-add-arguments! cfg block-lbl param var)))
                 (braun-write-variable! cfg var block-lbl resolved)
                 resolved))))))))

(define (braun-read-variable cfg var block-lbl)
  (let* ((defs (braun-cfg-ref cfg 'defs))
         (key (cons var block-lbl))
         (entry (assoc key defs)))
    (if entry
        (braun-resolve-val cfg (cdr entry))
        (braun-read-variable-recursive cfg var block-lbl))))

(define (braun-seal-block! cfg block-lbl)
  (let ((sealed (braun-cfg-ref cfg 'sealed)))
    (if (not (memq block-lbl sealed))
        (begin
          (braun-cfg-set! cfg 'sealed (cons block-lbl sealed))
          (let* ((incomp-entry (assq block-lbl (braun-cfg-ref cfg 'incomplete)))
                 (incomps (if incomp-entry (cdr incomp-entry) '())))
            (if incomp-entry (set-cdr! incomp-entry '()))
            (for-each
             (lambda (pair)
               (let ((param (car pair))
                     (var (cdr pair)))
                 (braun-add-arguments! cfg block-lbl param var)))
             (reverse incomps)))))))

(define (braun-seal-all-blocks! cfg)
  (let ((order (braun-cfg-ref cfg 'order)))
    (for-each (lambda (b) (braun-seal-block! cfg b)) order)
    cfg))

(define (braun-emit-inst! cfg block-lbl inst)
  (let* ((blocks (braun-cfg-ref cfg 'blocks))
         (entry (assq block-lbl blocks)))
    (if entry
        (set-cdr! entry (append (cdr entry) (list inst)))
        (braun-cfg-set! cfg 'blocks (cons (list block-lbl inst) blocks)))))

(define (braun-get-insts cfg block-lbl)
  (let ((entry (assq block-lbl (braun-cfg-ref cfg 'blocks))))
    (if entry (cdr entry) '())))

(define (braun-set-terminator! cfg block-lbl term)
  (let* ((terms (braun-cfg-ref cfg 'terminators))
         (entry (assq block-lbl terms)))
    (if entry
        (set-cdr! entry term)
        (braun-cfg-set! cfg 'terminators (cons (cons block-lbl term) terms)))))

(define (braun-get-terminator cfg block-lbl)
  (let ((entry (assq block-lbl (braun-cfg-ref cfg 'terminators))))
    (if entry (cdr entry) #f)))

(define (braun-auto-add-terminator-edges! cfg block-lbl term)
  (if (pair? term)
      (case (car term)
        ((%jump %direct-jump)
         (braun-add-edge! cfg block-lbl (cadr term)))
        ((%jump-if)
         (braun-add-edge! cfg block-lbl (caddr term))
         (let ((else-lbl (if (= (length term) 4) (cadddr term) (car (cddddr term)))))
           (braun-add-edge! cfg block-lbl else-lbl)))
        ((%jump-if-false %jump-cond)
         (braun-add-edge! cfg block-lbl (caddr term)))
        ((%jump-if-zero)
         (braun-add-edge! cfg block-lbl (cadr term)))
        ((%switch)
         (let* ((def-lbl (caddr term))
                (cases (cond ((= (length term) 5) (car (cddddr term)))
                             ((pair? (cdddr term)) (cadddr term))
                             (else '()))))
           (braun-add-edge! cfg block-lbl def-lbl)
           (for-each
            (lambda (c)
              (let ((c-lbl (if (pair? (cdr c)) (cadr c) (cdr c))))
                (braun-add-edge! cfg block-lbl c-lbl)))
            cases)))
        (else #f))))

;;; Path Splitting & Join Block Bypass for Braun SSA CFG (Chambers & Ungar 1989)
(define (braun-cfg-path-split! cfg)
  (let ((order (braun-cfg-ref cfg 'order)))
    (for-each
     (lambda (join-lbl)
       (let ((term (braun-get-terminator cfg join-lbl)))
         (if (and term (or (eq? (car term) '%jump-if) (eq? (car term) '%jump-if-false)))
             (let* ((cond-var (cadr term))
                    (then-target (if (eq? (car term) '%jump-if) (caddr term) #f))
                    (else-target (if (eq? (car term) '%jump-if) (cadddr term) (caddr term)))
                    (preds (braun-get-preds cfg join-lbl)))
               (for-each
                (lambda (pred-lbl)
                  (let* ((inc-val (braun-resolve-val cfg (braun-get-incoming cfg cond-var pred-lbl)))
                         (pred-term (braun-get-terminator cfg pred-lbl)))
                    (if (and inc-val pred-term (eq? (car pred-term) '%jump) (eq? (cadr pred-term) join-lbl))
                        ;; Check if incoming condition value is statically truthy or falsy
                        (let ((is-false? (or (eq? inc-val #f) (equal? inc-val 47))))
                          (cond
                            ((and is-false? else-target)
                             ;; Bypass join-lbl directly to else-target from pred-lbl
                             (let ((join-insts (braun-get-insts cfg join-lbl)))
                               (for-each (lambda (inst) (braun-emit-inst! cfg pred-lbl inst)) join-insts)
                               (braun-set-terminator! cfg pred-lbl (list '%jump else-target))
                               (braun-add-edge! cfg pred-lbl else-target)))
                            ((and (not is-false?) then-target)
                             ;; Bypass join-lbl directly to then-target from pred-lbl
                             (let ((join-insts (braun-get-insts cfg join-lbl)))
                               (for-each (lambda (inst) (braun-emit-inst! cfg pred-lbl inst)) join-insts)
                               (braun-set-terminator! cfg pred-lbl (list '%jump then-target))
                               (braun-add-edge! cfg pred-lbl then-target))))))))
                preds)))))
     order)
    cfg))

;;; Converts a Braun CFG into structured Block Arguments LIR
(define (braun-cfg->lir cfg)
  (let ((order (braun-cfg-ref cfg 'order)))
    (map
     (lambda (lbl)
       (let* ((params (braun-get-params cfg lbl))
              (raw-insts (braun-get-insts cfg lbl))
              ;; Resolve any variables in instructions
              (insts
               (map (lambda (inst)
                      (if (and (pair? inst) (eq? (car inst) '%inline-asm))
                          (let resolve-clause ((cs (cdr inst)))
                            (if (null? cs)
                                '()
                                (cons
                                 (let ((el (car cs)))
                                   (cond
                                     ((and (pair? el) (memq (car el) '(:inputs :outputs)))
                                      (list (car el)
                                            (map (lambda (entry)
                                                   (map (lambda (sub) (braun-resolve-val cfg sub)) entry))
                                                 (cadr el))))
                                     (else (braun-resolve-val cfg el))))
                                 (resolve-clause (cdr cs)))))
                          (map (lambda (elem) (braun-resolve-val cfg elem)) inst)))
                    raw-insts))
              (term (braun-get-terminator cfg lbl))
              (term-inst
               (cond
                 ((not term) '())
                 ((eq? (car term) '%jump)
                  (let* ((target (cadr term))
                         (target-params (braun-get-params cfg target))
                         (args (map (lambda (p)
                                      (braun-resolve-val cfg (braun-get-incoming cfg p lbl)))
                                    target-params)))
                    (list (list '%jump target args))))
                 ((eq? (car term) '%direct-jump)
                  (let* ((target (cadr term))
                         (target-params (braun-get-params cfg target))
                         (args (map (lambda (p)
                                      (braun-resolve-val cfg (braun-get-incoming cfg p lbl)))
                                    target-params)))
                    (if (null? args)
                        (list (list '%direct-jump target))
                        (list (list '%jump target args)))))
                 ((eq? (car term) '%jump-if-false)
                  (let* ((cond-var (braun-resolve-val cfg (cadr term)))
                         (else-lbl (caddr term))
                         (else-params (braun-get-params cfg else-lbl))
                         (else-args (map (lambda (p)
                                           (braun-resolve-val cfg (braun-get-incoming cfg p lbl)))
                                         else-params)))
                    (list (list '%jump-if-false cond-var else-lbl else-args))))
                 ((eq? (car term) '%jump-if)
                  (let* ((cond-var (braun-resolve-val cfg (cadr term)))
                         (then-lbl (caddr term))
                         (else-lbl (if (= (length term) 4) (cadddr term) (car (cddddr term))))
                         (then-params (braun-get-params cfg then-lbl))
                         (then-args (map (lambda (p)
                                           (braun-resolve-val cfg (braun-get-incoming cfg p lbl)))
                                         then-params))
                         (else-params (braun-get-params cfg else-lbl))
                         (else-args (map (lambda (p)
                                           (braun-resolve-val cfg (braun-get-incoming cfg p lbl)))
                                         else-params)))
                    (list (list '%jump-if cond-var then-lbl then-args else-lbl else-args))))
                 ((eq? (car term) '%switch)
                  (let* ((cond-var (braun-resolve-val cfg (cadr term)))
                         (def-lbl (caddr term))
                         (cases (cond ((= (length term) 5) (car (cddddr term)))
                                      ((pair? (cdddr term)) (cadddr term))
                                      (else '())))
                         (def-params (braun-get-params cfg def-lbl))
                         (def-args (map (lambda (p)
                                          (braun-resolve-val cfg (braun-get-incoming cfg p lbl)))
                                        def-params))
                         (lowered-cases
                          (map (lambda (c)
                                 (let* ((c-val (car c))
                                        (c-lbl (if (pair? (cdr c)) (cadr c) (cdr c)))
                                        (c-params (braun-get-params cfg c-lbl))
                                        (c-args (map (lambda (p)
                                                       (braun-resolve-val cfg (braun-get-incoming cfg p lbl)))
                                                     c-params)))
                                   (list c-val c-lbl c-args)))
                               cases)))
                    (list (list '%switch cond-var def-lbl def-args lowered-cases))))
                 ((eq? (car term) '%return)
                  (let ((val (if (pair? (cdr term))
                                 (braun-resolve-val cfg (cadr term))
                                 '%rax)))
                    (list (list '%return val))))
                 (else
                  (list (map (lambda (elem) (braun-resolve-val cfg elem)) term)))))
              (block-body (append insts term-inst)))
         (cons '%block (cons lbl (cons params block-body)))))
     order)))

;;; -----------------------------------------------------------------------
;;; Dominator Tree & Dominance Frontiers (Cooper et al. 2001)
;;; -----------------------------------------------------------------------
(define (braun-block-rpo-index order b)
  (let loop ((os order) (idx 0))
    (cond
      ((null? os) 999999)
      ((eq? (car os) b) idx)
      (else (loop (cdr os) (+ idx 1))))))

(define (braun-intersect-doms order idom b1 b2)
  (let loop ((finger1 b1) (finger2 b2))
    (cond
      ((eq? finger1 finger2) finger1)
      ((> (braun-block-rpo-index order finger1) (braun-block-rpo-index order finger2))
       (let ((p1 (assq finger1 idom)))
         (if (and p1 (not (eq? (cdr p1) finger1)))
             (loop (cdr p1) finger2)
             finger2)))
      (else
       (let ((p2 (assq finger2 idom)))
         (if (and p2 (not (eq? (cdr p2) finger2)))
             (loop finger1 (cdr p2))
             finger1))))))

(define (braun-compute-dominators cfg)
  (let* ((order (braun-cfg-ref cfg 'order)))
    (if (null? order) '()
        (let* ((entry (car order))
               (idom (map (lambda (b) (cons b (if (eq? b entry) entry #f))) order)))
          (let outer-loop ((changed? #t))
            (if (not changed?)
                (filter (lambda (entry) (cdr entry)) idom)
                (let inner-loop ((bs (cdr order)) (any-change? #f))
                  (if (null? bs)
                      (outer-loop any-change?)
                      (let* ((b (car bs))
                             (preds (braun-get-preds cfg b))
                             (processed-preds (filter (lambda (p)
                                                        (let ((cell (assq p idom)))
                                                          (and cell (cdr cell))))
                                                      preds)))
                        (if (null? processed-preds)
                            (inner-loop (cdr bs) any-change?)
                            (let* ((new-idom
                                    (let fold-p ((ps (cdr processed-preds))
                                                 (acc (car processed-preds)))
                                      (if (null? ps) acc
                                          (fold-p (cdr ps)
                                                  (braun-intersect-doms order idom (car ps) acc)))))
                                   (cur (assq b idom)))
                              (if (not (eq? (cdr cur) new-idom))
                                  (begin
                                    (set-cdr! cur new-idom)
                                    (inner-loop (cdr bs) #t))
                                  (inner-loop (cdr bs) any-change?)))))))))))))

(define (braun-compute-dominance-frontiers cfg idom-map)
  (let* ((order (braun-cfg-ref cfg 'order))
         (df-map (map (lambda (b) (cons b '())) order)))
    (for-each
     (lambda (b)
       (let ((preds (braun-get-preds cfg b)))
         (if (and (pair? preds) (pair? (cdr preds)))
             (let ((b-idom-entry (assq b idom-map)))
               (if b-idom-entry
                   (let ((b-idom (cdr b-idom-entry)))
                     (for-each
                      (lambda (p)
                        (let runner-loop ((runner p))
                          (if (and (not (eq? runner b-idom))
                                   (assq runner idom-map))
                              (begin
                                (let ((df-entry (assq runner df-map)))
                                  (if (and df-entry (not (memq b (cdr df-entry))))
                                      (set-cdr! df-entry (cons b (cdr df-entry)))))
                                (let ((r-idom-entry (assq runner idom-map)))
                                  (if (and r-idom-entry (not (eq? (cdr r-idom-entry) runner)))
                                      (runner-loop (cdr r-idom-entry))))))))
                      preds)))))))
     order)
    df-map))

;;; -----------------------------------------------------------------------
;;; CFG Verification (Integrity & Invariant Check)
;;; -----------------------------------------------------------------------
(define (braun-verify-cfg cfg)
  (let ((order (braun-cfg-ref cfg 'order))
        (sealed (braun-cfg-ref cfg 'sealed))
        (incomplete (braun-cfg-ref cfg 'incomplete)))
    ;; 1. All blocks must be sealed
    (for-each
     (lambda (b)
       (if (not (memq b sealed))
           (error "Braun CFG verification failure: block not sealed:" b)))
     order)
    ;; 2. Incomplete entries must be empty
    (for-each
     (lambda (inc-pair)
       (if (and (pair? (cdr inc-pair)) (not (null? (cdr inc-pair))))
           (error "Braun CFG verification failure: unresolved incomplete variables in block:" (car inc-pair))))
     incomplete)
    ;; 3. Check every block parameter has incoming values from all predecessors
    (for-each
     (lambda (b)
       (let ((params (braun-get-params cfg b))
             (preds (braun-get-preds cfg b)))
         (for-each
          (lambda (param)
            (for-each
             (lambda (pred)
               (let ((inc (braun-get-incoming cfg param pred)))
                 (if (not inc)
                     (error "Braun CFG verification failure: missing incoming value for param:" param "from pred:" pred "in block:" b))))
             preds))
          params)))
     order)
    ;; 4. Check terminator targets exist in CFG
    (for-each
     (lambda (b)
       (let ((term (braun-get-terminator cfg b)))
         (if term
             (case (car term)
               ((%jump %direct-jump)
                (if (not (memq (cadr term) order))
                    (error "Braun CFG verification failure: unknown jump target in block:" b (cadr term))))
               ((%jump-if)
                (if (not (memq (caddr term) order))
                    (error "Braun CFG verification failure: unknown then-target in block:" b (caddr term)))
                (let ((else-lbl (if (= (length term) 4) (cadddr term) (car (cddddr term)))))
                  (if (not (memq else-lbl order))
                      (error "Braun CFG verification failure: unknown else-target in block:" b else-lbl))))
               ((%jump-if-false %jump-cond)
                (if (not (memq (caddr term) order))
                    (error "Braun CFG verification failure: unknown else-target in block:" b (caddr term))))
               ((%jump-if-zero)
                (if (not (memq (cadr term) order))
                    (error "Braun CFG verification failure: unknown zero-target in block:" b (cadr term))))
               ((%switch)
                (let ((def-lbl (caddr term))
                      (cases (cond ((= (length term) 5) (car (cddddr term)))
                                   ((pair? (cdddr term)) (cadddr term))
                                   (else '()))))
                  (if (not (memq def-lbl order))
                      (error "Braun CFG verification failure: unknown switch default target:" def-lbl))
                  (for-each
                   (lambda (c)
                     (let ((c-lbl (if (pair? (cdr c)) (cadr c) (cdr c))))
                       (if (not (memq c-lbl order))
                           (error "Braun CFG verification failure: unknown switch case target:" c-lbl))))
                   cases)))
               (else #t)))))
     order)
    #t))

;;; -----------------------------------------------------------------------
;;; mem2reg Stack Variable Promotion (DSN-38 Section 2 D1, Issue #922)
;;; -----------------------------------------------------------------------
(define (braun-inst-returns-twice? inst)
  (and (pair? inst)
       (pair? (cdr inst))
       (case (car inst)
         ((%direct-call)
          (if (memq (cadr inst) '(__ulisp_setjmp setjmp _setjmp sigsetjmp)) #t #f))
         ((%c-call %call-foreign)
          (let ((fn (cadr inst)))
            (cond
              ((symbol? fn)
               (if (memq fn '(__ulisp_setjmp setjmp _setjmp sigsetjmp)) #t #f))
              ((string? fn)
               (if (or (string=? fn "__ulisp_setjmp")
                       (string=? fn "setjmp")
                       (string=? fn "_setjmp")
                       (string=? fn "sigsetjmp"))
                   #t
                   #f))
              (else #f))))
         (else #f))))

(define (braun-cfg-has-returns-twice? cfg)
  (let loop-blocks ((bs (braun-cfg-ref cfg 'blocks)))
    (if (null? bs)
        #f
        (let loop-insts ((is (cdar bs)))
          (cond
            ((null? is) (loop-blocks (cdr bs)))
            ((braun-inst-returns-twice? (car is)) #t)
            (else (loop-insts (cdr is))))))))

(define (braun-promote-alloca-to-ssa cfg candidate-offsets)
  (if (braun-cfg-has-returns-twice? cfg)
      #f
      (let ((order (braun-cfg-ref cfg 'order)))
        (for-each
         (lambda (b)
           (let* ((insts (braun-get-insts cfg b))
                  (new-insts
                   (let loop ((is insts) (acc '()))
                     (if (null? is) (reverse acc)
                         (let ((inst (car is)))
                           (cond
                             ;; (%store %rsp offset val)
                             ((and (pair? inst) (eq? (car inst) '%store)
                                   (eq? (cadr inst) '%rsp)
                                   (braun-member? (caddr inst) candidate-offsets))
                              (let* ((offset (caddr inst))
                                     (val (cadddr inst))
                                     (var (string->symbol (string-append "stk_" (number->string offset)))))
                                (braun-write-variable! cfg var b (braun-resolve-val cfg val))
                                (loop (cdr is) acc)))
                             ;; (%load dst %rsp offset)
                             ((and (pair? inst) (eq? (car inst) '%load)
                                   (eq? (caddr inst) '%rsp)
                                   (braun-member? (cadddr inst) candidate-offsets))
                              (let* ((dst (cadr inst))
                                     (offset (cadddr inst))
                                     (var (string->symbol (string-append "stk_" (number->string offset))))
                                     (val (braun-read-variable cfg var b)))
                                (loop (cdr is) (cons (list '%mov dst (braun-resolve-val cfg val)) acc))))
                             (else
                              (loop (cdr is) (cons inst acc)))))))))
             ;; Update block instructions
             (let ((blocks (braun-cfg-ref cfg 'blocks)))
               (let ((entry (assq b blocks)))
                 (if entry (set-cdr! entry new-insts))))))
         order)
        #t)))

;;; -----------------------------------------------------------------------
;;; Register-Safe & ABI-Safe C99 LIR mem2reg & Intra-Block Promotion (Issue #927)
;;; -----------------------------------------------------------------------

(define (%c99-m2r-reg? x)
  (case x
    ((%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp
      %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15 %al %cl)
     #t)
    (else #f)))

(define (%c99-m2r-caller-saved? x)
  (case x
    ((%rax %rcx %rdx %rsi %rdi %r8 %r9 %r10 %r11 %al %cl
      %xmm0 %xmm1 %xmm2 %xmm3 %xmm4 %xmm5 %xmm6 %xmm7
      %xmm8 %xmm9 %xmm10 %xmm11 %xmm12 %xmm13 %xmm14 %xmm15)
     #t)
    (else #f)))

(define (%c99-m2r-tree-has? tree sym)
  (cond
    ((eq? tree sym) #t)
    ((pair? tree)
     (or (%c99-m2r-tree-has? (car tree) sym)
         (%c99-m2r-tree-has? (cdr tree) sym)))
    (else #f)))

(define (%c99-m2r-type-width ty)
  (case ty
    ((bool i8 u8) 1)
    ((i16 u16) 2)
    ((i32 u32 f32) 4)
    ((i64 u64 f64 ptr raw-bits) 8)
    (else #f)))

(define (%c99-m2r-canon-int-kind ty)
  (case ty
    ((bool u8) 'u8)
    ((i8)      'i8)
    ((u16)     'u16)
    ((i16)     'i16)
    ((u32)     'u32)
    ((i32)     'i32)
    ((i64 u64 ptr raw-bits) 'i64)
    (else #f)))

(define (%c99-m2r-norm-int kind v)
  (case kind
    ((u8)  (modulo v 256))
    ((u16) (modulo v 65536))
    ((u32) (modulo v 4294967296))
    ((i8)  (let ((m (modulo v 256))) (if (>= m 128) (- m 256) m)))
    ((i16) (let ((m (modulo v 65536))) (if (>= m 32768) (- m 65536) m)))
    ((i32) (let ((m (modulo v 4294967296))) (if (>= m 2147483648) (- m 4294967296) m)))
    (else v)))

(define (%c99-m2r-managed-or-unsafe-body? insts)
  (let loop ((xs insts))
    (if (null? xs)
        #f
        (let ((inst (car xs)))
          (if (or (not (pair? inst))
                  (memq (car inst)
                        '(%block %alloc %alloc-stack %managed-alloc %managed-alloc-stack
                          %managed-safepoint-poll %safepoint-poll %managed-write-barrier
                          %managed-box %managed-unbox %capture-cc %push-handler %pop-handler
                          %raise %set-values-count %store-values-buf %call-closure
                          %dispatch-consumer %inline-asm %atomic-cas! %push %pop))
                  (%c99-m2r-tree-has? inst '%stack)
                  (%c99-m2r-tree-has? inst '%disp)
                  (%c99-m2r-tree-has? inst '%mem))
              #t
              (loop (cdr xs)))))))

(define (%c99-m2r-call-inst? inst)
  (and (pair? inst)
       (memq (car inst) '(%c-call %direct-call %call-indirect %call-foreign %syscall))))

(define (%c99-m2r-rsp-escape-inst? inst)
  (if (not (pair? inst))
      #t
      (let ((op (car inst)))
        (cond
          ((and (eq? op '%mov) (>= (length inst) 3))
           (or (eq? (cadr inst) '%rsp) (eq? (caddr inst) '%rsp)))
          ((and (memq op '(%store %store-byte)) (>= (length inst) 4))
           (or (not (eq? (cadr inst) '%rsp))
               (not (integer? (caddr inst)))
               (eq? (cadddr inst) '%rsp)))
          ((and (eq? op '%store-typed) (>= (length inst) 5))
           (or (not (eq? (caddr inst) '%rsp))
               (not (integer? (cadddr inst)))
               (eq? (car (cddddr inst)) '%rsp)))
          ((and (memq op '(%load %load-byte-zx)) (>= (length inst) 4))
           (or (eq? (cadr inst) '%rsp)
               (and (eq? (caddr inst) '%rsp) (not (integer? (cadddr inst))))))
          ((and (eq? op '%load-typed) (>= (length inst) 5))
           (or (eq? (caddr inst) '%rsp)
               (and (eq? (cadddr inst) '%rsp) (not (integer? (car (cddddr inst)))))))
          (else
           (%c99-m2r-tree-has? inst '%rsp))))))

(define (%c99-m2r-match-rsp-load inst)
  ;; Returns (dst off width kind) or #f
  (if (not (pair? inst))
      #f
      (let ((op (car inst)))
        (cond
          ((and (eq? op '%load) (= (length inst) 4)
                (eq? (caddr inst) '%rsp) (integer? (cadddr inst)))
           (list (cadr inst) (cadddr inst) 8 'i64))
          ((and (eq? op '%load-byte-zx) (= (length inst) 4)
                (eq? (caddr inst) '%rsp) (integer? (cadddr inst)))
           (list (cadr inst) (cadddr inst) 1 'u8))
          ((and (eq? op '%load-typed) (= (length inst) 5)
                (eq? (cadddr inst) '%rsp) (integer? (car (cddddr inst))))
           (let* ((mty (cadr inst))
                  (w (%c99-m2r-type-width mty)))
             (if w
                 (list (caddr inst) (car (cddddr inst)) w mty)
                 #f)))
          (else #f)))))

(define (%c99-m2r-match-rsp-store inst)
  ;; Returns (off width kind src) or #f
  (if (not (pair? inst))
      #f
      (let ((op (car inst)))
        (cond
          ((and (eq? op '%store) (= (length inst) 4)
                (eq? (cadr inst) '%rsp) (integer? (caddr inst)))
           (list (caddr inst) 8 'i64 (cadddr inst)))
          ((and (eq? op '%store-byte) (= (length inst) 4)
                (eq? (cadr inst) '%rsp) (integer? (caddr inst)))
           (list (caddr inst) 1 'u8 (cadddr inst)))
          ((and (eq? op '%store-typed) (= (length inst) 5)
                (eq? (caddr inst) '%rsp) (integer? (cadddr inst)))
           (let* ((mty (cadr inst))
                  (w (%c99-m2r-type-width mty)))
             (if w
                 (list (cadddr inst) w mty (car (cddddr inst)))
                 #f)))
          (else #f)))))

(define (%c99-m2r-all-gprs)
  '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp
    %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15 %al %cl))

(define (%c99-m2r-all-kill-regs)
  '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp
    %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15 %al %cl
    %xmm0 %xmm1 %xmm2 %xmm3 %xmm4 %xmm5 %xmm6 %xmm7
    %xmm8 %xmm9 %xmm10 %xmm11 %xmm12 %xmm13 %xmm14 %xmm15))

(define (%c99-m2r-collect-used-gprs insts)
  (let ((regs-box (cons '() '())))
    (for-each
     (lambda (inst)
       (for-each
        (lambda (r)
          (if (and (not (memq r (car regs-box)))
                   (or (%c99-m2r-tree-has? inst r)
                       (lir-inst-defines-reg? inst r)))
              (set-car! regs-box (cons r (car regs-box)))))
        (%c99-m2r-all-gprs)))
     insts)
    (car regs-box)))

(define (%c99-m2r-free-scratch-pool insts)
  (let* ((used (%c99-m2r-collect-used-gprs insts))
         (has-switch?
          (let loop ((xs insts))
            (and (pair? xs)
                 (or (and (pair? (car xs)) (eq? (caar xs) '%switch))
                     (loop (cdr xs))))))
         (p0 '())
         (p1 (if (memq '%r8 used) p0 (cons '%r8 p0)))
         (p2 (if (memq '%r9 used) p1 (cons '%r9 p1)))
         (p3 (if (or has-switch? (memq '%r10 used)) p2 (cons '%r10 p2)))
         (p4 (if (or has-switch? (memq '%r11 used)) p3 (cons '%r11 p3))))
    (reverse p4)))

(define (%c99-m2r-intervals-overlap? lo1 hi1 lo2 hi2)
  (and (< lo1 hi2) (< lo2 hi1)))

(define (%c99-m2r-insert-sort-candidates xs)
  (let loop ((rem xs) (sorted '()))
    (if (null? rem)
        sorted
        (let ((cur (car rem)))
          (let ins ((ss sorted) (acc '()))
            (if (null? ss)
                (loop (cdr rem) (reverse (cons cur acc)))
                (if (>= (cdr cur) (cdr (car ss)))
                    (loop (cdr rem) (append (reverse acc) (cons cur ss)))
                    (ins (cdr ss) (cons (car ss) acc)))))))))

(define (%c99-m2r-find-leaf-slot-map insts pool)
  ;; Scans all negative %rsp accesses; returns alist of (off . (preg . canon-kind))
  (let ((stats-box (cons '() '()))
        (bad-box (cons #f '())))
    (define (record-acc! off width kind is-load?)
      (let ((cur (assv off (car stats-box))))
        (if cur
            (let ((rec (cdr cur)))
              ;; rec = (width loads stores kinds-list has-float?)
              (if (or (not (= (list-ref rec 0) width))
                      (memq kind '(f32 f64)))
                  (set-car! rec -1))
              (if is-load?
                  (let ((ld-box (list-ref rec 1)))
                    (set-car! ld-box (+ (car ld-box) 1))
                    (let ((ks (list-ref rec 3)))
                      (if (not (memq kind (car ks)))
                          (set-car! ks (cons kind (car ks))))))
                  (let ((st-box (list-ref rec 2)))
                    (set-car! st-box (+ (car st-box) 1))
                    (let ((ks (list-ref rec 4)))
                      (if (not (memq kind (car ks)))
                          (set-car! ks (cons kind (car ks))))))))
            (let ((init-w (if (memq kind '(f32 f64)) -1 width)))
              (set-car! stats-box
                        (cons (cons off
                                    (list init-w
                                          (cons (if is-load? 1 0) '())
                                          (cons (if is-load? 0 1) '())
                                          (cons (if is-load? (list kind) '()) '())
                                          (cons (if is-load? '() (list kind)) '())))
                              (car stats-box)))))))
    (for-each
     (lambda (inst)
       (if (%c99-m2r-tree-has? inst '%stack)
           (set-car! bad-box #t))
       (let ((ld (%c99-m2r-match-rsp-load inst))
             (st (%c99-m2r-match-rsp-store inst)))
         (cond
           (ld
            (if (< (cadr ld) 0)
                (record-acc! (cadr ld) (caddr ld) (cadddr ld) #t)
                (set-car! bad-box #t)))
           (st
            (if (< (car st) 0)
                (record-acc! (car st) (cadr st) (caddr st) #f)
                (set-car! bad-box #t)))
           ((%c99-m2r-tree-has? inst '%rsp)
            (set-car! bad-box #t)))))
     insts)
    (if (car bad-box)
        '()
        (let* ((stats (car stats-box))
               (eligible
                (let loop ((xs stats) (acc '()))
                  (if (null? xs)
                      acc
                      (let* ((off (caar xs))
                             (rec (cdar xs))
                             (w (list-ref rec 0))
                             (lds (car (list-ref rec 1)))
                             (sts (car (list-ref rec 2)))
                             (l-kinds (car (list-ref rec 3)))
                             (s-kinds (car (list-ref rec 4)))
                             (hi (+ off w))
                             (overlaps?
                              (let chk ((ys stats))
                                (if (null? ys)
                                    #f
                                    (let* ((o2 (caar ys))
                                           (r2 (cdar ys))
                                           (w2 (let ((raw-w (list-ref r2 0)))
                                                 (if (> raw-w 0) raw-w 8))))
                                      (if (and (not (= o2 off))
                                               (%c99-m2r-intervals-overlap? off hi o2 (+ o2 w2)))
                                          #t
                                          (chk (cdr ys))))))))
                        (if (and (> w 0)
                                 (not overlaps?)
                                 (> lds 0)
                                 (> sts 0)
                                 (= (length l-kinds) 1)
                                 (>= w 1))
                            (let ((lk (%c99-m2r-canon-int-kind (car l-kinds)))
                                  (all-compat-stores?
                                   (let cl ((sks s-kinds))
                                     (or (null? sks)
                                         (and (%c99-m2r-canon-int-kind (car sks))
                                              (= (%c99-m2r-type-width (car sks)) w)
                                              (cl (cdr sks)))))))
                              (if (and lk all-compat-stores?)
                                  (loop (cdr xs) (cons (cons (list off lk) (+ lds sts)) acc))
                                  (loop (cdr xs) acc)))
                            (loop (cdr xs) acc))))))
               (ranked (%c99-m2r-insert-sort-candidates eligible)))
          (let assign ((cs ranked) (ps pool) (res '()))
            (if (or (null? cs) (null? ps))
                (reverse res)
                (let ((off (caaar cs))
                      (kind (cadar (car cs)))
                      (preg (car ps)))
                  (assign (cdr cs) (cdr ps)
                          (cons (list off preg kind) res)))))))))

(define (%c99-m2r-promote-leaf-slots insts)
  (let* ((has-call?
          (let loop ((xs insts))
            (and (pair? xs) (or (%c99-m2r-call-inst? (car xs)) (loop (cdr xs))))))
         (has-escape?
          (let loop ((xs insts))
            (and (pair? xs) (or (%c99-m2r-rsp-escape-inst? (car xs)) (loop (cdr xs)))))))
    (if (or has-call? has-escape?)
        insts
        (let ((pool (%c99-m2r-free-scratch-pool insts)))
          (if (null? pool)
              insts
              (let ((slot-map (%c99-m2r-find-leaf-slot-map insts pool)))
                (if (null? slot-map)
                    insts
                    (let loop ((xs insts) (acc '()))
                      (if (null? xs)
                          (reverse acc)
                          (let* ((inst (car xs))
                                 (ld (%c99-m2r-match-rsp-load inst))
                                 (st (%c99-m2r-match-rsp-store inst)))
                            (cond
                              ((and ld (assv (cadr ld) slot-map))
                               => (lambda (slot)
                                    (let ((dst (car ld))
                                          (preg (cadr slot)))
                                      (loop (cdr xs)
                                            (if (eq? dst preg)
                                                acc
                                                (cons (list '%mov dst preg) acc))))))
                              ((and st (assv (car st) slot-map))
                               => (lambda (slot)
                                    (let* ((preg (cadr slot))
                                           (kind (caddr slot))
                                           (src (cadddr st))
                                           (new-inst
                                            (cond
                                              ((integer? src)
                                               (list '%mov preg (%c99-m2r-norm-int kind src)))
                                              ((eq? kind 'i64)
                                               (if (eq? preg src) #f (list '%mov preg src)))
                                              ((memq kind '(i8 i16 i32))
                                               (list '%sext kind preg src))
                                              (else
                                               (list '%zext kind preg src)))))
                                      (loop (cdr xs)
                                            (if new-inst (cons new-inst acc) acc)))))
                              (else
                               (loop (cdr xs) (cons inst acc))))))))))))))

(define (%c99-m2r-inst-reads-any-reg? inst regs)
  ;; Over-approximation: check if any symbol in regs appears in rhs operands or implicit uses
  (if (not (pair? inst))
      #f
      (let ((op (car inst)))
        (or (and (memq op '(%cqo %idiv %udiv %urem))
                 (or (memq '%rax regs) (memq '%rdx regs)))
            (and (memq op '(%shl %shr %sar))
                 (= (length inst) 3)
                 (not (integer? (caddr inst)))
                 (memq '%rcx regs))
            (and (memq op '(%return))
                 (memq '%rax regs))
            (let loop ((rs regs))
              (if (null? rs)
                  #f
                  (if (%c99-m2r-tree-has? inst (car rs))
                      #t
                      (loop (cdr rs)))))))))

(define (%c99-m2r-slot-env-kill-overlap env off w)
  (let ((hi (+ off w)))
    (let loop ((xs env) (acc '()))
      (if (null? xs)
          (reverse acc)
          (let* ((e (car xs))
                 (eo (list-ref e 0))
                 (ew (list-ref e 1)))
            (if (%c99-m2r-intervals-overlap? off hi eo (+ eo ew))
                (loop (cdr xs) acc)
                (loop (cdr xs) (cons e acc))))))))

(define (%c99-m2r-slot-env-kill-reg env reg)
  (let loop ((xs env) (acc '()))
    (if (null? xs)
        (reverse acc)
        (let* ((e (car xs))
               (val (list-ref e 3)))
          (if (and (memq (car val) '(reg loaded-reg freg))
                   (lir-reg-aliases? (cdr val) reg))
              (loop (cdr xs) acc)
              (loop (cdr xs) (cons e acc)))))))

(define (%c99-m2r-slot-env-kill-caller-regs env keep-consts?)
  (let loop ((xs env) (acc '()))
    (if (null? xs)
        (reverse acc)
        (let* ((e (car xs))
               (val (list-ref e 3)))
          (cond
            ((eq? (car val) 'const)
             (if keep-consts?
                 (loop (cdr xs) (cons e acc))
                 (loop (cdr xs) acc)))
            ((and (memq (car val) '(reg loaded-reg)) (not (%c99-m2r-caller-saved? (cdr val))))
             (loop (cdr xs) (cons e acc)))
            (else
             (loop (cdr xs) acc)))))))

(define (%c99-m2r-reg-env-kill env inst)
  (let loop ((xs env) (acc '()))
    (if (null? xs)
        (reverse acc)
        (let* ((r (caar xs))
               (val (cdar xs)))
          (if (or (lir-inst-defines-reg? inst r)
                  (and (eq? (car val) 'reg) (lir-inst-defines-reg? inst (cdr val))))
              (loop (cdr xs) acc)
              (loop (cdr xs) (cons (car xs) acc)))))))

(define (%c99-m2r-forward-blocks insts)
  (let* ((has-escape?
          (let loop ((xs insts))
            (and (pair? xs) (or (%c99-m2r-rsp-escape-inst? (car xs)) (loop (cdr xs))))))
         (has-rt? (braun-cfg-has-returns-twice? (list (cons 'blocks (list (cons 'entry insts))))))
         (safe-across-calls? (and (not has-escape?) (not has-rt?))))
    (let loop ((xs insts) (slot-env '()) (reg-env '()) (acc '()))
      (if (null? xs)
          (reverse acc)
          (let ((inst (car xs)))
            (if (not (pair? inst))
                (loop (cdr xs) '() '() (cons inst acc))
                (let ((op (car inst))
                      (ld (%c99-m2r-match-rsp-load inst))
                      (st (%c99-m2r-match-rsp-store inst)))
                  (cond
                    ;; 1. Block terminators / labels reset intrablock state
                    ((or (lir-label-inst? inst)
                         (lir-inst-terminates-block? inst))
                     (loop (cdr xs) '() '() (cons inst acc)))

                    ;; 2. Calls preserve non-escaped constant stack slots if no setjmp/rsp-escape
                    ((%c99-m2r-call-inst? inst)
                     (loop (cdr xs)
                           (if safe-across-calls?
                               (%c99-m2r-slot-env-kill-caller-regs slot-env #t)
                               '())
                           '()
                           (cons inst acc)))

                    ;; 3. Other memory barriers reset everything
                    ((lir-inst-memory-barrier? inst)
                     (loop (cdr xs) '() '() (cons inst acc)))

                    ;; 4. Store to negative %rsp slot
                    ((and st (< (car st) 0))
                     (let* ((off (car st))
                            (w (cadr st))
                            (skind (caddr st))
                            (src (cadddr st))
                            (s-env0 (%c99-m2r-slot-env-kill-overlap slot-env off w))
                            (s-val (cond
                                     ((integer? src)
                                      (if (memq skind '(f32 f64))
                                          #f
                                          (let ((c-k (%c99-m2r-canon-int-kind skind)))
                                            (cons 'const (if c-k (%c99-m2r-norm-int c-k src) src)))))
                                     ((%c99-m2r-reg? src)
                                      (let ((r-hit (assq src reg-env)))
                                        (if (and r-hit (eq? (car (cdr r-hit)) 'const))
                                            (let ((c-k (%c99-m2r-canon-int-kind skind)))
                                              (cons 'const (if c-k
                                                               (%c99-m2r-norm-int c-k (cdr (cdr r-hit)))
                                                               (cdr (cdr r-hit)))))
                                            (if r-hit (cdr r-hit) (cons 'reg src)))))
                                     ((and (memq skind '(f64)) (lir-float-register? src))
                                      (cons 'freg src))
                                     (else #f)))
                            (s-env1 (if s-val
                                        (cons (list off w skind s-val) s-env0)
                                        s-env0)))
                       (loop (cdr xs) s-env1 reg-env (cons inst acc))))

                    ;; 5. Store to non-%rsp memory may alias if %rsp escaped
                    ((memq op '(%store %store-byte %store-typed))
                     (loop (cdr xs)
                           (if safe-across-calls? slot-env '())
                           reg-env
                           (cons inst acc)))

                    ;; 6. Load from negative %rsp slot
                    ((and ld (< (cadr ld) 0))
                     (let* ((dst (car ld))
                            (off (cadr ld))
                            (w (caddr ld))
                            (lkind (cadddr ld))
                            (l-c-kind (%c99-m2r-canon-int-kind lkind))
                            (hit (assv off slot-env))
                            (forwarded-inst
                             (if (and hit (= (list-ref hit 1) w))
                                 (let ((skind (list-ref hit 2))
                                       (vdesc (list-ref hit 3)))
                                   (cond
                                     ((and l-c-kind (not (memq skind '(f32 f64))) (eq? (car vdesc) 'const))
                                      (list '%mov dst (%c99-m2r-norm-int l-c-kind (cdr vdesc))))
                                     ((and l-c-kind (not (memq skind '(f32 f64))) (memq (car vdesc) '(reg loaded-reg)))
                                      (let ((sreg (cdr vdesc))
                                            (s-c-kind (%c99-m2r-canon-int-kind skind))
                                            (already-ext? (eq? (car vdesc) 'loaded-reg)))
                                        (cond
                                          ((or (= w 8)
                                               (and already-ext? (eq? s-c-kind l-c-kind)))
                                           (list '%mov dst sreg))
                                          ((memq l-c-kind '(i8 i16 i32))
                                           (list '%sext l-c-kind dst sreg))
                                          ((memq l-c-kind '(u8 u16 u32))
                                           (list '%zext l-c-kind dst sreg))
                                          (else #f))))
                                     ((and (eq? lkind 'f64) (eq? skind 'f64) (eq? (car vdesc) 'freg))
                                      (list '%fmov dst (cdr vdesc)))
                                     (else #f)))
                                 #f))
                            (emit-i (or forwarded-inst inst))
                            (r-env1 (%c99-m2r-reg-env-kill reg-env emit-i))
                            (s-env1
                             (let loop-kill ((rs (%c99-m2r-all-kill-regs)) (se slot-env))
                               (if (null? rs)
                                   se
                                   (loop-kill (cdr rs)
                                              (if (lir-inst-defines-reg? emit-i (car rs))
                                                  (%c99-m2r-slot-env-kill-reg se (car rs))
                                                  se)))))
                            (r-env2 (cond
                                      ((and (pair? emit-i) (eq? (car emit-i) '%mov) (= (length emit-i) 3)
                                            (%c99-m2r-reg? (cadr emit-i)) (integer? (caddr emit-i)))
                                       (cons (cons (cadr emit-i) (cons 'const (caddr emit-i))) r-env1))
                                      ((and (pair? emit-i) (eq? (car emit-i) '%mov) (= (length emit-i) 3)
                                            (%c99-m2r-reg? (cadr emit-i)) (%c99-m2r-reg? (caddr emit-i)))
                                       (let ((rh (assq (caddr emit-i) r-env1)))
                                         (if (and rh (eq? (car (cdr rh)) 'const))
                                             (cons (cons (cadr emit-i) (cdr rh)) r-env1)
                                             r-env1)))
                                      (else r-env1)))
                            (s-env2 (if (and (not forwarded-inst) l-c-kind (%c99-m2r-reg? dst))
                                        (cons (list off w lkind (cons 'loaded-reg dst))
                                              (%c99-m2r-slot-env-kill-overlap s-env1 off w))
                                        s-env1)))
                       (loop (cdr xs)
                             s-env2
                             r-env2
                             (if (and (memq (car emit-i) '(%mov %fmov)) (eq? (cadr emit-i) (caddr emit-i)))
                                 acc
                                 (cons emit-i acc)))))

                    ;; 7. Any other instruction: propagate reg-env & kill overwritten regs
                    (else
                     (let* ((r-env1 (%c99-m2r-reg-env-kill reg-env inst))
                            (s-env1
                             (let loop-kill ((rs (%c99-m2r-all-kill-regs)) (se slot-env))
                               (if (null? rs)
                                   se
                                   (loop-kill (cdr rs)
                                              (if (lir-inst-defines-reg? inst (car rs))
                                                  (%c99-m2r-slot-env-kill-reg se (car rs))
                                                  se)))))
                            (r-env2
                             (cond
                               ((and (eq? op '%mov) (= (length inst) 3)
                                     (%c99-m2r-reg? (cadr inst)) (integer? (caddr inst)))
                                (cons (cons (cadr inst) (cons 'const (caddr inst))) r-env1))
                               ((and (eq? op '%mov) (= (length inst) 3)
                                     (%c99-m2r-reg? (cadr inst)) (%c99-m2r-reg? (caddr inst)))
                                (let ((rh (assq (caddr inst) reg-env)))
                                  (if (and rh (not (eq? (cadr inst) (caddr inst))))
                                      (if (eq? (car (cdr rh)) 'const)
                                          (cons (cons (cadr inst) (cdr rh)) r-env1)
                                          r-env1)
                                      r-env1)))
                               (else r-env1)))
                            ;; If %mov reg1 reg2 where reg2 holds a constant in reg-env, replace with (%mov reg1 imm)!
                            (final-inst
                             (if (and (eq? op '%mov) (= (length inst) 3)
                                      (%c99-m2r-reg? (cadr inst)) (%c99-m2r-reg? (caddr inst)))
                                 (let ((rh (assq (caddr inst) reg-env)))
                                   (if (and rh (eq? (car (cdr rh)) 'const))
                                       (list '%mov (cadr inst) (cdr (cdr rh)))
                                       inst))
                                 inst)))
                       (loop (cdr xs) s-env1 r-env2 (cons final-inst acc))))))))))
    ))

(define (%c99-m2r-elim-dead-stores-intra-block insts)
  (let* ((has-escape?
          (let loop ((xs insts))
            (and (pair? xs) (or (%c99-m2r-rsp-escape-inst? (car xs)) (loop (cdr xs))))))
         (has-rt? (braun-cfg-has-returns-twice? (list (cons 'blocks (list (cons 'entry insts))))))
         (safe-across-calls? (and (not has-escape?) (not has-rt?))))
    (let loop ((xs (reverse insts)) (dead-ivs '()) (acc '()))
      (if (null? xs)
          acc
          (let* ((inst (car xs))
                 (ld (%c99-m2r-match-rsp-load inst))
                 (st (%c99-m2r-match-rsp-store inst)))
            (cond
              ((or (not (pair? inst))
                   (lir-label-inst? inst)
                   (lir-inst-terminates-block? inst))
               (loop (cdr xs) '() (cons inst acc)))
              ((%c99-m2r-call-inst? inst)
               ;; Outside the outgoing call frame, stores strictly overwritten LATER in subsequent blocks aren't tracked here;
               ;; reset dead-ivs at calls conservatively.
               (loop (cdr xs) (if safe-across-calls? '() '()) (cons inst acc)))
              ((lir-inst-memory-barrier? inst)
               (loop (cdr xs) '() (cons inst acc)))
              ((and st (< (car st) 0) (<= (+ (car st) (cadr st)) 0))
               (let* ((off (car st))
                      (w (cadr st))
                      (hi (+ off w))
                      (subsumed? (lir-iv-subsumed? dead-ivs off hi)))
                 (if subsumed?
                     (loop (cdr xs) dead-ivs acc)
                     (loop (cdr xs) (lir-iv-insert dead-ivs off hi) (cons inst acc)))))
              ((and ld (< (cadr ld) 0))
               (let ((off (cadr ld))
                     (w (caddr ld)))
                 (loop (cdr xs) (lir-iv-remove dead-ivs off (+ off w)) (cons inst acc))))
              ((and has-escape? (%c99-m2r-tree-has? inst '%load))
               (loop (cdr xs) '() (cons inst acc)))
              (else
               (loop (cdr xs) dead-ivs (cons inst acc)))))))))

(define (c99-lir-mem2reg-function-body body)
  (if (or (null? body) (%c99-m2r-managed-or-unsafe-body? body))
      body
      (let* ((b1 (%c99-m2r-promote-leaf-slots body))
             (b2 (%c99-m2r-forward-blocks b1))
             (b3 (%c99-m2r-elim-dead-stores-intra-block b2)))
        (if (equal? b3 body) body b3))))

(define (%c99-m2r-transform-clause form)
  (if (not (pair? form))
      form
      (case (car form)
        ((%lir-function)
         (let ((new-clauses
                (map (lambda (sub)
                       (if (and (pair? sub) (eq? (car sub) 'body))
                           (let* ((old-b (cdr sub))
                                  (new-b (c99-lir-mem2reg-function-body old-b)))
                             (if (eq? new-b old-b) sub (cons 'body new-b)))
                           sub))
                     (cdr form))))
           (if (equal? new-clauses (cdr form))
               form
               (cons '%lir-function new-clauses))))
        ((%lir-main)
         (let ((new-clauses
                (map (lambda (sub)
                       (if (and (pair? sub) (eq? (car sub) 'body))
                           (let* ((old-b (cdr sub))
                                  (new-b (c99-lir-mem2reg-function-body old-b)))
                             (if (eq? new-b old-b) sub (cons 'body new-b)))
                           sub))
                     (cdr form))))
           (if (equal? new-clauses (cdr form))
               form
               (cons '%lir-main new-clauses))))
        ((%lir-functions)
         (let ((new-fns (map %c99-m2r-transform-clause (cdr form))))
           (if (equal? new-fns (cdr form))
               form
               (cons '%lir-functions new-fns))))
        (else form))))

(define (c99-lir-mem2reg-optimize ir)
  (cond
    ((null? ir) '())
    ((and (pair? ir) (eq? (car ir) '%lir-program))
     (let ((new-body (map %c99-m2r-transform-clause (cdr ir))))
       (if (equal? new-body (cdr ir))
           ir
           (cons '%lir-program new-body))))
    ((pair? ir)
     (if (memq (car ir) '(%lir-function %lir-main))
         (%c99-m2r-transform-clause ir)
         (c99-lir-mem2reg-function-body ir)))
    (else ir)))

;;; -----------------------------------------------------------------------
;;; Unified L_mir_ssa <-> L_lir_mach Transformations (Issue #966)
;;; -----------------------------------------------------------------------

(define (%mir-body-has-managed-opcodes? insts)
  (let loop ((is insts))
    (if (null? is)
        #f
        (let ((inst (car is)))
          (cond
            ((not (pair? inst)) (loop (cdr is)))
            ((eq? (car inst) '%block)
             (or (%mir-body-has-managed-opcodes? (cdddr inst))
                 (loop (cdr is))))
            ((managed-dialect-opcode? (car inst)) #t)
            (else (loop (cdr is))))))))

(define (%mir-program-has-managed-opcodes? ir)
  (cond
    ((not (pair? ir)) #f)
    ((eq? (car ir) '%lir-program)
     (let ((fns (assq '%lir-functions (cdr ir)))
           (main (assq '%lir-main (cdr ir))))
       (or (and fns
                (let fl ((fs (cdr fns)))
                  (and (pair? fs)
                       (or (%mir-program-has-managed-opcodes? (car fs))
                           (fl (cdr fs))))))
           (and main (%mir-program-has-managed-opcodes? main)))))
    ((memq (car ir) '(%lir-function %lir-main))
     (let ((b (assq 'body (cdr ir))))
       (and b (%mir-body-has-managed-opcodes? (cdr b)))))
    (else (%mir-body-has-managed-opcodes? ir))))

(define (lir-to-mir-ssa ir)
  (let ((unmanaged (if (%mir-program-has-managed-opcodes? ir)
                       (lower-managed-dialect ir)
                       ir)))
    (c99-lir-mem2reg-optimize unmanaged)))

(define (braun-ssa-transform-program ir)
  (lir-to-mir-ssa ir))

(define (%mir-body-needs-mach-lowering? insts)
  (let walk-list ((xs insts))
    (if (null? xs)
        #f
        (let ((inst (car xs)))
          (if (not (pair? inst))
              (walk-list (cdr xs))
              (or (let walk-tree ((t inst))
                    (cond
                      ((not (pair? t)) #f)
                      ((lir-virtual-register? t) #t)
                      (else (or (walk-tree (car t)) (walk-tree (cdr t))))))
                  (and (eq? (car inst) '%block)
                       (pair? (cdr inst))
                       (pair? (cddr inst))
                       (list? (caddr inst))
                       (let pchk ((ps (caddr inst)))
                         (and (pair? ps)
                              (or (not (lir-block-param-physical? (car ps)))
                                  (pchk (cdr ps))))))
                  (walk-list (cdr xs))))))))

(define (%mir-unwrap-phys-wrapper x)
  (cond
    ((and (pair? x) (eq? (car x) '%reg) (pair? (cdr x)))
     (let ((inner (if (pair? (cddr x)) (caddr x) (cadr x))))
       (if (lir-physical-register-sym? inner) inner #f)))
    ((and (pair? x) (eq? (car x) '%freg) (pair? (cdr x)))
     (let ((inner (cadr x)))
       (if (memq inner *canonical-lir-float-registers*) inner #f)))
    (else #f)))

(define (%mir-vreg-kind-and-sym x)
  (cond
    ((%mir-unwrap-phys-wrapper x) #f)
    ((and (pair? x) (eq? (car x) '%reg) (pair? (cdr x)))
     (if (pair? (cddr x))
         (let ((mty (cadr x))
               (sym (caddr x)))
           (if (symbol? sym)
               (cons sym (if (memq mty '(f32 f64)) 'fpr 'gpr))
               #f))
         (if (symbol? (cadr x))
             (cons (cadr x) 'gpr)
             #f)))
    ((and (pair? x) (eq? (car x) '%freg) (pair? (cdr x)) (symbol? (cadr x)))
     (cons (cadr x) 'fpr))
    (else #f)))

(define (%mir-analyze-body insts orig-frame-size)
  (let ((used-box (cons '() '()))
        (calls-box (cons #f '()))
        (min-off-box (cons (if (> orig-frame-size 0) (- 0 orig-frame-size) 0) '()))
        (vregs-box (cons '() '()))
        (block-params-box (cons '() '())))
    (define add-used!
      (lambda (r)
        (if (and (symbol? r) (lir-physical-register-sym? r) (not (memq r (car used-box))))
            (set-car! used-box (cons r (car used-box))))))
    (define note-off!
      (lambda (off)
        (if (and (integer? off) (< off (car min-off-box)))
            (set-car! min-off-box off))))
    (define add-vreg!
      (lambda (sym kind)
        (if (and (symbol? sym) (not (assq sym (car vregs-box))))
            (set-car! vregs-box (cons (cons sym kind) (car vregs-box))))))
    (let walk-insts ((is insts))
      (if (not (null? is))
          (let ((inst (car is)))
            (if (pair? inst)
                (let ((op (car inst)))
                  (if (memq op '(%direct-call %c-call %call-foreign %call-indirect %call-closure %syscall %dispatch-consumer))
                      (set-car! calls-box #t))
                  (if (and (eq? op '%block) (pair? (cdr inst)) (pair? (cddr inst)) (list? (caddr inst)))
                      (let ((lbl (cadr inst))
                            (ps (caddr inst))
                            (sub (cdddr inst)))
                        (let ((has-virt?
                               (let chk ((xs ps))
                                 (and (pair? xs)
                                      (or (not (lir-block-param-physical? (car xs)))
                                          (chk (cdr xs)))))))
                          (if has-virt?
                              (begin
                                (set-car! block-params-box (cons (cons lbl ps) (car block-params-box)))
                                (for-each (lambda (p)
                                            (cond
                                              ((%mir-vreg-kind-and-sym p) => (lambda (kv) (add-vreg! (car kv) (cdr kv))))
                                              ((%mir-unwrap-phys-wrapper p) => add-used!)
                                              ((symbol? p)
                                               (if (lir-physical-register-sym? p)
                                                   (add-used! p)
                                                   (add-vreg! p 'gpr)))))
                                          ps)))
                          (walk-insts sub))))
                  (let walk-tree ((t inst))
                    (cond
                      ((symbol? t)
                       (if (lir-physical-register-sym? t) (add-used! t)))
                      ((pair? t)
                       (let ((phys (%mir-unwrap-phys-wrapper t))
                             (vk (%mir-vreg-kind-and-sym t)))
                         (cond
                           (phys (add-used! phys))
                           (vk (add-vreg! (car vk) (cdr vk)))
                           ((and (eq? (car t) '%stack) (pair? (cdr t)) (integer? (cadr t)))
                            (note-off! (cadr t)))
                           ((and (memq (car t) '(%load %load-byte-zx)) (>= (length t) 4)
                                 (eq? (caddr t) '%rsp) (integer? (cadddr t)))
                            (add-used! '%rsp)
                            (note-off! (cadddr t))
                            (walk-tree (cadr t)))
                           ((and (memq (car t) '(%store %store-byte)) (>= (length t) 4)
                                 (eq? (cadr t) '%rsp) (integer? (caddr t)))
                            (add-used! '%rsp)
                            (note-off! (caddr t))
                            (walk-tree (cadddr t)))
                           ((and (eq? (car t) '%load-typed) (>= (length t) 5)
                                 (eq? (cadddr t) '%rsp) (integer? (car (cddddr t))))
                            (add-used! '%rsp)
                            (note-off! (car (cddddr t)))
                            (walk-tree (caddr t)))
                           ((and (eq? (car t) '%store-typed) (>= (length t) 5)
                                 (eq? (caddr t) '%rsp) (integer? (cadddr t)))
                            (add-used! '%rsp)
                            (note-off! (cadddr t))
                            (walk-tree (car (cddddr t))))
                           (else
                            (walk-tree (car t))
                            (walk-tree (cdr t))))))))))
            (walk-insts (cdr is)))))
    (list (car used-box)
          (car calls-box)
          (car min-off-box)
          (reverse (car vregs-box))
          (reverse (car block-params-box)))))

(define (%mir-assign-vreg-locations analysis)
  (let* ((used-phys (list-ref analysis 0))
         (has-calls? (list-ref analysis 1))
         (start-off (list-ref analysis 2))
         (vregs (list-ref analysis 3))
         (free-gprs (if has-calls?
                        '()
                        (filter (lambda (r) (not (memq r used-phys)))
                                '(%r8 %r9 %rsi %rdi %rdx %rcx))))
         (free-fprs (if has-calls?
                        '()
                        (filter (lambda (r) (not (memq r used-phys)))
                                '(%xmm1 %xmm2 %xmm3 %xmm4 %xmm5 %xmm6 %xmm7 %xmm8 %xmm9 %xmm10 %xmm11 %xmm12 %xmm13)))))
    (let loop ((vs vregs) (gprs free-gprs) (fprs free-fprs) (cur-off start-off) (acc '()))
      (if (null? vs)
          (let* ((raw-fs (if (< cur-off 0) (- 0 cur-off) 0))
                 (aligned-fs (* (quotient (+ raw-fs 7) 8) 8)))
            (cons (reverse acc) aligned-fs))
          (let* ((entry (car vs))
                 (sym (car entry))
                 (kind (cdr entry)))
            (cond
              ((and (eq? kind 'gpr) (pair? gprs))
               (loop (cdr vs) (cdr gprs) fprs cur-off (cons (cons sym (car gprs)) acc)))
              ((and (eq? kind 'fpr) (pair? fprs))
               (loop (cdr vs) gprs (cdr fprs) cur-off (cons (cons sym (car fprs)) acc)))
              (else
               (let ((next-off (- cur-off 8)))
                 (loop (cdr vs) gprs fprs next-off
                       (cons (cons sym (list '%stack next-off)) acc))))))))))

(define (%mir-stack-opnd? x)
  (and (pair? x) (eq? (car x) '%stack) (pair? (cdr x)) (integer? (cadr x))))

(define (%mir-emit-move dst src)
  (cond
    ((equal? dst src) '())
    ((and (%mir-stack-opnd? dst) (%mir-stack-opnd? src))
     (list (list '%load '%r10 '%rsp (cadr src))
           (list '%store '%rsp (cadr dst) '%r10)))
    ((%mir-stack-opnd? dst)
     (list (list '%store '%rsp (cadr dst) src)))
    ((%mir-stack-opnd? src)
     (list (list '%load dst '%rsp (cadr src))))
    (else
     (list (list '%mov dst src)))))

(define (%mir-emit-parallel-moves dsts srcs)
  (let* ((pairs
          (let collect ((ds dsts) (ss srcs) (acc '()))
            (if (or (null? ds) (null? ss))
                (reverse acc)
                (let ((d (car ds)) (s (car ss)))
                  (if (equal? d s)
                      (collect (cdr ds) (cdr ss) acc)
                      (collect (cdr ds) (cdr ss) (cons (cons d s) acc))))))))
    (let loop ((rem pairs) (acc '()))
      (if (null? rem)
          acc
          ;; Find a move whose dst does not appear as src in any remaining move
          (let ((safe
                 (let find-safe ((ms rem))
                   (cond
                     ((null? ms) #f)
                     ((let is-read? ((d (caar ms)) (all rem))
                        (and (pair? all)
                             (or (and (not (eq? (car all) (car ms)))
                                      (equal? d (cdar all)))
                                 (is-read? d (cdr all)))))
                      (find-safe (cdr ms)))
                     (else (car ms))))))
            (if safe
                (let ((rest (let drop-one ((ms rem))
                              (cond ((null? ms) '())
                                    ((eq? (car ms) safe) (cdr ms))
                                    (else (cons (car ms) (drop-one (cdr ms))))))))
                  (loop rest (append acc (%mir-emit-move (car safe) (cdr safe)))))
                ;; Cycle remaining: break cycle using %r11 scratch register
                (let* ((head-dst (caar rem))
                       (save-insts (%mir-emit-move '%r11 head-dst))
                       (updated-rem
                        (map (lambda (m)
                               (if (equal? (cdr m) head-dst)
                                   (cons (car m) '%r11)
                                   m))
                             rem)))
                  (loop updated-rem (append acc save-insts)))))))))

(define (%mir-resolve-opnd x vreg-map)
  (let ((phys (%mir-unwrap-phys-wrapper x))
        (vk (%mir-vreg-kind-and-sym x)))
    (cond
      (phys phys)
      (vk
       (let ((hit (assq (car vk) vreg-map)))
         (if hit (cdr hit) (car vk))))
      ((symbol? x)
       (let ((hit (assq x vreg-map)))
         (if hit (cdr hit) x)))
      (else x))))

(define (%mir-tree-subst-vregs node vreg-map)
  (let ((phys (%mir-unwrap-phys-wrapper node))
        (vk (%mir-vreg-kind-and-sym node)))
    (cond
      (phys phys)
      (vk (let ((hit (assq (car vk) vreg-map)))
            (if hit (cdr hit) (car vk))))
      ((pair? node)
       (cons (%mir-tree-subst-vregs (car node) vreg-map)
             (%mir-tree-subst-vregs (cdr node) vreg-map)))
      ((symbol? node)
       (let ((hit (assq node vreg-map)))
         (if hit (cdr hit) node)))
      (else node))))

(define (%mir-spill-write-only-dst-indices op len)
  (cond
    ((memq op '(%mov %load %load-byte-zx %code-ref %str-ref %global-ref %global-addr %pop
                %not %set-boolean %fmov %sitofp %uitofp %fptosi %fptoui %alloc %alloc-stack
                %managed-alloc %managed-alloc-stack %box-fixnum %unbox-fixnum %box-flonum %unbox-flonum))
     '(1))
    ((memq op '(%load-typed %fneg %fpext %fptrunc %trunc %zext %sext %managed-box %managed-unbox))
     '(2))
    ((memq op '(%add-overflow %sub-overflow %mul-overflow))
     '(1 2))
    ((and (memq op '(%udiv %urem %shr %setb %setbe %seta %setae %fcmp-oeq %fcmp-une %fcmp-olt %fcmp-ole %fcmp-ogt %fcmp-oge))
          (>= len 4))
     '(1))
    (else '())))

(define (%mir-spill-read-write-dst-indices op len)
  (cond
    ((and (memq op '(%add %raw-add %sub %raw-sub %imul %raw-mul %bit-and %bit-or %bit-xor
                     %shl %sar %fadd %fsub %fmul %fdiv %set-boolean))
          (= len 3))
     '(1))
    ((and (memq op '(%shr)) (= len 3)) '(1))
    ((and (memq op '(%neg %inc)) (= len 2)) '(1))
    ((and (eq? op '%atomic-cas!) (= len 4)) '(1))
    (else '())))

(define (%mir-subst-vregs-with-spills inst vreg-map orig-inst)
  ;; Rewrites inst cleanly into valid L_lir_mach instructions (never leaving %reg/%freg or %stack in Register pos)
  (let* ((mapped (%mir-tree-subst-vregs inst vreg-map))
         (op (if (pair? mapped) (car mapped) #f)))
    (if (not op)
        (list mapped)
        (let* ((orig-has-vreg-pos?
                (let collect ((xs (cdr orig-inst)) (idx 1) (acc '()))
                  (if (null? xs)
                      acc
                      (let ((o (car xs))
                            (m (list-ref mapped idx)))
                        (if (and (%mir-stack-opnd? m)
                                 (or (lir-virtual-register? o)
                                     (and (symbol? o) (assq o vreg-map))))
                            (collect (cdr xs) (+ idx 1) (cons (list idx o m) acc))
                            (collect (cdr xs) (+ idx 1) acc))))))
               (gpr-scratch '(%r10 %r11))
               (fpr-scratch '(%xmm14 %xmm15)))
          (cond
            ;; Fast path: 0 spilled vregs in top-level operand positions
            ((null? orig-has-vreg-pos?)
             (list mapped))
            ;; Special clean lowering for (%mov dst src)
            ((and (eq? op '%mov) (= (length mapped) 3))
             (%mir-emit-move (cadr mapped) (caddr mapped)))
            (else
             (let* ((len (length mapped))
                    (wo-idxs (%mir-spill-write-only-dst-indices op len))
                    (rw-idxs (%mir-spill-read-write-dst-indices op len))
                    (slot-scratch-box (cons '() '()))
                    (pre-box (cons '() '()))
                    (post-box (cons '() '()))
                    (new-args
                     (let build ((xs (cdr mapped)) (idx 1) (gpool gpr-scratch) (fpool fpr-scratch) (acc '()))
                       (if (null? xs)
                           (reverse acc)
                           (let* ((cur (car xs))
                                  (orig-o (list-ref orig-inst idx))
                                  (is-spilled-vreg?
                                   (and (%mir-stack-opnd? cur)
                                        (or (lir-virtual-register? orig-o)
                                            (and (symbol? orig-o) (assq orig-o vreg-map))))))
                             (if (not is-spilled-vreg?)
                                 (build (cdr xs) (+ idx 1) gpool fpool (cons cur acc))
                                 (let* ((off (cadr cur))
                                        (is-fpr? (or (and (pair? orig-o) (eq? (car orig-o) '%freg))
                                                     (and (pair? orig-o) (eq? (car orig-o) '%reg)
                                                          (pair? (cddr orig-o)) (memq (cadr orig-o) '(f32 f64)))))
                                        (existing (assv off (car slot-scratch-box)))
                                        (scratch (if existing
                                                     (cdr existing)
                                                     (if is-fpr?
                                                         (if (pair? fpool) (car fpool) '%xmm15)
                                                         (if (pair? gpool) (car gpool) '%r11))))
                                        (next-g (if (and (not existing) (not is-fpr?) (pair? gpool)) (cdr gpool) gpool))
                                        (next-f (if (and (not existing) is-fpr? (pair? fpool)) (cdr fpool) fpool))
                                        (wo? (memv idx wo-idxs))
                                        (rw? (memv idx rw-idxs)))
                                   (if (not existing)
                                       (begin
                                         (set-car! slot-scratch-box (cons (cons off scratch) (car slot-scratch-box)))
                                         (if (not wo?)
                                             (set-car! pre-box
                                                       (cons (if is-fpr?
                                                                 (list '%mov scratch cur)
                                                                 (list '%load scratch '%rsp off))
                                                             (car pre-box))))))
                                   (if (or wo? rw?)
                                       (set-car! post-box
                                                 (cons (if is-fpr?
                                                           (list '%mov cur scratch)
                                                           (list '%store '%rsp off scratch))
                                                       (car post-box))))
                                   (build (cdr xs) (+ idx 1) next-g next-f (cons scratch acc)))))))))
               (append (reverse (car pre-box))
                       (cons (cons op new-args)
                             (reverse (car post-box)))))))))))

(define (%mir-lower-edge-args tgt-lbl args block-param-locs vreg-map)
  (let ((entry (assq tgt-lbl block-param-locs)))
    (if (not entry)
        (cons #f (map (lambda (a) (%mir-resolve-opnd a vreg-map)) args))
        (let* ((param-locs (cdr entry))
               (resolved-args (map (lambda (a) (%mir-resolve-opnd a vreg-map)) args)))
          (cons #t (%mir-emit-parallel-moves param-locs resolved-args))))))

(define (%mir-lower-inst inst block-param-locs vreg-map tramps-box)
  (if (not (pair? inst))
      (list inst)
      (let ((op (car inst)))
        (cond
          ((eq? op '%block)
           (let* ((lbl (cadr inst))
                  (orig-params (caddr inst))
                  (body (cdddr inst))
                  (lowered-body
                   (let bloop ((bs body) (acc '()))
                     (if (null? bs)
                         (reverse acc)
                         (let ((ls (%mir-lower-inst (car bs) block-param-locs vreg-map tramps-box)))
                           (bloop (cdr bs) (append (reverse ls) acc))))))
                  (new-params (if (assq lbl block-param-locs)
                                  '()
                                  (map (lambda (p) (%mir-resolve-opnd p vreg-map)) orig-params))))
             (list (cons '%block (cons lbl (cons new-params lowered-body))))))
          ((eq? op '%jump)
           (let* ((tgt (cadr inst))
                  (args (if (pair? (cddr inst)) (caddr inst) '()))
                  (edge (%mir-lower-edge-args tgt args block-param-locs vreg-map)))
             (if (car edge)
                 (append (cdr edge) (list (list '%jump tgt)))
                 (if (pair? (cddr inst))
                     (list (list '%jump tgt (cdr edge)))
                     (list inst)))))
          ((eq? op '%jump-if-false)
           (let* ((raw-cond (cadr inst))
                  (cond-loc (%mir-resolve-opnd raw-cond vreg-map))
                  (pre-cond (if (%mir-stack-opnd? cond-loc)
                                (list (list '%load '%r10 '%rsp (cadr cond-loc)))
                                '()))
                  (cond-reg (if (%mir-stack-opnd? cond-loc) '%r10 cond-loc))
                  (tgt (caddr inst))
                  (args (if (pair? (cdddr inst)) (cadddr inst) '()))
                  (edge (%mir-lower-edge-args tgt args block-param-locs vreg-map)))
             (cond
               ((not (car edge))
                (append pre-cond
                        (list (if (pair? (cdddr inst))
                                  (list '%jump-if-false cond-reg tgt (cdr edge))
                                  (list '%jump-if-false cond-reg tgt)))))
               ((null? (cdr edge))
                (append pre-cond (list (list '%jump-if-false cond-reg tgt))))
               (else
                (let ((tramp (unique-label-sym "mir_tramp_")))
                  (set-car! tramps-box
                            (cons (cons '%block (cons tramp (cons '() (append (cdr edge) (list (list '%jump tgt))))))
                                  (car tramps-box)))
                  (append pre-cond (list (list '%jump-if-false cond-reg tramp))))))))
          ((eq? op '%jump-if)
           (let* ((raw-cond (cadr inst))
                  (cond-loc (%mir-resolve-opnd raw-cond vreg-map))
                  (pre-cond (if (%mir-stack-opnd? cond-loc)
                                (list (list '%load '%r10 '%rsp (cadr cond-loc)))
                                '()))
                  (cond-reg (if (%mir-stack-opnd? cond-loc) '%r10 cond-loc))
                  (t-lbl (caddr inst))
                  (t-args (cadddr inst))
                  (e-lbl (car (cddddr inst)))
                  (e-args (cadr (cddddr inst)))
                  (t-edge (%mir-lower-edge-args t-lbl t-args block-param-locs vreg-map))
                  (e-edge (%mir-lower-edge-args e-lbl e-args block-param-locs vreg-map))
                  (new-t (cond
                           ((and (car t-edge) (pair? (cdr t-edge)))
                            (let ((tr (unique-label-sym "mir_tramp_")))
                              (set-car! tramps-box
                                        (cons (cons '%block (cons tr (cons '() (append (cdr t-edge) (list (list '%jump t-lbl))))))
                                              (car tramps-box)))
                              (cons tr '())))
                           ((car t-edge) (cons t-lbl '()))
                           (else (cons t-lbl (cdr t-edge)))))
                  (new-e (cond
                           ((and (car e-edge) (pair? (cdr e-edge)))
                            (let ((tr (unique-label-sym "mir_tramp_")))
                              (set-car! tramps-box
                                        (cons (cons '%block (cons tr (cons '() (append (cdr e-edge) (list (list '%jump e-lbl))))))
                                              (car tramps-box)))
                              (cons tr '())))
                           ((car e-edge) (cons e-lbl '()))
                           (else (cons e-lbl (cdr e-edge))))))
             (append pre-cond
                     (list (list '%jump-if cond-reg (car new-t) (cdr new-t) (car new-e) (cdr new-e))))))
          (else
           (%mir-subst-vregs-with-spills inst vreg-map inst))))))

(define (%mir-lower-body-to-mach body orig-frame-size)
  (if (not (%mir-body-needs-mach-lowering? body))
      (cons body orig-frame-size)
      (let* ((analysis (%mir-analyze-body body orig-frame-size))
             (assigned (%mir-assign-vreg-locations analysis))
             (vreg-map (car assigned))
             (new-frame-size (cdr assigned))
             (raw-block-params (list-ref analysis 4))
             (block-param-locs
              (map (lambda (bp)
                     (cons (car bp)
                           (map (lambda (p) (%mir-resolve-opnd p vreg-map)) (cdr bp))))
                   raw-block-params))
             (tramps-box (cons '() '()))
             (lowered-insts
              (let loop ((is body) (acc '()))
                (if (null? is)
                    (reverse acc)
                    (let ((ls (%mir-lower-inst (car is) block-param-locs vreg-map tramps-box)))
                      (loop (cdr is) (append (reverse ls) acc))))))
             (all-tramps (reverse (car tramps-box)))
             (final-body (if (null? all-tramps) lowered-insts (append lowered-insts all-tramps))))
        (cons final-body new-frame-size))))

(define (%mir-lower-fn-or-main form)
  (if (not (pair? form))
      form
      (case (car form)
        ((%lir-function)
         (let* ((lbl (cadr form))
                (params-clause (assq 'params (cddr form)))
                (frame-clause (assq 'frame-size (cddr form)))
                (body-clause (assq 'body (cddr form)))
                (orig-fs (if (and frame-clause (pair? (cdr frame-clause))) (cadr frame-clause) 0))
                (orig-body (if body-clause (cdr body-clause) '())))
           (if (not (%mir-body-needs-mach-lowering? orig-body))
               form
               (let ((res (%mir-lower-body-to-mach orig-body orig-fs)))
                 (list '%lir-function
                       lbl
                       (if params-clause params-clause '(params ()))
                       (list 'frame-size (cdr res))
                       (cons 'body (car res)))))))
        ((%lir-main)
         (let* ((frame-clause (assq 'frame-size (cdr form)))
                (body-clause (assq 'body (cdr form)))
                (orig-fs (if (and frame-clause (pair? (cdr frame-clause))) (cadr frame-clause) 0))
                (orig-body (if body-clause (cdr body-clause) '())))
           (if (not (%mir-body-needs-mach-lowering? orig-body))
               form
               (let ((res (%mir-lower-body-to-mach orig-body orig-fs)))
                 (list '%lir-main
                       (list 'frame-size (cdr res))
                       (cons 'body (car res)))))))
        (else form))))

(define (lower-mir-ssa-to-mach-lir ir)
  (cond
    ((null? ir) '())
    ((and (pair? ir) (eq? (car ir) '%lir-program))
     (let ((new-clauses
            (map (lambda (clause)
                   (if (not (pair? clause))
                       clause
                       (case (car clause)
                         ((%lir-functions)
                          (cons '%lir-functions (map %mir-lower-fn-or-main (cdr clause))))
                         ((%lir-main)
                          (%mir-lower-fn-or-main clause))
                         (else clause))))
                 (cdr ir))))
       (if (equal? new-clauses (cdr ir))
           ir
           (cons '%lir-program new-clauses))))
    ((and (pair? ir) (memq (car ir) '(%lir-function %lir-main)))
     (%mir-lower-fn-or-main ir))
    ((pair? ir)
     (car (%mir-lower-body-to-mach ir 0)))
    (else ir)))
