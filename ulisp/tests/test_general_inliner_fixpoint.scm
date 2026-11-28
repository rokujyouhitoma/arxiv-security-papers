;;; =======================================================================
;;; ULisp Test Suite: General Inliner, Beta-Reduction & Frontend Fixpoint
;;; Conforms to Issue #971 (THREAT-971-1 .. THREAT-971-4)
;;; =======================================================================

(test-begin "General Inliner, Beta-Reduction & Frontend Fixpoint (Issue #971)")

;;; -----------------------------------------------------------------------
;;; Group 1: Direct Beta-Reduction & Hygienic Alpha-Renaming (THREAT-971-1, 3)
;;; -----------------------------------------------------------------------
(display "--- Group 1: Beta-Reduction, Alpha-Renaming & Evaluation Order ---")
(newline)

;; 1.1 Direct lambda beta-reduction with constant args
(let* ((expr '((lambda (a b) (+ a (* b 2))) 10 16))
       (reduced (cp0-beta-reduce expr)))
  (assert-equal "1.1 direct constant beta-reduction reduces to expression"
                '(+ 10 (* 16 2))
                reduced)
  (assert-equal "1.2 cp0-opt finishes folding beta-reduced constant expr to 42"
                42
                (cp0-opt reduced)))

;; 1.2 Evaluation order & strict single evaluation for non-atomic args (THREAT-971-3)
(let* ((expr '((lambda (x y) (+ (* x x) y)) (next-val!) 5))
       (reduced (cp0-beta-reduce expr))
       (counter 0)
       (next-val! (lambda () (set! counter (+ counter 1)) 3)))
  (assert-equal "1.3 non-atomic arg is bound via let so side effect runs once"
                'let
                (car reduced))
  (assert-equal "1.4 evaluated result matches count=1 and 3*3 + 5 = 14"
                '(1 14)
                (let ((c 0))
                  (let ((nv (lambda () (set! c (+ c 1)) 3)))
                    (let ((res ((lambda (x y) (+ (* x x) y)) (nv) 5)))
                      (list c res)))))
  ;; Verify evaluation of transformed AST preserves single evaluation
  (set! counter 0)
  (assert-equal "1.5 direct beta-reduced AST preserves single evaluation"
                '(1 14)
                (eval `(let ((c 0))
                         (let ((next-val! (lambda () (set! c (+ c 1)) 3)))
                           (let ((res ,reduced))
                             (list c res))))
                      (interaction-environment))))

;; 1.3 Hygienic alpha-renaming across multiple inlining sites (THREAT-971-1)
(let* ((prog '(%program
                ((define calc (lambda (x)
                                (let ((tmp (* x 2)))
                                  (+ tmp x)))))
                (+ (calc a) (calc b))))
       (opt (frontend-inline-pass prog))
       (main-opt (caddr opt))
       (let-vars (let collect-let-vars ((e main-opt) (acc '()))
                   (cond
                     ((not (pair? e)) acc)
                     ((eq? (car e) 'let)
                      (let ((cur (append (map car* (cadr e)) acc)))
                        (collect-let-vars (caddr e) (collect-let-vars (cadr e) cur))))
                     (else (collect-let-vars (cdr e) (collect-let-vars (car e) acc)))))))
  (assert-true "1.6 both calls to calc expanded without remaining calc calls"
               (not (occurs-in? 'calc main-opt)))
  (assert-true "1.7 internal let variables are alpha-renamed distinctly across sites"
               (>= (length let-vars) 2))
  (assert-true "1.8 distinct fresh let variable symbols prevent capture"
               (not (eq? (car let-vars) (cadr let-vars)))))

;;; -----------------------------------------------------------------------
;;; Group 2: Cost Model & Single-Use / General Inlining Thresholds (THREAT-971-4)
;;; -----------------------------------------------------------------------
(display "--- Group 2: Cost Model & Use-Count Thresholds ---")
(newline)

;; 2.1 Cost <= 4 forced inline even with multiple uses
;; 2.2 Single-use (U = 1) medium function (cost 15..30 <= 36) forced inline
;; 2.3 Multi-use (U = 3) medium function exceeding growth budget stays outlined
(let* ((medium-body '(let ((t1 (+ x 1))
                           (t2 (* x 2))
                           (t3 (- x 3))
                           (t4 (+ x 4))
                           (t5 (* x 5)))
                       (+ (+ t1 t2) (+ (+ t3 t4) t5))))
       (prog-single (list '%program
                          (list (list 'define 'single-helper (list 'lambda '(x) medium-body)))
                          '(single-helper 10)))
       (prog-multi (list '%program
                         (list (list 'define 'multi-helper (list 'lambda '(x) medium-body)))
                         '(+ (multi-helper 10) (+ (multi-helper 20) (multi-helper 30)))))
       (opt-single (frontend-inline-pass prog-single))
       (opt-multi (frontend-inline-pass prog-multi)))
  (assert-true "2.1 medium function cost is between 13 and 36"
               (let ((c (cp0-expr-cost medium-body 40)))
                 (and c (> c 12) (<= c 36))))
  (assert-false "2.2 U=1 single-use medium function IS inlined"
                (occurs-in? 'single-helper (caddr opt-single)))
  (assert-true "2.3 U=3 multi-use medium function exceeds cost/growth budget and stays outlined"
               (occurs-in? 'multi-helper (caddr opt-multi))))

;; 2.4 Huge function (> 36 cost) not inlined even at U=1
(let* ((huge-body '(let ((a (+ x 1)) (b (+ x 2)) (c (+ x 3)) (d (+ x 4))
                         (e (+ x 5)) (f (+ x 6)) (g (+ x 7)) (h (+ x 8))
                         (i (+ x 9)) (j (+ x 10)) (k (+ x 11)) (l (+ x 12))
                         (m (+ x 13)) (n (+ x 14)))
                     (+ (+ (+ a b) (+ c d))
                        (+ (+ (+ e f) (+ g h))
                           (+ (+ (+ i j) (+ k l)) (+ m n))))))
       (prog-huge (list '%program
                        (list (list 'define 'huge-fn (list 'lambda '(x) huge-body)))
                        '(huge-fn 5)))
       (opt-huge (frontend-inline-pass prog-huge)))
  (assert-false "2.4 huge function cost exceeds 36"
                (cp0-expr-cost huge-body 36))
  (assert-true "2.5 U=1 huge function is NOT inlined (THREAT-971-4)"
               (occurs-in? 'huge-fn (caddr opt-huge))))

;;; -----------------------------------------------------------------------
;;; Group 3: 1-Step Recursion Unrolling & Local Loop Preservation (THREAT-971-2)
;;; -----------------------------------------------------------------------
(display "--- Group 3: 1-Step Recursion Unrolling & Loop Preservation ---")
(newline)

(init-default-pass-registry!)
(reset-pipeline-options!)
(set-pipeline-opt-level! 2)

;; 3.1 Recursive factorial with small constant folds via bounded fixpoint loop
(let* ((fact-prog '(%program
                     ((define fact
                        (lambda (n)
                          (if (<= n 1) 1 (* n (fact (- n 1)))))))
                     (fact 4)))
       (res (run-frontend-fixpoint fact-prog)))
  (assert-equal "3.1 bounded fixpoint unrolls & folds (fact 4) completely to 24"
                24
                (caddr res)))

;; 3.2 Base-case partial evaluation with non-constant second arg: (pow y 0) -> 1
(let* ((pow-prog '(%program
                    ((define pow
                       (lambda (x n)
                         (if (= n 0) 1 (* x (pow x (- n 1)))))))
                    (pow y 0)))
       (res (run-frontend-fixpoint pow-prog)))
  (assert-equal "3.2 constant base-case arg eliminates recursion: (pow y 0) -> 1"
                1
                (caddr res)))

;; 3.3 Large constant recursion terminates cleanly in max-iterations without divergence
(let* ((fact-big '(%program
                    ((define fact
                       (lambda (n)
                         (if (<= n 1) 1 (* n (fact (- n 1)))))))
                    (fact 50)))
       (res (run-frontend-fixpoint fact-big)))
  (assert-true "3.3 (fact 50) terminates cleanly with remaining recursive call"
               (occurs-in? 'fact (caddr res)))
  (assert-true "3.4 bounded fixpoint finished cleanly"
               (<= (last-fixpoint-iterations) 4)))

;; 3.4 Local tail-recursive letrec loop is preserved intact for pass-090-rtyper & pass-100-contify
(let* ((loop-ast '(letrec ((loop (lambda (i acc)
                                   (if (< i 20)
                                       (loop (+ i 1) (+ acc i))
                                       acc))))
                    (loop 0 0)))
       (opt (frontend-inline-pass loop-ast)))
  (assert-equal "3.5 local tail-recursive letrec loop is NOT peeled or destroyed"
                loop-ast
                opt))

;;; -----------------------------------------------------------------------
;;; Group 4: Safety Invariants (set!, call/cc, %num-args, shadow, asm stubs)
;;; -----------------------------------------------------------------------
(display "--- Group 4: Safety Invariants & Stub Protection ---")
(newline)

(let* ((unsafe-prog '(%program
                       ((define uses-callcc (lambda (f) (call/cc f)))
                        (define uses-numargs (lambda (x) (+ x (%num-args))))
                        (define uses-set (lambda (v) (set! g v)))
                        (define %asm-custom-op (lambda (x) x))
                        (define safe-add1 (lambda (x) (+ x 1)))
                        (define shadowed-helper (lambda (x) (+ x 2))))
                       (list (uses-callcc k)
                             (uses-numargs 1)
                             (uses-set 2)
                             (%asm-custom-op 30)
                             (let ((+ (lambda (a b) (* a b))))
                               (shadowed-helper 5))
                             (safe-add1 9))))
       (opt (frontend-inline-pass unsafe-prog))
       (main-opt (caddr opt)))
  (assert-true "4.1 call/cc callee is never inlined" (occurs-in? 'uses-callcc main-opt))
  (assert-true "4.2 %num-args callee is never inlined" (occurs-in? 'uses-numargs main-opt))
  (assert-true "4.3 set! callee is never inlined" (occurs-in? 'uses-set main-opt))
  (assert-true "4.4 %asm-* link-time stub is never inlined" (occurs-in? '%asm-custom-op main-opt))
  (assert-true "4.5 shadowed + prevents unsafe inlining of shadowed-helper"
               (occurs-in? 'shadowed-helper main-opt))
  (assert-false "4.6 safe non-shadowed safe-add1 IS inlined" (occurs-in? 'safe-add1 main-opt)))

;;; -----------------------------------------------------------------------
;;; Group 5: Cascading Fixpoint & Full Native AOT Pipeline Integration
;;; -----------------------------------------------------------------------
(display "--- Group 5: Cascading Fixpoint & Full Pipeline (LIR) Integration ---")
(newline)

;; 5.1 Inline -> CP0 -> LVN -> Inline -> CP0 chain
(let* ((chain-prog '((define (make-pair a b) (cons a b))
                     (define (sum-pair p) (+ (car p) (cdr p)))
                     (define (compute k)
                       (let ((pr (make-pair k 10)))
                         (if (pair? pr)
                             (sum-pair pr)
                             0)))
                     (compute 32)))
       (lir-o0 (begin (set-pipeline-opt-level! 0) (run-pass-pipeline chain-prog #t #f)))
       (lir-o2 (begin (set-pipeline-opt-level! 2) (run-pass-pipeline chain-prog #t #f)))
       (main-body-o2 (cdr (assq 'body (cdr (assq '%lir-main (cdr lir-o2)))))))
  (assert-true "5.1 -O0 compiles cleanly to LIR"
               (and (pair? lir-o0) (eq? (car lir-o0) '%lir-program)))
  (assert-true "5.2 -O2 fixpoint compiles cleanly to LIR"
               (and (pair? lir-o2) (eq? (car lir-o2) '%lir-program)))
  ;; In -O2, make-pair/sum-pair/compute + pair? + car/cdr + (+ 32 10) collapse completely!
  ;; Main body should contain NO heap %alloc (pair cons eliminated!) and hold 42 (* 42 4 = 168 in fixnum)!
  (assert-false "5.3 -O2 cascading fixpoint eliminates intermediate (cons a b) heap %alloc"
                (occurs-in? '%alloc main-body-o2)))

(test-end "General Inliner, Beta-Reduction & Frontend Fixpoint (Issue #971)")
(assert-report)
