;;; =======================================================================
;;; ULisp SRFI 141 / R7RS-large Integer Division Test Suite
;;; Conforms to DSN-33 Architecture Specification & Issue #662
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

(write-string "=== Running ULisp SRFI 141 Integer Division Tests ===\n")

;;; Helper to check n = q * d + r
(define (verify-div-law name q r n d)
  (test (string-append name " (identity law n = q*d + r)") n (+ (* q d) r)))

;;; --- 1. Floor Division ---
(write-string "--- 1. Floor Division ---\n")
(test "floor-quotient (5, 2)" 2 (floor-quotient 5 2))
(test "floor-remainder (5, 2)" 1 (floor-remainder 5 2))
(test "floor-quotient (-5, 2)" -3 (floor-quotient -5 2))
(test "floor-remainder (-5, 2)" 1 (floor-remainder -5 2))
(test "floor-quotient (5, -2)" -3 (floor-quotient 5 -2))
(test "floor-remainder (5, -2)" -1 (floor-remainder 5 -2))
(test "floor-quotient (-5, -2)" 2 (floor-quotient -5 -2))
(test "floor-remainder (-5, -2)" -1 (floor-remainder -5 -2))

(call-with-values (lambda () (floor/ -5 2))
  (lambda (q r)
    (test "floor/ q" -3 q)
    (test "floor/ r" 1 r)
    (verify-div-law "floor/ -5 2" q r -5 2)))

;;; --- 2. Truncate Division ---
(write-string "--- 2. Truncate Division ---\n")
(test "truncate-quotient (5, 2)" 2 (truncate-quotient 5 2))
(test "truncate-remainder (5, 2)" 1 (truncate-remainder 5 2))
(test "truncate-quotient (-5, 2)" -2 (truncate-quotient -5 2))
(test "truncate-remainder (-5, 2)" -1 (truncate-remainder -5 2))
(test "truncate-quotient (5, -2)" -2 (truncate-quotient 5 -2))
(test "truncate-remainder (5, -2)" 1 (truncate-remainder 5 -2))
(test "truncate-quotient (-5, -2)" 2 (truncate-quotient -5 -2))
(test "truncate-remainder (-5, -2)" -1 (truncate-remainder -5 -2))

(call-with-values (lambda () (truncate/ -5 2))
  (lambda (q r)
    (test "truncate/ q" -2 q)
    (test "truncate/ r" -1 r)
    (verify-div-law "truncate/ -5 2" q r -5 2)))

;;; --- 3. Ceiling Division ---
(write-string "--- 3. Ceiling Division ---\n")
(test "ceiling-quotient (5, 2)" 3 (ceiling-quotient 5 2))
(test "ceiling-remainder (5, 2)" -1 (ceiling-remainder 5 2))
(test "ceiling-quotient (-5, 2)" -2 (ceiling-quotient -5 2))
(test "ceiling-remainder (-5, 2)" -1 (ceiling-remainder -5 2))
(test "ceiling-quotient (5, -2)" -2 (ceiling-quotient 5 -2))
(test "ceiling-remainder (5, -2)" 1 (ceiling-remainder 5 -2))
(test "ceiling-quotient (-5, -2)" 3 (ceiling-quotient -5 -2))
(test "ceiling-remainder (-5, -2)" 1 (ceiling-remainder -5 -2))

(call-with-values (lambda () (ceiling/ 5 2))
  (lambda (q r)
    (test "ceiling/ q" 3 q)
    (test "ceiling/ r" -1 r)
    (verify-div-law "ceiling/ 5 2" q r 5 2)))

;;; --- 4. Round Division ---
(write-string "--- 4. Round Division ---\n")
(test "round-quotient (5, 2) -> tie to even 2" 2 (round-quotient 5 2))
(test "round-remainder (5, 2)" 1 (round-remainder 5 2))
(test "round-quotient (7, 2) -> tie to even 4" 4 (round-quotient 7 2))
(test "round-remainder (7, 2)" -1 (round-remainder 7 2))
(test "round-quotient (-5, 2) -> tie to even -2" -2 (round-quotient -5 2))
(test "round-remainder (-5, 2)" -1 (round-remainder -5 2))
(test "round-quotient (-7, 2) -> tie to even -4" -4 (round-quotient -7 2))
(test "round-remainder (-7, 2)" 1 (round-remainder -7 2))

(call-with-values (lambda () (round/ 7 2))
  (lambda (q r)
    (test "round/ q" 4 q)
    (test "round/ r" -1 r)
    (verify-div-law "round/ 7 2" q r 7 2)))

;;; --- 5. Euclidean Division ---
(write-string "--- 5. Euclidean Division ---\n")
;; In Euclidean division, remainder r is ALWAYS non-negative: 0 <= r < |d|
(test "euclidean-quotient (5, 2)" 2 (euclidean-quotient 5 2))
(test "euclidean-remainder (5, 2)" 1 (euclidean-remainder 5 2))
(test "euclidean-quotient (-5, 2)" -3 (euclidean-quotient -5 2))
(test "euclidean-remainder (-5, 2)" 1 (euclidean-remainder -5 2))
(test "euclidean-quotient (5, -2)" -2 (euclidean-quotient 5 -2))
(test "euclidean-remainder (5, -2)" 1 (euclidean-remainder 5 -2))
(test "euclidean-quotient (-5, -2)" 3 (euclidean-quotient -5 -2))
(test "euclidean-remainder (-5, -2)" 1 (euclidean-remainder -5 -2))

(call-with-values (lambda () (euclidean/ -5 -2))
  (lambda (q r)
    (test "euclidean/ q" 3 q)
    (test "euclidean/ r" 1 r)
    (verify-div-law "euclidean/ -5 -2" q r -5 -2)))

;;; --- 6. Centered Division ---
(write-string "--- 6. Centered Division ---\n")
;; In Centered division, remainder r satisfies -|d|/2 <= r < |d|/2
;; For d = 2, |d|/2 = 1 => -1 <= r < 1.
;; For n = 5, d = 2: q = 3, r = -1 (since r=1 violates r < 1)
(test "centered-quotient (5, 2)" 3 (centered-quotient 5 2))
(test "centered-remainder (5, 2)" -1 (centered-remainder 5 2))
(test "centered-quotient (-5, 2)" -2 (centered-quotient -5 2))
(test "centered-remainder (-5, 2)" -1 (centered-remainder -5 2))
(test "centered-quotient (7, 3)" 2 (centered-quotient 7 3))
(test "centered-remainder (7, 3)" 1 (centered-remainder 7 3))
(test "centered-quotient (8, 3)" 3 (centered-quotient 8 3))
(test "centered-remainder (8, 3)" -1 (centered-remainder 8 3))

(call-with-values (lambda () (centered/ 8 3))
  (lambda (q r)
    (test "centered/ q" 3 q)
    (test "centered/ r" -1 r)
    (verify-div-law "centered/ 8 3" q r 8 3)))

(write-string "=== All SRFI 141 Division Tests Passed Successfully! ===\n")
