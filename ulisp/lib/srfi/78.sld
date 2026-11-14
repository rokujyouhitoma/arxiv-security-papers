;;; =======================================================================
;;; Library: (srfi 78)
;;; Specification: SRFI 78: Lightweight testing
;;; Description: Fast, standalone check expressions, self-documenting arrow
;;;              syntax, mode control, reporting, and SRFI 64 runner bridge
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 78)
  (export
    check
    check-ec
    check-report
    check-set-mode!
    check-reset!
    check-passed?)
  (import (scheme base))
  (include "../check.scm"))
