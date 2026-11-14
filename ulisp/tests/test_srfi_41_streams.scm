;;; =======================================================================
;;; ULisp R7RS-large / SRFI 41 Streams Test Suite
;;; Conforms to DSN-33 Architecture Specification & Issue #703
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


;;; --- Test 1: Stream Primitives & Laziness ---
(write-string "--- Test 1: Stream Primitives & Laziness ---\n")
(test "stream? on stream-null" #t (stream? stream-null))
(test "stream-null? on stream-null" #t (stream-null? stream-null))
(test "stream-pair? on stream-null" #f (stream-pair? stream-null))

(define *eval-counter* (vector 0))
(define s-lazy
  (stream-cons
   (begin
     (vector-set! *eval-counter* 0 (+ (vector-ref *eval-counter* 0) 1))
     42)
   (stream-cons
    (begin
      (vector-set! *eval-counter* 0 (+ (vector-ref *eval-counter* 0) 10))
      99)
    stream-null)))

(test "stream-cons does not evaluate car eagerly" 0 (vector-ref *eval-counter* 0))
(test "stream-car forces first element" 42 (stream-car s-lazy))
(test "stream-car evaluated once" 1 (vector-ref *eval-counter* 0))
(test "stream-car memoizes first element" 42 (stream-car s-lazy))
(test "stream-car memoized count still 1" 1 (vector-ref *eval-counter* 0))
(test "stream-cadr forces second element" 99 (stream-car (stream-cdr s-lazy)))
(test "stream-cadr counter is 11" 11 (vector-ref *eval-counter* 0))

;;; --- Test 2: Finite Streams, Ranges, Unfold & Conversions ---
(write-string "--- Test 2: Finite Streams & Conversions ---\n")
(let ((s (stream 10 20 30 40)))
  (test "stream->list finite" '(10 20 30 40) (stream->list s))
  (test "stream-length" 4 (stream-length s))
  (test "stream-ref 2" 30 (stream-ref s 2))
  (test "stream-reverse" '(40 30 20 10) (stream->list (stream-reverse s))))

(test "list->stream roundtrip" '(1 2 3 4 5) (stream->list (list->stream '(1 2 3 4 5))))
(test "stream-range ascending" '(0 1 2 3 4) (stream->list (stream-range 0 5)))
(test "stream-range step 2" '(0 2 4 6 8) (stream->list (stream-range 0 10 2)))
(test "stream-range descending" '(5 4 3 2 1) (stream->list (stream-range 5 0)))
(test "port->stream" '(#\a #\b #\c) (stream->list (port->stream (open-input-string "abc"))))

;;; --- Test 3: Infinite Streams (stream-from, stream-iterate, Fibonacci, Sieve) ---
(write-string "--- Test 3: Infinite Streams ---\n")
(define nats (stream-from 0))
(test "first 6 naturals" '(0 1 2 3 4 5) (stream->list 6 nats))
(test "stream-drop and stream-take on infinite"
      '(10 11 12 13)
      (stream->list (stream-take 4 (stream-drop 10 nats))))

(define powers-of-two (stream-iterate (lambda (x) (* x 2)) 1))
(test "powers of two" '(1 2 4 8 16 32) (stream->list 6 powers-of-two))

(test "stream-constant repeating" '(a b a b a) (stream->list 5 (stream-constant 'a 'b)))

(define fibs
  (stream-cons 0
               (stream-cons 1
                            (stream-map (lambda (a b) (+ a b))
                                        fibs
                                        (stream-cdr fibs)))))
(test "Infinite Fibonacci stream (first 10)"
      '(0 1 1 2 3 5 8 13 21 34)
      (stream->list 10 fibs))

(define-stream (sieve s)
  (let ((p (stream-car s)))
    (stream-cons p
                 (sieve (stream-filter (lambda (n) (not (= (modulo n p) 0)))
                                       (stream-cdr s))))))
(define primes (sieve (stream-from 2)))
(test "Sieve of Eratosthenes (first 10 primes)"
      '(2 3 5 7 11 13 17 19 23 29)
      (stream->list 10 primes))

;;; --- Test 4: Higher-Order Stream Operations ---
(write-string "--- Test 4: Higher-Order Operations ---\n")
(test "stream-append"
      '(1 2 3 4 5)
      (stream->list (stream-append (stream 1 2) (stream 3) (stream 4 5))))
(test "stream-concat"
      '(10 20 30 40)
      (stream->list (stream-concat (stream (stream 10 20) stream-null (stream 30 40)))))
(test "stream-fold sum"
      15
      (stream-fold (lambda (acc x) (+ acc x)) 0 (stream-range 1 6)))
(test "stream-scan prefix sums"
      '(0 1 3 6 10 15)
      (stream->list (stream-scan (lambda (acc x) (+ acc x)) 0 (stream-range 1 6))))
(test "stream-take-while"
      '(0 1 2 3 4)
      (stream->list (stream-take-while (lambda (x) (< x 5)) nats)))
(test "stream-drop-while"
      '(5 6 7)
      (stream->list (stream-drop-while (lambda (x) (< x 5)) (stream-range 0 8))))
(test "stream-zip"
      '((1 a) (2 b) (3 c))
      (stream->list (stream-zip (stream 1 2 3) (stream 'a 'b 'c 'd))))

;;; --- Test 5: Stream Comprehensions (stream-of) & stream-unfolds ---
(write-string "--- Test 5: stream-of & stream-unfolds ---\n")
(define evens-sq
  (stream-of (* x x)
    (x in (stream-range 1 10))
    (= (modulo x 2) 0)))
(test "stream-of squares of evens" '(4 16 36 64) (stream->list evens-sq))

(define pythagorean
  (stream-of (list a b c)
    (a in (stream-range 1 15))
    (b in (stream-range a 15))
    (c is (+ (* a a) (* b b)))
    (= c 25)))
(test "stream-of with in, is, and predicate" '((3 4 25)) (stream->list pythagorean))

(call-with-values
  (lambda ()
    (stream-unfolds
     (lambda (s)
       (if (> s 5)
           (values s '() '())
           (if (= (modulo s 2) 0)
               (values (+ s 1) (list s) #f)
               (values (+ s 1) #f (list s)))))
     1))
  (lambda (evens odds)
    (test "stream-unfolds evens" '(2 4) (stream->list evens))
    (test "stream-unfolds odds" '(1 3 5) (stream->list odds))))


