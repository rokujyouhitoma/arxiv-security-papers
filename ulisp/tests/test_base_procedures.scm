;;; =======================================================================
;;; ULisp Test Suite: R7RS (scheme base) Core Procedures (Issue #610)
;;; Testing: string, multi-argument map / for-each, apply,
;;;          floor/, floor-quotient, floor-remainder,
;;;          truncate/, truncate-quotient, truncate-remainder,
;;;          modulo (floor division), exact-integer-sqrt
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

(define (add a b) (+ a b))
(define (sum4 a b c d) (+ (+ a b) (+ c d)))
(define (sum3 a b c) (+ (+ a b) c))

(write-string "=== Running ULisp R7RS (scheme base) Core Procedures Test Suite (Issue #610) ===")
(write-char #\newline)
(flush-output-port)

;; =======================================================================
;; Group 1: string constructor (R7RS §6.7)
;; =======================================================================
(write-string "--- Group 1: string constructor ---")
(write-char #\newline)
(flush-output-port)

(assert-equal "string 0 args" (string) "")
(assert-equal "string 1 arg" (string #\a) "a")
(assert-equal "string 3 args" (string #\a #\b #\c) "abc")
(assert-equal "string 5 args" (string #\H #\e #\l #\l #\o) "Hello")

;; First-class / apply invocation
(assert-equal "apply string" (apply string '(#\w #\o #\r #\l #\d)) "world")

;; =======================================================================
;; Group 2: apply procedure (R7RS §6.10)
;; =======================================================================
(write-string "--- Group 2: apply procedure ---")
(write-char #\newline)
(flush-output-port)

(assert-equal "apply 2 args" (apply sum4 '(1 2 3 4)) 10)
(assert-equal "apply 3 args" (apply add 10 '(20)) 30)
(assert-equal "apply 4 args" (apply sum4 1 2 '(3 4)) 10)
(assert-equal "apply list" (apply list 1 2 '(3 4)) '(1 2 3 4))

;; =======================================================================
;; Group 3: map & for-each with multiple lists (R7RS §6.10)
;; =======================================================================
(write-string "--- Group 3: map & for-each (multi-list) ---")
(write-char #\newline)
(flush-output-port)

;; 1-list map
(assert-equal "map 1-list" (map (lambda (x) (* x 2)) '(1 2 3)) '(2 4 6))

;; 2-list map
(assert-equal "map 2-lists" (map add '(1 2 3) '(10 20 30)) '(11 22 33))

;; 3-list map
(assert-equal "map 3-lists"
              (map list '(1 2) '(a b) '(x y))
              '((1 a x) (2 b y)))

;; Shortest list termination
(assert-equal "map shortest list 1" (map add '(1 2 3) '(10 20)) '(11 22))
(assert-equal "map shortest list 2" (map add '(1 2) '(10 20 30)) '(11 22))
(assert-equal "map empty list" (map add '() '(1 2 3)) '())

;; 1-list for-each
(let ((acc (vector 0)))
  (for-each (lambda (x) (vector-set! acc 0 (+ (vector-ref acc 0) x))) '(1 2 3 4))
  (assert-equal "for-each 1-list" (vector-ref acc 0) 10))

;; 2-list for-each
(let ((acc (vector 0)))
  (for-each (lambda (x y) (vector-set! acc 0 (+ (vector-ref acc 0) (* x y)))) '(1 2 3) '(10 20 30))
  (assert-equal "for-each 2-lists" (vector-ref acc 0) 140))

;; 3-list for-each with early termination
(let ((acc (vector '())))
  (for-each (lambda (a b c)
              (vector-set! acc 0 (cons (list a b c) (vector-ref acc 0))))
            '(1 2 3) '(a b) '(x y z))
  (assert-equal "for-each 3-lists early exit" (reverse (vector-ref acc 0)) '((1 a x) (2 b y))))

;; =======================================================================
;; Group 4: Truncated Division (truncate/, truncate-quotient, truncate-remainder)
;; =======================================================================
(write-string "--- Group 4: Truncated Division ---")
(write-char #\newline)
(flush-output-port)

(assert-equal "truncate-quotient positive/positive" (truncate-quotient 13 4) 3)
(assert-equal "truncate-remainder positive/positive" (truncate-remainder 13 4) 1)

(assert-equal "truncate-quotient negative/positive" (truncate-quotient -13 4) -3)
(assert-equal "truncate-remainder negative/positive" (truncate-remainder -13 4) -1)

(assert-equal "truncate-quotient positive/negative" (truncate-quotient 13 -4) -3)
(assert-equal "truncate-remainder positive/negative" (truncate-remainder 13 -4) 1)

(assert-equal "truncate-quotient negative/negative" (truncate-quotient -13 -4) 3)
(assert-equal "truncate-remainder negative/negative" (truncate-remainder -13 -4) -1)

;; truncate/ multiple values
(let-values (((q r) (truncate/ 13 4)))
  (assert-equal "truncate/ 13 4 q" q 3)
  (assert-equal "truncate/ 13 4 r" r 1))

(let-values (((q r) (truncate/ -13 4)))
  (assert-equal "truncate/ -13 4 q" q -3)
  (assert-equal "truncate/ -13 4 r" r -1))

(let-values (((q r) (truncate/ 13 -4)))
  (assert-equal "truncate/ 13 -4 q" q -3)
  (assert-equal "truncate/ 13 -4 r" r 1))

(let-values (((q r) (truncate/ -13 -4)))
  (assert-equal "truncate/ -13 -4 q" q 3)
  (assert-equal "truncate/ -13 -4 r" r -1))

;; =======================================================================
;; Group 5: Floored Division (floor/, floor-quotient, floor-remainder, modulo)
;; =======================================================================
(write-string "--- Group 5: Floored Division & modulo ---")
(write-char #\newline)
(flush-output-port)

(assert-equal "floor-quotient positive/positive" (floor-quotient 13 4) 3)
(assert-equal "floor-remainder positive/positive" (floor-remainder 13 4) 1)

(assert-equal "floor-quotient negative/positive" (floor-quotient -13 4) -4)
(assert-equal "floor-remainder negative/positive" (floor-remainder -13 4) 3)

(assert-equal "floor-quotient positive/negative" (floor-quotient 13 -4) -4)
(assert-equal "floor-remainder positive/negative" (floor-remainder 13 -4) -3)

(assert-equal "floor-quotient negative/negative" (floor-quotient -13 -4) 3)
(assert-equal "floor-remainder negative/negative" (floor-remainder -13 -4) -1)

;; modulo equivalence to floor-remainder
(assert-equal "modulo 13 4" (modulo 13 4) 1)
(assert-equal "modulo -13 4" (modulo -13 4) 3)
(assert-equal "modulo 13 -4" (modulo 13 -4) -3)
(assert-equal "modulo -13 -4" (modulo -13 -4) -1)

;; Exact multiples
(assert-equal "floor-quotient exact 12 4" (floor-quotient 12 4) 3)
(assert-equal "floor-remainder exact 12 4" (floor-remainder 12 4) 0)
(assert-equal "floor-quotient exact -12 4" (floor-quotient -12 4) -3)
(assert-equal "floor-remainder exact -12 4" (floor-remainder -12 4) 0)

;; floor/ multiple values
(let-values (((q r) (floor/ 13 4)))
  (assert-equal "floor/ 13 4 q" q 3)
  (assert-equal "floor/ 13 4 r" r 1))

(let-values (((q r) (floor/ -13 4)))
  (assert-equal "floor/ -13 4 q" q -4)
  (assert-equal "floor/ -13 4 r" r 3))

(let-values (((q r) (floor/ 13 -4)))
  (assert-equal "floor/ 13 -4 q" q -4)
  (assert-equal "floor/ 13 -4 r" r -3))

(let-values (((q r) (floor/ -13 -4)))
  (assert-equal "floor/ -13 -4 q" q 3)
  (assert-equal "floor/ -13 -4 r" r -1))

;; =======================================================================
;; Group 6: exact-integer-sqrt (R7RS §6.2.6)
;; =======================================================================
(write-string "--- Group 6: exact-integer-sqrt ---")
(write-char #\newline)
(flush-output-port)

(let-values (((s r) (exact-integer-sqrt 0)))
  (assert-equal "exact-integer-sqrt 0 s" s 0)
  (assert-equal "exact-integer-sqrt 0 r" r 0))

(let-values (((s r) (exact-integer-sqrt 1)))
  (assert-equal "exact-integer-sqrt 1 s" s 1)
  (assert-equal "exact-integer-sqrt 1 r" r 0))

(let-values (((s r) (exact-integer-sqrt 2)))
  (assert-equal "exact-integer-sqrt 2 s" s 1)
  (assert-equal "exact-integer-sqrt 2 r" r 1))

(let-values (((s r) (exact-integer-sqrt 3)))
  (assert-equal "exact-integer-sqrt 3 s" s 1)
  (assert-equal "exact-integer-sqrt 3 r" r 2))

(let-values (((s r) (exact-integer-sqrt 4)))
  (assert-equal "exact-integer-sqrt 4 s" s 2)
  (assert-equal "exact-integer-sqrt 4 r" r 0))

(let-values (((s r) (exact-integer-sqrt 5)))
  (assert-equal "exact-integer-sqrt 5 s" s 2)
  (assert-equal "exact-integer-sqrt 5 r" r 1))

(let-values (((s r) (exact-integer-sqrt 8)))
  (assert-equal "exact-integer-sqrt 8 s" s 2)
  (assert-equal "exact-integer-sqrt 8 r" r 4))

(let-values (((s r) (exact-integer-sqrt 9)))
  (assert-equal "exact-integer-sqrt 9 s" s 3)
  (assert-equal "exact-integer-sqrt 9 r" r 0))

(let-values (((s r) (exact-integer-sqrt 15)))
  (assert-equal "exact-integer-sqrt 15 s" s 3)
  (assert-equal "exact-integer-sqrt 15 r" r 6))

(let-values (((s r) (exact-integer-sqrt 16)))
  (assert-equal "exact-integer-sqrt 16 s" s 4)
  (assert-equal "exact-integer-sqrt 16 r" r 0))

(let-values (((s r) (exact-integer-sqrt 100)))
  (assert-equal "exact-integer-sqrt 100 s" s 10)
  (assert-equal "exact-integer-sqrt 100 r" r 0))

(let-values (((s r) (exact-integer-sqrt 105)))
  (assert-equal "exact-integer-sqrt 105 s" s 10)
  (assert-equal "exact-integer-sqrt 105 r" r 5))

(let-values (((s r) (exact-integer-sqrt 1000000)))
  (assert-equal "exact-integer-sqrt 1000000 s" s 1000)
  (assert-equal "exact-integer-sqrt 1000000 r" r 0))

(let-values (((s r) (exact-integer-sqrt 1000001)))
  (assert-equal "exact-integer-sqrt 1000001 s" s 1000)
  (assert-equal "exact-integer-sqrt 1000001 r" r 1))

;; Error on negative argument
(let ((caught (guard (ex (else 'negative-error-caught))
                (exact-integer-sqrt -1)
                'no-error)))
  (assert-equal "exact-integer-sqrt negative error" caught 'negative-error-caught))

;; =======================================================================
;; Summary
;; =======================================================================
(write-char #\newline)
(if (= (vector-ref *test-failures* 0) 0)
    (begin
      (write-string "ALL R7RS BASE CORE PROCEDURE TESTS PASSED!\n")
      (flush-output-port)
      0)
    (begin
      (write-string "FAILURES DETECTED IN R7RS BASE CORE PROCEDURE TESTS!\n")
      (flush-output-port)
      (error "R7RS base core procedure test failures detected")))
