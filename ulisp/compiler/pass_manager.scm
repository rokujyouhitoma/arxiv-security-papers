;;; =======================================================================
;;; ULisp Compiler: Unified Pass Manager & Optimization Pipeline Scheduler
;;; Conforms to DSN-33 Architecture Specification & Issue #598
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Pass Descriptor Record & Accessors
;;; -----------------------------------------------------------------------
;;; Each pass is represented as a structured 10-element tuple:
;;;   (list 'pass-descriptor id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory?)

(define (make-pass-descriptor id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory?)
  (list 'pass-descriptor id name category opt-level pass-fn verifier-phase in-lang out-lang prerequisites mandatory?))

(define (pass-descriptor? obj)
  (and (pair? obj) (eq? (car obj) 'pass-descriptor)))

(define (pass-id p) (cadr p))
(define (pass-name p) (caddr p))
(define (pass-category p) (cadddr p))
(define (pass-opt-level p) (car (cddddr p)))
(define (pass-fn p) (cadr (cddddr p)))
(define (pass-verifier-phase p) (caddr (cddddr p)))
(define (pass-in-lang p) (cadddr (cddddr p)))
(define (pass-out-lang p) (car (cddddr (cddddr p))))
(define (pass-prerequisites p) (cadr (cddddr (cddddr p))))
(define (pass-mandatory? p) (caddr (cddddr (cddddr p))))

;;; -----------------------------------------------------------------------
;;; 2. Global Pass Registry
;;; -----------------------------------------------------------------------

(define *pass-registry* (cons '() '()))

(define (pass-registry)
  (car *pass-registry*))

(define (reset-pass-registry!)
  (set-car! *pass-registry* '()))

(define (register-pass! descriptor)
  (let* ((id (pass-id descriptor))
         (current (car *pass-registry*))
         (filtered (let loop ((ps current))
                     (cond
                       ((null? ps) '())
                       ((eq? (pass-id (car ps)) id) (loop (cdr ps)))
                       (else (cons (car ps) (loop (cdr ps))))))))
    (set-car! *pass-registry* (append filtered (list descriptor)))
    id))

(define (lookup-pass id)
  (let loop ((ps (car *pass-registry*)))
    (cond
      ((null? ps)
       (error "lookup-pass: unknown compiler pass" id))
      ((eq? (pass-id (car ps)) id)
       (car ps))
      (else
       (loop (cdr ps))))))

(define (pass-registered? id)
  (let loop ((ps (car *pass-registry*)))
    (cond
      ((null? ps) #f)
      ((eq? (pass-id (car ps)) id) #t)
      (else (loop (cdr ps))))))

;;; -----------------------------------------------------------------------
;;; 3. Pipeline Configuration & Tuning Options
;;; -----------------------------------------------------------------------

(define *pipeline-opt-level* (cons 2 '()))
(define (pipeline-opt-level) (car *pipeline-opt-level*))
(define (set-pipeline-opt-level! lvl) (set-car! *pipeline-opt-level* lvl))

(define *pipeline-time-passes* (cons #f '()))
(define (pipeline-time-passes?) (car *pipeline-time-passes*))
(define (enable-pipeline-time-passes!) (set-car! *pipeline-time-passes* #t))
(define (disable-pipeline-time-passes!) (set-car! *pipeline-time-passes* #f))

(define *pipeline-dump-ir* (cons #f '()))
(define (pipeline-dump-ir) (car *pipeline-dump-ir*))
(define (set-pipeline-dump-ir! target) (set-car! *pipeline-dump-ir* target))

(define *pipeline-print-after-all* (cons #f '()))
(define (pipeline-print-after-all?) (car *pipeline-print-after-all*))
(define (enable-pipeline-print-after-all!) (set-car! *pipeline-print-after-all* #t))
(define (disable-pipeline-print-after-all!) (set-car! *pipeline-print-after-all* #f))

(define *pipeline-disabled-passes* (cons '() '()))
(define (pipeline-disabled-passes) (car *pipeline-disabled-passes*))

(define (disable-pass! id)
  (if (not (memq id (car *pipeline-disabled-passes*)))
      (set-car! *pipeline-disabled-passes* (cons id (car *pipeline-disabled-passes*)))))

(define (enable-pass! id)
  (set-car! *pipeline-disabled-passes*
            (let loop ((ps (car *pipeline-disabled-passes*)))
              (cond
                ((null? ps) '())
                ((eq? (car ps) id) (loop (cdr ps)))
                (else (cons (car ps) (loop (cdr ps))))))))

(define (reset-pipeline-options!)
  (set-car! *pipeline-opt-level* 2)
  (set-car! *pipeline-time-passes* #f)
  (set-car! *pipeline-dump-ir* #f)
  (set-car! *pipeline-print-after-all* #f)
  (set-car! *pipeline-disabled-passes* '()))

;;; -----------------------------------------------------------------------
;;; 4. Dynamic Pipeline Scheduling & Invariant Validation
;;; -----------------------------------------------------------------------

(define (pass-enabled? desc opt-level disabled-list)
  (let ((id (pass-id desc))
        (pass-opt (pass-opt-level desc))
        (mandatory (pass-mandatory? desc)))
    (if mandatory
        (not (memq id disabled-list))
        (and (<= pass-opt opt-level)
             (not (memq id disabled-list))))))

(define (build-pipeline opt-level disabled-list)
  (let ((all (car *pass-registry*)))
    (let loop ((ps all) (res '()))
      (if (null? ps)
          (reverse res)
          (let ((p (car ps)))
            (if (pass-enabled? p opt-level disabled-list)
                (loop (cdr ps) (cons p res))
                (loop (cdr ps) res)))))))

(define (validate-pipeline-prerequisites pass-list)
  (let loop ((ps pass-list) (seen '()))
    (if (null? ps)
        #t
        (let* ((p (car ps))
               (id (pass-id p))
               (prereqs (pass-prerequisites p)))
          (let check-prereqs ((reqs prereqs))
            (if (null? reqs)
                (loop (cdr ps) (cons id seen))
                (let ((req (car reqs)))
                  (if (not (memq req seen))
                      (error "validate-pipeline-prerequisites: missing required prerequisite pass"
                             (list 'pass id 'requires req))
                      (check-prereqs (cdr reqs))))))))))

;;; -----------------------------------------------------------------------
;;; 5. Pass Timing & Profiling Statistics
;;; -----------------------------------------------------------------------

(define *pass-manager-ticks* (cons 0 '()))
(define (current-time-monotonic-ms)
  (set-car! *pass-manager-ticks* (+ (car *pass-manager-ticks*) 1))
  (car *pass-manager-ticks*))

(define *pass-timings* (cons '() '()))

(define (reset-pass-timings!)
  (set-car! *pass-timings* '()))

(define (record-pass-timing! pass-id elapsed-ms)
  (set-car! *pass-timings*
            (append (car *pass-timings*) (list (cons pass-id elapsed-ms)))))

(define (get-pass-timings)
  (car *pass-timings*))

(define (print-pass-timing-report)
  (display "\n======================================================================\n")
  (display "Pass Execution Profiling Report (--time-passes)\n")
  (display "======================================================================\n")
  (let* ((timings (car *pass-timings*))
         (total (let loop ((ts timings) (acc 0))
                  (if (null? ts)
                      acc
                      (loop (cdr ts) (+ acc (cdar ts)))))))
    (let loop ((ts timings))
      (if (pair? ts)
          (let* ((entry (car ts))
                 (pid (car entry))
                 (ms (cdr entry))
                 (pct (if (> total 0) (quotient (* ms 100) total) 0)))
            (display "  ")
            (display pid)
            (display " : ")
            (display ms)
            (display " ticks (")
            (display pct)
            (display "%)\n")
            (loop (cdr ts)))))
    (display "----------------------------------------------------------------------\n")
    (display "  Total passes time : ")
    (display total)
    (display " ticks\n")
    (display "======================================================================\n\n")))

;;; -----------------------------------------------------------------------
;;; 6. IR Dump & Observability
;;; -----------------------------------------------------------------------

(define (dump-pass-ir pass-id stage ast)
  (display "\n----------------------------------------------------------------------\n")
  (display "[PASS MANAGER IR DUMP] ")
  (display pass-id)
  (display " (")
  (display stage)
  (display ")\n")
  (display "----------------------------------------------------------------------\n")
  (write (truncate-expr-for-diagnostics ast))
  (newline)
  (display "======================================================================\n\n"))

;;; -----------------------------------------------------------------------
;;; 7. Pipeline Execution Engine
;;; -----------------------------------------------------------------------

(define (run-single-pass pass-desc input-ast verify-mode trace-mode)
  (let* ((id (pass-id pass-desc))
         (fn (pass-fn pass-desc))
         (vphase (pass-verifier-phase pass-desc)))
    (set-current-pass! id)
    (with-call-frame id input-ast
      (lambda ()
        (let* ((t0 (current-time-monotonic-ms))
               (output-ast (fn input-ast))
               (t1 (current-time-monotonic-ms))
               (d (- t1 t0))
               (elapsed (if (< d 0) 0 d)))
          (if (pipeline-time-passes?)
              (record-pass-timing! id elapsed))
          (if trace-mode
              (nanopass-display-ast-diff id input-ast output-ast))
          (if (or (pipeline-print-after-all?)
                  (eq? (pipeline-dump-ir) id)
                  (eq? (pipeline-dump-ir) 'all))
              (dump-pass-ir id 'output output-ast))
          (if (and verify-mode vphase)
              (verify-pass-output vphase output-ast))
          output-ast)))))

(define (run-pass-pipeline forms verify-mode trace-mode)
  (if (null? (car *pass-registry*))
      (init-default-pass-registry!))
  (if verify-mode
      (begin
        (enable-verifier!)
        (if (eq? verify-mode 'strict)
            (set-verifier-strict! #t))))
  (if trace-mode
      (enable-nanopass-trace!))
  (let* ((opt-level (pipeline-opt-level))
         (disabled (pipeline-disabled-passes))
         (pipeline (build-pipeline opt-level disabled)))
    (validate-pipeline-prerequisites pipeline)
    (reset-pass-timings!)
    (let loop ((ps pipeline) (current-ast forms))
      (if (null? ps)
          (begin
            (if (pipeline-time-passes?)
                (print-pass-timing-report))
            (if verify-mode
                (verify-pass-output 'lir current-ast))
            current-ast)
          (let ((next-ast (run-single-pass (car ps) current-ast verify-mode trace-mode)))
            (loop (cdr ps) next-ast))))))

;;; -----------------------------------------------------------------------
;;; 8. Default Pass Registry Initialization
;;; -----------------------------------------------------------------------

(define (init-default-pass-registry!)
  (reset-pass-registry!)
  ;; Frontend Passes (Opt 0 = Mandatory, Opt 1/2 = Optimization)
  (register-pass!
    (make-pass-descriptor 'pass-010-library "Desugar Libraries and Imports" 'frontend 0
      (lambda (forms) (desugar-libraries-and-imports forms)) #f 'L_src 'L_src '() #t))
  (register-pass!
    (make-pass-descriptor 'pass-015-dsl-expander "DSL Expander" 'frontend 0
      (lambda (forms) (expand-dsl-forms forms)) #f 'L_src 'L_src '(pass-010-library) #t))
  (register-pass!
    (make-pass-descriptor 'pass-020-macro-expander "Hygienic Macro Expander" 'frontend 0
      (lambda (forms) (expand-macros-in-forms forms)) #f 'L_src 'L_src '(pass-015-dsl-expander) #t))
  (register-pass!
    (make-pass-descriptor 'pass-025-top-level "Rewrite Top-Level" 'frontend 0
      (lambda (forms) (rewrite-top-level forms)) #f 'L_src 'L_src '(pass-020-macro-expander) #t))
  (register-pass!
    (make-pass-descriptor 'pass-030-desugar "Core Desugar All" 'frontend 0
      (lambda (forms) (desugar-all forms)) 'desugar 'L_src 'L_core '(pass-025-top-level) #t))
  (register-pass!
    (make-pass-descriptor 'pass-035-scope-resolve "Lexical Scope Resolution and Alpha-Conversion" 'frontend 0
      (lambda (forms) (scope-resolve-all forms)) #f 'L_core 'L_core '(pass-030-desugar) #t))
  (register-pass!
    (make-pass-descriptor 'pass-050-cp0 "CP0 Source Optimization" 'frontend 1
      (lambda (forms) (cp0-optimize forms)) #f 'L_core 'L_core '(pass-030-desugar) #f))
  (register-pass!
    (make-pass-descriptor 'pass-060-lvn "Local Value Numbering" 'frontend 2
      (lambda (forms) (lvn-all forms)) #f 'L_core 'L_core '(pass-030-desugar) #f))
  (register-pass!
    (make-pass-descriptor 'pass-070-anf "A-Normal Form Conversion" 'frontend 0
      (lambda (forms) (anf-all forms)) 'anf 'L_core 'L_anf '(pass-030-desugar) #t))
  (register-pass!
    (make-pass-descriptor 'pass-080-annotator "Abstract Interpretation Annotator" 'frontend 2
      (lambda (forms) (annotate-all forms)) #f 'L_anf 'L_anf '(pass-070-anf) #f))
  (register-pass!
    (make-pass-descriptor 'pass-090-rtyper "Representation Typer & Unboxing" 'frontend 2
      (lambda (forms) (rtyper-all forms)) #f 'L_anf 'L_anf '(pass-070-anf) #f))
  (register-pass!
    (make-pass-descriptor 'pass-100-contify "Contification" 'frontend 2
      (lambda (forms) (contify-all forms)) #f 'L_anf 'L_anf '(pass-070-anf) #f))
  (register-pass!
    (make-pass-descriptor 'pass-110-closure-convert "Closure Conversion" 'frontend 0
      (lambda (forms) (closure-convert forms)) 'closure 'L_anf 'L_lifted '(pass-070-anf) #t))
  (register-pass!
    (make-pass-descriptor 'pass-120-alias-escape "TBAA and Escape Analysis" 'frontend 2
      (lambda (forms) (alias-escape-all forms)) #f 'L_lifted 'L_lifted '(pass-110-closure-convert) #f))
  ;; Middle-End / LIR Passes
  (register-pass!
    (make-pass-descriptor 'pass-130-lir "LIR Lowering and Generation" 'middle 0
      (lambda (forms) (generate-lir forms)) #f 'L_lifted 'L_lir_raw '(pass-110-closure-convert) #t))
  (register-pass!
    (make-pass-descriptor 'pass-128-lir-branch-fusion "LIR Branch Fusion" 'middle 2
      (lambda (lir) (lir-fuse-branches lir)) #f 'L_lir_raw 'L_lir_raw '(pass-130-lir) #f))
  (register-pass!
    (make-pass-descriptor 'pass-133-lir-peephole "LIR Peephole Optimization" 'middle 1
      (lambda (lir) (lir-peephole-optimize lir)) 'lir 'L_lir_raw 'L_lir_canonical '(pass-130-lir) #f))
  #t)
