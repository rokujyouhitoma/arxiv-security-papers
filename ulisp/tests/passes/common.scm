;;; =======================================================================
;;; ULisp Passes Common Test Harness
;;; Conforms to Issue #572 & Nanopass Architecture Quality Standard
;;; =======================================================================

(define *pass-tests-run* 0)
(define *pass-tests-passed* 0)
(define *pass-tests-failed* 0)

(define (reset-pass-test-counters!)
  (set! *pass-tests-run* 0)
  (set! *pass-tests-passed* 0)
  (set! *pass-tests-failed* 0))

(define (assert-true label cond)
  (set! *pass-tests-run* (+ *pass-tests-run* 1))
  (if cond
      (begin
        (set! *pass-tests-passed* (+ *pass-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (set! *pass-tests-failed* (+ *pass-tests-failed* 1))
        (display "  [FAIL] ") (display label) (newline)
        (error "Assertion failed: expected #t" label))))

(define (assert-equal label expected actual)
  (set! *pass-tests-run* (+ *pass-tests-run* 1))
  (if (equal? expected actual)
      (begin
        (set! *pass-tests-passed* (+ *pass-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (set! *pass-tests-failed* (+ *pass-tests-failed* 1))
        (display "  [FAIL] ") (display label)
        (display " -> Expected: ") (write expected)
        (display " but got: ") (write actual) (newline)
        (error "Assertion failed: values are not equal" label))))
