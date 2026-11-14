;;; =======================================================================
;;; ULisp R7RS-large / SRFI 113 Sets and Bags Test Suite
;;; Conforms to DSN-33 Architecture Specification & Issue #702
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


;;; --- Test 1: Set Creation, Predicates & Membership ---
(write-string "--- Test 1: Set Creation & Membership ---\n")
(let ((s (set exact-integer-comparator 10 20 30 20 10))
      (empty-s (set exact-integer-comparator)))
  (test "set? on set" #t (set? s))
  (test "set? on bag" #f (set? (bag exact-integer-comparator 1)))
  (test "set-empty? on empty" #t (set-empty? empty-s))
  (test "set-empty? on non-empty" #f (set-empty? s))
  (test "set-size deduplicates" 3 (set-size s))
  (test "set-contains? 20" #t (set-contains? s 20))
  (test "set-contains? 99" #f (set-contains? s 99))
  (test "set-member found" 20 (set-member s 20 'missing))
  (test "set-member missing" 'missing (set-member s 99 'missing)))

;;; --- Test 2: Set Adjoin, Delete, Search & Unfold ---
(write-string "--- Test 2: Set Adjoin, Delete, Search & Unfold ---\n")
(let* ((s1 (set exact-integer-comparator 1 2 3))
       (s2 (set-adjoin s1 3 4 5))
       (s3 (set-delete s2 2 4)))
  (test "set-adjoin immutable original" 3 (set-size s1))
  (test "set-adjoin new size" 5 (set-size s2))
  (test "set-delete size" 3 (set-size s3))
  (test "set-delete removed 2" #f (set-contains? s3 2))
  (test "set-delete kept 5" #t (set-contains? s3 5)))

(let ((s-unf (set-unfold (lambda (n) (> n 4))
                         (lambda (n) (* n 10))
                         (lambda (n) (+ n 1))
                         1
                         exact-integer-comparator)))
  (test "set-unfold size" 4 (set-size s-unf))
  (test "set-unfold contains 40" #t (set-contains? s-unf 40)))

(let ((s (set exact-integer-comparator 10 20)))
  (call-with-values
    (lambda ()
      (set-search! s 30
                   (lambda (insert ignore) (insert 'inserted))
                   (lambda (elem update remove) (update elem 'unexpected))))
    (lambda (s-after tag)
      (test "set-search! insert tag" 'inserted tag)
      (test "set-search! inserted 30" #t (set-contains? s-after 30)))))

;;; --- Test 3: Set Iterators, Filter, Partition & Algebra ---
(write-string "--- Test 3: Set Iterators & Algebra ---\n")
(let ((a (set exact-integer-comparator 1 2 3 4))
      (b (set exact-integer-comparator 3 4 5 6)))
  (test "set-count even" 2 (set-count (lambda (x) (= (modulo x 2) 0)) a))
  (test "set-any? > 3" #t (set-any? (lambda (x) (> x 3)) a))
  (test "set-every? > 0" #t (set-every? (lambda (x) (> x 0)) a))
  (test "set-fold sum" 10 (set-fold (lambda (x acc) (+ x acc)) 0 a))
  (test "set-union size" 6 (set-size (set-union a b)))
  (test "set-intersection size" 2 (set-size (set-intersection a b)))
  (test "set-difference size" 2 (set-size (set-difference a b)))
  (test "set-xor size" 4 (set-size (set-xor a b)))
  (test "set=? identical" #t (set=? (set exact-integer-comparator 3 4) (set-intersection a b)))
  (test "set<? proper subset" #t (set<? (set exact-integer-comparator 3 4) a))
  (test "set<=? subset" #t (set<=? a a))
  (test "set-disjoint? false" #f (set-disjoint? a b))
  (test "set-disjoint? true" #t (set-disjoint? (set-difference a b) (set-difference b a))))

;;; --- Test 4: Bags (Multisets) Multiplicity & Algebra ---
(write-string "--- Test 4: Bags (Multisets) ---\n")
(let ((b1 (list->bag symbol-comparator '(a b a c a b)))
      (b2 (bag symbol-comparator 'a 'b 'b 'd)))
  (test "bag? on bag" #t (bag? b1))
  (test "bag-size total" 6 (bag-size b1))
  (test "bag-unique-size" 3 (bag-unique-size b1))
  (test "bag-element-count 'a" 3 (bag-element-count b1 'a))
  (test "bag-element-count 'b" 2 (bag-element-count b1 'b))
  (test "bag-element-count 'z" 0 (bag-element-count b1 'z))

  (let ((u (bag-union b1 b2))
        (s (bag-sum b1 b2))
        (inter (bag-intersection b1 b2))
        (diff (bag-difference b1 b2))
        (prod (bag-product 2 b2)))
    (test "bag-union max multiplicity 'a" 3 (bag-element-count u 'a))
    (test "bag-union max multiplicity 'b" 2 (bag-element-count u 'b))
    (test "bag-sum additive multiplicity 'a" 4 (bag-element-count s 'a))
    (test "bag-sum additive multiplicity 'b" 4 (bag-element-count s 'b))
    (test "bag-intersection min multiplicity 'a" 1 (bag-element-count inter 'a))
    (test "bag-intersection min multiplicity 'b" 2 (bag-element-count inter 'b))
    (test "bag-difference multiplicity 'a" 2 (bag-element-count diff 'a))
    (test "bag-difference multiplicity 'b" 0 (bag-element-count diff 'b))
    (test "bag-product multiplicity 'b" 4 (bag-element-count prod 'b))))

;;; --- Test 5: Bag <-> Set & Alist Conversions ---
(write-string "--- Test 5: Bag <-> Set & Alist Conversions ---\n")
(let* ((b (bag exact-integer-comparator 5 5 5 10 10))
       (s (bag->set b))
       (al (bag->alist b))
       (b-roundtrip (alist->bag exact-integer-comparator al)))
  (test "bag->set size" 2 (set-size s))
  (test "alist->bag roundtrip bag=?" #t (bag=? b b-roundtrip)))

