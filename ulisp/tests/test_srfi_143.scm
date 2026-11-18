;;; =======================================================================
;;; ULisp Test Suite: SRFI 143 Fixnums & (scheme fixnum)
;;; Conforms to R7RS-large Tangerine Edition & SRFI 143
;;; Tests:
;;;   Group 1: Constants & Basic Predicates
;;;   Group 2: Comparison Predicates & Min / Max
;;;   Group 3: Basic Arithmetic, Abs, Square, Sqrt
;;;   Group 4: Arithmetic with Carry (fx+/carry, fx-/carry, fx*/carry)
;;;   Group 5: Rounding Division (fxfloor/, fxtruncate/)
;;;   Group 6: Bitwise Operations & Shifts
;;;   Group 7: Boundary & 62-bit Extreme Values
;;; =======================================================================

(test-begin "srfi-143")

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
;; Group 1: Constants & Basic Predicates
;; =======================================================================
(write-string "--- Group 1: Constants & Basic Predicates ---\n")

(assert-equal "fx-width is 62" fx-width 62)
(assert-true "fx-greatest is positive" (fxpositive? fx-greatest))
(assert-true "fx-least is negative" (fxnegative? fx-least))
(assert-equal "fx-greatest + fx-least = -1" (+ fx-greatest fx-least) -1)

