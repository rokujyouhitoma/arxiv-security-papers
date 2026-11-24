;;; =======================================================================
;;; Test Suite: Specialization Memoization, Hard Limits & Widening
;;; Conforms to DSN-33-03 §5.1, §5.2, §5.3 & Issue #877
;;; =======================================================================

(display "\n=== [Test Suite: Specialization Memoization & Widening (Issue #877)] ===\n")

;;; -----------------------------------------------------------------------
;;; Group 1: Pi_static Projection & Signature Key
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Pi_static Projection & Signature Key ---\n")

(let* ((sv-stat (make-static-val 'integer 42 #f #f))
       (sv-dyn  (make-dynamic-val 'unknown 'x #f #f))
       (sv-psds (make-psds-val 'pair (cons sv-stat sv-dyn) #f #f))
       (sv-deep (make-psds-val 'pair (cons (make-static-val 'sym 'foo #f #f) sv-psds) #f #f)))

  ;; 1.1 Pure static value projection
  (assert-equal "1.1 Pure static projection" 42 (stage-project-static-key sv-stat))

  ;; 1.2 Pure dynamic value projection -> *dynamic*
  (assert-equal "1.2 Pure dynamic projection" '*dynamic* (stage-project-static-key sv-dyn))

  ;; 1.3 PSDS pair projection masks dynamic leaf
  (assert-equal "1.3 PSDS pair projection" '(42 . *dynamic*) (stage-project-static-key sv-psds))

  ;; 1.4 Deep PSDS pair projection
  (assert-equal "1.4 Deep PSDS pair projection" '(foo 42 . *dynamic*) (stage-project-static-key sv-deep))

  ;; 1.5 Signature key generation
  (let ((key (make-spec-signature-key 'power (list sv-dyn sv-stat))))
    (assert-equal "1.5 Signature key format" '(power *dynamic* 42) key)))

;;; -----------------------------------------------------------------------
;;; Group 2: Specialization Memoization & Cache Reuse
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Specialization Memoization & Cache Reuse ---\n")

(let* ((memo (make-spec-memo-table))
       (s1 (make-static-val 'integer 10 #f #f))
       (d1 (make-dynamic-val 'unknown 'n #f #f))
       (key1 (make-spec-signature-key 'ackermann (list s1 d1)))
       (builder-called-count (cons 0 '()))
       (builder (lambda (spec-name args)
                  (set-car! builder-called-count (+ (car builder-called-count) 1))
                  (list 'define (cons spec-name '(n)) '(+ n 10)))))

  ;; First call: triggers specialization
  (let ((res1 (specialize-or-widen memo 'ackermann (list s1 d1) 0 builder)))
    (assert-equal "2.1 First call specialized" 'specialized (car res1))
    (assert-equal "2.1 Builder called once" 1 (car builder-called-count))
    (let ((spec-sym (cadr res1)))
      (assert-equal "2.1 Spec symbol generated" 'ackermann$spec0 spec-sym)

      ;; Second call with SAME static signature: MUST hit cache!
      (let ((res2 (specialize-or-widen memo 'ackermann (list s1 d1) 0 builder)))
        (assert-equal "2.2 Second call hits cache" 'cached (car res2))
        (assert-equal "2.2 Cache returns same spec symbol" spec-sym (cadr res2))
        (assert-equal "2.2 Builder NOT called again" 1 (car builder-called-count)))))

  ;; Verify residual function is recorded
  (let ((fns (spec-memo-residual-fns memo)))
    (assert-equal "2.3 Exactly one residual fn recorded" 1 (length fns))
    (assert-equal "2.3 Residual fn header" 'define (caar fns))))

;;; -----------------------------------------------------------------------
;;; Group 3: MAX_SPEC_INSTANCES=8 Hard Limit & Widening
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: MAX_SPEC_INSTANCES=8 Hard Limit & Widening ---\n")

(let* ((memo (make-spec-memo-table))
       (dyn-x (make-dynamic-val 'unknown 'x #f #f))
       (builder (lambda (spec-name args)
                  (list 'define (cons spec-name '(x)) '(+ x 1)))))

  ;; Specialize 8 times with different static constants (0 to 7)
  (let loop ((i 0))
    (if (< i 8)
        (let* ((stat-i (make-static-val 'integer i #f #f))
               (res (specialize-or-widen memo 'poly-fn (list stat-i dyn-x) 0 builder)))
          (assert-equal "3.1 Up to 8 instances allowed" 'specialized (car res))
          (loop (+ i 1)))))

  (assert-equal "3.2 Instance count reaches 8" 8 (spec-memo-instance-count memo 'poly-fn))

  ;; 9th attempt: MUST trigger Widening!
  (let* ((stat-9 (make-static-val 'integer 999 #f #f))
         (res-widen (specialize-or-widen memo 'poly-fn (list stat-9 dyn-x) 0 builder)))
    (assert-equal "3.3 9th attempt triggers widening" 'widened (car res-widen))
    (assert-equal "3.3 Widened routes back to original fn" 'poly-fn (cadr res-widen))
    ;; Residual functions count remains exactly 8 (no unbounded growth)
    (assert-equal "3.4 Residual functions capped at 8" 8 (length (spec-memo-residual-fns memo)))))

;;; -----------------------------------------------------------------------
;;; Group 4: MAX_SPEC_DEPTH=4 Call Depth Limit & Widening
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: MAX_SPEC_DEPTH=4 Call Depth Limit & Widening ---\n")

(let* ((memo (make-spec-memo-table))
       (stat-val (make-static-val 'integer 1 #f #f))
       (builder (lambda (spec-name args)
                  (list 'define (cons spec-name '()) 42))))

  ;; Depth 0, 1, 2, 3, 4 are within limit
  (assert-equal "4.1 Depth 0 allowed" #t (spec-memo-can-specialize? memo 'rec-fn '(rec-fn 1) 0))
  (assert-equal "4.1 Depth 4 allowed" #t (spec-memo-can-specialize? memo 'rec-fn '(rec-fn 1) 4))

  ;; Depth 5 exceeds *max-spec-depth* (4) -> Widening!
  (assert-equal "4.2 Depth 5 rejected" #f (spec-memo-can-specialize? memo 'rec-fn '(rec-fn 1) 5))

  (let ((res-deep (specialize-or-widen memo 'rec-fn (list stat-val) 5 builder)))
    (assert-equal "4.3 Deep recursion triggers widening" 'widened (car res-deep))
    (assert-equal "4.3 Widened routes to rec-fn" 'rec-fn (cadr res-deep))))

;;; -----------------------------------------------------------------------
;;; Group 5: Residual Function Definitions Extraction
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Residual Function Definitions Extraction ---\n")

(let* ((memo (make-spec-memo-table))
       (s-a (make-static-val 'symbol 'mode-fast #f #f))
       (s-b (make-static-val 'symbol 'mode-safe #f #f))
       (d (make-dynamic-val 'unknown 'buf #f #f))
       (builder-fast (lambda (name args) (list 'define (cons name '(buf)) '(vector-ref buf 0))))
       (builder-safe (lambda (name args) (list 'define (cons name '(buf)) '(safe-vector-ref buf 0)))))

  (specialize-or-widen memo 'dispatch (list s-a d) 0 builder-fast)
  (specialize-or-widen memo 'dispatch (list s-b d) 0 builder-safe)

  (let ((defs (spec-memo-residual-fns memo)))
    (assert-equal "5.1 Exactly 2 residual functions defined" 2 (length defs))
    (assert-equal "5.2 First residual fn name" 'dispatch$spec0 (caar (cdar defs)))
    (assert-equal "5.3 Second residual fn name" 'dispatch$spec1 (caar (cdr (cadr defs))))))

;;; -----------------------------------------------------------------------
;;; Group 6: End-to-End eval-in-stage-apply Specialization & Widening (#942)
;;; -----------------------------------------------------------------------
(display "\n--- Group 6: End-to-End eval-in-stage-apply Specialization (#942) ---\n")

;; 6.1 Memoization reuse across calls with identical static signatures
(let* ((prog-reuse
        '(begin
           (define (add-k k x) (+ k x))
           (+ (add-k 10 a) (add-k 10 b))))
       (lowered (stage-poly-lower prog-reuse '()))
       (memo (get-last-spec-memo-table))
       (res-val (eval-residual-anf-expr lowered '((a . 3) (b . 4)))))
  (assert-equal "6.1 Specialized reuse computes (10+3)+(10+4)=27" 27 res-val)
  (assert-equal "6.2 Cache hit creates exactly 1 add-k$spec instance" 1 (spec-memo-instance-count memo 'add-k))
  (assert-true "6.3 add-k calls completely specialized away"
               (and (not (equal? (spec-memo-residual-fns memo) '()))
                    (= (length (spec-memo-residual-fns memo)) 1))))

;; 6.2 Instance limit (*max-spec-instances* = 8) widening through eval-in-stage-apply
(let* ((prog-9-calls
        '(begin
           (define (scale k x) (* k x))
           (+ (+ (+ (scale 1 a) (scale 2 a)) (+ (scale 3 a) (scale 4 a)))
              (+ (+ (scale 5 a) (scale 6 a)) (+ (scale 7 a) (+ (scale 8 a) (scale 9 a)))))))
       (lowered-9 (stage-poly-lower prog-9-calls '()))
       (memo-9 (get-last-spec-memo-table)))
  (assert-equal "6.4 Instance limit caps scale$spec at 8" 8 (spec-memo-instance-count memo-9 'scale))
  (assert-equal "6.5 9th call widened cleanly via residual call" 8 (length (spec-memo-residual-fns memo-9))))

;; 6.3 Recursion depth limit (*max-spec-depth* = 4) triggers widening fallback
(let* ((prog-deep-rec
        '(begin
           (define (down n acc)
             (if (= n 0)
                 acc
                 (down (- n 1) (+ acc 1))))
           (down 6 dyn-acc)))
       (lowered-rec (stage-poly-lower prog-deep-rec '()))
       (memo-rec (get-last-spec-memo-table)))
  (assert-equal "6.6 Recursion depth 5 triggers widening at 5 instances (depth 0..4)"
                5 (spec-memo-instance-count memo-rec 'down)))

(display "\n[RESULT] All Specialization Memoization & Widening tests PASSED!\n")
