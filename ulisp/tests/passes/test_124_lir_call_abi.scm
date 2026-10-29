;;; =======================================================================
;;; Unit Test: Pass 124 (LIR Call ABI & Tail Jump Lowering)
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
(display " Starting Pass 124 (LIR Call ABI & Tail Jump Lowering) Unit Tests\n")
(display "=======================================================\n")

;; Test 1: Non-tail indirect call (%call-closure)
(reset-lir!)
(lir-compile-call 'f '(a b) -32 '((f . -8) (a . -16) (b . -24)) #f)
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "call: emits %call-closure instruction for non-tail call"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%call-closure))) insts)))
  (assert-true "call: loads arg 0 to %rdi"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%load) (eq? (cadr i) '%rdi))) insts)))
  (assert-true "call: loads arg 1 to %rsi"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%load) (eq? (cadr i) '%rsi))) insts))))

;; Test 2: Tail direct call (%direct-jump label)
(reset-lir!)
(lir-compile-direct-call 'foo_label '(a) -16 '((%num-params . 1) (a . -8)) #t)
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "direct-call: emits %direct-jump for tail-call"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%direct-jump) (eq? (cadr i) 'foo_label))) insts)))
  (assert-true "tail direct-call: loads arg 0 to %rdi"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%load) (eq? (cadr i) '%rdi))) insts))))

;; Test 3: Non-tail direct call (%direct-call label)
(reset-lir!)
(lir-compile-direct-call 'other_label '(a) -16 '((a . -8)) #f)
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "direct-call: emits %direct-call for non-tail call"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%direct-call) (eq? (cadr i) 'other_label))) insts)))
  (assert-true "direct-call: loads arg 0 to %rdi"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%load) (eq? (cadr i) '%rdi))) insts))))

;; Test 4: 7-argument direct call (registers rdi..r9 for 0..5, stack for 6)
(reset-lir!)
(lir-compile-direct-call 'fn7 '(a b c d e f g) -64 '((a . -8) (b . -16) (c . -24) (d . -32) (e . -40) (f . -48) (g . -56)) #f)
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "fn7: loads arg 0 to %rdi"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%load) (eq? (cadr i) '%rdi))) insts)))
  (assert-true "fn7: loads arg 1 to %rsi"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%load) (eq? (cadr i) '%rsi))) insts)))
  (assert-true "fn7: loads arg 2 to %rdx"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%load) (eq? (cadr i) '%rdx))) insts)))
  (assert-true "fn7: loads arg 3 to %rcx"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%load) (eq? (cadr i) '%rcx))) insts)))
  (assert-true "fn7: loads arg 4 to %r8"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%load) (eq? (cadr i) '%r8))) insts)))
  (assert-true "fn7: loads arg 5 to %r9"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%load) (eq? (cadr i) '%r9))) insts))))

(display "=======================================================\n")
(display " Pass 124: All tests passed!\n")
(display "=======================================================\n")
