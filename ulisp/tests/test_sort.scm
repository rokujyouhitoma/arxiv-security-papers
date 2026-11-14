;;; =======================================================================
;;; ULisp Test Suite: R7RS-large / SRFI 132 / SRFI 95 Sort Procedures
;;; Conforms to DSN-33 Architecture Specification & Issue #655
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(test-begin "sort")

(define-syntax assert-equal
  (syntax-rules ()
    ((assert-equal name actual expected)
     (test-equal name expected actual))))

(define-syntax assert-true
  (syntax-rules ()
    ((assert-true name expr)
     (test-assert name expr))))

(define-syntax assert-false
  (syntax-rules ()
    ((assert-false name expr)
     (test-assert name (not expr)))))






;;; -----------------------------------------------------------------------

;; Comparison procedure helpers for higher-order sort procedure testing
(define (num< a b) (< a b))
(define (num> a b) (> a b))
(define (num<= a b) (<= a b))
(define (num>= a b) (>= a b))
(define (num= a b) (= a b))

;;; Group 1: Sorted? Predicates (list-sorted?, vector-sorted?, sorted?)
;;; -----------------------------------------------------------------------
(write-string "--- Group 1: Sorted? Predicates ---")
(write-char #\newline)

(assert-true "empty list is sorted"
             (list-sorted? num< '()))

(assert-true "single element list is sorted"
             (list-sorted? num< '(42)))

(assert-true "strictly ascending list"
             (list-sorted? num< '(1 2 3 4 5)))

(assert-false "unsorted list with <"
              (list-sorted? num< '(1 3 2 4 5)))

(assert-true "non-decreasing list with duplicates is sorted under <"
             (list-sorted? num< '(1 2 2 3 3 5)))

(assert-false "unsorted list with duplicates fails <"
              (list-sorted? num< '(1 2 2 1 5)))

(assert-true "empty vector is sorted"
             (vector-sorted? num< (vector)))

(assert-true "ascending vector"
             (vector-sorted? num< (vector 10 20 30 40)))

(assert-false "descending vector with <"
              (vector-sorted? num< (vector 40 30 20 10)))

(assert-true "vector range sorted"
             (vector-sorted? num< (vector 99 1 2 3 0) 1 4))

(assert-false "vector range not sorted"
              (vector-sorted? num< (vector 99 3 2 1 0) 1 4))

(assert-true "vector-sorted? out of bounds signals error"
             (guard (ex (else #t))
               (vector-sorted? num< (vector 1 2 3) 0 10)
               #f))

(assert-true "sorted? on list"
             (sorted? '(2 4 6 8) num<))

(assert-true "sorted? on vector"
             (sorted? (vector 8 6 4 2) num>))

;;; -----------------------------------------------------------------------
;;; Group 2: Merge Procedures (list-merge, vector-merge, merge)
;;; -----------------------------------------------------------------------
(write-string "--- Group 2: Merge Procedures ---")
(write-char #\newline)

(assert-equal "list-merge both empty"
              (list-merge num< '() '())
              '())

(assert-equal "list-merge left empty"
              (list-merge num< '() '(1 2 3))
              '(1 2 3))

(assert-equal "list-merge right empty"
              (list-merge num< '(1 2 3) '())
              '(1 2 3))

(assert-equal "list-merge disjoint lists"
              (list-merge num< '(1 3 5) '(2 4 6))
              '(1 2 3 4 5 6))

(assert-equal "list-merge overlapping identical elements"
              (list-merge num< '(1 2 5) '(2 3 5))
              '(1 2 2 3 5 5))

(assert-equal "vector-merge disjoint"
              (vector-merge num< (vector 1 4 7) (vector 2 3 8))
              (vector 1 2 3 4 7 8))

(assert-equal "vector-merge with empty"
              (vector-merge num< (vector) (vector 10 20))
              (vector 10 20))

(assert-equal "SRFI 95 merge procedure"
              (merge '(10 30) '(20 40) num<)
              '(10 20 30 40))

;;; -----------------------------------------------------------------------
;;; Group 3: List Sorting (list-sort, list-stable-sort, sort)
;;; -----------------------------------------------------------------------
(write-string "--- Group 3: List Sorting ---")
(write-char #\newline)

(assert-equal "list-sort empty"
              (list-sort num< '())
              '())

(assert-equal "list-sort single"
              (list-sort num< '(7))
              '(7))

(assert-equal "list-sort two ascending"
              (list-sort num< '(1 2))
              '(1 2))

(assert-equal "list-sort two descending"
              (list-sort num< '(2 1))
              '(1 2))

(assert-equal "list-sort odd count"
              (list-sort num< '(5 2 8 1 9 4 3 7 6))
              '(1 2 3 4 5 6 7 8 9))

(assert-equal "list-sort even count"
              (list-sort num< '(4 1 3 2))
              '(1 2 3 4))

(assert-equal "list-sort descending comparator >"
              (list-sort num> '(1 5 2 4 3))
              '(5 4 3 2 1))

(assert-equal "list-sort all identical elements"
              (list-sort num< '(3 3 3 3 3))
              '(3 3 3 3 3))

(assert-equal "list-sort negative and extreme numbers"
              (list-sort num< '(100 -50 0 42 -10 999 -999))
              '(-999 -50 -10 0 42 100 999))

(assert-equal "list-stable-sort alias"
              (list-stable-sort num< '(3 1 2))
              '(1 2 3))

(assert-equal "SRFI 95 sort on list"
              (sort '(9 1 5) num<)
              '(1 5 9))

;;; -----------------------------------------------------------------------
;;; Group 4: Stability Verification (Keyed Pairs)
;;; -----------------------------------------------------------------------
(write-string "--- Group 4: Stability Verification ---")
(write-char #\newline)

;; Compare pairs by their car only; equal cars must preserve cdr order
(define (pair-key-< a b)
  (< (car a) (car b)))

(let* ((input '((2 . a) (1 . a) (2 . b) (1 . b) (2 . c) (1 . c)))
       (res (list-sort pair-key-< input)))
  (assert-equal "list-sort preserves relative order of equal keys"
                res
                '((1 . a) (1 . b) (1 . c) (2 . a) (2 . b) (2 . c))))

(let* ((input (vector (cons 2 'a) (cons 1 'a) (cons 2 'b) (cons 1 'b) (cons 2 'c) (cons 1 'c)))
       (res (vector-sort pair-key-< input)))
  (assert-equal "vector-sort preserves relative order of equal keys"
                res
                (vector (cons 1 'a) (cons 1 'b) (cons 1 'c) (cons 2 'a) (cons 2 'b) (cons 2 'c))))

;;; -----------------------------------------------------------------------
;;; Group 5: Vector Sorting (vector-sort, vector-stable-sort)
;;; -----------------------------------------------------------------------
(write-string "--- Group 5: Vector Sorting ---")
(write-char #\newline)

(assert-equal "vector-sort empty"
              (vector-sort num< (vector))
              (vector))

(assert-equal "vector-sort single"
              (vector-sort num< (vector 42))
              (vector 42))

(assert-equal "vector-sort basic ascending"
              (vector-sort num< (vector 5 3 1 4 2))
              (vector 1 2 3 4 5))

(assert-equal "vector-sort descending >"
              (vector-sort num> (vector 10 40 20 50 30))
              (vector 50 40 30 20 10))

;; Immutability check: vector-sort must not mutate original vector
(let* ((orig (vector 3 2 1))
       (sorted (vector-sort num< orig)))
  (assert-equal "vector-sort returns sorted copy" sorted (vector 1 2 3))
  (assert-equal "vector-sort leaves original unchanged" orig (vector 3 2 1)))

;; Partial range sorting
(assert-equal "vector-sort with start index"
              (vector-sort num< (vector 5 4 3 2 1) 2)
              (vector 1 2 3))

(assert-equal "vector-sort with start and end index"
              (vector-sort num< (vector 99 5 2 8 1 0) 1 5)
              (vector 1 2 5 8))

(assert-true "vector-sort out of bounds signals error"
             (guard (ex (else #t))
               (vector-sort num< (vector 1 2 3) 2 1)
               #f))

;;; -----------------------------------------------------------------------
;;; Group 6: In-place Destructive Sorts & SRFI 95 (list-sort!, vector-sort!, sort!)
;;; -----------------------------------------------------------------------
(write-string "--- Group 6: Destructive Sorts & SRFI 95 ---")
(write-char #\newline)

(let ((lst (list 5 1 4 2 3)))
  (assert-equal "list-sort! mutates and returns sorted"
                (list-sort! num< lst)
                '(1 2 3 4 5)))

(let ((vec (vector 50 20 40 10 30)))
  (assert-equal "vector-sort! mutates entire vector"
                (vector-sort! num< vec)
                (vector 10 20 30 40 50))
  (assert-equal "vector-sort! verified in-place"
                vec
                (vector 10 20 30 40 50)))

(let ((vec (vector 99 5 1 4 2 88)))
  (vector-sort! num< vec 1 5)
  (assert-equal "vector-sort! in-place subrange"
                vec
                (vector 99 1 2 4 5 88)))

(let ((vec (vector 3 1 2)))
  (assert-equal "SRFI 95 sort! on vector"
                (sort! vec num<)
                (vector 1 2 3)))

(let ((lst (list 3 1 2)))
  (assert-equal "SRFI 95 sort! on list"
                (sort! lst num<)
                '(1 2 3)))

(test-end "sort")
