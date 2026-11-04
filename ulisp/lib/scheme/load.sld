;;; =======================================================================
;;; Library: (scheme load)
;;; Specification: R7RS-small Section 7.1.10 (Load Library)
;;; Description: Dynamic Scheme source file loader
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme load)
  (export
    ;; §6.14 System interface (Dynamic load)
    load)
  (import (scheme base)
          (scheme eval)
          (scheme file)
          (scheme read)))
