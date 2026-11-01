;;; =======================================================================
;;; SRFI 28: Basic Format Strings Library Definition
;;; Conforms to DSN-33 Architecture Specification, Issue #654
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 28)
  (export
    format)
  (import (scheme base))
  (include "lib/format.scm"))

