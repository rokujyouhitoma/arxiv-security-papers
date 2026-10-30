;;; =======================================================================
;;; ULisp Test Suite: R7RS case-lambda (Issue #609 / R7RS Section 4.2.9)
;;; Testing (scheme case-lambda) variable arity pattern matching syntax
;;; =======================================================================

(define *test-failures* (vector 0))

(define (assert-true val msg)
  (if (not val)
      (begin
        (vector-set! *test-failures* 0 (+ (vector-ref *test-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #f)
      (begin
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(define (test-equal? a b)
  (cond
    ((eqv? a b) #t)
    ((and (string? a) (string? b)) (string=? a b))
    ((and (pair? a) (pair? b))
     (and (test-equal? (car a) (car b))
          (test-equal? (cdr a) (cdr b))))
    (else #f)))

(define (assert-equal actual expected msg)
  (if (not (test-equal? actual expected))
      (begin
        (vector-set! *test-failures* 0 (+ (vector-ref *test-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #f)
      (begin
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(write-string "=== Running ULisp R7RS case-lambda Test Suite (Issue #609) ===\n")
(flush-output-port)

;; --- Group 1: Basic Zero- and Single-Arity ---
(let ((f0 (case-lambda (() 42))))
  (assert-equal (f0) 42 "Zero arity case-lambda returns 42"))

(let ((f1 (case-lambda ((x) (* x 2)))))
  (assert-equal (f1 21) 42 "Single arity case-lambda returns double"))

;; --- Group 2: Multiple Fixed Arities ---
(let ((multi (case-lambda
               (() 0)
               ((x) x)
               ((x y) (+ x y))
               ((x y z) (+ x (+ y z)))
               ((x y z w) (* (+ x y) (+ z w))))))
  (assert-equal (multi) 0 "Multiple arities: 0 args")
  (assert-equal (multi 10) 10 "Multiple arities: 1 arg")
  (assert-equal (multi 10 20) 30 "Multiple arities: 2 args")
  (assert-equal (multi 1 2 3) 6 "Multiple arities: 3 args")
  (assert-equal (multi 2 3 4 5) 45 "Multiple arities: 4 args"))

;; --- Group 3: Rest Arguments (Dotted Formals) ---
(let ((my-sum (case-lambda
                (() 0)
                ((x) x)
                ((x y) (+ x y))
                ((x y . rest)
                 (let loop ((acc (+ x y)) (r rest))
                   (if (null? r)
                       acc
                       (loop (+ acc (car r)) (cdr r))))))))
  (assert-equal (my-sum) 0 "Rest arity: 0 args")
  (assert-equal (my-sum 5) 5 "Rest arity: 1 arg")
  (assert-equal (my-sum 10 20) 30 "Rest arity: 2 args")
  (assert-equal (my-sum 1 2 3) 6 "Rest arity: 3 args (1 rest item)")
  (assert-equal (my-sum 1 2 3 4 5) 15 "Rest arity: 5 args (3 rest items)"))

;; --- Group 4: All-Rest Formals (Single Symbol) ---
(let ((collector (case-lambda (args args))))
  (assert-equal (collector) '() "All-rest formal: 0 args")
  (assert-equal (collector 1) '(1) "All-rest formal: 1 arg")
  (assert-equal (collector 10 20 30) '(10 20 30) "All-rest formal: 3 args"))

;; --- Group 5: Clause Dispatch Precedence (First-Match Wins) ---
(let ((precedence (case-lambda
                    ((x) 1)
                    ((x y) 2)
                    (rest 3))))
  (assert-equal (precedence 10) 1 "Precedence: 1 arg matches first clause")
  (assert-equal (precedence 10 20) 2 "Precedence: 2 args matches second clause")
  (assert-equal (precedence) 3 "Precedence: 0 args matches rest clause")
  (assert-equal (precedence 1 2 3 4) 3 "Precedence: 4 args matches rest clause"))

;; --- Group 6: Multi-expression Bodies in Clauses ---
(let ((multi-expr (case-lambda
                    ((x)
                     (let ((a (* x 2)))
                       (let ((b (+ a 1)))
                         b)))
                    ((x y)
                     (let ((sum (+ x y)))
                       (* sum sum))))))
  (assert-equal (multi-expr 5) 11 "Multi-expression body 1 arg")
  (assert-equal (multi-expr 3 4) 49 "Multi-expression body 2 args"))

;; --- Group 7: Arity Mismatch Error Signal ---
(let ((strict (case-lambda
                ((x) x)
                ((x y) (+ x y)))))
  (let ((caught (guard (ex (else 'error-caught))
                  (strict)
                  'no-error)))
    (assert-equal caught 'error-caught "Arity mismatch on 0 args signals error"))
  (let ((caught (guard (ex (else 'error-caught))
                  (strict 1 2 3)
                  'no-error)))
    (assert-equal caught 'error-caught "Arity mismatch on 3 args signals error")))

;; --- Final Summary ---
(if (= (vector-ref *test-failures* 0) 0)
    (begin
      (write-string "ALL CASE-LAMBDA TESTS PASSED!\n")
      (flush-output-port)
      #t)
    (begin
      (write-string "FAILURES DETECTED IN CASE-LAMBDA TESTS!\n")
      (flush-output-port)
      (error "case-lambda test failures detected")))
