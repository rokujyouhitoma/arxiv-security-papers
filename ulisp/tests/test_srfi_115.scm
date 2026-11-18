;;; =======================================================================
;;; ULisp Test Suite: SRFI 115 Scheme Regular Expressions (SRE)
;;; Conforms to R7RS-large Tangerine Edition & SRFI 115
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(test-begin "srfi-115")

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

;; =======================================================================
;; Group 1: Basic Literals & Sequencing
;; =======================================================================
(write-string "--- Group 1: Basic Literals & Sequencing ---\n")

;; Single character match
(assert-true "char exact match" (regexp-matches? #\a "a"))
(assert-false "char mismatch" (regexp-matches? #\a "b"))
(assert-false "char extra trailing" (regexp-matches? #\a "ab"))

;; Literal string match
(assert-true "string exact match" (regexp-matches? "hello" "hello"))
(assert-false "string mismatch" (regexp-matches? "hello" "world"))

;; any & nonl
(assert-true "any matches char" (regexp-matches? 'any "x"))
(assert-true "any matches newline" (regexp-matches? 'any "\n"))
(assert-true "nonl matches char" (regexp-matches? 'nonl "x"))
(assert-false "nonl rejects newline" (regexp-matches? 'nonl "\n"))

;; Sequence (: ...) and (seq ...)
(assert-true "seq match" (regexp-matches? '(: "foo" "bar") "foobar"))
(assert-true "nested seq" (regexp-matches? '(: "a" (: "b" "c") "d") "abcd"))
(assert-false "seq fail" (regexp-matches? '(: "foo" "bar") "foobaz"))

;; Alternation (or ...)
(assert-true "or match 1" (regexp-matches? '(or "cat" "dog") "cat"))
(assert-true "or match 2" (regexp-matches? '(or "cat" "dog") "dog"))
(assert-false "or mismatch" (regexp-matches? '(or "cat" "dog") "bird"))

;; rx macro
(assert-true "rx macro basic" (regexp-matches? (rx "hello" (or "1" "2")) "hello1"))

;; =======================================================================
;; Group 2: Repetition (Greedy & Non-Greedy)
;; =======================================================================
(write-string "--- Group 2: Repetition ---\n")

;; Zero or more (*)
(assert-true "star zero" (regexp-matches? '(* #\a) ""))
(assert-true "star one" (regexp-matches? '(* #\a) "a"))
(assert-true "star multiple" (regexp-matches? '(* #\a) "aaaaa"))
(assert-false "star mismatch" (regexp-matches? '(* #\a) "aaab"))

;; One or more (+)
(assert-false "plus zero" (regexp-matches? '(+ #\a) ""))
(assert-true "plus one" (regexp-matches? '(+ #\a) "a"))
(assert-true "plus multiple" (regexp-matches? '(+ #\a) "aaa"))

;; Zero or one (?)
(assert-true "opt zero" (regexp-matches? '(? #\a) ""))
(assert-true "opt one" (regexp-matches? '(? #\a) "a"))
(assert-false "opt multiple" (regexp-matches? '(? #\a) "aa"))

;; Exact count (= n ...)
(assert-true "exact count pass" (regexp-matches? '(= 3 #\a) "aaa"))
(assert-false "exact count too short" (regexp-matches? '(= 3 #\a) "aa"))
(assert-false "exact count too long" (regexp-matches? '(= 3 #\a) "aaaa"))

;; At least count (>= n ...)
(assert-false "at-least fail" (regexp-matches? '(>= 2 #\a) "a"))
(assert-true "at-least exact" (regexp-matches? '(>= 2 #\a) "aa"))
(assert-true "at-least more" (regexp-matches? '(>= 2 #\a) "aaaa"))

;; Range count (** from to ...)
(assert-false "range count too short" (regexp-matches? '(** 2 4 #\a) "a"))
(assert-true "range count min" (regexp-matches? '(** 2 4 #\a) "aa"))
(assert-true "range count mid" (regexp-matches? '(** 2 4 #\a) "aaa"))
(assert-true "range count max" (regexp-matches? '(** 2 4 #\a) "aaaa"))
(assert-false "range count too long" (regexp-matches? '(** 2 4 #\a) "aaaaa"))

;; Non-greedy (*?, +?, ??)
(assert-true "non-greedy star"
             (regexp-matches? '(: (*? any) "end") "abcend"))
(assert-true "non-greedy plus"
             (regexp-matches? '(: (+? any) "end") "abcend"))
(assert-true "non-greedy opt"
             (regexp-matches? '(: (?? "a") "b") "b"))

;; =======================================================================
;; Group 3: Submatches & Captures
;; =======================================================================
(write-string "--- Group 3: Submatches & Captures ---\n")

;; Basic numbered submatch
(let ((m (regexp-matches '(: (submatch "foo") (submatch "bar")) "foobar")))
  (assert-true "submatch exists" (regexp-match? m))
  (assert-equal "submatch 0 (whole)" (regexp-match-submatch m 0) "foobar")
  (assert-equal "submatch 1" (regexp-match-submatch m 1) "foo")
  (assert-equal "submatch 2" (regexp-match-submatch m 2) "bar")
  (assert-equal "submatch 1 start" (regexp-match-submatch-start m 1) 0)
  (assert-equal "submatch 1 end" (regexp-match-submatch-end m 1) 3)
  (assert-equal "submatch 2 start" (regexp-match-submatch-start m 2) 3)
  (assert-equal "submatch 2 end" (regexp-match-submatch-end m 2) 6)
  (assert-equal "submatch count" (regexp-match-count m) 2))

;; Nested submatches
(let ((m (regexp-matches '(: (submatch "a" (submatch "b") "c")) "abc")))
  (assert-equal "nested outer submatch 1" (regexp-match-submatch m 1) "abc")
  (assert-equal "nested inner submatch 2" (regexp-match-submatch m 2) "b")
  (assert-equal "inner start" (regexp-match-submatch-start m 2) 1)
  (assert-equal "inner end" (regexp-match-submatch-end m 2) 2))

;; Named submatch
(let ((m (regexp-matches '(: (submatch-named year (= 4 numeric))
                             "-"
                             (submatch-named month (= 2 numeric))
                             "-"
                             (submatch-named day (= 2 numeric)))
                        "2026-11-18")))
  (assert-equal "named year" (regexp-match-submatch m 'year) "2026")
  (assert-equal "named month" (regexp-match-submatch m 'month) "11")
  (assert-equal "named day" (regexp-match-submatch m 'day) "18")
  (assert-equal "named year by index 1" (regexp-match-submatch m 1) "2026")
  (assert-equal "named month by index 2" (regexp-match-submatch m 2) "11")
  (assert-equal "named day by index 3" (regexp-match-submatch m 3) "18"))

;; Unmatched optional submatch returns #f
(let ((m (regexp-matches '(: "a" (? (submatch "b")) "c") "ac")))
  (assert-equal "whole match" (regexp-match-submatch m 0) "ac")
  (assert-equal "unmatched submatch is #f" (regexp-match-submatch m 1) #f)
  (assert-equal "unmatched submatch start is #f" (regexp-match-submatch-start m 1) #f))

;; =======================================================================
;; Group 4: Boundary Assertions
;; =======================================================================
(write-string "--- Group 4: Boundary Assertions ---\n")

;; bos & eos
(assert-true "bos match" (regexp-matches? '(: bos "abc") "abc"))
(assert-true "eos match" (regexp-matches? '(: "abc" eos) "abc"))

;; Search with bos / eos
(assert-true "search with bos at start"
             (regexp-search '(: bos "abc") "abcdef"))
(assert-false "search with bos not at start"
              (regexp-search '(: bos "def") "abcdef"))

;; bol & eol
(assert-true "bol at line beginning"
             (regexp-search '(: bol "world") "hello\nworld"))
(assert-false "bol in middle of line"
              (regexp-search '(: bol "orld") "hello\nworld"))
(assert-true "eol at line ending"
             (regexp-search '(: "hello" eol) "hello\nworld"))

;; bow & eow & word
(assert-true "bow at word start"
             (regexp-search '(: bow "test") "a test case"))
(assert-false "bow inside word"
              (regexp-search '(: bow "est") "a test case"))
(assert-true "eow at word end"
             (regexp-search '(: "test" eow) "a test case"))
(assert-false "eow inside word"
              (regexp-search '(: "tes" eow) "a test case"))
(assert-true "word boundary macro"
             (regexp-search '(word "test") "run test now"))
(assert-false "word boundary rejection"
              (regexp-search '(word "test") "run testcase now"))

;; =======================================================================
;; Group 5: Character Classes & Ranges
;; =======================================================================
(write-string "--- Group 5: Character Classes & Ranges ---\n")

;; Standard classes
(assert-true "alpha match" (regexp-matches? '(+ alpha) "Scheme"))
(assert-false "alpha reject digits" (regexp-matches? '(+ alpha) "Scheme7"))
(assert-true "numeric match" (regexp-matches? '(+ numeric) "123456"))
(assert-true "whitespace match" (regexp-matches? '(+ whitespace) " \t\n "))

;; Character range (/)
(assert-true "range lowercase" (regexp-matches? '(+ (/ "a" "z")) "hello"))
(assert-false "range reject uppercase" (regexp-matches? '(+ (/ "a" "z")) "Hello"))
(assert-true "range digits" (regexp-matches? '(+ (/ #\0 #\9)) "9876"))

;; Complement (~)
(assert-true "complement non-digits" (regexp-matches? '(+ (~ numeric)) "abcdef"))
(assert-false "complement rejects digit" (regexp-matches? '(+ (~ numeric)) "abc1ef"))

;; Intersection (&) and Difference (-)
(assert-true "diff: alpha but not upper -> lower"
             (regexp-matches? '(+ (- alpha upper)) "hello"))
(assert-false "diff: rejects upper"
              (regexp-matches? '(+ (- alpha upper)) "Hello"))

;; Case insensitivity (w/nocase)
(assert-true "w/nocase matches mixed case"
             (regexp-matches? '(w/nocase "scheme") "ScHeMe"))
(assert-true "w/nocase in char range"
             (regexp-matches? '(w/nocase (/ "a" "z")) "K"))

;; =======================================================================
;; Group 6: High-Level Text Utilities
;; =======================================================================
(write-string "--- Group 6: High-Level Text Utilities ---\n")

;; regexp-search
(let ((m (regexp-search '(: "foo" (submatch (+ numeric))) "prefix foo123 suffix")))
  (assert-true "search found match" (regexp-match? m))
  (assert-equal "search matched text" (regexp-match-submatch m 0) "foo123")
  (assert-equal "search submatch 1" (regexp-match-submatch m 1) "123")
  (assert-equal "search start" (regexp-match-submatch-start m 0) 7)
  (assert-equal "search end" (regexp-match-submatch-end m 0) 13))

;; regexp-extract
(assert-equal "extract words"
              (regexp-extract '(+ alpha) "apple, orange; banana!")
              '("apple" "orange" "banana"))

;; regexp-split
(assert-equal "split by commas and spaces"
              (regexp-split '(+ (or #\, #\space)) "a, b,  c,d")
              '("a" "b" "c" "d"))

;; regexp-partition
(assert-equal "partition numbers and text"
              (regexp-partition '(+ numeric) "item100price25end")
              '("item" "100" "price" "25" "end"))

;; regexp-replace
(assert-equal "replace first occurrence"
              (regexp-replace "world" "hello world world" "Scheme")
              "hello Scheme world")

;; regexp-replace-all
(assert-equal "replace all occurrences"
              (regexp-replace-all "world" "hello world world" "Scheme")
              "hello Scheme Scheme")

;; regexp-replace with procedure
(assert-equal "replace with procedure"
              (regexp-replace-all '(+ numeric) "a1b22c333"
                                  (lambda (m)
                                    (number->string (* 2 (string->number (regexp-match-submatch m 0))))))
              "a2b44c666")

;; regexp-fold
(assert-equal "fold count matches"
              (regexp-fold '(+ numeric)
                           (lambda (from m s acc) (+ acc 1))
                           0
                           "10 and 20 and 30")
              3)

(test-end "srfi-115")
