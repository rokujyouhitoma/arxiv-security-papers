;;; =======================================================================
;;; Unit Test: Pass 125 (LIR Continuation & Loop Fusion Lowering)
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
(display " Starting Pass 125 (LIR Continuation & Loop Fusion Lowering) Unit Tests\n")
(display "=======================================================\n")

;; Test 1: cont-body-has-external-call? and expr-references-var?
(assert-true "expr-references-var?: finds variable in expression"
             (expr-references-var? '(+ x 1) 'x))
(assert-true "expr-references-var?: returns #f if variable is absent"
             (not (expr-references-var? '(+ y 1) 'x)))

(assert-true "cont-body-has-external-call?: identifies external call"
             (cont-body-has-external-call? '(%direct-call f 1 2) 'loop_k))
(assert-true "cont-body-has-external-call?: returns #f for internal continuation call"
             (not (cont-body-has-external-call? '(%cont-call loop_k 1 2) 'loop_k)))

;; Test 2: lir-compile-cont-call emits direct branch %jump
(reset-lir!)
(let ((test-env '((k_cont . (%cont-target L_k_target ((x . %rbx))))
                  (val . -8))))
  (lir-compile-cont-call 'k_cont '(val) -16 test-env))
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "cont-call: emits %jump to continuation target label"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%jump) (eq? (cadr i) 'L_k_target))) insts))))

(display "=======================================================\n")
(display " Pass 125: All tests passed!\n")
(display "=======================================================\n")
