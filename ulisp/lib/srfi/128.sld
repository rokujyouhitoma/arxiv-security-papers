;;; =======================================================================
;;; Library: (srfi 128)
;;; Specification: SRFI 128 (Comparators (reduced))
;;; Description: Alias library re-exporting (scheme comparator)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 128)
  (export
    comparator?
    comparator-ordered?
    comparator-hashable?
    make-comparator
    make-pair-comparator
    make-list-comparator
    make-vector-comparator
    make-eq-comparator
    make-eqv-comparator
    make-equal-comparator
    boolean-hash
    char-hash
    char-ci-hash
    string-hash
    string-ci-hash
    symbol-hash
    number-hash
    default-hash
    hash-bound
    hash-salt
    make-default-comparator
    default-comparator
    comparator-register-default!
    boolean-comparator
    char-comparator
    char-ci-comparator
    string-comparator
    string-ci-comparator
    symbol-comparator
    exact-integer-comparator
    number-comparator
    comparator-type-test-predicate
    comparator-equality-predicate
    comparator-ordering-predicate
    comparator-hash-function
    comparator-test-type
    comparator-check-type
    comparator-equal?
    comparator-compare
    comparator-hash
    =?
    <?
    >?
    <=?
    >=?
    comparator-if<=>)
  (import (scheme comparator)))

