;;; =======================================================================
;;; ULisp SRFI 146 Library: (srfi 146) — Mappings
;;; Specification: SRFI 146 / R7RS-large (scheme mapping)
;;; Conforms to DSN-33 Architecture Specification & Issue #709
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 146)
  (import (scheme mapping))
  (export
    mapping mapping-unfold
    mapping/ordered mapping-unfold/ordered
    mapping? mapping-contains? mapping-empty? mapping-disjoint?
    mapping-ref mapping-ref/default mapping-key-comparator
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
    mapping-size mapping-find mapping-count
    mapping-any? mapping-every?
    mapping-keys mapping-values mapping-entries
    mapping-map mapping-for-each mapping-fold
    mapping-map->list
    mapping-filter mapping-filter!
    mapping-remove mapping-remove!
    mapping-partition mapping-partition!
    mapping-copy mapping->alist
    alist->mapping alist->mapping!
    alist->mapping/ordered alist->mapping/ordered!
    mapping=? mapping<? mapping>? mapping<=? mapping>=?
    mapping-union mapping-intersection mapping-difference mapping-xor
    mapping-union! mapping-intersection! mapping-difference! mapping-xor!
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
    mapping-comparator make-mapping-comparator)
  (begin))

