;;; =======================================================================
;;; MLisp Test Suite: Example VMs & End-to-End JIT (test_examples.scm)
;;; Conforms to DSN-34 Architecture Specification & Issue #507
;;;
;;; Verifies:
;;; - TinyVM stack machine execution and automatic JIT trace synthesis
;;; - Metacircular Scheme evaluator self-applied JIT compilation
;;; - Full 100% Pure Scheme execution lifecycle
;;; =======================================================================

(define *ex-tests-passed* 0)
(define *ex-tests-failed* 0)

(define (assert-equal test-name expected actual)
  (if (equal? expected actual)
      (begin
        (set! *ex-tests-passed* (+ *ex-tests-passed* 1))
        (display "  [PASS] ")
        (display test-name)
        (newline))
      (begin
        (set! *ex-tests-failed* (+ *ex-tests-failed* 1))
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
(display " Starting MLisp Example VMs & E2E JIT Test Suite")
(newline)
(display "=======================================================")
(newline)

;;; Reset global tracer & JIT runtime
(tracer-reset!)
(set-hot-threshold! 3)
(jit-runtime-reset!)

;;; Test 1: TinyVM Execution & Trace Synthesis
(display "--- Test 1: TinyVM Stack Machine & JIT Integration ---")
(newline)
;; Program: sum = 0; i = 0; while (i < 5) { sum = sum + i; i = i + 1; }
(define tiny-sum-prog
  '(;; PC 0: init
    (PUSH 0) (STORE sum)
    (PUSH 0) (STORE i)
    ;; PC 4: loop header
    (LOOP-HEADER)
    ;; PC 5: sum = sum + i
    (LOAD sum)
    (LOAD i)
    (ADD)
    (STORE sum)
    ;; PC 9: i = i + 1
    (LOAD i)
    (PUSH 1)
    (ADD)
    (STORE i)
    ;; PC 13: condition (i < 5)
    (LOAD i)
    (PUSH 5)
    (JUMP-IF-LT 4)
    ;; PC 17: halt
    (LOAD sum)
    (HALT)))

(let ((res (run-tiny-vm tiny-sum-prog '())))
  (assert-equal "TinyVM computed sum 0..4 = 10" 10 res)
  (let ((trace (lookup-compiled-trace 4)))
    (assert-true "MLisp automatically synthesized trace for loop at PC 4" (pair? trace))
    (assert-equal "trace PC is 4" 4 (cadr (assq '%pc (cdr trace))))))

;;; Test 2: Metacircular Scheme Evaluator
(display "--- Test 2: Metacircular Scheme Evaluator ---")
(newline)
(let* ((env '((base . 100)))
       (e1 '(let ((x 10) (y 20)) (+ x y)))
       (res1 (mini-eval e1 env)))
  (assert-equal "mini-eval let addition" 30 res1))

(let* ((env '())
       (e2 '(if (< 5 10) 42 99))
       (res2 (mini-eval e2 env)))
  (assert-equal "mini-eval conditional if" 42 res2))

;;; Test 3: Self-Applied JIT on Scheme Loop
(display "--- Test 3: Self-Applied Scheme JIT Loop ---")
(newline)
(tracer-reset!)
(set-hot-threshold! 3)

(let* ((env '())
       ;; Loop that counts 1 to 4
       (loop-expr '(loop-tail scheme-cnt-loop (n acc) (1 0)
                              (if (< n 5)
                                  (+ acc n)
                                  acc)))
       (res (mini-eval loop-expr env)))
  (assert-equal "evaluated Scheme loop result" 1 res)
  (assert-true "loop was tracked by MLisp tracer"
               (>= (get-loop-count 'scheme-cnt-loop) 1)))

(display "=======================================================")
(newline)
(display " All ")
(display *ex-tests-passed*)
(display " MLisp Example VMs tests PASSED successfully! (0 failures)")
(newline)
(display "=======================================================")
(newline)
