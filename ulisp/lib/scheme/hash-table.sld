;;; =======================================================================
;;; R7RS-large (Red Edition): (scheme hash-table) Library Definition
;;; Conforms to DSN-33 Architecture Specification, Issue #649
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme hash-table)
  (export
    ;; Type and Constructors
    make-hash-table
    hash-table
    hash-table?
    alist->hash-table

    ;; Predicates
    hash-table-contains?
    hash-table-exists?
    hash-table-empty?
    hash-table=?

    ;; Accessors & Mutators
    hash-table-ref
    hash-table-ref/default
    hash-table-set!
    hash-table-delete!
    hash-table-update!
    hash-table-update!/default
    hash-table-clear!
    hash-table-pop!

    ;; Whole-Table Operations
    hash-table-size
    hash-table-keys
    hash-table-values
    hash-table->alist
    hash-table-copy
    hash-table-merge!

    ;; Iteration & Mapping
    hash-table-for-each
    hash-table-walk
    hash-table-map
    hash-table-map->list
    hash-table-fold

    ;; Hash Functions
    string-hash
    string-ci-hash
    symbol-hash
    number-hash
    hash
    hash-by-identity)
  (import (scheme base))
  (include "lib/hashtable.scm"))

