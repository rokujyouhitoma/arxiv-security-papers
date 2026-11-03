;;; =======================================================================
;;; Library: (scheme box)
;;; Specification: R7RS-large Red Edition (Data Structures: Boxes)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme box)
  (export
    box
    box?
    unbox
    set-box!)

  (import (scheme base))
  (include "../box.scm"))

