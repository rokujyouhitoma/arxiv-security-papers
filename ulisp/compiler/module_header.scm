;;; =======================================================================
;;; ULisp Compiler Module Header & Interface Specification
;;; Conforms to DSN-33 Architecture Specification & Issue #608
;;; =======================================================================

;; I/O Compatibility Macros (expanding to stdlib runtime ports)
(define-syntax newline
  (syntax-rules ()
    ((newline) (port-newline *stdout-port*))
    ((newline p) (port-newline p))))

(define-syntax display
  (syntax-rules ()
    ((display val) (port-display val *stdout-port*))
    ((display val p) (port-display val p))))

(define-syntax write
  (syntax-rules ()
    ((write val) (port-write val *stdout-port*))
    ((write val p) (port-write val p))))

(define-syntax read
  (syntax-rules ()
    ((read) (port-read *stdin-port*))
    ((read p) (port-read p))))
