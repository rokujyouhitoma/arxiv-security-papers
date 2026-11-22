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
