;;; =======================================================================
;;; MLisp Test Suite: LIR Bridge & JIT Buffer Runtime (test_bridge.scm)
;;; Conforms to DSN-34 Architecture Specification & Issue #507
;;;
;;; Verifies pure Scheme bridge and runtime execution:
;;; - Conversion from MLisp traces to canonical ULisp %lir-program
;;; - Correct register allocation and instruction mapping
;;; - JIT code buffer installation and W^X status transition
;;; - Guard bailout / deoptimization handler execution
;;; - End-to-end JIT pipeline (Trace -> Opt -> LIR -> Install -> Dispatch)
;;; =======================================================================

(define *bridge-tests-passed* 0)
(define *bridge-tests-failed* 0)

(define (assert-equal test-name expected actual)
  (if (equal? expected actual)
      (begin
        (set! *bridge-tests-passed* (+ *bridge-tests-passed* 1))
        (display "  [PASS] ")
        (display test-name)
        (newline))
      (begin
        (set! *bridge-tests-failed* (+ *bridge-tests-failed* 1))
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
(display " Starting MLisp LIR Bridge & JIT Runtime Test Suite")
(newline)
(display "=======================================================")
(newline)

;;; Reset JIT runtime
(jit-runtime-reset!)

;;; Test 1: Trace to LIR Program Conversion
(display "--- Test 1: Trace to LIR Translation ---")
(newline)
(let* ((sample-trace
        '(%trace-loop
           (%pc loop-42)
           (%body
             ((%trace-loop-entry loop-42)
              (%mov reg-i 0)
              (%mov reg-sum 0)
              (%add reg-sum reg-sum reg-i)
              (%add reg-i reg-i 1)
              (%guard cmp-lt reg-i 100 bailout-target)
              (%trace-loop-jump loop-42)))))
       (lir-prog (trace->lir-program sample-trace)))
  (assert-true "result is pair" (pair? lir-prog))
  (assert-equal "root tag is %lir-program" '%lir-program (car lir-prog))

  ;; Check structure according to Pass 6 specification
  (let* ((fields (cdr lir-prog))
         (strings-entry (assq 'strings fields))
         (funcs-entry (assq '%lir-functions fields))
         (main-entry (assq '%lir-main fields)))
    (assert-true "contains strings" (pair? strings-entry))
    (assert-true "contains %lir-functions" (pair? funcs-entry))
    (assert-true "contains %lir-main" (pair? main-entry))

    ;; Verify body instructions
    (let ((body (cadr (assq 'body (cdr main-entry)))))
      (assert-true "contains %label" (pair? (assoc '%label body)))
      (assert-true "contains %mov" (pair? (assoc '%mov body)))
      (assert-true "contains %add" (pair? (assoc '%add body)))
      (assert-true "contains %cmp (guard)" (pair? (assoc '%cmp body)))
      (assert-true "contains %jump" (pair? (assoc '%jump body)))
      (assert-true "ends with %return" (pair? (member '(%return) body))))))

;;; Test 2: JIT Buffer Installation and W^X Permission Transition
(display "--- Test 2: JIT Buffer & W^X Lifecycle ---")
(newline)
(let* ((mock-lir '(%lir-program (strings ()) (%lir-functions ()) (%lir-main (frame-size 16) (body ((%return))))))
       (buf (install-jit-code! 'test-pc-w-x mock-lir)))
  (assert-true "buffer is installed" (pair? buf))
  (assert-equal "buffer status transitioned to EXECUTABLE"
                'EXECUTABLE
                (cdr (assq 'status (cdr buf))))
  (assert-true "buffer can be looked up"
               (pair? (lookup-jit-buffer 'test-pc-w-x))))

;;; Test 3: Guard Bailout / Deoptimization Handling
(display "--- Test 3: Speculative Guard Bailout (Deopt) ---")
(newline)
(let ((bailout-called #f)
      (received-state #f))
  (register-bailout-handler! 'bailout-target-1
    (lambda (st)
      (set! bailout-called #t)
      (set! received-state st)))
  ;; Trigger simulated bailout from JIT
  (trigger-bailout! 'bailout-target-1 '(reg-i 101 reg-sum 450))
  (assert-true "bailout handler was executed" bailout-called)
  (assert-equal "bailout received interpreter state correctly"
                '(reg-i 101 reg-sum 450)
                received-state)
  (assert-equal "bailout stats recorded" 1 *jit-stats-bailouts*))

;;; Test 4: End-to-end Pipeline (Trace -> Opt -> LIR Bridge -> JIT Buffer -> Dispatch)
(display "--- Test 4: End-to-end Pure Scheme JIT Pipeline ---")
(newline)
(let* ((raw-trace
        '(%trace-loop
           (%pc full-pipeline-loop)
           (%body
             ((%trace-loop-entry full-pipeline-loop)
              (%mov c1 10)
              (%mov c2 20)
              (%add c3 c1 c2)                    ; Will be constant-folded to 30!
              (%cons p c1 c3)                    ; Virtual pair -> will be eliminated!
              (%car val p)                       ; Reads c1 -> will be 10!
              (%add total val 5)                 ; 10 + 5 = 15!
              (%trace-loop-jump full-pipeline-loop)))))
       ;; 1. Optimize
       (opt-trace (optimize-trace-full raw-trace))
       ;; 2. Bridge to ULisp LIR
       (lir-prog (trace->lir-program opt-trace))
       ;; 3. Install in Pure Scheme JIT Buffer
       (buf (install-jit-code! 'full-pipeline-loop lir-prog))
       ;; 4. Dispatch
       (exec-res (dispatch-jit-loop 'full-pipeline-loop '(init-state))))
  (assert-true "buffer installed successfully" (pair? buf))
  (assert-equal "dispatch executed successfully"
                '(jit-executed full-pipeline-loop (init-state))
                exec-res)
  (assert-equal "execution count incremented" 1 *jit-stats-executed*))

(display "=======================================================")
(newline)
(display " All ")
(display *bridge-tests-passed*)
(display " MLisp LIR Bridge & JIT Runtime tests PASSED successfully! (0 failures)")
(newline)
(display "=======================================================")
(newline)
