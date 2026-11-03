;;; =======================================================================
;;; Library: (scheme charset)
;;; Specification: R7RS-large Red Edition / SRFI 14 (Character-set Library)
;;; Description: Bitmap character sets and set algebra operations
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme charset)
  (export
    ;; §2.1 / SRFI 14 Predicates, Comparison & Hashing
    char-set?
    char-set=
    char-set<=
    char-set-hash
    ;; §2.1 / SRFI 14 Cursors & Iteration
    char-set-cursor
    char-set-ref
    char-set-cursor-next
    end-of-char-set?
    char-set-fold
    char-set-unfold
    char-set-unfold!
    char-set-for-each
    char-set-map
    ;; §2.1 / SRFI 14 Constructors & Conversions
    char-set-copy
    char-set
    list->char-set
    list->char-set!
    string->char-set
    string->char-set!
    char-set-filter
    char-set-filter!
    ucs-range->char-set
    ucs-range->char-set!
    ->char-set
    ;; §2.1 / SRFI 14 Querying
    char-set-size
    char-set-count
    char-set->list
    char-set->string
    char-set-contains?
    char-set-every
    char-set-any
    ;; §2.1 / SRFI 14 Character-Set Algebra
    char-set-adjoin
    char-set-delete
    char-set-adjoin!
    char-set-delete!
    char-set-complement
    char-set-union
    char-set-intersection
    char-set-difference
    char-set-xor
    char-set-diff+intersection
    char-set-complement!
    char-set-union!
    char-set-intersection!
    char-set-difference!
    char-set-xor!
    char-set-diff+intersection!
    ;; §2.1 / SRFI 14 Standard Character Sets
    char-set:lower-case
    char-set:upper-case
    char-set:title-case
    char-set:letter
    char-set:digit
    char-set:letter+digit
    char-set:graphic
    char-set:printing
    char-set:whitespace
    char-set:iso-control
    char-set:punctuation
    char-set:symbol
    char-set:hex-digit
    char-set:blank
    char-set:ascii
    char-set:empty
    char-set:full)

  (import (scheme base))
  (include "../charset.scm"))

