;;; =======================================================================
;;; Library: (srfi 141)
;;; Specification: SRFI 141: Integer Division / R7RS-large Tangerine
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 141)
  (export
    ;; Floor division
    floor/
    floor-quotient
    floor-remainder

    ;; Truncate division
    truncate/
    truncate-quotient
    truncate-remainder

    ;; Ceiling division
    ceiling/
    ceiling-quotient
    ceiling-remainder

    ;; Round division
    round/
    round-quotient
    round-remainder

    ;; Euclidean division
    euclidean/
    euclidean-quotient
    euclidean-remainder

    ;; Centered division
    centered/
    centered-quotient
    centered-remainder)

  (import (scheme base))
  (include "../math.scm"))

