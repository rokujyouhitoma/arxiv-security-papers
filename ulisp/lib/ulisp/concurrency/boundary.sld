;;; =======================================================================
;;; Library: (ulisp concurrency boundary)
;;; Specification: DSN-37 Section 8.1, 9.1 & Phase 4 Task 4.1 (Issue #641)
;;; Description: Host-Kernel Boundary Sanitizer & Shared-Nothing Isolation
;;; =======================================================================

(define-library (ulisp concurrency boundary)
  (export
    ;; Configuration Constants
    *boundary-max-depth*
    *boundary-max-bytes*

    ;; Predicates
    immediate-value?
    shared-pointer?
    collect-all-pointers

    ;; Sanitization Procedures
    sanitize-to-arena
    sanitize-from-arena)
  (import (scheme base)
          (ulisp concurrency arena))
  (include "../../runtime/concurrency/boundary.scm"))

