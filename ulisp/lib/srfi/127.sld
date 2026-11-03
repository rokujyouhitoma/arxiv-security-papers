;;; =======================================================================
;;; Library: (srfi 127)
;;; Specification: SRFI 127 (Lazy Sequences)
;;; Description: Generator-backed lazy sequences (lseqs)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 127)
  (export
    generator->lseq
    lseq?
    lseq=?
    lseq-car
    lseq-first
    lseq-cdr
    lseq-rest
    lseq-ref
    lseq-take
    lseq-drop
    lseq-realize
    lseq->generator
    lseq-length
    lseq-append
    lseq-zip
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

  (import (scheme lseq)))

