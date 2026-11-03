;;; =======================================================================
;;; ULisp R7RS §4.1.7 include-ci Case-Insensitive Inclusion Test Suite
;;; Conforms to DSN-33 Architecture Specification & Issue #659
;;; =======================================================================

(define (equal? a b)
  (cond
    ((eq? a b) #t)
    ((and (pair? a) (pair? b))
     (and (equal? (car a) (car b))
          (equal? (cdr a) (cdr b))))
    ((and (string? a) (string? b))
     (string=? a b))
    (else #f)))

(define (test name expected actual)
  (if (equal? expected actual)
      (begin
        (write-string "  [PASS] ")
        (write-string name)
        (write-char #\newline)
        (flush-output-port)
        #t)
      (begin
        (write-string "  [FAIL] ")
        (write-string name)
        (write-string " - Expected: ")
        (display expected)
        (write-string ", Actual: ")
        (display actual)
        (write-char #\newline)
        (flush-output-port)
        (exit 1))))

(write-string "=== Running ULisp R7RS include-ci Tests ===\n")

;;; --- Test 1: include-ci loads uppercase file and normalizes identifiers to lowercase ---
(write-string "--- Test 1: include-ci file inclusion ---\n")
(include-ci "tests/fixture_ci_upper.scm")

(test "include-ci normalized function call calculate-upper-sum" 30 (calculate-upper-sum 12 18))
(test "include-ci normalized variable uppercase-test-constant" 42 uppercase-test-constant)
(test "include-ci preserves string literal case" "HELLO WORLD" uppercase-literal-string)
(test "include-ci conditional branching true" 20 (evaluate-upper-cond #t 10))
(test "include-ci conditional branching false" 8 (evaluate-upper-cond #f 10))

(write-string "=== All include-ci Tests Passed Successfully! ===\n")

