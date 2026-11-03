;;; =======================================================================
;;; R7RS Library: (ulisp concurrency passes inline-hotpath)
;;; Conforms to DSN-37 Section 4.3, 12.4 & Phase 4 Task 4.1 (Issue #682)
;;; =======================================================================

(define-library (ulisp concurrency passes inline-hotpath)
  (export
    ;; Pass Procedures & Predicates
    inline-hotpath-pass
    inline-hotpath-kernel
    inline-hotpath-expr
    eliminate-redundant-type-checks
    inline-concurrency-primitives

    ;; Type Environment API
    make-type-env
    type-env-lookup
    type-env-extend
    statically-typed?

    ;; AST & Predicate Helpers
    linear-var-name?
    arena-var-name?
    atomic-box-var-name?
    task-var-name?
    eliminated-assertion?

    ;; Injection API
    synapse-inline-hotpath-descriptor
    inject-synapse-inline-hotpath-pass!
    remove-synapse-inline-hotpath-pass!)
  (import (scheme base))
  (include "pass_inline_hotpath.scm"))

