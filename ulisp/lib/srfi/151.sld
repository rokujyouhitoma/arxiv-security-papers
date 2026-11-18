;;; =======================================================================
;;; Library: (srfi 151)
;;; Specification: SRFI 151: Bitwise Operations / R7RS-large Tangerine
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 151)
  (export
    ;; Basic boolean operations
    bitwise-not
    bitwise-and
    bitwise-ior
    bitwise-xor
    bitwise-eqv
    bitwise-nand
    bitwise-nor
    bitwise-andc1
    bitwise-andc2
    bitwise-orc1
    bitwise-orc2

    ;; Integer operations & shift
    arithmetic-shift
    bit-count
    integer-length
    bitwise-if

    ;; Single-bit operations
    bit-set?
    copy-bit
    bit-swap
    any-bit-set?
    every-bit-set?
    first-set-bit

    ;; Bit field operations
    bit-field
    bit-field-any?
    bit-field-every?
    bit-field-clear
    bit-field-set
    bit-field-replace
    bit-field-replace-same
    bit-field-rotate
    bit-field-reverse

    ;; Bitwise fold, unfold & generator
    bitwise-fold
    bitwise-for-each
    bitwise-unfold
    make-bitwise-generator

    ;; Conversions
    bits->list
    list->bits
    bits->vector
    vector->bits
    bits

    ;; Compatibility aliases (SRFI 33 / SRFI 60)
    bitwise-merge
    extract-bit-field
    test-bit-field?
    clear-bit-field
    replace-bit-field
    copy-bit-field
    ash)

  (import (scheme base))
  (include "../bitwise.scm"))
