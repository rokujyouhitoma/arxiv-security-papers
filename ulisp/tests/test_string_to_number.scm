;;; =======================================================================
;;; ULisp Test Suite: R7RS §6.2.6 string->number and Radix Support
;;; Conforms to Issue #652
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

;;; -----------------------------------------------------------------------
;;; Group 1: Basic Decimal Parsing (radix 10)
;;; -----------------------------------------------------------------------
(write-string "--- Group 1: Basic Decimal Parsing ---")
(write-char #\newline)

(assert-equal "decimal 0" (string->number "0") 0)
(assert-equal "decimal positive" (string->number "42") 42)
(assert-equal "decimal with plus" (string->number "+42") 42)
(assert-equal "decimal negative" (string->number "-42") -42)
(assert-equal "decimal large" (string->number "1000000") 1000000)
(assert-equal "decimal explicit radix 10" (string->number "123" 10) 123)
(assert-equal "decimal explicit radix 10 negative" (string->number "-999" 10) -999)

;;; -----------------------------------------------------------------------
;;; Group 2: Explicit Radix Parameter (2, 8, 10, 16)
;;; -----------------------------------------------------------------------
(write-string "--- Group 2: Explicit Radix Parameter ---")
(write-char #\newline)

;; Radix 2 (Binary)
(assert-equal "binary 0" (string->number "0" 2) 0)
(assert-equal "binary 1" (string->number "1" 2) 1)
(assert-equal "binary 1010" (string->number "1010" 2) 10)
(assert-equal "binary 11111111" (string->number "11111111" 2) 255)
(assert-equal "binary negative" (string->number "-101" 2) -5)
(assert-equal "binary with plus" (string->number "+101" 2) 5)

;; Radix 8 (Octal)
(assert-equal "octal 0" (string->number "0" 8) 0)
(assert-equal "octal 77" (string->number "77" 8) 63)
(assert-equal "octal negative" (string->number "-17" 8) -15)
(assert-equal "octal 755" (string->number "+755" 8) 493)

;; Radix 16 (Hexadecimal)
(assert-equal "hex 0" (string->number "0" 16) 0)
(assert-equal "hex lowercase ff" (string->number "ff" 16) 255)
(assert-equal "hex uppercase FF" (string->number "FF" 16) 255)
(assert-equal "hex mixed 1a2b" (string->number "1a2b" 16) 6699)
(assert-equal "hex negative" (string->number "-ff" 16) -255)
(assert-equal "hex with plus" (string->number "+dead" 16) 57005)

;;; -----------------------------------------------------------------------
;;; Group 3: Radix & Exactness Prefixes
;;; -----------------------------------------------------------------------
(write-string "--- Group 3: Radix & Exactness Prefixes ---")
(write-char #\newline)

(assert-equal "prefix #b1010" (string->number "#b1010") 10)
(assert-equal "prefix #B1010" (string->number "#B1010") 10)
(assert-equal "prefix #o77" (string->number "#o77") 63)
(assert-equal "prefix #O77" (string->number "#O77") 63)
(assert-equal "prefix #d42" (string->number "#d42") 42)
(assert-equal "prefix #D42" (string->number "#D42") 42)
(assert-equal "prefix #xff" (string->number "#xff") 255)
(assert-equal "prefix #XFF" (string->number "#XFF") 255)
(assert-equal "prefix #e42" (string->number "#e42") 42)
(assert-equal "prefix #E42" (string->number "#E42") 42)
(assert-equal "prefix #e#x1f" (string->number "#e#x1f") 31)
(assert-equal "prefix #x#e1f" (string->number "#x#e1f") 31)

;; Prefix and sign order permutations
(assert-equal "prefix #x-1f" (string->number "#x-1f") -31)
(assert-equal "prefix -#x1f" (string->number "-#x1f") -31)
(assert-equal "prefix #x+1f" (string->number "#x+1f") 31)
(assert-equal "prefix +#x1f" (string->number "+#x1f") 31)
(assert-equal "prefix #b-101" (string->number "#b-101") -5)
(assert-equal "prefix -#b101" (string->number "-#b101") -5)

;;; -----------------------------------------------------------------------
;;; Group 4: Radix Consistency Validation
;;; -----------------------------------------------------------------------
(write-string "--- Group 4: Radix Consistency Validation ---")
(write-char #\newline)

;; Matching prefix and radix argument
(assert-equal "matching #b and radix 2" (string->number "#b101" 2) 5)
(assert-equal "matching #o and radix 8" (string->number "#o77" 8) 63)
(assert-equal "matching #d and radix 10" (string->number "#d100" 10) 100)
(assert-equal "matching #x and radix 16" (string->number "#xff" 16) 255)

;; Conflicting prefix and radix argument -> must return #f
(assert-false "conflicting #b with radix 10" (string->number "#b101" 10))
(assert-false "conflicting #x with radix 10" (string->number "#xff" 10))
(assert-false "conflicting #x with radix 8" (string->number "#xff" 8))
(assert-false "conflicting #o with radix 16" (string->number "#o77" 16))
(assert-false "conflicting #d with radix 16" (string->number "#d123" 16))

;;; -----------------------------------------------------------------------
;;; Group 5: Error Cases, Malformed Inputs & CWE-190 Fixnum Hardening
;;; -----------------------------------------------------------------------
(write-string "--- Group 5: Error Cases & Fixnum Overflow Hardening ---")
(write-char #\newline)

;; Malformed syntax
(assert-false "empty string" (string->number ""))
(assert-false "only plus" (string->number "+"))
(assert-false "only minus" (string->number "-"))
(assert-false "only prefix #x" (string->number "#x"))
(assert-false "only prefix #b" (string->number "#b"))
(assert-false "invalid digit for base 10" (string->number "12a"))
(assert-false "invalid digit for base 2" (string->number "102" 2))
(assert-false "invalid digit for base 8" (string->number "88" 8))
(assert-false "invalid digit for base 16" (string->number "12g" 16))
(assert-false "pure symbol string" (string->number "abc"))
(assert-equal "inexact prefix #i" (string->number "#i123") (inexact 123))
(assert-false "non-string argument" (string->number 123))
(assert-false "unsupported radix 3" (string->number "10" 3))
(assert-false "unsupported radix 36" (string->number "10" 36))

;; Fixnum boundaries: MAX = 288230376151711743 (2^58 - 1), MIN = -288230376151711744 (-2^58)
(assert-equal "fixnum max decimal"
              (string->number "288230376151711743")
              288230376151711743)
(assert-equal "fixnum min decimal"
              (string->number "-288230376151711744")
              -288230376151711744)
(assert-false "fixnum max + 1 overflow"
              (string->number "288230376151711744"))
(assert-false "fixnum min - 1 underflow"
              (string->number "-288230376151711745"))
(assert-false "huge number overflow"
              (string->number "99999999999999999999999999999999"))

(assert-equal "fixnum max hex"
              (string->number "#x03ffffffffffffff")
              288230376151711743)
(assert-false "fixnum max hex overflow"
              (string->number "#x0400000000000000"))
(assert-equal "fixnum min hex"
              (string->number "-#x0400000000000000")
              -288230376151711744)
(assert-false "fixnum min hex underflow"
              (string->number "-#x0400000000000001"))

;;; -----------------------------------------------------------------------
;;; Group 6: S-Expression Reader Integration
;;; -----------------------------------------------------------------------
(write-string "--- Group 6: S-Expression Reader Integration ---")
(write-char #\newline)

(assert-equal "read binary literal"
              (read (open-input-string "#b1011"))
              11)
(assert-equal "read octal literal"
              (read (open-input-string "#o755"))
              493)
(assert-equal "read decimal literal"
              (read (open-input-string "#d12345"))
              12345)
(assert-equal "read hex lowercase literal"
              (read (open-input-string "#xcafe"))
              51966)
(assert-equal "read hex uppercase literal"
              (read (open-input-string "#XDEAD"))
              57005)
(assert-equal "read negative hex literal"
              (read (open-input-string "-#xff"))
              -255)
(assert-equal "read compound expression with radix literals"
              (read (open-input-string "(+ #x10 #b101)"))
              '(+ 16 5))

;;; -----------------------------------------------------------------------
;;; Summary & Exit
;;; -----------------------------------------------------------------------
(write-string "=== ULisp R7RS string->number Tests Completed: ")
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

