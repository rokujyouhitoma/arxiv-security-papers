;;; =======================================================================
;;; Unit & Integration Test Suite: Hot-Loop Profiler & Linear Trace Recorder
;;; Conforms to DSN-33-05 §3 & §4, DSN-33-02 (Pass 6), and Issue #899
;;; Pure Scheme. Zero External Dependencies.
;;; =======================================================================

(test-begin "Hot-Loop Profiler & Linear Trace Recorder (Issue #899)")

;;; -----------------------------------------------------------------------
;;; Group 1: Hot-Loop Profiler & Counter Mechanics
;;; -----------------------------------------------------------------------
(print-group "--- Group 1: Hot-Loop Profiler & Counter Mechanics ---")

(tracer-reset!)
(set-hot-threshold! 5)

(assert-equal "1.1 Initial loop count is 0" 0 (get-loop-count 'loop-pc-alpha))
(assert-false "1.2 Not hot initially" (hot-loop? 'loop-pc-alpha))

;; Increment 4 times
(inc-loop-count! 'loop-pc-alpha)
(inc-loop-count! 'loop-pc-alpha)
(inc-loop-count! 'loop-pc-alpha)
(inc-loop-count! 'loop-pc-alpha)
(assert-equal "1.3 Count after 4 increments is 4" 4 (get-loop-count 'loop-pc-alpha))
(assert-false "1.4 Still not hot at 4 < 5" (hot-loop? 'loop-pc-alpha))

;; 5th increment reaches threshold
(inc-loop-count! 'loop-pc-alpha)
(assert-equal "1.5 Count after 5th increment is 5" 5 (get-loop-count 'loop-pc-alpha))
(assert-true "1.6 Becomes hot at threshold 5" (hot-loop? 'loop-pc-alpha))

;; Counter decay
(decay-loop-counters! 2)
(assert-equal "1.7 Count decayed by factor 2 is 2" 2 (get-loop-count 'loop-pc-alpha))
(assert-false "1.8 Not hot after decay" (hot-loop? 'loop-pc-alpha))

;; CWE-400: Capacity limit test (simulate max profiler entries)
(let ((saved-limit *jit-max-profiler-entries*))
  (set! *jit-max-profiler-entries* 5)
  (inc-loop-count! 'pc_1)
  (inc-loop-count! 'pc_2)
  (inc-loop-count! 'pc_3)
  (inc-loop-count! 'pc_4)
  ;; Now 5 entries exist (loop-pc-alpha, pc_1..pc_4)
  (let ((res (inc-loop-count! 'pc_overflow)))
    (assert-equal "1.9 Overflow entry rejected (returns 0)" 0 res)
    (assert-equal "1.10 Overflow entry was not added" 0 (get-loop-count 'pc_overflow)))
  (set! *jit-max-profiler-entries* saved-limit))

;;; -----------------------------------------------------------------------
;;; Group 2: Delimited Continuations & Prompt Boundary Protection
;;; -----------------------------------------------------------------------
(print-group "--- Group 2: Delimited Continuations & Prompt Boundary ---")

(assert-equal "2.1 Initial prompt depth is 0" 0 (prompt-depth))

;; with-jit-prompt execution
(let ((val (with-jit-prompt
             (+ 10 20))))
  (assert-equal "2.2 with-jit-prompt returns result" 30 val)
  (assert-equal "2.3 Prompt depth popped back to 0" 0 (prompt-depth)))

;; shift inside with-jit-prompt (single-shot continuation capture)
(let ((val (with-jit-prompt
             (+ 5 (shift k (k (* 2 10)))))))
  (assert-equal "2.4 shift composes continuation correctly" 25 val)
  (assert-equal "2.5 Prompt depth clean after shift" 0 (prompt-depth)))

;; CWE-674: Prompt depth limit protection
(let ((err-caught #f)
      (saved-max *max-prompt-depth*))
  (set! *max-prompt-depth* 3)
  (guard (ex (else (set! err-caught #t)))
    (with-jit-prompt
      (with-jit-prompt
        (with-jit-prompt
          (with-jit-prompt
            'should-fail)))))
  (assert-true "2.6 Excessive prompt nesting triggers CWE-674 error" err-caught)
  ;; Clean up meta-continuation stack
  (set! *meta-continuation-stack* '())
  (set! *max-prompt-depth* saved-max))

;;; -----------------------------------------------------------------------
;;; Group 3: Linear S-expression Trace Recording & Cycle Closure
;;; -----------------------------------------------------------------------
(print-group "--- Group 3: Linear Trace Recording & Cycle Closure ---")

(tracer-reset!)
(set-hot-threshold! 1)

;; High-level capture-loop-trace-delimited
(let ((trace (capture-loop-trace-delimited
              'test_loop_1
              '(i sum)
              (lambda ()
                (trace-guard! 'type-fixnum 'i 'fixnum 'bailout_1)
                (trace-record! '%add 'sum 'sum 'i)
                (trace-record! '%add 'i 'i 1)))))

  (assert-true "3.1 Trace object generated" (pair? trace))
  (assert-equal "3.2 Root tag is %trace-loop" '%trace-loop (car trace))
  (let* ((fields (cdr trace))
         (pc-entry (assq '%pc fields))
         (body-entry (assq '%body fields)))
    (assert-equal "3.3 PC entry is test_loop_1" 'test_loop_1 (cadr pc-entry))
    (let ((body (cadr body-entry)))
      (assert-equal "3.4 Body starts with %trace-loop-entry" '%trace-loop-entry (caar body))
      (assert-equal "3.5 Body ends with %trace-loop-jump" '%trace-loop-jump (car (car (reverse body))))
      (assert-equal "3.6 Total 5 instructions in linear trace" 5 (length body)))))

;;; -----------------------------------------------------------------------
;;; Group 4: Bridge to Canonical Low-Level IR (%lir-program)
;;; -----------------------------------------------------------------------
(print-group "--- Group 4: Bridge to Low-Level IR (%lir-program) ---")

(let* ((sample-trace
        '(%trace-loop
           (%pc loop_add)
           (%body ((%trace-loop-entry loop_add)
                   (%guard type-fixnum reg_x fixnum fail_target_1)
                   (%add reg_acc reg_acc reg_x)
                   (%trace-loop-jump loop_add)))))
       (lir-prog (trace->lir-program sample-trace)))

  (assert-true "4.1 LIR program generated" (pair? lir-prog))
  (assert-equal "4.2 Root tag is %lir-program" '%lir-program (car lir-prog))
  (let* ((lir-main (assq '%lir-main (cdr lir-prog)))
         (body-field (assq 'body (cdr lir-main)))
         (insts (cadr body-field)))
    (assert-true "4.3 LIR main has body" (pair? insts))
    (assert-equal "4.4 First LIR inst is function label" '%label (caar insts))
    ;; Verify presence of guard and arithmetic operations
    (assert-true "4.5 Contains %jump-if-zero for guard"
                 (pair? (assoc '%jump-if-zero insts)))
    (assert-true "4.6 Contains %add instruction"
                 (pair? (assoc '%add insts)))))

;;; -----------------------------------------------------------------------
;;; Group 5: Control Flow Straight-Line Linearization
;;; -----------------------------------------------------------------------
(print-group "--- Group 5: Control Flow Straight-Line Linearization ---")

;; Test that an interpreter loop with an internal branch records ONLY
;; the hot path taken, with the alternative path converted to %guard
(tracer-reset!)
(set-hot-threshold! 1)

(define (simulated-interpreter-step op x y)
  (case op
    ((add)
     (trace-guard! 'cmp-eq 'op 'add 'bailout_op_mismatch)
     (trace-record! '%add 'dst x y))
    ((sub)
     (trace-guard! 'cmp-eq 'op 'sub 'bailout_op_mismatch)
     (trace-record! '%sub 'dst x y))))

(let ((trace (capture-loop-trace-delimited
              'dispatch_loop
              '(op x y dst)
              (lambda ()
                ;; Execute 'add branch
                (simulated-interpreter-step 'add 'reg_a 'reg_b)))))
  (let* ((body (cadr (assq '%body (cdr trace)))))
    ;; Verify that %sub is completely absent and only %add exists
    (assert-true "5.1 Contains %add" (pair? (assoc '%add body)))
    (assert-false "5.2 %sub branch completely eliminated" (assoc '%sub body))
    (assert-true "5.3 Guard exists for branch protection" (pair? (assoc '%guard body)))))

;;; -----------------------------------------------------------------------
;;; Group 6: Register Pool Spill to Stack Slots
;;; -----------------------------------------------------------------------
(print-group "--- Group 6: Register Pool Spill to Stack ---")

;; Define trace with 6 variables (> 4 available in *reg-pool*)
(let* ((vars-6 '(v1 v2 v3 v4 v5 v6))
       (vmap (allocate-lir-registers vars-6)))
  (assert-equal "6.1 vmap allocated for 6 variables" 6 (length vmap))
  ;; First 4 variables must receive hardware registers
  (assert-equal "6.2 v1 gets %rax" '%rax (cdr (assq 'v1 vmap)))
  (assert-equal "6.3 v2 gets %rdx" '%rdx (cdr (assq 'v2 vmap)))
  (assert-equal "6.4 v3 gets %rcx" '%rcx (cdr (assq 'v3 vmap)))
  (assert-equal "6.5 v4 gets %r10" '%r10 (cdr (assq 'v4 vmap)))
  ;; 5th and 6th variables must spill to stack
  (assert-equal "6.6 v5 spilled to (%stack -16)" '(%stack -16) (cdr (assq 'v5 vmap)))
  (assert-equal "6.7 v6 spilled to (%stack -24)" '(%stack -24) (cdr (assq 'v6 vmap))))

(display "\n[PASS] All Hot-Loop Profiler & Linear Trace Recorder tests passed successfully!\n\n")
