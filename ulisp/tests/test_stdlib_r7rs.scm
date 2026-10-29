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
    ((and (pair? a) (pair? b))
     (and (test-equal? (car a) (car b))
          (test-equal? (cdr a) (cdr b))))
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

;; string->list & list->string
(assert-equal "string->list full" '(#\h #\e #\l #\l #\o) (string->list "hello"))
(assert-equal "string->list slice start" '(#\e #\l #\l #\o) (string->list "hello" 1))
(assert-equal "string->list slice range" '(#\e #\l #\l) (string->list "hello" 1 4))
(assert-equal "string->list empty" '() (string->list ""))
(assert-equal "list->string" "hi" (list->string '(#\h #\i)))
(assert-equal "list->string empty" "" (list->string '()))
(assert-equal "string<->list roundtrip" "scheme" (list->string (string->list "scheme")))

;; string->vector
(assert-equal "string->vector full" (vector #\a #\b #\c) (string->vector "abc"))
(assert-equal "string->vector slice start" (vector #\b #\c) (string->vector "abc" 1))
(assert-equal "string->vector slice range" (vector #\b #\c) (string->vector "abcd" 1 3))
(assert-equal "string->vector empty" (vector) (string->vector ""))

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

;; vector->string
(assert-equal "vector->string full" "abc" (vector->string (vector #\a #\b #\c)))
(assert-equal "vector->string slice start" "bc" (vector->string (vector #\a #\b #\c) 1))
(assert-equal "vector->string slice range" "bc" (vector->string (vector #\a #\b #\c #\d) 1 3))
(assert-equal "vector->string empty" "" (vector->string (vector)))
(assert-equal "string<->vector roundtrip" "ulisp" (vector->string (string->vector "ulisp")))

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

;;; =======================================================================
;;; 6. String Comparison Operations (R7RS Section 6.7)
;;; =======================================================================
(write-string "--- 6. String Comparison Procedures ---")
(write-char #\newline)
(flush-output-port)

;; string<? tests
(assert-equal "string<? 2 args true" #t (string<? "abc" "abd"))
(assert-equal "string<? 2 args false" #f (string<? "abd" "abc"))
(assert-equal "string<? 2 args equal false" #f (string<? "abc" "abc"))
(assert-equal "string<? prefix < longer" #t (string<? "abc" "abcd"))
(assert-equal "string<? longer < prefix false" #f (string<? "abcd" "abc"))
(assert-equal "string<? empty < non-empty" #t (string<? "" "a"))
(assert-equal "string<? empty < empty false" #f (string<? "" ""))
(assert-equal "string<? 3 args chain true" #t (string<? "a" "b" "c"))
(assert-equal "string<? 4 args chain true" #t (string<? "a" "ab" "abc" "b"))
(assert-equal "string<? 3 args chain false (unordered)" #f (string<? "a" "c" "b"))
(assert-equal "string<? 3 args chain false (duplicate)" #f (string<? "a" "b" "b"))

;; string>? tests
(assert-equal "string>? 2 args true" #t (string>? "z" "a"))
(assert-equal "string>? 2 args false" #f (string>? "a" "z"))
(assert-equal "string>? 2 args equal false" #f (string>? "abc" "abc"))
(assert-equal "string>? prefix > longer false" #f (string>? "abc" "abcd"))
(assert-equal "string>? longer > prefix true" #t (string>? "abcd" "abc"))
(assert-equal "string>? 3 args chain true" #t (string>? "z" "y" "x"))
(assert-equal "string>? 3 args chain false (unordered)" #f (string>? "z" "x" "y"))
(assert-equal "string>? 3 args chain false (duplicate)" #f (string>? "z" "y" "y"))

;; string<=? tests
(assert-equal "string<=? 2 args less true" #t (string<=? "abc" "abd"))
(assert-equal "string<=? 2 args equal true" #t (string<=? "abc" "abc"))
(assert-equal "string<=? 2 args greater false" #f (string<=? "abd" "abc"))
(assert-equal "string<=? 3 args chain true" #t (string<=? "a" "b" "c"))
(assert-equal "string<=? 4 args chain with duplicate true" #t (string<=? "a" "b" "b" "c"))
(assert-equal "string<=? 3 args chain false" #f (string<=? "a" "c" "b"))

;; string>=? tests
(assert-equal "string>=? 2 args greater true" #t (string>=? "b" "a"))
(assert-equal "string>=? 2 args equal true" #t (string>=? "a" "a"))
(assert-equal "string>=? 2 args less false" #f (string>=? "a" "b"))
(assert-equal "string>=? 3 args chain true" #t (string>=? "c" "b" "a"))
(assert-equal "string>=? 4 args chain with duplicate true" #t (string>=? "c" "b" "b" "a"))
(assert-equal "string>=? 3 args chain false" #f (string>=? "b" "c" "a"))

;; string=? tests (multi-arg chain)
(assert-equal "string=? 3 args chain true" #t (string=? "abc" "abc" "abc"))
(assert-equal "string=? 3 args chain false" #f (string=? "abc" "abc" "xyz"))

;;; -----------------------------------------------------------------------
;;; R7RS 6.2.6 Elementary Integer Math (Issue #558)
;;; -----------------------------------------------------------------------
;; square
(assert-num-equal "square 0" 0 (square 0))
(assert-num-equal "square 7" 49 (square 7))
(assert-num-equal "square -5" 25 (square -5))

;; remainder (sign follows dividend)
(assert-num-equal "remainder 13 4" 1 (remainder 13 4))
(assert-num-equal "remainder -13 4" -1 (remainder -13 4))
(assert-num-equal "remainder 13 -4" 1 (remainder 13 -4))
(assert-num-equal "remainder -13 -4" -1 (remainder -13 -4))
(assert-num-equal "remainder 12 4" 0 (remainder 12 4))
(assert-num-equal "remainder 0 5" 0 (remainder 0 5))

;; gcd (variadic, non-negative)
(assert-num-equal "gcd no args" 0 (gcd))
(assert-num-equal "gcd 1 arg negative" 12 (gcd -12))
(assert-num-equal "gcd 32 -36" 4 (gcd 32 -36))
(assert-num-equal "gcd 0 5" 5 (gcd 0 5))
(assert-num-equal "gcd 0 0" 0 (gcd 0 0))
(assert-num-equal "gcd 3 args" 6 (gcd 12 18 24))
(assert-num-equal "gcd 4 args" 1 (gcd 12 18 24 7))

;; lcm (variadic, non-negative)
(assert-num-equal "lcm no args" 1 (lcm))
(assert-num-equal "lcm 1 arg negative" 7 (lcm -7))
(assert-num-equal "lcm 32 -36" 288 (lcm 32 -36))
(assert-num-equal "lcm with zero" 0 (lcm 0 5))
(assert-num-equal "lcm 3 args" 60 (lcm 4 6 10))

;; expt (binary exponentiation)
(assert-num-equal "expt 0^0" 1 (expt 0 0))
(assert-num-equal "expt 5^0" 1 (expt 5 0))
(assert-num-equal "expt 0^5" 0 (expt 0 5))
(assert-num-equal "expt 2^10" 1024 (expt 2 10))
(assert-num-equal "expt 3^5" 243 (expt 3 5))
(assert-num-equal "expt -2^3" -8 (expt -2 3))
(assert-num-equal "expt -2^4" 16 (expt -2 4))
(assert-num-equal "expt 2^40" 1099511627776 (expt 2 40))
(assert-num-equal "expt 1^-3" 1 (expt 1 -3))
(assert-num-equal "expt -1^-3" -1 (expt -1 -3))
(assert-num-equal "expt -1^-2" 1 (expt -1 -2))

;;; =======================================================================
;;; 7. Iteration (R7RS Section 4.2.4: do)
;;; =======================================================================
(write-string "--- 7. Iteration (do) ---")
(write-char #\newline)
(flush-output-port)

;; Simple counter loop
(assert-num-equal "do simple counter 1 to 10 sum"
                  55
                  (do ((i 1 (+ i 1))
                       (sum 0 (+ sum i)))
                      ((> i 10) sum)))

;; Fibonacci sequence (parallel variable updates)
(assert-num-equal "do fibonacci 10"
                  55
                  (do ((i 0 (+ i 1))
                       (a 0 b)
                       (b 1 (+ a b)))
                      ((= i 10) a)))

;; Step omitted (variable retained)
(assert-num-equal "do step omitted"
                  420
                  (do ((i 0 (+ i 1))
                       (scale 42))
                      ((= i 10) (* i scale))))

;; Side effects in command body
(let ((vec (make-vector 5 0)))
  (do ((i 0 (+ i 1)))
      ((= i 5) vec)
    (vector-set! vec i (* i i)))
  (assert-equal "do vector mutation commands"
                (vector 0 1 4 9 16)
                vec))

;; Multiple return expressions in exit clause
(assert-num-equal "do multi exit expressions"
                  20
                  (let ((x (vector 0)))
                    (do ((i 0 (+ i 1)))
                        ((= i 5) (vector-set! x 0 10) (+ (vector-ref x 0) 10)))))

;; No return expressions in exit clause (returns #f)
(assert-equal "do no exit expressions"
              #f
              (do ((i 0 (+ i 1)))
                  ((= i 3))))

;; Empty bindings list
(assert-num-equal "do empty bindings"
                  100
                  (let ((count (vector 0)))
                    (do ()
                        ((= (vector-ref count 0) 10) 100)
                      (vector-set! count 0 (+ (vector-ref count 0) 1)))))

;;; =======================================================================
;;; 8. Multiple-value Definitions (R7RS Section 5.3.3: define-values)
;;; =======================================================================
(write-string "--- 8. Multiple-value Definitions (define-values) ---")
(write-char #\newline)
(flush-output-port)

;; Top-level define-values
(define-values (r7rs-x r7rs-y) (values 10 20))
(assert-num-equal "define-values top-level 2 values sum"
                  30
                  (+ r7rs-x r7rs-y))

(define-values (r7rs-a r7rs-b r7rs-c) (values 1 2 3))
(assert-num-equal "define-values top-level 3 values"
                  6
                  (+ (+ r7rs-a r7rs-b) r7rs-c))

(define-values (r7rs-single) (values 99))
(assert-num-equal "define-values top-level single value"
                  99
                  r7rs-single)

;; Internal define-values in procedure
(define (r7rs-divmod-proc n d)
  (define-values (q r) (values (quotient n d) (remainder n d)))
  (+ (* q 10) r))

(assert-num-equal "define-values internal in procedure"
                  32
                  (r7rs-divmod-proc 17 5))

;; Internal define-values in let
(assert-num-equal "define-values internal in let"
                  50
                  (let ()
                    (define-values (v1 v2) (values 20 30))
                    (+ v1 v2)))

;; Sequential internal define-values
(assert-num-equal "define-values sequential internal"
                  33
                  (let ()
                    (define-values (s1 s2) (values 1 2))
                    (define-values (s3 s4) (values 10 20))
                    (+ (+ s1 s2) (+ s3 s4))))

;;; -----------------------------------------------------------------------
;;; R7RS Section 5.3.2: Internal definitions
;;; -----------------------------------------------------------------------

;; Internal variable definitions in procedure
(define (r7rs-int-vars)
  (define x 10)
  (define y 20)
  (+ x y))

(assert-num-equal "internal define variables in procedure"
                  30
                  (r7rs-int-vars))

;; Internal procedure definition
(define (r7rs-int-proc)
  (define (double n) (* n 2))
  (double 21))

(assert-num-equal "internal define procedure in procedure"
                  42
                  (r7rs-int-proc))

;; Mutually recursive internal procedure definitions
(define (r7rs-int-mutual n)
  (define (even? m) (if (= m 0) #t (odd? (- m 1))))
  (define (odd? m) (if (= m 0) #f (even? (- m 1))))
  (if (even? n) 100 200))

(assert-num-equal "internal define mutually recursive procedures"
                  100
                  (r7rs-int-mutual 10))

;; Curried shorthand internal procedure definition
(define (r7rs-int-curry)
  (define ((curry-add a) b) (+ a b))
  ((curry-add 15) 27))

(assert-num-equal "internal define curried procedure"
                  42
                  (r7rs-int-curry))

;; Splicing begin with internal definitions
(assert-num-equal "internal define in splicing begin"
                  300
                  (let ()
                    (begin
                      (define u 100)
                      (define v 200))
                    (+ u v)))

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
      (exit 1)))
