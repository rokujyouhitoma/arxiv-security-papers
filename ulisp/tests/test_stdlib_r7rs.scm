;;; =======================================================================
;;; ULisp Comprehensive R7RS Standard Library Test Suite
;;; Covers R7RS Section 6.4 (Lists), 6.7 (Strings), 6.8 (Vectors), 6.9 (Bytevectors)
;;; Conforms to Issue #551
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
  (write-char #\newline)
  (flush-output-port))

(define (test-equal? a b)
  (cond
    ((eqv? a b) #t)
    ((and (pair? a) (pair? b))
     (and (test-equal? (car a) (car b))
          (test-equal? (cdr a) (cdr b))))
    ((and (string? a) (string? b))
     (string=? a b))
    ((and (vector? a) (vector? b))
     (let ((la (vector-length a))
           (lb (vector-length b)))
       (if (= la lb)
           (let loop ((i 0))
             (if (= i la)
                 #t
                 (if (test-equal? (vector-ref a i) (vector-ref b i))
                     (loop (+ i 1))
                     #f)))
           #f)))
    ((and (bytevector? a) (bytevector? b))
     (bytevector=? a b))
    (else #f)))

(define (assert-true name expr)
  (if expr
      (test-pass name)
      (test-fail name "#t" "#f")))

(define (assert-equal name expected actual)
  (if (test-equal? expected actual)
      (test-pass name)
      (test-fail name expected actual)))

(define (assert-num-equal name expected actual)
  (if (= expected actual)
      (test-pass name)
      (test-fail name expected actual)))

(write-string "=== Running ULisp R7RS Standard Library Sequence Tests (Issue #551) ===")
(write-char #\newline)
(flush-output-port)

;;; =======================================================================
;;; 1. List Operations (R7RS Section 6.4)
;;; =======================================================================
(write-string "--- 1. List Procedures ---")
(write-char #\newline)
(flush-output-port)

(assert-equal "list-copy empty" '() (list-copy '()))
(assert-equal "list-copy non-pair" 42 (list-copy 42))
(assert-equal "list-copy proper list" '(1 2 3) (list-copy '(1 2 3)))

;; Verify list-copy produces a shallow distinct spine
(let* ((orig (list 1 2 3))
       (cp (list-copy orig)))
  (set-car! cp 99)
  (assert-equal "list-copy spine mutation independence (copy)" '(99 2 3) cp)
  (assert-equal "list-copy spine mutation independence (orig)" '(1 2 3) orig))

(assert-equal "make-list 0" '() (make-list 0))
(assert-equal "make-list 3 fill 'a" '(a a a) (make-list 3 'a))
(assert-equal "make-list 2 default fill #f" '(#f #f) (make-list 2))

;; list-tail tests
(assert-equal "list-tail 0" '(a b c) (list-tail '(a b c) 0))
(assert-equal "list-tail 1" '(b c) (list-tail '(a b c) 1))
(assert-equal "list-tail 3 (end of list)" '() (list-tail '(a b c) 3))

;; list-ref tests
(assert-equal "list-ref 0" 'a (list-ref '(a b c) 0))
(assert-equal "list-ref 1" 'b (list-ref '(a b c) 1))
(assert-equal "list-ref 2" 'c (list-ref '(a b c) 2))

;; list-set! tests
(let ((lst (list 'x 'y 'z)))
  (list-set! lst 0 'first)
  (assert-equal "list-set! index 0" '(first y z) lst)
  (list-set! lst 1 'second)
  (assert-equal "list-set! index 1" '(first second z) lst)
  (list-set! lst 2 'third)
  (assert-equal "list-set! index 2" '(first second third) lst))

;;; =======================================================================
;;; 2. String Operations (R7RS Section 6.7)
;;; =======================================================================
(write-string "--- 2. String Procedures ---")
(write-char #\newline)
(flush-output-port)

(assert-equal "string-copy full" "hello" (string-copy "hello"))
(assert-equal "string-copy with start" "world" (string-copy "hello world" 6))
(assert-equal "string-copy with start and end" "hello" (string-copy "hello world" 0 5))

;; string-copy! distinct strings
(let ((to (string-copy "abcdef")))
  (string-copy! to 1 "XYZ")
  (assert-equal "string-copy! distinct strings" "aXYZef" to))

(let ((to (string-copy "abcdef")))
  (string-copy! to 1 "WXYZ" 1 3)
  (assert-equal "string-copy! distinct with slice" "aXYdef" to))

;; string-copy! overlapping regions (backward copy when at > start)
(let ((s (string-copy "abcdef")))
  (string-copy! s 2 s 0 3)
  (assert-equal "string-copy! overlap backward copy (at > start)" "ababcf" s))

;; string-copy! overlapping regions (forward copy when at < start)
(let ((s (string-copy "abcdef")))
  (string-copy! s 0 s 2 5)
  (assert-equal "string-copy! overlap forward copy (at < start)" "cdedef" s))

;; string-fill!
(let ((s (string-copy "hello")))
  (string-fill! s #\x)
  (assert-equal "string-fill! full" "xxxxx" s))

(let ((s (string-copy "hello")))
  (string-fill! s #\x 1 4)
  (assert-equal "string-fill! range" "hxxxo" s))

;; string-map
(assert-equal "string-map replace char" "bAnAnA"
              (string-map (lambda (c) (if (char=? c #\a) #\A c)) "banana"))

;; string-for-each
(let ((cnt (vector 0)))
  (string-for-each (lambda (c) (vector-set! cnt 0 (+ (vector-ref cnt 0) 1))) "12345")
  (assert-num-equal "string-for-each counter" 5 (vector-ref cnt 0)))

;;; =======================================================================
;;; 3. Vector Operations (R7RS Section 6.8)
;;; =======================================================================
(write-string "--- 3. Vector Procedures ---")
(write-char #\newline)
(flush-output-port)

(assert-equal "vector-copy full" (vector 10 20 30) (vector-copy (vector 10 20 30)))
(assert-equal "vector-copy slice" (vector 20 30) (vector-copy (vector 10 20 30 40) 1 3))

;; vector-copy! distinct
(let ((to (vector 0 0 0 0 0))
      (from (vector 1 2 3)))
  (vector-copy! to 1 from)
  (assert-equal "vector-copy! distinct" (vector 0 1 2 3 0) to))

;; vector-copy! overlap backward copy (at > start)
(let ((v (vector 1 2 3 4 5)))
  (vector-copy! v 2 v 0 3)
  (assert-equal "vector-copy! overlap backward (at > start)" (vector 1 2 1 2 3) v))

;; vector-copy! overlap forward copy (at < start)
(let ((v (vector 1 2 3 4 5)))
  (vector-copy! v 0 v 2 5)
  (assert-equal "vector-copy! overlap forward (at < start)" (vector 3 4 5 4 5) v))

;; vector-append
(assert-equal "vector-append 2 vectors" (vector 1 2 3 4) (vector-append (vector 1 2) (vector 3 4)))

;; vector->list & list->vector
(assert-equal "vector->list full" '(10 20 30) (vector->list (vector 10 20 30)))
(assert-equal "vector->list slice" '(20 30) (vector->list (vector 10 20 30 40) 1 3))
(assert-equal "list->vector" (vector 1 2 3) (list->vector '(1 2 3)))

;; vector-fill!
(let ((v (vector 1 2 3 4 5)))
  (vector-fill! v 9 1 4)
  (assert-equal "vector-fill! range" (vector 1 9 9 9 5) v))

;; vector-map
(assert-equal "vector-map double" (vector 2 4 6)
              (vector-map (lambda (x) (* x 2)) (vector 1 2 3)))

;; vector-for-each
(let ((acc (vector 0)))
  (vector-for-each (lambda (x) (vector-set! acc 0 (+ (vector-ref acc 0) x))) (vector 10 20 30))
  (assert-num-equal "vector-for-each sum" 60 (vector-ref acc 0)))

;;; =======================================================================
;;; 4. Bytevector Operations (R7RS Section 6.9)
;;; =======================================================================
(write-string "--- 4. Bytevector Procedures ---")
(write-char #\newline)
(flush-output-port)

(assert-equal "bytevector-copy full" (bytevector 10 20 30) (bytevector-copy (bytevector 10 20 30)))
(assert-equal "bytevector-copy slice" (bytevector 20 30) (bytevector-copy (bytevector 10 20 30 40) 1 3))

;; bytevector-copy! distinct
(let ((to (make-bytevector 5 0))
      (from (bytevector 1 2 3)))
  (bytevector-copy! to 1 from)
  (assert-equal "bytevector-copy! distinct" (bytevector 0 1 2 3 0) to))

;; bytevector-copy! overlap backward copy (at > start)
(let ((bv (bytevector 1 2 3 4 5)))
  (bytevector-copy! bv 2 bv 0 3)
  (assert-equal "bytevector-copy! overlap backward (at > start)" (bytevector 1 2 1 2 3) bv))

;; bytevector-copy! overlap forward copy (at < start)
(let ((bv (bytevector 1 2 3 4 5)))
  (bytevector-copy! bv 0 bv 2 5)
  (assert-equal "bytevector-copy! overlap forward (at < start)" (bytevector 3 4 5 4 5) bv))

;; bytevector-append
(assert-equal "bytevector-append 2 bvs" (bytevector 1 2 3 4) (bytevector-append (bytevector 1 2) (bytevector 3 4)))

;;; =======================================================================
;;; 5. Character Comparison Operations (R7RS Section 6.6)
;;; =======================================================================
(write-string "--- 5. Character Comparison Procedures ---")
(write-char #\newline)
(flush-output-port)

;; char<? tests (2 arguments & chained)
(assert-equal "char<? 2 args true" #t (char<? #\a #\b))
(assert-equal "char<? 2 args false" #f (char<? #\b #\a))
(assert-equal "char<? 2 args equal false" #f (char<? #\a #\a))
(assert-equal "char<? uppercase < lowercase" #t (char<? #\A #\a))
(assert-equal "char<? 3 args chain true" #t (char<? #\a #\b #\c))
(assert-equal "char<? 4 args chain true" #t (char<? #\a #\b #\c #\d))
(assert-equal "char<? 3 args chain false (unordered)" #f (char<? #\a #\c #\b))
(assert-equal "char<? 3 args chain false (duplicate)" #f (char<? #\a #\b #\b))

;; char>? tests (2 arguments & chained)
(assert-equal "char>? 2 args true" #t (char>? #\z #\a))
(assert-equal "char>? 2 args false" #f (char>? #\a #\z))
(assert-equal "char>? 2 args equal false" #f (char>? #\z #\z))
(assert-equal "char>? 3 args chain true" #t (char>? #\z #\y #\x))
(assert-equal "char>? 3 args chain false (unordered)" #f (char>? #\z #\x #\y))
(assert-equal "char>? 3 args chain false (duplicate)" #f (char>? #\z #\y #\y))

;; char<=? tests (2 arguments & chained)
(assert-equal "char<=? 2 args less true" #t (char<=? #\a #\b))
(assert-equal "char<=? 2 args equal true" #t (char<=? #\a #\a))
(assert-equal "char<=? 2 args greater false" #f (char<=? #\b #\a))
(assert-equal "char<=? 3 args chain true" #t (char<=? #\a #\b #\c))
(assert-equal "char<=? 4 args chain with duplicate true" #t (char<=? #\a #\b #\b #\c))
(assert-equal "char<=? 3 args chain false" #f (char<=? #\a #\c #\b))

;; char>=? tests (2 arguments & chained)
(assert-equal "char>=? 2 args greater true" #t (char>=? #\b #\a))
(assert-equal "char>=? 2 args equal true" #t (char>=? #\a #\a))
(assert-equal "char>=? 2 args less false" #f (char>=? #\a #\b))
(assert-equal "char>=? 3 args chain true" #t (char>=? #\c #\b #\a))
(assert-equal "char>=? 4 args chain with duplicate true" #t (char>=? #\c #\b #\b #\a))
(assert-equal "char>=? 3 args chain false" #f (char>=? #\b #\c #\a))

;;; Summary
(write-string "=== ULisp R7RS Standard Library Tests Completed: ")
(if (= (vector-ref *test-failures* 0) 0)
    (begin
      (write-string "ALL TESTS PASSED ===")
      (write-char #\newline)
      (flush-output-port)
      #t)
    (begin
      (write-string "FAILURES ENCOUNTERED ===")
      (write-char #\newline)
      (flush-output-port)
      #f))
