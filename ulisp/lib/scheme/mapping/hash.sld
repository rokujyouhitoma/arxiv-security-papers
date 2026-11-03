;;; =======================================================================
;;; ULisp R7RS-large Library: (scheme mapping hash) — SRFI 146 Hashmaps
;;; Specification: R7RS-large Tangerine Edition / SRFI 146
;;; Conforms to DSN-33 Architecture Specification & Issue #709
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme mapping hash)
  (import (scheme base))
  (export
    ;; Constructors
    hashmap hashmap-unfold
    ;; Predicates
    hashmap? hashmap-contains? hashmap-empty? hashmap-disjoint?
    ;; Accessors
    hashmap-ref hashmap-ref/default hashmap-key-comparator
    ;; Updaters
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
    ;; The whole hashmap
    hashmap-size hashmap-find hashmap-count
    hashmap-any? hashmap-every?
    hashmap-keys hashmap-values hashmap-entries
    ;; Mapping and folding
    hashmap-map hashmap-for-each hashmap-fold
    hashmap-map->list
    hashmap-filter hashmap-filter!
    hashmap-remove hashmap-remove!
    hashmap-partition hashmap-partition!
    ;; Copying and conversion
    hashmap-copy hashmap->alist
    alist->hashmap alist->hashmap!
    ;; Submappings & Set-theoretic operations
    hashmap=? hashmap<? hashmap>? hashmap<=? hashmap>=?
    hashmap-union hashmap-intersection hashmap-difference hashmap-xor
    hashmap-union! hashmap-intersection! hashmap-difference! hashmap-xor!
    ;; Comparators
    hashmap-comparator make-hashmap-comparator)
  (begin))

