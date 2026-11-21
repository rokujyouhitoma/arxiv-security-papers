;;; =======================================================================
;;; MLisp Test Suite: JIT Optimizer & Deopt Trampoline (test_jit_optimizer.scm)
;;; Conforms to DSN-33, DSN-34 & Issue #900
;;;
;;; Verifies:
;;; - Group 1: Constant folding, propagation & trivial guard removal
;;; - Group 2: Dominating Guard Elimination (type & comparison guards)
;;; - Group 3: Virtual Object Optimization & Allocation Removal (O(0) allocation)
;;; - Group 4: Guard failure Deopt Trampoline & Interpreter frame reconstruction
;;; - Group 5: Virtual Object Re-materialization on Deopt (CWE-400 defense)
;;; - Group 6: Deopt thrashing detector & trace blacklisting (CWE-674 defense)
;;; =======================================================================

(test-begin "MLisp JIT Trace Optimizer & Deopt Trampoline")

;;; Reset JIT & Deopt runtime
(jit-runtime-reset!)

;;; =======================================================================
;;; Group 1: Constant Folding, Propagation & Trivial Guard Removal
;;; =======================================================================
(display "--- Group 1: Constant Folding & Trivial Guards ---")
(newline)

(let* ((input-trace
        '(%trace-loop
           (%pc loop-g1)
           (%body
             ((%trace-loop-entry loop-g1)
              (%mov reg-c 10)
              (%add reg-d reg-c 25)
              (%guard cmp-lt reg-c 50 fail-g1) ; 10 < 50 is statically TRUE -> eliminate!
              (%trace-loop-jump loop-g1)))))
       (opt (optimize-trace-pe input-trace))
       (body (cadr (assq '%body (cdr opt)))))
  (assert-equal "1.1 Constant move preserved" '(%mov reg-c 10) (cadr body))
  (assert-equal "1.2 Constant folded into mov" '(%mov reg-d 35) (caddr body))
  (assert-equal "1.3 Statically true guard eliminated (only entry, mov, mov, jump remain)"
                4
                (length body)))

;;; =======================================================================
;;; Group 2: Dominating Guard Elimination
;;; =======================================================================
(display "--- Group 2: Dominating Guard Elimination ---")
(newline)

;;; Test 2.1: Repeated Type Guards on Same Variable
(let* ((input-trace
        '(%trace-loop
           (%pc loop-g2-1)
           (%body
             ((%trace-loop-entry loop-g2-1)
              (%guard type-fixnum var-dyn fixnum fail-lbl-1)
              (%guard fixnum-check var-dyn fixnum fail-lbl-2) ; Dominating guard -> eliminate!
              (%trace-loop-jump loop-g2-1)))))
       (opt (optimize-trace-pe input-trace))
       (body (cadr (assq '%body (cdr opt)))))
  (assert-true "2.1 First guard preserved"
               (member '(%guard type-fixnum var-dyn fixnum fail-lbl-1) body))
  (assert-true "2.2 Redundant dominated guard eliminated"
               (not (member '(%guard fixnum-check var-dyn fixnum fail-lbl-2) body)))
  (assert-equal "2.3 Exactly one guard remains"
                3 ; entry, first guard, jump
                (length body)))

;;; Test 2.2: Repeated Comparison Guard on Unmodified Variable
(let* ((input-trace
        '(%trace-loop
           (%pc loop-g2-2)
           (%body
             ((%trace-loop-entry loop-g2-2)
              (%guard cmp-lt reg-i 100 fail-lbl-a)
              (%guard cmp-lt reg-i 100 fail-lbl-b) ; Dominating guard -> eliminate!
              (%trace-loop-jump loop-g2-2)))))
       (opt (optimize-trace-pe input-trace))
       (body (cadr (assq '%body (cdr opt)))))
  (assert-true "2.4 First comparison guard preserved"
               (member '(%guard cmp-lt reg-i 100 fail-lbl-a) body))
  (assert-true "2.5 Second dominated comparison guard eliminated"
               (not (member '(%guard cmp-lt reg-i 100 fail-lbl-b) body)))
  (assert-equal "2.6 Exactly one comparison guard remains"
                3
                (length body)))

;;; Test 2.3: Invalidation of Dominating Guard upon Variable Mutation
(let* ((input-trace
        '(%trace-loop
           (%pc loop-g2-3)
           (%body
             ((%trace-loop-entry loop-g2-3)
              (%guard cmp-lt reg-i 100 fail-lbl-a)
              (%add reg-i reg-i 1) ; Mutates reg-i! Invalidates prior guard condition!
              (%guard cmp-lt reg-i 100 fail-lbl-b) ; Must NOT be eliminated!
              (%trace-loop-jump loop-g2-3)))))
       (opt (optimize-trace-pe input-trace))
       (body (cadr (assq '%body (cdr opt)))))
  (assert-true "2.7 Guard prior to mutation preserved"
               (member '(%guard cmp-lt reg-i 100 fail-lbl-a) body))
  (assert-true "2.8 Guard after mutation preserved"
               (member '(%guard cmp-lt reg-i 100 fail-lbl-b) body))
  (assert-equal "2.9 Both guards retained due to mutation"
                5 ; entry, guard1, add, guard2, jump
                (length body)))

;;; =======================================================================
;;; Group 3: Virtual Object Optimization & Allocation Removal
;;; =======================================================================
(display "--- Group 3: Virtual Object Optimization ---")
(newline)

(let* ((input-trace
        '(%trace-loop
           (%pc loop-g3)
           (%body
             ((%trace-loop-entry loop-g3)
              (%cons p-temp val-x val-y) ; Non-escaping allocation -> eliminate!
              (%car read-car p-temp)     ; Rewrite to (%mov read-car val-x)
              (%cdr read-cdr p-temp)     ; Rewrite to (%mov read-cdr val-y)
              (%add result read-car read-cdr)
              (%trace-loop-jump loop-g3)))))
       (opt (optimize-trace-virtuals input-trace))
       (v-field (assq '%virtual-objects (cdr opt)))
       (body (cadr (assq '%body (cdr opt)))))
  (assert-true "3.1 %virtual-objects metadata present in trace" (pair? v-field))
  (assert-true "3.2 p-temp recorded in virtual object table" (pair? (assq 'p-temp (cadr v-field))))
  (assert-true "3.3 Physical %cons instruction removed" (not (member '(%cons p-temp val-x val-y) body)))
  (assert-true "3.4 %car rewritten to direct move" (member '(%mov read-car val-x) body))
  (assert-true "3.5 %cdr rewritten to direct move" (member '(%mov read-cdr val-y) body)))

;;; =======================================================================
;;; Group 4: Guard Failure Deopt Trampoline & Frame Reconstruction
;;; =======================================================================
(display "--- Group 4: Deopt Trampoline & Frame Reconstruction ---")
(newline)

(let* ((snapshot (make-deopt-snapshot 'pc-eval-loop
                                      '((var-x . %rax)
                                        (var-y . %rdx)
                                        (var-z . 42))
                                      '()))
       (machine-state '((%rax . 100)
                        (%rdx . 200)))
       (recovered-frame (restore-interpreter-frame snapshot machine-state)))
  (assert-equal "4.1 var-x recovered from %rax" 100 (cdr (assq 'var-x recovered-frame)))
  (assert-equal "4.2 var-y recovered from %rdx" 200 (cdr (assq 'var-y recovered-frame)))
  (assert-equal "4.3 var-z recovered from immediate literal" 42 (cdr (assq 'var-z recovered-frame))))

;;; Test Deopt Trigger with handler
(register-deopt-snapshot! 'bailout-target-g4
                          (make-deopt-snapshot 'loop-eval-main
                                               '((i . %rax) (sum . %rdx))
                                               '()))
(let* ((bailout-called #f)
       (passed-pc #f)
       (passed-frame #f)
       (handler (lambda (pc lbl frame blacklisted?)
                  (set! bailout-called #t)
                  (set! passed-pc pc)
                  (set! passed-frame frame))))
  (trigger-guard-deopt! 'loop-eval-main 'bailout-target-g4 '((%rax . 15) (%rdx . 120)) handler)
  (assert-true "4.4 Deopt handler invoked" bailout-called)
  (assert-equal "4.5 Handled PC matched" 'loop-eval-main passed-pc)
  (assert-equal "4.6 Recovered i in handler" 15 (cdr (assq 'i passed-frame)))
  (assert-equal "4.7 Recovered sum in handler" 120 (cdr (assq 'sum passed-frame))))

;;; =======================================================================
;;; Group 5: Virtual Object Re-materialization on Deoptimization
;;; =======================================================================
(display "--- Group 5: Virtual Object Re-materialization ---")
(newline)

(let* ((v-defs '((virt-pair pair %rax %rdx)))
       (snapshot (make-deopt-snapshot 'loop-pair-deopt
                                      '((result-pair . virt-pair)
                                        (scalar-val . %rax))
                                      v-defs))
       (machine-state '((%rax . 55)
                        (%rdx . 99)))
       (recovered (restore-interpreter-frame snapshot machine-state)))
  (assert-equal "5.1 Scalar value preserved" 55 (cdr (assq 'scalar-val recovered)))
  (assert-equal "5.2 Virtual pair re-materialized into concrete cons cell"
                '(55 . 99)
                (cdr (assq 'result-pair recovered)))
  (assert-true "5.3 Re-materialization counter incremented"
               (> *jit-stats-rematerializations* 0)))

;;; Nested virtual pair re-materialization
(let* ((v-defs '((inner-pair pair 10 20)
                 (outer-pair pair inner-pair 30)))
       (snapshot (make-deopt-snapshot 'loop-nested-deopt
                                      '((nested . outer-pair))
                                      v-defs))
       (recovered (restore-interpreter-frame snapshot '())))
  (assert-equal "5.4 Nested virtual pair recursively re-materialized"
                '((10 . 20) . 30)
                (cdr (assq 'nested recovered))))

;;; =======================================================================
;;; Group 6: Deopt Thrashing Detector & Trace Blacklisting (CWE-674)
;;; =======================================================================
(display "--- Group 6: Deopt Thrashing & Blacklisting (CWE-674) ---")
(newline)

(let ((test-pc 'loop-thrashing-pc))
  ;; First deopt failure: count = 1, not blacklisted
  (assert-false "6.1 Not blacklisted on 1st deopt" (record-deopt-failure! test-pc))
  (assert-false "6.2 Query reports not blacklisted" (deopt-blacklisted? test-pc))

  ;; Second deopt failure: count = 2, not blacklisted
  (assert-false "6.3 Not blacklisted on 2nd deopt" (record-deopt-failure! test-pc))
  (assert-false "6.4 Query reports not blacklisted" (deopt-blacklisted? test-pc))

  ;; Third deopt failure: count = 3 == *jit-max-deopt-thrash* -> BLACKLISTED!
  (assert-true "6.5 Blacklisted on 3rd consecutive deopt" (record-deopt-failure! test-pc))
  (assert-true "6.6 Query reports blacklisted" (deopt-blacklisted? test-pc))

  ;; Verify JIT buffer lookup bypasses blacklisted trace
  (install-jit-code! test-pc '(%lir-program (strings ()) (%lir-functions ()) (%lir-main (frame-size 16) (body ()))))
  (assert-false "6.7 JIT buffer lookup returns #f for blacklisted PC (falls back to interpreter)"
                (lookup-jit-buffer test-pc)))

(display "\n[PASS] All JIT Trace Optimizer & Deopt Trampoline tests passed successfully!\n")
(test-end "MLisp JIT Trace Optimizer & Deopt Trampoline")
