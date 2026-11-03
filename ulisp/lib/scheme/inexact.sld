;;; =======================================================================
;;; Library: (scheme inexact)
;;; Specification: R7RS-small Section 7.1.8 (Inexact Numbers Library)
;;; Description: Floating-point transcendental functions and predicates
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme inexact)
  (export
    ;; §6.2.6 Numerical operations (Transcendental / Inexact)
    acos
    asin
    atan
    cos
    sin
    tan
    exp
    log
    sqrt
    finite?
    infinite?
    nan?))
