;;; =======================================================================
;;; ULisp Test Suite: R7RS-large / SRFI 1 (List Library) Procedures (Issue #648)
;;; Testing: xcons, cons*, list-tabulate, iota,
;;;          proper-list?, circular-list?, dotted-list?, not-pair?, null-list?, list=,
;;;          first..tenth, car+cdr, take, drop, take-right, drop-right, split-at, last, last-pair,
;;;          count, fold, fold-right, unfold, unfold-right, reduce, reduce-right,
;;;          filter, remove, partition, find, find-tail, any, every, list-index,
;;;          take-while, drop-while, span, break,
;;;          delete, delete-duplicates, alist-cons, alist-copy, alist-delete
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
    ((and (vector? a) (vector? b))
     (and (= (vector-length a) (vector-length b))
          (let loop ((i 0))
            (if (= i (vector-length a))
                #t
                (if (test-equal? (vector-ref a i) (vector-ref b i))
                    (loop (+ i 1))
                    #f)))))
    (else #f)))

(define (assert-equal name actual expected)
  (if (test-equal? actual expected)
      (test-pass name)
      (test-fail name expected actual)))

(define (assert-true name val)
  (if val
      (test-pass name)
      (test-fail name #t val)))

(define (assert-false name val)
  (if (not val)
      (test-pass name)
      (test-fail name #f val)))

(define (num= a b) (= a b))
(define (add a b) (+ a b))
(define (sub a b) (- a b))
(define (mul a b) (* a b))
(define (pair-cons a b) (cons a b))
(define (test-eq? a b) (eq? a b))

(write-string "=== Running ULisp SRFI 1 (List Library) Test Suite (Issue #648) ===")
(write-char #\newline)
(flush-output-port)

;; =======================================================================
;; Group 1: Constructors (xcons, cons*, list-tabulate, iota)
;; =======================================================================
(write-string "--- Group 1: Constructors ---")
(write-char #\newline)

(assert-equal "1.1 xcons basic" (xcons '(b c) 'a) '(a b c))
(assert-equal "1.2 xcons atomic" (xcons 2 1) '(1 . 2))

(assert-equal "1.3 cons* single" (cons* 'a) 'a)
(assert-equal "1.4 cons* pair" (cons* 1 2) '(1 . 2))
(assert-equal "1.5 cons* list" (cons* 1 2 3 '(4 5)) '(1 2 3 4 5))
(assert-equal "1.6 cons* chain" (cons* 1 2 3 '()) '(1 2 3))

(assert-equal "1.7 list-tabulate zero" (list-tabulate 0 (lambda (x) (* x 2))) '())
(assert-equal "1.8 list-tabulate squares" (list-tabulate 5 (lambda (x) (* x x))) '(0 1 4 9 16))

(assert-equal "1.9 iota zero" (iota 0) '())
(assert-equal "1.10 iota count" (iota 5) '(0 1 2 3 4))
(assert-equal "1.11 iota count start" (iota 4 10) '(10 11 12 13))
(assert-equal "1.12 iota count start step" (iota 4 10 -2) '(10 8 6 4))

;; =======================================================================
;; Group 2: Predicates (proper-list?, circular-list?, dotted-list?, not-pair?, null-list?, list=)
;; =======================================================================
(write-string "--- Group 2: Predicates ---")
(write-char #\newline)

(assert-true "2.1 proper-list? nil" (proper-list? '()))
(assert-true "2.2 proper-list? list" (proper-list? '(1 2 3 4)))
(assert-false "2.3 proper-list? atom" (proper-list? 42))
(assert-false "2.4 proper-list? dot" (proper-list? '(1 2 . 3)))

(let* ((c4 (cons 4 '()))
       (c3 (cons 3 c4))
       (c2 (cons 2 c3))
       (circ (cons 1 c2)))
  (set-cdr! c4 circ)
  (assert-true "2.5 circular-list? true" (circular-list? circ))
  (assert-false "2.6 circular-list? false for proper" (circular-list? '(1 2 3 4))))

(assert-true "2.7 dotted-list? true" (dotted-list? '(1 2 . 3)))
(assert-false "2.8 dotted-list? false for nil" (dotted-list? '()))
(assert-false "2.9 dotted-list? false for proper" (dotted-list? '(1 2 3)))

(assert-true "2.10 not-pair? atom" (not-pair? 100))
(assert-true "2.11 not-pair? nil" (not-pair? '()))
(assert-false "2.12 not-pair? pair" (not-pair? '(a . b)))

(assert-true "2.13 null-list? nil" (null-list? '()))
(assert-false "2.14 null-list? pair" (null-list? '(1)))

(assert-true "2.15 list= zero/one" (list= num=))
(assert-true "2.16 list= one" (list= num= '(1 2 3)))
(assert-true "2.17 list= two equal" (list= num= '(1 2 3) '(1 2 3)))
(assert-false "2.18 list= two diff len" (list= num= '(1 2 3) '(1 2)))
(assert-false "2.19 list= two diff elt" (list= num= '(1 2 3) '(1 9 3)))
(assert-true "2.20 list= three equal" (list= num= '(1 2) '(1 2) '(1 2)))

;; =======================================================================
;; Group 3: Selectors (first..tenth, car+cdr, take, drop, take-right, drop-right, split-at, last, last-pair)
;; =======================================================================
(write-string "--- Group 3: Selectors ---")
(write-char #\newline)

(let ((l '(10 20 30 40 50 60 70 80 90 100)))
  (assert-equal "3.1 first" (first l) 10)
  (assert-equal "3.2 second" (second l) 20)
  (assert-equal "3.3 third" (third l) 30)
  (assert-equal "3.4 fourth" (fourth l) 40)
  (assert-equal "3.5 fifth" (fifth l) 50)
  (assert-equal "3.6 sixth" (sixth l) 60)
  (assert-equal "3.7 seventh" (seventh l) 70)
  (assert-equal "3.8 eighth" (eighth l) 80)
  (assert-equal "3.9 ninth" (ninth l) 90)
  (assert-equal "3.10 tenth" (tenth l) 100))

(call-with-values
  (lambda () (car+cdr '(hello . world)))
  (lambda (a d)
    (assert-equal "3.11 car+cdr car" a 'hello)
    (assert-equal "3.12 car+cdr cdr" d 'world)))

(assert-equal "3.13 take zero" (take '(a b c d) 0) '())
(assert-equal "3.14 take 2" (take '(a b c d) 2) '(a b))
(assert-equal "3.15 take all" (take '(a b c d) 4) '(a b c d))

(assert-equal "3.16 drop zero" (drop '(a b c d) 0) '(a b c d))
(assert-equal "3.17 drop 2" (drop '(a b c d) 2) '(c d))
(assert-equal "3.18 drop all" (drop '(a b c d) 4) '())

(assert-equal "3.19 take-right zero" (take-right '(a b c d) 0) '())
(assert-equal "3.20 take-right 2" (take-right '(a b c d) 2) '(c d))
(assert-equal "3.21 take-right all" (take-right '(a b c d) 4) '(a b c d))

(assert-equal "3.22 drop-right zero" (drop-right '(a b c d) 0) '(a b c d))
(assert-equal "3.23 drop-right 2" (drop-right '(a b c d) 2) '(a b))
(assert-equal "3.24 drop-right all" (drop-right '(a b c d) 4) '())

(call-with-values
  (lambda () (split-at '(1 2 3 4 5) 3))
  (lambda (p s)
    (assert-equal "3.25 split-at prefix" p '(1 2 3))
    (assert-equal "3.26 split-at suffix" s '(4 5))))

(assert-equal "3.27 last" (last '(a b c d)) 'd)
(assert-equal "3.28 last-pair" (last-pair '(a b c d)) '(d))

;; =======================================================================
;; Group 4: Fold, Unfold & Reductions
;; =======================================================================
(write-string "--- Group 4: Fold, Unfold & Reductions ---")
(write-char #\newline)

(assert-equal "4.1 count single" (count (lambda (x) (> x 0)) '(-1 2 -3 4 5)) 3)
(assert-equal "4.2 count dual" (count num= '(1 2 3 4) '(1 9 3 8)) 2)

(assert-equal "4.3 fold single" (fold add 0 '(1 2 3 4 5)) 15)
(assert-equal "4.4 fold cons (reverse)" (fold pair-cons '() '(a b c)) '(c b a))
(assert-equal "4.5 fold dual" (fold (lambda (x y acc) (+ (+ x y) acc)) 0 '(1 2 3) '(10 20 30)) 66)

(assert-equal "4.6 fold-right single" (fold-right pair-cons '() '(a b c)) '(a b c))
(assert-equal "4.7 fold-right minus" (fold-right sub 0 '(1 2 3)) 2) ; 1 - (2 - (3 - 0)) = 2

(assert-equal "4.8 unfold count-down"
              (unfold (lambda (x) (= x 0))
                      (lambda (x) (* x x))
                      (lambda (x) (- x 1))
                      5)
              '(25 16 9 4 1))

(assert-equal "4.9 unfold-right"
              (unfold-right (lambda (x) (= x 0))
                            (lambda (x) (* x x))
                            (lambda (x) (- x 1))
                            5)
              '(1 4 9 16 25))

(assert-equal "4.10 reduce empty" (reduce add 0 '()) 0)
(assert-equal "4.11 reduce single" (reduce add 0 '(42)) 42)
(assert-equal "4.12 reduce multi" (reduce add 0 '(1 2 3 4)) 10)

(assert-equal "4.13 reduce-right empty" (reduce-right add 0 '()) 0)
(assert-equal "4.14 reduce-right multi" (reduce-right sub 0 '(1 2 3)) 2)

;; =======================================================================
;; Group 5: Searching & Filtering
;; =======================================================================
(write-string "--- Group 5: Searching & Filtering ---")
(write-char #\newline)

(define (even? n) (= (modulo n 2) 0))
(define (odd? n) (not (even? n)))

(assert-equal "5.1 filter" (filter even? '(1 2 3 4 5 6)) '(2 4 6))
(assert-equal "5.2 remove" (remove even? '(1 2 3 4 5 6)) '(1 3 5))

(call-with-values
  (lambda () (partition even? '(1 2 3 4 5 6)))
  (lambda (evens odds)
    (assert-equal "5.3 partition evens" evens '(2 4 6))
    (assert-equal "5.4 partition odds" odds '(1 3 5))))

(assert-equal "5.5 find hit" (find even? '(1 3 5 8 9)) 8)
(assert-false "5.6 find miss" (find even? '(1 3 5 7)))

(assert-equal "5.7 find-tail hit" (find-tail even? '(1 3 5 8 9)) '(8 9))
(assert-false "5.8 find-tail miss" (find-tail even? '(1 3 5 7)))

(assert-equal "5.9 any single hit" (any (lambda (x) (and (> x 3) (* x 10))) '(1 2 4 5)) 40)
(assert-false "5.10 any single miss" (any (lambda (x) (> x 10)) '(1 2 4 5)))
(assert-true "5.11 any dual hit" (any num= '(1 2 3) '(9 2 8)))

(assert-true "5.12 every true" (every (lambda (x) (> x 0)) '(1 2 3 4)))
(assert-false "5.13 every false" (every (lambda (x) (> x 0)) '(1 2 -3 4)))
(assert-equal "5.14 every value return" (every (lambda (x) (+ x 10)) '(1 2 3)) 13)

(assert-equal "5.15 list-index hit" (list-index even? '(1 3 5 6 7)) 3)
(assert-false "5.16 list-index miss" (list-index even? '(1 3 5 7)))
(assert-equal "5.17 list-index dual" (list-index num= '(1 2 3 4) '(9 8 3 1)) 2)

(assert-equal "5.18 take-while" (take-while odd? '(1 3 5 6 7 9)) '(1 3 5))
(assert-equal "5.19 drop-while" (drop-while odd? '(1 3 5 6 7 9)) '(6 7 9))

(call-with-values
  (lambda () (span odd? '(1 3 5 6 7 9)))
  (lambda (prefix suffix)
    (assert-equal "5.20 span prefix" prefix '(1 3 5))
    (assert-equal "5.21 span suffix" suffix '(6 7 9))))

(call-with-values
  (lambda () (break even? '(1 3 5 6 7 9)))
  (lambda (prefix suffix)
    (assert-equal "5.22 break prefix" prefix '(1 3 5))
    (assert-equal "5.23 break suffix" suffix '(6 7 9))))

;; =======================================================================
;; Group 6: Deletion & Association Lists
;; =======================================================================
(write-string "--- Group 6: Deletion & Association Lists ---")
(write-char #\newline)

(assert-equal "6.1 delete basic" (delete 3 '(1 2 3 4 3 5)) '(1 2 4 5))
(assert-equal "6.2 delete custom eq" (delete 'b '((a . 1) (b . 2) (c . 3)) (lambda (x y) (eq? x (car y)))) '((a . 1) (c . 3)))

(assert-equal "6.3 delete-duplicates" (delete-duplicates '(a b a c b d a)) '(a b c d))

(assert-equal "6.4 alist-cons" (alist-cons 'key 'val '((foo . bar))) '((key . val) (foo . bar)))

(let* ((orig '((a . 1) (b . 2)))
       (cp (alist-copy orig)))
  (assert-equal "6.5 alist-copy content" cp orig)
  (set-cdr! (car cp) 99)
  (assert-equal "6.6 alist-copy shallow spine copy" (cdr (car orig)) 1))

(assert-equal "6.7 alist-delete" (alist-delete 'b '((a . 1) (b . 2) (c . 3) (b . 4)) test-eq?) '((a . 1) (c . 3)))

;; =======================================================================
;; Summary
;; =======================================================================
(write-string "=======================================================")
(write-char #\newline)
(if (= (vector-ref *test-failures* 0) 0)
    (begin
      (write-string "ALL SRFI 1 PROCEDURES TESTS PASSED (0 failures)!")
      (write-char #\newline)
      (flush-output-port))
    (begin
      (write-string "TEST FAILURES DETECTED: ")
      (write (vector-ref *test-failures* 0))
      (write-char #\newline)
      (flush-output-port)
      (exit 1)))
