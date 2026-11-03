;;; =======================================================================
;;; Library: (srfi 111)
;;; Specification: SRFI 111: Boxes / R7RS-large Red Edition
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 111)
  (export
    box
    box?
    unbox
    set-box!)

  (import (scheme base))
  (include "../box.scm"))

