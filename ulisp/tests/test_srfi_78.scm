;;; =======================================================================
;;; ULisp SRFI 78 Lightweight Testing Test Suite
;;; Conforms to DSN-33 Architecture Specification & Issue #820
;;; =======================================================================



;; Reset check state to known baseline
(check-set-mode! 'report-failed)
(check-reset!)

;; -----------------------------------------------------------------------
;; Test 1: Basic Checks (=> equal?)
;; -----------------------------------------------------------------------
(write-string "--- Test 1: Basic Checks ---\n")

(check (+ 1 1) => 2)
(check (* 6 7) => 42)
(check 'alpha => 'alpha)
(check (not #f) => #t)
(check (string-append "hello " "world") => "hello world")
(check (cons 1 '(2 3)) => '(1 2 3))
(check (vector 10 20 30) => #(10 20 30))
(check (car (list 99 100)) => 99)

;; -----------------------------------------------------------------------
;; Test 2: Custom Equality Predicates (=> <equal-pred>)
;; -----------------------------------------------------------------------
(write-string "--- Test 2: Custom Equality Predicates ---\n")

;; Helper: abs (if not already defined)
(define (abs x)
  (if (< x 0) (- 0 x) x))

;; Approximate numeric comparison
(define (approx-equal? expected actual)
  (< (abs (- actual expected)) 0.01))

(check 3.1415 (=> approx-equal?) 3.14)
(check 100.005 (=> approx-equal?) 100.0)

;; Case-insensitive string comparison
(check "Scheme" (=> string-ci=?) "SCHEME")
(check "ULisp" (=> string-ci=?) "ulisp")

;; Custom list length predicate
(define (same-length? a b)
  (= (length a) (length b)))

(check '(a b c) (=> same-length?) '(1 2 3))

;; -----------------------------------------------------------------------
;; Test 3: Eager Comprehension Checks (check-ec)
;; -----------------------------------------------------------------------
(write-string "--- Test 3: Eager Comprehension Checks (check-ec) ---\n")

;; Iteration over integer range 0..4
(check-ec (: x 5) (+ x 0) => x)

;; Iteration over range from 1 to 5
(check-ec (: x 1 6) (* x 2) (=> =) (+ x x))

;; Iteration over list elements
(check-ec (:list s '("alpha" "beta" "gamma")) (string? s) => #t)

;; -----------------------------------------------------------------------
;; Test 4: Mode Switching & Exception Isolation
;; -----------------------------------------------------------------------
(write-string "--- Test 4: Mode Switching & Exception Isolation ---\n")

;; Off mode: checks are ignored, no counting or output
(check-set-mode! 'off)
(check (+ 999 1) => 0) ; Would fail if executed, but skipped in 'off' mode

;; Summary mode: silent per-check execution
(check-set-mode! 'summary)
(check (* 2 2) => 4)
(check (* 3 3) => 9)

;; Restore default 'report-failed mode
(check-set-mode! 'report-failed)

;; Exception isolation: expression raising an error must be caught and recorded as failed
(define (test-exception-handling)
  ;; Save current counts
  (let ((saved-passed (unbox *check-passed-count*))
        (saved-failed (unbox *check-failed-count*)))
    ;; In off/summary mode, execute a check that raises an error
    (check-set-mode! 'summary)
    (check (error "deliberate test error") => 42)
    ;; Check that failed count increased by 1
    (let ((new-failed (unbox *check-failed-count*)))
      (check-set-mode! 'report-failed)
      (if (= new-failed (+ saved-failed 1))
          ;; Revert the deliberate failure so total suite remains 100% clean
          (begin
            (set-box! *check-failed-count* saved-failed)
            (set-box! *check-total-count* (- (unbox *check-total-count*) 1))
            #t)
          #f))))

(check (test-exception-handling) => #t)

;; -----------------------------------------------------------------------
;; Test 5: Integration with SRFI 64 Test Runners
;; -----------------------------------------------------------------------
(write-string "--- Test 5: Integration with SRFI 64 Test Runners ---\n")

(define test-runner (test-runner-null))

(test-with-runner test-runner
  (test-begin "srfi-78-bridge-suite")
  (check (+ 10 20) => 30)
  (check (list 'x 'y) => '(x y))
  (test-end "srfi-78-bridge-suite"))

;; Verify that SRFI 64 runner recorded the checks
(check (test-runner-pass-count test-runner) => 2)
(check (test-runner-fail-count test-runner) => 0)

;; -----------------------------------------------------------------------
;; Test 6: Verification of check-passed? and check-report
;; -----------------------------------------------------------------------
(write-string "--- Test 6: Final Verification & Reporting ---\n")

;; All checks executed so far should pass cleanly
(check (check-passed?) => #t)

;; Verify check-report returns #t when 0 checks failed
(check (check-report) => #t)

