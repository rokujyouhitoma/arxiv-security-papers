;;; =======================================================================
;;; SRFI Standard Library: (srfi 214)
;;; Conforms to SRFI 214: Flexvectors
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 214)
  (export
    ;; Constructors
    make-flexvector
    flexvector
    flexvector-unfold
    flexvector-unfold-right
    flexvector-copy
    flexvector-reverse-copy
    flexvector-append
    flexvector-concatenate
    flexvector-append-subvectors

    ;; Predicates
    flexvector?
    flexvector-empty?
    flexvector=?

    ;; Selectors
    flexvector-ref
    flexvector-front
    flexvector-back
    flexvector-length

    ;; Fixed-size Mutators
    flexvector-set!
    flexvector-swap!
    flexvector-fill!
    flexvector-reverse!
    flexvector-copy!
    flexvector-reverse-copy!

    ;; Dynamic Mutators
    flexvector-add!
    flexvector-add-front!
    flexvector-add-back!
    flexvector-remove!
    flexvector-remove-front!
    flexvector-remove-back!
    flexvector-remove-range!
    flexvector-clear!
    flexvector-trim!
    flexvector-set-length!
    flexvector-append!

    ;; Iteration & Higher-Order
    flexvector-fold
    flexvector-fold-right
    flexvector-map
    flexvector-map!
    flexvector-map/index
    flexvector-map/index!
    flexvector-append-map
    flexvector-append-map/index
    flexvector-for-each
    flexvector-for-each/index
    flexvector-filter
    flexvector-filter!
    flexvector-filter/index
    flexvector-filter/index!
    flexvector-remove
    flexvector-remove/index
    flexvector-count
    flexvector-cumulate
    flexvector-partition

    ;; Searching
    flexvector-index
    flexvector-index-right
    flexvector-skip
    flexvector-skip-right
    flexvector-binary-search
    flexvector-any
    flexvector-every

    ;; Conversions
    vector->flexvector
    flexvector->vector
    list->flexvector
    reverse-list->flexvector
    flexvector->list
    reverse-flexvector->list
    generator->flexvector
    flexvector->generator)
  (include "../flexvector.scm"))
