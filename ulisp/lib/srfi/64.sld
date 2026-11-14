;;; =======================================================================
;;; Library: (srfi 64)
;;; Specification: SRFI 64 (A Scheme API for test suites)
;;; Description: Standard test suites, group nesting, assertion macros,
;;;              skip / expect-fail predicates, and customizable test runners
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 64)
  (export
    ;; Execution & Grouping Syntax
    test-begin
    test-end
    test-group
    test-group-with-cleanup
    test-apply
    test-with-runner

    ;; Assertion Syntax
    test-assert
    test-eqv
    test-eq
    test-equal
    test-approximate
    test-error

    ;; Specifier Predicates & Skip / Expect-Fail Syntax
    test-match-nth
    test-match-all
    test-match-any
    test-match-name
    test-skip
    test-expect-fail
    test-read-eval-string

    ;; Test Results & Status Inquiry
    test-runner-group-path
    test-result-ref
    test-result-set!
    test-result-clear
    test-result-remove
    test-result-kind
    test-passed?
    test-result-alist
    test-result-alist!

    ;; Test Runner Object Operations & Parameters
    test-runner?
    test-runner-reset
    test-runner-null
    test-runner-simple
    test-runner-current
    test-runner-factory
    test-runner-get
    test-runner-create
    test-runner-test-name
    test-runner-pass-count
    test-runner-pass-count!
    test-runner-fail-count
    test-runner-fail-count!
    test-runner-xpass-count
    test-runner-xpass-count!
    test-runner-xfail-count
    test-runner-xfail-count!
    test-runner-skip-count
    test-runner-skip-count!
    test-runner-group-stack
    test-runner-group-stack!
    test-runner-on-test-begin
    test-runner-on-test-begin!
    test-runner-on-test-end
    test-runner-on-test-end!
    test-runner-on-group-begin
    test-runner-on-group-begin!
    test-runner-on-group-end
    test-runner-on-group-end!
    test-runner-on-final
    test-runner-on-final!
    test-runner-on-bad-count
    test-runner-on-bad-count!
    test-runner-on-bad-end-name
    test-runner-on-bad-end-name!
    test-runner-aux-value
    test-runner-aux-value!

    ;; Standard / Simple Runner Callbacks
    test-on-group-begin-simple
    test-on-group-end-simple
    test-on-bad-count-simple
    test-on-bad-end-name-simple
    test-on-final-simple
    test-on-test-end-simple)

  (import (scheme base)
          (scheme write)
          (scheme complex))
  (include "../test.scm"))
