;;; =======================================================================
;;; ULisp R7RS-large Library: (scheme mapping) — SRFI 146 Mappings
;;; Specification: R7RS-large Tangerine Edition / SRFI 146
;;; Conforms to DSN-33 Architecture Specification & Issue #709
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme mapping)
  (import (scheme base))
  (export
    ;; Constructors
    mapping mapping-unfold
    mapping/ordered mapping-unfold/ordered
    ;; Predicates
    mapping? mapping-contains? mapping-empty? mapping-disjoint?
    ;; Accessors
    mapping-ref mapping-ref/default mapping-key-comparator
    ;; Updaters
    mapping-adjoin mapping-adjoin!
    mapping-set mapping-set!
    mapping-replace mapping-replace!
    mapping-delete mapping-delete!
    mapping-delete-all mapping-delete-all!
    mapping-intern mapping-intern!
    mapping-update mapping-update!
    mapping-update/default mapping-update!/default
    mapping-pop mapping-pop!
    mapping-search mapping-search!
    ;; The whole mapping
    mapping-size mapping-find mapping-count
    mapping-any? mapping-every?
    mapping-keys mapping-values mapping-entries
    ;; Mapping and folding
    mapping-map mapping-for-each mapping-fold
    mapping-map->list
    mapping-filter mapping-filter!
    mapping-remove mapping-remove!
    mapping-partition mapping-partition!
    ;; Copying and conversion
    mapping-copy mapping->alist
    alist->mapping alist->mapping!
    alist->mapping/ordered alist->mapping/ordered!
    ;; Submappings & Set-theoretic operations
    mapping=? mapping<? mapping>? mapping<=? mapping>=?
    mapping-union mapping-intersection mapping-difference mapping-xor
    mapping-union! mapping-intersection! mapping-difference! mapping-xor!
    ;; Ordered key operations
    mapping-min-key mapping-max-key
    mapping-min-value mapping-max-value
    mapping-min-entry mapping-max-entry
    mapping-key-predecessor mapping-key-successor
    mapping-range= mapping-range< mapping-range> mapping-range<= mapping-range>=
    mapping-range=! mapping-range<! mapping-range>! mapping-range<=! mapping-range>=!
    mapping-split
    mapping-catenate mapping-catenate!
    mapping-map/monotone mapping-map/monotone!
    mapping-fold/reverse
    ;; Comparators
    mapping-comparator make-mapping-comparator)
  (begin))

