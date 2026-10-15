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

(define (extract-directives-and-forms raw-forms)
  (let ((initial-gc 'all))
    (let loop ((forms raw-forms)
               (target 'x86_64)
               (gc-mode initial-gc))
      (if (null? forms)
          (list target gc-mode '())
          (let ((first (car forms)))
            (cond
              ((and (pair? first) (eq? (car first) '!target) (pair? (cdr first)))
               (loop (cdr forms) (cadr first) gc-mode))
              ((and (pair? first) (eq? (car first) '!gc) (pair? (cdr first)))
               (loop (cdr forms) target (cadr first)))
              (else
               (list target gc-mode forms))))))))

(define (extract-target-and-forms raw-forms)
  (let ((res (extract-directives-and-forms raw-forms)))
    (cons (car res) (caddr res))))

;;; Entry point: read all S-expressions from standard input and compile through serial pipeline
(let* ((raw (read-all-forms))
       (directives (extract-directives-and-forms raw))
       (target (car directives))
       (gc-mode (cadr directives))
       (forms (caddr directives)))
  (if (not (null? forms))
      (let* ((macro-expanded (expand-macros-in-forms forms))
             (ast0 (rewrite-top-level macro-expanded))
             (ast1 (desugar-all ast0))
             (ast2 (cp0-optimize ast1))
             (ast2b (lvn-all ast2))
             (ast3 (anf-all ast2b))
             (ast3b (annotate-all ast3))
             (ast3c (rtyper-all ast3b))
             (ast3d (contify-all ast3c))
             (ast4 (closure-convert ast3d))
             (ast4b (alias-escape-all ast4))
             (lir  (generate-lir ast4b)))
        (cond
          ((eq? target 'c)
           (emit-c lir gc-mode))
          ((eq? target 'aarch64)
           (emit-aarch64 lir gc-mode))
          (else
           (emit-x86-64 lir gc-mode))))))
