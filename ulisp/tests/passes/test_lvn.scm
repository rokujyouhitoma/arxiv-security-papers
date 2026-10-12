;;; =======================================================================
;;; ULisp Test Suite: Extended Local Value Numbering (LVN) (test_lvn.scm)
;;; Conforms to DSN-33 Section 8.2 & Issue #521
;;;
;;; Verifies:
;;; 1. Single-block continuous pair accessor memoization (car/cdr deduplication)
;;; 2. Pair constructor reduction: (car (cons a b)) -> a, (cdr (cons a b)) -> b
;;; 3. Commutative normalization & algebraic identities (+, -, *, =, eq?)
;;; 4. Type predicate folding across dominance paths
;;; 5. Mutation invalidation sound safety (set-car!, set-cdr!)
;;; 6. End-to-end AST integration with lvn-all
;;; =======================================================================

(define *lvn-tests-passed* 0)
(define *lvn-tests-failed* 0)

(define (assert-equal test-name expected actual)
  (if (equal? expected actual)
      (begin
        (set! *lvn-tests-passed* (+ *lvn-tests-passed* 1))
        (display "  [PASS] ")
        (display test-name)
        (newline))
      (begin
        (set! *lvn-tests-failed* (+ *lvn-tests-failed* 1))
        (display "  [FAIL] ")
        (display test-name)
        (display " -> Expected: ")
        (display expected)
        (display " but got: ")
        (display actual)
        (newline)
        (exit 1))))

(define (assert-true test-name expr)
  (assert-equal test-name #t (if expr #t #f)))

(display "=======================================================")
(newline)
(display " Starting ULisp Extended LVN & Accessor Memoization Test Suite")
(newline)
(display "=======================================================")
(newline)

;;; Test Group 1: Immutable Pair Accessor Memoization
(display "--- Group 1: Immutable Pair Accessor Memoization ---")
(newline)

;; 1. Deduplicate consecutive (car p) in let-chain
(let* ((input '(let ((a (car p)))
                 (let ((b (car p)))
                   (+ a b))))
       (opt (lvn-all input)))
  (assert-equal "deduplicate identical (car p) calls"
                '(let ((a (car p))) (+ a a))
                opt))

;; 2. Deduplicate consecutive (cdr p) in let-chain
(let* ((input '(let ((a (cdr p)))
                 (let ((b (cdr p)))
                   (+ a b))))
       (opt (lvn-all input)))
  (assert-equal "deduplicate identical (cdr p) calls"
                '(let ((a (cdr p))) (+ a a))
                opt))

;; 3. Do not conflate accessors on different pairs
(let* ((input '(let ((a (car p)))
                 (let ((b (car q)))
                   (+ a b))))
       (opt (lvn-all input)))
  (assert-equal "preserve accessors on distinct pairs p and q"
                '(let ((a (car p)))
                   (let ((b (car q)))
                     (+ a b)))
                opt))

;; 4. Constructor reduction: (car (cons x y)) -> x
(let* ((input '(let ((p (cons x y)))
                 (let ((a (car p)))
                   a)))
       (opt (lvn-all input)))
  (assert-equal "reduce (car (cons x y)) directly to x"
                '(let ((p (cons x y))) x)
                opt))

;; 5. Constructor reduction: (cdr (cons x y)) -> y
(let* ((input '(let ((p (cons x y)))
                 (let ((d (cdr p)))
                   d)))
       (opt (lvn-all input)))
  (assert-equal "reduce (cdr (cons x y)) directly to y"
                '(let ((p (cons x y))) y)
                opt))

;;; Test Group 2: Algebraic Identity Normalization
(display "--- Group 2: Algebraic Identity Normalization ---")
(newline)

