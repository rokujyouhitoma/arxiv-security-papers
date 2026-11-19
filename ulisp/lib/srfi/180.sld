;;; =======================================================================
;;; SRFI Standard Library: (srfi 180)
;;; Conforms to SRFI 180: JSON (RFC 8259)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 180)
  (export
    json-error?
    json-error-reason
    json-null?
    json-nesting-depth-limit
    json-number-of-character-limit
    json-read
    json-write
    json-generator
    json-accumulator
    json-fold
    json-lines-read
    json-sequence-read
    string->json
    json->string
    bytes->json
    json->bytes)
  (include "../json.scm"))
