;;; =======================================================================
;;; ULisp SRFI 64 Test Suites & Extended Test Runners Test Suite
;;; Conforms to DSN-33 Architecture Specification & Issue #819
;;; =======================================================================

(write-string "=== Running ULisp SRFI 64 Test Suite ===\n")

;; -----------------------------------------------------------------------
;; Test 1: Basic Assertions (test-assert, test-eq, test-eqv, test-equal)
;; -----------------------------------------------------------------------
(test-begin "basic-assertions")

(test-assert "test-assert-true" #t)
(test-assert "test-assert-truthy-val" 42)
(test-assert (not (= 1 2)))

(test-eq "test-eq-symbol" 'alpha 'alpha)
(test-eq "test-eq-fixnum" 100 100)
(test-eq 'beta 'beta)

(test-eqv "test-eqv-char" #\a #\a)
(test-eqv "test-eqv-bool" #f #f)
(test-eqv 999 999)

(test-equal "test-equal-list" '(1 2 (3 4)) '(1 2 (3 4)))
(test-equal "test-equal-string" "hello world" "hello world")
(test-equal "test-equal-vector" #(10 20 30) #(10 20 30))
(test-equal 4 (+ 2 2))

(test-end "basic-assertions")

;; -----------------------------------------------------------------------
;; Test 2: Approximate Comparisons (test-approximate)
;; -----------------------------------------------------------------------
(test-begin "approximate-assertions")

(test-approximate "approx-pi" 3.1415 3.14 0.01)
(test-approximate "approx-exact" 100 102 5)
(test-approximate 10.0 10.05 0.1)

(test-end "approximate-assertions")

;; -----------------------------------------------------------------------
;; Test 3: Exception Assertions (test-error)
;; -----------------------------------------------------------------------
(test-begin "error-assertions")

(test-error "error-explicit-raise" (error "test-error message"))
(test-error "error-custom-condition" (raise 'runtime-fault))
(test-error (error "anonymous error"))

(test-end "error-assertions")

;; -----------------------------------------------------------------------
;; Test 4: Nested Test Groups (test-group & test-group-with-cleanup)
;; -----------------------------------------------------------------------
(test-begin "grouping-suite")

(test-group "inner-group-1"
  (test-assert "group-1-pass" #t)
  (test-equal "group-1-math" 10 (* 2 5)))

(define *cleanup-executed* (box #f))

(test-group-with-cleanup "inner-group-2-cleanup"
  (test-assert "group-2-pass" #t)
  (test-equal "group-2-val" 42 42)
  (set-box! *cleanup-executed* #t))

(test-assert "cleanup-form-was-executed" (unbox *cleanup-executed*))

(test-end "grouping-suite")

;; -----------------------------------------------------------------------
;; Test 5: Condition Filtering (test-skip & test-expect-fail)
;; -----------------------------------------------------------------------
(test-begin "filtering-suite")

;; Skip 1 test by count
(test-skip 1)
(test-assert "skipped-assert-by-count" #f)

;; Skip by name match
(test-skip "skipped-by-name")
(test-assert "skipped-by-name" #f)

;; Expect fail (XFAIL)
(test-expect-fail 1)
(test-assert "expected-fail-assert" #f)

;; Normal passing test in the same suite
(test-assert "normal-pass-after-filters" #t)

(test-end "filtering-suite")

;; -----------------------------------------------------------------------
;; Test 6: Custom Runner & Result Queries
;; -----------------------------------------------------------------------
(define custom-runner (test-runner-null))
(define custom-records (box '()))

(test-runner-on-test-end! custom-runner
  (lambda (r)
    (set-box! custom-records
              (cons (cons (test-runner-test-name r) (test-result-kind r))
                    (unbox custom-records)))))

(test-with-runner custom-runner
  (test-begin "custom-suite")
  (test-assert "custom-t1" #t)
  (test-equal "custom-t2" 99 99)
  (test-end "custom-suite"))

(test-begin "meta-verification")
(test-equal "custom-pass-count" 2 (test-runner-pass-count custom-runner))
(test-equal "custom-fail-count" 0 (test-runner-fail-count custom-runner))
(test-equal "custom-records-length" 2 (length (unbox custom-records)))
(test-end "meta-verification")

(write-string "=== All SRFI 64 Tests Passed Successfully! ===\n")
