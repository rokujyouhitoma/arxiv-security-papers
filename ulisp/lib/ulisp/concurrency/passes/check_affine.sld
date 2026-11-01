;;; =======================================================================
;;; R7RS Library: (ulisp concurrency passes check-affine)
;;; Conforms to DSN-37 Section 4.3, 12.2 & Phase 3 Task 3.2 (Issue #638)
;;; =======================================================================

(define-library (ulisp concurrency passes check-affine)
  (export
    ;; Pass Procedures & Predicates
    check-affine-pass
    check-affine-kernel
    check-affine-expr
    linear-variable?
    affine-forbidden-syntax?

    ;; Environment Operations
    lin-env-lookup
    lin-env-set
    lin-env-add-available
    lin-env-mark-moved
    lin-env-unconsumed

    ;; Injection API
    synapse-check-affine-descriptor
    inject-synapse-check-affine-pass!
    remove-synapse-check-affine-pass!)
  (import (scheme base))
  (include "pass_check_affine.scm"))

