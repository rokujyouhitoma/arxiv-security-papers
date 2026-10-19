;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 132 (Braun SSA & Block Arguments Engine)
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
(display " Starting Pass 132 (Braun SSA Engine) Unit Test Suite") (newline)
(display "=======================================================") (newline)

;; 1. CFG creation
(let ((cfg (make-braun-cfg)))
  (assert-true "cfg is list" (pair? cfg))
  (assert-equal "initial order empty" '() (braun-cfg-ref cfg 'order)))

;; 2. Block creation and ordering
(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'entry)
  (braun-new-block! cfg 'body)
  (braun-new-block! cfg 'exit)
  (assert-equal "block order preserved" '(entry body exit) (braun-cfg-ref cfg 'order))
  (assert-equal "current block is exit" 'exit (braun-cfg-ref cfg 'current-block)))

;; 3. Edge creation and predecessor tracking
(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'b0)
  (braun-new-block! cfg 'b1)
  (braun-add-edge! cfg 'b0 'b1)
  (assert-equal "preds of b1 include b0" '(b0) (braun-get-preds cfg 'b1)))

;; 4. Local value definition and read
(let ((cfg (make-braun-cfg)))
  (braun-new-block! cfg 'b0)
  (braun-write-variable! cfg 'x 'b0 '%v1)
  (assert-equal "read defined var" '%v1 (braun-read-variable cfg 'x 'b0)))


(display "=======================================================") (newline)
(display " Pass 132: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
