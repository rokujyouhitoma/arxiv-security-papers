;;; =======================================================================
;;; Library: (scheme lseq)
;;; Specification: R7RS-large Red Edition / SRFI 127 (Lazy Sequences)
;;; Description: Generator-backed lazy sequences (lseqs)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme lseq)
  (export
    ;; §2.1 / SRFI 127 Constructors & Predicates
    generator->lseq
    lseq?
    lseq=?
    ;; §2.1 / SRFI 127 Selectors
    lseq-car
    lseq-first
    lseq-cdr
    lseq-rest
    lseq-ref
    lseq-take
    lseq-drop
    ;; §2.1 / SRFI 127 Whole Lazy Sequence
    lseq-realize
    lseq->generator
    lseq-length
    lseq-append
    lseq-zip
    ;; §2.1 / SRFI 127 Mapping, Filtering & Searching
    lseq-map
    lseq-for-each
    lseq-filter
    lseq-remove
    lseq-find
    lseq-find-tail
    lseq-take-while
    lseq-drop-while
    lseq-any
    lseq-every
    lseq-index
    lseq-member
    lseq-memq
    lseq-memv)

  (import (scheme base))
  (include "../lseq.scm"))

