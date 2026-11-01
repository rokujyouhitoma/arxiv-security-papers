;;; =======================================================================
;;; SRFI 69: Basic Hash Tables Library Definition
;;; Conforms to DSN-33 Architecture Specification, Issue #649
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 69)
  (export
    ;; Type and Constructors
    make-hash-table
    hash-table?
    alist->hash-table

    ;; Predicates
    hash-table-exists?

    ;; Accessors & Mutators
    hash-table-ref
    hash-table-ref/default
    hash-table-set!
    hash-table-delete!
    hash-table-update!
    hash-table-update!/default
    hash-table-clear!

    ;; Whole-Table Operations
    hash-table-size
    hash-table-keys
    hash-table-values
    hash-table->alist
    hash-table-copy
    hash-table-merge!

    ;; Iteration
    hash-table-walk
    hash-table-fold

    ;; Hash Functions
    string-hash
    string-ci-hash
    symbol-hash
    hash
    hash-by-identity)
  (import (scheme base))
  (include "lib/hashtable.scm"))

