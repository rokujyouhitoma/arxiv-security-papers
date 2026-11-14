;;; =======================================================================
;;; ULisp R7RS-large / SRFI 128 Comparators Test Suite
;;; Conforms to DSN-33 Architecture Specification & Issue #701
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


;;; --- Test 1: Predicates and Atomic Comparators ---
(write-string "--- Test 1: Predicates and Atomic Comparators ---\n")
(test "comparator? on default-comparator" #t (comparator? default-comparator))
(test "comparator? on non-comparator" #f (comparator? 42))
(test "comparator-ordered? on exact-integer-comparator" #t (comparator-ordered? exact-integer-comparator))
(test "comparator-hashable? on exact-integer-comparator" #t (comparator-hashable? exact-integer-comparator))

(let ((eq-comp (make-eq-comparator)))
  (test "comparator-ordered? on make-eq-comparator" #f (comparator-ordered? eq-comp))
  (test "comparator-hashable? on make-eq-comparator" #t (comparator-hashable? eq-comp))
  (test "comparator-equal? on eq-comp same symbol" #t (comparator-equal? eq-comp 'alpha 'alpha))
  (test "comparator-equal? on eq-comp diff symbol" #f (comparator-equal? eq-comp 'alpha 'beta)))

(test "boolean-comparator #f < #t" -1 (comparator-compare boolean-comparator #f #t))
(test "boolean-comparator #t = #t" 0 (comparator-compare boolean-comparator #t #t))
(test "boolean-comparator #t > #f" 1 (comparator-compare boolean-comparator #t #f))

(test "char-ci-comparator #\\a = #\\A" #t (comparator-equal? char-ci-comparator #\a #\A))
(test "char-ci-comparator hash match" #t (= (comparator-hash char-ci-comparator #\a)
                                            (comparator-hash char-ci-comparator #\A)))

(test "string-ci-comparator equal" #t (comparator-equal? string-ci-comparator "Scheme" "scheme"))
(test "string-ci-comparator hash match" #t (= (comparator-hash string-ci-comparator "Scheme")
                                              (comparator-hash string-ci-comparator "scheme")))

;;; --- Test 2: Composite Comparators (Pair, List, Vector) ---
(write-string "--- Test 2: Composite Comparators ---\n")
(let ((pcomp (make-pair-comparator exact-integer-comparator string-comparator)))
  (test "pair-comparator type-test valid" #t (comparator-test-type pcomp (cons 10 "abc")))
  (test "pair-comparator type-test invalid" #f (comparator-test-type pcomp (cons "abc" 10)))
  (test "pair-comparator equal" #t (comparator-equal? pcomp (cons 1 "a") (cons 1 "a")))
  (test "pair-comparator ordering car" -1 (comparator-compare pcomp (cons 1 "z") (cons 2 "a")))
  (test "pair-comparator ordering cdr" -1 (comparator-compare pcomp (cons 1 "a") (cons 1 "b"))))

(let ((lcomp (make-list-comparator exact-integer-comparator list? (lambda (x) (null? x)) (lambda (x) (car x)) (lambda (x) (cdr x)))))
  (test "list-comparator type-test valid" #t (comparator-test-type lcomp '(1 2 3)))
  (test "list-comparator type-test invalid" #f (comparator-test-type lcomp '(1 "x" 3)))
  (test "list-comparator equal" #t (comparator-equal? lcomp '(1 2 3) '(1 2 3)))
  (test "list-comparator ordering prefix" -1 (comparator-compare lcomp '(1 2) '(1 2 3)))
  (test "list-comparator ordering elem" 1 (comparator-compare lcomp '(1 5) '(1 2))))

(let ((vcomp (make-vector-comparator exact-integer-comparator (lambda (x) (vector? x)) (lambda (v) (vector-length v)) (lambda (v i) (vector-ref v i)))))
  (test "vector-comparator equal" #t (comparator-equal? vcomp (vector 10 20) (vector 10 20)))
  (test "vector-comparator shorter < longer" -1 (comparator-compare vcomp (vector 99) (vector 1 2)))
  (test "vector-comparator same len ordering" -1 (comparator-compare vcomp (vector 1 2) (vector 1 3))))

;;; --- Test 3: Default Comparator & Comparison Predicates ---
(write-string "--- Test 3: Default Comparator & Predicates ---\n")
(test "=? chain true" #t (=? exact-integer-comparator 5 5 5 5))
(test "=? chain false" #f (=? exact-integer-comparator 5 5 6 5))
(test "<? chain true" #t (<? exact-integer-comparator 1 2 3 4))
(test "<? chain false" #f (<? exact-integer-comparator 1 2 2 4))
(test ">? chain true" #t (>? exact-integer-comparator 9 7 4 1))
(test "<=? chain true" #t (<=? exact-integer-comparator 1 2 2 4))
(test ">=? chain true" #t (>=? exact-integer-comparator 4 2 2 1))

(test "default-comparator cross-type '() < pair" #t (<? default-comparator '() '(1)))
(test "default-comparator cross-type boolean < char" #t (<? default-comparator #t #\a))
(test "default-comparator cross-type string < symbol" #t (<? default-comparator "z" 'a))
(test "default-comparator deep equal" #t (=? default-comparator (list 1 (vector 'a "b")) (list 1 (vector 'a "b"))))

;;; --- Test 4: comparator-if<=> Syntax ---
(write-string "--- Test 4: comparator-if<=> Syntax ---\n")
(test "comparator-if<=> explicit less"
      'less
      (comparator-if<=> exact-integer-comparator 3 5 'less 'equal 'greater))
(test "comparator-if<=> explicit equal"
      'equal
      (comparator-if<=> exact-integer-comparator 5 5 'less 'equal 'greater))
(test "comparator-if<=> explicit greater"
      'greater
      (comparator-if<=> exact-integer-comparator 8 5 'less 'equal 'greater))
(test "comparator-if<=> implicit default-comparator"
      'less
      (comparator-if<=> "apple" "banana" 'less 'equal 'greater))

;;; --- Test 5: Hash Bounds and Custom Comparator Registration ---
(write-string "--- Test 5: Hash Bounds and Custom Registration ---\n")
(test "hash-bound positive" #t (> (hash-bound) 0))
(test "hash-salt non-negative" #t (>= (hash-salt) 0))

(define-record-type <point>
  (make-point x y)
  point?
  (x point-x)
  (y point-y))

(define point-comparator
  (make-comparator
   point?
   (lambda (a b) (and (= (point-x a) (point-x b)) (= (point-y a) (point-y b))))
   (lambda (a b)
     (if (< (point-x a) (point-x b))
         #t
         (and (= (point-x a) (point-x b)) (< (point-y a) (point-y b)))))
   (lambda (p) (modulo (+ (* (point-x p) 31) (point-y p)) (hash-bound)))))

(comparator-register-default! point-comparator)

(test "registered point equal via default-comparator"
      #t
      (=? default-comparator (make-point 3 4) (make-point 3 4)))
(test "registered point ordering via default-comparator"
      #t
      (<? default-comparator (make-point 1 9) (make-point 2 0)))

