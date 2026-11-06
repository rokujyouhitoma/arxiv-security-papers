;;; =======================================================================
;;; ULisp AArch64 Native Execution Smoke Tests
;;; Conforms to Issue #691 & DSN-33 Architecture Specification
;;; Contains Scheme definitions for QEMU emulation smoke test suite.
;;; =======================================================================

;; Case 1: Simple Arithmetic & Immediate Expressions
(define (smoke-test-arithmetic)
  (+ 40 2))

;; Case 2: Recursive Fibonacci (Branching & Call ABI)
(define (smoke-test-fib n)
  (if (<= n 1)
      n
      (+ (smoke-test-fib (- n 1)) (smoke-test-fib (- n 2)))))

;; Case 3: Strings & write-string output
(define (smoke-test-string-io)
  (begin
    (write-string "Hello AArch64 Pure Scheme!\n")
    0))

;; Case 4: Higher-Order Closures & Environment Capture
(define (smoke-test-closure)
  ((lambda (x)
     ((lambda (y)
        (+ x y))
      12))
   30))

;; Case 5: 100,000 Iteration Tail Call Optimization (TCO) Loop
(define (smoke-test-tco-loop n acc)
  (if (= n 0)
      acc
      (smoke-test-tco-loop (- n 1) (+ acc 1))))

;; Case 6: Pure Scheme write-char & Newline
(define (smoke-test-char-io)
  (begin
    (write-char #\A)
    (write-char #\A)
    (write-char #\R)
    (write-char #\C)
    (write-char #\H)
    (write-char #\6)
    (write-char #\4)
    (write-char #\newline)
    0))

;; Case 7: Exception Guard & Raise (Issue #748)
(define (smoke-test-exception)
  (guard (ex
          ((eq? ex 99) 42)
          (else 0))
    (+ 10 20)
    (raise 99)))

;; Case 8: First-Class Continuation call/cc (Issue #748)
(define (smoke-test-callcc)
  (%raw-call/cc
    (lambda (k)
      (k 42)
      100)))

;; Case 9: Nested Exception Guard & Handler Chain Isolation (Issue #748)
(define (smoke-test-nested-guard)
  (guard (outer ((eq? outer 'outer-err) 42))
    (let ((res (guard (inner ((eq? inner 10) 'inner-ok))
                 (raise 10))))
      (if (eq? res 'inner-ok)
          42
          0))))

