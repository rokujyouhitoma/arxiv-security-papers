;;; =======================================================================
;;; MLisp Live Demonstration: Endogenous Meta-Tracing JIT in Action
;;; Demonstrates TinyVM execution, dynamic trace recording,
;;; partial evaluation & virtual object optimization, and LIR bridge!
;;; =======================================================================

(display "==================================================================")
(newline)
(display "        MLisp 100% Pure Scheme Meta-Tracing JIT Demo              ")
(newline)
(display "==================================================================")
(newline)
(newline)

;;; -----------------------------------------------------------------------
;;; Part 1: TinyVM Stack Machine Execution & Automatic JIT Synthesis
;;; -----------------------------------------------------------------------
(display ">>> [DEMO 1] Running TinyVM Bytecode Stack Machine...")
(newline)
(display "    Target Program: sum = 0; i = 0; while (i < 5) { sum += i; i += 1; }")
(newline)

;; Reset tracer state
(tracer-reset!)
(set-hot-threshold! 3)
(jit-runtime-reset!)

;; Define bytecode program
(define demo-tiny-prog
  '(;; PC 0: init sum = 0, i = 0
    (PUSH 0) (STORE sum)
    (PUSH 0) (STORE i)
    ;; PC 4: loop header (triggers jit-merge-point)
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

(display "    Executing TinyVM interpreter...")
(newline)
(define vm-result (run-tiny-vm demo-tiny-prog '()))
(display "    => TinyVM Execution Result: sum = ")
(display vm-result)
(newline)
(newline)

(display ">>> Inspecting Automatically Synthesized JIT Trace:")
(newline)
(define raw-trace (lookup-compiled-trace 4))
(display "    [Raw Trace S-Expression]:")
(newline)
(write raw-trace)
(newline)
(newline)

(display ">>> Applying Pure Scheme Trace Optimizations (PE + Virtuals):")
(newline)
(define opt-trace (optimize-trace-full raw-trace))
(display "    [Optimized Trace S-Expression]:")
(newline)
(write opt-trace)
(newline)
(newline)

(display ">>> Translating Optimized Trace into Canonical ULisp Pass 6 LIR:")
(newline)
(define lir-prog (trace->lir-program opt-trace))
(display "    [ULisp %lir-program Structure]:")
(newline)
(write lir-prog)
(newline)
(newline)

;;; -----------------------------------------------------------------------
;;; Part 2: Metacircular Scheme Evaluator (Scheme-on-Scheme Self-Applied JIT)
;;; -----------------------------------------------------------------------
(display ">>> [DEMO 2] Running Metacircular Scheme Evaluator (Self-Applied JIT)...")
(newline)
(define test-expr
  '(let ((x 10) (y 32))
     (+ x y)))

(display "    Evaluating Scheme expression: ")
(write test-expr)
(newline)
(define eval-res (mini-eval test-expr '()))
(display "    => Metacircular Evaluator Result: ")
(display eval-res)
(newline)
(newline)

(display "==================================================================")
(newline)
(display " MLisp Demonstration completed successfully! All steps 100% Scheme.")
(newline)
(display "==================================================================")
(newline)
