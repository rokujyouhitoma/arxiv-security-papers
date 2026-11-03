;;; =======================================================================
;;; Library: (scheme list)
;;; Specification: R7RS-large (Red Edition) / SRFI 1 (List Library)
;;; Description: Comprehensive list processing, constructors, predicates,
;;;              selectors, folds, unfolds, searching, filtering, and alists
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme list)
  (export
    ;; Constructors
    xcons
    cons*
    make-list
    list-tabulate
    list-copy
    iota

    ;; Predicates
    proper-list?
    circular-list?
    dotted-list?
    not-pair?
    null-list?
    list=

    ;; Selectors
    first
    second
    third
    fourth
    fifth
    sixth
    seventh
    eighth
    ninth
    tenth
    car+cdr
    take
    drop
    take-right
    drop-right
    split-at
    last
    last-pair

    ;; Miscellaneous: Fold, Unfold & Reductions
    count
    fold
    fold-right
    unfold
    unfold-right
    reduce
    reduce-right

    ;; Searching & Filtering
    filter
    remove
    partition
    find
    find-tail
    any
    every
    list-index
    take-while
    drop-while
    span
    break

    ;; Deletion & Association Lists
    delete
    delete-duplicates
    alist-cons
    alist-copy
    alist-delete

    ;; Core List Procedures (re-exported)
    cons
    car
    cdr
    pair?
    null?
    list
    length
    append
    reverse
    list-tail
    list-ref
    list-set!
    memq
    memv
    member
    assq
    assv
    assoc
    caar
    cadr
    cdar
    cddr
    caaar
    caadr
    cadar
    caddr
    cdaar
    cdadr
    cddar
    cdddr
    cadddr
    cddddr
    map
    for-each)

  (include "lib/list.scm"))
