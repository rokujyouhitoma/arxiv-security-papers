;;; =======================================================================
;;; ULisp SRFI 134 Library: (srfi 134) — Immutable Deques
;;; Specification: SRFI 134 / R7RS-large (scheme ideque)
;;; Conforms to DSN-33 Architecture Specification & Issue #710
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 134)
  (import (scheme ideque))
  (export
    ideque ideque-tabulate ideque-unfold ideque-unfold-right
    ideque? ideque-empty? ideque= ideque-any ideque-every
    ideque-front ideque-back
    ideque-remove-front ideque-remove-back
    ideque-add-front ideque-add-back
    ideque-ref
    ideque-take ideque-take-right
    ideque-drop ideque-drop-right
    ideque-split-at
    ideque-length ideque-append ideque-reverse ideque-count ideque-zip
    ideque-map ideque-filter-map
    ideque-for-each ideque-for-each-right
    ideque-fold ideque-fold-right
    ideque-append-map
    ideque-filter ideque-remove ideque-partition
    ideque-find ideque-find-right
    ideque-take-while ideque-take-while-right
    ideque-drop-while ideque-drop-while-right
    ideque-span ideque-break
    list->ideque ideque->list
    generator->ideque ideque->generator)
  (begin))
