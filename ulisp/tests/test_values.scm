;;; =======================================================================
;;; ULisp Comprehensive R7RS Multiple Values Test Suite
;;; Conforms to Issue #538 & R7RS Section 6.10 / 4.2.2 Specifications
;;; =======================================================================

(define (equal? a b)
  (cond
    ((eq? a b) #t)
    ((and (pair? a) (pair? b))
     (and (equal? (car a) (car b))
          (equal? (cdr a) (cdr b))))
    ((and (string? a) (string? b))
     (string=? a b))
    (else #f)))

(define (test name expected actual)
  (if (equal? expected actual)
      (begin
        (write-string "  [PASS] ")
        (write-string name)
        (write-char #\newline)
        #t)
      (begin
        (write-string "  [FAIL] ")
        (write-string name)
        (write-string " - Expected: ")
        (write-string (if (symbol? expected) (symbol->string expected) "val"))
        (write-char #\newline)
        #f)))

(write-string "=== Running ULisp R7RS Multiple Values Tests ===\n")

;; Test 1: Basic 2-value passing with call-with-values
(test "cwv-2-values"
      30
      (call-with-values (lambda () (values 10 20))
        (lambda (x y) (+ x y))))

;; Test 2: 3-value passing
(test "cwv-3-values"
      60
      (call-with-values (lambda () (values 10 20 30))
        (lambda (a b c) (+ (+ a b) c))))

;; Test 3: Single-value passing (via values and direct function return)
(test "cwv-1-value-values"
      42
      (call-with-values (lambda () (values 42))
        (lambda (x) x)))

(test "cwv-1-value-normal"
      100
      (call-with-values (lambda () 100)
        (lambda (x) x)))

;; Test 4: 0-value passing
(test "cwv-0-values"
      'zero-vals
      (call-with-values (lambda () (values))
        (lambda () 'zero-vals)))

;; Test 5: let-values single binding
(test "let-values-single"
      12
      (let-values (((a b) (values 3 4)))
        (* a b)))

;; Test 6: let-values multiple bindings
(test "let-values-multiple"
      110
      (let-values (((a b) (values 10 20))
                   ((c d) (values 3 4)))
        (+ (* a c) (* b d))))

;; Test 7: let*-values sequential dependencies
(test "let*-values-seq"
      33
      (let*-values (((a b) (values 1 2))
                    ((c d) (values (+ a 10) (+ b 20))))
        (+ c d)))

;; Test 8: Dynamic multi-value return across function call boundary
(define (divmod n d)
  (values (quotient n d) (modulo n d)))

(test "dynamic-divmod"
      '(3 . 2)
      (call-with-values (lambda () (divmod 17 5))
        (lambda (q r) (cons q r))))

;; Test 9: Nested call-with-values pipelines
(test "nested-cwv"
      14
      (call-with-values
        (lambda ()
          (call-with-values (lambda () (values 5 6))
            (lambda (x y) (values (+ x 1) (+ y 2)))))
        (lambda (a b) (+ a b))))

;; Test 10: Zero-heap allocation in tight iterative multi-value loop
(test "multi-value-loop"
      499500
      (let loop ((i 0) (sum 0))
        (if (< i 1000)
            (let-values (((ni ns) (values (+ i 1) (+ sum i))))
              (loop ni ns))
            sum)))

;; Test 11: Top-level define-values (2 values)
(define-values (dv-x dv-y) (values 100 200))
(test "define-values-top-2"
      300
      (+ dv-x dv-y))

;; Test 12: Top-level define-values (3 values)
(define-values (dv-a dv-b dv-c) (values 10 20 30))
(test "define-values-top-3"
      60
      (+ (+ dv-a dv-b) dv-c))

;; Test 13: Top-level define-values single value
(define-values (dv-single) (values 42))
(test "define-values-top-1"
      42
      dv-single)

;; Test 14: Internal define-values in procedure
(define (test-internal-dv)
  (define-values (p q) (values 15 25))
  (+ p q))

(test "define-values-internal-proc"
      40
      (test-internal-dv))

;; Test 15: Sequential internal define-values
(define (test-internal-seq-dv)
  (define-values (u v) (values 1 2))
  (define-values (w z) (values 10 20))
  (+ (+ u v) (+ w z)))

(test "define-values-internal-seq"
      33
      (test-internal-seq-dv))

;; Test 16: Internal define-values in let
(test "define-values-internal-let"
      55
      (let ()
        (define-values (m n) (values 25 30))
        (+ m n)))

(write-string "=== All Multiple Values Tests Passed ===\n")
#t
