;;; =======================================================================
;;; ULisp Test Suite: SRFI 180 JSON (RFC 8259)
;;; Conforms to R7RS-large Orange / Hypnos Docket & SRFI 180
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(test-begin "srfi-180")

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

;; Helper to assert that an expression raises an error satisfying json-error?
(define (assert-json-error name thunk)
  (let ((raised-cell (cons #f '())))
    (with-exception-handler
     (lambda (exn)
       (set-car! raised-cell (and (json-error? exn) (read-error? exn)))
       #f)
     thunk)
    (test-assert name (car raised-cell))))

;; =======================================================================
;; Group 1: Scalars & Literals
;; =======================================================================
(write-string "--- Group 1: Scalars & Literals ---\n")

;; null
(assert-true "null? predicate" (json-null? 'null))
(assert-false "null? on other symbol" (json-null? 'foo))
(assert-false "null? on false" (json-null? #f))
(assert-equal "parse null" (string->json "null") 'null)
(assert-equal "serialize null" (json->string 'null) "null")

;; boolean
(assert-equal "parse true" (string->json "true") #t)
(assert-equal "parse false" (string->json "false") #f)
(assert-equal "serialize true" (json->string #t) "true")
(assert-equal "serialize false" (json->string #f) "false")

;; integers & bignums
(assert-equal "parse zero" (string->json "0") 0)
(assert-equal "parse negative zero" (string->json "-0") 0)
(assert-equal "parse positive int" (string->json "42") 42)
(assert-equal "parse negative int" (string->json "-12345") -12345)
(assert-equal "parse bignum" (string->json "100000000000000000000") 100000000000000000000)
(assert-equal "serialize zero" (json->string 0) "0")
(assert-equal "serialize positive int" (json->string 42) "42")
(assert-equal "serialize negative int" (json->string -12345) "-12345")
(assert-equal "serialize bignum" (json->string 100000000000000000000) "100000000000000000000")

;; floats & exponents
(assert-equal "parse simple float" (string->json "3.1415") 3.1415)
(assert-equal "parse negative float" (string->json "-0.5") -0.5)
(assert-equal "parse exponent positive" (string->json "1e3") 1000.0)
(assert-equal "parse exponent plus sign" (string->json "2.5e+2") 250.0)
(assert-equal "parse exponent minus sign" (string->json "1e-2") 0.01)

;; =======================================================================
;; Group 2: Strings & Unicode Escapes
;; =======================================================================
(write-string "--- Group 2: Strings & Unicode Escapes ---\n")

(assert-equal "parse empty string" (string->json "\"\"") "")
(assert-equal "parse simple string" (string->json "\"hello world\"") "hello world")
(assert-equal "serialize simple string" (json->string "hello world") "\"hello world\"")

;; escapes
(assert-equal "parse quote escape" (string->json "\"hello \\\"world\\\"\"") "hello \"world\"")
(assert-equal "parse backslash escape" (string->json "\"foo\\\\bar\"") "foo\\bar")
(assert-equal "parse slash escape" (string->json "\"foo\\/bar\"") "foo/bar")
(assert-equal "parse newline escape" (string->json "\"line1\\nline2\"") "line1\nline2")
(assert-equal "parse tab escape" (string->json "\"a\\tb\"") "a\tb")
(assert-equal "parse carriage return escape" (string->json "\"a\\rb\"") (string #\a (integer->char 13) #\b))

;; BMP unicode escape
(assert-equal "parse bmp hex escape" (string->json "\"\\u0041\\u0042\\u0043\"") "ABC")

;; Surrogate pair decoding (e.g. Emoji U+1F600 = \uD83D\uDE00)
(assert-equal "parse surrogate pair emoji"
              (string->json "\"\\uD83D\\uDE00\"")
              (string (integer->char #x1f600)))

;; =======================================================================
;; Group 3: Arrays & Objects
;; =======================================================================
(write-string "--- Group 3: Arrays & Objects ---\n")

;; arrays
(assert-equal "parse empty array" (string->json "[]") (vector))
(assert-equal "serialize empty array" (json->string (vector)) "[]")
(assert-equal "parse array with spaces" (string->json " [  ] ") (vector))
(assert-equal "parse number array" (string->json "[1, 2, 3]") (vector 1 2 3))
(assert-equal "serialize number array" (json->string (vector 1 2 3)) "[1, 2, 3]")
(assert-equal "parse mixed array"
              (string->json "[\"foo\", 42, true, null, false]")
              (vector "foo" 42 #t 'null #f))
(assert-equal "nested array" (string->json "[[1, 2], [3, 4]]") (vector (vector 1 2) (vector 3 4)))

;; objects
(assert-equal "parse empty object" (string->json "{}") '())
(assert-equal "serialize empty object" (json->string '()) "{}")
(assert-equal "parse single key object" (string->json "{\"k\": \"val\"}") '((k . "val")))
(assert-equal "serialize single key object" (json->string '((k . "val"))) "{\"k\": \"val\"}")
(assert-equal "parse multi key object"
              (string->json "{\"a\": 1, \"b\": 2}")
              '((a . 1) (b . 2)))
(assert-equal "serialize multi key object"
              (json->string '((a . 1) (b . 2)))
              "{\"a\": 1, \"b\": 2}")
(assert-equal "nested object and array"
              (string->json "{\"a\": \"Alice\", \"b\": [100, 95]}")
              (list (cons 'a "Alice") (cons 'b (vector 100 95))))

;; =======================================================================
;; Group 4: Roundtrip Tests & Convenience Helpers
;; =======================================================================
(write-string "--- Group 4: Roundtrip Tests & Convenience Helpers ---\n")

(define (roundtrip val)
  (string->json (json->string val)))

(assert-equal "roundtrip scalar" (roundtrip 12345) 12345)
(assert-equal "roundtrip string" (roundtrip "test string") "test string")
(assert-equal "roundtrip vector" (roundtrip (vector 1 "a" #t 'null)) (vector 1 "a" #t 'null))
(assert-equal "roundtrip alist" (roundtrip '((x . 10) (y . 20))) '((x . 10) (y . 20)))

;; bytes->json & json->bytes
(let* ((orig-obj (list (cons 's "ulisp") (cons 'p 8080)))
       (bv (json->bytes orig-obj))
       (restored (bytes->json bv)))
  (assert-equal "bytes roundtrip" restored orig-obj))

;; =======================================================================
;; Group 5: Streaming APIs (json-generator, json-accumulator, json-fold)
;; =======================================================================
(write-string "--- Group 5: Streaming APIs ---\n")

;; json-generator on scalar
(let* ((in (open-input-string "42"))
       (gen (json-generator in)))
  (assert-equal "generator scalar 1" (gen) 42)
  (assert-true "generator scalar eof" (eof-object? (gen))))

;; json-generator on array
(let* ((in (open-input-string "[1, 2]"))
       (gen (json-generator in))
       (t1 (gen))
       (t2 (gen))
       (t3 (gen))
       (t4 (gen))
       (t5 (gen)))
  (assert-equal "gen array 1" t1 'array-start)
  (assert-equal "gen array 2" t2 1)
  (assert-equal "gen array 3" t3 2)
  (assert-equal "gen array 4" t4 'array-end)
  (assert-true "gen array eof" (eof-object? t5)))

;; json-generator on object
(let* ((in (open-input-string "{\"k\": \"v\"}"))
       (gen (json-generator in))
       (t1 (gen))
       (t2 (gen))
       (t3 (gen))
       (t4 (gen))
       (t5 (gen)))
  (assert-equal "gen obj 1" t1 'object-start)
  (assert-equal "gen obj 2" t2 "k")
  (assert-equal "gen obj 3" t3 "v")
  (assert-equal "gen obj 4" t4 'object-end)
  (assert-true "gen obj eof" (eof-object? t5)))

;; json-accumulator building an array
(let* ((out (open-output-string))
       (acc (json-accumulator out)))
  (acc 'array-start)
  (acc 1)
  (acc 2)
  (acc 3)
  (acc 'array-end)
  (acc (eof-object))
  (assert-equal "accumulator array" (get-output-string out) "[1, 2, 3]"))

;; json-accumulator building an object
(let* ((out (open-output-string))
       (acc (json-accumulator out)))
  (acc 'object-start)
  (acc "title")
  (acc "Scheme")
  (acc "year")
  (acc 2026)
  (acc 'object-end)
  (acc (eof-object))
  (assert-equal "accumulator object" (get-output-string out) "{\"title\": \"Scheme\", \"year\": 2026}"))

;; json-fold counting elements
(let* ((in (open-input-string "[10, 20, 30]"))
       (count (json-fold (lambda (val seed) (+ seed 1))
                         (lambda (seed) seed)
                         (lambda (seed) seed)
                         (lambda (seed) seed)
                         (lambda (seed) seed)
                         0
                         in)))
  (assert-equal "json-fold sum count" count 3))

;; =======================================================================
;; Group 6: Lines (ndjson) & Sequences (RFC 7464)
;; =======================================================================
(write-string "--- Group 6: Lines & Sequences ---\n")

;; json-lines-read
(let* ((ndjson-text "{\"a\": 1}\n\n{\"b\": 2}\n{\"c\": 3}\n")
       (in (open-input-string ndjson-text))
       (gen (json-lines-read in))
       (item1 (gen))
       (item2 (gen))
       (item3 (gen))
       (item4 (gen)))
  (assert-equal "ndjson item 1" item1 '((a . 1)))
  (assert-equal "ndjson item 2" item2 '((b . 2)))
  (assert-equal "ndjson item 3" item3 '((c . 3)))
  (assert-true "ndjson eof" (eof-object? item4)))

;; json-sequence-read (RFC 7464 with RS #\x1e)
(let* ((rs (string (integer->char #x1e)))
       (seq-text (string-append rs "{\"a\": 1}\n" rs "{\"b\": 2}\n"))
       (in (open-input-string seq-text))
       (gen (json-sequence-read in))
       (r1 (gen))
       (r2 (gen))
       (r3 (gen)))
  (assert-equal "json-sequence item 1" r1 '((a . 1)))
  (assert-equal "json-sequence item 2" r2 '((b . 2)))
  (assert-true "json-sequence eof" (eof-object? r3)))

;; =======================================================================
;; Group 7: Security, Boundaries & Error Conditions
;; =======================================================================
(write-string "--- Group 7: Security & Error Conditions ---\n")

;; Nesting depth limit
(parameterize ((json-nesting-depth-limit 3))
  (assert-json-error "nesting depth limit exceeded"
                     (lambda () (string->json "[[[[1]]]]"))))

;; Character limit
(parameterize ((json-number-of-character-limit 10))
  (assert-json-error "character limit exceeded"
                     (lambda () (string->json "{\"very_long_key_name\": 42}"))))

;; Malformed numbers
(assert-json-error "leading zero rejected"
                   (lambda () (string->json "0123")))
(assert-json-error "trailing decimal point rejected"
                   (lambda () (string->json "1.")))
(assert-json-error "empty exponent rejected"
                   (lambda () (string->json "1e")))
(assert-json-error "leading plus sign rejected"
                   (lambda () (string->json "+1")))

;; Lone surrogates
(assert-json-error "lone high surrogate rejected"
                   (lambda () (string->json "\"\\uD800\"")))
(assert-json-error "lone low surrogate rejected"
                   (lambda () (string->json "\"\\uDC00\"")))

;; Unescaped control characters in string
(assert-json-error "unescaped raw newline in string rejected"
                   (lambda () (string->json "\"\n\"")))
(assert-json-error "unescaped raw tab in string rejected"
                   (lambda () (string->json "\"\t\"")))

;; Trailing comma in array & object
(assert-json-error "trailing comma in array rejected"
                   (lambda () (string->json "[1, 2,]")))
(assert-json-error "trailing comma in object rejected"
                   (lambda () (string->json "{\"a\": 1,}")))

;; Unterminated structures
(assert-json-error "unterminated string rejected"
                   (lambda () (string->json "\"abc")))
(assert-json-error "unterminated array rejected"
                   (lambda () (string->json "[1, 2")))
(assert-json-error "unterminated object rejected"
                   (lambda () (string->json "{\"a\": 1")))

(test-end "srfi-180")
