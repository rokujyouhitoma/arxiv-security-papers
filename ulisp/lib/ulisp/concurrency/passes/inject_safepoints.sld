;;; =======================================================================
;;; R7RS Library: (ulisp concurrency passes inject-safepoints)
;;; Conforms to DSN-37 Section 7.2, 12.4 & Phase 3 Task 3.4 (Issue #640)
;;; =======================================================================

(define-library (ulisp concurrency passes inject-safepoints)
  (export
    ;; Pass Procedures & Predicates
    inject-safepoints-pass
    inject-safepoints-kernel
    inject-safepoints-expr
    safepoint-poll-form?
    make-safepoint-poll
    lambda-form?
    named-let-form?
    asc-kernel-form?

    ;; Injection API
    synapse-inject-safepoints-descriptor
    inject-synapse-safepoints-pass!
    remove-synapse-safepoints-pass!)
  (import (scheme base))
  (include "pass_inject_safepoints.scm"))

