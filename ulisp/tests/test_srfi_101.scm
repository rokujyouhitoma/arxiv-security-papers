;;; =======================================================================
;;; ULisp Test Suite: R7RS-large / SRFI 101 Purely Functional Random-Access Lists (Issue #854)
;;; Testing:
;;;   Constructors: ra-cons, ra-list, ra-make-list, ra-quote
;;;   Predicates:   ra-pair?, ra-null?, ra-list?, ra-length<=?
;;;   Selectors:    ra-car, ra-cdr, ra-car+cdr, ra-list-ref, ra-list-tail, 28 cxr accessors
;;;   Updaters:     ra-list-set, ra-list-ref/update, immutability & structural sharing
;;;   Iteration:    ra-length, ra-append, ra-reverse, ra-map, ra-for-each
;;;   Conversion:   list->rlist, rlist->list, linear-access-list->random-access-list,
;;;                 random-access-list->linear-access-list
;;;   Improper:     dotted pairs, improper lists, length<=? bounds
;;;   Scale:        10,000 elements random-access performance and logarithmic depth
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(test-begin "srfi-101")

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

;; =======================================================================
;; Group 1: Constructors
;; =======================================================================
(write-string "--- Group 1: Constructors ---")
(write-char #\newline)

;; ra-cons
(define p1 (ra-cons 10 '()))
(assert-true "1.1 ra-cons to null" (ra-pair? p1))
(assert-equal "1.2 ra-car of single" (ra-car p1) 10)
(assert-equal "1.3 ra-cdr of single" (ra-cdr p1) '())

(define p2 (ra-cons 20 p1))
(assert-equal "1.4 ra-car p2" (ra-car p2) 20)
(assert-equal "1.5 ra-car cdr p2" (ra-car (ra-cdr p2)) 10)

;; ra-list
(assert-equal "1.6 ra-list empty" (ra-list) '())
(assert-equal "1.7 ra-list 1" (rlist->list (ra-list 1)) '(1))
(assert-equal "1.8 ra-list 2" (rlist->list (ra-list 1 2)) '(1 2))
(assert-equal "1.9 ra-list 3" (rlist->list (ra-list 1 2 3)) '(1 2 3))
(assert-equal "1.10 ra-list 5" (rlist->list (ra-list 1 2 3 4 5)) '(1 2 3 4 5))
(assert-equal "1.11 ra-list 7" (rlist->list (ra-list 1 2 3 4 5 6 7)) '(1 2 3 4 5 6 7))

;; ra-make-list
(assert-equal "1.12 ra-make-list 0" (rlist->list (ra-make-list 0 'x)) '())
(assert-equal "1.13 ra-make-list 1" (rlist->list (ra-make-list 1 'a)) '(a))
(assert-equal "1.14 ra-make-list 4" (rlist->list (ra-make-list 4 'z)) '(z z z z))
(assert-equal "1.15 ra-make-list default fill" (rlist->list (ra-make-list 3)) '(0 0 0))

;; ra-quote
(define q-ls (ra-quote (a b c)))
(assert-true "1.16 ra-quote pair?" (ra-pair? q-ls))
(assert-equal "1.17 ra-quote elements" (rlist->list q-ls) '(a b c))

;; =======================================================================
;; Group 2: Predicates
;; =======================================================================
(write-string "--- Group 2: Predicates ---")
(write-char #\newline)

;; ra-null?
(assert-true "2.1 ra-null? empty" (ra-null? '()))
(assert-false "2.2 ra-null? pair" (ra-null? p1))
(assert-false "2.3 ra-null? symbol" (ra-null? 'foo))

;; ra-pair?
(assert-true "2.4 ra-pair? on ra-cons" (ra-pair? (ra-cons 1 2)))
(assert-false "2.5 ra-pair? on empty" (ra-pair? '()))
(assert-false "2.6 ra-pair? on vector" (ra-pair? (vector 1 2 3 4)))
(assert-false "2.7 ra-pair? on integer" (ra-pair? 42))

;; ra-list?
(assert-true "2.8 ra-list? empty" (ra-list? '()))
(assert-true "2.9 ra-list? proper 3" (ra-list? (ra-list 1 2 3)))
(assert-false "2.10 ra-list? dotted pair" (ra-list? (ra-cons 1 2)))
(assert-false "2.11 ra-list? improper list" (ra-list? (ra-cons 1 (ra-cons 2 3))))
(assert-false "2.12 ra-list? non-list" (ra-list? 'hello))

;; ra-length<=?
(assert-true "2.13 length<=? non-list 0" (ra-length<=? 'not-a-list 0))
(assert-false "2.14 length<=? non-list 1" (ra-length<=? 'not-a-list 1))
(assert-true "2.15 length<=? dotted 0" (ra-length<=? (ra-cons 'a 'b) 0))
(assert-true "2.16 length<=? dotted 1" (ra-length<=? (ra-cons 'a 'b) 1))
(assert-false "2.17 length<=? dotted 2" (ra-length<=? (ra-cons 'a 'b) 2))

(define l5 (ra-list 10 20 30 40 50))
(assert-true "2.18 length<=? l5 0" (ra-length<=? l5 0))
(assert-true "2.19 length<=? l5 3" (ra-length<=? l5 3))
(assert-true "2.20 length<=? l5 5" (ra-length<=? l5 5))
(assert-false "2.21 length<=? l5 6" (ra-length<=? l5 6))

;; =======================================================================
;; Group 3: Selectors & Composite Accessors
;; =======================================================================
(write-string "--- Group 3: Selectors ---")
(write-char #\newline)

;; ra-car+cdr
(call-with-values
  (lambda () (ra-car+cdr (ra-list 100 200)))
  (lambda (a d)
    (assert-equal "3.1 ra-car+cdr head" a 100)
    (assert-equal "3.2 ra-car+cdr tail" (rlist->list d) '(200))))

;; 2-level cxr
(define tree-2 (ra-list (ra-list 1 2) (ra-list 3 4)))
(assert-equal "3.3 ra-caar" (ra-caar tree-2) 1)
(assert-equal "3.4 ra-cadar" (ra-cadar tree-2) 2)
(assert-equal "3.5 ra-caadr" (ra-caadr tree-2) 3)
(assert-equal "3.6 ra-cddr" (ra-cddr tree-2) '())

;; 3-level and 4-level cxr
(define nested-tree
  (ra-cons (ra-cons (ra-cons (ra-cons 'x 'y) 'z) 'w) 'v))
(assert-equal "3.7 ra-caaaar" (ra-caaaar nested-tree) 'x)
(assert-equal "3.8 ra-cdaaar" (ra-cdaaar nested-tree) 'y)
(assert-equal "3.9 ra-cdaar" (ra-cdaar nested-tree) 'z)
(assert-equal "3.10 ra-cdar" (ra-cdar nested-tree) 'w)
(assert-equal "3.11 ra-cdr" (ra-cdr nested-tree) 'v)

(define linear-4 (ra-list 'a 'b 'c 'd))
(assert-equal "3.12 ra-cadddr" (ra-cadddr linear-4) 'd)
(assert-equal "3.13 ra-cddddr" (ra-cddddr linear-4) '())

;; ra-list-ref (O(log n))
(define seq-7 (ra-list 0 1 2 3 4 5 6))
(assert-equal "3.14 list-ref 0" (ra-list-ref seq-7 0) 0)
(assert-equal "3.15 list-ref 1" (ra-list-ref seq-7 1) 1)
(assert-equal "3.16 list-ref 2" (ra-list-ref seq-7 2) 2)
(assert-equal "3.17 list-ref 3" (ra-list-ref seq-7 3) 3)
(assert-equal "3.18 list-ref 4" (ra-list-ref seq-7 4) 4)
(assert-equal "3.19 list-ref 5" (ra-list-ref seq-7 5) 5)
(assert-equal "3.20 list-ref 6" (ra-list-ref seq-7 6) 6)

;; ra-list-tail (O(log n))
(assert-equal "3.21 list-tail 0" (rlist->list (ra-list-tail seq-7 0)) '(0 1 2 3 4 5 6))
(assert-equal "3.22 list-tail 1" (rlist->list (ra-list-tail seq-7 1)) '(1 2 3 4 5 6))
(assert-equal "3.23 list-tail 3" (rlist->list (ra-list-tail seq-7 3)) '(3 4 5 6))
(assert-equal "3.24 list-tail 7" (rlist->list (ra-list-tail seq-7 7)) '())

;; =======================================================================
;; Group 4: Purely Functional Updaters (O(log n))
;; =======================================================================
(write-string "--- Group 4: Updaters ---")
(write-char #\newline)

;; ra-list-set
(define orig-ls (ra-list 10 20 30 40 50 60 70))
(define mod-ls (ra-list-set orig-ls 3 999))

;; Verify immutability of original
(assert-equal "4.1 orig-ls unchanged" (rlist->list orig-ls) '(10 20 30 40 50 60 70))
;; Verify update in mod-ls
(assert-equal "4.2 mod-ls updated" (rlist->list mod-ls) '(10 20 30 999 50 60 70))

;; Update head and tail
(define mod-head (ra-list-set orig-ls 0 111))
(define mod-tail (ra-list-set orig-ls 6 777))
(assert-equal "4.3 mod-head" (rlist->list mod-head) '(111 20 30 40 50 60 70))
(assert-equal "4.4 mod-tail" (rlist->list mod-tail) '(10 20 30 40 50 60 777))

;; ra-list-ref/update
(define negate (lambda (x) (- 0 x)))
(call-with-values
  (lambda () (ra-list-ref/update (ra-list 7 8 9 10) 2 negate))
  (lambda (old-val new-list)
    (assert-equal "4.5 ref/update old-val" old-val 9)
    (assert-equal "4.6 ref/update new-list" (rlist->list new-list) '(7 8 -9 10))))

;; =======================================================================
;; Group 5: Iteration & Higher-Order Procedures
;; =======================================================================
(write-string "--- Group 5: Iteration ---")
(write-char #\newline)

;; ra-length (O(log n))
(assert-equal "5.1 length empty" (ra-length '()) 0)
(assert-equal "5.2 length 1" (ra-length (ra-list 1)) 1)
(assert-equal "5.3 length 7" (ra-length seq-7) 7)

;; ra-append
(assert-equal "5.4 append 0" (ra-append) '())
(assert-equal "5.5 append 1" (rlist->list (ra-append (ra-list 1 2))) '(1 2))
(assert-equal "5.6 append 2" (rlist->list (ra-append (ra-list 1 2) (ra-list 3 4))) '(1 2 3 4))
(assert-equal "5.7 append 3" (rlist->list (ra-append (ra-list 1) (ra-list 2 3) (ra-list 4 5))) '(1 2 3 4 5))

;; ra-reverse
(assert-equal "5.8 reverse empty" (ra-reverse '()) '())
(assert-equal "5.9 reverse single" (rlist->list (ra-reverse (ra-list 'a))) '(a))
(assert-equal "5.10 reverse 5" (rlist->list (ra-reverse (ra-list 1 2 3 4 5))) '(5 4 3 2 1))

;; ra-map
(define sq (lambda (x) (* x x)))
(assert-equal "5.11 map unary" (rlist->list (ra-map sq (ra-list 1 2 3 4))) '(1 4 9 16))

(define plus (lambda (a b) (+ a b)))
(assert-equal "5.12 map binary" (rlist->list (ra-map plus (ra-list 1 2 3) (ra-list 10 20 30))) '(11 22 33))

(define mult3 (lambda (a b c) (* (* a b) c)))
(assert-equal "5.13 map ternary" (rlist->list (ra-map mult3 (ra-list 1 2) (ra-list 3 4) (ra-list 5 6))) '(15 48))

;; ra-for-each
(let ((sum-box (vector 0)))
  (ra-for-each (lambda (x) (vector-set! sum-box 0 (+ (vector-ref sum-box 0) x)))
               (ra-list 10 20 30))
  (assert-equal "5.14 for-each unary" (vector-ref sum-box 0) 60))

(let ((pairs-box (vector '())))
  (ra-for-each (lambda (a b)
                 (vector-set! pairs-box 0 (cons (cons a b) (vector-ref pairs-box 0))))
               (ra-list 1 2) (ra-list 'a 'b))
  (assert-equal "5.15 for-each binary" (reverse (vector-ref pairs-box 0)) '((1 . a) (2 . b))))

;; =======================================================================
;; Group 6: Conversion & Interoperability
;; =======================================================================
(write-string "--- Group 6: Conversion ---")
(write-char #\newline)

(define test-lst '(10 20 30 40 50 60 70 80 90 100))
(define converted-rl (list->rlist test-lst))
(assert-true "6.1 list->rlist is ra-pair" (ra-pair? converted-rl))
(assert-equal "6.2 rlist->list roundtrip" (rlist->list converted-rl) test-lst)
(assert-equal "6.3 linear-access-list->random-access-list"
  (random-access-list->linear-access-list (linear-access-list->random-access-list '(a b c)))
  '(a b c))

;; =======================================================================
;; Group 7: Improper Lists & Edge Cases
;; =======================================================================
(write-string "--- Group 7: Improper Lists ---")
(write-char #\newline)

(define dot-pair (ra-cons 'foo 'bar))
(assert-true "7.1 dotted pair is ra-pair?" (ra-pair? dot-pair))
(assert-equal "7.2 dotted car" (ra-car dot-pair) 'foo)
(assert-equal "7.3 dotted cdr" (ra-cdr dot-pair) 'bar)
(assert-false "7.4 dotted is not ra-list?" (ra-list? dot-pair))

;; =======================================================================
;; Group 8: Scale & Algorithmic Complexity (10,000 Elements)
;; =======================================================================
(write-string "--- Group 8: Scale (10,000 Elements) ---")
(write-char #\newline)

;; Construct 10,000 element random-access list
(define big-rl
  (let loop ((i 10000) (acc '()))
    (if (<= i 0)
        acc
        (loop (- i 1) (ra-cons (- i 1) acc)))))

(assert-equal "8.1 big-rl length" (ra-length big-rl) 10000)
(assert-true "8.2 big-rl is ra-list?" (ra-list? big-rl))

;; Random access in O(log n)
(assert-equal "8.3 ref index 0" (ra-list-ref big-rl 0) 0)
(assert-equal "8.4 ref index 1" (ra-list-ref big-rl 1) 1)
(assert-equal "8.5 ref index 500" (ra-list-ref big-rl 500) 500)
(assert-equal "8.6 ref index 4999" (ra-list-ref big-rl 4999) 4999)
(assert-equal "8.7 ref index 5000" (ra-list-ref big-rl 5000) 5000)
(assert-equal "8.8 ref index 9998" (ra-list-ref big-rl 9998) 9998)
(assert-equal "8.9 ref index 9999" (ra-list-ref big-rl 9999) 9999)

;; Functional update in O(log n)
(define big-updated (ra-list-set big-rl 5000 888888))
(assert-equal "8.10 big-rl original unmodified" (ra-list-ref big-rl 5000) 5000)
(assert-equal "8.11 big-updated element updated" (ra-list-ref big-updated 5000) 888888)
(assert-equal "8.12 big-updated neighbor unaffected" (ra-list-ref big-updated 5001) 5001)

;; list-tail in O(log n)
(define tail-half (ra-list-tail big-rl 5000))
(assert-equal "8.13 tail-half length" (ra-length tail-half) 5000)
(assert-equal "8.14 tail-half head" (ra-car tail-half) 5000)

;; length<=? in O(log(min(k,n)))
(assert-true "8.15 length<=? 0" (ra-length<=? big-rl 0))
(assert-true "8.16 length<=? 5000" (ra-length<=? big-rl 5000))
(assert-true "8.17 length<=? 10000" (ra-length<=? big-rl 10000))
(assert-false "8.18 length<=? 10001" (ra-length<=? big-rl 10001))

(test-end "srfi-101")
