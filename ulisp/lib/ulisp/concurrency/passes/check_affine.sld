;;; =======================================================================
;;; R7RS Library: (ulisp concurrency passes check-affine)
;;; Conforms to DSN-37 Section 4.3, 12.2 & Phase 3 Task 3.2 (Issue #638)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (ulisp concurrency passes check-affine)
  (export
    ;; Pass Procedures & Predicates
    check-affine-pass
    check-affine-kernel
    check-affine-expr
    linear-variable?
    linear-variable-name-hint?
    linear-type?
    linear-constructor-op?
    linear-constructor-expr?
    infer-linear-binding?
    affine-forbidden-syntax?

    ;; Signatures & Return Type Propagation (Issue #792)
    *default-affine-signatures*
    register-affine-signature!
    reset-affine-signatures!
    lookup-affine-signature
    scan-form-signatures
    infer-expr-linear-return-type

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

