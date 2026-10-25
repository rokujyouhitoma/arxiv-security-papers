;;; =======================================================================
;;; ULisp Compiler: Generic Dataflow Analysis Framework & Lattice Engine
;;; Conforms to DSN-33 Architecture Specification & Issue #599
;;; Based on Monotone Framework (Kam & Ullman 1977, Kildall 1973)
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; Part 1: Set Operations & Equality Helpers
;;; -----------------------------------------------------------------------

(define (dataflow-set-equal? s1 s2)
  (and (= (length s1) (length s2))
       (dataflow-set-subset? s1 s2)))

(define (dataflow-set-subset? s1 s2)
  (cond
    ((null? s1) #t)
    ((memq (car s1) s2)
     (dataflow-set-subset? (cdr s1) s2))
    (else #f)))

(define (dataflow-set-intersect s1 s2)
  (cond
    ((null? s1) '())
    ((null? s2) '())
    ((memq (car s1) s2)
     (cons (car s1) (dataflow-set-intersect (cdr s1) s2)))
    (else
     (dataflow-set-intersect (cdr s1) s2))))

;;; -----------------------------------------------------------------------
;;; Part 2: Semi-Lattice Record & Built-in Lattices
;;; -----------------------------------------------------------------------

;;; Lattice record:
;;;   (list 'lattice name bottom top leq? join meet)
(define (make-lattice name bottom top leq? join meet)
  (list 'lattice name bottom top leq? join meet))

(define (lattice? obj)
  (and (pair? obj) (eq? (car obj) 'lattice)))

(define (lattice-name l) (cadr l))
(define (lattice-bottom l) (caddr l))
(define (lattice-top l) (cadddr l))
(define (lattice-leq? l a b) ((car (cddddr l)) a b))
(define (lattice-join l a b) ((cadr (cddddr l)) a b))
(define (lattice-meet l a b) ((caddr (cddddr l)) a b))

;;; Built-in Sentinel symbols
(define *df-bottom* '*df-bottom*)
(define *df-top* '*df-top*)

(define (df-bottom? x) (eq? x *df-bottom*))
(define (df-top? x) (eq? x *df-top*))

;;; 2.1 Boolean Lattice
;;; Bottom = #f, Top = #t
;;; #f <= #f, #f <= #t, #t <= #t
;;; Join = or, Meet = and
(define (make-boolean-lattice name)
  (make-lattice
   name
   #f
   #t
   (lambda (a b)
     (if a (and b #t) #t))
   (lambda (a b)
     (or a b))
   (lambda (a b)
     (and a b))))

;;; 2.2 Flat Lattice (Constants / Single values)
;;; Elements: *df-bottom*, constants c, *df-top*
;;; *df-bottom* <= c <= *df-top*
;;; If c1 != c2, c1 join c2 = *df-top*
(define (make-flat-lattice name eq-fn)
  (make-lattice
   name
   *df-bottom*
   *df-top*
   (lambda (a b)
     (cond
       ((eq? a *df-bottom*) #t)
       ((eq? b *df-top*) #t)
       ((and (not (eq? a *df-top*)) (not (eq? b *df-bottom*)))
        (eq-fn a b))
       (else #f)))
   (lambda (a b)
     (cond
       ((eq? a *df-bottom*) b)
       ((eq? b *df-bottom*) a)
       ((or (eq? a *df-top*) (eq? b *df-top*)) *df-top*)
       ((eq-fn a b) a)
       (else *df-top*)))
   (lambda (a b)
     (cond
       ((eq? a *df-top*) b)
       ((eq? b *df-top*) a)
       ((or (eq? a *df-bottom*) (eq? b *df-bottom*)) *df-bottom*)
       ((eq-fn a b) a)
       (else *df-bottom*)))))

;;; 2.3 Powerset Lattice (Set of symbols / expressions)
;;; Bottom = '(), Top = universe-or-top
;;; Join = set-union, Meet = dataflow-set-intersect
;;; Order: a <= b iff a subseteq b
(define (make-powerset-lattice name universe)
  (make-lattice
   name
   '()
   (if universe universe *df-top*)
   (lambda (a b)
     (cond
       ((eq? b *df-top*) #t)
       ((eq? a *df-top*) (eq? b *df-top*))
       (else (dataflow-set-subset? a b))))
   (lambda (a b)
     (cond
       ((eq? a *df-top*) *df-top*)
       ((eq? b *df-top*) *df-top*)
       (else (set-union a b))))
   (lambda (a b)
     (cond
       ((eq? a *df-top*) b)
       ((eq? b *df-top*) a)
       (else (dataflow-set-intersect a b))))))

;;; 2.4 Map / Environment Lattice (Var -> Value Lattice)
;;; Represents mappings from symbols to elements of an inner lattice.
;;; An environment is an alist: ((var . val) ...)
;;; Unbound variable is treated as (lattice-bottom val-lat).
(define (make-map-lattice name val-lat)
  (let* ((v-bot (lattice-bottom val-lat))
         (lookup-val (lambda (env k)
                       (let ((entry (assq k env)))
                         (if entry (cdr entry) v-bot)))))
    (make-lattice
     name
     '()
     *df-top*
     ;; leq? env1 env2
     (lambda (env1 env2)
       (cond
         ((eq? env2 *df-top*) #t)
         ((eq? env1 *df-top*) (eq? env2 *df-top*))
         (else
          (let loop ((entries env1))
            (if (null? entries)
                #t
                (let* ((k (caar entries))
                       (v1 (cdar entries))
                       (v2 (lookup-val env2 k)))
                  (if (lattice-leq? val-lat v1 v2)
                      (loop (cdr entries))
                      #f)))))))
     ;; join env1 env2
     (lambda (env1 env2)
       (cond
         ((eq? env1 *df-top*) *df-top*)
         ((eq? env2 *df-top*) *df-top*)
         (else
          (let* ((all-keys (set-union (map car* env1) (map car* env2))))
            (let loop ((keys all-keys) (acc '()))
              (if (null? keys)
                  acc
                  (let* ((k (car keys))
                         (v1 (lookup-val env1 k))
                         (v2 (lookup-val env2 k))
                         (v-joined (lattice-join val-lat v1 v2)))
                    ;; If joined value is bottom, omit from map for compactness
                    (if (lattice-leq? val-lat v-joined v-bot)
                        (loop (cdr keys) acc)
                        (loop (cdr keys) (cons (cons k v-joined) acc))))))))))
     ;; meet env1 env2
     (lambda (env1 env2)
       (cond
         ((eq? env1 *df-top*) env2)
         ((eq? env2 *df-top*) env1)
         (else
          (let* ((all-keys (set-union (map car* env1) (map car* env2))))
            (let loop ((keys all-keys) (acc '()))
              (if (null? keys)
                  acc
                  (let* ((k (car keys))
                         (v1 (lookup-val env1 k))
                         (v2 (lookup-val env2 k))
                         (v-met (lattice-meet val-lat v1 v2)))
                    (if (lattice-leq? val-lat v-met v-bot)
                        (loop (cdr keys) acc)
                        (loop (cdr keys) (cons (cons k v-met) acc)))))))))))))

;;; 2.5 Product Lattice (Tuple of two lattices)
(define (make-product-lattice name lat1 lat2)
  (make-lattice
   name
   (cons (lattice-bottom lat1) (lattice-bottom lat2))
   (cons (lattice-top lat1) (lattice-top lat2))
   (lambda (p1 p2)
     (and (lattice-leq? lat1 (car p1) (car p2))
          (lattice-leq? lat2 (cdr p1) (cdr p2))))
   (lambda (p1 p2)
     (cons (lattice-join lat1 (car p1) (car p2))
           (lattice-join lat2 (cdr p1) (cdr p2))))
   (lambda (p1 p2)
     (cons (lattice-meet lat1 (car p1) (car p2))
           (lattice-meet lat2 (cdr p1) (cdr p2))))))

;;; -----------------------------------------------------------------------
;;; Part 3: Dataflow Problem Specification
;;; -----------------------------------------------------------------------

;;; Problem record:
;;;   (list 'dataflow-problem name direction lattice boundary-val init-val transfer-fn)
(define (make-dataflow-problem name direction lattice boundary-val init-val transfer-fn)
  (list 'dataflow-problem name direction lattice boundary-val init-val transfer-fn))

(define (dataflow-problem? obj)
  (and (pair? obj) (eq? (car obj) 'dataflow-problem)))

(define (df-problem-name p) (cadr p))
(define (df-problem-direction p) (caddr p))
(define (df-problem-lattice p) (cadddr p))
(define (df-problem-boundary-val p) (car (cddddr p)))
(define (df-problem-init-val p) (cadr (cddddr p)))
(define (df-problem-transfer-fn p) (caddr (cddddr p)))

;;; -----------------------------------------------------------------------
;;; Part 4: Generic Worklist Fixed-Point Engine
;;; -----------------------------------------------------------------------

;;; Max iteration safety bound to prevent infinite compilation loops
(define *dataflow-max-iterations* (cons 2000 '()))

(define (dataflow-get-max-iterations)
  (car *dataflow-max-iterations*))

(define (dataflow-set-max-iterations! limit)
  (set-car! *dataflow-max-iterations* limit))

;;; Lookup state in alist ((node . state) ...)
(define (df-lookup-state table node default-val)
  (let ((entry (assq node table)))
    (if entry (cdr entry) default-val)))

;;; Update or add state in alist
(define (df-set-state table node new-val)
  (let loop ((entries table) (acc '()))
    (cond
      ((null? entries)
       (cons (cons node new-val) acc))
      ((eq? (caar entries) node)
       (append (cdr entries) (cons (cons node new-val) acc)))
      (else
       (loop (cdr entries) (cons (car entries) acc))))))

;;; Equality of lattice values using leq in both directions
(define (df-lattice-equal? lat a b)
  (and (lattice-leq? lat a b)
       (lattice-leq? lat b a)))

;;; Worklist Solver
;;; Arguments:
;;;   problem:      dataflow-problem
;;;   nodes:        list of node symbols/identifiers
;;;   entry-nodes:  list of entry/source nodes (for forward) or exit nodes (for backward)
;;;   preds-fn:     (lambda (node) -> list of predecessor nodes)
;;;   succs-fn:     (lambda (node) -> list of successor nodes)
;;; Returns:
;;;   Result table: ((node (in . in-val) (out . out-val)) ...)
(define (dataflow-analyze problem nodes entry-nodes preds-fn succs-fn)
  (let* ((lat (df-problem-lattice problem))
         (direction (df-problem-direction problem))
         (forward? (eq? direction 'forward))
         (boundary-val (df-problem-boundary-val problem))
         (init-val (df-problem-init-val problem))
         (transfer-fn (df-problem-transfer-fn problem))
         (max-iters (dataflow-get-max-iterations)))

    ;; Initialize in-table and out-table
    ;; For forward:
    ;;   in-table of entry-nodes = boundary-val, others = init-val
    ;;   out-table of all nodes = init-val
    ;; For backward:
    ;;   out-table of exit-nodes = boundary-val, others = init-val
    ;;   in-table of all nodes = init-val
    (let* ((init-tables
            (let loop ((ns nodes) (in-acc '()) (out-acc '()))
              (if (null? ns)
                  (cons in-acc out-acc)
                  (let* ((n (car ns))
                         (is-boundary? (if (memq n entry-nodes) #t #f)))
                    (if forward?
                        (loop (cdr ns)
                              (cons (cons n (if is-boundary? boundary-val init-val)) in-acc)
                              (cons (cons n init-val) out-acc))
                        (loop (cdr ns)
                              (cons (cons n init-val) in-acc)
                              (cons (cons n (if is-boundary? boundary-val init-val)) out-acc)))))))
           (initial-in-table (car init-tables))
           (initial-out-table (cdr init-tables))
           ;; Worklist initially contains all nodes
           (initial-worklist nodes))

      ;; Worklist iteration loop
      (let solve-loop ((worklist initial-worklist)
                       (in-table initial-in-table)
                       (out-table initial-out-table)
                       (iter-count 0))
        (cond
          ((null? worklist)
           ;; Fixed-point reached: construct result table
           (let loop ((ns nodes) (res '()))
             (if (null? ns)
                 (reverse res)
                 (let* ((n (car ns))
                        (in-v (df-lookup-state in-table n init-val))
                        (out-v (df-lookup-state out-table n init-val)))
                   (loop (cdr ns)
                         (cons (list n (cons 'in in-v) (cons 'out out-v)) res))))))

          ((>= iter-count max-iters)
           ;; Exceeded maximum iterations: log diagnostic and return best-effort
           (let loop ((ns nodes) (res '()))
             (if (null? ns)
                 (reverse res)
                 (let* ((n (car ns))
                        (in-v (df-lookup-state in-table n (lattice-top lat)))
                        (out-v (df-lookup-state out-table n (lattice-top lat))))
                   (loop (cdr ns)
                         (cons (list n (cons 'in in-v) (cons 'out out-v)) res))))))

          (else
           (let* ((n (car worklist))
                  (rest-wl (cdr worklist)))
             (if forward?
                 ;; --- FORWARD ANALYSIS ---
                 (let* ((preds (preds-fn n))
                        ;; in[n] = join_{p in preds} out[p] (or boundary-val if entry)
                        (new-in
                         (if (memq n entry-nodes)
                             (if (null? preds)
                                 boundary-val
                                 (let loop-p ((ps preds) (acc boundary-val))
                                   (if (null? ps) acc
                                       (let ((p-out (df-lookup-state out-table (car ps) init-val)))
                                         (loop-p (cdr ps) (lattice-join lat acc p-out))))))
                             (let loop-p ((ps preds) (acc init-val))
                               (if (null? ps) acc
                                   (let ((p-out (df-lookup-state out-table (car ps) init-val)))
                                     (loop-p (cdr ps) (lattice-join lat acc p-out)))))))
                        ;; out[n] = transfer(n, in[n])
                        (new-out (transfer-fn n new-in))
                        (old-out (df-lookup-state out-table n init-val)))
                   (if (df-lattice-equal? lat old-out new-out)
                       ;; No change in out[n], continue
                       (solve-loop rest-wl
                                   (df-set-state in-table n new-in)
                                   out-table
                                   (+ iter-count 1))
                       ;; out[n] changed: add all successors to worklist
                       (let* ((succs (succs-fn n))
                              (new-wl (let add-loop ((ss succs) (cur-wl rest-wl))
                                        (cond
                                          ((null? ss) cur-wl)
                                          ((memq (car ss) cur-wl) (add-loop (cdr ss) cur-wl))
                                          (else (add-loop (cdr ss) (cons (car ss) cur-wl)))))))
                         (solve-loop new-wl
                                     (df-set-state in-table n new-in)
                                     (df-set-state out-table n new-out)
                                     (+ iter-count 1)))))

                 ;; --- BACKWARD ANALYSIS ---
                 (let* ((succs (succs-fn n))
                        ;; out[n] = join_{s in succs} in[s] (or boundary-val if exit)
                        (new-out
                         (if (memq n entry-nodes)
                             (if (null? succs)
                                 boundary-val
                                 (let loop-s ((ss succs) (acc boundary-val))
                                   (if (null? ss) acc
                                       (let ((s-in (df-lookup-state in-table (car ss) init-val)))
                                         (loop-s (cdr ss) (lattice-join lat acc s-in))))))
                             (let loop-s ((ss succs) (acc init-val))
                               (if (null? ss) acc
                                   (let ((s-in (df-lookup-state in-table (car ss) init-val)))
                                     (loop-s (cdr ss) (lattice-join lat acc s-in)))))))
                        ;; in[n] = transfer(n, out[n])
                        (new-in (transfer-fn n new-out))
                        (old-in (df-lookup-state in-table n init-val)))
                   (if (df-lattice-equal? lat old-in new-in)
                       ;; No change in in[n], continue
                       (solve-loop rest-wl
                                   in-table
                                   (df-set-state out-table n new-out)
                                   (+ iter-count 1))
                       ;; in[n] changed: add all predecessors to worklist
                       (let* ((preds (preds-fn n))
                              (new-wl (let add-loop ((ps preds) (cur-wl rest-wl))
                                        (cond
                                          ((null? ps) cur-wl)
                                          ((memq (car ps) cur-wl) (add-loop (cdr ps) cur-wl))
                                          (else (add-loop (cdr ps) (cons (car ps) cur-wl)))))))
                         (solve-loop new-wl
                                     (df-set-state in-table n new-in)
                                     (df-set-state out-table n new-out)
                                     (+ iter-count 1)))))))))))))

;;; -----------------------------------------------------------------------
;;; Part 5: Result Accessors & Query Helpers
;;; -----------------------------------------------------------------------

(define (dataflow-result-in results node)
  (let ((entry (assq node results)))
    (if entry
        (let ((in-pair (assq 'in (cdr entry))))
          (if in-pair (cdr in-pair) #f))
        #f)))

(define (dataflow-result-out results node)
  (let ((entry (assq node results)))
    (if entry
        (let ((out-pair (assq 'out (cdr entry))))
          (if out-pair (cdr out-pair) #f))
        #f)))

;;; -----------------------------------------------------------------------
;;; Part 6: High-Level Dataflow Problem Builders
;;; -----------------------------------------------------------------------

;;; 6.1 Liveness Analysis Problem (Backward)
;;; Lattice: Powerset of variables
;;; Transfer: In[n] = (Out[n] \ Def[n]) U Use[n]
(define (make-liveness-problem name def-use-table)
  (let ((lat (make-powerset-lattice (string->symbol (string-append (symbol->string name) "-liveness")) #f)))
    (make-dataflow-problem
     name
     'backward
     lat
     '()    ; boundary-val: exit has no live variables
     '()    ; init-val: bottom is empty set
     (lambda (node out-state)
       (let ((du (assq node def-use-table)))
         (if du
             (let* ((defs (cadr du))
                    (uses (caddr du)))
               (set-union (set-diff out-state defs) uses))
             out-state))))))

;;; 6.2 Reaching Definitions Problem (Forward)
;;; Lattice: Powerset of definition IDs
;;; Transfer: Out[n] = Gen[n] U (In[n] \ Kill[n])
(define (make-reaching-defs-problem name gen-kill-table)
  (let ((lat (make-powerset-lattice (string->symbol (string-append (symbol->string name) "-reaching")) #f)))
    (make-dataflow-problem
     name
     'forward
     lat
     '()    ; boundary-val: entry has no definitions
     '()    ; init-val: bottom is empty set
     (lambda (node in-state)
       (let ((gk (assq node gen-kill-table)))
         (if gk
             (let* ((gen (cadr gk))
                    (kill (caddr gk)))
               (set-union gen (set-diff in-state kill)))
             in-state))))))

;;; 6.3 Constant Propagation Problem (Forward)
;;; Lattice: Map from Var -> Flat Lattice
(define (make-constant-propagation-problem name const-transfer-fn)
  (let* ((flat-lat (make-flat-lattice 'const-val equal?))
         (map-lat (make-map-lattice 'const-env flat-lat)))
    (make-dataflow-problem
     name
     'forward
     map-lat
     '()    ; boundary-val: entry environment is empty
     '()    ; init-val: empty
     const-transfer-fn)))
