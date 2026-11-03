;;; =======================================================================
;;; Library: (scheme write)
;;; Specification: R7RS-small Section 7.1.15 (Write Library)
;;; Description: Output formatting and object serialization
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (scheme write)
  (export
    ;; §6.13.3 Output procedures
    display
    write
    write-shared
    write-simple)

  (include "../printer.scm"))
