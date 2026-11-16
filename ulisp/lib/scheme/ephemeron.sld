;;; =======================================================================
;;; Library: (scheme ephemeron)
;;; Specification: R7RS-large Red Edition (Data Structures: Ephemerons)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md §2.1
;;; Reference: SRFI 124 (Arthur A. Gleckler)
;;; =======================================================================

(define-library (scheme ephemeron)
  (export
    make-ephemeron
    ephemeron?
    ephemeron-broken?
    ephemeron-key
    ephemeron-datum
    reference-barrier)

  (import (scheme base))
  (include "../ephemeron.scm"))
