;;; =======================================================================
;;; Library: (scheme list-queue)
;;; Specification: R7RS-large Red Edition / SRFI 117 (Queues based on lists)
;;; Description: Mutable O(1) double-ended list queues (tconc)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme list-queue)
  (export
    ;; §2.1 / SRFI 117 Constructors & Predicates
    make-list-queue
    list-queue
    list-queue-copy
    list-queue-unfold
    list-queue-unfold-right
    list-queue?
    list-queue-empty?
    ;; §2.1 / SRFI 117 Accessors & Mutators
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
    ;; §2.1 / SRFI 117 Concatenation & Mapping
    list-queue-append
    list-queue-append!
    list-queue-concatenate
    list-queue-map
    list-queue-map!
    list-queue-for-each)

  (import (scheme base))
  (include "../list-queue.scm"))

