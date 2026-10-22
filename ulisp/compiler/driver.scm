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
               (gc-mode initial-gc)
               (verify #f)
               (trace #f))
      (if (null? forms)
          (list target gc-mode '() verify trace)
          (let ((first (car forms)))
            (cond
              ((and (pair? first) (eq? (car first) '!target) (pair? (cdr first)))
               (loop (cdr forms) (cadr first) gc-mode verify trace))
              ((and (pair? first) (eq? (car first) '!gc) (pair? (cdr first)))
               (loop (cdr forms) target (cadr first) verify trace))
              ((or (eq? first '--gc-stress) (eq? first '!gc-stress))
               (loop (cdr forms) target 'stress verify trace))
              ((and (pair? first) (eq? (car first) '!verify))
               (let ((vmode (if (pair? (cdr first)) (cadr first) #t)))
                 (loop (cdr forms) target gc-mode vmode trace)))
              ((or (eq? first '--trace-passes) (eq? first '!trace))
               (loop (cdr forms) target gc-mode verify #t))
              ((and (pair? first) (eq? (car first) '!trace))
               (loop (cdr forms) target gc-mode verify #t))
              (else
               (list target gc-mode forms verify trace))))))))

(define (extract-target-and-forms raw-forms)
  (let ((res (extract-directives-and-forms raw-forms)))
    (cons (car res) (caddr res))))

;;; Entry point: read all S-expressions from standard input and compile through serial pipeline
(let* ((raw (read-all-forms))
       (directives (extract-directives-and-forms raw))
       (target (car directives))
       (gc-mode (cadr directives))
       (forms (caddr directives))
       (verify-mode (cadddr directives))
       (trace-mode (car (cddddr directives))))
  (if verify-mode
      (begin
        (enable-verifier!)
        (if (eq? verify-mode 'strict)
            (set-verifier-strict! #t))))
  (if trace-mode
      (enable-nanopass-trace!))
  (if (not (null? forms))
      (let* ((ast010     (desugar-libraries-and-imports forms))
             (ast015     (expand-dsl-forms ast010))
             (ast020     (expand-macros-in-forms ast015))
             (ast025     (rewrite-top-level ast020))
             (ast030     (desugar-all ast025))
             (_v030      (if verify-mode (verify-pass-output 'desugar ast030) #t))
             (ast050     (cp0-optimize ast030))
             (ast060     (lvn-all ast050))
             (ast070     (anf-all ast060))
             (_v070      (if verify-mode (verify-pass-output 'anf ast070) #t))
             (ast080     (annotate-all ast070))
             (ast090     (rtyper-all ast080))
             (ast100     (contify-all ast090))
             (ast110     (closure-convert ast100))
             (_v110      (if verify-mode (verify-pass-output 'closure ast110) #t))
             (ast120     (alias-escape-all ast110))
             (lir130     (generate-lir ast120))
             (_v130      (if verify-mode (verify-pass-output 'ssa lir130) #t)))
        (cond
          ((eq? target 'c)
           (emit-c lir130 gc-mode))
          ((eq? target 'aarch64)
           (emit-aarch64 lir130 gc-mode))
          (else
           (emit-x86-64 lir130 gc-mode))))))

