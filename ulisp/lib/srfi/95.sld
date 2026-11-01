;;; =======================================================================
;;; SRFI 95: Sorting and Merging (SLIB Compatible)
;;; Conforms to DSN-33 Architecture Specification & Issue #655
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 95)
  (export
    sorted?
    merge
    merge!
    sort
    sort!)
  (import (scheme base))
  (include "lib/sort.scm"))

