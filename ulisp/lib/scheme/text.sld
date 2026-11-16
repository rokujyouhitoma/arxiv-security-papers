;;; =======================================================================
;;; Library: (scheme text)
;;; Specification: R7RS-large (Red Edition) / SRFI 135 (Immutable Texts)
;;; Description: Purely functional, immutable text sequence library with
;;;              O(1) length, O(1) subtext slicing, and logarithmic/constant indexing
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme text)
  (export
    ;; §2.1 Predicates
    text?
    textual?
    textual-null?
    textual-every
    textual-any

    ;; §2.1 Constructors
    make-text
    text
    text-tabulate
    text-unfold
    text-unfold-right

    ;; §2.1 Conversion
    textual->text
    textual->string
    textual->vector
    textual->list
    string->text
    vector->text
    list->text
    reverse-list->text
    textual->utf8
    textual->utf16be
    textual->utf16le
    textual->utf16
    utf8->text
    utf16be->text
    utf16le->text
    utf16->text

    ;; §2.1 Selection & Slicing
    text-length
    textual-length
    text-ref
    textual-ref
    subtext
    subtextual
    textual-copy
    textual-take
    textual-take-right
    textual-drop
    textual-drop-right
    textual-pad
    textual-pad-right
    textual-trim
    textual-trim-right
    textual-trim-both

    ;; §2.1 Replacement
    textual-replace

    ;; §2.1 Comparison
    textual=?
    textual<?
    textual>?
    textual<=?
    textual>=?
    textual-ci=?
    textual-ci<?
    textual-ci>?
    textual-ci<=?
    textual-ci>=?

    ;; §2.1 Prefixes & Suffixes
    textual-prefix-length
    textual-suffix-length
    textual-prefix?
    textual-suffix?

    ;; §2.1 Searching
    textual-index
    textual-index-right
    textual-skip
    textual-skip-right
    textual-contains
    textual-contains-right

    ;; §2.1 Case conversion
    textual-upcase
    textual-downcase
    textual-foldcase
    textual-titlecase

    ;; §2.1 Concatenation
    textual-append
    textual-concatenate
    textual-concatenate-reverse
    textual-join

    ;; §2.1 Fold, Map & Friends
    textual-fold
    textual-fold-right
    textual-map
    textual-for-each
    textual-map-index
    textual-for-each-index
    textual-count
    textual-filter
    textual-remove

    ;; §2.1 Replication & Splitting
    textual-replicate
    textual-split)

  (import (scheme base)
          (scheme char)
          (scheme case-lambda))
  (include "../text.scm"))
