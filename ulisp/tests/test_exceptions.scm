;;; =======================================================================
;;; ULisp Exception Handling Unit Tests (R7RS Section 6.11 / Issue #531)
;;; =======================================================================

(test-begin "exceptions")

;; Test 1: Basic guard & raise
(test-equal "basic-guard-raise"
      'caught
      (guard (e ((= e 42) 'caught))
        (raise 42)))

;; Test 2: Normal return (no exception raised)
(test-equal "guard-normal-return"
      30
      (guard (e (else 'caught))
        (+ 10 20)))

;; Test 3: Fallthrough to else clause
(test-equal "guard-else-clause"
      'other
      (guard (e ((= e 1) 'one)
                ((= e 2) 'two)
                (else 'other))
        (raise 99)))

;; Test 4: Nested guards with re-raise
(test-equal "nested-guards-reraise"
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

(test-equal "deep-call-unwind"
      'handled-zero
      (guard (e ((eq? e 'zero-error) 'handled-zero))
        (call-deep-1 0)))

;; Test 6: Deep call normal execution
(test-equal "deep-call-normal"
      11
      (guard (e ((eq? e 'zero-error) 'handled-zero))
        (call-deep-1 10)))

;; Test 7: Error object predicate and accessors
(test-equal "error-object-basics"
      "something went wrong"
      (guard (e ((error-object? e)
                 (error-object-message e)))
        (error "something went wrong" 10 20)))

(test-equal "error-object-irritants"
      '(10 20)
      (guard (e ((error-object? e)
                 (error-object-irritants e)))
        (error "something went wrong" 10 20)))

;; Test 8: Guard with arrow syntax (=>)
(test-equal "guard-arrow-syntax"
      "arrow-success"
      (guard (e (((lambda (x) (if (error-object? x) (error-object-message x) #f)) e) => (lambda (msg) msg)))
        (error "arrow-success")))

;; Test 9: with-exception-handler
(test-equal "with-exception-handler"
      'caught-via-weh
      (with-exception-handler
        (lambda (e) 'caught-via-weh)
        (lambda () (raise 'err))))

;; Test 10: SRFI 64 test-error validation
(test-error "test-error-handling"
      error-object?
      (error "expected error"))

(test-end "exceptions")