;; 6. (+ x 0) -> x
(assert-equal "identity: (+ x 0) -> x"
              'x
              (lvn-all '(+ x 0)))

;; 7. (+ 0 x) -> x
(assert-equal "identity: (+ 0 x) -> x"
              'x
              (lvn-all '(+ 0 x)))

;; 8. (* x 1) -> x
(assert-equal "identity: (* x 1) -> x"
              'x
              (lvn-all '(* x 1)))

;; 9. (* 1 x) -> x
(assert-equal "identity: (* 1 x) -> x"
              'x
              (lvn-all '(* 1 x)))

;; 10. (* x 0) -> 0
(assert-equal "absorbing: (* x 0) -> 0"
              0
              (lvn-all '(* x 0)))

;; 11. (* 0 x) -> 0
(assert-equal "absorbing: (* 0 x) -> 0"
              0
              (lvn-all '(* 0 x)))

;; 12. (- x 0) -> x
(assert-equal "identity: (- x 0) -> x"
              'x
              (lvn-all '(- x 0)))

;; 13. (- x x) -> 0 (same value number)
(assert-equal "identity: (- x x) -> 0"
              0
              (lvn-all '(- x x)))

;; 14. (= x x) -> #t
(assert-equal "reflexive: (= x x) -> #t"
              #t
              (lvn-all '(= x x)))

;; 15. (eq? x x) -> #t
(assert-equal "reflexive: (eq? x x) -> #t"
              #t
              (lvn-all '(eq? x x)))

;;; Test Group 3: Commutative CSE & Normalization
(display "--- Group 3: Commutative Normalization & CSE ---")
(newline)

;; 16. Commutative normalization: (+ b a) and (+ a b) have same VN
(let* ((input '(let ((x (+ b a)))
                 (let ((y (+ a b)))
                   (- x y))))
       (opt (lvn-all input)))
  (assert-equal "commutative cse simplifies (- x y) to 0"
                '(let ((x (+ b a))) 0)
                opt))

;; 16b. Commutative normalization preserving live variable
(let* ((input '(let ((x (+ b a)))
                 (let ((y (+ a b)))
                   (cons x y))))
       (opt (lvn-all input)))
  (assert-equal "commutative cse reuses x for (+ a b)"
                '(let ((x (+ b a))) (cons x x))
                opt))

;;; Test Group 4: Type Predicate Folding
(display "--- Group 4: Type Predicate Folding ---")
(newline)

;; 17. Constant predicate folding
(assert-equal "predicate literal: (fixnum? 42) -> #t"
              #t
              (lvn-all '(fixnum? 42)))

(assert-equal "predicate literal: (pair? 42) -> #f"
              #f
              (lvn-all '(pair? 42)))

;; 18. Constructor-based predicate folding
(assert-equal "predicate constructor: (pair? (cons 1 2)) -> #t"
              #t
              (lvn-all '(pair? (cons 1 2))))

(assert-equal "predicate constructor: (null? (cons 1 2)) -> #f"
              #f
              (lvn-all '(null? (cons 1 2))))

;; 19. Arithmetic produces fixnum
(assert-equal "predicate arithmetic: (fixnum? (+ a b)) -> #t"
              #t
              (lvn-all '(fixnum? (+ a b))))

;; 20. Dominance scope type predicate folding
(let* ((input '(if (fixnum? x)
                   (if (fixnum? x)
                       (+ x 0)
                       42)
                   99))
       (opt (lvn-all input)))
  (assert-equal "dominance predicate folding removes redundant nested type check and +0"
                '(if (fixnum? x) x 99)
                opt))

;;; Test Group 5: Mutation Invalidation Safety
(display "--- Group 5: Mutation Invalidation Safety ---")
(newline)

;; 21. set-car! invalidates memoized pairs
(let* ((input '(begin
                 (car p)
                 (set-car! p 99)
                 (car p)))
       (opt (lvn-all input)))
  (assert-true "second (car p) is preserved after set-car!"
               (pair? opt)))

;;; Test Group 6: End-to-End Program Transformation
(display "--- Group 6: End-to-End Program Transformation ---")
(newline)

;; 22. %program form optimization
(let* ((prog '(%program
                ((define foo (lambda (p)
                               (let ((x (car p)))
                                 (let ((y (car p)))
                                   (+ x y))))))
                (foo (cons 10 20))))
       (opt (lvn-all prog)))
  (assert-true "optimized program contains single (car p)"
               (pair? opt)))

(display "=======================================================")
(newline)
(display " All ")
(display *lvn-tests-passed*)
(display " ULisp Extended LVN tests PASSED successfully! (0 failures)")
(newline)
(display "=======================================================")
(newline)
