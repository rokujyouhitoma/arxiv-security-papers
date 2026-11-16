;;; =======================================================================
;;; Library: (srfi 124)
;;; Specification: SRFI 124: Ephemerons / R7RS-large Red Edition
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md §2.1
;;; =======================================================================

(define-library (srfi 124)
  (export
    make-ephemeron
    ephemeron?
    ephemeron-broken?
    ephemeron-key
    ephemeron-datum
    reference-barrier)

  (import (scheme base))
  (include "../ephemeron.scm"))
