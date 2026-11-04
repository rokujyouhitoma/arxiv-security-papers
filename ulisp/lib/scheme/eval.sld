;;; =======================================================================
;;; Library: (scheme eval)
;;; Specification: R7RS-small Section 7.1.6 (Eval Library)
;;; Description: Dynamic program evaluation and environment specifiers
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme eval)
  (export
    ;; §6.12 Environments and evaluation
    eval
    environment)
  (import (scheme base)))
