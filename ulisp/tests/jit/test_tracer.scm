;;; =======================================================================
;;; MLisp Test Suite: Endogenous Meta-Tracer (test_tracer.scm)
;;; Conforms to DSN-34 Architecture Specification & Issue #507
;;;
;;; Verifies pure Scheme endogenous meta-tracing JIT functionality:
;;; - Hot loop detection & threshold triggering
;;; - Trace recording & speculative guard recording
;;; - Full loop cycle detection and S-expression trace finalization
;;; - Integration with an actual interpreter loop
;;; =======================================================================

(define *tracer-tests-passed* 0)
(define *tracer-tests-failed* 0)

(define (assert-equal test-name expected actual)
  (if (equal? expected actual)
      (begin
        (set! *tracer-tests-passed* (+ *tracer-tests-passed* 1))
        (display "  [PASS] ")
        (display test-name)
        (newline))
      (begin
        (set! *tracer-tests-failed* (+ *tracer-tests-failed* 1))
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
(display " Starting MLisp Endogenous Meta-Tracer Test Suite")
(newline)
(display "=======================================================")
(newline)

;;; Initialize tracer
(tracer-reset!)
(set-hot-threshold! 3)

;;; Test 1: Loop count increment before threshold
(display "--- Test 1: Iteration Counter Tracking ---")
(newline)
(assert-equal "initial count is 0" 0 (get-loop-count 'loop-pc-1))
(assert-equal "count 1 returns false" #f (jit-merge-point 'loop-pc-1 '()))
(assert-equal "count updated to 1" 1 (get-loop-count 'loop-pc-1))
(assert-equal "count 2 returns false" #f (jit-merge-point 'loop-pc-1 '()))
(assert-equal "count updated to 2" 2 (get-loop-count 'loop-pc-1))

;;; Test 2: Triggering hot loop threshold transitions to RECORDING
(display "--- Test 2: Hot Loop Trigger ---")
(newline)
(assert-equal "iteration 3 triggers recording"
              'started-recording
              (jit-merge-point 'loop-pc-1 '()))
(assert-equal "tracer state is RECORDING"
              'RECORDING
              *tracer-state*)

;;; Test 3: Emitting trace instructions during recording
(display "--- Test 3: Trace Instruction Recording ---")
(newline)
(trace-guard! 'type-fixnum 'reg-i 'fixnum 'bailout-target-1)
(trace-record! '%add 'reg-sum 'reg-sum 'reg-i)
(trace-record! '%add 'reg-i 'reg-i 1)
(trace-guard! 'cmp-lt 'reg-i 100 'bailout-target-2)

(assert-equal "accumulated 5 instructions (1 entry + 4 recorded)"
              5
              (length *current-trace-buffer*))

;;; Test 4: Reaching same PC finishes trace
(display "--- Test 4: Trace Completion on Loop Cycle ---")
(newline)
(let ((completed (jit-merge-point 'loop-pc-1 '())))
  (assert-true "trace object returned" (pair? completed))
  (assert-equal "root tag is %trace-loop" '%trace-loop (car completed))
  (assert-equal "tracer state transitioned to COMPILED" 'COMPILED *tracer-state*)

  ;; Verify trace body structure
  (let* ((body-entry (assq '%body (cdr completed)))
         (body (cadr body-entry)))
    (assert-equal "first instruction is loop entry"
                  '(%trace-loop-entry loop-pc-1)
                  (car body))
    (assert-equal "last instruction is loop jump"
                  '(%trace-loop-jump loop-pc-1)
                  (car (reverse body)))
    (assert-true "contains %guard instruction"
                 (pair? (assoc '%guard body)))
    (assert-true "contains %add instruction"
                 (pair? (assoc '%add body)))))

;;; Test 5: Lookup cached compiled trace
(display "--- Test 5: Compiled Trace Cache Lookup ---")
(newline)
(let ((cached (lookup-compiled-trace 'loop-pc-1)))
  (assert-true "cached trace found" (pair? cached))
  (assert-equal "cached trace tag" '%trace-loop (car cached)))

;;; Test 6: End-to-end integration with a simulated interpreter loop
(display "--- Test 6: End-to-end Interpreter Loop Tracing ---")
(newline)
(tracer-reset!)
(set-hot-threshold! 4)

;; A minimal interpreter simulation for: sum = 0; i = 0; while (i < 10) { sum += i; i++; }
(define (run-simulated-loop)
  (let loop ((i 0)
             (sum 0))
    ;; JIT merge point placed at loop header
    (let ((jit-status (jit-merge-point 'sim-loop-pc (list i sum))))
      (cond
        ((eq? jit-status 'started-recording)
         ;; While recording, interpreter steps emit trace ops
         (trace-guard! 'fixnum-check i 'fixnum 'exit-guard)
         (trace-record! '%add 'sum 'sum i)
         (trace-record! '%add 'i 'i 1)
         (if (< (+ i 1) 10)
             (loop (+ i 1) (+ sum i))
             sum))
        (else
         (if (< i 10)
             (loop (+ i 1) (+ sum i))
             sum))))))

(let ((result (run-simulated-loop)))
  (assert-equal "interpreter correctly computed sum 0..9" 45 result)
  (let ((trace (lookup-compiled-trace 'sim-loop-pc)))
    (assert-true "trace was automatically synthesized" (pair? trace))
    (assert-equal "trace PC is sim-loop-pc" 'sim-loop-pc (cadr (assq '%pc (cdr trace))))))

(display "=======================================================")
(newline)
(display " All ")
(display *tracer-tests-passed*)
(display " MLisp Endogenous Meta-Tracer tests PASSED successfully! (0 failures)")
(newline)
(display "=======================================================")
(newline)
