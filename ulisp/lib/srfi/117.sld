;;; =======================================================================
;;; Library: (srfi 117)
;;; Specification: SRFI 117 (Queues based on lists)
;;; Description: Mutable O(1) double-ended list queues (tconc)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 117)
  (export
    make-list-queue
    list-queue
    list-queue-copy
    list-queue-unfold
    list-queue-unfold-right
    list-queue?
    list-queue-empty?
    list-queue-front
    list-queue-back
    list-queue-list
    list-queue-first-last
    list-queue-add-front!
    list-queue-add-back!
    list-queue-remove-front!
    list-queue-remove-back!
    list-queue-remove-all!
    list-queue-set-list!
    list-queue-append
    list-queue-append!
    list-queue-concatenate
    list-queue-map
    list-queue-map!
    list-queue-for-each)

  (import (scheme list-queue)))

