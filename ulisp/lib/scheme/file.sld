;;; =======================================================================
;;; Library: (scheme file)
;;; Specification: R7RS-small Section 7.1.7 (File Library)
;;; Description: File-system based textual and binary stream operations
;;; =======================================================================

(define-library (scheme file)
  (export
    ;; §6.13.1 File ports
    call-with-input-file
    call-with-output-file
    with-input-from-file
    with-output-to-file
    open-input-file
    open-output-file
    open-binary-input-file
    open-binary-output-file

    ;; §6.14 System interface
    file-exists?
    delete-file)

  (include "../posix.scm"
           "../port.scm"))
