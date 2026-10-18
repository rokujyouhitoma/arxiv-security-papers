;;; =======================================================================
;;; ULisp Test Suite: R7RS Delayed Evaluation (Issue #550 / R7RS Section 4.2.5)
;;; Testing delay, force, delay-force, make-promise, promise?
;;; =======================================================================

(define *test-failures* (vector 0))

(define (print-msg s)
  (write-string s)
  (write-char #\newline)
  (flush-output-port))

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

;; -----------------------------------------------------------------------
;; Test 1: promise? predicate
;; -----------------------------------------------------------------------
(print-msg "=== Test 1: promise? Predicate ===")

(assert-true (promise? (delay 42)) "delay produces a promise")
(assert-true (promise? (delay-force (delay 42))) "delay-force produces a promise")
(assert-true (promise? (make-promise 42)) "make-promise produces a promise")
(assert-true (not (promise? 42)) "integer is not a promise")
(assert-true (not (promise? "string")) "string is not a promise")
(assert-true (not (promise? 'sym)) "symbol is not a promise")
(assert-true (not (promise? '(1 2 3))) "list is not a promise")
(assert-true (not (promise? (vector 1 2 3))) "generic vector is not a promise")
(assert-true (not (promise? (vector '%%promise))) "vector of length 1 is not a promise")
(assert-true (not (promise? #f)) "boolean #f is not a promise")

;; -----------------------------------------------------------------------
;; Test 2: Basic delay and force
;; -----------------------------------------------------------------------
(print-msg "=== Test 2: Basic delay and force ===")

(let ((p1 (delay (+ 10 20))))
  (assert-equal (force p1) 30 "basic arithmetic delay/force"))

(let ((p2 (delay (string-append "hello" " " "world"))))
  (assert-equal (force p2) "hello world" "string concatenation in delay"))

(let ((p3 (delay (list 1 2 3))))
  (assert-equal (force p3) '(1 2 3) "list expression in delay"))

;; -----------------------------------------------------------------------
;; Test 3: Memoization (Side effects run only once)
;; -----------------------------------------------------------------------
(print-msg "=== Test 3: Memoization ===")

(let ((eval-count (vector 0)))
  (let ((p (delay (begin
                    (vector-set! eval-count 0 (+ (vector-ref eval-count 0) 1))
                    (* 7 6)))))
    (assert-equal (vector-ref eval-count 0) 0 "promise thunk not evaluated before force")
    (assert-equal (force p) 42 "first force computes result")
    (assert-equal (vector-ref eval-count 0) 1 "eval-count is 1 after first force")
    (assert-equal (force p) 42 "second force returns cached result")
    (assert-equal (vector-ref eval-count 0) 1 "eval-count remains 1 after second force")
    (assert-equal (force p) 42 "third force returns cached result")
    (assert-equal (vector-ref eval-count 0) 1 "eval-count remains 1 after third force")))

;; -----------------------------------------------------------------------
;; Test 4: make-promise procedure semantics
;; -----------------------------------------------------------------------
(print-msg "=== Test 4: make-promise ===")

(let ((p (make-promise 999)))
  (assert-true (promise? p) "make-promise on value returns promise")
  (assert-equal (force p) 999 "force of make-promise returns value"))

(let ((orig-p (delay 123)))
  (let ((wrapped-p (make-promise orig-p)))
    (assert-true (eq? orig-p wrapped-p) "make-promise on existing promise returns same object")
    (assert-equal (force wrapped-p) 123 "force of wrapped promise returns value")))

;; -----------------------------------------------------------------------
;; Test 5: delay-force tail recursion & bounded space
;; -----------------------------------------------------------------------
(print-msg "=== Test 5: delay-force tail recursion ===")

(define (lazy-countdown n)
  (delay-force
    (if (= n 0)
        (delay 'blastoff)
        (lazy-countdown (- n 1)))))

(assert-equal (force (lazy-countdown 5000)) 'blastoff "5000 iterations of delay-force in constant space")

;; -----------------------------------------------------------------------
;; Test 6: R7RS 4.2.5 Re-entrant Self-Referential Promise
;; -----------------------------------------------------------------------
(print-msg "=== Test 6: R7RS Re-entrancy ===")

(define r7rs-count (vector 0))
(define r7rs-x (vector 5))
(define r7rs-p
  (delay
    (begin
      (vector-set! r7rs-count 0 (+ (vector-ref r7rs-count 0) 1))
      (if (> (vector-ref r7rs-count 0) (vector-ref r7rs-x 0))
          (vector-ref r7rs-count 0)
          (force r7rs-p)))))

(assert-equal (force r7rs-p) 6 "re-entrant force reaches termination at 6")
(vector-set! r7rs-x 0 10)
(assert-equal (force r7rs-p) 6 "memoized value remains 6 after x is mutated")

;; -----------------------------------------------------------------------
;; Test 7: Infinite Lazy Streams & stream-filter
;; -----------------------------------------------------------------------
(print-msg "=== Test 7: Infinite Lazy Streams ===")

(define (stream-integers n)
  (delay (cons n (stream-integers (+ n 1)))))

(define (stream-car s)
  (car (force s)))

(define (stream-cdr s)
  (cdr (force s)))

(define (stream-filter pred s)
  (delay-force
    (let ((pair (force s)))
      (let ((head (car pair))
            (tail (cdr pair)))
        (if (pred head)
            (delay (cons head (stream-filter pred tail)))
            (stream-filter pred tail))))))

(define (stream-take n s)
  (if (= n 0)
      '()
      (cons (stream-car s) (stream-take (- n 1) (stream-cdr s)))))

(let* ((all-ints (stream-integers 0))
       (even-ints (stream-filter (lambda (x) (= (modulo x 2) 0)) all-ints))
       (first-5 (stream-take 5 even-ints)))
  (assert-equal first-5 '(0 2 4 6 8) "infinite stream even number filtering"))

;; -----------------------------------------------------------------------
;; Test 8: Nested delay and force
;; -----------------------------------------------------------------------
(print-msg "=== Test 8: Nested delay and force ===")

(let ((nested (delay (delay 42))))
  (let ((inner (force nested)))
    (assert-true (promise? inner) "forcing outer promise yields inner promise")
    (assert-equal (force inner) 42 "forcing inner promise yields value")
    (assert-equal (force (force nested)) 42 "double force on nested delay yields value")))

;; -----------------------------------------------------------------------
;; Test 9: Non-promise passed to force
;; -----------------------------------------------------------------------
(print-msg "=== Test 9: Non-promise passed to force ===")

(assert-equal (force 42) 42 "force on integer returns integer")
(assert-equal (force "abc") "abc" "force on string returns string")
(assert-equal (force '(1 2 3)) '(1 2 3) "force on list returns list")
(assert-equal (force #t) #t "force on boolean returns boolean")

;; -----------------------------------------------------------------------
;; Summary
;; -----------------------------------------------------------------------
(print-msg "=======================================================")
(if (= (vector-ref *test-failures* 0) 0)
    (begin
      (print-msg "All R7RS delayed evaluation tests passed successfully!")
      (print-msg "=======================================================")
      #t)
    (begin
      (print-msg "SOME TESTS FAILED!")
      (print-msg "=======================================================")
      #f))
