;;; =======================================================================
;;; Library: (scheme r5rs)
;;; Specification: R7RS-small Section 7.1.16 (R5RS Compatibility Library)
;;; Description: Compatibility exports conforming to Revised^5 Report
;;; =======================================================================

(define-library (scheme r5rs)
  (export
    ;; R5RS primitives & syntax
    * + - / < <= = > >= abs acos and angle append apply asin assoc assq assv
    atan begin boolean? caaaar caaadr caaar caadar caaddr caadr caar cadaar
    cadadr cadar caddar cadddr caddr cadr call-with-current-continuation
    call-with-input-file call-with-output-file call-with-values car case
    cdaaar cdaadr cdaar cdadar cdaddr cdadr cdar cddaar cddadr cddar cdddar
    cddddr cdddr cddr cdr char->integer char-alphabetic? char-ci<=? char-ci<?
    char-ci=? char-ci>=? char-ci>? char-downcase char-lower-case? char-numeric?
    char-ready? char-upcase char-upper-case? char-whitespace? char<=? char<?
    char=? char>=? char>? char? close-input-port close-output-port complex?
    cond cons current-input-port current-output-port define define-syntax
    delay display do dynamic-wind eof-object? eq? equal? eqv? eval even?
    exact->inexact exact? exp expt force for-each gcd if imag-part
    inexact->exact inexact? input-port? integer->char integer?
    interaction-environment lambda lcm length let let* let-syntax letrec
    letrec-syntax list list->string list->vector list-ref list-tail list?
    load log magnitude make-polar make-rectangular make-string make-vector
    max member memq memv min modulo negative? newline not null-environment
    null? number->string number? numerator odd? open-input-file open-output-file
    or output-port? pair? peek-char positive? procedure? quote quotient
    rational? rationalize read read-char real-part real? remainder reverse
    scheme-report-environment set! set-car! set-cdr! sin sqrt string
    string->list string->number string->symbol string-append string-ci<=?
    string-ci<? string-ci=? string-ci>=? string-ci>? string-copy string-fill!
    string-length string-ref string-set! string<=? string<? string=? string>=?
    string>? string? substring symbol->string symbol? syntax-rules tan
    truncate values vector vector->list vector-fill! vector-length vector-ref
    vector-set! vector? with-input-from-file with-output-to-file write
    write-char zero?)

  (import (scheme base)))
