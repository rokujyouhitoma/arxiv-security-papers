;;; =======================================================================
;;; ULisp Test Suite: R7RS-large / SRFI 135 Immutable Texts (Issue #855)
;;; Testing:
;;;   Group 1:  Predicates (text?, textual?, textual-null?, textual-every, textual-any)
;;;   Group 2:  Constructors (make-text, text, text-tabulate, text-unfold, text-unfold-right)
;;;   Group 3:  Conversion (textual->text, textual->string, textual->vector, textual->list,
;;;             string->text, vector->text, list->text, reverse-list->text, UTF-8/UTF-16)
;;;   Group 4:  Selection & Slicing (text-length, textual-length, text-ref, textual-ref,
;;;             subtext, subtextual, textual-copy, take, drop, pad, trim)
;;;   Group 5:  Replacement (textual-replace)
;;;   Group 6:  Comparison (textual=?, textual<?, textual-ci=?, etc.)
;;;   Group 7:  Prefixes & Suffixes (prefix-length, suffix-length, prefix?, suffix?)
;;;   Group 8:  Searching (index, index-right, skip, skip-right, contains, contains-right)
;;;   Group 9:  Case Conversion (upcase, downcase, foldcase, titlecase)
;;;   Group 10: Concatenation (append, concatenate, concatenate-reverse, join)
;;;   Group 11: Fold, Map & Friends (fold, map, for-each, map-index, count, filter, remove)
;;;   Group 12: Replication & Splitting (replicate, split)
;;;   Group 13: Scale & Structural Sharing (10,000 chars slicing & tree concatenation)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(test-begin "srfi-135")

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
;; Group 1: Predicates
;; =======================================================================
(write-string "--- Group 1: Predicates ---")
(write-char #\newline)

(define t-empty (text))
(define t-abc (string->text "abc"))

(assert-true "1.1 text? on text" (text? t-abc))
(assert-true "1.2 text? on empty text" (text? t-empty))
(assert-false "1.3 text? on string" (text? "abc"))
(assert-false "1.4 text? on vector" (text? #(1 2 3)))
(assert-false "1.5 text? on symbol" (text? 'abc))

(assert-true "1.6 textual? on text" (textual? t-abc))
(assert-true "1.7 textual? on string" (textual? "abc"))
(assert-false "1.8 textual? on symbol" (textual? 'abc))

(assert-true "1.9 textual-null? on empty text" (textual-null? t-empty))
(assert-true "1.10 textual-null? on empty string" (textual-null? ""))
(assert-false "1.11 textual-null? on non-empty text" (textual-null? t-abc))
(assert-false "1.12 textual-null? on non-empty string" (textual-null? "a"))

(assert-true "1.13 textual-every all-digits"
  (textual-every char-numeric? "12345"))
(assert-false "1.14 textual-every mixed"
  (textual-every char-numeric? "123a5"))
(assert-true "1.15 textual-every empty"
  (textual-every char-numeric? ""))

(assert-true "1.16 textual-any has-digit"
  (textual-any char-numeric? "abc4def"))
(assert-false "1.17 textual-any no-digit"
  (textual-any char-numeric? "abcdef"))
(assert-false "1.18 textual-any empty"
  (textual-any char-numeric? ""))

;; =======================================================================
;; Group 2: Constructors
;; =======================================================================
(write-string "--- Group 2: Constructors ---")
(write-char #\newline)

(define t-rep (make-text 5 #\a))
(assert-equal "2.1 make-text length" (text-length t-rep) 5)
(assert-equal "2.2 make-text to string" (textual->string t-rep) "aaaaa")

(define t-space (make-text 3))
(assert-equal "2.3 make-text space default" (textual->string t-space) "   ")

(define t-chars (text #\H #\e #\l #\l #\o))
(assert-equal "2.4 text varargs" (textual->string t-chars) "Hello")

(define t-tab (text-tabulate 4 (lambda (i) (integer->char (+ 65 i)))))
(assert-equal "2.5 text-tabulate" (textual->string t-tab) "ABCD")

(define t-unf (text-unfold (lambda (s) (= s 3))
                           (lambda (s) (integer->char (+ 97 s)))
                           (lambda (s) (+ s 1))
                           0))
(assert-equal "2.6 text-unfold" (textual->string t-unf) "abc")

(define t-unf-r (text-unfold-right (lambda (s) (= s 3))
                                   (lambda (s) (integer->char (+ 97 s)))
                                   (lambda (s) (+ s 1))
                                   0))
(assert-equal "2.7 text-unfold-right" (textual->string t-unf-r) "cba")

;; =======================================================================
;; Group 3: Conversion
;; =======================================================================
(write-string "--- Group 3: Conversion ---")
(write-char #\newline)

(assert-equal "3.1 string->text full" (textual->string (string->text "Scheme")) "Scheme")
(assert-equal "3.2 string->text range" (textual->string (string->text "Scheme" 1 4)) "che")

(assert-equal "3.3 list->text" (textual->string (list->text '(#\x #\y #\z))) "xyz")
(assert-equal "3.4 reverse-list->text" (textual->string (reverse-list->text '(#\x #\y #\z))) "zyx")

(assert-equal "3.5 vector->text" (textual->string (vector->text (vector #\1 #\2 #\3))) "123")
(assert-equal "3.6 vector->text range" (textual->string (vector->text (vector #\1 #\2 #\3 #\4) 1 3)) "23")

(assert-equal "3.7 textual->vector" (textual->vector t-abc) (vector #\a #\b #\c))
(assert-equal "3.8 textual->list" (textual->list t-abc) '(#\a #\b #\c))

;; UTF-8 encoding / decoding
(define utf8-bv (textual->utf8 "Scheme 7!"))
(assert-equal "3.9 textual->utf8 length" (bytevector-length utf8-bv) 9)
(assert-equal "3.10 utf8->text" (textual->string (utf8->text utf8-bv)) "Scheme 7!")

;; UTF-16 BE / LE / BOM
(define utf16be-bv (textual->utf16be "AB"))
(assert-equal "3.11 utf16be length" (bytevector-length utf16be-bv) 4)
(assert-equal "3.12 utf16be b0" (bytevector-u8-ref utf16be-bv 0) 0)
(assert-equal "3.13 utf16be b1" (bytevector-u8-ref utf16be-bv 1) 65)
(assert-equal "3.14 utf16be->text" (textual->string (utf16be->text utf16be-bv)) "AB")

(define utf16le-bv (textual->utf16le "AB"))
(assert-equal "3.15 utf16le b0" (bytevector-u8-ref utf16le-bv 0) 65)
(assert-equal "3.16 utf16le b1" (bytevector-u8-ref utf16le-bv 1) 0)
(assert-equal "3.17 utf16le->text" (textual->string (utf16le->text utf16le-bv)) "AB")

;; =======================================================================
;; Group 4: Selection & Slicing
;; =======================================================================
(write-string "--- Group 4: Selection ---")
(write-char #\newline)

(define t-hello (string->text "Hello, World!"))
(assert-equal "4.1 text-length" (text-length t-hello) 13)
(assert-equal "4.2 textual-length on str" (textual-length "Hello") 5)
(assert-equal "4.3 text-ref 0" (text-ref t-hello 0) #\H)
(assert-equal "4.4 text-ref 7" (text-ref t-hello 7) #\W)
(assert-equal "4.5 textual-ref str" (textual-ref "xyz" 1) #\y)

;; subtext
(define t-sub1 (subtext t-hello 7 12))
(assert-equal "4.6 subtext" (textual->string t-sub1) "World")

;; nested subtext (slice of slice)
(define t-sub2 (subtext t-sub1 1 4))
(assert-equal "4.7 nested subtext" (textual->string t-sub2) "orl")

;; take & drop
(assert-equal "4.8 textual-take" (textual->string (textual-take t-hello 5)) "Hello")
(assert-equal "4.9 textual-drop" (textual->string (textual-drop t-hello 7)) "World!")
(assert-equal "4.10 textual-take-right" (textual->string (textual-take-right t-hello 6)) "World!")
(assert-equal "4.11 textual-drop-right" (textual->string (textual-drop-right t-hello 8)) "Hello")

;; pad
(assert-equal "4.12 textual-pad exact" (textual->string (textual-pad "abc" 3)) "abc")
(assert-equal "4.13 textual-pad expand" (textual->string (textual-pad "abc" 5 #\*)) "**abc")
(assert-equal "4.14 textual-pad truncate" (textual->string (textual-pad "abcde" 3)) "cde")

(assert-equal "4.15 textual-pad-right expand" (textual->string (textual-pad-right "abc" 5 #\-)) "abc--")
(assert-equal "4.16 textual-pad-right truncate" (textual->string (textual-pad-right "abcde" 3)) "abc")

;; trim
(assert-equal "4.17 textual-trim" (textual->string (textual-trim "  foo ")) "foo ")
(assert-equal "4.18 textual-trim-right" (textual->string (textual-trim-right "  foo ")) "  foo")
(assert-equal "4.19 textual-trim-both" (textual->string (textual-trim-both "  foo ")) "foo")

;; =======================================================================
;; Group 5: Replacement
;; =======================================================================
(write-string "--- Group 5: Replacement ---")
(write-char #\newline)

(assert-equal "5.1 textual-replace middle"
  (textual->string (textual-replace "The quick brown fox" 4 9 "slow"))
  "The slow brown fox")

(assert-equal "5.2 textual-replace empty insert"
  (textual->string (textual-replace "Hello!" 5 5 " there"))
  "Hello there!")

;; =======================================================================
;; Group 6: Comparison
;; =======================================================================
(write-string "--- Group 6: Comparison ---")
(write-char #\newline)

(assert-true "6.1 textual=?" (textual=? "apple" (string->text "apple") "apple"))
(assert-false "6.2 textual=? mismatch" (textual=? "apple" "Apple"))

(assert-true "6.3 textual<?" (textual<? "apple" "banana" "cherry"))
(assert-false "6.4 textual<? not sorted" (textual<? "banana" "apple"))

(assert-true "6.5 textual>?" (textual>? "zebra" "yak" "walrus"))
(assert-true "6.6 textual<=?" (textual<=? "apple" "apple" "banana"))
(assert-true "6.7 textual>=?" (textual>=? "banana" "banana" "apple"))

(assert-true "6.8 textual-ci=?" (textual-ci=? "Apple" "apple" "APPLE"))
(assert-true "6.9 textual-ci<?" (textual-ci<? "apple" "BANANA" "cherry"))
(assert-true "6.10 textual-ci>?" (textual-ci>? "ZEBRA" "yak" "WALRUS"))
(assert-true "6.11 textual-ci<=?" (textual-ci<=? "apple" "APPLE" "banana"))
(assert-true "6.12 textual-ci>=?" (textual-ci>=? "banana" "BANANA" "apple"))

;; =======================================================================
;; Group 7: Prefixes & Suffixes
;; =======================================================================
(write-string "--- Group 7: Prefixes & Suffixes ---")
(write-char #\newline)

(assert-equal "7.1 textual-prefix-length" (textual-prefix-length "preheat" "prepare") 3)
(assert-equal "7.2 textual-suffix-length" (textual-suffix-length "running" "jumping") 3)

(assert-true "7.3 textual-prefix? true" (textual-prefix? "pre" "prefix"))
(assert-false "7.4 textual-prefix? false" (textual-prefix? "fix" "prefix"))

(assert-true "7.5 textual-suffix? true" (textual-suffix? "fix" "prefix"))
(assert-false "7.6 textual-suffix? false" (textual-suffix? "pre" "prefix"))

;; =======================================================================
;; Group 8: Searching
;; =======================================================================
(write-string "--- Group 8: Searching ---")
(write-char #\newline)

(assert-equal "8.1 textual-index" (textual-index char-numeric? "foo12bar") 3)
(assert-false "8.2 textual-index none" (textual-index char-numeric? "foobar"))

(assert-equal "8.3 textual-index-right" (textual-index-right char-numeric? "f1o2bar") 3)

(assert-equal "8.4 textual-skip" (textual-skip (lambda (c) (char=? c #\x)) "xxxy") 3)
(assert-equal "8.5 textual-skip-right" (textual-skip-right (lambda (c) (char=? c #\x)) "yxxx") 0)

(assert-equal "8.6 textual-contains" (textual-contains "supercalifragilistic" "fragil") 9)
(assert-false "8.7 textual-contains not found" (textual-contains "supercalifragilistic" "magic"))

(assert-equal "8.8 textual-contains-right" (textual-contains-right "banana" "an") 3)

;; =======================================================================
;; Group 9: Case Conversion
;; =======================================================================
(write-string "--- Group 9: Case Conversion ---")
(write-char #\newline)

(assert-equal "9.1 textual-upcase" (textual->string (textual-upcase "Hello World!")) "HELLO WORLD!")
(assert-equal "9.2 textual-downcase" (textual->string (textual-downcase "Hello World!")) "hello world!")
(assert-equal "9.3 textual-foldcase" (textual->string (textual-foldcase "Hello World!")) "hello world!")
(assert-equal "9.4 textual-titlecase" (textual->string (textual-titlecase "the quick BROWN fox")) "The Quick Brown Fox")

;; =======================================================================
;; Group 10: Concatenation
;; =======================================================================
(write-string "--- Group 10: Concatenation ---")
(write-char #\newline)

(assert-equal "10.1 textual-append 0" (textual->string (textual-append)) "")
(assert-equal "10.2 textual-append 1" (textual->string (textual-append "abc")) "abc")
(assert-equal "10.3 textual-append 3" (textual->string (textual-append "a" (string->text "b") "c")) "abc")

(assert-equal "10.4 textual-concatenate" (textual->string (textual-concatenate '("foo" "bar" "baz"))) "foobarbaz")

(assert-equal "10.5 textual-concatenate-reverse"
  (textual->string (textual-concatenate-reverse '("baz" "bar" "foo")))
  "foobarbaz")

(assert-equal "10.6 textual-join infix"
  (textual->string (textual-join '("one" "two" "three") ", "))
  "one, two, three")

(assert-equal "10.7 textual-join prefix"
  (textual->string (textual-join '("one" "two") "/" 'prefix))
  "/one/two")

(assert-equal "10.8 textual-join suffix"
  (textual->string (textual-join '("one" "two") ";" 'suffix))
  "one;two;")

;; =======================================================================
;; Group 11: Fold, Map & Friends
;; =======================================================================
(write-string "--- Group 11: Fold, Map & Friends ---")
(write-char #\newline)

(assert-equal "11.1 textual-fold count"
  (textual-fold (lambda (c acc) (+ acc 1)) 0 "Scheme")
  6)

(assert-equal "11.2 textual-fold-right build-list"
  (textual-fold-right (lambda (c acc) (cons c acc)) '() "abc")
  '(#\a #\b #\c))

(assert-equal "11.3 textual-map 1-arg"
  (textual->string (textual-map char-upcase "abc"))
  "ABC")

(assert-equal "11.4 textual-map 2-arg"
  (textual->string (textual-map (lambda (c1 c2)
                                  (if (char<? c1 c2) c1 c2))
                                "apple" "bacon"))
  "aacle")

(define cnt-box (vector 0))
(textual-for-each (lambda (c) (vector-set! cnt-box 0 (+ (vector-ref cnt-box 0) 1))) "test")
(assert-equal "11.5 textual-for-each" (vector-ref cnt-box 0) 4)

(assert-equal "11.6 textual-map-index"
  (textual->string (textual-map-index (lambda (i) (integer->char (+ 48 i))) "abcde"))
  "01234")

(assert-equal "11.7 textual-count" (textual-count (lambda (c) (char=? c #\a)) "banana") 3)

(assert-equal "11.8 textual-filter"
  (textual->string (textual-filter char-alphabetic? "R7RS-large (135)!"))
  "RRSlarge")

(assert-equal "11.9 textual-remove"
  (textual->string (textual-remove char-numeric? "a1b2c3d4"))
  "abcd")

;; =======================================================================
;; Group 12: Replication & Splitting
;; =======================================================================
(write-string "--- Group 12: Replication & Splitting ---")
(write-char #\newline)

(assert-equal "12.1 textual-replicate cycle"
  (textual->string (textual-replicate "abc" 0 7))
  "abcabca")

(assert-equal "12.2 textual-replicate offset"
  (textual->string (textual-replicate "abc" 1 6))
  "bcabc")

(define split-res (textual-split "foo,bar,,baz" #\,))
(assert-equal "12.3 textual-split length" (length split-res) 4)
(assert-equal "12.4 textual-split elem 0" (textual->string (car split-res)) "foo")
(assert-equal "12.5 textual-split elem 1" (textual->string (cadr split-res)) "bar")
(assert-equal "12.6 textual-split elem 2" (textual->string (caddr split-res)) "")
(assert-equal "12.7 textual-split elem 3" (textual->string (cadddr split-res)) "baz")

;; limit split
(define split-limit (textual-split "a:b:c:d" #\: 'infix 2))
(assert-equal "12.8 textual-split limit length" (length split-limit) 2)
(assert-equal "12.9 textual-split limit elem 0" (textual->string (car split-limit)) "a")
(assert-equal "12.10 textual-split limit elem 1" (textual->string (cadr split-limit)) "b:c:d")

;; =======================================================================
;; Group 13: Scale & Structural Sharing (10,000 Chars)
;; =======================================================================
(write-string "--- Group 13: Scale & Structural Sharing ---")
(write-char #\newline)

;; Build large 10,000 character text via make-text and append
(define t-big-chunk (make-text 1000 #\X))
(define t-big (textual-concatenate (make-list 10 t-big-chunk)))

(assert-equal "13.1 big text length" (text-length t-big) 10000)
(assert-equal "13.2 big text ref 0" (text-ref t-big 0) #\X)
(assert-equal "13.3 big text ref 5000" (text-ref t-big 5000) #\X)
(assert-equal "13.4 big text ref 9999" (text-ref t-big 9999) #\X)

;; Subtext slicing of 10,000 char text in O(1)
(define t-big-sub (subtext t-big 2500 7500))
(assert-equal "13.5 big subtext length" (text-length t-big-sub) 5000)
(assert-equal "13.6 big subtext ref 0" (text-ref t-big-sub 0) #\X)

;; Slicing and replacing
(define t-mod (textual-replace t-big 4995 5005 "0123456789"))
(assert-equal "13.7 modified big text length" (text-length t-mod) 10000)
(assert-equal "13.8 modified big text ref 4995" (text-ref t-mod 4995) #\0)
(assert-equal "13.9 modified big text ref 5004" (text-ref t-mod 5004) #\9)
(assert-equal "13.10 original unchanged" (text-ref t-big 4995) #\X)

(test-end "srfi-135")
