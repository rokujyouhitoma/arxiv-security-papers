;;; =======================================================================
;;; MLisp Test Suite: JIT Guard Elimination & OSR Bailout (test_guard_elimination.scm)
;;; Conforms to DSN-33, DSN-34 & Issue #520
;;;
;;; Verifies:
;;; 1. A-priori Guard Elimination for static integer/fixnum operands
;;; 2. Type propagation across arithmetic chains (%add, %sub, %mul)
;;; 3. Dominating Guard Elimination for repeated type checks
;;; 4. Speculation preservation for statically unknown dynamic variables
;;; 5. Automatic OSR bailout adapter block synthesis in Pass 6 LIR bridge
;;; 6. End-to-end arithmetic loop trace guard count reduction to ZERO
;;; =======================================================================

(define *ge-tests-passed* 0)
(define *ge-tests-failed* 0)

(define (assert-equal test-name expected actual)
  (if (equal? expected actual)
      (begin
        (set! *ge-tests-passed* (+ *ge-tests-passed* 1))
        (display "  [PASS] ")
        (display test-name)
        (newline))
      (begin
        (set! *ge-tests-failed* (+ *ge-tests-failed* 1))
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
(display " Starting MLisp JIT Guard Elimination & OSR Test Suite")
(newline)
(display "=======================================================")
(newline)

;;; Test 1: Immediate/Literal Guard Elimination
(display "--- Test 1: Immediate & Constant Guard Elimination ---")
(newline)
(let* ((input-trace
        '(%trace-loop
           (%pc test-ge-1)
           (%body
             ((%trace-loop-entry test-ge-1)
              (%guard type-fixnum 10 fixnum exit-bailout-1)
              (%guard fixnum-check 42 fixnum exit-bailout-2)
              (%mov reg-x 100)
              (%guard type-fixnum reg-x fixnum exit-bailout-3)
              (%trace-loop-jump test-ge-1)))))
       (opt (optimize-trace-pe input-trace))
       (body (cadr (assq '%body (cdr opt)))))
  (assert-true "literal guard 10 eliminated" (not (member '(%guard type-fixnum 10 fixnum exit-bailout-1) body)))
  (assert-true "literal guard 42 eliminated" (not (member '(%guard fixnum-check 42 fixnum exit-bailout-2) body)))
  (assert-true "constant reg-x guard eliminated" (not (member '(%guard type-fixnum reg-x fixnum exit-bailout-3) body)))
  (assert-equal "all trivial guards eliminated (only entry, mov, jump remain)"
                3
                (length body)))

;;; Test 2: Type Propagation across Arithmetic Chains
(display "--- Test 2: Arithmetic Chain Type Propagation ---")
(newline)
(let* ((input-trace
        '(%trace-loop
           (%pc test-ge-2)
           (%types ((a . fixnum) (b . fixnum)))
           (%body
             ((%trace-loop-entry test-ge-2)
              (%guard type-fixnum a fixnum exit-a)
              (%guard type-fixnum b fixnum exit-b)
              (%add sum a b)
              (%guard type-fixnum sum fixnum exit-sum)
              (%mul prod sum 2)
              (%guard type-fixnum prod fixnum exit-prod)
              (%trace-loop-jump test-ge-2)))))
       (opt (optimize-trace-pe input-trace))
       (body (cadr (assq '%body (cdr opt)))))
  (assert-true "guard on typed input a eliminated" (not (member '(%guard type-fixnum a fixnum exit-a) body)))
  (assert-true "guard on typed input b eliminated" (not (member '(%guard type-fixnum b fixnum exit-b) body)))
  (assert-true "guard on %add result eliminated" (not (member '(%guard type-fixnum sum fixnum exit-sum) body)))
  (assert-true "guard on %mul result eliminated" (not (member '(%guard type-fixnum prod fixnum exit-prod) body)))
  (assert-equal "total guards in optimized body is 0"
                0
                (length (filter (lambda (inst) (eq? (car inst) '%guard)) body))))

;;; Test 3: Dominating Guard Elimination (Redundant Guard Removal)
(display "--- Test 3: Dominating Guard Elimination ---")
(newline)
(let* ((input-trace
        '(%trace-loop
           (%pc test-ge-3)
           (%body
             ((%trace-loop-entry test-ge-3)
              (%guard type-fixnum unknown-var fixnum exit-first)
              (%mov intermediate unknown-var)
              (%guard type-fixnum unknown-var fixnum exit-second)
              (%guard type-fixnum intermediate fixnum exit-third)
              (%trace-loop-jump test-ge-3)))))
       (opt (optimize-trace-pe input-trace))
       (body (cadr (assq '%body (cdr opt)))))
  (assert-true "first guard on dynamic unknown-var preserved"
               (member '(%guard type-fixnum unknown-var fixnum exit-first) body))
  (assert-true "second redundant guard on unknown-var ELIMINATED"
               (not (member '(%guard type-fixnum unknown-var fixnum exit-second) body)))
  (assert-true "third redundant guard on moved variable ELIMINATED"
               (not (member '(%guard type-fixnum intermediate fixnum exit-third) body)))
  (assert-equal "only 1 guard remains in body"
                1
                (length (filter (lambda (inst) (eq? (car inst) '%guard)) body))))

;;; Test 4: OSR Bailout Adapter Synthesis
(display "--- Test 4: OSR Bailout Adapter Synthesis ---")
(newline)
(let* ((speculative-trace
        '(%trace-loop
           (%pc test-ge-4)
           (%body
             ((%trace-loop-entry test-ge-4)
              (%guard type-fixnum dyn-val fixnum deopt-target-99)
              (%add dyn-val dyn-val 1)
              (%trace-loop-jump test-ge-4)))))
       (lir-prog (trace->lir-program speculative-trace))
       (main-entry (assq '%lir-main (cdr lir-prog)))
       (body (cadr (assq 'body (cdr main-entry)))))
  (assert-true "LIR contains deopt-target-99 label"
               (pair? (member '(%label deopt-target-99) body)))
  (assert-true "LIR contains OSR deopt sentinel mov %rax 255"
               (pair? (member '(%mov %rax 255) body)))
  (assert-true "LIR contains return for OSR bailout"
               (pair? (member '(%return) body))))

;;; Test 5: End-to-End Loop Trace Guard Elimination (TinyVM Loop)
(display "--- Test 5: End-to-End Loop Trace Guard Elimination (TinyVM Loop) ---")
(newline)
(let* ((tiny-vm-trace
        '(%trace-loop
           (%pc 4)
           (%body
             ((%trace-loop-entry 4)
              (%guard type-fixnum 1 fixnum exit-guard)
              (%mov sum 1)
              (%guard type-fixnum 2 fixnum exit-guard)
              (%mov i 2)
              (%add reg-res 1 2)
              (%mov sum 3)
              (%guard type-fixnum 2 fixnum exit-guard)
              (%mov i 2)
              (%mov reg-val 1)
              (%add reg-res 2 1)
              (%mov i 3)
              (%guard type-fixnum 3 fixnum exit-guard)
              (%mov i 3)
              (%mov reg-val 5)
              (%guard cmp-lt 3 5 exit-guard)
              (%trace-loop-jump 4)))))
       (opt (optimize-trace-pe tiny-vm-trace))
       (body (cadr (assq '%body (cdr opt))))
       (guards (filter (lambda (inst) (eq? (car inst) '%guard)) body)))
  (assert-equal "all type and trivial condition guards eliminated: count = 0"
                0
                (length guards))
  (assert-equal "total body instructions reduced from 17 to 12 (all 5 guards removed)"
                12
                (length body)))

(display "=======================================================")
(newline)
(display " All ")
(display *ge-tests-passed*)
(display " MLisp JIT Guard Elimination & OSR tests PASSED successfully! (0 failures)")
(newline)
(display "=======================================================")
(newline)
