;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 131 (GC Safepoint & Stackmap Bitmaps)
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
(display " Starting Pass 131 (LIR Safepoint & Stackmap) Unit Test Suite") (newline)
(display "=======================================================") (newline)

;; 1. power-of-2 helper
(assert-equal "power-of-2 0" 1 (power-of-2 0))
(assert-equal "power-of-2 1" 2 (power-of-2 1))
(assert-equal "power-of-2 3" 8 (power-of-2 3))
(assert-equal "power-of-2 8" 256 (power-of-2 8))

;; 2. safepoint label generator & reset
(reset-safepoints!)
(let ((lbl1 (new-safepoint-label!))
      (lbl2 (new-safepoint-label!)))
  (assert-equal "first safepoint label" "__safepoint_1" lbl1)
  (assert-equal "second safepoint label" "__safepoint_2" lbl2)
  (record-safepoint! lbl1 32 3)
  (assert-true "safepoints recorded" (pair? (car *lir-safepoints*))))

;; 3. compute-stackmap-bitmap for empty env
(let ((bm (compute-stackmap-bitmap 32 -16 '() '())))
  (assert-true "bitmap is an integer" (integer? bm))
  (assert-true "bitmap is non-negative" (>= bm 0)))

(display "=======================================================") (newline)
(display " Pass 131: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
