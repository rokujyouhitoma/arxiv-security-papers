;;; =======================================================================
;;; Library: (scheme complex)
;;; Specification: R7RS-small Section 7.1.4 (Complex Numbers Library)
;;; Description: Rectangular and polar complex number arithmetic
;;; =======================================================================

(define-library (scheme complex)
  (export
    ;; §6.2.6 Numerical operations (Complex)
    make-rectangular
    make-polar
    real-part
    imag-part
    magnitude
    angle))
