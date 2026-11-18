;;; =======================================================================
;;; R7RS Standard Library: (scheme fixnum)
;;; Conforms to R7RS-large Tangerine Edition & SRFI 143
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme fixnum)
  (export
    ;; Constants
    fx-width
    fx-greatest
    fx-least

    ;; Predicates
    fixnum?
    fx=?
    fx<?
    fx>?
    fx<=?
    fx>=?
    fxzero?
    fxpositive?
    fxnegative?
    fxodd?
    fxeven?
    fxmax
    fxmin

    ;; Basic Arithmetic
    fx+
    fx-
    fxneg
    fx*
    fxquotient
    fxremainder
    fxabs
    fxsquare
    fxsqrt

    ;; Arithmetic with Carry
    fx+/carry
    fx-/carry
    fx*/carry

    ;; Division
    fxfloor/
    fxfloor-quotient
    fxfloor-remainder
    fxtruncate/
    fxtruncate-quotient
    fxtruncate-remainder

    ;; Bitwise Operations
    fxnot
    fxand
    fxior
    fxxor
    fxif
    fxbit-count
    fxlength
    fxfirst-set-bit
    fxbit-set?
    fxcopy-bit
    fxarithmetic-shift
    fxarithmetic-shift-left
    fxarithmetic-shift-right
    fxbit-field
    fxbit-field-rotate
    fxbit-field-reverse)
  (import (scheme base)
          (scheme bitwise))
  (include "../fixnum.scm"))
