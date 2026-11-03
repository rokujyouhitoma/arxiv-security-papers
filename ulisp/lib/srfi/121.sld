;;; =======================================================================
;;; Library: (srfi 121)
;;; Specification: SRFI 121 (Generators - R7RS-large Red Edition)
;;; Description: Compatibility library exporting the SRFI 121 subset of (scheme generator)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 121)
  (export
    generator circular-generator make-iota-generator make-range-generator
    make-coroutine-generator list->generator vector->generator
    reverse-vector->generator string->generator bytevector->generator
    make-for-each-generator make-unfold-generator
    gcons* gappend gcombine gfilter gremove gstate-filter
    gtake gdrop gtake-while gdrop-while
    gdelete gdelete-neighbor-dups gindex gselect
    generator->list generator->reverse-list
    generator->vector generator->vector! generator->string
    generator-fold generator-for-each
    generator-find generator-count generator-any generator-every
    generator-unfold)
  (import (scheme generator)))

