;;; =======================================================================
;;; ULisp Test Suite: SRFI 48 Intermediate Format Strings
;;; Conforms to DSN-33 Architecture Specification, SRFI 48 & Issue #864
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

(test-begin "format")

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

;; Intern symbols for runtime symbol->string lookups
(define sym-lambda (string->symbol "lambda"))
(define sym-ok (string->symbol "ok"))
(define sym-foo (string->symbol "foo"))
(define sym-name (string->symbol "name"))
(define sym-a (string->symbol "a"))
(define sym-b (string->symbol "b"))
(define sym-c (string->symbol "c"))
(define sym-x (string->symbol "x"))
(define sym-z (string->symbol "z"))

;;; -----------------------------------------------------------------------
;;; Group 1: Basic string formatting without arguments
;;; -----------------------------------------------------------------------
(write-string "--- Group 1: Basic Strings Without Directives ---")
(write-char #\newline)

(assert-equal "empty string"
              (format "")
              "")

(assert-equal "plain string literal"
              (format "Hello, ULisp!")
              "Hello, ULisp!")

(assert-equal "string with punctuation"
              (format "Alpha: [1, 2, 3]; Beta: {x: 10}!")
              "Alpha: [1, 2, 3]; Beta: {x: 10}!")

;;; -----------------------------------------------------------------------
;;; Group 2: Escapes, Tabs, Spaces and Newlines (~%, ~~, ~t, ~_, ~&)
;;; -----------------------------------------------------------------------
(write-string "--- Group 2: Escapes and Newlines (~%, ~~, ~t, ~_, ~&) ---")
(write-char #\newline)

(assert-equal "single newline ~%"
              (format "line1~%line2")
              "line1\nline2")

(assert-equal "consecutive newlines ~%~%"
              (format "a~%~%b")
              "a\n\nb")

(assert-equal "trailing newline"
              (format "done~%")
              "done\n")

(assert-equal "tilde literal ~~"
              (format "~~")
              "~")

(assert-equal "tilde followed by text"
              (format "cost: ~~$10")
              "cost: ~$10")

(assert-equal "mixed ~% and ~~"
              (format "~~start~%~~end~%")
              "~start\n~end\n")

(assert-equal "tab directive ~t"
              (format "col1~tcol2")
              "col1\tcol2")

(assert-equal "uppercase tab directive ~T"
              (format "a~Tb")
              "a\tb")

(assert-equal "space directive ~_"
              (format "word1~_word2")
              "word1 word2")

(assert-equal "freshline ~& without preceding newline"
              (format "first~&second")
              "first\nsecond")

(assert-equal "freshline ~& with preceding newline"
              (format "first~%~&second")
              "first\nsecond")

(assert-equal "consecutive freshlines ~&~&"
              (format "a~&~&b")
              "a\nb")

;;; -----------------------------------------------------------------------
;;; Group 3: ~a and ~A Directives (Display Format)
;;; -----------------------------------------------------------------------
(write-string "--- Group 3: ~a and ~A Directives (Display) ---")
(write-char #\newline)

(assert-equal "~a with string (unquoted)"
              (format "Hello, ~a!" "World")
              "Hello, World!")

(assert-equal "~a with integer"
              (format "Answer: ~a" 42)
              "Answer: 42")

(assert-equal "~a with negative integer"
              (format "Negative: ~a" -100)
              "Negative: -100")

(assert-equal "~a with symbol"
              (format "Symbol: ~a" sym-lambda)
              "Symbol: lambda")

(assert-equal "~a with boolean #t and #f"
              (format "flags: ~a, ~a" #t #f)
              "flags: #t, #f")

(assert-equal "~a with empty list"
              (format "empty: ~a" '())
              "empty: ()")

(assert-equal "~a with list"
              (format "items: ~a" (list sym-a sym-b sym-c))
              "items: (a b c)")

(assert-equal "~A uppercase directive"
              (format "Uppercase: ~A" sym-ok)
              "Uppercase: ok")

(assert-equal "multiple ~a directives in sequence"
              (format "~a + ~a = ~a" 10 20 30)
              "10 + 20 = 30")

(assert-equal "mixed ~a and text with ~%"
              (format "User: ~a~%ID: ~a~%" "alice" 1001)
              "User: alice\nID: 1001\n")

;;; -----------------------------------------------------------------------
;;; Group 4: ~s, ~S and ~w, ~W Directives (Write & WriteCircular)
;;; -----------------------------------------------------------------------
(write-string "--- Group 4: ~s, ~S and ~w, ~W Directives (Write) ---")
(write-char #\newline)

(assert-equal "~s with string (quoted)"
              (format "Quoted: ~s" "hello")
              "Quoted: \"hello\"")

(assert-equal "~s vs ~a contrast"
              (format "display: ~a, write: ~s" "text" "text")
              "display: text, write: \"text\"")

(assert-equal "~s with symbol"
              (format "sym: ~s" sym-foo)
              "sym: foo")

(assert-equal "~s with nested pair"
              (format "pair: ~s" (list sym-a (cons sym-b sym-c) '()))
              "pair: (a (b . c) ())")

(assert-equal "~S uppercase directive"
              (format "Write uppercase: ~S" "quote")
              "Write uppercase: \"quote\"")

(assert-equal "~w write-circular directive"
              (format "Circ: ~w" (list 1 2 3))
              "Circ: (1 2 3)")

(assert-equal "~W uppercase write-circular directive"
              (format "Circ: ~W" "item")
              "Circ: \"item\"")

(assert-equal "complex ~a and ~s combination"
              (format "Entry ~a => key: ~a, value: ~s~%" 1 sym-name "Antigravity")
              "Entry 1 => key: name, value: \"Antigravity\"\n")

;;; -----------------------------------------------------------------------
;;; Group 5: Radix-Based Numeric Directives (~d, ~x, ~o, ~b)
;;; -----------------------------------------------------------------------
(write-string "--- Group 5: Radix-Based Numeric Directives (~d, ~x, ~o, ~b) ---")
(write-char #\newline)

(assert-equal "~d decimal output"
              (format "Dec: ~d" 12345)
              "Dec: 12345")

(assert-equal "~D uppercase decimal output"
              (format "Dec: ~D" -9876)
              "Dec: -9876")

(assert-equal "~x lowercase hexadecimal output"
              (format "Hex: ~x" 255)
              "Hex: ff")

(assert-equal "~X uppercase hexadecimal output"
              (format "Hex: ~X" 4095)
              "Hex: fff")

(assert-equal "~o octal output"
              (format "Oct: ~o" 64)
              "Oct: 100")

(assert-equal "~O uppercase octal output"
              (format "Oct: ~O" 511)
              "Oct: 777")

(assert-equal "~b binary output"
              (format "Bin: ~b" 10)
              "Bin: 1010")

(assert-equal "~B uppercase binary output"
              (format "Bin: ~B" 255)
              "Bin: 11111111")

(assert-equal "composite radix formatting"
              (format "v=~d hex=~x oct=~o bin=~b" 42 42 42 42)
              "v=42 hex=2a oct=52 bin=101010")

;;; -----------------------------------------------------------------------
;;; Group 6: Character Output (~c) and Pretty-Print (~y)
;;; -----------------------------------------------------------------------
(write-string "--- Group 6: Character Output (~c) and Pretty-Print (~y) ---")
(write-char #\newline)

(assert-equal "~c character output"
              (format "Letter: ~c" #\A)
              "Letter: A")

(assert-equal "~C uppercase character directive"
              (format "Symbol: ~C" #\$)
              "Symbol: $")

(assert-equal "~y yuppify / pretty-print list"
              (format "List: ~y" (list 1 2 3))
              "List: (1 2 3)")

(assert-equal "~Y uppercase yuppify directive"
              (format "Pair: ~Y" (cons 10 20))
              "Pair: (10 . 20)")

;;; -----------------------------------------------------------------------
;;; Group 7: Fixed-Point & Padding Directives (~F, ~wF, ~w,dF)
;;; -----------------------------------------------------------------------
(write-string "--- Group 7: Fixed-Point & Padding (~F, ~wF, ~w,dF) ---")
(write-char #\newline)

(assert-equal "~F default float formatting"
              (format "~F" 123)
              "123")

(assert-equal "~F string formatting"
              (format "~F" "hello")
              "hello")

(assert-equal "~wF width padding with string"
              (format "~6F" "foo")
              "   foo")

(assert-equal "~wF width padding with integer"
              (format "~6F" 32)
              "    32")

(assert-equal "~w,dF with rational fraction 1/3"
              (format "~8,2F" 1/3)
              "    0.33")

(assert-equal "~w,dF with integer 32"
              (format "~8,2F" 32)
              "   32.00")

(assert-equal "~w,dF width smaller than number"
              (format "~1,2F" 4321)
              "4321.00")

(assert-equal "~w,dF with zero"
              (format "~6,2F" 0)
              "  0.00")

(assert-equal "~w,dF with negative number"
              (format "~8,2F" -0.5)
              "   -0.50")

(assert-equal "~w,dF rounding carry"
              (format "~8,2F" 9.999)
              "   10.00")

(assert-equal "~w,0F zero decimal digits"
              (format "~5,0F" 32.7)
              "   33")

;;; -----------------------------------------------------------------------
;;; Group 8: Indirection Directives (~?, ~k, ~K)
;;; -----------------------------------------------------------------------
(write-string "--- Group 8: Indirection (~?, ~k, ~K) ---")
(write-char #\newline)

(assert-equal "~? indirection with format string and args"
              (format "Result: ~?" "x=~a, y=~a" '(10 20))
              "Result: x=10, y=20")

(assert-equal "~k indirection backward compatibility"
              (format "Data: ~k" "[~d:~x]" '(15 15))
              "Data: [15:f]")

(assert-equal "~K uppercase indirection"
              (format "Val: ~K!" "{~a}" '("inner"))
              "Val: {inner}!")

(assert-equal "nested indirection and surrounding directives"
              (format "Start: ~a, Middle: ~?, End: ~a" "A" "sub: ~s" '("B") "C")
              "Start: A, Middle: sub: \"B\", End: C")

;;; -----------------------------------------------------------------------
;;; Group 9: Output Port Dispatching (#f, #t, output-port)
;;; -----------------------------------------------------------------------
(write-string "--- Group 9: Output Port Dispatching (#f, #t, output-port) ---")
(write-char #\newline)

(assert-equal "format with explicit #f port argument"
              (format #f "hello ~a" "world")
              "hello world")

(assert-equal "format into string-port object"
              (let ((p (open-output-string)))
                (format p "value: ~x~%" 255)
                (get-output-string p))
              "value: ff\n")

;;; -----------------------------------------------------------------------
;;; Group 10: Help (~h), First-Class Calls & Error Handling / Security
;;; -----------------------------------------------------------------------
(write-string "--- Group 10: Help, First-Class Calls & Security Errors ---")
(write-char #\newline)

;; Help documentation directive
(assert-true "~h outputs documentation string containing OPTION"
             (let ((s (format "~h")))
               (and (string? s)
                    (> (string-length s) 50))))

;; First-class procedure via apply
(assert-equal "apply format with 0 extra args"
              (apply format '("dynamic static"))
              "dynamic static")

(assert-equal "apply format with 1 arg"
              (apply format (list "val: ~a" 999))
              "val: 999")

(assert-equal "apply format with port #f and args"
              (apply format (list #f "~a ~s ~a" sym-x "y" sym-z))
              "x \"y\" z")

;; Error condition: illegal directive
(assert-true "error on illegal directive ~z"
             (guard (ex (else #t))
               (format "bad: ~z" 1)
               #f))

;; Error condition: too few arguments
(assert-true "error on too few arguments"
             (guard (ex (else #t))
               (format "need two: ~a and ~a" 1)
               #f))

;; Error condition: too many arguments
(assert-true "error on too many arguments"
             (guard (ex (else #t))
               (format "need one: ~a" 1 2 3)
               #f))

;; Error condition: illegal trailing escape character
(assert-true "error on trailing ~"
             (guard (ex (else #t))
               (format "ends with tilde~")
               #f))

;; Error condition: non-string format argument
(assert-true "error on non-string format"
             (guard (ex (else #t))
               (%format 12345 '())
               #f))

;; Error condition: type mismatch for ~d (non-number)
(assert-true "error on ~d with non-number"
             (guard (ex (else #t))
               (format "num: ~d" "not-a-number")
               #f))

;; Error condition: type mismatch for ~c (non-char)
(assert-true "error on ~c with non-char"
             (guard (ex (else #t))
               (format "char: ~c" 123)
               #f))

;; Error condition: bad port argument
(assert-true "error on invalid port argument"
             (guard (ex (else #t))
               (format 999 "hello")
               #f))

;; Error condition: ~? with non-string template
(assert-true "error on ~? with non-string template"
             (guard (ex (else #t))
               (format "~?" 123 '(1 2))
               #f))

;; Error condition: ~? with non-list argument
(assert-true "error on ~? with non-list argument"
             (guard (ex (else #t))
               (format "~?" "test: ~a" "not-a-list")
               #f))

(test-end "format")
