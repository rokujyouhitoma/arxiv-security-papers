;;; =======================================================================
;;; Library: (scheme repl)
;;; Specification: R7RS-small Section 7.1.13 (REPL Library)
;;; Description: Interactive read-eval-print loop environment specifiers
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme repl)
  (export
    ;; §6.12 Environments and evaluation
    interaction-environment)
  (import (scheme base)))
