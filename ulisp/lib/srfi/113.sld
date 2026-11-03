;;; =======================================================================
;;; Library: (srfi 113)
;;; Specification: SRFI 113 (Sets and bags)
;;; Description: Alias library re-exporting (scheme set)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 113)
  (export
    set set-unfold
    set? set-contains? set-empty? set-disjoint?
    set-member set-element-comparator
    set-adjoin set-adjoin! set-replace set-replace!
    set-delete set-delete! set-delete-all set-delete-all! set-search!
    set-size set-find set-count set-any? set-every?
    set-map set-for-each set-fold
    set-filter set-filter! set-remove set-remove!
    set-partition set-partition!
    set-copy set->list list->set list->set!
    set=? set<? set>? set<=? set>=?
    set-union set-intersection set-difference set-xor
    set-union! set-intersection! set-difference! set-xor!
    bag bag-unfold
    bag? bag-contains? bag-empty? bag-disjoint?
    bag-member bag-element-comparator
    bag-adjoin bag-adjoin! bag-replace bag-replace!
    bag-delete bag-delete! bag-delete-all bag-delete-all! bag-search!
    bag-size bag-unique-size bag-find bag-count bag-any? bag-every?
    bag-map bag-for-each bag-fold
    bag-filter bag-filter! bag-remove bag-remove!
    bag-partition bag-partition!
    bag-copy bag->list list->bag list->bag!
    bag=? bag<? bag>? bag<=? bag>=?
    bag-union bag-intersection bag-difference bag-xor
    bag-union! bag-intersection! bag-difference! bag-xor!
    bag-sum bag-sum! bag-product bag-product!
    bag-element-count bag-for-each-unique bag-fold-unique
    bag-increment! bag-decrement!
    bag->set set->bag set->bag!
    bag->alist alist->bag)
  (import (scheme set)))

