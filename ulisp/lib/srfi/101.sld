;;; =======================================================================
;;; Library: (srfi 101)
;;; Specification: SRFI 101 (Purely Functional Random-Access Pairs and Lists)
;;; Description: Purely functional random-access lists with worst-case O(1) cons, car, cdr
;;;              and O(log n) list-ref, list-set, list-ref/update
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 101)
  (export
    ;; §2.1 / SRFI 101 Constructors
    (rename ra-quote quote)
    (rename ra-cons cons)
    (rename ra-list list)
    (rename ra-make-list make-list)

    ;; §2.1 / SRFI 101 Predicates
    (rename ra-pair? pair?)
    (rename ra-null? null?)
    (rename ra-list? list?)
    (rename ra-length<=? length<=?)

    ;; §2.1 / SRFI 101 Selectors & Composite Accessors
    (rename ra-car car)
    (rename ra-cdr cdr)
    (rename ra-car+cdr car+cdr)
    (rename ra-caar caar)
    (rename ra-cadr cadr)
    (rename ra-cdar cdar)
    (rename ra-cddr cddr)
    (rename ra-caaar caaar)
    (rename ra-caadr caadr)
    (rename ra-cadar cadar)
    (rename ra-caddr caddr)
    (rename ra-cdaar cdaar)
    (rename ra-cdadr cdadr)
    (rename ra-cddar cddar)
    (rename ra-cdddr cdddr)
    (rename ra-caaaar caaaar)
    (rename ra-caaadr caaadr)
    (rename ra-caadar caadar)
    (rename ra-caaddr caaddr)
    (rename ra-cadaar cadaar)
    (rename ra-cadadr cadadr)
    (rename ra-caddar caddar)
    (rename ra-cadddr cadddr)
    (rename ra-cdaaar cdaaar)
    (rename ra-cdaadr cdaadr)
    (rename ra-cdadar cdadar)
    (rename ra-cdaddr cdaddr)
    (rename ra-cddaar cddaar)
    (rename ra-cddadr cddadr)
    (rename ra-cdddar cdddar)
    (rename ra-cddddr cddddr)
    (rename ra-list-ref list-ref)
    (rename ra-list-tail list-tail)

    ;; §2.1 / SRFI 101 Purely Functional Updaters
    (rename ra-list-set list-set)
    (rename ra-list-ref/update list-ref/update)

    ;; §2.1 / SRFI 101 Iteration, Length, Append, Reverse & Higher-Order Procedures
    (rename ra-length length)
    (rename ra-append append)
    (rename ra-reverse reverse)
    (rename ra-map map)
    (rename ra-for-each for-each)

    ;; §2.1 / SRFI 101 Conversions
    random-access-list->linear-access-list
    linear-access-list->random-access-list
    rlist->list
    list->rlist

    ;; Prefixed aliases for non-conflicting imports
    ra-quote
    ra-cons
    ra-list
    ra-make-list
    ra-pair?
    ra-null?
    ra-list?
    ra-length<=?
    ra-car
    ra-cdr
    ra-car+cdr
    ra-caar
    ra-cadr
    ra-cdar
    ra-cddr
    ra-caaar
    ra-caadr
    ra-cadar
    ra-caddr
    ra-cdaar
    ra-cdadr
    ra-cddar
    ra-cdddr
    ra-caaaar
    ra-caaadr
    ra-caadar
    ra-caaddr
    ra-cadaar
    ra-cadadr
    ra-caddar
    ra-cadddr
    ra-cdaaar
    ra-cdaadr
    ra-cdadar
    ra-cdaddr
    ra-cddaar
    ra-cddadr
    ra-cdddar
    ra-cddddr
    ra-list-ref
    ra-list-tail
    ra-list-set
    ra-list-ref/update
    ra-length
    ra-append
    ra-reverse
    ra-map
    ra-for-each)

  (include "lib/rlist.scm"))
