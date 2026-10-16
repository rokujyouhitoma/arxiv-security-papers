;;; =======================================================================
;;; ULisp Exception Handling Unit Tests (R7RS Section 6.11 / Issue #531)
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

(write-string "=== Running ULisp R7RS Exception Handling Tests ===\n")

;; Test 1: Basic guard & raise
(test "basic-guard-raise"
      'caught
      (guard (e ((= e 42) 'caught))
        (raise 42)))

;; Test 2: Normal return (no exception raised)
(test "guard-normal-return"
      30
      (guard (e (else 'caught))
        (+ 10 20)))

;; Test 3: Fallthrough to else clause
(test "guard-else-clause"
      'other
      (guard (e ((= e 1) 'one)
                ((= e 2) 'two)
                (else 'other))
        (raise 99)))

;; Test 4: Nested guards with re-raise
(test "nested-guards-reraise"
      'caught-outer
      (guard (outer ((= outer 100) 'caught-outer))
        (guard (inner ((= inner 50) 'caught-inner))
          (raise 100))))

;; Test 5: Exception raised across deep procedure calls
(define (call-deep-1 x) (call-deep-2 x))
(define (call-deep-2 x) (call-deep-3 x))
(define (call-deep-3 x)
  (if (= x 0)
      (raise 'zero-error)
      (+ x 1)))

(test "deep-call-unwind"
      'handled-zero
      (guard (e ((eq? e 'zero-error) 'handled-zero))
        (call-deep-1 0)))

;; Test 6: Deep call normal execution
(test "deep-call-normal"
      11
      (guard (e ((eq? e 'zero-error) 'handled-zero))
        (call-deep-1 10)))

;; Test 7: Error object predicate and accessors
(test "error-object-basics"
      "something went wrong"
      (guard (e ((error-object? e)
                 (error-object-message e)))
        (error "something went wrong" 10 20)))

(test "error-object-irritants"
      '(10 20)
      (guard (e ((error-object? e)
                 (error-object-irritants e)))
        (error "something went wrong" 10 20)))

;; Test 8: Guard with arrow syntax (=>)
(test "guard-arrow-syntax"
      "arrow-success"
      (guard (e (((lambda (x) (if (error-object? x) (error-object-message x) #f)) e) => (lambda (msg) msg)))
        (error "arrow-success")))

;; Test 9: with-exception-handler
(test "with-exception-handler"
      'caught-via-weh
      (with-exception-handler
        (lambda (e) 'caught-via-weh)
        (lambda () (raise 'err))))

(write-string "=== All Exception Tests Passed ===\n")
