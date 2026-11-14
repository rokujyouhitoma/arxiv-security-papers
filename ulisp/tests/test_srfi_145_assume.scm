;;; =======================================================================
;;; ULisp SRFI 145 Assumptions (assume / assert) Test Suite
;;; Conforms to DSN-33 Architecture Specification & Issue #664
;;; =======================================================================

(define (test name expected actual)
  (if (equal? expected actual)
      (begin
        (write-string "  [PASS] ")
        (write-string name)
        (write-char #\newline)
        (flush-output-port)
        #t)
      (begin
        (write-string "  [FAIL] ")
        (write-string name)
        (write-string " - Expected: ")
        (display expected)
        (write-string ", Actual: ")
        (display actual)
        (write-char #\newline)
        (flush-output-port)
        (exit 1))))


;;; --- Test 1: assume on satisfied conditions ---
(write-string "--- Test 1: assume satisfied conditions ---\n")
(define v1 (assume (> 10 5)))
(test "assume returns condition value when true" #t v1)

(define v2 (assume (+ 20 30) "should not trigger"))
(test "assume returns evaluated expression value" 50 v2)

(define (safe-div a b)
  (assume (not (= b 0)) "divisor cannot be zero" b)
  (quotient a b))

(test "safe-div with valid arguments" 5 (safe-div 10 2))

;;; --- Test 2: assert compatibility syntax ---
(write-string "--- Test 2: assert syntax ---\n")
(define v3 (assert (< 3 7)))
(test "assert returns true on valid condition" #t v3)

(define v4 (assert (* 6 7)))
(test "assert returns expression value" 42 v4)

;;; --- Test 3: Single evaluation of expression (no duplicate side-effects) ---
(write-string "--- Test 3: Side-effect single evaluation ---\n")
(define eval-count-box (box 0))
(define (side-effecting-pred)
  (set-box! eval-count-box (+ (unbox eval-count-box) 1))
  #t)

(assume (side-effecting-pred) "predicate failed")
(test "assume evaluated condition exactly once" 1 (unbox eval-count-box))

;;; --- Test 4: Exception handling on violated assumption ---
(write-string "--- Test 4: Exception on violated assumption ---\n")
(define caught-error-box (box #f))
(guard (exc (else (set-box! caught-error-box #t)))
  (assume (= 1 2) "1 should equal 2"))

(test "assume raised exception on false condition" #t (unbox caught-error-box))

(define caught-assert-error-box (box #f))
(guard (exc (else (set-box! caught-assert-error-box #t)))
  (assert #f "assertion failed message"))

(test "assert raised exception on false condition" #t (unbox caught-assert-error-box))

