;;; =======================================================================
;;; Library: (srfi 158)
;;; Specification: SRFI 158 (Generators and Accumulators)
;;; Description: Alias library re-exporting (scheme generator)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 158)
  (export
    generator circular-generator make-iota-generator make-range-generator
    make-coroutine-generator list->generator vector->generator
    reverse-vector->generator string->generator bytevector->generator
    make-for-each-generator make-unfold-generator
    gcons* gappend gcombine gfilter gremove gstate-filter
    gtake gdrop gtake-while gdrop-while
    gdelete gdelete-neighbor-dups gindex gselect
    gflatten ggroup gmerge gmap
    generator->list generator->reverse-list
    generator->vector generator->vector! generator->string
    generator-fold generator-for-each generator-map->list
    generator-find generator-count generator-any generator-every
    generator-unfold
    make-accumulator count-accumulator list-accumulator
    reverse-list-accumulator vector-accumulator
    reverse-vector-accumulator vector-accumulator!
    string-accumulator bytevector-accumulator bytevector-accumulator!
    sum-accumulator product-accumulator)
  (import (scheme generator)))

