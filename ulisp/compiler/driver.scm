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
              ((or (eq? first '--target-lir)
                   (and (pair? first) (eq? (car first) '!target) (pair? (cdr first)) (eq? (cadr first) 'lir)))
               (loop (cdr forms) 'lir gc-mode verify trace))
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

;;; -----------------------------------------------------------------------
;;; Two-Layer Compiler Pipeline API (Frontend/LIR & Backend)
;;; Conforms to DSN-33 Architecture Specification & Issue #590
;;; -----------------------------------------------------------------------

(define (compile-to-lir forms verify-mode trace-mode)
  (if verify-mode
      (begin
        (enable-verifier!)
        (if (eq? verify-mode 'strict)
            (set-verifier-strict! #t))))
  (if trace-mode
      (enable-nanopass-trace!))
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
         (_v130      (if verify-mode (verify-pass-output 'lir lir130) #t)))
    lir130))

(define (compile-backend lir-ast target gc-mode)
  (cond
    ((eq? target 'c)
     (emit-c lir-ast gc-mode))
    ((eq? target 'aarch64)
     (emit-aarch64 lir-ast gc-mode))
    (else
     (emit-x86-64 lir-ast gc-mode))))

;;; -----------------------------------------------------------------------
;;; Canonical LIR S-expression Serializer
;;; Resolves compiled quotation symbols under native AOT without '?' masking
;;; -----------------------------------------------------------------------

(define *lir-known-symbols*
  '((%lir-program . "%lir-program")
    (%lir-functions . "%lir-functions")
    (%lir-function . "%lir-function")
    (%lir-main . "%lir-main")
    (strings . "strings")
    (stackmaps . "stackmaps")
    (frame-size . "frame-size")
    (body . "body")
    (params . "params")
    (%mov . "%mov")
    (%load . "%load")
    (%store . "%store")
    (%add . "%add")
    (%sub . "%sub")
    (%mul . "%mul")
    (%div . "%div")
    (%cmp . "%cmp")
    (%jump . "%jump")
    (%jump-cond . "%jump-cond")
    (%label . "%label")
    (%call . "%call")
    (%call-closure . "%call-closure")
    (%return . "%return")
    (%alloc . "%alloc")
    (%safepoint . "%safepoint")
    (%rax . "%rax")
    (%rbx . "%rbx")
    (%rcx . "%rcx")
    (%rdx . "%rdx")
    (%rsi . "%rsi")
    (%rdi . "%rdi")
    (%rbp . "%rbp")
    (%rsp . "%rsp")
    (%r8 . "%r8")
    (%r9 . "%r9")
    (%r10 . "%r10")
    (%r11 . "%r11")
    (%r12 . "%r12")
    (%r13 . "%r13")
    (%r14 . "%r14")
    (%r15 . "%r15")
    (%al . "%al")
    (equal . "equal")
    (not-equal . "not-equal")
    (less . "less")
    (less-equal . "less-equal")
    (greater . "greater")
    (greater-equal . "greater-equal")
    (zero . "zero")
    (not-zero . "not-zero")))

(define (lir-symbol->string sym)
  (let ((entry (assq sym *lir-known-symbols*)))
    (if entry
        (cdr entry)
        (let ((s (symbol->string sym)))
          (if (string=? s "?")
              "?"
              s)))))

(define (dump-lir-token val)
  (cond
    ((symbol? val)
     (display (lir-symbol->string val)))
    ((number? val)
     (display val))
    ((string? val)
     (write val))
    ((boolean? val)
     (display (if val "#t" "#f")))
    ((null? val)
     (display "()"))
    ((pair? val)
     (display "(")
     (let loop ((curr val) (first? #t))
       (cond
         ((null? curr)
          (display ")"))
         ((pair? curr)
          (if (not first?) (display " "))
          (dump-lir-token (car curr))
          (loop (cdr curr) #f))
         (else
          (display " . ")
          (dump-lir-token curr)
          (display ")")))))
    (else
     (write val))))

(define (dump-lir-ast lir-ast)
  (dump-lir-token lir-ast)
  (newline))

;;; Entry point: read all S-expressions from standard input and compile through two-layer pipeline
(let* ((raw (read-all-forms))
       (directives (extract-directives-and-forms raw))
       (target (car directives))
       (gc-mode (cadr directives))
       (forms (caddr directives))
       (verify-mode (cadddr directives))
       (trace-mode (car (cddddr directives))))
  (if (not (null? forms))
      (cond
        ;; 1. LIR Intermediate Output Mode (--target-lir or (!target lir))
        ((eq? target 'lir)
         (let ((lir (compile-to-lir forms verify-mode trace-mode)))
           (dump-lir-ast lir)))
        ;; 2. Direct LIR Ingestion Mode (Input is already a Canonical LIR S-expression)
        ((and (pair? forms) (pair? (car forms)) (eq? (caar forms) '%lir-program))
         (let ((lir (car forms)))
           (if verify-mode
               (begin
                 (enable-verifier!)
                 (verify-pass-output 'lir lir)))
           (compile-backend lir target gc-mode)))
        ;; 3. Standard Full Pipeline (Frontend -> LIR -> Backend)
        (else
         (let ((lir (compile-to-lir forms verify-mode trace-mode)))
           (compile-backend lir target gc-mode))))))

