;;; =======================================================================
;;; Unit Test: Pass 127 (LIR Runtime Services & Multiple Values)
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
(display " Starting Pass 127 (LIR Runtime Services & Multiple Values) Unit Tests\n")
(display "=======================================================\n")

;; Test 1: lir-compile-values generates multi-value storage
(reset-lir!)
(lir-compile-values '(1 2) -24 '())
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "values: sets values count to 2"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%set-values-count) (equal? (cadr i) 2))) insts)))
  (assert-true "values: stores to values buffer"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%store-values-buf))) insts))))

;; Test 2: lir-compile-call-with-values lowers consumer and producer
(reset-lir!)
(lir-compile-call-with-values 'prod 'cons -32 '((prod . -8) (cons . -16)) #f)
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "call-with-values: emits %dispatch-consumer"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%dispatch-consumer))) insts))))

;; Test 3: lir-compile-with-handler sets up and tears down exception frame
(reset-lir!)
(lir-compile-with-handler 'h 'body -32 '((h . -8) (body . -16)) #f)
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "with-handler: emits %push-handler"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%push-handler))) insts)))
  (assert-true "with-handler: emits %pop-handler"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%pop-handler))) insts))))

;; Test 4: lir-compile-raw-call-cc captures continuation
(reset-lir!)
(lir-compile-raw-call-cc 'proc -32 '((proc . -8)) #f)
(let ((insts (reverse (car *lir-instructions*))))
  (assert-true "raw-call-cc: emits %capture-cc"
               (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%capture-cc))) insts))))

(display "=======================================================\n")
(display " Pass 127: All tests passed!\n")
(display "=======================================================\n")
