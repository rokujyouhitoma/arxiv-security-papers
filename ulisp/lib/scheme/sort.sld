;;; =======================================================================
;;; (scheme sort): R7RS-large Tangerine Sort Library
;;; Conforms to DSN-33 Architecture Specification & Issue #655
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme sort)
  (export
    list-sorted?
    vector-sorted?
    list-merge
    vector-merge
    list-sort
    list-sort!
    list-stable-sort
    vector-sort
    vector-sort!
    vector-stable-sort)
  (import (scheme base))
  (include "lib/sort.scm"))

