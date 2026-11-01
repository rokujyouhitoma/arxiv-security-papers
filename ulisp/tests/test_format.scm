;;; =======================================================================
;;; ULisp Test Suite: SRFI 28 Basic Format Strings
;;; Conforms to DSN-33 Architecture Specification & Issue #654
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
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
(write-string "=== Group 1: Basic Strings Without Directives ===")
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
;;; Group 2: Escapes and Newlines (~% and ~~)
;;; -----------------------------------------------------------------------
(write-string "=== Group 2: Escapes and Newlines (~% and ~~) ===")
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

;;; -----------------------------------------------------------------------
;;; Group 3: ~a and ~A Directives (Display Format)
;;; -----------------------------------------------------------------------
(write-string "=== Group 3: ~a and ~A Directives (Display) ===")
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
;;; Group 4: ~s and ~S Directives (Write Format)
;;; -----------------------------------------------------------------------
(write-string "=== Group 4: ~s and ~S Directives (Write) ===")
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

(assert-equal "complex ~a and ~s combination"
              (format "Entry ~a => key: ~a, value: ~s~%" 1 sym-name "Antigravity")
              "Entry 1 => key: name, value: \"Antigravity\"\n")

;;; -----------------------------------------------------------------------
;;; Group 5: First-Class Procedure, Dynamic Calls & Error Handling
;;; -----------------------------------------------------------------------
(write-string "=== Group 5: First-Class Procedure & Error Handling ===")
(write-char #\newline)

;; First-class procedure via apply
(assert-equal "apply format with 0 extra args"
              (apply format '("dynamic static"))
              "dynamic static")

(assert-equal "apply format with 1 arg"
              (apply format (list "val: ~a" 999))
              "val: 999")

(assert-equal "apply format with 3 args"
              (apply format (list "~a ~s ~a" sym-x "y" sym-z))
              "x \"y\" z")

;; Error condition: illegal directive
(assert-true "error on illegal directive ~x"
             (guard (ex (else #t))
               (format "bad: ~x" 1)
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

;;; -----------------------------------------------------------------------
;;; Summary & Exit Code
;;; -----------------------------------------------------------------------
(write-string "------------------------------------------------------------")
(write-char #\newline)
(if (= (vector-ref *test-failures* 0) 0)
    (begin
      (write-string "All SRFI 28 format tests PASSED successfully!")
      (write-char #\newline)
      (exit 0))
    (begin
      (write-string "Test failures detected: ")
      (write (vector-ref *test-failures* 0))
      (write-char #\newline)
      (exit 1)))
