;;; =======================================================================
;;; Library: (scheme division)
;;; Specification: R7RS-large Tangerine Edition (Numerics: Division)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme division)
  (export
    floor/
    floor-quotient
    floor-remainder
    truncate/
    truncate-quotient
    truncate-remainder
    ceiling/
    ceiling-quotient
    ceiling-remainder
    round/
    round-quotient
    round-remainder
    euclidean/
    euclidean-quotient
    euclidean-remainder
    centered/
    centered-quotient
    centered-remainder)

  (import (scheme base))
  (include "../math.scm"))

