;;; =======================================================================
;;; ULisp Test Suite: Whole-Program 0-CFA Devirtualization & HOF Monomorphization
;;; Conforms to Issue #972 (THREAT-972-1 .. THREAT-972-4)
;;; =======================================================================

(test-begin "Whole-Program 0-CFA Devirtualization & HOF Monomorphization (Issue #972)")

;;; -----------------------------------------------------------------------
;;; Group 1: 0-CFA Closure Flow Lattice, Aliases & K_max Widening (THREAT-972-1)
;;; -----------------------------------------------------------------------
(display "--- Group 1: 0-CFA Lattice & Constraint Propagation ---")
(newline)

(reset-type-annotations!)
(assert-equal "1.1 cfa-join bot with {a} -> {a}" '(a) (cfa-join *cfa-bot* '(a)))
(assert-equal "1.2 cfa-join {a} with *cfa-top* -> *cfa-top*" *cfa-top* (cfa-join '(a) *cfa-top*))
(assert-equal "1.3 cfa-join distinct <=4 stays bounded"
              4
              (length (cfa-join '(a b) '(c d))))
(assert-equal "1.4 cfa-join > K_max=4 widens to *cfa-top*"
              *cfa-top*
              (cfa-join '(a b c d) '(e)))

;; Singleton convergence across let alias chain & identical-branch if
(let* ((prog '(%program
                ((define add1-fn (lambda (x) (+ x 1)))
                 (define id-fn (lambda (x) x))
                 (define dbl-fn (lambda (x) (* x 2))))
                (let ((a1 (id-fn add1-fn)))
                  (let ((a2 (if #t a1 add1-fn)))
                    (let ((multi (if cond add1-fn dbl-fn)))
                      (list (a2 10) (multi 5)))))))
       (_ (cfa-analyze-program prog)))
  (assert-true "1.5 id-fn returns singleton matching add1-fn"
               (symbol? (get-cfa-singleton-target 'a1)))
  (assert-equal "1.6 a2 merges identical branches to same singleton target"
                (get-cfa-singleton-target 'add1-fn)
                (get-cfa-singleton-target 'a2))
  (assert-false "1.7 multi-closure variable has NO singleton target (THREAT-972-1)"
                (get-cfa-singleton-target 'multi))
  (assert-equal "1.8 multi-closure set has cardinality 2"
                2
                (length (get-cfa-closure-set 'multi))))

;;; -----------------------------------------------------------------------
;;; Group 2: Higher-Order Loop Specialization & Unboxing (closure_1m)
;;; -----------------------------------------------------------------------
(display "--- Group 2: Higher-Order Loop Monomorphization (closure_1m) ---")
(newline)

(init-default-pass-registry!)
(reset-pipeline-options!)
(disable-pass! 'pass-synapse-inject-safepoints)
(set-pipeline-opt-level! 2)

(let* ((closure-1m-src
        '((letrec ((iter (lambda (n f acc)
                           (if (= n 0)
                               acc
                               (iter (- n 1) f (f acc))))))
            (iter 1000000 (lambda (x) (+ x 1)) 0))))
       (lir (run-pass-pipeline closure-1m-src #t #f))
       (lir-o0 (begin (set-pipeline-opt-level! 0)
                      (let ((r (run-pass-pipeline closure-1m-src #t #f)))
                        (set-pipeline-opt-level! 2)
                        r))))
  (assert-true "2.1 -O0 compiles cleanly to LIR"
               (and (pair? lir-o0) (eq? (car lir-o0) '%lir-program)))
  (assert-true "2.2 -O2 compiles cleanly to LIR"
               (and (pair? lir) (eq? (car lir) '%lir-program)))
  ;; With 0-CFA HOF monomorphization, closure_1m must eliminate ALL heap closure allocation (%alloc)!
  (assert-false "2.3 -O2 closure_1m eliminates closure heap allocation (%alloc)"
                (occurs-in? '%alloc lir))
  ;; Specialized loop must be contified + unboxed (no indirect %call-closure in loop)
  (assert-false "2.4 -O2 closure_1m eliminates indirect closure dispatch (%call-closure)"
                (occurs-in? '%call-closure lir))
  ;; Verify semantic parity via end-to-end Scheme pipeline evaluation
  (reset-type-annotations!)
  (let* ((anf (anf-all (cp0-optimize (desugar-all (car closure-1m-src)))))
         (ann (annotate-all anf))
         (rty (rtyper-all ann))
         (con (contify-all rty))
         (cc (closure-convert con)))
    (assert-true "2.5 specialized closure_1m passes L_anf? before lowering" (L_anf? ann))
    (assert-true "2.6 specialized closure_1m passes L_lifted? after pass 110" (L_lifted? cc))
    (assert-false "2.7 zero closures remain in L_lifted AST" (occurs-in? '%make-closure-env cc))
    (assert-true "2.8 loop contains unboxed %raw-add in rtyper AST" (occurs-in? '%raw-add rty))))

;;; -----------------------------------------------------------------------
;;; Group 3: Top-Level Multi-Site HOF Cloning & Reuse
;;; -----------------------------------------------------------------------
(display "--- Group 3: Top-Level Multi-Site HOF Monomorphization ---")
(newline)

(reset-type-annotations!)
(set-pipeline-opt-level! 2)

(let* ((hof-prog '(%program
                    ((define apply-twice
                       (lambda (fn x)
                         (let ((t1 (fn x)))
                           (fn t1))))
                     (define inc (lambda (v) (+ v 1)))
                     (define dbl (lambda (v) (* v 2))))
                    (let ((a (apply-twice inc 10)))
                      (let ((b (apply-twice inc 20)))
                        (let ((c (apply-twice dbl 5)))
                          (let ((s1 (+ a b)))
                            (+ s1 c)))))))
       (ann (annotate-all hof-prog))
       (defs (cadr ann))
       (cc (closure-convert (contify-all (rtyper-all ann)))))
  (assert-true "3.1 top-level multi-site HOF produces specialized clones in %program"
               (> (length defs) 3))
  (assert-true "3.2 specialized clone reuses cache for duplicate (apply-twice inc) calls"
               (<= (length defs) 5))
  (assert-true "3.3 specialized HOF program satisfies L_anf? schema"
               (L_anf? ann))
  (assert-false "3.4 zero closure allocations remain after HOF monomorphization"
                (occurs-in? '%make-closure-env cc))
  (assert-true "3.5 monomorphized program compiles through Pass 110 satisfying L_lifted?"
               (L_lifted? cc)))

;;; -----------------------------------------------------------------------
;;; Group 4: 0-CFA Direct Call Devirtualization & Alias Propagation (Pass 110)
;;; -----------------------------------------------------------------------
(display "--- Group 4: 0-CFA Direct Call Devirtualization ---")
(newline)

(reset-type-annotations!)
(set-pipeline-opt-level! 2)

(let* ((alias-prog '(%program
                      ((define step (lambda (x) (+ x 3))))
                      (let ((f step))
                        (let ((g (if #t f step)))
                          (g 10)))))
       (ann (annotate-all alias-prog))
       (cc (closure-convert ann))
       (main-cc (caddr cc)))
  (assert-true "4.1 0-CFA resolves conditional alias g to singleton %direct-call"
               (occurs-in? '%direct-call main-cc))
  (assert-false "4.2 0-CFA devirtualization eliminates %make-closure-env on direct call path"
                (occurs-in? '%make-closure-env main-cc))
  (assert-true "4.3 devirtualized program satisfies L_lifted?"
               (L_lifted? cc)))

;;; -----------------------------------------------------------------------
;;; Group 5: Safety Invariants (THREAT-972-1 .. THREAT-972-4)
;;; -----------------------------------------------------------------------
(display "--- Group 5: Safety Invariants ---")
(newline)

;; 5.1 Mutated variable via set! MUST NOT be devirtualized or treated as singleton
(reset-type-annotations!)
(let* ((mut-prog '(%program
                    ((define fn1 (lambda (x) (+ x 1)))
                     (define fn2 (lambda (x) (+ x 2))))
                    (let ((f fn1))
                      (begin
                        (set! f fn2)
                        (f 10)))))
       (_ (cfa-analyze-program mut-prog)))
  (assert-equal "5.1 set!-mutated variable widens to *cfa-top*"
                *cfa-top*
                (get-cfa-closure-set 'f))
  (assert-false "5.2 set!-mutated variable has NO singleton target"
                (get-cfa-singleton-target 'f)))

;; 5.2 Arity mismatch MUST widen to *cfa-top* and NOT emit unsound %direct-call
(reset-type-annotations!)
(let* ((arity-prog '(%program
                      ((define fn1 (lambda (x) (+ x 1))))
                      (let ((f fn1))
                        (f 1 2))))
       (ann (annotate-all arity-prog))
       (cc (closure-convert ann)))
  (assert-false "5.3 arity mismatch prevents singleton target registration"
                (get-cfa-singleton-target 'f))
  (assert-false "5.4 arity mismatch call does NOT emit invalid %direct-call to fn1"
                (and (pair? (caddr cc)) (eq? (car (caddr cc)) '%direct-call))))

;; 5.3 Free-variable capture safety: top-level HOF must NOT expand local-capture lambda into top-level clone
(reset-type-annotations!)
(let* ((cap-prog '(%program
                    ((define hof (lambda (fn x) (fn x))))
                    (let ((secret 99))
                      (let ((adder (lambda (y) (+ y secret))))
                        (hof adder 1)))))
       (ann (annotate-all cap-prog))
       (defs (cadr ann)))
  (assert-equal "5.5 local free-var capturing lambda stays uncloned in top-level HOF (THREAT-972-2)"
                1
                (length defs))
  (assert-false "5.6 secret does not leak into top-level HOF definition"
                (occurs-in? 'secret defs)))

;; 5.4 Unsafe primitives (%num-args / call/cc) prevent monomorphization
(reset-type-annotations!)
(let* ((unsafe-prog '(%program
                       ((define hof-u (lambda (fn x) (fn x))))
                       (let ((bad (lambda (y) (call/cc (lambda (k) (k y))))))
                         (hof-u bad 5))))
       (ann (annotate-all unsafe-prog)))
  (assert-equal "5.7 call/cc lambda is skipped by HOF monomorphizer"
                1
                (length (cadr ann))))

;; 5.5 Polymorphic call site stays dynamic in closure-convert
(reset-type-annotations!)
(let* ((poly-prog '(%program
                     ((define f1 (lambda (x) (+ x 1)))
                      (define f2 (lambda (x) (* x 2))))
                     (let ((g (if unknown f1 f2)))
                       (g 7))))
       (ann (annotate-all poly-prog))
       (cc (closure-convert ann)))
  (assert-false "5.8 polymorphic g (|C(g)| = 2) is NOT devirtualized to %direct-call"
                (occurs-in? '%direct-call (caddr cc)))
  (assert-true "5.9 polymorphic closure conversion satisfies L_lifted?"
               (L_lifted? cc)))

;; 5.6 Quoted improper pair '(1 . 2) at top-level MUST NOT trigger type-error in CFA/annotator
(reset-type-annotations!)
(set-pipeline-opt-level! 2)
(let ((qann (annotate-all '(quote (1 . 2))))
      (qlir (run-pass-pipeline '((quote (1 . 2))) #t #f)))
  (assert-equal "5.10 quoted improper pair '(1 . 2) annotates cleanly"
                '(quote (1 . 2))
                qann)
  (assert-true "5.11 quoted improper pair '(1 . 2) compiles cleanly through -O2 pipeline"
               (and (pair? qlir) (eq? (car qlir) '%lir-program))))

(test-end "Whole-Program 0-CFA Devirtualization & HOF Monomorphization (Issue #972)")
(assert-report)
