;;; =======================================================================
;;; ULisp Test Suite: R7RS §4.2.2 letrec* Evaluation Order & Semantics
;;; Conforms to Issue #650
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
;;; Group 1: Basic Binding and Empty Bindings
;;; -----------------------------------------------------------------------
(write-string "--- Group 1: Basic Binding and Empty Bindings ---")
(write-char #\newline)

(assert-equal "letrec* empty bindings"
              (letrec* () 42)
              42)

(assert-equal "letrec* single binding"
              (letrec* ((x 100)) x)
              100)

(assert-equal "letrec* multi-expression body"
              (letrec* ((x 10))
                (+ x 1)
                (+ x 2)
                (+ x 5))
              15)

;;; -----------------------------------------------------------------------
;;; Group 2: Left-to-Right Evaluation Order & Forward Values
;;; -----------------------------------------------------------------------
(write-string "--- Group 2: Left-to-Right Evaluation Order & Forward Values ---")
(write-char #\newline)

(assert-equal "letrec* sequential dependency"
              (letrec* ((a 10)
                        (b (+ a 5))
                        (c (* b 2)))
                c)
              30)

(assert-equal "letrec* list construction from previous inits"
              (letrec* ((x 1)
                        (y (+ x 1))
                        (z (+ y 1)))
                (list x y z))
              '(1 2 3))

;;; -----------------------------------------------------------------------
;;; Group 3: Mutual Recursion between Procedures
;;; -----------------------------------------------------------------------
(write-string "--- Group 3: Mutual Recursion between Procedures ---")
(write-char #\newline)

(assert-true "letrec* mutual recursion even? and odd?"
             (letrec* ((even? (lambda (n) (if (= n 0) #t (odd? (- n 1)))))
                       (odd?  (lambda (n) (if (= n 0) #f (even? (- n 1))))))
               (and (even? 0)
                    (odd? 1)
                    (even? 10)
                    (odd? 11)
                    (not (even? 13))
                    (not (odd? 14)))))

(assert-equal "letrec* mutual recursive arithmetic"
              (letrec* ((f (lambda (n) (if (= n 0) 1 (+ (g (- n 1)) n))))
                        (g (lambda (n) (if (= n 0) 0 (+ (f (- n 1)) 2)))))
                (f 5))
              13)

;;; -----------------------------------------------------------------------
;;; Group 4: Mixing Procedures and Non-Procedure Variables
;;; -----------------------------------------------------------------------
(write-string "--- Group 4: Mixing Procedures and Non-Procedure Variables ---")
(write-char #\newline)

;; Earlier variable used inside procedure
(assert-equal "letrec* proc using earlier variable"
              (letrec* ((base 100)
                        (add-base (lambda (n) (+ base n))))
                (add-base 42))
              142)

;; Earlier procedure called in subsequent init expression
(assert-equal "letrec* subsequent init calling earlier procedure"
              (letrec* ((scale (lambda (x) (* x 10)))
                        (v1 5)
                        (v2 (scale v1))
                        (v3 (+ v2 3)))
                v3)
              53)

;; Interleaved procedures and variables
(assert-equal "letrec* interleaved procedures and variables"
              (letrec* ((init-val 10)
                        (inc (lambda (x) (+ x 1)))
                        (val1 (inc init-val))
                        (dbl (lambda (x) (* x 2)))
                        (val2 (dbl val1)))
                val2)
              22)

;;; -----------------------------------------------------------------------
;;; Group 5: Forward References in Procedure Bodies
;;; -----------------------------------------------------------------------
(write-string "--- Group 5: Forward References in Procedure Bodies ---")
(write-char #\newline)

;; Procedure captures subsequent variable (valid if called after assignment)
(assert-equal "letrec* proc capturing subsequent variable"
              (letrec* ((f (lambda () x))
                        (x 42))
                (f))
              42)

;; Intertwined procedure calls capturing variables
(assert-equal "letrec* intertwined procs and vars"
              (letrec* ((get-b (lambda () b))
                        (a 10)
                        (b 20)
                        (sum (lambda () (+ a (get-b)))))
                (sum))
              30)

;;; -----------------------------------------------------------------------
;;; Group 6: Nested letrec* Expressions
;;; -----------------------------------------------------------------------
(write-string "--- Group 6: Nested letrec* Expressions ---")
(write-char #\newline)

(assert-equal "nested letrec*"
              (letrec* ((x 5)
                        (y (letrec* ((a (+ x 1))
                                     (b (* a 2)))
                             b)))
                (+ x y))
              17)

;;; -----------------------------------------------------------------------
;;; Summary & Exit
;;; -----------------------------------------------------------------------
(write-string "=== ULisp R7RS letrec* Tests Completed: ")
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

