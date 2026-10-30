;;; =======================================================================
;;; Library: (scheme base)
;;; Specification: R7RS-small Section 7.1.1 (Base Library)
;;; Description: Core Scheme syntax, primitives, pairs, lists, strings, vectors, control
;;; =======================================================================

(define-library (scheme base)
  (export
    ;; §4.1 Primitive expression types
    quote
    lambda
    if
    set!
    include
    include-ci

    ;; §4.2 Derived expression types
    cond
    case
    and
    or
    when
    unless
    let
    let*
    letrec
    letrec*
    let-values
    let*-values
    begin
    do
    make-parameter
    parameterize
    guard
    quasiquote
    unquote
    unquote-splicing

    ;; §5.3 Variable definitions
    define
    define-values
    define-record-type
    define-syntax
    syntax-rules

    ;; §6.1 Equivalence predicates
    eq?
    eqv?
    equal?

    ;; §6.2 Numbers
    number?
    integer?
    zero?
    positive?
    negative?
    odd?
    even?
    max
    min
    +
    *
    -
    /
    abs
    quotient
    remainder
    modulo
    floor/
    floor-quotient
    floor-remainder
    truncate/
    truncate-quotient
    truncate-remainder
    exact-integer-sqrt
    gcd
    lcm
    square
    expt
    =
    <
    >
    <=
    >=

    ;; §6.3 Booleans
    boolean?
    not
    boolean=?

    ;; §6.4 Pairs and lists
    pair?
    cons
    car
    cdr
    set-car!
    set-cdr!
    caar
    cadr
    cdar
    cddr
    null?
    list?
    make-list
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
    list-copy

    ;; §6.5 Symbols
    symbol?
    symbol=?
    symbol->string
    string->symbol

    ;; §6.6 Characters
    char?
    char=?
    char<?
    char>?
    char<=?
    char>=?
    char->integer
    integer->char

    ;; §6.7 Strings
    string?
    make-string
    string
    string-length
    string-ref
    string-set!
    string=?
    string<?
    string>?
    string<=?
    string>=?
    substring
    string-append
    string->list
    list->string
    string-copy
    string-copy!
    string-fill!

    ;; §6.8 Vectors
    vector?
    make-vector
    vector
    vector-length
    vector-ref
    vector-set!
    vector->list
    list->vector
    vector->string
    string->vector
    vector-copy
    vector-copy!
    vector-fill!

    ;; §6.9 Bytevectors
    bytevector?
    make-bytevector
    bytevector
    bytevector-length
    bytevector-u8-ref
    bytevector-u8-set!
    bytevector-copy
    bytevector-copy!
    bytevector-append
    utf8->string
    string->utf8

    ;; §6.10 Control features
    procedure?
    apply
    map
    for-each
    call-with-current-continuation
    call/cc
    values
    call-with-values
    dynamic-wind

    ;; §6.11 Exceptions
    with-exception-handler
    raise
    raise-continuable
    error
    error-object?
    error-object-message
    error-object-irritants
    error-object-traceback
    read-error?
    file-error?

    ;; §6.13 Input and output
    current-input-port
    current-output-port
    current-error-port
    port?
    input-port?
    output-port?
    textual-port?
    binary-port?
    open-input-string
    open-output-string
    get-output-string
    close-port
    close-input-port
    close-output-port
    eof-object?
    eof-object
    read-char
    peek-char
    read-line
    char-ready?
    read-string
    read-u8
    peek-u8
    u8-ready?
    read-bytevector
    read-bytevector!
    write-char
    write-u8
    write-string
    write-bytevector
    flush-output-port)

  (include "../list.scm"
           "../equality.scm"
           "../math.scm"
           "../vector.scm"
           "../bytevector.scm"
           "../string.scm"
           "../values.scm"
           "../parameter.scm"
           "../exception.scm"
           "../continuation.scm"
           "../port.scm"))
