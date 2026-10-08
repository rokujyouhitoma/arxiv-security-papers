;;; =======================================================================
;;; ULisp Compiler Pass 5: Compilation Driver & CLI Entrypoint
;;; Conforms to DSN-33 Architecture Specification
;;; =======================================================================

(define (read-all-forms)
  (let loop ((acc '()))
    (let ((expr (read)))
      (if (eof-object? expr)
          (reverse acc)
          (loop (cons expr acc))))))

;;; Entry point: read all S-expressions from standard input and compile
(let ((forms (read-all-forms)))
  (if (not (null? forms))
      (compile-program (rewrite-top-level forms))))