(assert-true "fixnum? on 0" (fixnum? 0))
(assert-true "fixnum? on 42" (fixnum? 42))
(assert-true "fixnum? on -42" (fixnum? -42))
(assert-true "fixnum? on fx-greatest" (fixnum? fx-greatest))
(assert-true "fixnum? on fx-least" (fixnum? fx-least))
(assert-false "fixnum? on #f" (fixnum? #f))
(assert-false "fixnum? on symbol" (fixnum? 'foo))
(assert-false "fixnum? on string" (fixnum? "123"))

(assert-true "fxzero? on 0" (fxzero? 0))
(assert-false "fxzero? on 1" (fxzero? 1))
(assert-false "fxzero? on -1" (fxzero? -1))

(assert-true "fxpositive? on 1" (fxpositive? 1))
(assert-false "fxpositive? on 0" (fxpositive? 0))
(assert-false "fxpositive? on -1" (fxpositive? -1))

(assert-true "fxnegative? on -1" (fxnegative? -1))
(assert-false "fxnegative? on 0" (fxnegative? 0))
(assert-false "fxnegative? on 1" (fxnegative? 1))

(assert-true "fxodd? on 1" (fxodd? 1))
(assert-true "fxodd? on -1" (fxodd? -1))
(assert-true "fxodd? on 3" (fxodd? 3))
(assert-false "fxodd? on 0" (fxodd? 0))
(assert-false "fxodd? on 2" (fxodd? 2))

(assert-true "fxeven? on 0" (fxeven? 0))
(assert-true "fxeven? on 2" (fxeven? 2))
(assert-true "fxeven? on -2" (fxeven? -2))
(assert-false "fxeven? on 1" (fxeven? 1))

;; =======================================================================
;; Group 2: Comparison Predicates & Min / Max
;; =======================================================================
(write-string "--- Group 2: Comparison Predicates & Min / Max ---\n")

(assert-true "fx=? single" (fx=? 10))
(assert-true "fx=? two equal" (fx=? 10 10))
(assert-false "fx=? two unequal" (fx=? 10 20))
(assert-true "fx=? multiple equal" (fx=? 5 5 5 5))
(assert-false "fx=? multiple with mismatch" (fx=? 5 5 6 5))

(assert-true "fx<? strict increasing" (fx<? 1 2 3 4))
(assert-false "fx<? equal elements" (fx<? 1 2 2 4))
(assert-false "fx<? decreasing" (fx<? 4 3 2 1))

(assert-true "fx>? strict decreasing" (fx>? 4 3 2 1))
(assert-false "fx>? equal elements" (fx>? 4 2 2 1))
(assert-false "fx>? increasing" (fx>? 1 2 3 4))

(assert-true "fx<=? non-decreasing" (fx<=? 1 2 2 3 4))
(assert-false "fx<=? decreasing" (fx<=? 1 2 1 3))

(assert-true "fx>=? non-increasing" (fx>=? 4 3 3 2 1))
(assert-false "fx>=? increasing" (fx>=? 4 3 4 1))

(assert-equal "fxmax single" (fxmax 42) 42)
(assert-equal "fxmax two" (fxmax 10 20) 20)
(assert-equal "fxmax multiple" (fxmax 10 50 30 20) 50)
(assert-equal "fxmax with negatives" (fxmax -10 -5 -20) -5)

(assert-equal "fxmin single" (fxmin 42) 42)
(assert-equal "fxmin two" (fxmin 10 20) 10)
(assert-equal "fxmin multiple" (fxmin 50 10 30 20) 10)
(assert-equal "fxmin with negatives" (fxmin -10 -5 -20) -20)

;; =======================================================================
;; Group 3: Basic Arithmetic, Abs, Square, Sqrt
;; =======================================================================
(write-string "--- Group 3: Basic Arithmetic, Abs, Square, Sqrt ---\n")

(assert-equal "fx+ zero args" (fx+) 0)
(assert-equal "fx+ 1 arg" (fx+ 42) 42)
(assert-equal "fx+ 2 args" (fx+ 10 20) 30)
(assert-equal "fx+ 4 args" (fx+ 1 2 3 4) 10)

(assert-equal "fx- 1 arg negation" (fx- 42) -42)
(assert-equal "fx- 2 args" (fx- 100 30) 70)
(assert-equal "fx- 3 args" (fx- 100 30 20) 50)
(assert-equal "fxneg positive" (fxneg 42) -42)
(assert-equal "fxneg negative" (fxneg -42) 42)
(assert-equal "fxneg zero" (fxneg 0) 0)

(assert-equal "fx* zero args" (fx*) 1)
(assert-equal "fx* 1 arg" (fx* 42) 42)
(assert-equal "fx* 2 args" (fx* 6 7) 42)
(assert-equal "fx* 4 args" (fx* 2 3 4 5) 120)

(assert-equal "fxquotient positive" (fxquotient 10 3) 3)
(assert-equal "fxquotient negative dividend" (fxquotient -10 3) -3)
(assert-equal "fxquotient negative divisor" (fxquotient 10 -3) -3)
(assert-equal "fxremainder positive" (fxremainder 10 3) 1)
(assert-equal "fxremainder negative dividend" (fxremainder -10 3) -1)

(assert-equal "fxabs positive" (fxabs 42) 42)
(assert-equal "fxabs negative" (fxabs -42) 42)
(assert-equal "fxabs zero" (fxabs 0) 0)

(assert-equal "fxsquare 0" (fxsquare 0) 0)
(assert-equal "fxsquare positive" (fxsquare 7) 49)
(assert-equal "fxsquare negative" (fxsquare -7) 49)

(assert-equal "fxsqrt 0" (fxsqrt 0) 0)
(assert-equal "fxsqrt 1" (fxsqrt 1) 1)
(assert-equal "fxsqrt 4" (fxsqrt 4) 2)
(assert-equal "fxsqrt 9" (fxsqrt 9) 3)
(assert-equal "fxsqrt 15" (fxsqrt 15) 3)
(assert-equal "fxsqrt 16" (fxsqrt 16) 4)
(assert-equal "fxsqrt 1000000" (fxsqrt 1000000) 1000)
(assert-equal "fxsqrt 1000000000000" (fxsqrt 1000000000000) 1000000)

;; =======================================================================
;; Group 4: Arithmetic with Carry (fx+/carry, fx-/carry, fx*/carry)
;; =======================================================================
(write-string "--- Group 4: Arithmetic with Carry ---\n")

;; fx+/carry i j k: i + j + k = carry * 2^62 + sum
(call-with-values
  (lambda () (fx+/carry 10 20 0))
  (lambda (s c)
    (assert-equal "fx+/carry basic sum" s 30)
    (assert-equal "fx+/carry basic carry" c 0)))

(call-with-values
  (lambda () (fx+/carry fx-greatest 1 0))
  (lambda (s c)
    ;; (2^61 - 1) + 1 = 2^61 = -2^61 (signed 62-bit) with carry 1
    (assert-equal "fx+/carry overflow to negative" s fx-least)
    (assert-equal "fx+/carry overflow carry" c 1)))

(call-with-values
  (lambda () (fx+/carry fx-greatest fx-greatest 0))
  (lambda (s c)
    ;; (2^61 - 1) + (2^61 - 1) = 2^62 - 2 = -2 (signed 62-bit) with carry 1
    (assert-equal "fx+/carry large sum" s -2)
    (assert-equal "fx+/carry large carry" c 1)))

;; fx-/carry i j k: i - j - k = borrow * 2^62 + diff
(call-with-values
  (lambda () (fx-/carry 50 20 0))
  (lambda (d b)
    (assert-equal "fx-/carry basic diff" d 30)
    (assert-equal "fx-/carry basic borrow" b 0)))

(call-with-values
  (lambda () (fx-/carry fx-least 1 0))
  (lambda (d b)
    ;; -2^61 - 1 = 2^61 - 1 (signed 62-bit) with borrow -1
    (assert-equal "fx-/carry underflow to positive" d fx-greatest)
    (assert-equal "fx-/carry underflow borrow" b -1)))

(call-with-values
  (lambda () (fx-/carry fx-least fx-greatest 0))
  (lambda (d b)
    ;; -2^61 - (2^61 - 1) = -2^62 + 1 = 1 with borrow -1
    (assert-equal "fx-/carry large diff" d 1)
    (assert-equal "fx-/carry large borrow" b -1)))

;; fx*/carry i j k: i * j + k = high * 2^62 + low
(call-with-values
  (lambda () (fx*/carry 10 20 5))
  (lambda (low high)
    (assert-equal "fx*/carry basic low" low 205)
    (assert-equal "fx*/carry basic high" high 0)))

(call-with-values
  (lambda () (fx*/carry 0 100 42))
  (lambda (low high)
    (assert-equal "fx*/carry zero mul low" low 42)
    (assert-equal "fx*/carry zero mul high" high 0)))

(call-with-values
  (lambda () (fx*/carry 2 (quotient fx-greatest 2) 0)) ; 2 * (2^60 - 1)
  (lambda (low high)
    ;; 2 * 2^60 - 2 = 2^61 - 2
    (assert-equal "fx*/carry 2^61-2 low" low (- fx-greatest 1))
    (assert-equal "fx*/carry 2^61-2 high" high 0)))

;; =======================================================================
;; Group 5: Rounding Division (fxfloor/, fxtruncate/)
;; =======================================================================
(write-string "--- Group 5: Rounding Division ---\n")

(assert-equal "fxtruncate-quotient positive" (fxtruncate-quotient 10 3) 3)
(assert-equal "fxtruncate-remainder positive" (fxtruncate-remainder 10 3) 1)
(assert-equal "fxtruncate-quotient negative dividend" (fxtruncate-quotient -10 3) -3)
(assert-equal "fxtruncate-remainder negative dividend" (fxtruncate-remainder -10 3) -1)

(call-with-values
  (lambda () (fxtruncate/ 10 3))
  (lambda (q r)
    (assert-equal "fxtruncate/ q" q 3)
    (assert-equal "fxtruncate/ r" r 1)))

(assert-equal "fxfloor-quotient positive" (fxfloor-quotient 10 3) 3)
(assert-equal "fxfloor-remainder positive" (fxfloor-remainder 10 3) 1)
(assert-equal "fxfloor-quotient negative dividend" (fxfloor-quotient -10 3) -4)
(assert-equal "fxfloor-remainder negative dividend" (fxfloor-remainder -10 3) 2)

(call-with-values
  (lambda () (fxfloor/ -10 3))
  (lambda (q r)
    (assert-equal "fxfloor/ q" q -4)
    (assert-equal "fxfloor/ r" r 2)))

;; =======================================================================
;; Group 6: Bitwise Operations & Shifts
;; =======================================================================
(write-string "--- Group 6: Bitwise Operations & Shifts ---\n")

(assert-equal "fxnot 0" (fxnot 0) -1)
(assert-equal "fxnot -1" (fxnot -1) 0)
(assert-equal "fxnot 10" (fxnot 10) -11)

(assert-equal "fxand 0-ary" (fxand) -1)
(assert-equal "fxand 1-ary" (fxand 42) 42)
(assert-equal "fxand 2-ary" (fxand 12 10) 8)
(assert-equal "fxand 3-ary" (fxand 15 14 10) 10)

(assert-equal "fxior 0-ary" (fxior) 0)
(assert-equal "fxior 1-ary" (fxior 42) 42)
(assert-equal "fxior 2-ary" (fxior 12 10) 14)
(assert-equal "fxior 3-ary" (fxior 1 2 4) 7)

(assert-equal "fxxor 0-ary" (fxxor) 0)
(assert-equal "fxxor 1-ary" (fxxor 42) 42)
(assert-equal "fxxor 2-ary" (fxxor 12 10) 6)
(assert-equal "fxxor 3-ary" (fxxor 12 10 6) 0)

(assert-equal "fxif test 1" (fxif 3 1 2) 1)
(assert-equal "fxif test 2" (fxif #b1010 #b1100 #b0011) #b1001)

(assert-equal "fxbit-count 0" (fxbit-count 0) 0)
(assert-equal "fxbit-count 7" (fxbit-count 7) 3)
(assert-equal "fxbit-count -1" (fxbit-count -1) 0)
(assert-equal "fxbit-count -2" (fxbit-count -2) 1)

(assert-equal "fxlength 0" (fxlength 0) 0)
(assert-equal "fxlength 1" (fxlength 1) 1)
(assert-equal "fxlength 7" (fxlength 7) 3)
(assert-equal "fxlength 8" (fxlength 8) 4)
(assert-equal "fxlength -1" (fxlength -1) 0)
(assert-equal "fxlength -8" (fxlength -8) 3)

(assert-equal "fxfirst-set-bit 0" (fxfirst-set-bit 0) -1)
(assert-equal "fxfirst-set-bit 1" (fxfirst-set-bit 1) 0)
(assert-equal "fxfirst-set-bit 8" (fxfirst-set-bit 8) 3)
(assert-equal "fxfirst-set-bit 12" (fxfirst-set-bit 12) 2)

(assert-true "fxbit-set? 0 of 1" (fxbit-set? 0 1))
(assert-false "fxbit-set? 1 of 1" (fxbit-set? 1 1))
(assert-true "fxbit-set? 2 of 4" (fxbit-set? 2 4))

(assert-equal "fxcopy-bit set" (fxcopy-bit 2 0 #t) 4)
(assert-equal "fxcopy-bit clear" (fxcopy-bit 2 7 #f) 3)

(assert-equal "fxarithmetic-shift left 2" (fxarithmetic-shift 3 2) 12)
(assert-equal "fxarithmetic-shift right 2" (fxarithmetic-shift 12 -2) 3)
(assert-equal "fxarithmetic-shift-left 2" (fxarithmetic-shift-left 3 2) 12)
(assert-equal "fxarithmetic-shift-right 2" (fxarithmetic-shift-right 12 2) 3)

(assert-equal "fxbit-field extract" (fxbit-field #b110100 2 5) #b101)
(assert-equal "fxbit-field-rotate" (fxbit-field-rotate #b110100 1 2 5) #b101100)
(assert-equal "fxbit-field-reverse" (fxbit-field-reverse #b110100 2 5) #b110100)

;; =======================================================================
;; Group 7: Boundary & 62-bit Extreme Values
;; =======================================================================
(write-string "--- Group 7: Boundary & 62-bit Extreme Values ---\n")

(assert-equal "fx+ greatest + least" (fx+ fx-greatest fx-least) -1)
(assert-equal "fx- greatest - 1" (fx- fx-greatest 1) (- fx-greatest 1))
(assert-equal "fx+ least + 1" (fx+ fx-least 1) (+ fx-least 1))
(assert-equal "fxabs fx-greatest" (fxabs fx-greatest) fx-greatest)
(assert-true "fxpositive? fx-greatest" (fxpositive? fx-greatest))
(assert-true "fxnegative? fx-least" (fxnegative? fx-least))

(test-end "srfi-143")
