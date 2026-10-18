;;; =======================================================================
;;; Library: (scheme char)
;;; Specification: R7RS-small Section 7.1.3 (Character Library)
;;; Description: Case-insensitive character and string operations, classifications
;;; =======================================================================

(define-library (scheme char)
  (export
    ;; §6.6 Characters
    char-alphabetic?
    char-numeric?
    char-whitespace?
    char-upper-case?
    char-lower-case?
    digit-value
    char-upcase
    char-downcase
    char-foldcase
    char-ci=?
    char-ci<?
    char-ci>?
    char-ci<=?
    char-ci>=?

    ;; §6.7 Strings
    string-upcase
    string-downcase
    string-foldcase
    string-ci=?
    string-ci<?
    string-ci>?
    string-ci<=?
    string-ci>=?)

  (include "../char.scm"
           "../string.scm"))
