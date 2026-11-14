;;; =======================================================================
;;; Library: (srfi 252)
;;; Specification: SRFI 252: Property Testing
;;; Description: Property-based testing framework, SRFI 158-compliant
;;;              generators, deterministic PRNG seed control, and SRFI 64
;;;              test runner integration
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 252)
  (export
    test-property
    test-property-expect-fail
    test-property-skip
    test-property-error
    test-property-error-type
    property-test-runner
    property-random-seed-set!
    property-random-seed-get
    boolean-generator
    char-generator
    string-generator
    symbol-generator
    bytevector-generator
    exact-integer-generator
    exact-rational-generator
    exact-complex-generator
    exact-real-generator
    exact-number-generator
    inexact-real-generator
    inexact-integer-generator
    inexact-rational-generator
    inexact-complex-generator
    inexact-number-generator
    pair-generator
    list-generator
    vector-generator
    sexpr-generator)
  (import (scheme base))
  (include "../property.scm"))
