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
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%call-closure))) insts))))

;; Test 2: Tail direct call (%direct-jump label)
(reset-lir!)
(lir-compile-direct-call 'foo_label '(a) -16 '((%num-params . 1) (a . -8)) #t)
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "direct-call: emits %direct-jump for tail-call"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%direct-jump) (eq? (cadr i) 'foo_label))) insts))))

;; Test 3: Non-tail direct call (%direct-call label)
(reset-lir!)
(lir-compile-direct-call 'other_label '(a) -16 '((a . -8)) #f)
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "direct-call: emits %direct-call for non-tail call"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%direct-call) (eq? (cadr i) 'other_label))) insts))))

(display "=======================================================\n")
(display " Pass 124: All tests passed!\n")
(display "=======================================================\n")
