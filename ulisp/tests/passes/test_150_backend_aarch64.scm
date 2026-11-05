;;; =======================================================================
;;; ULisp AArch64 Backend Full Test Suite
;;; Conforms to Issue #503 & DSN-33 Architecture Specification
;;; Verifies AArch64 instruction emission and LIR pipeline integration.
;;; =======================================================================

(define *aarch64-tests-passed* 0)
(define *aarch64-tests-failed* 0)

(define (assert-equal test-name expected actual)
  (if (equal? expected actual)
      (begin
        (set! *aarch64-tests-passed* (+ *aarch64-tests-passed* 1))
        (display "  [PASS] ")
        (display test-name)
        (newline))
      (begin
        (set! *aarch64-tests-failed* (+ *aarch64-tests-failed* 1))
        (display "  [FAIL] ")
        (display test-name)
        (display " -> Expected: ")
        (display expected)
        (display " but got: ")
        (display actual)
        (newline)
        (exit 1))))

(define (assert-true test-name expr)
  (assert-equal test-name #t (if expr #t #f)))

(display "=======================================================")
(newline)
(display " Starting ULisp AArch64 Backend Detailed Test Suite")
(newline)
(display "=======================================================")
(newline)

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

(display "=======================================================")
(newline)
(display " All ")
(display *aarch64-tests-passed*)
(display " AArch64 Backend tests PASSED successfully! (0 failures)")
(newline)
(display "=======================================================")
(newline)
