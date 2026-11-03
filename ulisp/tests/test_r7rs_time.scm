;;; =======================================================================
;;; ULisp R7RS §6.14 (scheme time) Time Procedures Test Suite
;;; Conforms to DSN-33 Architecture Specification & Issue #661
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

(write-string "=== Running ULisp R7RS (scheme time) Tests ===\n")

;;; --- Test 1: current-second sanity check ---
(write-string "--- Test 1: current-second ---\n")
(define sec (current-second))
(test "current-second is positive integer" #t (> sec 1700000000))

;;; --- Test 2: jiffies-per-second ---
(write-string "--- Test 2: jiffies-per-second ---\n")
(define jps (jiffies-per-second))
(test "jiffies-per-second is 1000000" 1000000 jps)

;;; --- Test 3: current-jiffy monotonicity & elapsed time ---
(write-string "--- Test 3: current-jiffy monotonicity ---\n")
(define j1 (current-jiffy))
;; Small busy loop to consume time
(let loop ((i 0) (acc 0))
  (if (< i 500000)
      (loop (+ i 1) (+ acc 1))
      acc))
(define j2 (current-jiffy))

(test "current-jiffy is monotonically increasing (j2 >= j1)" #t (>= j2 j1))
(write-string "  Measured jiffies elapsed: ")
(display (- j2 j1))
(write-string "\n")

(write-string "=== All (scheme time) Tests Passed Successfully! ===\n")

