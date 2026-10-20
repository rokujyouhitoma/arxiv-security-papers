;;; =======================================================================
;;; Unit Test: Pass 126 (LIR Structured Control Flow)
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
(display " Starting Pass 126 (LIR Structured Control Flow) Unit Tests\n")
(display "=======================================================\n")

;; Test 1: lir-compile-if emits conditional branches and labels
(reset-lir!)
(lir-compile-if '#t 10 '(20) -16 '() #f)
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "if: emits %jump-if-false conditional branch"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%jump-if-false))) insts)))
  (assert-true "if: emits %block markers for branches"
               (>= (length (filter (lambda (i) (and (pair? i) (eq? (car i) '%block))) insts)) 2)))

;; Test 2: lir-compile-let binds variables and executes body
(reset-lir!)
(lir-compile-let '((x 42)) 'x -16 '() #f)
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "let: compiles variable binding with stack store"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%store) (equal? (caddr i) -16))) insts))))

;; Test 3: lir-compile-begin sequences multiple expressions
(reset-lir!)
(lir-compile-begin '(1 2 3) -16 '() #f)
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "begin: compiles sequence and loads constants"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%mov) (equal? (caddr i) 12))) insts))))

(display "=======================================================\n")
(display " Pass 126: All tests passed!\n")
(display "=======================================================\n")
