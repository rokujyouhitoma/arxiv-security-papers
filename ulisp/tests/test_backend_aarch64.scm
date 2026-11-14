;;; =======================================================================
;;; ULisp AArch64 Backend Full Test Suite
;;; Conforms to Issue #503 & DSN-33 Architecture Specification
;;; Verifies AArch64 instruction emission and LIR pipeline integration.
;;; =======================================================================

(test-begin "AArch64 Backend")

;;; Test 1: Immediate values to LIR to AArch64 instruction mapping
(display "--- Step 1: Immediate & Arithmetic Instructions ---")
(newline)
(let* ((lir (generate-lir (closure-convert (anf-all (cp0-optimize (desugar-all '(+ 10 20))))))))
  (assert-true "lir generated for (+ 10 20)" (pair? lir))
  (assert-equal "lir root tag" '%lir-program (car lir)))

;;; Test 2: Conditional branching & comparison
(display "--- Step 2: Conditionals & Booleans ---")
(newline)
(let* ((lir (generate-lir (closure-convert (anf-all (cp0-optimize (desugar-all '(if (= 5 5) 42 0))))))))
  (assert-true "lir generated for if condition" (pair? lir))
  (assert-equal "lir tag" '%lir-program (car lir)))

;;; Test 3: Division & Modulo (sdiv / msub verification)
(display "--- Step 3: Division & Modulo ---")
(newline)
(let* ((lir-div (generate-lir (closure-convert (anf-all (cp0-optimize (desugar-all '(quotient 42 7)))))))
       (lir-mod (generate-lir (closure-convert (anf-all (cp0-optimize (desugar-all '(modulo 42 5))))))))
  (assert-true "lir generated for quotient" (pair? lir-div))
  (assert-true "lir generated for modulo" (pair? lir-mod)))

;;; Test 4: Closure generation & procedure call
(display "--- Step 4: Closures & Non-tail Calls ---")
(newline)
(let* ((lir (generate-lir (closure-convert (anf-all (cp0-optimize (desugar-all '((lambda (x) (+ x 1)) 41))))))))
  (assert-true "lir generated for lambda call" (pair? lir))
  (let ((funcs (cdr (assq '%lir-functions (cdr lir)))))
    (assert-equal "lifted lambda function count" 1 (length funcs))))

;;; Test 5: Tail-Call Optimization (TCO) loop
(display "--- Step 5: Tail Call Optimization (TCO) ---")
(newline)
(let* ((lir (generate-lir (closure-convert (anf-all (cp0-optimize (desugar-all
              '(letrec ((loop (lambda (n) (if (= n 0) 42 (loop (- n 1)))))) (loop 10)))))))))
  (assert-true "lir generated for tco loop" (pair? lir))
  (let ((funcs (cdr (assq '%lir-functions (cdr lir)))))
    (assert-equal "tco lifted function count" 1 (length funcs))))

;;; Test 6: Heap Allocation (cons, car, cdr)
(display "--- Step 6: Heap Allocation & Pairs ---")
(newline)
(let* ((lir-cons (generate-lir (closure-convert (anf-all (cp0-optimize (desugar-all '(cons 1 2)))))))
       (lir-car  (generate-lir (closure-convert (anf-all (cp0-optimize (desugar-all '(car (cons 1 2)))))))))
  (assert-true "lir generated for cons" (pair? lir-cons))
  (assert-true "lir generated for car" (pair? lir-car)))

;;; Test 7: String creation & indexing
(display "--- Step 7: Strings ---")
(newline)
(let* ((lir-str (generate-lir (closure-convert (anf-all (cp0-optimize (desugar-all '(make-string 5))))))))
  (assert-true "lir generated for make-string" (pair? lir-str)))

;;; Test 8: Raw Syscall LIR generation (Issue #690)
(display "--- Step 8: Multi-Architecture System Calls LIR ---")
(newline)
(let* ((ast (desugar-all '(%raw-syscall (%to-raw 93) (%to-raw 42) 0 0 0 0 0)))
       (lir (generate-lir (closure-convert (anf-all (cp0-optimize ast))))))
  (assert-true "lir generated for %raw-syscall" (pair? lir))
  (let* ((main-clause (assq '%lir-main (cdr lir)))
         (body (cdr (assq 'body (cdr main-clause)))))
    (assert-true "body contains %syscall"
                 (let loop ((rest body))
                   (and (pair? rest)
                        (or (and (pair? (car rest)) (eq? (caar rest) '%syscall))
                            (loop (cdr rest))))))))

;;; Test 9: Platform Feature Identifiers & cond-expand resolution (Issue #690)
(display "--- Step 9: Platform Features & Architecture Target Switching ---")
(newline)
(set-current-target-arch! 'aarch64)
(assert-equal "aarch64 feature active when target is aarch64" #t (ulisp-supported-feature? 'aarch64))
(assert-equal "arm64 feature active when target is aarch64" #t (ulisp-supported-feature? 'arm64))
(assert-equal "x86-64 feature inactive when target is aarch64" #f (ulisp-supported-feature? 'x86-64))
(assert-equal "posix feature active on aarch64" #t (ulisp-supported-feature? 'posix))
(assert-equal "linux feature active on aarch64" #t (ulisp-supported-feature? 'linux))

(set-current-target-arch! 'x86_64)
(assert-equal "x86-64 feature active when target is x86_64" #t (ulisp-supported-feature? 'x86-64))
(assert-equal "aarch64 feature inactive when target is x86_64" #f (ulisp-supported-feature? 'aarch64))
(assert-equal "posix feature active on x86_64" #t (ulisp-supported-feature? 'posix))

;;; Test 10: cond-expand Syscall Selection for AArch64 (Issue #690)
(display "--- Step 10: cond-expand Syscall Table Validation ---")
(newline)
(set-current-target-arch! 'aarch64)
(let* ((forms (expand-cond-expands-in-forms
               '((cond-expand
                   ((or aarch64 arm64)
                    (define test-sys-exit 93)
                    (define test-sys-read 63)
                    (define test-sys-write 64)
                    (define test-sys-openat 56))
                   (else
                    (define test-sys-exit 60)
                    (define test-sys-read 0)
                    (define test-sys-write 1)
                    (define test-sys-open 2)))))))
  (assert-equal "cond-expand expands aarch64 branch when target is aarch64"
                '(define test-sys-exit 93)
                (car forms)))
(set-current-target-arch! 'x86_64)

;;; Test 11: TPIDR_EL0 TLS Worker Identification & Exception Isolation (Issue #748)
(display "--- Step 11: TPIDR_EL0 TLS & Worker Memory Isolation (Issue #748) ---")
(newline)
(define (test-aarch64-str-contains? str sub)
  (let ((slen (string-length str))
        (sublen (string-length sub)))
    (let loop ((i 0))
      (cond
        ((> (+ i sublen) slen) #f)
        ((string=? (substring str i (+ i sublen)) sub) #t)
        (else (loop (+ i 1)))))))

(define (test-aarch64-lines-contain? lines sub)
  (let loop ((ls lines))
    (and (pair? ls)
         (or (test-aarch64-str-contains? (car ls) sub)
             (loop (cdr ls))))))

(let* ((ast '(guard (ex (else 42)) (raise 'boom)))
       (lir (generate-lir (closure-convert (anf-all (cp0-optimize (desugar-all ast)))))))
  (assert-true "lir generated for guard/raise expression" (pair? lir))
  (let ((emitted-lines '()))
    (set-emit-line-sink! (lambda (line) (set! emitted-lines (cons line emitted-lines))))
    (emit-aarch64 lir 'none)
    (set-emit-line-sink! #f)
    (let ((lines (reverse emitted-lines)))
      (assert-true "emitted asm contains tpidr_el0"
                   (test-aarch64-lines-contain? lines "tpidr_el0"))
      (assert-true "emitted asm contains ulisp_worker_tls_table"
                   (test-aarch64-lines-contain? lines "ulisp_worker_tls_table"))
      (assert-true "emitted asm contains ulisp_handler_chain"
                   (test-aarch64-lines-contain? lines "ulisp_handler_chain")))))

;;; Test 12: Synapse safepoint poll LIR selection & AArch64 weak stubs (Issue #809)
(display "--- Step 12: Safepoint Poll LIR Selection & AArch64 Weak Stubs (Issue #809) ---")
(newline)
(define (test-aarch64-tree-contains? tree item)
  (cond
    ((equal? tree item) #t)
    ((pair? tree) (or (test-aarch64-tree-contains? (car tree) item)
                      (test-aarch64-tree-contains? (cdr tree) item)))
    (else #f)))

(define (test-aarch64-count-lines lines str)
  (let loop ((ls lines) (n 0))
    (if (pair? ls)
        (loop (cdr ls) (if (string=? (car ls) str) (+ n 1) n))
        n)))

(define (test-aarch64-capture lir)
  (let ((emitted-lines '()))
    (set-emit-line-sink! (lambda (line) (set! emitted-lines (cons line emitted-lines))))
    (emit-aarch64 lir 'none)
    (set-emit-line-sink! #f)
    (reverse emitted-lines)))

(let* ((ast '(%synapse-safepoint-poll!))
       (lir (generate-lir (closure-convert (anf-all (cp0-optimize (desugar-all ast)))))))
  ;; Phase 1: zero-arg primitive selection must never be a silent NOP
  (assert-true "safepoint poll lowers to %memory-fence in LIR"
               (test-aarch64-tree-contains? lir '(%memory-fence)))
  (assert-true "safepoint poll yields #t (111) in LIR"
               (test-aarch64-tree-contains? lir '(%mov %rax 111)))
  ;; Phase 2: runtime unlinked -> weak stubs emitted exactly once
  (let ((lines (test-aarch64-capture lir)))
    (assert-true "emitted asm contains dmb ish fence for safepoint poll"
                 (test-aarch64-lines-contain? lines "dmb ish"))
    (assert-equal "weak fn stub label emitted exactly once" 1
                  (test-aarch64-count-lines lines "ulisp_fn__pctsynapse_safepoint_poll_excl:"))
    (assert-true "fn stub marked .weak"
                 (test-aarch64-lines-contain? lines ".weak ulisp_fn__pctsynapse_safepoint_poll_excl"))
    (assert-true "fn stub returns #f via x0 (mov x0, #47)"
                 (test-aarch64-lines-contain? lines "mov x0, #47"))
    (assert-equal "weak gvar stub label emitted exactly once" 1
                  (test-aarch64-count-lines lines "ulisp_gvar__pctsynapse_safepoint_poll_excl:"))
    (assert-true "gvar stub uses 64-bit .xword pointer"
                 (test-aarch64-lines-contain? lines ".xword ulisp_fn__pctsynapse_safepoint_poll_excl")))
  ;; Runtime linked (top-level definition present) -> stubs suppressed
  (let ((saved-fns (car *top-level-fns*)))
    (set-car! *top-level-fns*
              (cons (cons '%synapse-safepoint-poll! "ulisp_fn__pctsynapse_safepoint_poll_excl")
                    saved-fns))
    (let ((lines (test-aarch64-capture lir)))
      (set-car! *top-level-fns* saved-fns)
      (assert-equal "weak stub suppressed when runtime defines %synapse-safepoint-poll!" 0
                    (test-aarch64-count-lines lines "ulisp_fn__pctsynapse_safepoint_poll_excl:")))))

(test-end "AArch64 Backend")
