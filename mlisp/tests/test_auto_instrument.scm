;;; =======================================================================
;;; MLisp Test Suite: Auto-Instrumentation Pass (test_auto_instrument.scm)
;;; Conforms to DSN-34 Architecture Specification & Issue #510
;;;
;;; Verifies pure Scheme loop detection & transparent JIT instrumentation:
;;; - Named let automatic instrumentation
;;; - Tail-recursive define automatic instrumentation
;;; - Rejection of non-loops (zero false positives)
;;; - Nested loop distinct tagging
;;; - Idempotency (avoid double instrumentation)
;;; - End-to-end execution of unannotated Scheme loop with JIT tracer
;;; =======================================================================

(define *auto-inst-passed* 0)
(define *auto-inst-failed* 0)

(define (assert-equal test-name expected actual)
  (if (equal? expected actual)
      (begin
        (set! *auto-inst-passed* (+ *auto-inst-passed* 1))
        (display "  [PASS] ")
        (display test-name)
        (newline))
      (begin
        (set! *auto-inst-failed* (+ *auto-inst-failed* 1))
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
(display " Starting MLisp Auto-Instrumentation Test Suite")
(newline)
(display "=======================================================")
(newline)

(reset-auto-loop-counter!)

;;; --- Test 1: Named let Detection and Instrumentation ---
(display "--- Test 1: Named let Instrumentation ---")
(newline)

(let* ((orig '(let loop ((i 0) (sum 0))
                (if (>= i 10)
                    sum
                    (loop (+ i 1) (+ sum i)))))
       (res (auto-instrument-form orig)))
  (assert-true "result is pair" (pair? res))
  (assert-equal "operator is let" 'let (car res))
  (assert-equal "loop name is loop" 'loop (cadr res))
  (assert-equal "bindings preserved" '((i 0) (sum 0)) (caddr res))
  ;; Check that first expression in body is (jit-merge-point 'loop_0 (list i sum))
  (let ((body (cdddr res)))
    (assert-true "body has at least 2 expressions" (>= (length body) 2))
    (let ((injected (car body)))
      (assert-equal "injected call is jit-merge-point" 'jit-merge-point (car injected))
      (assert-equal "loop tag is quoted loop_0" ''loop_0 (cadr injected))
      (assert-equal "state env is (list i sum)" '(list i sum) (caddr injected)))))

;;; --- Test 2: Tail-Recursive define Instrumentation ---
(display "--- Test 2: Tail-Recursive define Instrumentation ---")
(newline)

(let* ((orig '(define (countdown n acc)
                (if (<= n 0)
                    acc
                    (countdown (- n 1) (+ acc n)))))
       (res (auto-instrument-form orig)))
  (assert-equal "define operator preserved" 'define (car res))
  (assert-equal "function signature preserved" '(countdown n acc) (cadr res))
  (let ((body (cddr res)))
    (assert-true "body has injected call" (pair? body))
    (let ((injected (car body)))
      (assert-equal "injected is jit-merge-point" 'jit-merge-point (car injected))
      (assert-equal "function tag is quoted countdown" ''countdown (cadr injected))
      (assert-equal "state env is (list n acc)" '(list n acc) (caddr injected)))))

;;; --- Test 3: Non-Recursive Functions Unchanged (No False Positives) ---
(display "--- Test 3: Non-Recursive Function Preserved ---")
(newline)

(let* ((orig '(define (add a b)
                (+ a b)))
       (res (auto-instrument-form orig)))
  (assert-equal "non-recursive define is completely untouched" orig res))

;;; --- Test 4: Standard let Unchanged (No False Positives) ---
(display "--- Test 4: Standard let Preserved ---")
(newline)

(let* ((orig '(let ((x 10) (y 20))
                (+ x y)))
       (res (auto-instrument-form orig)))
  (assert-equal "standard let is completely untouched" orig res))

;;; --- Test 5: Idempotency (Pre-existing jit-merge-point not duplicated) ---
(display "--- Test 5: Idempotency ---")
(newline)

(let* ((orig '(let loop ((i 0))
                (jit-merge-point 'manual-pc (list i))
                (if (< i 5) (loop (+ i 1)) i)))
       (res (auto-instrument-form orig)))
  (let ((body (cdddr res)))
    (assert-equal "body has exactly 2 expressions (not duplicated)" 2 (length body))
    (assert-equal "first expr is the original manual jit-merge-point"
                  '(jit-merge-point 'manual-pc (list i))
                  (car body))))

;;; --- Test 6: Nested Loops Receive Unique Tags ---
(display "--- Test 6: Nested Loops Distinct Tagging ---")
(newline)

(let* ((orig '(let outer ((i 0))
                (let inner ((j 0))
                  (if (< j 5) (inner (+ j 1)) i))))
       (res (auto-instrument-form orig)))
  (let* ((outer-body (cdddr res))
         (outer-tag (cadr (car outer-body)))
         (inner-let (cadr outer-body))
         (inner-body (cdddr inner-let))
         (inner-tag (cadr (car inner-body))))
    (assert-true "outer tag is quoted symbol" (pair? outer-tag))
    (assert-true "inner tag is quoted symbol" (pair? inner-tag))
    (assert-true "outer and inner tags are distinct"
                 (not (equal? outer-tag inner-tag)))))

;;; --- Test 7: End-to-End Evaluation & JIT Trace Synthesizing ---
(display "--- Test 7: End-to-End Pure Scheme Loop with Tracer ---")
(newline)

(tracer-reset!)
(set-hot-threshold! 3)

;; User writes completely normal Scheme loop with zero JIT hints
(define unannotated-loop-code
  '(let sim-loop ((i 0) (acc 0))
     (if (< i 6)
         (sim-loop (+ i 1) (+ acc i))
         acc)))

;; MLisp automatically instruments it
(define instrumented-loop-code
  (auto-instrument-form unannotated-loop-code))

;; Verify that the instrumented code runs and computes correct result 0+1+2+3+4+5 = 15
(define exec-result (eval instrumented-loop-code (interaction-environment)))
(assert-equal "evaluated unannotated loop computes sum 15" 15 exec-result)

;; Verify that the MLisp tracer automatically tracked and hot-compiled the loop!
(assert-true "tracer reached COMPILED state automatically"
             (eq? *tracer-state* *TRACER-STATE-COMPILED*))
(assert-true "compiled trace exists for auto-instrumented loop tag"
             (pair? *compiled-traces*))

(display "=======================================================")
(newline)
(display " All ")
(display *auto-inst-passed*)
(display " MLisp Auto-Instrumentation tests PASSED successfully! (0 failures)")
(newline)
(display "=======================================================")
(newline)
