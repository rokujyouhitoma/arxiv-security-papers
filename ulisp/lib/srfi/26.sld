;;; =======================================================================
;;; Library: (srfi 26)
;;; Specification: SRFI 26: Notation for Specializing Parameters without Currying (cut, cute)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 26)
  (export
    cut
    cute
    <>
    <...>)

  (import (scheme base)))
