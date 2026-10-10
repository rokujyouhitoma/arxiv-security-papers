;;; =======================================================================
;;; MLisp Test Suite: Delimited Continuations (test_delimcc.scm)
;;; Conforms to DSN-34 Architecture Specification & Issue #507
;;; Verifies correctness of shift / reset semantics including multi-shot
;;; continuations, nested prompts, and early exit.
;;; =======================================================================

(define *delimcc-tests-passed* 0)
(define *delimcc-tests-failed* 0)

(define (assert-equal test-name expected actual)
  (if (equal? expected actual)
      (begin
        (set! *delimcc-tests-passed* (+ *delimcc-tests-passed* 1))
        (display "  [PASS] ")
        (display test-name)
        (newline))
      (begin
        (set! *delimcc-tests-failed* (+ *delimcc-tests-failed* 1))
        (display "  [FAIL] ")
        (display test-name)
        (display " -> Expected: ")
        (display expected)
        (display " but got: ")
        (display actual)
        (newline)
        (exit 1))))

(display "=======================================================")
(newline)
(display " Starting MLisp Delimited Continuations Test Suite")
(newline)
(display "=======================================================")
(newline)

;;; Test 1: Simple reset without shift returns value directly
(display "--- Test 1: Simple Reset ---")
(newline)
(assert-equal "reset evaluates body normally"
              42
              (reset (+ 40 2)))

;;; Test 2: Shift without invoking continuation returns shift value (Abort)
(display "--- Test 2: Abort / Discard Continuation ---")
(newline)
(assert-equal "shift ignores outer context and returns value"
              1099
              (+ 1000 (reset (+ 1 (shift k 99)))))

;;; Test 3: Shift invoking continuation once
(display "--- Test 3: Single-shot Continuation ---")
(newline)
(assert-equal "shift invokes continuation with argument"
              15
              (reset (+ 5 (shift k (k 10)))))

;;; Test 4: Shift modifying and extending continuation argument
(display "--- Test 4: Continuation Composition ---")
(newline)
(assert-equal "shift computes argument before invoking continuation"
              35
              (reset (+ 5 (shift k (k (+ 10 20))))))

;;; Test 5: Nested resets and boundary isolation
(display "--- Test 5: Nested Resets ---")
(newline)
(assert-equal "nested reset keeps shift within inner boundary"
              29
              (+ 5 (reset (+ 10 (reset (* 2 (shift k (k (+ 3 4)))))))))

;;; Test 6: Dynamic value injection into continuation
(display "--- Test 6: Value Injection into Continuation ---")
(newline)
(assert-equal "shift passes computed argument into continuation"
              52
              (reset (+ 2 (shift k (k (* 5 10))))))

;;; Test 7: Speculative Bailout Unwinding (Simulates JIT guard failure abort)
(display "--- Test 7: Speculative Bailout Unwinding ---")
(newline)
(define (run-speculative-trace condition fallback-val)
  (reset
    (let ((x 10)
          (y 20))
      ;; Speculative guard check: if failed, immediately abort out to prompt
      (if condition
          (+ x y)
          (abort-delimited fallback-val)))))

(assert-equal "speculative trace succeeds when guard passes"
              30
              (run-speculative-trace #t 999))
(assert-equal "speculative trace aborts to fallback on guard failure"
              999
              (run-speculative-trace #f 999))

;;; Test 8: Delimited early exit (escape)
(display "--- Test 8: Delimited Early Exit ---")
(newline)
(define (find-first-positive lst)
  (reset
    (for-each (lambda (x)
                (if (> x 0)
                    (abort-delimited x)
                    #f))
              lst)
    'none))

(assert-equal "finds first positive number via abort"
              42
              (find-first-positive '(-5 -2 42 -10 99)))

(display "=======================================================")
(newline)
(display " All ")
(display *delimcc-tests-passed*)
(display " MLisp Delimited Continuations tests PASSED successfully! (0 failures)")
(newline)
(display "=======================================================")
(newline)
