;;; =======================================================================
;;; R7RS Library: (ulisp concurrency passes split-planes)
;;; Conforms to DSN-37 Section 1.2, 8.1, 12.1 & Phase 3 Task 3.1 (Issue #637)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (ulisp concurrency passes split-planes)
  (export
    ;; Pass Procedures & AST Predicates
    split-planes-pass
    split-planes-ast
    asc-kernel?
    boundary-bridge?
    extract-free-variables
    classify-capture-mode
    reset-asc-kernel-counter!

    ;; Injection API
    synapse-split-planes-descriptor
    inject-synapse-split-planes-pass!
    remove-synapse-split-planes-pass!)
  (import (scheme base))
  (include "pass_split_planes.scm"))

