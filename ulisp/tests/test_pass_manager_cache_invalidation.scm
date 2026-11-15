;;; =======================================================================
;;; Unit Test Suite: Automatic Analysis Cache Invalidation & Fixpoint Pass
;;; Conforms to Issue #840 (Pass Analysis Contracts & Dependency DAG)
;;; =======================================================================

(define (tci-stat-val key)
  (let ((p (assq key (analysis-cache-stats))))
    (if p (cdr p) 0)))

(define (tci-assert-error-tag label expected-tag thunk)
  (let ((caught #f))
    (guard (ex
            (else
             (set! caught ex)))
      (thunk))
    (assert-true label
                 (and (pair? caught)
                      (eq? (car caught) expected-tag)))))

(define (tci-assert-any-error label thunk)
  (let ((errored #f))
    (guard (ex
            (else
             (set! errored #t)))
      (thunk))
    (assert-true label errored)))

(test-begin "Nanopass Analysis Cache Invalidation & Fixpoint Suite (#840)")

;;; -----------------------------------------------------------------------
;;; Group 1: Analysis Property Registry & On-Demand Cache Hit/Miss
;;; -----------------------------------------------------------------------
(print-group "=== Group 1: Registry & On-Demand Cache Hit/Miss ===")

(reset-analysis-cache!)
(reset-pass-analysis-contracts!)
(init-default-analysis-properties!)

(assert-true "built-in cfg-dominators registered"
             (and (lookup-analysis-property 'cfg-dominators) #t))
(assert-true "built-in variable-liveness registered"
             (and (lookup-analysis-property 'variable-liveness) #t))
(assert-true "built-in reaching-defs registered"
             (and (lookup-analysis-property 'reaching-defs) #t))
(assert-true "built-in alias-sets registered"
             (and (lookup-analysis-property 'alias-sets) #t))
(assert-true "built-in free-vars registered"
             (and (lookup-analysis-property 'free-vars) #t))
(assert-true "built-in use-counts registered"
             (and (lookup-analysis-property 'use-counts) #t))
(assert-true "built-in femto-attrs registered"
             (and (lookup-analysis-property 'femto-attrs) #t))
(assert-true "built-in term-hash-consing registered"
             (and (lookup-analysis-property 'term-hash-consing) #t))

(let* ((sample-ast '(let ((p (cons 1 2)) (q 3)) (+ q (car p))))
       (aliases (require-analysis 'alias-sets sample-ast)))
  (assert-true "built-in alias-sets triggers reaching-defs dependency"
               (analysis-valid? 'reaching-defs sample-ast))
  (assert-true "built-in alias-sets returns pair list"
               (list? aliases)))

(define *g1-prop-a-computes* 0)
(register-analysis-property!
  'tci-prop-a
  (lambda (ast)
    (set! *g1-prop-a-computes* (+ *g1-prop-a-computes* 1))
    (list 'prop-a ast *g1-prop-a-computes*))
  '()
  "Test property A")

(let ((ast-1 (list 'program 'x 10))
      (ast-2 (list 'program 'x 10)))
  (assert-false "tci-prop-a initially invalid" (analysis-valid? 'tci-prop-a))
  (assert-false "get-cached-analysis returns #f when invalid"
                (get-cached-analysis 'tci-prop-a))

  ;; 1st demand -> miss + compute
  (let ((v1 (require-analysis 'tci-prop-a ast-1)))
    (assert-equal "first require-analysis computes once" 1 *g1-prop-a-computes*)
    (assert-equal "analysis-compute-count = 1" 1 (analysis-compute-count 'tci-prop-a))
    (assert-equal "analysis-hit-count = 0" 0 (analysis-hit-count 'tci-prop-a))
    (assert-true "analysis-valid? #t for ast-1" (analysis-valid? 'tci-prop-a ast-1))
    (assert-equal "get-cached-analysis matches computed value" v1 (get-cached-analysis 'tci-prop-a)))

  ;; 2nd demand with eq? ast-1 -> cache hit
  (let ((v2 (require-analysis 'tci-prop-a ast-1)))
    (assert-equal "second require-analysis hits cache" 1 *g1-prop-a-computes*)
    (assert-equal "analysis-hit-count = 1" 1 (analysis-hit-count 'tci-prop-a))
    (assert-equal "cached value preserved" (list 'prop-a ast-1 1) v2))

  ;; 3rd demand with distinct AST identity (not eq?) -> recompute
  (let ((v3 (require-analysis 'tci-prop-a ast-2)))
    (assert-equal "distinct eq? AST invalidates and recomputes" 2 *g1-prop-a-computes*)
    (assert-equal "analysis-compute-count = 2" 2 (analysis-compute-count 'tci-prop-a))
    (assert-true "analysis-valid? #t for ast-2" (analysis-valid? 'tci-prop-a ast-2))
    (assert-false "analysis-valid? #f for stale ast-1" (analysis-valid? 'tci-prop-a ast-1))
    (assert-equal "new computed value returned" (list 'prop-a ast-2 2) v3))

  ;; Explicit invalidation
  (invalidate-analysis! 'tci-prop-a)
  (assert-false "analysis-valid? #f after explicit invalidate-analysis!"
                (analysis-valid? 'tci-prop-a))
  (assert-false "get-cached-analysis #f after invalidation"
                (get-cached-analysis 'tci-prop-a)))

;;; -----------------------------------------------------------------------
;;; Group 2: Declarative define-pass Contracts & Pipeline Execution
;;; -----------------------------------------------------------------------
(print-group "=== Group 2: define-pass Declarative Contracts ===")

(reset-analysis-cache!)
(reset-pass-analysis-contracts!)
(init-default-analysis-properties!)

(define *g2-live-cnt* 0)
(define *g2-dom-cnt* 0)

(register-analysis-property!
  'tci-live
  (lambda (ast)
    (set! *g2-live-cnt* (+ *g2-live-cnt* 1))
    (list 'live *g2-live-cnt* ast))
  '()
  "Test liveness analysis")

(register-analysis-property!
  'tci-dom
  (lambda (ast)
    (set! *g2-dom-cnt* (+ *g2-dom-cnt* 1))
    (list 'dom *g2-dom-cnt*))
  '()
  "Test dominator analysis")

(define-language L_tci
  (terminals
    (symbol (x))
    (constant (c)))
  (Expr (e)
    x
    c
    (tagged x e1)
    (wrap x e1)
    (e0 e1 ...)))

(define-pass tci-np-readonly
  : L_tci (ir) -> L_tci ()
  (requires tci-live tci-dom)
  (preserves all)
  (Expr : Expr (ir) -> Expr ()
    ((tagged ,x ,e1) ir)
    ((wrap ,x ,e1) ir)))

(define-pass tci-np-retag
  :requires (tci-live)
  :preserves (tci-dom)
  :invalidates (tci-live)
  : L_tci (ir) -> L_tci ()
  (Expr : Expr (ir) -> Expr ()
    ((tagged ,x ,e1)
     (list 'wrap x (Expr e1)))))

(assert-equal "define-pass clause requires parsed"
              '(tci-live tci-dom)
              (pass-requires-analyses tci-np-readonly))
(assert-equal "define-pass clause preserves parsed"
              '(all)
              (pass-preserves-analyses tci-np-readonly))
(assert-equal "define-pass header :requires parsed"
              '(tci-live)
              (pass-requires-analyses tci-np-retag))
(assert-equal "define-pass header :preserves parsed"
              '(tci-dom)
              (pass-preserves-analyses tci-np-retag))
(assert-equal "define-pass header :invalidates parsed"
              '(tci-live)
              (pass-invalidates-analyses tci-np-retag))

(let ((ir-1 '(tagged foo 42)))
  ;; Standalone call triggers pre/post analysis hooks
  (let ((r1 (tci-np-readonly ir-1)))
    (assert-equal "standalone readonly returns equal IR" ir-1 r1)
    (assert-equal "readonly computes tci-live once" 1 *g2-live-cnt*)
    (assert-equal "readonly computes tci-dom once" 1 *g2-dom-cnt*)
    (assert-true "tci-live valid after readonly" (analysis-valid? 'tci-live r1))
    (assert-true "tci-dom valid after readonly" (analysis-valid? 'tci-dom r1)))

  ;; Second standalone call hits cache for both
  (let ((r2 (tci-np-readonly ir-1)))
    (assert-equal "second readonly call keeps tci-live cached" 1 *g2-live-cnt*)
    (assert-equal "second readonly call keeps tci-dom cached" 1 *g2-dom-cnt*))

  ;; Run mutating pass inside pipeline runner (pass-descriptor wraps define-pass)
  (let* ((retag-desc (make-pass-descriptor 'tci-retag "Retag" 'frontend 1
                                           tci-np-retag #f 'L_tci 'L_tci '() #f))
         (ro-desc (make-pass-descriptor 'tci-ro "Readonly" 'frontend 0
                                        tci-np-readonly #f 'L_tci 'L_tci '() #f))
         (ir-2 (run-single-pass retag-desc ir-1 #f #f)))
    (assert-equal "retag pass transformed IR" '(wrap foo 42) ir-2)
    (assert-equal "retag reused cached tci-live before pass" 1 *g2-live-cnt*)
    (assert-false "tci-live invalidated after retag pass" (analysis-valid? 'tci-live))
    (assert-true "tci-dom preserved across retag pass for new ir-2"
                 (analysis-valid? 'tci-dom ir-2))
    (assert-equal "tci-live invalidation count incremented" 1
                  (analysis-invalidation-count 'tci-live))
    ;; Follow-up pass requiring both tci-live and tci-dom recomputes ONLY tci-live!
    (run-single-pass ro-desc ir-2 #f #f)
    (assert-equal "follow-up pass recomputed tci-live" 2 *g2-live-cnt*)
    (assert-equal "follow-up pass did NOT recompute preserved tci-dom" 1 *g2-dom-cnt*)))

;;; -----------------------------------------------------------------------
;;; Group 3: Transitive Invalidation, Cycles, Fail-Safe & Isolation
;;; -----------------------------------------------------------------------
(print-group "=== Group 3: Transitive DAG, THREAT-840-1/2/3 ===")

(reset-analysis-cache!)
(init-default-analysis-properties!)

(define *g3-base* 0)
(define *g3-mid* 0)
(define *g3-top* 0)

(register-analysis-property! 'tci-base
  (lambda (ast) (set! *g3-base* (+ *g3-base* 1)) (list 'base *g3-base*))
  '() "Base analysis")
(register-analysis-property! 'tci-mid
  (lambda (ast) (set! *g3-mid* (+ *g3-mid* 1))
          (list 'mid *g3-mid* (require-analysis 'tci-base ast)))
  '(tci-base) "Mid analysis depending on base")
(register-analysis-property! 'tci-top
  (lambda (ast) (set! *g3-top* (+ *g3-top* 1))
          (list 'top *g3-top* (require-analysis 'tci-mid ast)))
  '(tci-mid) "Top analysis depending on mid")

(let ((dag-ast '(dag-root 1 2)))
  (require-analysis 'tci-top dag-ast)
  (assert-equal "transitive demand computed base=1" 1 *g3-base*)
  (assert-equal "transitive demand computed mid=1" 1 *g3-mid*)
  (assert-equal "transitive demand computed top=1" 1 *g3-top*)
  (assert-true "base valid" (analysis-valid? 'tci-base dag-ast))
  (assert-true "mid valid" (analysis-valid? 'tci-mid dag-ast))
  (assert-true "top valid" (analysis-valid? 'tci-top dag-ast))

  ;; Invalidating base must transitively invalidate mid and top!
  (invalidate-analysis! 'tci-base)
  (assert-false "base invalidated" (analysis-valid? 'tci-base))
  (assert-false "mid transitively invalidated" (analysis-valid? 'tci-mid))
  (assert-false "top transitively invalidated" (analysis-valid? 'tci-top))

  ;; Demanding top recomputes all 3 cleanly
  (require-analysis 'tci-top dag-ast)
  (assert-equal "recompute after transitive inv base=2" 2 *g3-base*)
  (assert-equal "recompute after transitive inv mid=2" 2 *g3-mid*)
  (assert-equal "recompute after transitive inv top=2" 2 *g3-top*))

;; THREAT-840-2: Dependency cycle detection
(tci-assert-error-tag "self-cycle raises analysis-cycle-error"
                      'analysis-cycle-error
                      (lambda ()
                        (register-analysis-property! 'tci-self-cyc
                          (lambda (ast) ast)
                          '(tci-self-cyc)
                          "Self cycle")))

(register-analysis-property! 'tci-cyc-x (lambda (ast) ast) '() "Cycle node X")
(register-analysis-property! 'tci-cyc-y (lambda (ast) ast) '(tci-cyc-x) "Cycle node Y")
(tci-assert-error-tag "2-node cycle raises analysis-cycle-error"
                      'analysis-cycle-error
                      (lambda ()
                        (register-analysis-property! 'tci-cyc-x
                          (lambda (ast) ast)
                          '(tci-cyc-y)
                          "Cycle back-edge X -> Y -> X")))

;; THREAT-840-1: Fail-safe invalidation on AST change & identity eq? preservation
(let* ((ast-fail '(orig a b))
       (mutating-no-contract (make-pass-descriptor 'tci-mut-nocontract "Mutate No Contract"
                               'frontend 0 (lambda (a) (cons 'changed a)) #f 'L_any 'L_any '() #f))
       (noop-no-contract (make-pass-descriptor 'tci-noop-nocontract "Noop No Contract"
                             'frontend 0 (lambda (a) a) #f 'L_any 'L_any '() #f))
       (conflicting-contract (make-pass-descriptor 'tci-conflict "Conflict"
                               'frontend 0 (lambda (a) (cons 'chg2 a)) #f 'L_any 'L_any '() #f
                               ':preserves '(tci-base) ':invalidates '(tci-base))))
  (require-analysis 'tci-top ast-fail)
  ;; eq? unchanged AST preserves analyses even with no :preserves contract
  (run-single-pass noop-no-contract ast-fail #f #f)
  (assert-true "eq? unchanged IR preserves tci-base even without contract"
               (analysis-valid? 'tci-base ast-fail))
  (assert-true "eq? unchanged IR preserves tci-top even without contract"
               (analysis-valid? 'tci-top ast-fail))

  ;; Mutated AST without contract fail-safe invalidates all cached properties
  (run-single-pass mutating-no-contract ast-fail #f #f)
  (assert-false "THREAT-840-1: mutating pass without contract invalidates tci-base"
                (analysis-valid? 'tci-base))
  (assert-false "THREAT-840-1: mutating pass without contract invalidates tci-top"
                (analysis-valid? 'tci-top))

  ;; Conflicting preserves + invalidates on same property -> invalidates wins (fail-safe)
  (require-analysis 'tci-base ast-fail)
  (assert-true "tci-base recomputed before conflict test" (analysis-valid? 'tci-base ast-fail))
  (run-single-pass conflicting-contract ast-fail #f #f)
  (assert-false "THREAT-840-1: explicit invalidates overrides preserves on conflict"
                (analysis-valid? 'tci-base)))

;; THREAT-840-3: Cross-pipeline cache isolation
(init-default-pass-registry!)
(register-pass!
  (make-pass-descriptor 'pass-tci-iso-check "Isolation Check" 'frontend 0
    (lambda (ast) ast) #f 'L_any 'L_any '() #f))
(register-pipeline!
  (make-pipeline-descriptor 'tci-iso-pipeline "Isolation Pipeline"
    '(pass-tci-iso-check) 'L_any '()))

(let ((stale-val (require-analysis 'tci-base '(module-a 1))))
  (assert-true "tci-base valid before pipeline run" (analysis-valid? 'tci-base))
  (run-named-pipeline 'tci-iso-pipeline '(module-b 2) #f #f)
  (assert-false "THREAT-840-3: run-named-pipeline resets analysis cache across pipelines"
                (analysis-valid? 'tci-base)))

;;; -----------------------------------------------------------------------
;;; Group 4: Femtopass Attribute Preservation Across Passes
;;; -----------------------------------------------------------------------
(print-group "=== Group 4: Femtopass Cache Preservation ===")

(reset-analysis-cache!)
(femto-cache-reset!)

(let* ((shared-node '(node-payload 123))
       (femto-computes 0)
       (probe (lambda (n)
                (femto-get-cached-attr 'tci-femto-cost n
                  (lambda ()
                    (set! femto-computes (+ femto-computes 1))
                    77))))
       (pass-unpreserved (make-pass-descriptor 'tci-f-unpres "Femto Unpreserved" 'frontend 0
                           (lambda (a) (cons 'u a)) #f 'L_any 'L_any '() #f))
       (pass-preserves-femto (make-pass-descriptor 'tci-f-pres "Femto Preserved" 'frontend 0
                               (lambda (a) (cons 'p a)) #f 'L_any 'L_any '() #f
                               ':preserves '(femto-attrs)))
       (pass-inv-femto (make-pass-descriptor 'tci-f-inv "Femto Explicitly Invalidated" 'frontend 0
                         (lambda (a) (cons 'i a)) #f 'L_any 'L_any '() #f
                         ':preserves '(all) ':invalidates '(femto-attrs))))
  (assert-equal "initial femto probe returns 77" 77 (probe shared-node))
  (assert-equal "initial femto probe computed once" 1 femto-computes)
  (assert-equal "immediate femto probe hits cache" 77 (probe shared-node))
  (assert-equal "femto-computes stays 1" 1 femto-computes)

  ;; Unpreserved pass resets femto cache
  (run-single-pass pass-unpreserved shared-node #f #f)
  (probe shared-node)
  (assert-equal "unpreserved pass triggers femto cache reset (computes=2)" 2 femto-computes)

  ;; Preserved pass keeps femto cache intact!
  (run-single-pass pass-preserves-femto shared-node #f #f)
  (assert-equal "preserved femto cache returns 77 on shared-node" 77 (probe shared-node))
  (assert-equal "preserved pass did NOT reset femto cache (computes stays 2)" 2 femto-computes)

  ;; Explicit invalidation of femto-attrs overrides preserves '(all)
  (run-single-pass pass-inv-femto shared-node #f #f)
  (probe shared-node)
  (assert-equal "invalidates femto-attrs resets femto cache (computes=3)" 3 femto-computes))

;;; -----------------------------------------------------------------------
;;; Group 5: Bounded Iterative Fixpoint Optimization (run-pass-fixpoint)
;;; -----------------------------------------------------------------------
(print-group "=== Group 5: Iterative Fixpoint Optimization Loop ===")

(reset-analysis-cache!)
(reset-pass-analysis-contracts!)
(init-default-analysis-properties!)

(define *g5-dom-computes* 0)
(define *g5-live-computes* 0)

(register-analysis-property!
  'tci-fp-dom
  (lambda (ast)
    (set! *g5-dom-computes* (+ *g5-dom-computes* 1))
    (list 'dom-tree *g5-dom-computes*))
  '()
  "Tracked CFG dominators during fixpoint loop")

(register-analysis-property!
  'tci-fp-live
  (lambda (ast)
    (set! *g5-live-computes* (+ *g5-live-computes* 1))
    ;; Compute live variables in (let ((v rhs) ...) body) -> union of referenced symbols
    (if (and (pair? ast) (eq? (car ast) 'let))
        (let ((bindings (cadr ast))
              (body (caddr ast)))
          (let collect ((expr body) (acc '()))
            (cond
              ((symbol? expr)
               (if (memq expr acc) acc (cons expr acc)))
              ((pair? expr)
               (let ((from-rhs (collect (cdr expr) (collect (car expr) acc))))
                 from-rhs))
              (else acc))))
        '()))
  '()
  "Tracked live variables from body references")

;; Wait: to model cascading DCE -> constant folding:
;; Let's define two cooperating passes over `(let ((v1 e1) ...) body)`:
;; 1) const-fold pass: folds `(+ c1 c2)` in bindings/body AND if body is a symbol bound to a constant in `bindings`, substitutes it in `body` (reducing refs so another binding becomes dead!)
;;    requires: '(tci-fp-dom)
;;    preserves: '(tci-fp-dom)
;;    invalidates: '(tci-fp-live) (only when AST actually changes!)
;; 2) dce pass: requires '(tci-fp-live tci-fp-dom), reads `(get-cached-analysis 'tci-fp-live)` to drop unused bindings, and unwraps `(let () body)` -> `body`!
;;    preserves: '(tci-fp-dom)
;;    invalidates: '(tci-fp-live)

(define (tci-eval-const expr)
  (cond
    ((number? expr) expr)
    ((and (pair? expr) (eq? (car expr) '+) (= (length expr) 3)
          (number? (cadr expr)) (number? (caddr expr)))
     (+ (cadr expr) (caddr expr)))
    (else expr)))

(define (tci-subst-sym expr var val)
  (cond
    ((eq? expr var) val)
    ((not (pair? expr)) expr)
    (else (cons (tci-subst-sym (car expr) var val)
                (tci-subst-sym (cdr expr) var val)))))

(define (tci-fold-pass ast)
  (if (not (and (pair? ast) (eq? (car ast) 'let)))
      (tci-eval-const ast)
      (let* ((bindings (cadr ast))
             (body (caddr ast))
             (changed? #f)
             ;; Fold arithmetic in bindings
             (new-bindings
              (map (lambda (b)
                     (let* ((v (car b))
                            (rhs (cadr b))
                            (f (tci-eval-const rhs)))
                       (if (not (equal? f rhs))
                           (begin (set! changed? #t) (list v f))
                           b)))
                   bindings))
             ;; Fold arithmetic in body
             (body-1 (tci-eval-const body)))
        (if (not (equal? body-1 body))
            (set! changed? #t))
        ;; Propagate one constant binding used in body
        (let loop ((bs new-bindings) (b2 body-1))
          (if (null? bs)
              (if changed?
                  (list 'let new-bindings b2)
                  ast)
              (let ((var (caar bs))
                    (val (cadar bs)))
                (if (number? val)
                    (let ((b3 (tci-subst-sym b2 var val)))
                      (if (not (equal? b3 b2))
                          (set! changed? #t))
                      (loop (cdr bs) b3))
                    (loop (cdr bs) b2))))))))

(define (tci-dce-pass ast)
  ;; Reads freshly computed tci-fp-live (must NEVER be stale!)
  (let ((live-in-body (get-cached-analysis 'tci-fp-live)))
    (if (not (and (pair? ast) (eq? (car ast) 'let)))
        ast
        (let* ((bindings (cadr ast))
               (body (caddr ast))
               (kept (let filter-bs ((bs bindings) (acc '()))
                       (if (null? bs)
                           (reverse acc)
                           (let ((b (car bs)))
                             (if (memq (car b) live-in-body)
                                 (filter-bs (cdr bs) (cons b acc))
                                 (filter-bs (cdr bs) acc)))))))
          (cond
            ((null? kept) body)
            ((= (length kept) (length bindings)) ast)
            (else (list 'let kept body)))))))

(define *tci-fp-const-desc*
  (make-pass-descriptor 'tci-fp-const "ConstFold+Prop" 'frontend 2
    tci-fold-pass #f 'L_any 'L_any '() #f
    ':requires '(tci-fp-dom) ':preserves '(tci-fp-dom) ':invalidates '(tci-fp-live)))

(define *tci-fp-dce-desc*
  (make-pass-descriptor 'tci-fp-dce "DeadBindingElim" 'frontend 2
    tci-dce-pass #f 'L_any 'L_any '() #f
    ':requires '(tci-fp-live tci-fp-dom) ':preserves '(tci-fp-dom) ':invalidates '(tci-fp-live)))

(let* ((initial-ir '(let ((dead (+ 10 20)) (x (+ 3 4))) (+ x 1)))
       (final-ir (run-pass-fixpoint (list *tci-fp-const-desc* *tci-fp-dce-desc*) initial-ir)))
  ;; Iteration 1:
  ;;  - const-fold folds dead->30, x->7, body -> (+ 7 1) [AST changed -> invalidates tci-fp-live]
  ;;  - dce requires tci-fp-live (computed #1 on (+ 7 1) -> '()), drops both bindings -> (+ 7 1) [AST changed]
  ;; Iteration 2:
  ;;  - const-fold folds (+ 7 1) -> 8 [AST changed]
  ;;  - dce requires tci-fp-live (computed #2 on 8), returns 8 unchanged [AST unchanged!]
  ;; Iteration 3:
  ;;  - const-fold returns 8 (eq?) -> preserves tci-fp-live
  ;;  - dce returns 8 (eq?) -> converged!
  (assert-equal "fixpoint converges cascading const-fold + dce to 8" 8 final-ir)
  (assert-true "fixpoint reports converged? #t" (last-fixpoint-converged?))
  (assert-true "fixpoint finished in bounded iterations (<= 5)"
               (<= (last-fixpoint-iterations) 5))
  (assert-equal "cfg-dominators (tci-fp-dom) computed ONLY ONCE across all fixpoint iterations!"
                1 *g5-dom-computes*)
  (assert-true "tci-fp-live recomputed cleanly without staleness (>= 2 times)"
               (>= *g5-live-computes* 2)))

;; THREAT-840-2: Max-iterations bounding for non-converging fixpoint loops
(let* ((inc-desc (make-pass-descriptor 'tci-fp-inc "NonConvergingInc" 'frontend 2
                   (lambda (n) (+ n 1)) #f 'L_any 'L_any '() #f))
       (res (run-pass-fixpoint (list inc-desc) 0 5)))
  (assert-equal "non-converging fixpoint terminates cleanly at max-iterations=5" 5 res)
  (assert-false "non-converging fixpoint sets converged? #f" (last-fixpoint-converged?))
  (assert-equal "non-converging fixpoint records iterations=5" 5 (last-fixpoint-iterations)))

(let ((inc-desc (make-pass-descriptor 'tci-fp-inc2 "NonConvergingIncErr" 'frontend 2
                  (lambda (n) (+ n 1)) #f 'L_any 'L_any '() #f)))
  (tci-assert-error-tag ":on-limit 'error raises when max-iterations exceeded"
                        'fixpoint-max-iterations-error
                        (lambda ()
                          (run-pass-fixpoint (list inc-desc) 0 ':max-iterations 3 ':on-limit 'error))))

(test-end "Nanopass Analysis Cache Invalidation & Fixpoint Suite (#840)")
(assert-report)
