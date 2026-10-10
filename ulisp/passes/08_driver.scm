;;; =======================================================================
;;; ULisp Compiler Pass 8: Compilation Driver & CLI Entrypoint
;;; Conforms to DSN-33 Architecture Specification & Issue #504
;;; =======================================================================

(define (read-all-forms)
  (let loop ((acc '()))
    (let ((expr (read)))
      (if (eof-object? expr)
          (reverse acc)
          (loop (cons expr acc))))))

(define (extract-target-and-forms raw-forms)
  (if (and (pair? raw-forms)
           (pair? (car raw-forms))
           (eq? (caar raw-forms) '!target))
      (cons (cadar raw-forms) (cdr raw-forms))
      (cons 'x86_64 raw-forms)))

;;; Entry point: read all S-expressions from standard input and compile through serial pipeline
(let* ((raw (read-all-forms))
       (target-and-forms (extract-target-and-forms raw))
       (target (car target-and-forms))
       (forms (cdr target-and-forms)))
  (if (not (null? forms))
      (let* ((macro-expanded (expand-macros-in-forms forms))
             (ast0 (rewrite-top-level macro-expanded))
             (ast1 (desugar-all ast0))
             (ast2 (cp0-optimize ast1))
             (ast3 (anf-all ast2))
             (ast4 (closure-convert ast3))
             (lir  (generate-lir ast4)))
        (cond
          ((eq? target 'c)
           (emit-c lir))
          ((eq? target 'aarch64)
           (emit-aarch64 lir))
          (else
           (emit-x86-64 lir))))))
