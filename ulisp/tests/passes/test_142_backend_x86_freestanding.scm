;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 142 (x86-64 Freestanding Runtime Generator)
;;; Conforms to Issue #572 & Nanopass Architecture Quality Standard
;;; =======================================================================

(define *pass-tests-passed* 0)
(define *pass-tests-failed* 0)

(define (assert-equal label expected actual)
  (if (equal? expected actual)
      (begin
        (set! *pass-tests-passed* (+ *pass-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (set! *pass-tests-failed* (+ *pass-tests-failed* 1))
        (display "  [FAIL] ") (display label)
        (display " -> Expected: ") (write expected)
        (display " but got: ") (write actual) (newline)
        (error "Assertion failed:" label))))

(define (assert-true label cond)
  (assert-equal label #t (if cond #t #f)))

(display "=======================================================") (newline)
(display " Starting Pass 142 (x86-64 Freestanding) Unit Test Suite") (newline)
(display "=======================================================") (newline)

;; Test existence and callable nature of freestanding emission procedures
(assert-true "emit-freestanding-runtime is procedure" (procedure? emit-freestanding-runtime))

(display "=======================================================") (newline)
(display " Pass 142: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)

