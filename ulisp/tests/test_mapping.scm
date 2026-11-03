;;; =======================================================================
;;; ULisp Test Suite: SRFI 146 (scheme mapping) & (scheme mapping hash)
;;; Conforms to DSN-33 Architecture Specification & Issue #709
;;; =======================================================================

(define *pass-count* (cons 0 '()))

(define (assert-equal name expected actual)
  (set-car! *pass-count* (+ (car *pass-count*) 1))
  (if (equal? expected actual)
      (begin
        (display "  [PASS] ")
        (display name)
        (newline)
        (flush-output-port))
      (begin
        (display "  [FAIL] ")
        (display name)
        (display " | expected: ")
        (write expected)
        (display " | actual: ")
        (write actual)
        (newline)
        (flush-output-port)
        (exit 1))))

(display "=============================================================\n")
(display " Starting SRFI 146 (scheme mapping & hash) Test Suite\n")
(display "=============================================================\n")

(define num-comp (make-default-comparator))

;; ---------------------------------------------------------------------
;; 1. Ordered Mapping: Constructors, Predicates & Accessors
;; ---------------------------------------------------------------------
(display "--- 1. Ordered Mapping Constructors, Predicates & Accessors ---\n")

(define m0 (mapping num-comp))
(assert-equal "mapping? on empty" #t (mapping? m0))
(assert-equal "mapping? on list" #f (mapping? '(1 2)))
(assert-equal "mapping-empty? on empty" #t (mapping-empty? m0))

(define m1 (mapping-adjoin (mapping num-comp 30 "c" 10 "a") 20 "b" 10 "dup"))
(assert-equal "mapping-size deduplicates & orders" 3 (mapping-size m1))
(assert-equal "mapping-keys sorted" '(10 20 30) (mapping-keys m1))
(assert-equal "mapping-values in key order (first wins)" '("a" "b" "c") (mapping-values m1))
(assert-equal "mapping-contains? 20" #t (mapping-contains? m1 20))
(assert-equal "mapping-contains? 99" #f (mapping-contains? m1 99))
(assert-equal "mapping-ref 20" "b" (mapping-ref m1 20))
(assert-equal "mapping-ref missing with failure" 'missing (mapping-ref m1 99 (lambda () 'missing)))
(assert-equal "mapping-ref with success" '("a") (mapping-ref m1 10 (lambda () #f) list))
(assert-equal "mapping-ref/default present" "c" (mapping-ref/default m1 30 "def"))
(assert-equal "mapping-ref/default absent" "def" (mapping-ref/default m1 99 "def"))

;; ---------------------------------------------------------------------
;; 2. Ordered Mapping: Updaters, Search & Pop
;; ---------------------------------------------------------------------
(display "--- 2. Ordered Mapping Updaters, Search & Pop ---\n")

(define m2 (mapping-set m1 20 "B" 40 "d"))
(assert-equal "mapping-set overwrites & inserts" '("a" "B" "c" "d") (mapping-values m2))
(assert-equal "original m1 unchanged" '("a" "b" "c") (mapping-values m1))

(define m3 (mapping-replace m1 20 "BB" 99 "ZZ"))
(assert-equal "mapping-replace only updates existing" '((10 . "a") (20 . "BB") (30 . "c")) (mapping->alist m3))

(define m4 (mapping-delete m2 10 30))
(assert-equal "mapping-delete removes keys" '((20 . "B") (40 . "d")) (mapping->alist m4))

(define m5 (mapping-update/default m1 50 (lambda (x) (+ x 1)) 100))
(assert-equal "mapping-update/default" 101 (mapping-ref m5 50))

(call-with-values
  (lambda () (mapping-intern m1 25 (lambda () "twenty-five")))
  (lambda (m-int val)
    (assert-equal "mapping-intern value" "twenty-five" val)
    (assert-equal "mapping-intern size" 4 (mapping-size m-int))))

(call-with-values
  (lambda () (mapping-pop m1))
  (lambda (m-rest k v)
    (assert-equal "mapping-pop min key" 10 k)
    (assert-equal "mapping-pop min val" "a" v)
    (assert-equal "mapping-pop rest keys" '(20 30) (mapping-keys m-rest))))

(call-with-values
  (lambda ()
    (mapping-search m1 15
      (lambda (insert ignore) (insert "fifteen" 'inserted))
      (lambda (k v update remove) (remove 'removed))))
  (lambda (m-searched tag)
    (assert-equal "mapping-search insert tag" 'inserted tag)
    (assert-equal "mapping-search inserted key order" '(10 15 20 30) (mapping-keys m-searched))))

;; ---------------------------------------------------------------------
;; 3. Ordered Mapping: Fold, Filter, Partition, Set Operations & Ranges
;; ---------------------------------------------------------------------
(display "--- 3. Ordered Mapping Fold, Filter, Set Ops & Ranges ---\n")

(assert-equal "mapping-fold keys" '(30 20 10)
              (mapping-fold (lambda (k v acc) (cons k acc)) '() m1))
(assert-equal "mapping-fold/reverse keys" '(10 20 30)
              (mapping-fold/reverse (lambda (k v acc) (cons k acc)) '() m1))

(assert-equal "mapping-count" 2
              (mapping-count (lambda (k v) (>= k 20)) m1))

(call-with-values
  (lambda () (mapping-partition (lambda (k v) (<= k 20)) m2))
  (lambda (m-in m-out)
    (assert-equal "mapping-partition in" '(10 20) (mapping-keys m-in))
    (assert-equal "mapping-partition out" '(30 40) (mapping-keys m-out))))

(define ma (alist->mapping num-comp '((1 . a) (2 . b) (3 . c))))
(define mb (alist->mapping num-comp '((2 . B) (3 . c) (4 . d))))
(assert-equal "mapping-union prefers first" '((1 . a) (2 . b) (3 . c) (4 . d))
              (mapping->alist (mapping-union ma mb)))
(assert-equal "mapping-intersection" '((2 . b) (3 . c))
              (mapping->alist (mapping-intersection ma mb)))
(assert-equal "mapping-difference" '((1 . a))
              (mapping->alist (mapping-difference ma mb)))
(assert-equal "mapping-xor" '((1 . a) (4 . d))
              (mapping->alist (mapping-xor ma mb)))

(assert-equal "mapping-min-key" 10 (mapping-min-key m2))
(assert-equal "mapping-max-key" 40 (mapping-max-key m2))
(assert-equal "mapping-key-predecessor of 25" 20 (mapping-key-predecessor m2 25 (lambda () #f)))
(assert-equal "mapping-key-successor of 20" 30 (mapping-key-successor m2 20 (lambda () #f)))

(call-with-values
  (lambda () (mapping-split m2 20))
  (lambda (lt le eq ge gt)
    (assert-equal "mapping-split <" '(10) (mapping-keys lt))
    (assert-equal "mapping-split <=" '(10 20) (mapping-keys le))
    (assert-equal "mapping-split =" '(20) (mapping-keys eq))
    (assert-equal "mapping-split >=" '(20 30 40) (mapping-keys ge))
    (assert-equal "mapping-split >" '(30 40) (mapping-keys gt))))

(assert-equal "mapping=? equal" #t
              (mapping=? num-comp (mapping num-comp 1 10 2 20) (mapping num-comp 2 20 1 10)))
(assert-equal "mapping<? proper submapping" #t
              (mapping<? num-comp (mapping num-comp 1 10) (mapping num-comp 1 10 2 20)))

;; ---------------------------------------------------------------------
;; 4. Hash Mappings: (scheme mapping hash) / (srfi 146 hash)
;; ---------------------------------------------------------------------
(display "--- 4. Hash Mappings (scheme mapping hash) ---\n")

(define hm0 (hashmap num-comp))
(assert-equal "hashmap? on empty" #t (hashmap? hm0))
(assert-equal "hashmap-empty? on empty" #t (hashmap-empty? hm0))

(define hm1 (hashmap-adjoin (hashmap num-comp 'x 100 'y 200) 'z 300 'x 999))
(assert-equal "hashmap-size deduplicates" 3 (hashmap-size hm1))
(assert-equal "hashmap-ref x (first wins)" 100 (hashmap-ref hm1 'x))
(assert-equal "hashmap-contains? y" #t (hashmap-contains? hm1 'y))
(assert-equal "hashmap-contains? w" #f (hashmap-contains? hm1 'w))

(define hm2 (hashmap-set hm1 'y 250 'w 400))
(assert-equal "hashmap-set updates y" 250 (hashmap-ref hm2 'y))
(assert-equal "hashmap-set adds w" 400 (hashmap-ref hm2 'w))
(assert-equal "hashmap-delete removes x y" 2 (hashmap-size (hashmap-delete hm2 'x 'y)))

(define hma (alist->hashmap num-comp '((a . 1) (b . 2))))
(define hmb (alist->hashmap num-comp '((b . 2) (a . 1))))
(assert-equal "hashmap=? order-independent" #t (hashmap=? num-comp hma hmb))
(assert-equal "hashmap-comparator =?" #t (=? hashmap-comparator hma hmb))
(assert-equal "hashmap-comparator hash equal"
              (comparator-hash hashmap-comparator hma)
              (comparator-hash hashmap-comparator hmb))

(display "=============================================================\n")
(display " All ")
(display (car *pass-count*))
(display " SRFI 146 (scheme mapping & hash) Tests Passed Successfully!\n")
(display "=============================================================\n")

