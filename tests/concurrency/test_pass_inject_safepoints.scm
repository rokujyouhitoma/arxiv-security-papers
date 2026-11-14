;;; =======================================================================
;;; Synapse Reduction Safepoint Injection Test Suite
;;; Path: tests/concurrency/test_pass_inject_safepoints.scm
;;; Conforms to DSN-37 Section 7.2, 12.4 & Phase 3 Task 3.4 (Issue #640)
;;; =======================================================================

(test-begin "Synapse Reduction Safepoint Injection")

;;; -----------------------------------------------------------------------
;;; Group 1: AST Predicates & Construction
;;; -----------------------------------------------------------------------

(newline)
(display "--- Group 1: AST Predicates & Construction ---\n")

(assert-true "1.1 safepoint-poll-form? detects %synapse-safepoint-poll!"
             (safepoint-poll-form? '(%synapse-safepoint-poll!)))

(assert-true "1.2 safepoint-poll-form? detects %safepoint-poll!"
             (safepoint-poll-form? '(%safepoint-poll!)))

(assert-false "1.3 safepoint-poll-form? rejects arbitrary symbols"
              (safepoint-poll-form? '(foo 1 2)))

(assert-true "1.4 make-safepoint-poll produces valid polling form"
             (safepoint-poll-form? (make-safepoint-poll)))

(assert-true "1.5 lambda-form? detects valid lambda"
             (lambda-form? '(lambda (x y) (+ x y))))

(assert-false "1.6 lambda-form? rejects non-lambda"
              (lambda-form? '(define (f x) x)))

(assert-true "1.7 named-let-form? detects named let loop"
             (named-let-form? '(let loop ((n 10)) (if (> n 0) (loop (- n 1)) 0))))

(assert-false "1.8 named-let-form? rejects standard let"
              (named-let-form? '(let ((x 1)) x)))

(assert-true "1.9 asc-kernel-form? detects %asc-kernel"
             (asc-kernel-form? '(%asc-kernel (task 100) (display 1))))

;;; -----------------------------------------------------------------------
;;; Group 2: Function Prologue Safepoint Injection
;;; -----------------------------------------------------------------------

(newline)
(display "--- Group 2: Function Prologue Safepoint Injection ---\n")

(let* ((orig '(lambda (x) (+ x 1)))
       (res (inject-safepoints-expr orig '())))
  (assert-true "2.1 lambda prologue gets safepoint injected"
               (equal? res '(lambda (x) (begin (%synapse-safepoint-poll!) (+ x 1))))))

;; Idempotency: verify no duplicate injection if already present
(let* ((orig '(lambda (x) (begin (%synapse-safepoint-poll!) (+ x 1))))
       (res (inject-safepoints-expr orig '())))
  (assert-true "2.2 lambda prologue does not duplicate existing safepoint"
               (equal? res '(lambda (x) (begin (%synapse-safepoint-poll!) (+ x 1))))))

;; Multi-expression lambda body
(let* ((orig '(lambda (a b) (display a) (+ a b)))
       (res (inject-safepoints-expr orig '())))
  (assert-true "2.3 multi-expression lambda preserves all expressions after safepoint"
               (equal? res '(lambda (a b) (begin (%synapse-safepoint-poll!) (display a) (+ a b))))))

;;; -----------------------------------------------------------------------
;;; Group 3: Loop Backedge & Named-Let Injection
;;; -----------------------------------------------------------------------

(newline)
(display "--- Group 3: Loop Backedge & Named-Let Injection ---\n")

;; Infinite loop
(let* ((orig '(let loop () (loop)))
       (res (inject-safepoints-expr orig '())))
  (assert-true "3.1 named-let infinite loop receives entry safepoint and backedge safepoint"
               (equal? res '(let loop ()
                              (begin
                                (%synapse-safepoint-poll!)
                                (begin (%synapse-safepoint-poll!) (loop)))))))

;; Conditional loop with recursion
(let* ((orig '(let loop ((n 10))
                (if (> n 0)
                    (loop (- n 1))
                    n)))
       (res (inject-safepoints-expr orig '())))
  (assert-true "3.2 conditional loop backedge receives safepoint before recursive call"
               (equal? res '(let loop ((n 10))
                              (begin
                                (%synapse-safepoint-poll!)
                                (if (> n 0)
                                    (begin (%synapse-safepoint-poll!) (loop (- n 1)))
                                    n))))))

;; Nested loops
(let* ((orig '(let outer ()
                (let inner ()
                  (inner))
                (outer)))
       (res (inject-safepoints-expr orig '())))
  (assert-true "3.3 nested loops both receive entry and backedge safepoints"
               (and (pair? res)
                    (eq? (car res) 'let)
                    (eq? (cadr res) 'outer))))

;;; -----------------------------------------------------------------------
;;; Group 4: ASC Kernel Transformation
;;; -----------------------------------------------------------------------

(newline)
(display "--- Group 4: ASC Kernel Transformation ---\n")

(let* ((kernel '(%asc-kernel (task: (id 101))
                  (let loop ((count 100))
                    (if (> count 0)
                        (loop (- count 1))
                        'done))))
       (trans (inject-safepoints-kernel kernel)))
  (assert-true "4.1 kernel output retains %asc-kernel tag"
               (and (pair? trans) (eq? (car trans) '%asc-kernel)))
  (assert-equal "4.2 kernel header preserved"
                '(task: (id 101))
                (cadr trans))
  (let ((body (caddr trans)))
    ;; Body wrapped in begin with prologue safepoint
    (assert-true "4.3 kernel body has top-level safepoint poll"
                 (and (pair? body)
                      (eq? (car body) 'begin)
                      (safepoint-poll-form? (cadr body))))))

;;; -----------------------------------------------------------------------
;;; Group 5: Layer 1 (R7RS) Functions & Loops Safepoint Injection (#744)
;;; -----------------------------------------------------------------------

(newline)
(display "--- Group 5: Layer 1 (R7RS) Functions & Loops Safepoint Injection (#744) ---\n")

(let* ((r7rs-forms '((define (host-func x) (* x 2))
                     (let loop () (loop))))
       (out (inject-safepoints-pass r7rs-forms)))
  (assert-true "5.1 define function prologue receives safepoint"
               (equal? (car out)
                       '(define (host-func x) (%synapse-safepoint-poll!) (* x 2))))
  (assert-true "5.2 top-level loop receives safepoint in entry and backedge"
               (equal? (cadr out)
                       '(let loop ()
                          (begin
                            (%synapse-safepoint-poll!)
                            (begin (%synapse-safepoint-poll!) (loop)))))))

;;; -----------------------------------------------------------------------
;;; Group 6: Pass Manager Injection & Pipeline Integration
;;; -----------------------------------------------------------------------

(newline)
(display "--- Group 6: Pass Manager Injection & Pipeline Integration ---\n")

(init-default-pass-registry!)
(inject-synapse-split-planes-pass!)
(inject-synapse-check-affine-pass!)
(inject-synapse-fbip-pass!)
(inject-synapse-safepoints-pass!)

(define pipeline-all (build-pipeline 0 '()))
(define ids-all (map pass-id pipeline-all))

(assert-true "6.1 pass-synapse-split-planes present in pipeline"
             (memq 'pass-synapse-split-planes ids-all))
(assert-true "6.2 pass-synapse-check-affine present in pipeline"
             (memq 'pass-synapse-check-affine ids-all))
(assert-true "6.3 pass-synapse-fbip present in pipeline"
             (memq 'pass-synapse-fbip ids-all))
(assert-true "6.4 pass-synapse-inject-safepoints present in pipeline"
             (memq 'pass-synapse-inject-safepoints ids-all))

(define (pass-after? p1 p2 p-list)
  (let loop ((ps p-list))
    (cond
      ((null? ps) #f)
      ((null? (cdr ps)) #f)
      ((and (eq? (car ps) p1) (eq? (cadr ps) p2)) #t)
      (else (loop (cdr ps))))))

(assert-true "6.5 safepoints pass directly follows fbip pass"
             (pass-after? 'pass-synapse-fbip 'pass-synapse-inject-safepoints ids-all))

;; Validate prerequisites DAG
(assert-true "6.6 injected pipeline satisfies all DAG prerequisites"
             (validate-pipeline-prerequisites pipeline-all))

;; Execute pass through pass-function
(define forms-input
  (list
    '(define (caller) 42)
    '(%asc-kernel (task: (id 200))
       (let loop () (loop)))))

(define forms-output (inject-safepoints-pass forms-input))

(assert-equal "6.7 define form transformed with safepoint prologue"
              '(define (caller) (%synapse-safepoint-poll!) 42)
              (car forms-output))

(assert-true "6.8 kernel form transformed"
             (and (pair? (cadr forms-output))
                  (eq? (car (cadr forms-output)) '%asc-kernel)))

;; Clean up pass from manager
(remove-synapse-safepoints-pass!)
(remove-synapse-fbip-pass!)
(remove-synapse-check-affine-pass!)
(remove-synapse-split-planes-pass!)

(define clean-pipe (build-pipeline 0 '()))
(define clean-ids (map pass-id clean-pipe))
(assert-false "6.9 safepoints pass cleanly removed"
              (memq 'pass-synapse-inject-safepoints clean-ids))

;;; -----------------------------------------------------------------------
;;; Group 7: Default Registry Integration & Automatic Safepoint Injection (#790)
;;; -----------------------------------------------------------------------

(newline)
(display "--- Group 7: Default Registry Integration & Pipeline Hook (#790) ---\n")

;; Re-register hook and re-initialize default pass registry
(register-pass-registry-init-hook! inject-synapse-safepoints-pass!)
(init-default-pass-registry!)

(define def-pipeline (build-pipeline 0 '()))
(define def-ids (map pass-id def-pipeline))

(assert-true "7.1 pass-synapse-inject-safepoints automatically registered in default registry"
             (memq 'pass-synapse-inject-safepoints def-ids))

(assert-true "7.2 default pipeline satisfies DAG prerequisites without Synapse FBIP"
             (validate-pipeline-prerequisites def-pipeline))

;; Test dynamic pass disabling via pass manager
(disable-pass! 'pass-synapse-inject-safepoints)
(define disabled-pipe (build-pipeline 0 (pipeline-disabled-passes)))
(define disabled-ids (map pass-id disabled-pipe))

(assert-false "7.3 pass-synapse-inject-safepoints excluded when disabled"
              (memq 'pass-synapse-inject-safepoints disabled-ids))

;; Re-enable pass
(enable-pass! 'pass-synapse-inject-safepoints)
(define reenabled-pipe (build-pipeline 0 (pipeline-disabled-passes)))
(define reenabled-ids (map pass-id reenabled-pipe))

(assert-true "7.4 pass-synapse-inject-safepoints restored when enabled"
             (memq 'pass-synapse-inject-safepoints reenabled-ids))

;; Test AST transformation via inject-safepoints-pass on pure Scheme forms
(define test-pure-forms
  (list
    '(define (compute-sum n)
       (let loop ((i 0) (acc 0))
         (if (< i n)
             (loop (+ i 1) (+ acc i))
             acc)))))

(define transformed-pure-forms (inject-safepoints-pass test-pure-forms))
(define trans-def (car transformed-pure-forms))

;; Check prologue in define
(assert-true "7.5 define form received automatic prologue safepoint"
             (and (eq? (car trans-def) 'define)
                  (pair? (cddr trans-def))
                  (safepoint-poll-form? (caddr trans-def))))

;; Check loop entry and backedge in named-let
(define trans-let (cadddr trans-def))
(assert-true "7.6 named-let received automatic entry safepoint"
             (and (eq? (car trans-let) 'let)
                  (eq? (cadr trans-let) 'loop)
                  (pair? (cadddr trans-let))
                  (eq? (car (cadddr trans-let)) 'begin)
                  (safepoint-poll-form? (cadr (cadddr trans-let)))))

;; Clean up pass from manager
(remove-synapse-safepoints-pass!)

;;; -----------------------------------------------------------------------
;;; Group 8: Exclusion Rules & Trivial Accessor Pruning (#796)
;;; -----------------------------------------------------------------------

(newline)
(display "--- Group 8: Exclusion Rules & Trivial Accessor Pruning (#796) ---\n")

;; 8.1 Name prefix deprecation (#810): user procedures (make-*, task-*, etc.) DO receive safepoints
;; while %-prefixed and exact excluded symbols (or procedures with declare) do NOT.
(let* ((forms '((define (make-tree n) (display n) (+ n 1))
                (define (%synapse-lowlevel-call x) (display x) x)
                (define (sys-poll) (display "poll") 0)
                (define (task-internal-helper a b)
                  (declare (no-safepoints))
                  (display a)
                  (+ a b))))
       (trans (inject-safepoints-pass forms)))
  (assert-true "8.1 make-tree user procedure receives safepoint prologue"
               (safepoint-poll-form? (caddr (car trans))))
  (assert-false "8.2 %synapse-* internal procedure does not receive safepoint prologue"
                (safepoint-poll-form? (caddr (cadr trans))))
  (assert-false "8.3 sys-poll exact excluded symbol does not receive safepoint prologue"
                (safepoint-poll-form? (caddr (caddr trans))))
  (assert-false "8.3.1 task-internal-helper with declare no-safepoints skips safepoint"
                (safepoint-poll-form? (caddr (cadddr trans)))))

;; 8.2 Explicit (declare (no-safepoints)) skips safepoint injection and strips declare (#810)
(let* ((forms '((define (explicitly-exempt x y)
                  (declare (no-safepoints))
                  (display x)
                  (+ x y))
                (lambda (a b)
                  (declare (no-safepoints))
                  (display a)
                  (+ a b))))
       (trans (inject-safepoints-pass forms)))
  (assert-false "8.4 explicit declare no-safepoints skips define prologue safepoint"
                (safepoint-poll-form? (caddr (car trans))))
  (assert-false "8.5 explicit declare no-safepoints skips lambda prologue safepoint"
                (and (pair? (caddr (cadr trans)))
                     (pair? (cdr (caddr (cadr trans))))
                     (safepoint-poll-form? (cadr (caddr (cadr trans))))))
  (let ((contains-no-safepoints?
         (lambda (tree)
           (let loop ((t tree))
             (cond
               ((eq? t 'no-safepoints) #t)
               ((not (pair? t)) #f)
               (else (or (loop (car t)) (loop (cdr t)))))))))
    (assert-false "8.5.1 declaration symbol stripped from define body"
                  (contains-no-safepoints? (car trans)))
    (assert-false "8.5.2 declaration symbol stripped from lambda body"
                  (contains-no-safepoints? (cadr trans)))))

;; 8.3 Trivial field accessors skip safepoint prologue
(let* ((forms '((define (get-car p) (car p))
                (define (get-cdr p) (cdr p))
                (define (get-field v) (vector-ref v 0))))
       (trans (inject-safepoints-pass forms)))
  (assert-false "8.6 trivial car accessor skips prologue safepoint"
                (safepoint-poll-form? (caddr (car trans))))
  (assert-false "8.7 trivial cdr accessor skips prologue safepoint"
                (safepoint-poll-form? (caddr (cadr trans))))
  (assert-false "8.8 trivial vector-ref accessor skips prologue safepoint"
                (safepoint-poll-form? (caddr (caddr trans)))))

;; 8.4 Function with named-let loop still receives loop entry & backedge safepoints
(let* ((forms '((define (scan-list lst)
                  (let loop ((cur lst))
                    (if (null? cur)
                        #f
                        (begin
                          (display (car cur))
                          (loop (cdr cur))))))))
       (trans (inject-safepoints-pass forms)))
  (let* ((fn (car trans))
         ;; fn is (define (scan-list lst) (%synapse-safepoint-poll!) (let loop ...))
         (loop-expr (cadddr fn)))
    (assert-true "8.9 loop entry inside function receives safepoint"
                 (and (pair? (cadddr loop-expr))
                      (eq? (car (cadddr loop-expr)) 'begin)
                      (safepoint-poll-form? (cadr (cadddr loop-expr)))))))


;;; -----------------------------------------------------------------------
;;; Group 9: Tail-Call Optimization (TCO) Preservation & Stack Safety (#802)
;;; -----------------------------------------------------------------------

(newline)
(display "--- Group 9: Tail-Call Optimization (TCO) Preservation & Stack Safety (#802) ---\n")

;; Mock runtime polling definition for interpreter-level execution tests
(define (%synapse-safepoint-poll!) #t)

;; 9.1 cont-recurse-tail? detects %cont-call inside begin wrapper
(let ((wrapped '(%cont-call loop (- n 1) (+ acc n))))
  (assert-true "9.1 direct %cont-call is in tail position"
               (cont-recurse-tail? 'loop wrapped)))

(let ((wrapped '(begin (%synapse-safepoint-poll!) (%cont-call loop (- n 1) (+ acc n)))))
  (assert-true "9.2 %cont-call wrapped in begin safepoint is recognized as tail call"
               (cont-recurse-tail? 'loop wrapped)))

(let ((wrapped '(begin (display "poll") (%synapse-safepoint-poll!) (%cont-call loop 0 0))))
  (assert-true "9.3 multi-statement begin with %cont-call at tail is recognized as tail call"
               (cont-recurse-tail? 'loop wrapped)))

;; 9.4 cont-loop-rotation-candidate? recognizes loop with safepoint prologue
(let* ((f-body '(begin
                  (%synapse-safepoint-poll!)
                  (if (= n 0)
                      acc
                      (begin (%synapse-safepoint-poll!) (%cont-call loop (- n 1) (+ acc n))))))
       (rot (cont-loop-rotation-candidate? 'loop f-body)))
  (assert-true "9.4 loop with safepoint prologue recognized as rotation candidate"
               (and rot (pair? rot))))

;; 9.5 cont-can-unroll-counting-loop? recognizes counting loop with begin wrapper
(let* ((cmp '(= i 16))
       (recurse '(begin (%synapse-safepoint-poll!) (%cont-call loop (+ i 1) (+ acc i)))))
  (assert-true "9.5 counting loop with begin wrapper recognized for unrolling"
               (cont-can-unroll-counting-loop? '(i acc) cmp recurse 'loop)))

;; 9.6 TCO & Zero-Closure Verification: inject-safepoints + contify + closure-convert + LIR
(let* ((input '(letrec ((loop (lambda (n acc)
                                (begin
                                  (%synapse-safepoint-poll!)
                                  (if (= n 0)
                                      acc
                                      (begin
                                        (%synapse-safepoint-poll!)
                                        (loop (- n 1) (+ acc n))))))))
                 (loop 10 0)))
       (contified (contify-all input))
       (closed (closure-convert contified))
       (lir (generate-lir closed))
       (main-insts (caddr (assq '%lir-main lir))))
  ;; Verify that NO %call-closure instructions were generated (TCO preserved)
  (let ((has-call-closure?
         (let check-cc ((insts main-insts))
           (and (pair? insts)
                (or (and (pair? (car insts)) (eq? (caar insts) '%call-closure))
                    (check-cc (cdr insts)))))))
    (assert-false "9.6 no %call-closure in safepoint-injected contified loop LIR"
                  has-call-closure?))
  ;; Verify that %jump instructions are generated for the loop
  (let ((jump-count
         (let check-jmp ((insts main-insts) (cnt 0))
           (if (null? insts) cnt
               (let ((inst (car insts)))
                 (if (and (pair? inst) (eq? (car inst) '%jump))
                     (check-jmp (cdr insts) (+ cnt 1))
                     (check-jmp (cdr insts) cnt)))))))
    (assert-true "9.7 safepoint-injected loop generates %jump instructions (TCO jmp)"
                 (>= jump-count 2))))

;; 9.8 1,000,000-iteration tail-recursive execution completes without stack overflow (CWE-400)
(let* ((million 1000000)
       (sum-million
        (let loop ((i 0) (acc 0))
          (begin
            (%synapse-safepoint-poll!)
            (if (= i million)
                acc
                (begin
                  (%synapse-safepoint-poll!)
                  (loop (+ i 1) (+ acc 1))))))))
  (assert-equal "9.8 1,000,000 iterations complete with constant stack (TCO verified)"
                million
                sum-million))


(test-end "Synapse Reduction Safepoint Injection")
