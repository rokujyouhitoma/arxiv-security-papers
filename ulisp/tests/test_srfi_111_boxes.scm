;;; =======================================================================
;;; ULisp SRFI 111 / R7RS-large Red Edition Boxes Test Suite
;;; Conforms to DSN-33 Architecture Specification & Issue #663
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

(write-string "=== Running ULisp SRFI 111 Boxes Tests ===\n")

;;; --- Test 1: box creation and predicate ---
(write-string "--- Test 1: box & box? ---\n")
(define b1 (box 100))
(test "box? returns #t for box" #t (box? b1))
(test "box? returns #f for number" #f (box? 100))
(test "box? returns #f for pair" #f (box? (cons 1 2)))
(test "box? returns #f for vector" #f (box? (vector 100)))
(test "box? returns #f for string" #f (box? "hello"))
(test "box? returns #f for boolean" #f (box? #t))
(test "box? returns #f for null" #f (box? '()))

;;; --- Test 2: unbox & set-box! ---
(write-string "--- Test 2: unbox & set-box! ---\n")
(test "unbox initial value" 100 (unbox b1))

(set-box! b1 250)
(test "unbox updated value" 250 (unbox b1))

;;; --- Test 3: Shared mutable state between closures ---
(write-string "--- Test 3: Shared mutable state across closures ---\n")
(define shared-counter (box 0))

(define (increment-counter!)
  (let ((cur (unbox shared-counter)))
    (set-box! shared-counter (+ cur 1))
    (+ cur 1)))

(define (get-counter)
  (unbox shared-counter))

(test "initial counter" 0 (get-counter))
(test "increment once" 1 (increment-counter!))
(test "increment twice" 2 (increment-counter!))
(test "read counter after increments" 2 (get-counter))

;;; --- Test 4: Nested boxes ---
(write-string "--- Test 4: Nested boxes ---\n")
(define inner (box "inner-data"))
(define outer (box inner))

(test "box? on outer" #t (box? outer))
(test "unbox outer returns box" #t (box? (unbox outer)))
(test "unbox nested" "inner-data" (unbox (unbox outer)))

(write-string "=== All SRFI 111 Boxes Tests Passed Successfully! ===\n")

