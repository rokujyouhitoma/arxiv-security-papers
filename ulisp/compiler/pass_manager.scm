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

(define *pass-manager-timer-ticks* (cons 0 '()))

(define (current-time-monotonic-us)
  (let ((p (sys-clock-gettime-monotonic)))
    (if (and (pair? p) (or (> (car p) 0) (> (cdr p) 0)))
        (+ (* (car p) 1000000) (quotient (cdr p) 1000))
        (begin
          (set-car! *pass-manager-timer-ticks* (+ (car *pass-manager-timer-ticks*) 1000))
          (car *pass-manager-timer-ticks*)))))

(define (current-time-monotonic-ms)
  (quotient (current-time-monotonic-us) 1000))

(define (current-heap-alloc-bytes)
  (gc-current-heap-bytes))

;; Formatters
(define (pad-right str width)
  (let ((len (string-length str)))
    (if (>= len width)
        str
        (let ((res (make-string width #\space)))
          (let loop ((i 0))
            (if (< i len)
                (begin
                  (string-set! res i (string-ref str i))
                  (loop (+ i 1)))
                res))))))

(define (pad-left str width)
  (let ((len (string-length str)))
    (if (>= len width)
        str
        (let* ((pad (- width len))
               (res (make-string width #\space)))
          (let loop ((i 0))
            (if (< i len)
                (begin
                  (string-set! res (+ pad i) (string-ref str i))
                  (loop (+ i 1)))
                res))))))

(define (format-fixed-2-ms us)
  (let* ((total-cs (quotient (+ us 5) 10))
         (whole (quotient total-cs 100))
         (frac (modulo total-cs 100))
         (whole-str (number->string whole))
         (frac-str (if (< frac 10)
                       (string-append "0" (number->string frac))
                       (number->string frac))))
    (string-append whole-str "." frac-str " ms")))

(define (format-fixed-1-pct part total)
  (if (<= total 0)
      " 0.0%"
      (let* ((scaled (quotient (* part 1000) total))
             (whole (quotient scaled 10))
             (frac (modulo scaled 10))
             (whole-str (number->string whole))
             (frac-str (number->string frac)))
        (string-append whole-str "." frac-str "%"))))

(define (format-alloc-kb bytes)
  (if (<= bytes 0)
      "0 KB"
      (let ((kb (quotient (+ bytes 1023) 1024)))
        (string-append (number->string kb) " KB"))))

;; Timing Record
(define (make-pass-timing-entry id name elapsed-us alloc-bytes)
  (list id name elapsed-us alloc-bytes))

(define (pass-timing-id e) (car e))
(define (pass-timing-name e) (cadr e))
(define (pass-timing-elapsed-us e) (caddr e))
(define (pass-timing-alloc-bytes e) (cadddr e))

(define *pass-timings* (cons '() '()))

(define (reset-pass-timings!)
  (set-car! *pass-timings* '()))

(define (record-pass-timing! pass-id pass-name elapsed-us alloc-bytes)
  (set-car! *pass-timings*
            (append (car *pass-timings*)
                    (list (make-pass-timing-entry pass-id pass-name elapsed-us alloc-bytes)))))

(define (get-pass-timings)
  (car *pass-timings*))

(define *pass-id-names*
  '((pass-010-library . "pass-010-library")
    (pass-015-dsl-expander . "pass-015-dsl-expander")
    (pass-020-macro-expander . "pass-020-macro-expander")
    (pass-025-top-level . "pass-025-top-level")
    (pass-030-desugar . "pass-030-desugar")
    (pass-035-scope-resolve . "pass-035-scope-resolve")
    (pass-050-cp0 . "pass-050-cp0")
    (pass-060-lvn . "pass-060-lvn")
    (pass-070-anf . "pass-070-anf")
    (pass-080-annotator . "pass-080-annotator")
    (pass-090-rtyper . "pass-090-rtyper")
    (pass-100-contify . "pass-100-contify")
    (pass-110-closure-convert . "pass-110-closure-convert")
    (pass-120-alias-escape . "pass-120-alias-escape")
    (pass-130-lir . "pass-130-lir")
    (pass-128-lir-branch-fusion . "pass-128-lir-branch-fusion")
    (pass-133-lir-peephole . "pass-133-lir-peephole")
    (pass-140-backend-x86-64 . "pass-140-backend-x86-64")
    (pass-150-backend-aarch64 . "pass-150-backend-aarch64")
    (pass-160-backend-c . "pass-160-backend-c")))

(define (pass-id->string pid)
  (if (string? pid)
      pid
      (let ((entry (assq pid *pass-id-names*)))
        (if entry
            (cdr entry)
            (if (symbol? pid)
                (let ((s (symbol->string pid)))
                  (if (string=? s "?")
                      "pass"
                      s))
                "pass")))))

;; Stderr print wrappers
(define (display-stderr msg)
  (display msg (get-compiler-error-port)))

(define (newline-stderr)
  (newline (get-compiler-error-port)))

(define (print-pass-timing-report)
  (let* ((timings (car *pass-timings*))
         (total-us (let loop ((ts timings) (acc 0))
                     (if (null? ts)
                         acc
                         (loop (cdr ts) (+ acc (pass-timing-elapsed-us (car ts)))))))
         (total-bytes (let loop ((ts timings) (acc 0))
                        (if (null? ts)
                            acc
                            (loop (cdr ts) (+ acc (pass-timing-alloc-bytes (car ts))))))))
    (display-stderr "\n========================================================================================\n")
    (display-stderr "ULisp Nanopass Execution Profile (--time-passes)\n")
    (display-stderr "========================================================================================\n")
    (display-stderr "Pass ID                  Pass Name                         Time (ms)  Share (%)   Heap (KB)\n")
    (display-stderr "----------------------------------------------------------------------------------------\n")
    (let loop ((ts timings))
      (if (pair? ts)
          (let* ((entry (car ts))
                 (pid (pass-timing-id entry))
                 (pname (pass-timing-name entry))
                 (us (pass-timing-elapsed-us entry))
                 (bytes (pass-timing-alloc-bytes entry))
                 (id-str (pass-id->string pid))
                 (name-str (if (string? pname) pname (if (symbol? pname) (symbol->string pname) id-str)))
                 (time-str (format-fixed-2-ms us))
                 (share-str (format-fixed-1-pct us total-us))
                 (heap-str (format-alloc-kb bytes)))
            (display-stderr (pad-right id-str 24))
            (display-stderr " ")
            (display-stderr (pad-right name-str 32))
            (display-stderr " ")
            (display-stderr (pad-left time-str 11))
            (display-stderr " ")
            (display-stderr (pad-left share-str 10))
            (display-stderr " ")
            (display-stderr (pad-left heap-str 10))
            (newline-stderr)
            (loop (cdr ts)))))
    (display-stderr "----------------------------------------------------------------------------------------\n")
    (display-stderr "Total Compilation Time : ")
    (display-stderr (format-fixed-2-ms total-us))
    (newline-stderr)
    (display-stderr "Total Heap Allocation  : ")
    (display-stderr (format-alloc-kb total-bytes))
    (newline-stderr)
    (display-stderr "========================================================================================\n\n")))


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
         (pname (pass-name pass-desc))
         (fn (pass-fn pass-desc))
         (vphase (pass-verifier-phase pass-desc)))
    (set-current-pass! id)
    (with-call-frame id input-ast
      (lambda ()
        (if (pipeline-time-passes?)
            (let* ((t0 (current-time-monotonic-us))
                   (m0 (current-heap-alloc-bytes))
                   (output-ast (fn input-ast))
                   (t1 (current-time-monotonic-us))
                   (m1 (current-heap-alloc-bytes))
                   (elapsed-us (let ((d (- t1 t0))) (if (< d 0) 0 d)))
                   (alloc-bytes (let ((d (- m1 m0))) (if (< d 0) 0 d))))
              (record-pass-timing! id pname elapsed-us alloc-bytes)
              (if trace-mode
                  (nanopass-display-ast-diff id input-ast output-ast))
              (if (or (pipeline-print-after-all?)
                      (eq? (pipeline-dump-ir) id)
                      (eq? (pipeline-dump-ir) 'all))
                  (dump-pass-ir id 'output output-ast))
              (if (and verify-mode vphase)
                  (if (not (verify-pass-output vphase output-ast))
                      (error "IR Verifier Invariant Violation in pass" id)))
              output-ast)
            (let ((output-ast (fn input-ast)))
              (if trace-mode
                  (nanopass-display-ast-diff id input-ast output-ast))
              (if (or (pipeline-print-after-all?)
                      (eq? (pipeline-dump-ir) id)
                      (eq? (pipeline-dump-ir) 'all))
                  (dump-pass-ir id 'output output-ast))
              (if (and verify-mode vphase)
                  (if (not (verify-pass-output vphase output-ast))
                      (error "IR Verifier Invariant Violation in pass" id)))
              output-ast))))))

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
            (if verify-mode
                (if (not (verify-pass-output 'lir current-ast))
                    (error "IR Verifier Invariant Violation in final LIR" current-ast)))
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
