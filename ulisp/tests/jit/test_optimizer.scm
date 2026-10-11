;;; =======================================================================
;;; MLisp Test Suite: Trace Optimizer & Virtual Allocations (test_optimizer.scm)
;;; Conforms to DSN-34 Architecture Specification & Issue #507
;;;
;;; Verifies pure Scheme trace optimizations:
;;; - Partial evaluation & constant folding
;;; - Constant propagation and dead code elimination
;;; - Trivial guard removal
;;; - Virtual object optimization (cons/car/cdr elimination)
;;; - Combined multi-pass optimization pipeline
;;; =======================================================================

(define *opt-tests-passed* 0)
(define *opt-tests-failed* 0)

(define (assert-equal test-name expected actual)
  (if (equal? expected actual)
      (begin
        (set! *opt-tests-passed* (+ *opt-tests-passed* 1))
        (display "  [PASS] ")
        (display test-name)
        (newline))
      (begin
        (set! *opt-tests-failed* (+ *opt-tests-failed* 1))
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
(display " Starting MLisp Trace Optimizer & Virtuals Test Suite")
(newline)
(display "=======================================================")
(newline)

;;; Test 1: Constant folding
(display "--- Test 1: Constant Folding ---")
(newline)
(let* ((input-trace
        '(%trace-loop
           (%pc test-pc-1)
           (%body
             ((%trace-loop-entry test-pc-1)
              (%add reg-a 10 20)
              (%mul reg-b 3 7)
              (%trace-loop-jump test-pc-1)))))
       (opt (optimize-trace-pe input-trace))
       (body (cadr (assq '%body (cdr opt)))))
  (assert-equal "add 10 20 folded to mov 30"
                '(%mov reg-a 30)
                (cadr body))
  (assert-equal "mul 3 7 folded to mov 21"
                '(%mov reg-b 21)
                (caddr body)))

;;; Test 2: Constant propagation across instructions
(display "--- Test 2: Constant Propagation ---")
(newline)
(let* ((input-trace
        '(%trace-loop
           (%pc test-pc-2)
           (%body
             ((%trace-loop-entry test-pc-2)
              (%mov reg-x 5)
              (%add reg-y reg-x 10)
              (%trace-loop-jump test-pc-2)))))
       (opt (optimize-trace-pe input-trace))
       (body (cadr (assq '%body (cdr opt)))))
  (assert-equal "mov reg-x 5 preserved"
                '(%mov reg-x 5)
                (cadr body))
  (assert-equal "reg-x propagated into add and folded to 15"
                '(%mov reg-y 15)
                (caddr body)))

;;; Test 3: Redundant move and trivial guard elimination
(display "--- Test 3: Redundant Move & Trivial Guard Removal ---")
(newline)
(let* ((input-trace
        '(%trace-loop
           (%pc test-pc-3)
           (%body
             ((%trace-loop-entry test-pc-3)
              (%mov reg-x reg-x)                 ; Redundant self-move -> should drop
              (%guard < 5 10 bailout-fail)       ; 5 < 10 is statically TRUE -> should drop
              (%guard > 5 10 bailout-fail)       ; 5 > 10 is statically FALSE -> keep
              (%trace-loop-jump test-pc-3)))))
       (opt (optimize-trace-pe input-trace))
       (body (cadr (assq '%body (cdr opt)))))
  (assert-equal "body length reduced from 5 to 3" 3 (length body))
  (assert-equal "first instruction is entry" '(%trace-loop-entry test-pc-3) (car body))
  (assert-equal "second instruction is the non-trivial guard" '(%guard > 5 10 bailout-fail) (cadr body))
  (assert-equal "third instruction is jump" '(%trace-loop-jump test-pc-3) (caddr body)))

;;; Test 4: Virtual pair allocation elimination (Virtuals)
(display "--- Test 4: Virtual Object Elimination (cons / car / cdr) ---")
(newline)
(let* ((input-trace
        '(%trace-loop
           (%pc test-pc-4)
           (%body
             ((%trace-loop-entry test-pc-4)
              (%cons tmp-pair val-a val-b)       ; Non-escaping allocation -> should be ELIMINATED!
              (%car out-car tmp-pair)            ; Should rewrite to (%mov out-car val-a)
              (%cdr out-cdr tmp-pair)            ; Should rewrite to (%mov out-cdr val-b)
              (%trace-loop-jump test-pc-4)))))
       (opt (optimize-trace-virtuals input-trace))
       (body (cadr (assq '%body (cdr opt)))))
  (assert-equal "cons was completely removed from trace body"
                #f
                (assq '%cons body))
  (assert-equal "car rewritten to direct move from val-a"
                '(%mov out-car val-a)
                (cadr body))
  (assert-equal "cdr rewritten to direct move from val-b"
                '(%mov out-cdr val-b)
                (caddr body)))

;;; Test 5: Escaping allocation must be preserved
(display "--- Test 5: Escaping Allocation Preservation ---")
(newline)
(let* ((input-trace
        '(%trace-loop
           (%pc test-pc-5)
           (%body
             ((%trace-loop-entry test-pc-5)
              (%cons esc-pair 1 2)
              (%store-global global-head esc-pair) ; Escapes to global!
              (%trace-loop-jump test-pc-5)))))
       (opt (optimize-trace-virtuals input-trace))
       (body (cadr (assq '%body (cdr opt)))))
  (assert-true "cons is preserved because it escapes to global"
               (pair? (assq '%cons body))))

;;; Test 6: Combined Full Optimizer Pipeline (PE + Virtuals + PE)
(display "--- Test 6: Full Combined Optimizer Pipeline ---")
(newline)
(let* ((input-trace
        '(%trace-loop
           (%pc test-pc-6)
           (%body
             ((%trace-loop-entry test-pc-6)
              (%mov num-1 100)
              (%mov num-2 200)
              (%cons pair num-1 num-2)           ; Virtual pair!
              (%car read-1 pair)                 ; Reads num-1
              (%cdr read-2 pair)                 ; Reads num-2
              (%add total read-1 read-2)         ; 100 + 200 = 300!
              (%trace-loop-jump test-pc-6)))))
       (opt (optimize-trace-full input-trace))
       (body (cadr (assq '%body (cdr opt)))))
  ;; In the fully optimized trace:
  ;; %cons is gone, read-1 and read-2 became 100 and 200, and %add total 100 200 became (%mov total 300)!
  (assert-equal "cons is gone in full pipeline" #f (assq '%cons body))
  (assert-true "total computed to constant 300"
               (member '(%mov total 300) body)))

(display "=======================================================")
(newline)
(display " All ")
(display *opt-tests-passed*)
(display " MLisp Trace Optimizer tests PASSED successfully! (0 failures)")
(newline)
(display "=======================================================")
(newline)
