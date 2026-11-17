;;; =======================================================================
;;; Library: (srfi 133)
;;; Specification: SRFI 133 (Vector Library / R7RS-compatible)
;;; Description: Comprehensive vector processing, constructors, predicates,
;;;              selectors, iteration, searching, mutators, and conversions
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 133)
  (export
    ;; Constructors
    make-vector
    vector
    vector-unfold
    vector-unfold-right
    vector-copy
    vector-reverse-copy
    vector-append
    vector-concatenate
    vector-append-subvectors

    ;; Predicates
    vector?
    vector-empty?
    vector=

    ;; Selectors
    vector-ref
    vector-length

    ;; Iteration
    vector-fold
    vector-fold-right
    vector-map
    vector-map!
    vector-for-each
    vector-count
    vector-cumulate

    ;; Searching
    vector-index
    vector-index-right
    vector-skip
    vector-skip-right
    vector-binary-search
    vector-any
    vector-every
    vector-partition

    ;; Mutators
    vector-set!
    vector-swap!
    vector-fill!
    vector-reverse!
    vector-copy!
    vector-reverse-copy!
    vector-unfold!
    vector-unfold-right!

    ;; Conversion
    vector->list
    reverse-vector->list
    list->vector
    reverse-list->vector
    string->vector
    vector->string)

  (include "lib/vector.scm" "lib/srfi/133.scm"))
