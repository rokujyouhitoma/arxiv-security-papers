;;; =======================================================================
;;; ULisp R7RS-large Library: (scheme ideque) — SRFI 134 Immutable Deques
;;; Specification: R7RS-large Red Edition / SRFI 134
;;; Conforms to DSN-33 Architecture Specification & Issue #710
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme ideque)
  (import (scheme base))
  (export
    ;; Constructors
    ideque ideque-tabulate ideque-unfold ideque-unfold-right
    ;; Predicates
    ideque? ideque-empty? ideque= ideque-any ideque-every
    ;; Queue operations
    ideque-front ideque-back
    ideque-remove-front ideque-remove-back
    ideque-add-front ideque-add-back
    ideque-ref
    ideque-take ideque-take-right
    ideque-drop ideque-drop-right
    ideque-split-at
    ;; The whole ideque
    ideque-length ideque-append ideque-reverse ideque-count ideque-zip
    ;; Mapping
    ideque-map ideque-filter-map
    ideque-for-each ideque-for-each-right
    ideque-fold ideque-fold-right
    ideque-append-map
    ;; Filtering
    ideque-filter ideque-remove ideque-partition
    ;; Searching
    ideque-find ideque-find-right
    ideque-take-while ideque-take-while-right
    ideque-drop-while ideque-drop-while-right
    ideque-span ideque-break
    ;; Conversion
    list->ideque ideque->list
    generator->ideque ideque->generator)
  (begin))
