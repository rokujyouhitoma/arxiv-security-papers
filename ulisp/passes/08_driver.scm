;;; =======================================================================
;;; ULisp Compiler Pass 8: Compilation Driver & CLI Entrypoint
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
      (let* ((macro-expanded (expand-macros-in-forms forms))
             (ast0 (rewrite-top-level macro-expanded))
             (ast1 (desugar-all ast0))
             (ast2 (cp0-optimize ast1))
             (ast3 (anf-all ast2))
             (ast4 (closure-convert ast3))
             (lir  (generate-lir ast4)))
        (emit-x86-64 lir))))
