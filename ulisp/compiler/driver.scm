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
      (let* ((ast010     (desugar-libraries-and-imports forms))
             (ast020     (expand-macros-in-forms ast010))
             (ast030-top (rewrite-top-level ast020))
             (ast030     (desugar-all ast030-top))
             (ast050     (cp0-optimize ast030))
             (ast060     (lvn-all ast050))
             (ast070     (anf-all ast060))
             (ast080     (annotate-all ast070))
             (ast090     (rtyper-all ast080))
             (ast100     (contify-all ast090))
             (ast110     (closure-convert ast100))
             (ast120     (alias-escape-all ast110))
             (lir130     (generate-lir ast120)))
        (cond
          ((eq? target 'c)
           (emit-c lir130 gc-mode))
          ((eq? target 'aarch64)
           (emit-aarch64 lir130 gc-mode))
          (else
           (emit-x86-64 lir130 gc-mode))))))

