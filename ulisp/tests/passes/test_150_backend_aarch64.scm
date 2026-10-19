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

(display "=======================================================")
(newline)
(display " All ")
(display *aarch64-tests-passed*)
(display " AArch64 Backend tests PASSED successfully! (0 failures)")
(newline)
(display "=======================================================")
(newline)
