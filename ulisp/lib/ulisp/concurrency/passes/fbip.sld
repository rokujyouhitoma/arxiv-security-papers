;;; =======================================================================
;;; R7RS Library: (ulisp concurrency passes fbip)
;;; Conforms to DSN-37 Section 1.1, 12.3 & Phase 3 Task 3.3 (Issue #639)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (ulisp concurrency passes fbip)
  (export
    ;; Pass Procedures & Predicates
    fbip-pass
    fbip-transform-kernel
    fbip-transform-block
    collect-drops
    affine-drop-form?
    cons-form?

    ;; Injection API
    synapse-fbip-descriptor
    inject-synapse-fbip-pass!
    remove-synapse-fbip-pass!)
  (import (scheme base))
  (include "pass_fbip.scm"))

