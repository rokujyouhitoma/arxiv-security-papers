;;; =======================================================================
;;; ULisp Test Suite: R7RS §6.2.6 max and min Variadic Procedures
;;; Conforms to Issue #653
;;; =======================================================================

(define *test-failures* (vector 0))

(define (test-pass name)
  (write-string "  [PASS] ")
  (write-string name)
  (write-char #\newline)
  (flush-output-port))

(define (test-fail name expected actual)
  (vector-set! *test-failures* 0 (+ (vector-ref *test-failures* 0) 1))
  (write-string "  [FAIL] ")
  (write-string name)
  (write-string " (expected ")
  (write expected)
  (write-string ", got ")
  (write actual)
  (write-string ")")
  (write-char #\newline)
  (flush-output-port))

(define (test-equal? a b)
  (cond
    ((eqv? a b) #t)
    ((and (string? a) (string? b)) (string=? a b))
    ((and (pair? a) (pair? b))
     (and (test-equal? (car a) (car b))
          (test-equal? (cdr a) (cdr b))))
    (else #f)))

(define (assert-equal name actual expected)
  (if (test-equal? actual expected)
      (test-pass name)
      (test-fail name expected actual)))

(define (assert-true name cond)
  (if cond
      (test-pass name)
      (test-fail name #t #f)))

(define (assert-false name cond)
  (if (not cond)
      (test-pass name)
      (test-fail name #f #t)))

;;; -----------------------------------------------------------------------
;;; Group 1: Single Argument Calls (1-arity identity)
;;; -----------------------------------------------------------------------
(write-string "--- Group 1: Single Argument Calls ---")
(write-char #\newline)

(assert-equal "max single positive" (max 42) 42)
(assert-equal "max single negative" (max -10) -10)
(assert-equal "max single zero" (max 0) 0)

(assert-equal "min single positive" (min 42) 42)
(assert-equal "min single negative" (min -10) -10)
(assert-equal "min single zero" (min 0) 0)

;;; -----------------------------------------------------------------------
;;; Group 2: Binary Comparisons (2-arity)
;;; -----------------------------------------------------------------------
(write-string "--- Group 2: Binary Comparisons ---")
(write-char #\newline)

(assert-equal "max binary ascending" (max 10 20) 20)
(assert-equal "max binary descending" (max 20 10) 20)
(assert-equal "max binary identical" (max 5 5) 5)
(assert-equal "max binary negative" (max -10 -20) -10)
(assert-equal "max binary mixed signs" (max -5 5) 5)
(assert-equal "max binary with zero" (max 0 -7) 0)

(assert-equal "min binary ascending" (min 10 20) 10)
(assert-equal "min binary descending" (min 20 10) 10)
(assert-equal "min binary identical" (min 5 5) 5)
(assert-equal "min binary negative" (min -10 -20) -20)
(assert-equal "min binary mixed signs" (min -5 5) -5)
(assert-equal "min binary with zero" (min 0 7) 0)

;;; -----------------------------------------------------------------------
;;; Group 3: Variadic Calls (3 to 10+ Arguments)
;;; -----------------------------------------------------------------------
(write-string "--- Group 3: Variadic Calls ---")
(write-char #\newline)

;; max variadic
(assert-equal "max 3 args middle peak" (max 1 9 4) 9)
(assert-equal "max 4 args end peak" (max 2 5 3 8) 8)
(assert-equal "max 5 args first peak" (max 100 20 50 30 10) 100)
(assert-equal "max 10 args ascending" (max 1 2 3 4 5 6 7 8 9 10) 10)
(assert-equal "max 10 args descending" (max 10 9 8 7 6 5 4 3 2 1) 10)
(assert-equal "max 11 args random with duplicates" (max 3 1 4 1 5 9 2 6 5 3 5) 9)
(assert-equal "max all negative variadic" (max -50 -20 -80 -10 -30) -10)
(assert-equal "max mixed with multiple zeros" (max -5 0 0 -2 0) 0)

;; min variadic
(assert-equal "min 3 args middle trough" (min 9 1 4) 1)
(assert-equal "min 4 args end trough" (min 8 5 3 2) 2)
(assert-equal "min 5 args first trough" (min 10 20 50 30 100) 10)
(assert-equal "min 10 args ascending" (min 1 2 3 4 5 6 7 8 9 10) 1)
(assert-equal "min 10 args descending" (min 10 9 8 7 6 5 4 3 2 1) 1)
(assert-equal "min 11 args random with duplicates" (min 3 1 4 1 5 9 2 6 5 3 5) 1)
(assert-equal "min all negative variadic" (min -50 -20 -80 -10 -30) -80)
(assert-equal "min mixed with zeros" (min 5 0 -2 7 0) -2)

;;; -----------------------------------------------------------------------
;;; Group 4: Fixnum Extreme Boundary Values
;;; -----------------------------------------------------------------------
(write-string "--- Group 4: Fixnum Extreme Boundary Values ---")
(write-char #\newline)

(define *fix-max* 288230376151711743)
(define *fix-min* -288230376151711744)

(assert-equal "max with fixnum boundary values"
              (max *fix-min* 0 *fix-max* -100 100)
              *fix-max*)

(assert-equal "min with fixnum boundary values"
              (min *fix-max* 0 *fix-min* -100 100)
              *fix-min*)

(assert-equal "max fixnum max and min"
              (max *fix-max* *fix-min*)
              *fix-max*)

(assert-equal "min fixnum max and min"
              (min *fix-max* *fix-min*)
              *fix-min*)

;;; -----------------------------------------------------------------------
;;; Group 5: First-Class Procedures, Higher-Order Functions & Apply
;;; -----------------------------------------------------------------------
(write-string "--- Group 5: Higher-Order Functions & Apply ---")
(write-char #\newline)

;; apply with list
(assert-equal "apply max single" (apply max '(42)) 42)
(assert-equal "apply min single" (apply min '(-42)) -42)
(assert-equal "apply max list" (apply max '(1 5 3 9 2)) 9)
(assert-equal "apply min list" (apply min '(1 5 3 9 2)) 1)
(assert-equal "apply max with prefix args" (apply max 10 20 '(5 30 15)) 30)
(assert-equal "apply min with prefix args" (apply min 10 20 '(5 30 15)) 5)

;; map with max and min
(assert-equal "map max two lists"
              (map max '(1 10 5) '(8 2 9))
              '(8 10 9))

(assert-equal "map min two lists"
              (map min '(1 10 5) '(8 2 9))
              '(1 2 5))

;; Procedure binding
(define my-max max)
(define my-min min)
(assert-equal "bound max procedure" (my-max 3 7 2) 7)
(assert-equal "bound min procedure" (my-min 3 7 2) 2)

;;; -----------------------------------------------------------------------
;;; Summary & Exit
;;; -----------------------------------------------------------------------
(write-string "=== ULisp R7RS max/min Tests Completed: ")
(if (= (vector-ref *test-failures* 0) 0)
    (begin
      (write-string "ALL TESTS PASSED ===")
      (write-char #\newline)
      (flush-output-port)
      #t)
    (begin
      (write-string "FAILURES ENCOUNTERED ===")
      (write-char #\newline)
      (flush-output-port)
      (exit 1)))

