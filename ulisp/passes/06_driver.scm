;;; =======================================================================
;;; ULisp Compiler Pass 6: Compilation Driver & CLI Entrypoint
;;; Conforms to DSN-33 Architecture Specification
;;; =======================================================================

(define (read-all-forms)
  (let loop ((acc '()))
    (let ((expr (read)))
      (if (eof-object? expr)
          (reverse acc)
          (loop (cons expr acc))))))

;;; Entry point: read all S-expressions from standard input and compile through serial pipeline
(let ((forms (read-all-forms)))
  (if (not (null? forms))
      (let* ((ast0 (rewrite-top-level forms))
             (ast1 (desugar-all ast0))
             (ast2 (closure-convert ast1)))
        (compile-program ast2))))
