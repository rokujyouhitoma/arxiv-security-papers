;;; =======================================================================
;;; ULisp Test Suite: R7RS-large / SRFI 133 (Vector Library) Procedures (Issue #853)
;;; Testing:
;;;   Constructors: vector-unfold, vector-unfold-right, vector-reverse-copy,
;;;                 vector-concatenate, vector-append-subvectors
;;;   Predicates:   vector-empty?, vector=
;;;   Iteration:    vector-fold, vector-fold-right, vector-map, vector-map!,
;;;                 vector-for-each, vector-count, vector-cumulate
;;;   Searching:    vector-index, vector-index-right, vector-skip, vector-skip-right,
;;;                 vector-binary-search, vector-any, vector-every, vector-partition
;;;   Mutators:     vector-swap!, vector-fill!, vector-reverse!, vector-copy!,
;;;                 vector-reverse-copy!, vector-unfold!, vector-unfold-right!
;;;   Conversion:   vector->list, reverse-vector->list, list->vector,
;;;                 reverse-list->vector, string->vector, vector->string
;;; =======================================================================

(test-begin "srfi-133")

(define-syntax assert-equal
  (syntax-rules ()
    ((assert-equal name actual expected)
     (test-equal name expected actual))))

(define-syntax assert-true
  (syntax-rules ()
    ((assert-true name val)
     (test-assert name val))))

(define-syntax assert-false
  (syntax-rules ()
    ((assert-false name val)
     (test-assert name (not val)))))

(define (num= a b) (= a b))
(define (add a b) (+ a b))
(define (num-cmp a b) (- a b))
(define (even-num? n) (= (remainder n 2) 0))

;; =======================================================================
;; Group 1: Constructors
;; =======================================================================
(write-string "--- Group 1: Constructors ---")
(write-char #\newline)

;; vector-unfold
(assert-equal "1.1 vector-unfold basic"
  (vector-unfold (lambda (i x) (values (* i 2) (+ x 1))) 4 0)
  (vector 0 2 4 6))

(assert-equal "1.2 vector-unfold empty"
  (vector-unfold (lambda (i x) (values x x)) 0 10)
  (vector))

;; vector-unfold-right
(assert-equal "1.3 vector-unfold-right basic"
  (vector-unfold-right (lambda (i x) (values (* i 10) (+ x 1))) 4 0)
  (vector 0 10 20 30))

;; vector-reverse-copy
(assert-equal "1.4 vector-reverse-copy full"
  (vector-reverse-copy (vector 1 2 3 4 5))
  (vector 5 4 3 2 1))

(assert-equal "1.5 vector-reverse-copy slice"
  (vector-reverse-copy (vector 1 2 3 4 5) 1 4)
  (vector 4 3 2))

(assert-equal "1.6 vector-reverse-copy start only"
  (vector-reverse-copy (vector 1 2 3 4 5) 2)
  (vector 5 4 3))

;; vector-concatenate
(assert-equal "1.7 vector-concatenate"
  (vector-concatenate (list (vector 1 2) (vector 3 4) (vector 5)))
  (vector 1 2 3 4 5))

(assert-equal "1.8 vector-concatenate empty"
  (vector-concatenate '())
  (vector))

;; vector-append-subvectors
(assert-equal "1.9 vector-append-subvectors"
  (vector-append-subvectors (vector 10 20 30 40) 1 3 (vector 100 200 300) 0 2)
  (vector 20 30 100 200))


;; =======================================================================
;; Group 2: Predicates
;; =======================================================================
(write-string "--- Group 2: Predicates ---")
(write-char #\newline)

;; vector-empty?
(assert-true "2.1 vector-empty? on empty"
  (vector-empty? (vector)))

(assert-false "2.2 vector-empty? on non-empty"
  (vector-empty? (vector 1)))

;; vector=
(assert-true "2.3 vector= zero args"
  (vector= num=))

(assert-true "2.4 vector= single arg"
  (vector= num= (vector 1 2 3)))

(assert-true "2.5 vector= two equal vectors"
  (vector= num= (vector 1 2 3) (vector 1 2 3)))

(assert-true "2.6 vector= three equal vectors"
  (vector= num= (vector 1 2 3) (vector 1 2 3) (vector 1 2 3)))

(assert-false "2.7 vector= different elements"
  (vector= num= (vector 1 2 3) (vector 1 2 4)))

(assert-false "2.8 vector= different lengths"
  (vector= num= (vector 1 2) (vector 1 2 3)))


;; =======================================================================
;; Group 3: Iteration
;; =======================================================================
(write-string "--- Group 3: Iteration ---")
(write-char #\newline)

;; vector-fold
(assert-equal "3.1 vector-fold single vector"
  (vector-fold (lambda (acc x) (+ acc x)) 0 (vector 1 2 3 4 5))
  15)

(assert-equal "3.2 vector-fold multi vectors"
  (vector-fold (lambda (acc x y) (+ acc (* x y))) 0 (vector 1 2 3) (vector 10 20 30))
  140)

(assert-equal "3.3 vector-fold unequal lengths (stops at min)"
  (vector-fold (lambda (acc x y) (+ acc (* x y))) 0 (vector 1 2 3 4) (vector 10 20))
  50)

;; vector-fold-right
(assert-equal "3.4 vector-fold-right single vector"
  (vector-fold-right (lambda (acc x) (cons x acc)) '() (vector 1 2 3))
  '(1 2 3))

(assert-equal "3.5 vector-fold-right multi vectors"
  (vector-fold-right (lambda (acc x y) (cons (+ x y) acc)) '() (vector 1 2 3) (vector 10 20 30))
  '(11 22 33))

;; vector-map multi
(assert-equal "3.6 vector-map multi vectors"
  (vector-map (lambda (x y) (+ x y)) (vector 1 2 3) (vector 10 20 30))
  (vector 11 22 33))

(assert-equal "3.7 vector-map unequal lengths"
  (vector-map (lambda (x y) (+ x y)) (vector 1 2 3 4) (vector 10 20))
  (vector 11 22))

;; vector-map!
(let ((tgt (vector 0 0 0)))
  (vector-map! (lambda (x) (* x 3)) tgt (vector 1 2 3))
  (assert-equal "3.8 vector-map! single" tgt (vector 3 6 9)))

(let ((tgt (vector 0 0 0)))
  (vector-map! add tgt (vector 1 2 3) (vector 10 20 30))
  (assert-equal "3.9 vector-map! multi" tgt (vector 11 22 33)))

;; vector-for-each multi
(let ((sum (vector 0)))
  (vector-for-each (lambda (x y) (vector-set! sum 0 (+ (vector-ref sum 0) (* x y))))
                   (vector 1 2 3) (vector 10 20 30))
  (assert-equal "3.10 vector-for-each multi" (vector-ref sum 0) 140))

;; vector-count
(assert-equal "3.11 vector-count single"
  (vector-count (lambda (x) (> x 2)) (vector 1 2 3 4 5))
  3)

(assert-equal "3.12 vector-count multi"
  (vector-count (lambda (x y) (= (+ x y) 10)) (vector 1 2 3 4) (vector 9 8 5 6))
  3)

;; vector-cumulate
(assert-equal "3.13 vector-cumulate prefix sums"
  (vector-cumulate add 0 (vector 1 2 3 4 5))
  (vector 1 3 6 10 15))


;; =======================================================================
;; Group 4: Searching
;; =======================================================================
(write-string "--- Group 4: Searching ---")
(write-char #\newline)

;; vector-index
(assert-equal "4.1 vector-index found"
  (vector-index (lambda (x) (> x 2)) (vector 1 2 3 4 5))
  2)

(assert-false "4.2 vector-index not found"
  (vector-index (lambda (x) (> x 10)) (vector 1 2 3)))

(assert-equal "4.3 vector-index multi"
  (vector-index (lambda (x y) (= x y)) (vector 1 2 3 4) (vector 9 2 5 4))
  1)

;; vector-index-right
(assert-equal "4.4 vector-index-right found"
  (vector-index-right even-num? (vector 1 2 3 4 5))
  3)

(assert-false "4.5 vector-index-right not found"
  (vector-index-right (lambda (x) (> x 10)) (vector 1 2 3)))

;; vector-skip
(assert-equal "4.10 vector-skip found"
  (vector-skip (lambda (x) (< x 3)) (vector 1 2 3 4 5))
  2)

;; vector-skip-right
(assert-equal "4.11 vector-skip-right found"
  (vector-skip-right (lambda (x) (> x 3)) (vector 1 2 3 4 5))
  2)

;; vector-binary-search
(assert-equal "4.6 vector-binary-search middle"
  (vector-binary-search (vector 10 20 30 40 50) 30 num-cmp)
  2)

(assert-equal "4.7 vector-binary-search first"
  (vector-binary-search (vector 10 20 30 40 50) 10 num-cmp)
  0)

(assert-equal "4.8 vector-binary-search last"
  (vector-binary-search (vector 10 20 30 40 50) 50 num-cmp)
  4)

(assert-false "4.9 vector-binary-search not found"
  (vector-binary-search (vector 10 20 30 40 50) 25 num-cmp)
  )

(assert-equal "4.10 vector-binary-search slice hit"
  (vector-binary-search (vector 10 20 30 40 50) 40 num-cmp 2 5)
  3)

(assert-false "4.11 vector-binary-search slice miss"
  (vector-binary-search (vector 10 20 30 40 50) 20 num-cmp 2 5)
  )

;; vector-any
(assert-equal "4.12 vector-any hit"
  (vector-any (lambda (x) (if (> x 3) (* x 10) #f)) (vector 1 2 3 4 5))
  40)

(assert-false "4.13 vector-any miss"
  (vector-any (lambda (x) (> x 10)) (vector 1 2 3)))

;; vector-every
(assert-true "4.14 vector-every all match"
  (vector-every (lambda (x) (> x 0)) (vector 1 2 3)))

(assert-false "4.15 vector-every not all match"
  (vector-every (lambda (x) (> x 2)) (vector 1 2 3)))

(assert-true "4.16 vector-every empty"
  (vector-every (lambda (x) #f) (vector)))

;; vector-partition
(call-with-values
  (lambda () (vector-partition even-num? (vector 1 2 3 4 5 6)))
  (lambda (v cnt)
    (assert-equal "4.17 vector-partition count" cnt 3)
    (assert-equal "4.18 vector-partition result" v (vector 2 4 6 1 3 5))))


;; =======================================================================
;; Group 5: Mutators
;; =======================================================================
(write-string "--- Group 5: Mutators ---")
(write-char #\newline)

;; vector-swap!
(let ((v (vector 10 20 30)))
  (vector-swap! v 0 2)
  (assert-equal "5.1 vector-swap!" v (vector 30 20 10)))

;; vector-reverse!
(let ((v (vector 1 2 3 4 5)))
  (vector-reverse! v)
  (assert-equal "5.2 vector-reverse! full" v (vector 5 4 3 2 1)))

(let ((v (vector 1 2 3 4 5)))
  (vector-reverse! v 1 4)
  (assert-equal "5.3 vector-reverse! slice" v (vector 1 4 3 2 5)))

;; vector-reverse-copy!
(let ((to (vector 0 0 0 0 0))
      (from (vector 1 2 3)))
  (vector-reverse-copy! to 1 from)
  (assert-equal "5.4 vector-reverse-copy! distinct" to (vector 0 3 2 1 0)))

(let ((v (vector 1 2 3 4 5)))
  (vector-reverse-copy! v 1 v 0 3)
  (assert-equal "5.5 vector-reverse-copy! overlapping" v (vector 1 3 2 1 5)))

;; vector-unfold!
(let ((v (vector 0 0 0 0 0)))
  (vector-unfold! (lambda (i x) (values (* i 10) (+ x 1))) v 1 4 0)
  (assert-equal "5.6 vector-unfold!" v (vector 0 10 20 30 0)))

;; vector-unfold-right!
(let ((v (vector 0 0 0 0 0)))
  (vector-unfold-right! (lambda (i x) (values (* i 10) (+ x 1))) v 1 4 0)
  (assert-equal "5.7 vector-unfold-right!" v (vector 0 10 20 30 0)))


;; =======================================================================
;; Group 6: Conversion
;; =======================================================================
(write-string "--- Group 6: Conversion ---")
(write-char #\newline)

;; reverse-vector->list
(assert-equal "6.1 reverse-vector->list full"
  (reverse-vector->list (vector 1 2 3 4 5))
  '(5 4 3 2 1))

(assert-equal "6.2 reverse-vector->list slice"
  (reverse-vector->list (vector 1 2 3 4 5) 1 4)
  '(4 3 2))

;; reverse-list->vector
(assert-equal "6.3 reverse-list->vector full"
  (reverse-list->vector '(1 2 3 4 5))
  (vector 5 4 3 2 1))

(assert-equal "6.4 reverse-list->vector slice"
  (reverse-list->vector '(1 2 3 4 5) 1 4)
  (vector 4 3 2))

;; vector->list slice
(assert-equal "6.5 vector->list slice"
  (vector->list (vector 1 2 3 4 5) 1 4)
  '(2 3 4))

;; list->vector slice
(assert-equal "6.6 list->vector slice"
  (list->vector '(1 2 3 4 5) 1 4)
  (vector 2 3 4))

(test-end "srfi-133")
