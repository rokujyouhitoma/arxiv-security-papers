;;; =======================================================================
;;; Library: (scheme stream)
;;; Specification: R7RS-large Red Edition / SRFI 41 (Streams)
;;; Description: Lazy even streams and stream comprehensions
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme stream)
  (export
    stream-null
    stream-cons
    stream?
    stream-null?
    stream-pair?
    stream-car
    stream-cdr
    stream-lambda
    define-stream
    list->stream
    port->stream
    stream
    stream->list
    stream-append
    stream-concat
    stream-constant
    stream-drop
    stream-drop-while
    stream-filter
    stream-fold
    stream-for-each
    stream-from
    stream-iterate
    stream-length
    stream-let
    stream-map
    stream-of
    stream-range
    stream-ref
    stream-reverse
    stream-scan
    stream-take
    stream-take-while
    stream-unfold
    stream-unfolds
    stream-zip)
  (import (scheme base)
          (scheme lazy)
          (scheme case-lambda))
  (include "../stream.scm"))

