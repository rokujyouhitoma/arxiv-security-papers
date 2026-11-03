;;; =======================================================================
;;; ULisp SRFI 146 Hash Library: (srfi 146 hash) — Hashmaps
;;; Specification: SRFI 146 / R7RS-large (scheme mapping hash)
;;; Conforms to DSN-33 Architecture Specification & Issue #709
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 146 hash)
  (import (scheme mapping hash))
  (export
    hashmap hashmap-unfold
    hashmap? hashmap-contains? hashmap-empty? hashmap-disjoint?
    hashmap-ref hashmap-ref/default hashmap-key-comparator
    hashmap-adjoin hashmap-adjoin!
    hashmap-set hashmap-set!
    hashmap-replace hashmap-replace!
    hashmap-delete hashmap-delete!
    hashmap-delete-all hashmap-delete-all!
    hashmap-intern hashmap-intern!
    hashmap-update hashmap-update!
    hashmap-update/default hashmap-update!/default
    hashmap-pop hashmap-pop!
    hashmap-search hashmap-search!
    hashmap-size hashmap-find hashmap-count
    hashmap-any? hashmap-every?
    hashmap-keys hashmap-values hashmap-entries
    hashmap-map hashmap-for-each hashmap-fold
    hashmap-map->list
    hashmap-filter hashmap-filter!
    hashmap-remove hashmap-remove!
    hashmap-partition hashmap-partition!
    hashmap-copy hashmap->alist
    alist->hashmap alist->hashmap!
    hashmap=? hashmap<? hashmap>? hashmap<=? hashmap>=?
    hashmap-union hashmap-intersection hashmap-difference hashmap-xor
    hashmap-union! hashmap-intersection! hashmap-difference! hashmap-xor!
    hashmap-comparator make-hashmap-comparator)
  (begin))

