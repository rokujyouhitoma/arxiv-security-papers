;;; =======================================================================
;;; Library: (ulisp concurrency panic)
;;; Specification: DSN-37 Section 8.4.4 & 14.8 Task 6.3 (Issue #668)
;;; Description: Fail-Fast "Let It Crash" Semantics, Arena O(1) Instant Reset,
;;;              Channel Drop, and Assertion Guards
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (ulisp concurrency panic)
  (export
    ;; Panic Records & Allocator
    <synapse-panic-record>
    synapse-panic-record?
    synapse-panic-reason
    synapse-panic-details
    synapse-panic-source-loc
    synapse-panic-timestamp
    make-synapse-panic-record
    allocate-panic-timestamp!

    ;; Current Task Tracking
    current-synapse-task
    synapse-cleanup-task-resources!

    ;; Panic Primitives
    synapse-panic!
    synapse-secure-panic!

    ;; Task Boundary Protection
    with-synapse-task-boundary

    ;; Assertion Guards
    synapse-assert-true!
    synapse-assert)
  (import (scheme base)
          (scheme case-lambda)
          (ulisp concurrency channel)
          (ulisp concurrency arena)
          (ulisp concurrency links))
  (include "ulisp/runtime/concurrency/panic.scm"))

