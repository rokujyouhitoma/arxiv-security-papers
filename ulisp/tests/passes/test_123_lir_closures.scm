;;; =======================================================================
;;; Unit Test: Pass 123 (LIR Closures & Stack Allocation)
;;; Conforms to DSN-33 Architecture Specification & Issue #583
;;; =======================================================================

(define *tests-passed* 0)
(define *tests-failed* 0)

(define (assert-true test-name expr)
  (if expr
      (begin
        (set! *tests-passed* (+ *tests-passed* 1))
        (display "  [PASS] ")
        (display test-name)
        (newline))
      (begin
        (set! *tests-failed* (+ *tests-failed* 1))
        (display "  [FAIL] ")
        (display test-name)
        (newline)
        (exit 1))))

(display "=======================================================\n")
(display " Starting Pass 123 (LIR Closures & Stack Allocation) Unit Tests\n")
(display "=======================================================\n")

;; Test 1: Heap closure creation (%make-closure 'label arg1 arg2)
(reset-lir!)
(lir-compile-make-closure '(%make-closure 'L_fn x y) -24 '((x . -8) (y . -16)))
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "make-closure: emits %alloc for heap allocation"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%alloc))) insts)))
  (assert-true "make-closure: emits %code-ref for target function label"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%code-ref) (eq? (caddr i) 'L_fn))) insts))))

;; Test 2: Stack-allocated pair (%stack-cons e1 e2)
(reset-lir!)
(lir-compile-stack-cons '(%stack-cons 10 20) -8 '())
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "stack-cons: emits %alloc-stack with pair tag 1"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%alloc-stack) (= (cadddr i) 1))) insts))))

;; Test 3: Stack-allocated closure (%make-stack-closure 'label arg1)
(reset-lir!)
(lir-compile-make-stack-closure '(%make-stack-closure 'L_stack_fn x) -16 '((x . -8)))
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "stack-closure: emits %alloc-stack with closure tag 1"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%alloc-stack) (= (cadddr i) 1))) insts)))
  (assert-true "stack-closure: emits %code-ref for stack label"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%code-ref) (eq? (caddr i) 'L_stack_fn))) insts))))

(display "=======================================================\n")
(display " Pass 123: All tests passed!\n")
(display "=======================================================\n")
