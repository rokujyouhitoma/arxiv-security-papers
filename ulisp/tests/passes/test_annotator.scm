;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 04b (S-Annotator Flow-Sensitive Narrowing)
;;; Conforms to DSN-33 Architecture Specification & Issue #524
;;; =======================================================================

(define *annotator-tests-run* 0)
(define *annotator-tests-passed* 0)

(define (assert-true label cond)
  (set! *annotator-tests-run* (+ *annotator-tests-run* 1))
  (if cond
      (begin
        (set! *annotator-tests-passed* (+ *annotator-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (display "  [FAIL] ") (display label) (newline)
        (error "Assertion failed:" label))))

(define (assert-equal label expected actual)
  (set! *annotator-tests-run* (+ *annotator-tests-run* 1))
  (if (type-equal? expected actual)
      (begin
        (set! *annotator-tests-passed* (+ *annotator-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (display "  [FAIL] ") (display label)
        (display " -> Expected: ") (write expected)
        (display " but got: ") (write actual) (newline)
        (error "Assertion failed:" label))))

(display "=======================================================")
(newline)
(display " Starting Pass 04b (S-Annotator Narrowing) Detailed Test Suite")
(newline)
(display "=======================================================")
(newline)

;;; --- Group 1: Lattice Meet Operations (GLB: \sqcap) ---
(display "--- Group 1: Lattice Meet Operations (GLB) ---") (newline)

(assert-equal "type-meet bot any is bot" (type-bot) (type-meet (type-bot) (type-fixnum)))
(assert-equal "type-meet any bot is bot" (type-bot) (type-meet (type-top) (type-bot)))
(assert-equal "type-meet top fixnum is fixnum" (type-fixnum) (type-meet (type-top) (type-fixnum)))
(assert-equal "type-meet fixnum top is fixnum" (type-fixnum) (type-meet (type-fixnum) (type-top)))
(assert-equal "type-meet fixnum fixnum is fixnum" (type-fixnum) (type-meet (type-fixnum) (type-fixnum)))

;; Range meets
(assert-equal "type-meet overlapping ranges"
              '(fixnum 5 10)
              (type-meet (type-fixnum-range 0 10) (type-fixnum-range 5 15)))

(assert-equal "type-meet disjoint ranges is bot"
              (type-bot)
              (type-meet (type-fixnum-range 0 4) (type-fixnum-range 5 10)))

(assert-equal "type-meet range with unbounded fixnum"
              '(fixnum 0 10)
              (type-meet (type-fixnum-range 0 10) (type-fixnum)))

;; Disjoint types
(assert-equal "type-meet fixnum and boolean is bot"
              (type-bot)
              (type-meet (type-fixnum) (type-boolean)))

(assert-equal "type-meet pair and string is bot"
              (type-bot)
              (type-meet (type-pair (type-top) (type-top)) (type-string)))

;; Pair meets
(assert-equal "type-meet compatible pairs"
              (list 'pair (type-fixnum) (type-boolean))
              (type-meet (type-pair (type-fixnum) (type-top))
                         (type-pair (type-top) (type-boolean))))

(assert-equal "type-meet incompatible car pairs is bot"
              (type-bot)
              (type-meet (type-pair (type-fixnum) (type-top))
                         (type-pair (type-boolean) (type-top))))

;;; --- Group 2: Predicate Extraction & Branch Narrowing ---
(display "--- Group 2: Predicate Extraction & Branch Narrowing ---") (newline)

(let* ((env '((x . top)))
       (n-fix (extract-predicate-narrowing '(fixnum? x) env)))
  (assert-equal "narrowing fixnum? then is fixnum" (type-fixnum) (cdar n-fix))
  (assert-equal "narrowing fixnum? target is x" 'x (caar n-fix)))

(let* ((env '((p . top)))
       (n-pair (extract-predicate-narrowing '(pair? p) env)))
  (assert-equal "narrowing pair? then is pair" '(pair top top) (cdar n-pair)))

(let* ((env '((z . top)))
       (n-zero (extract-predicate-narrowing '(zero? z) env)))
  (assert-equal "narrowing zero? then is [0 0]" '(fixnum 0 0) (cdar n-zero)))

(let* ((env '((k . top)))
       (n-eq (extract-predicate-narrowing '(= k 42) env)))
  (assert-equal "narrowing = const then is [42 42]" '(fixnum 42 42) (cdar n-eq)))

(let* ((env '((b . top)))
       (n-not (extract-predicate-narrowing '(not (fixnum? b)) env)))
  (assert-equal "narrowing not fixnum? then is not fixnum" (type-top) (cdar n-not))
  (assert-equal "narrowing not fixnum? else is fixnum" (type-fixnum) (cddr n-not)))

;;; --- Group 3: ANF Let Fact Tracking ---
(display "--- Group 3: ANF Let Fact Tracking ---") (newline)

(let* ((env-with-fact (type-env-extend-with-fact 't0 (type-boolean) '(fixnum? x) '((x . top))))
       (fact (type-env-lookup-fact 't0 env-with-fact)))
  (assert-true "lookup fact succeeds" (pair? fact))
  (assert-equal "fact operator is fixnum?" 'fixnum? (car fact))
  (assert-equal "fact operand is x" 'x (cadr fact)))

;;; --- Group 4: End-to-End Flow-Sensitive AST Evaluation ---
(display "--- Group 4: End-to-End Flow-Sensitive AST Evaluation ---") (newline)

;; (if (fixnum? x) (+ x 1) "not-fixnum")
(reset-type-annotations!)
(let* ((expr '(if (fixnum? x) (+ x 1) "not-fixnum"))
       (env '((x . top)))
       (res-t (abstract-eval-expr expr env)))
  (assert-equal "merged branch type is top (fixnum lub string)" (type-top) res-t))

;; In then branch of (if (zero? x) (+ x 5) 0), x is [0, 0] so (+ x 5) -> [5, 5]
(reset-type-annotations!)
(let* ((expr '(if (zero? x) (+ x 5) 0))
       (env '((x . top)))
       (res-t (abstract-eval-expr expr env)))
  (assert-true "then branch arithmetic with zero? is fixnum" (type-fixnum? res-t)))

;; ANF let binding predicate then branch evaluation
(reset-type-annotations!)
(let* ((expr '(let ((t (fixnum? x)))
                (if t (+ x 10) 0)))
       (env '((x . top)))
       (res-t (abstract-eval-expr expr env)))
  (assert-true "anf let predicate produces fixnum result" (type-fixnum? res-t)))

;; narrow-var-in-branch utility
(let ((env '((x . top))))
  (assert-equal "narrow-var-in-branch then branch"
                (type-fixnum)
                (narrow-var-in-branch 'x '(fixnum? x) #t env)))

(display "=======================================================")
(newline)
(display " All ") (display *annotator-tests-passed*)
(display " Pass 04b (S-Annotator Narrowing) unit tests PASSED! (0 failures)")
(newline)
(display "=======================================================")
(newline)
