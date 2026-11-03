;;; =======================================================================
;;; Library: (scheme read)
;;; Specification: R7RS-small Section 7.1.12 (Read Library)
;;; Description: S-expression lexical analysis and parsing
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme read)
  (export
    ;; §6.13.2 Input procedures
    read)

  (include "../reader.scm"))
