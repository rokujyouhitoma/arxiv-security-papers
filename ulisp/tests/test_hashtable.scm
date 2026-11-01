;;; =======================================================================
;;; ULisp Test Suite: Hash Tables (SRFI 69 / SRFI 125 / scheme hash-table)
;;; Conforms to DSN-33 Architecture Specification, Issue #649
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(define *test-failures* (vector 0))
(define *test-passes* (vector 0))

(define (assert-true desc expr)
  (if expr
      (begin
        (vector-set! *test-passes* 0 (+ (vector-ref *test-passes* 0) 1))
        (write-string "  [PASS] ") (write-string desc) (write-char #\newline)
        (flush-output-port))
      (begin
        (vector-set! *test-failures* 0 (+ (vector-ref *test-failures* 0) 1))
        (write-string "  [FAIL] ") (write-string desc)
        (write-string " => expected #t, got #f") (write-char #\newline)
        (flush-output-port))))

(define (assert-false desc expr)
  (if (not expr)
      (begin
        (vector-set! *test-passes* 0 (+ (vector-ref *test-passes* 0) 1))
        (write-string "  [PASS] ") (write-string desc) (write-char #\newline)
        (flush-output-port))
      (begin
        (vector-set! *test-failures* 0 (+ (vector-ref *test-failures* 0) 1))
        (write-string "  [FAIL] ") (write-string desc)
        (write-string " => expected #f, got truthy") (write-char #\newline)
        (flush-output-port))))

(define (assert-equal desc expected actual)
  (if (equal? expected actual)
      (begin
        (vector-set! *test-passes* 0 (+ (vector-ref *test-passes* 0) 1))
        (write-string "  [PASS] ") (write-string desc) (write-char #\newline)
        (flush-output-port))
      (begin
        (vector-set! *test-failures* 0 (+ (vector-ref *test-failures* 0) 1))
        (write-string "  [FAIL] ") (write-string desc)
        (write-string " => expected: ") (write expected)
        (write-string ", got: ") (write actual) (write-char #\newline)
        (flush-output-port))))

;; First-class function wrappers
(define (num= a b) (= a b))
(define (str= a b) (string=? a b))
(define (sym= a b) (eq? a b))
(define (add-val k v acc) (+ v acc))
(define (double-val k v) (* v 2))

(write-string "=======================================================") (write-char #\newline)
(write-string " Starting R7RS Hash Table (SRFI 69 / 125) Test Suite   ") (write-char #\newline)
(write-string "=======================================================") (write-char #\newline)
(flush-output-port)

;; ---------------------------------------------------------------------
;; Group 1: Constructors & Type Predicates
;; ---------------------------------------------------------------------
(write-string "--- Group 1: Constructors & Type Predicates ---") (write-char #\newline)

(let ((ht (make-hash-table)))
  (assert-true "make-hash-table returns hash-table" (hash-table? ht))
  (assert-false "vector is not hash-table" (hash-table? #(1 2 3)))
  (assert-false "number is not hash-table" (hash-table? 42))
  (assert-true "new hash-table is empty" (hash-table-empty? ht))
  (assert-equal "new hash-table size is 0" 0 (hash-table-size ht)))

(let ((ht (make-hash-table str= string-hash 16)))
  (assert-true "make-hash-table with custom eq/hash" (hash-table? ht))
  (assert-equal "size is 0" 0 (hash-table-size ht)))

(let ((ht (alist->hash-table '((a . 1) (b . 2) (c . 3)))))
  (assert-true "alist->hash-table creates table" (hash-table? ht))
  (assert-equal "size is 3" 3 (hash-table-size ht))
  (assert-equal "ref a" 1 (hash-table-ref ht 'a))
  (assert-equal "ref b" 2 (hash-table-ref ht 'b))
  (assert-equal "ref c" 3 (hash-table-ref ht 'c)))

(let ((ht (hash-table 'x 100 'y 200 'z 300)))
  (assert-true "hash-table variable constructor" (hash-table? ht))
  (assert-equal "size is 3" 3 (hash-table-size ht))
  (assert-equal "ref x" 100 (hash-table-ref ht 'x))
  (assert-equal "ref y" 200 (hash-table-ref ht 'y))
  (assert-equal "ref z" 300 (hash-table-ref ht 'z)))

;; ---------------------------------------------------------------------
;; Group 2: Accessors & Mutators (Set, Ref, Delete, Update)
;; ---------------------------------------------------------------------
(write-string "--- Group 2: Accessors & Mutators ---") (write-char #\newline)

(let ((ht (make-hash-table)))
  (hash-table-set! ht "alpha" 10)
  (assert-equal "size after 1 set" 1 (hash-table-size ht))
  (assert-false "not empty" (hash-table-empty? ht))
  (assert-true "contains key alpha" (hash-table-contains? ht "alpha"))
  (assert-true "exists key alpha" (hash-table-exists? ht "alpha"))
  (assert-false "not contains key beta" (hash-table-contains? ht "beta"))
  (assert-equal "ref key alpha" 10 (hash-table-ref ht "alpha"))
  (assert-equal "ref/default key alpha" 10 (hash-table-ref/default ht "alpha" -1))
  (assert-equal "ref/default missing key" -1 (hash-table-ref/default ht "beta" -1))

  ;; Key update / overwrite
  (hash-table-set! ht "alpha" 99)
  (assert-equal "size remains 1 on overwrite" 1 (hash-table-size ht))
  (assert-equal "ref key alpha new val" 99 (hash-table-ref ht "alpha"))

  ;; Multi-arg set!
  (hash-table-set! ht "beta" 20 "gamma" 30)
  (assert-equal "size after multi set" 3 (hash-table-size ht))
  (assert-equal "ref beta" 20 (hash-table-ref ht "beta"))
  (assert-equal "ref gamma" 30 (hash-table-ref ht "gamma"))

  ;; Update! with updater function
  (hash-table-update! ht "beta" (lambda (x) (* x 2)))
  (assert-equal "ref beta after update" 40 (hash-table-ref ht "beta"))

  ;; Update!/default with updater function
  (hash-table-update!/default ht "delta" (lambda (x) (+ x 5)) 100)
  (assert-equal "ref delta after update/default" 105 (hash-table-ref ht "delta"))

  ;; Delete!
  (hash-table-delete! ht "alpha")
  (assert-equal "size after 1 delete" 3 (hash-table-size ht))
  (assert-false "alpha no longer exists" (hash-table-contains? ht "alpha"))
  (assert-equal "ref/default deleted alpha" -1 (hash-table-ref/default ht "alpha" -1))

  ;; Delete non-existent key (no-op)
  (hash-table-delete! ht "non-existent")
  (assert-equal "size unchanged after missing delete" 3 (hash-table-size ht))

  ;; Multi-arg delete!
  (hash-table-delete! ht "beta" "gamma")
  (assert-equal "size after multi delete" 1 (hash-table-size ht))
  (assert-true "delta still exists" (hash-table-contains? ht "delta"))

  ;; Pop!
  (call-with-values
    (lambda () (hash-table-pop! ht))
    (lambda (k v)
      (assert-equal "pop key is delta" "delta" k)
      (assert-equal "pop val is 105" 105 v)))
  (assert-equal "size is 0 after pop" 0 (hash-table-size ht))
  (assert-true "empty after pop" (hash-table-empty? ht)))

;; ---------------------------------------------------------------------
;; Group 3: Whole-Table Operations & Equivalence
;; ---------------------------------------------------------------------
(write-string "--- Group 3: Whole-Table Operations & Equivalence ---") (write-char #\newline)

(let ((ht (alist->hash-table '((10 . "ten") (20 . "twenty") (30 . "thirty")))))
  (assert-equal "size is 3" 3 (hash-table-size ht))
  (let ((ks (hash-table-keys ht))
        (vs (hash-table-values ht)))
    (assert-equal "keys length is 3" 3 (length ks))
    (assert-equal "values length is 3" 3 (length vs))
    (assert-true "10 in keys" (if (memq 10 ks) #t #f))
    (assert-true "20 in keys" (if (memq 20 ks) #t #f))
    (assert-true "30 in keys" (if (memq 30 ks) #t #f)))

  ;; Copy
  (let ((cp (hash-table-copy ht)))
    (assert-equal "copied size is 3" 3 (hash-table-size cp))
    (assert-true "copied contains 10" (hash-table-contains? cp 10))
    (assert-equal "copied val 10" "ten" (hash-table-ref cp 10))
    (hash-table-set! cp 10 "new-ten")
    (assert-equal "original unchanged" "ten" (hash-table-ref ht 10))
    (assert-equal "copy updated" "new-ten" (hash-table-ref cp 10)))

  ;; Clear!
  (hash-table-clear! ht)
  (assert-equal "size 0 after clear" 0 (hash-table-size ht))
  (assert-true "empty after clear" (hash-table-empty? ht))
  (assert-false "contains 10 after clear" (hash-table-contains? ht 10)))

;; Merge!
(let ((h1 (alist->hash-table '((a . 1) (b . 2))))
      (h2 (alist->hash-table '((b . 20) (c . 30)))))
  (hash-table-merge! h1 h2)
  (assert-equal "merged size is 3" 3 (hash-table-size h1))
  (assert-equal "a remains 1" 1 (hash-table-ref h1 'a))
  (assert-equal "b overwritten to 20" 20 (hash-table-ref h1 'b))
  (assert-equal "c added with 30" 30 (hash-table-ref h1 'c)))

;; Hash-table=?
(let ((t1 (alist->hash-table '((x . 1) (y . 2))))
      (t2 (alist->hash-table '((y . 2) (x . 1))))
      (t3 (alist->hash-table '((x . 1) (y . 3))))
      (t4 (alist->hash-table '((x . 1)))))
  (assert-true "t1 = t2" (hash-table=? num= t1 t2))
  (assert-false "t1 != t3 (diff val)" (hash-table=? num= t1 t3))
  (assert-false "t1 != t4 (diff size)" (hash-table=? num= t1 t4)))

;; ---------------------------------------------------------------------
;; Group 4: Iteration & Higher-Order Mapping
;; ---------------------------------------------------------------------
(write-string "--- Group 4: Iteration & Higher-Order Mapping ---") (write-char #\newline)

(let ((ht (alist->hash-table '((a . 10) (b . 20) (c . 30)))))
  ;; Fold
  (let ((sum (hash-table-fold ht add-val 0)))
    (assert-equal "fold sum is 60" 60 sum))

  ;; Map
  (let ((doubled (hash-table-map double-val ht)))
    (assert-equal "doubled size is 3" 3 (hash-table-size doubled))
    (assert-equal "a is 20" 20 (hash-table-ref doubled 'a))
    (assert-equal "b is 40" 40 (hash-table-ref doubled 'b))
    (assert-equal "c is 60" 60 (hash-table-ref doubled 'c)))

  ;; Map->list
  (let ((lst (hash-table-map->list (lambda (k v) v) ht)))
    (assert-equal "map->list length is 3" 3 (length lst))))

;; ---------------------------------------------------------------------
;; Group 5: Hash Functions
;; ---------------------------------------------------------------------
(write-string "--- Group 5: Hash Functions ---") (write-char #\newline)

(assert-true "string-hash is integer" (number? (string-hash "test")))
(assert-equal "string-hash deterministic" (string-hash "hello") (string-hash "hello"))
(assert-true "string-hash with bound" (< (string-hash "hello" 10) 10))
(assert-true "string-hash non-negative" (>= (string-hash "hello" 10) 0))

(assert-equal "string-ci-hash case-insensitive"
              (string-ci-hash "Hello")
              (string-ci-hash "hello"))

(assert-true "symbol-hash is integer" (number? (symbol-hash 'scheme)))
(assert-equal "symbol-hash deterministic" (symbol-hash 'scheme) (symbol-hash 'scheme))

(assert-true "number-hash is integer" (number? (number-hash 12345)))
(assert-equal "number-hash deterministic" (number-hash 42) (number-hash 42))

(assert-true "generic hash integer" (number? (hash '(1 2 3))))
(assert-equal "generic hash pair" (hash '(a . b)) (hash '(a . b)))
(let ((v (vector 1 "a" #t)))
  (assert-equal "generic hash vector" (hash v) (hash v)))

;; ---------------------------------------------------------------------
;; Group 6: Dynamic Rehash & Scale Test (50 Items)
;; ---------------------------------------------------------------------
(write-string "--- Group 6: Dynamic Rehash & Scale Test ---") (write-char #\newline)

(define (verify-scaled-keys ht limit)
  (let loop ((i 0) (ok? #t))
    (if (< i limit)
        (if (hash-table-contains? ht i)
            (if (= (hash-table-ref ht i) (* i 3))
                (loop (+ i 1) ok?)
                #f)
            #f)
        ok?)))

(let ((ht (make-hash-table num= number-hash 8)))
  ;; Insert 50 integer key-value pairs (starts with cap 8, expands dynamically)
  (let loop ((i 0))
    (if (< i 50)
        (begin
          (hash-table-set! ht i (* i 3))
          (loop (+ i 1)))
        #t))
  (assert-equal "size is 50 after scale insert" 50 (hash-table-size ht))

  ;; Verify all 50 keys
  (assert-true "all 50 items verified correctly after dynamic rehash" (verify-scaled-keys ht 50))

  ;; Delete 25 items
  (let loop-del ((i 0))
    (if (< i 25)
        (begin
          (hash-table-delete! ht i)
          (loop-del (+ i 1)))
        #t))
  (assert-equal "size is 25 after 25 deletes" 25 (hash-table-size ht))
  (assert-false "key 0 is deleted" (hash-table-contains? ht 0))
  (assert-false "key 24 is deleted" (hash-table-contains? ht 24))
  (assert-true "key 25 exists" (hash-table-contains? ht 25))
  (assert-equal "key 25 value correct" 75 (hash-table-ref ht 25))
  (assert-true "key 49 exists" (hash-table-contains? ht 49))
  (assert-equal "key 49 value correct" 147 (hash-table-ref ht 49)))

;; ---------------------------------------------------------------------
;; Summary & Final Exit Code
;; ---------------------------------------------------------------------
(write-string "=======================================================") (write-char #\newline)
(write-string " Hash Table Test Suite Summary: ")
(write (vector-ref *test-passes* 0)) (write-string " passed, ")
(write (vector-ref *test-failures* 0)) (write-string " failed.") (write-char #\newline)
(write-string "=======================================================") (write-char #\newline)

(if (> (vector-ref *test-failures* 0) 0)
    (exit 1)
    #t)

