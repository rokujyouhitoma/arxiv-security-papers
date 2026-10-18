;;; =======================================================================
;;; Library: (scheme process-context)
;;; Specification: R7RS-small Section 7.1.11 (Process Context Library)
;;; Description: Execution process lifecycle, command-line arguments, environment
;;; =======================================================================

(define-library (scheme process-context)
  (export
    ;; §6.14 System interface
    command-line
    exit
    emergency-exit
    get-environment-variable
    get-environment-variables)

  (include "../posix.scm"))
