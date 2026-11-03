;;; =======================================================================
;;; Library: (srfi 193)
;;; Specification: SRFI 193 (Command line) & R7RS-small §6.14
;;; Description: Command-line inspection and script path procedures
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define-library (srfi 193)
  (export
    ;; §6.14 / SRFI 193 Command line procedures
    command-line
    command-name
    command-args
    script-file
    script-directory)

  (import (scheme base))
  (include "../posix.scm"))
