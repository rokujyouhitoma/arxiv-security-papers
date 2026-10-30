;;; =======================================================================
;;; ULisp Test Suite: R7RS (scheme char) Characters & Strings (Issue #612)
;;; Testing: char-alphabetic?, char-numeric?, char-whitespace?,
;;;          char-upper-case?, char-lower-case?, digit-value,
;;;          char-upcase, char-downcase, char-foldcase,
;;;          char-ci=?, char-ci<?, char-ci>?, char-ci<=?, char-ci>=?,
;;;          string-upcase, string-downcase, string-foldcase,
;;;          string-ci=?, string-ci<?, string-ci>?, string-ci<=?, string-ci>=?
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
    (else #f)))

(define (assert-equal name actual expected)
  (if (test-equal? actual expected)
      (test-pass name)
      (test-fail name expected actual)))

(define (assert-true name cond)
  (if cond
      (test-pass name)
      (test-fail name #t #f)))

(define (assert-false name cond)
  (if (not cond)
      (test-pass name)
      (test-fail name #f #t)))

(write-string "=== Running ULisp R7RS (scheme char) ASCII Test Suite (Issue #612) ===")
(write-char #\newline)
(flush-output-port)

;; =======================================================================
;; Group 1: Character Classification Predicates (R7RS §6.6)
;; =======================================================================
(write-string "--- Group 1: Character Classification Predicates ---")
(write-char #\newline)

(assert-true "char-alphabetic? on lower 'a'" (char-alphabetic? #\a))
(assert-true "char-alphabetic? on lower 'z'" (char-alphabetic? #\z))
(assert-true "char-alphabetic? on upper 'A'" (char-alphabetic? #\A))
(assert-true "char-alphabetic? on upper 'Z'" (char-alphabetic? #\Z))
(assert-false "char-alphabetic? on digit '0'" (char-alphabetic? #\0))
(assert-false "char-alphabetic? on digit '9'" (char-alphabetic? #\9))
(assert-false "char-alphabetic? on space" (char-alphabetic? #\space))
(assert-false "char-alphabetic? on punctuation '!'" (char-alphabetic? #\!))

(assert-true "char-numeric? on '0'" (char-numeric? #\0))
(assert-true "char-numeric? on '5'" (char-numeric? #\5))
(assert-true "char-numeric? on '9'" (char-numeric? #\9))
(assert-false "char-numeric? on 'a'" (char-numeric? #\a))
(assert-false "char-numeric? on 'Z'" (char-numeric? #\Z))
(assert-false "char-numeric? on space" (char-numeric? #\space))
(assert-false "char-numeric? on newline" (char-numeric? #\newline))

(assert-true "char-whitespace? on space" (char-whitespace? #\space))
(assert-true "char-whitespace? on tab" (char-whitespace? #\tab))
(assert-true "char-whitespace? on newline" (char-whitespace? #\newline))
(assert-true "char-whitespace? on CR (13)" (char-whitespace? (integer->char 13)))
(assert-true "char-whitespace? on VT (11)" (char-whitespace? (integer->char 11)))
(assert-true "char-whitespace? on FF (12)" (char-whitespace? (integer->char 12)))
(assert-false "char-whitespace? on 'a'" (char-whitespace? #\a))
(assert-false "char-whitespace? on '0'" (char-whitespace? #\0))

(assert-true "char-upper-case? on 'A'" (char-upper-case? #\A))
(assert-true "char-upper-case? on 'M'" (char-upper-case? #\M))
(assert-true "char-upper-case? on 'Z'" (char-upper-case? #\Z))
(assert-false "char-upper-case? on 'a'" (char-upper-case? #\a))
(assert-false "char-upper-case? on 'z'" (char-upper-case? #\z))
(assert-false "char-upper-case? on '1'" (char-upper-case? #\1))

(assert-true "char-lower-case? on 'a'" (char-lower-case? #\a))
(assert-true "char-lower-case? on 'm'" (char-lower-case? #\m))
(assert-true "char-lower-case? on 'z'" (char-lower-case? #\z))
(assert-false "char-lower-case? on 'A'" (char-lower-case? #\A))
(assert-false "char-lower-case? on 'Z'" (char-lower-case? #\Z))
(assert-false "char-lower-case? on '9'" (char-lower-case? #\9))

(assert-equal "digit-value on '0'" (digit-value #\0) 0)
(assert-equal "digit-value on '7'" (digit-value #\7) 7)
(assert-equal "digit-value on '9'" (digit-value #\9) 9)
(assert-equal "digit-value on 'a'" (digit-value #\a) #f)
(assert-equal "digit-value on 'A'" (digit-value #\A) #f)
(assert-equal "digit-value on space" (digit-value #\space) #f)

;; =======================================================================
;; Group 2: Character Conversions (R7RS §6.6)
;; =======================================================================
(write-string "--- Group 2: Character Conversions ---")
(write-char #\newline)

(assert-equal "char-upcase on 'a'" (char-upcase #\a) #\A)
(assert-equal "char-upcase on 'z'" (char-upcase #\z) #\Z)
(assert-equal "char-upcase on 'A'" (char-upcase #\A) #\A)
(assert-equal "char-upcase on '0'" (char-upcase #\0) #\0)
(assert-equal "char-upcase on space" (char-upcase #\space) #\space)

(assert-equal "char-downcase on 'A'" (char-downcase #\A) #\a)
(assert-equal "char-downcase on 'Z'" (char-downcase #\Z) #\z)
(assert-equal "char-downcase on 'a'" (char-downcase #\a) #\a)
(assert-equal "char-downcase on '0'" (char-downcase #\0) #\0)

(assert-equal "char-foldcase on 'A'" (char-foldcase #\A) #\a)
(assert-equal "char-foldcase on 'a'" (char-foldcase #\a) #\a)
(assert-equal "char-foldcase on 'Z'" (char-foldcase #\Z) #\z)

;; =======================================================================
;; Group 3: Case-Insensitive Character Comparisons (R7RS §6.6)
;; =======================================================================
(write-string "--- Group 3: Case-Insensitive Character Comparisons ---")
(write-char #\newline)

(assert-true "char-ci=? on #\\a and #\\A" (char-ci=? #\a #\A))
(assert-true "char-ci=? on #\\A and #\\a" (char-ci=? #\A #\a))
(assert-true "char-ci=? on #\\a and #\\a" (char-ci=? #\a #\a))
(assert-false "char-ci=? on #\\a and #\\b" (char-ci=? #\a #\b))
(assert-false "char-ci=? on #\\a and #\\B" (char-ci=? #\a #\B))

(assert-true "char-ci<? on #\\a and #\\B" (char-ci<? #\a #\B))
(assert-true "char-ci<? on #\\A and #\\b" (char-ci<? #\A #\b))
(assert-false "char-ci<? on #\\b and #\\A" (char-ci<? #\b #\A))
(assert-false "char-ci<? on #\\a and #\\A" (char-ci<? #\a #\A))

(assert-true "char-ci>? on #\\b and #\\A" (char-ci>? #\b #\A))
(assert-true "char-ci>? on #\\B and #\\a" (char-ci>? #\B #\a))
(assert-false "char-ci>? on #\\a and #\\B" (char-ci>? #\a #\B))

(assert-true "char-ci<=? on #\\a and #\\A" (char-ci<=? #\a #\A))
(assert-true "char-ci<=? on #\\a and #\\B" (char-ci<=? #\a #\B))
(assert-false "char-ci<=? on #\\B and #\\a" (char-ci<=? #\B #\a))

(assert-true "char-ci>=? on #\\A and #\\a" (char-ci>=? #\A #\a))
(assert-true "char-ci>=? on #\\B and #\\a" (char-ci>=? #\B #\a))
(assert-false "char-ci>=? on #\\a and #\\B" (char-ci>=? #\a #\B))

;; Multi-argument comparisons desugared via Pass 030
(assert-true "char-ci=? 4 args" (char-ci=? #\a #\A #\a #\A))
(assert-false "char-ci=? 4 args false" (char-ci=? #\a #\A #\b #\A))
(assert-true "char-ci<? 4 args" (char-ci<? #\a #\B #\c #\D))
(assert-false "char-ci<? 4 args false" (char-ci<? #\a #\C #\B #\d))
(assert-true "char-ci<=? 5 args" (char-ci<=? #\a #\A #\b #\B #\c))
(assert-true "char-ci>? 4 args" (char-ci>? #\d #\C #\b #\A))
(assert-true "char-ci>=? 5 args" (char-ci>=? #\d #\D #\c #\B #\b))

;; =======================================================================
;; Group 4: String Case Conversions (R7RS §6.7)
;; =======================================================================
(write-string "--- Group 4: String Case Conversions ---")
(write-char #\newline)

(assert-equal "string-upcase on 'Hello, World!'" (string-upcase "Hello, World!") "HELLO, WORLD!")
(assert-equal "string-upcase on empty string" (string-upcase "") "")
(assert-equal "string-upcase on '123 abc XYZ'" (string-upcase "123 abc XYZ") "123 ABC XYZ")

(assert-equal "string-downcase on 'Hello, World!'" (string-downcase "Hello, World!") "hello, world!")
(assert-equal "string-downcase on empty string" (string-downcase "") "")
(assert-equal "string-downcase on '123 ABC xyz'" (string-downcase "123 ABC xyz") "123 abc xyz")

(assert-equal "string-foldcase on 'Hello, World!'" (string-foldcase "Hello, World!") "hello, world!")
(assert-equal "string-foldcase on 'SCHEME'" (string-foldcase "SCHEME") "scheme")

;; =======================================================================
;; Group 5: Case-Insensitive String Comparisons (R7RS §6.7)
;; =======================================================================
(write-string "--- Group 5: Case-Insensitive String Comparisons ---")
(write-char #\newline)

(assert-true "string-ci=? on 'Scheme' and 'sChEmE'" (string-ci=? "Scheme" "sChEmE"))
(assert-true "string-ci=? on empty strings" (string-ci=? "" ""))
(assert-false "string-ci=? on 'Scheme' and 'Lisp'" (string-ci=? "Scheme" "Lisp"))
(assert-false "string-ci=? on 'abc' and 'abcd'" (string-ci=? "abc" "abcd"))

(assert-true "string-ci<? on 'abc' and 'ABD'" (string-ci<? "abc" "ABD"))
(assert-true "string-ci<? on 'abc' and 'ABCD'" (string-ci<? "abc" "ABCD"))
(assert-false "string-ci<? on 'abcd' and 'ABC'" (string-ci<? "abcd" "ABC"))
(assert-false "string-ci<? on 'ABC' and 'abc'" (string-ci<? "ABC" "abc"))

(assert-true "string-ci>? on 'ABD' and 'abc'" (string-ci>? "ABD" "abc"))
(assert-true "string-ci>? on 'ABCD' and 'abc'" (string-ci>? "ABCD" "abc"))
(assert-false "string-ci>? on 'abc' and 'ABD'" (string-ci>? "abc" "ABD"))

(assert-true "string-ci<=? on 'abc' and 'ABC'" (string-ci<=? "abc" "ABC"))
(assert-true "string-ci<=? on 'abc' and 'ABD'" (string-ci<=? "abc" "ABD"))
(assert-false "string-ci<=? on 'ABD' and 'abc'" (string-ci<=? "ABD" "abc"))

(assert-true "string-ci>=? on 'ABC' and 'abc'" (string-ci>=? "ABC" "abc"))
(assert-true "string-ci>=? on 'ABD' and 'abc'" (string-ci>=? "ABD" "abc"))
(assert-false "string-ci>=? on 'abc' and 'ABD'" (string-ci>=? "abc" "ABD"))

;; Multi-argument string comparisons desugared via Pass 030
(assert-true "string-ci=? 3 args" (string-ci=? "abc" "AbC" "ABC"))
(assert-false "string-ci=? 3 args false" (string-ci=? "abc" "ABC" "abd"))
(assert-true "string-ci<? 4 args" (string-ci<? "a" "B" "c" "D"))
(assert-true "string-ci<=? 5 args" (string-ci<=? "a" "A" "b" "B" "c"))
(assert-true "string-ci>? 4 args" (string-ci>? "d" "C" "b" "A"))
(assert-true "string-ci>=? 5 args" (string-ci>=? "d" "D" "c" "B" "b"))

;; =======================================================================
;; Summary
;; =======================================================================
(write-string "=======================================================")
(write-char #\newline)
(if (= (vector-ref *test-failures* 0) 0)
    (begin
      (write-string " ALL R7RS (scheme char) ASCII TESTS PASSED!")
      (write-char #\newline)
      (flush-output-port))
    (begin
      (write-string " FAILURES DETECTED: ")
      (write (vector-ref *test-failures* 0))
      (write-char #\newline)
      (flush-output-port)
      (exit 1)))

