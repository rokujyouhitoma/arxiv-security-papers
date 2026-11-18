;;; =======================================================================
;;; ULisp Test Suite: R7RS-large / SRFI 151 (Bitwise Operations) (Issue #857)
;;; Testing:
;;;   1. Basic Boolean Operations:
;;;      bitwise-not, bitwise-and, bitwise-ior, bitwise-xor, bitwise-eqv,
;;;      bitwise-nand, bitwise-nor, bitwise-andc1, bitwise-andc2, bitwise-orc1, bitwise-orc2
;;;   2. Integer Operations & Shift:
;;;      arithmetic-shift, bit-count, integer-length, bitwise-if
;;;   3. Single-Bit Operations:
;;;      bit-set?, copy-bit, bit-swap, any-bit-set?, every-bit-set?, first-set-bit
;;;   4. Bit Field Operations:
;;;      bit-field, bit-field-any?, bit-field-every?, bit-field-clear, bit-field-set,
;;;      bit-field-replace, bit-field-replace-same, bit-field-rotate, bit-field-reverse
;;;   5. Bitwise Fold, Unfold & Generation:
;;;      bitwise-fold, bitwise-for-each, bitwise-unfold, make-bitwise-generator
;;;   6. Conversions:
;;;      bits->list, list->bits, bits->vector, vector->bits, bits
;;;   7. Compatibility Aliases (SRFI 33 / SRFI 60):
;;;      bitwise-merge, extract-bit-field, test-bit-field?, clear-bit-field,
;;;      replace-bit-field, copy-bit-field, ash
;;; =======================================================================

(test-begin "srfi-151")

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
;; Group 1: Basic Boolean Operations
;; =======================================================================
(write-string "--- Group 1: Basic Boolean Operations ---")
(write-char #\newline)

;; bitwise-not
(assert-equal "1.1 bitwise-not 0" (bitwise-not 0) -1)
(assert-equal "1.2 bitwise-not -1" (bitwise-not -1) 0)
(assert-equal "1.3 bitwise-not positive" (bitwise-not 42) -43)
(assert-equal "1.4 bitwise-not negative" (bitwise-not -43) 42)

;; bitwise-and
(assert-equal "1.5 bitwise-and 0-ary" (bitwise-and) -1)
(assert-equal "1.6 bitwise-and 1-ary" (bitwise-and 42) 42)
(assert-equal "1.7 bitwise-and 2-ary" (bitwise-and 6 3) 2)
(assert-equal "1.8 bitwise-and 3-ary" (bitwise-and 7 3 2) 2)
(assert-equal "1.9 bitwise-and with negative" (bitwise-and -1 15) 15)

;; bitwise-ior
(assert-equal "1.10 bitwise-ior 0-ary" (bitwise-ior) 0)
(assert-equal "1.11 bitwise-ior 1-ary" (bitwise-ior 42) 42)
(assert-equal "1.12 bitwise-ior 2-ary" (bitwise-ior 6 3) 7)
(assert-equal "1.13 bitwise-ior 3-ary" (bitwise-ior 1 2 4) 7)
(assert-equal "1.14 bitwise-ior with negative" (bitwise-ior -2 1) -1)

;; bitwise-xor
(assert-equal "1.15 bitwise-xor 0-ary" (bitwise-xor) 0)
(assert-equal "1.16 bitwise-xor 1-ary" (bitwise-xor 42) 42)
(assert-equal "1.17 bitwise-xor 2-ary" (bitwise-xor 6 3) 5)
(assert-equal "1.18 bitwise-xor 3-ary" (bitwise-xor 1 2 3) 0)
(assert-equal "1.19 bitwise-xor with negative" (bitwise-xor -1 5) -6)

;; bitwise-eqv
(assert-equal "1.20 bitwise-eqv 0-ary" (bitwise-eqv) -1)
(assert-equal "1.21 bitwise-eqv 1-ary" (bitwise-eqv 42) 42)
(assert-equal "1.22 bitwise-eqv 2-ary identical" (bitwise-eqv 7 7) -1)
(assert-equal "1.23 bitwise-eqv 2-ary" (bitwise-eqv 6 3) (bitwise-not 5))
(assert-equal "1.24 bitwise-eqv 3-ary" (bitwise-eqv 7 7 7) 7)

;; bitwise-nand, bitwise-nor
(assert-equal "1.25 bitwise-nand" (bitwise-nand 11 26) (bitwise-not (bitwise-and 11 26)))
(assert-equal "1.26 bitwise-nor" (bitwise-nor 11 26) (bitwise-not (bitwise-ior 11 26)))

;; bitwise-andc1, bitwise-andc2
(assert-equal "1.27 bitwise-andc1" (bitwise-andc1 11 26) (bitwise-and (bitwise-not 11) 26))
(assert-equal "1.28 bitwise-andc2" (bitwise-andc2 11 26) (bitwise-and 11 (bitwise-not 26)))

;; bitwise-orc1, bitwise-orc2
(assert-equal "1.29 bitwise-orc1" (bitwise-orc1 11 26) (bitwise-ior (bitwise-not 11) 26))
(assert-equal "1.30 bitwise-orc2" (bitwise-orc2 11 26) (bitwise-ior 11 (bitwise-not 26)))

;; =======================================================================
;; Group 2: Integer Operations & Shift
;; =======================================================================
(write-string "--- Group 2: Integer Operations & Shift ---")
(write-char #\newline)

;; arithmetic-shift
(assert-equal "2.1 arithmetic-shift 0" (arithmetic-shift 42 0) 42)
(assert-equal "2.2 arithmetic-shift left positive" (arithmetic-shift 1 4) 16)
(assert-equal "2.3 arithmetic-shift left negative" (arithmetic-shift -1 4) -16)
(assert-equal "2.4 arithmetic-shift right positive" (arithmetic-shift 16 -3) 2)
(assert-equal "2.5 arithmetic-shift right negative" (arithmetic-shift -16 -3) -2)
(assert-equal "2.6 arithmetic-shift right floor" (arithmetic-shift -1 -1) -1)
(assert-equal "2.7 arithmetic-shift right odd negative" (arithmetic-shift -3 -1) -2)

;; bit-count
(assert-equal "2.8 bit-count 0" (bit-count 0) 0)
(assert-equal "2.9 bit-count 1" (bit-count 1) 1)
(assert-equal "2.10 bit-count 7" (bit-count 7) 3)
(assert-equal "2.11 bit-count 1023" (bit-count 1023) 10)
(assert-equal "2.12 bit-count -1" (bit-count -1) 0)
(assert-equal "2.13 bit-count -2" (bit-count -2) 1)
(assert-equal "2.14 bit-count -8" (bit-count -8) 3)

;; integer-length
(assert-equal "2.15 integer-length 0" (integer-length 0) 0)
(assert-equal "2.16 integer-length 1" (integer-length 1) 1)
(assert-equal "2.17 integer-length 7" (integer-length 7) 3)
(assert-equal "2.18 integer-length 8" (integer-length 8) 4)
(assert-equal "2.19 integer-length -1" (integer-length -1) 0)
(assert-equal "2.20 integer-length -2" (integer-length -2) 1)
(assert-equal "2.21 integer-length -8" (integer-length -8) 3)
(assert-equal "2.22 integer-length -9" (integer-length -9) 4)

;; bitwise-if
(assert-equal "2.23 bitwise-if all 1s mask" (bitwise-if -1 10 20) 10)
(assert-equal "2.24 bitwise-if all 0s mask" (bitwise-if 0 10 20) 20)
(assert-equal "2.25 bitwise-if mixed" (bitwise-if 3 10 20) 22) ; mask=0b0011, 10=0b1010, 20=0b10100 -> (3 & 10) | (~3 & 20) = 2 | 20 = 22

;; =======================================================================
;; Group 3: Single-Bit Operations
;; =======================================================================
(write-string "--- Group 3: Single-Bit Operations ---")
(write-char #\newline)

;; bit-set?
(assert-true "3.1 bit-set? bit 0 of 1" (bit-set? 0 1))
(assert-false "3.2 bit-set? bit 1 of 1" (bit-set? 1 1))
(assert-true "3.3 bit-set? bit 3 of 8" (bit-set? 3 8))
(assert-true "3.4 bit-set? negative bit 100" (bit-set? 100 -1))
(assert-false "3.5 bit-set? zero bit 5" (bit-set? 5 0))

;; copy-bit
(assert-equal "3.6 copy-bit set" (copy-bit 2 0 #t) 4)
(assert-equal "3.7 copy-bit clear" (copy-bit 2 7 #f) 3)
(assert-equal "3.8 copy-bit no-op" (copy-bit 0 1 #t) 1)

;; bit-swap
(assert-equal "3.9 bit-swap different" (bit-swap 0 1 1) 2)
(assert-equal "3.10 bit-swap same" (bit-swap 1 2 7) 7)
(assert-equal "3.11 bit-swap indices equal" (bit-swap 2 2 4) 4)

;; any-bit-set? / every-bit-set?
(assert-true "3.12 any-bit-set? true" (any-bit-set? 3 6))
(assert-false "3.13 any-bit-set? false" (any-bit-set? 1 6))
(assert-true "3.14 every-bit-set? true" (every-bit-set? 6 7))
(assert-false "3.15 every-bit-set? false" (every-bit-set? 6 5))

;; first-set-bit
(assert-equal "3.16 first-set-bit 0" (first-set-bit 0) -1)
(assert-equal "3.17 first-set-bit 1" (first-set-bit 1) 0)
(assert-equal "3.18 first-set-bit 2" (first-set-bit 2) 1)
(assert-equal "3.19 first-set-bit 40" (first-set-bit 40) 3) ; 40 = 0b101000 -> bit 3
(assert-equal "3.20 first-set-bit negative" (first-set-bit -4) 2) ; -4 = ...11111100 -> bit 2

;; =======================================================================
;; Group 4: Bit Field Operations
;; =======================================================================
(write-string "--- Group 4: Bit Field Operations ---")
(write-char #\newline)

;; bit-field
(assert-equal "4.1 bit-field basic" (bit-field 42 1 4) 5) ; 42 = 0b101010, bits [1, 4) = 0b101 = 5
(assert-equal "4.2 bit-field entire" (bit-field 7 0 3) 7)
(assert-equal "4.3 bit-field zero width" (bit-field 42 2 2) 0)

;; bit-field-any? / bit-field-every?
(assert-true "4.4 bit-field-any? true" (bit-field-any? 42 1 4))
(assert-false "4.5 bit-field-any? false" (bit-field-any? 40 0 3))
(assert-true "4.6 bit-field-every? true" (bit-field-every? 15 0 4))
(assert-false "4.7 bit-field-every? false" (bit-field-every? 14 0 4))

;; bit-field-clear / bit-field-set
(assert-equal "4.8 bit-field-clear" (bit-field-clear 42 1 4) 32) ; 42 = 0b101010, clear [1,4) -> 0b100000 = 32
(assert-equal "4.9 bit-field-set" (bit-field-set 32 1 4) 46)   ; 32 | 0b1110 = 46

;; bit-field-replace / bit-field-replace-same
(assert-equal "4.10 bit-field-replace" (bit-field-replace 0 5 1 4) 10) ; 5 = 0b101 -> inserted at [1, 4) -> 0b1010 = 10
(assert-equal "4.11 bit-field-replace-same" (bit-field-replace-same 0 42 1 4) 10)

;; bit-field-rotate
(assert-equal "4.12 bit-field-rotate zero" (bit-field-rotate 42 0 1 4) 42)
(assert-equal "4.13 bit-field-rotate 1" (bit-field-rotate 42 1 1 4) 38) ; field [1,4) was 0b101 (5), rotated left by 1 in 3 bits -> 0b011 (3), replaced into 42 -> 32 | (3<<1) = 38
;; In bit-field-rotate: width=3, c=1. field=0b101 (5).
;; bit-field 0 to (- 3 1)=2 is bits 0,1 -> 0b01 = 1. shifted by 1 -> 2.
;; arithmetic-shift field (- 1 3) = -2 -> 5 >> 2 = 1.
;; ior 2 1 = 3 (0b011).
;; replace into 42 [1,4): 32 | (3 << 1) = 32 | 6 = 38.
(assert-equal "4.13 bit-field-rotate 1 test" (bit-field (bit-field-rotate 42 1 1 4) 1 4) 3)

;; bit-field-reverse
(assert-equal "4.14 bit-field-reverse" (bit-field (bit-field-reverse 42 1 4) 1 4) 5) ; 0b101 reversed is 0b101 (symmetric)
(assert-equal "4.15 bit-field-reverse asymmetric" (bit-field (bit-field-reverse 34 1 4) 1 4) 4) ; 34 = 0b100010. field [1,4) = 0b001 (1). reversed in 3 bits -> 0b100 (4).

;; =======================================================================
;; Group 5: Bitwise Fold, Unfold & Generation
;; =======================================================================
(write-string "--- Group 5: Bitwise Fold, Unfold & Generation ---")
(write-char #\newline)

;; bitwise-fold
(assert-equal "5.1 bitwise-fold popcount"
  (bitwise-fold (lambda (b acc) (if b (+ acc 1) acc)) 0 42)
  3)

;; bitwise-for-each
(assert-equal "5.2 bitwise-for-each"
  (let ((cnt-box (vector 0)))
    (bitwise-for-each (lambda (b) (if b (vector-set! cnt-box 0 (+ (vector-ref cnt-box 0) 1)) #f)) 42)
    (vector-ref cnt-box 0))
  3)

;; bitwise-unfold
(assert-equal "5.3 bitwise-unfold"
  (bitwise-unfold
    (lambda (n) (= n 4))
    (lambda (n) (not (= (remainder n 2) 0)))
    (lambda (n) (+ n 1))
    0)
  10) ; bits at 0,1,2,3: odd?(0)=#f, odd?(1)=#t, odd?(2)=#f, odd?(3)=#t -> 0b1010 = 10

;; make-bitwise-generator
(assert-equal "5.4 make-bitwise-generator"
  (let ((g (make-bitwise-generator 6))) ; 6 = 0b110
    (list (g) (g) (g) (g)))
  '(#f #t #t #f))

;; =======================================================================
;; Group 6: Conversions
;; =======================================================================
(write-string "--- Group 6: Conversions ---")
(write-char #\newline)

;; bits->list / list->bits
(assert-equal "6.1 bits->list" (bits->list 6 4) '(#f #t #t #f))
(assert-equal "6.2 list->bits" (list->bits '(#f #t #t #f)) 6)
(assert-equal "6.3 round-trip list" (list->bits (bits->list 42 6)) 42)

;; bits->vector / vector->bits
(assert-equal "6.4 bits->vector" (bits->vector 6 4) #(#f #t #t #f))
(assert-equal "6.5 vector->bits" (vector->bits #(#f #t #t #f)) 6)
(assert-equal "6.6 round-trip vector" (vector->bits (bits->vector 42 6)) 42)

;; bits constructor
(assert-equal "6.7 bits varargs" (bits #f #t #t #f) 6)

;; =======================================================================
;; Group 7: Compatibility Aliases (SRFI 33 / SRFI 60)
;; =======================================================================
(write-string "--- Group 7: Compatibility Aliases ---")
(write-char #\newline)

(assert-equal "7.1 bitwise-merge" (bitwise-merge 3 10 20) 22)
(assert-equal "7.2 extract-bit-field" (extract-bit-field 42 1 4) 5)
(assert-true "7.3 test-bit-field?" (test-bit-field? 42 1 4))
(assert-equal "7.4 clear-bit-field" (clear-bit-field 42 1 4) 32)
(assert-equal "7.5 replace-bit-field" (replace-bit-field 0 5 1 4) 10)
(assert-equal "7.6 copy-bit-field" (copy-bit-field 0 1 4 5) 10)
(assert-equal "7.7 ash" (ash 1 4) 16)

(test-end "srfi-151")
