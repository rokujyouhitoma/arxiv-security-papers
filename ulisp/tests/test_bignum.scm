;;; =======================================================================
;;; ULisp Test Suite: Pure Scheme Bignum Arithmetic (tests/test_bignum.scm)
;;; Conforms to DSN-38 §2 A1/B1 & Issue #832
;;; =======================================================================

(test-begin "bignum")

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
;; Group 1: Constructors, Predicates & Normalization
;; =======================================================================
(write-string "--- Group 1: Constructors & Normalization ---\n")

(let ((z (bignum-zero))
      (one (bignum-one))
      (custom (make-bignum 1 (vector 42))))
  (assert-true "bignum? on bignum-zero" (bignum? z))
  (assert-true "bignum? on bignum-one" (bignum? one))
  (assert-true "bignum? on custom" (bignum? custom))
  (assert-false "bignum? on fixnum" (bignum? 42))
  (assert-false "bignum? on symbol" (bignum? 'hello))
  (assert-false "bignum? on ordinary vector" (bignum? (vector 1 2 3)))

  (assert-equal "bignum-sign of zero" (bignum-sign z) 0)
  (assert-equal "bignum-sign of one" (bignum-sign one) 1)
  (assert-true "bignum-zero? on zero" (bignum-zero? z))
  (assert-false "bignum-zero? on one" (bignum-zero? one))
  (assert-true "bignum-positive? on one" (bignum-positive? one))
  (assert-false "bignum-positive? on zero" (bignum-positive? z))

  ;; Normalization: strips trailing zero limbs
  (let* ((unnormalized (vector 10 20 0 0))
         (norm (bignum-normalize 1 unnormalized)))
    (assert-equal "normalized length" (bignum-num-limbs norm) 2)
    (assert-equal "normalized limb 0" (vector-ref (bignum-limbs norm) 0) 10)
    (assert-equal "normalized limb 1" (vector-ref (bignum-limbs norm) 1) 20))

  ;; All-zeros normalization returns bignum-zero
  (let* ((all-zeros (vector 0 0 0))
         (norm-z (bignum-normalize 1 all-zeros)))
    (assert-true "all zeros normalizes to zero" (bignum-zero? norm-z))
    (assert-equal "zero limbs count" (bignum-num-limbs norm-z) 0)))

;; =======================================================================
;; Group 2: Fixnum <-> Bignum Conversions
;; =======================================================================
(write-string "--- Group 2: Fixnum <-> Bignum Conversions ---\n")

(assert-equal "fixnum->bignum 0" (bignum->fixnum (fixnum->bignum 0)) 0)
(assert-equal "fixnum->bignum 1" (bignum->fixnum (fixnum->bignum 1)) 1)
(assert-equal "fixnum->bignum -1" (bignum->fixnum (fixnum->bignum -1)) -1)
(assert-equal "fixnum->bignum 1073741823" (bignum->fixnum (fixnum->bignum 1073741823)) 1073741823)
(assert-equal "fixnum->bignum 1073741824" (bignum->fixnum (fixnum->bignum 1073741824)) 1073741824)
(assert-equal "fixnum->bignum -1073741824" (bignum->fixnum (fixnum->bignum -1073741824)) -1073741824)

;; Multi-limb fixnum (60-bit integer)
(let ((big-val (+ 123456789 (* 987654321 1073741824))))
  (assert-equal "fixnum roundtrip 60-bit" (bignum->fixnum (fixnum->bignum big-val)) big-val)
  (assert-equal "fixnum roundtrip -60-bit" (bignum->fixnum (fixnum->bignum (- 0 big-val))) (- 0 big-val)))

;; =======================================================================
;; Group 3: Comparisons
;; =======================================================================
(write-string "--- Group 3: Comparisons ---\n")

(let ((zero (bignum-zero))
      (one (bignum-one))
      (neg-one (bignum-negate (bignum-one)))
      (two (fixnum->bignum 2))
      (big1 (fixnum->bignum 2000000000))
      (big2 (fixnum->bignum 3000000000)))

  (assert-equal "bignum-cmp 0 0" (bignum-cmp zero zero) 0)
  (assert-equal "bignum-cmp 1 0" (bignum-cmp one zero) 1)
  (assert-equal "bignum-cmp -1 0" (bignum-cmp neg-one zero) -1)
  (assert-equal "bignum-cmp 1 2" (bignum-cmp one two) -1)
  (assert-equal "bignum-cmp 2 1" (bignum-cmp two one) 1)
  (assert-equal "bignum-cmp -1 -2" (bignum-cmp neg-one (bignum-negate two)) 1)

  (assert-true "bignum=? zero zero" (bignum=? zero zero))
  (assert-true "bignum<? 1 2" (bignum<? one two))
  (assert-true "bignum<=? 1 1" (bignum<=? one one))
  (assert-true "bignum<=? 1 2" (bignum<=? one two))
  (assert-true "bignum>? 2 1" (bignum>? two one))
  (assert-true "bignum>=? 2 2" (bignum>=? two two))
  (assert-true "bignum>=? 2 1" (bignum>=? two one))
  (assert-true "bignum<? big1 big2" (bignum<? big1 big2)))

;; =======================================================================
;; Group 4: Addition & Subtraction
;; =======================================================================
(write-string "--- Group 4: Addition & Subtraction ---\n")

(let ((b10 (fixnum->bignum 10))
      (b20 (fixnum->bignum 20))
      (b30 (fixnum->bignum 30))
      (b-10 (fixnum->bignum -10))
      (b-20 (fixnum->bignum -20)))

  (assert-true "10 + 20 = 30" (bignum=? (bignum-add b10 b20) b30))
  (assert-true "20 - 10 = 10" (bignum=? (bignum-sub b20 b10) b10))
  (assert-true "10 - 20 = -10" (bignum=? (bignum-sub b10 b20) b-10))
  (assert-true "10 + (-10) = 0" (bignum-zero? (bignum-add b10 b-10)))
  (assert-true "(-10) + (-20) = -30" (bignum=? (bignum-add b-10 b-20) (fixnum->bignum -30)))
  (assert-true "(-10) - (-20) = 10" (bignum=? (bignum-sub b-10 b-20) b10))

  ;; Radix boundary carry: (2^30 - 1) + 1 = 2^30
  (let* ((max-limb (fixnum->bignum 1073741823))
         (sum (bignum-add max-limb (bignum-one))))
    (assert-equal "limbs after boundary carry" (bignum-num-limbs sum) 2)
    (assert-equal "limb 0" (vector-ref (bignum-limbs sum) 0) 0)
    (assert-equal "limb 1" (vector-ref (bignum-limbs sum) 1) 1))

  ;; Radix boundary borrow: 2^30 - 1 = 2^30 - 1
  (let* ((two-30 (bignum-shift-left (bignum-one) 30))
         (diff (bignum-sub two-30 (bignum-one))))
    (assert-equal "limbs after borrow" (bignum-num-limbs diff) 1)
    (assert-equal "limb 0" (vector-ref (bignum-limbs diff) 0) 1073741823)))

;; =======================================================================
;; Group 5: Multiplication
;; =======================================================================
(write-string "--- Group 5: Multiplication ---\n")

(assert-true "123 * 0 = 0" (bignum-zero? (bignum-mul (fixnum->bignum 123) (bignum-zero))))
(assert-true "0 * 123 = 0" (bignum-zero? (bignum-mul (bignum-zero) (fixnum->bignum 123))))
(assert-true "123 * 1 = 123" (bignum=? (bignum-mul (fixnum->bignum 123) (bignum-one)) (fixnum->bignum 123)))
(assert-true "12 * 34 = 408" (bignum=? (bignum-mul (fixnum->bignum 12) (fixnum->bignum 34)) (fixnum->bignum 408)))
(assert-true "12 * (-34) = -408" (bignum=? (bignum-mul (fixnum->bignum 12) (fixnum->bignum -34)) (fixnum->bignum -408)))
(assert-true "(-12) * (-34) = 408" (bignum=? (bignum-mul (fixnum->bignum -12) (fixnum->bignum -34)) (fixnum->bignum 408)))

;; Large multi-limb multiplication: 123456789 * 987654321 = 121932631112635269
(let* ((a (fixnum->bignum 123456789))
       (b (fixnum->bignum 987654321))
       (prod (bignum-mul a b)))
  (assert-equal "multi-limb product string" (bignum->string prod 10) "121932631112635269"))

;; Factorial 20! = 2432902008176640000
(let loop ((i 1) (acc (bignum-one)))
  (if (> i 20)
      (assert-equal "20! factorial string" (bignum->string acc 10) "2432902008176640000")
      (loop (+ i 1) (bignum-mul acc (fixnum->bignum i)))))

;; =======================================================================
;; Group 6: Division & Remainder (Knuth Algorithm D)
;; =======================================================================
(write-string "--- Group 6: Division & Remainder ---\n")

;; Single-limb divisor
(let ((u (fixnum->bignum 100))
      (v (fixnum->bignum 7)))
  (call-with-values (lambda () (bignum-div-rem u v))
    (lambda (q r)
      (assert-equal "100 / 7 quotient" (bignum->fixnum q) 14)
      (assert-equal "100 / 7 remainder" (bignum->fixnum r) 2))))

;; Division identity: u = q * v + r, with 0 <= r < |v|
(let* ((u (bignum-add (bignum-shift-left (fixnum->bignum 987654321) 60)
                      (fixnum->bignum 123456789)))
       (v (bignum-add (bignum-shift-left (fixnum->bignum 111111111) 30)
                      (fixnum->bignum 222222222))))
  (call-with-values (lambda () (bignum-div-rem u v))
    (lambda (q r)
      (let ((recon (bignum-add (bignum-mul q v) r)))
        (assert-true "Knuth D division theorem u == q*v + r" (bignum=? u recon))
        (assert-true "Knuth D remainder < divisor" (bignum<? r v))
        (assert-true "Knuth D remainder >= 0" (bignum>=? r (bignum-zero)))))))

;; Negative divisions
(assert-equal "quotient (-100, 7)" (bignum->fixnum (bignum-quotient (fixnum->bignum -100) (fixnum->bignum 7))) -14)
(assert-equal "remainder (-100, 7)" (bignum->fixnum (bignum-remainder (fixnum->bignum -100) (fixnum->bignum 7))) -2)
(assert-equal "modulo (-100, 7)" (bignum->fixnum (bignum-modulo (fixnum->bignum -100) (fixnum->bignum 7))) 5)

;; =======================================================================
;; Group 7: Bitwise Shifts & Logic Operations
;; =======================================================================
(write-string "--- Group 7: Bitwise Shifts & Logic ---\n")

;; Shift left & right
(let ((one (bignum-one)))
  (assert-equal "1 << 0" (bignum->fixnum (bignum-shift-left one 0)) 1)
  (assert-equal "1 << 10" (bignum->fixnum (bignum-shift-left one 10)) 1024)
  (assert-equal "1 << 30" (bignum->fixnum (bignum-shift-left one 30)) 1073741824)
  (let ((two-60 (bignum-shift-left one 60)))
    (assert-equal "2^60 >> 30" (bignum->fixnum (bignum-shift-right two-60 30)) 1073741824)
    (assert-equal "2^60 >> 60" (bignum->fixnum (bignum-shift-right two-60 60)) 1)))

;; Arithmetic right shift on negative numbers
(assert-equal "-5 >> 1" (bignum->fixnum (bignum-shift-right (fixnum->bignum -5) 1)) -3)
(assert-equal "-1 >> 5" (bignum->fixnum (bignum-shift-right (fixnum->bignum -1) 5)) -1)
(assert-equal "-16 >> 2" (bignum->fixnum (bignum-shift-right (fixnum->bignum -16) 2)) -4)

;; Bitwise logic
(let ((a (fixnum->bignum 12))  ; 1100
      (b (fixnum->bignum 10))) ; 1010
  (assert-equal "12 AND 10" (bignum->fixnum (bignum-bitwise-and a b)) 8)   ; 1000
  (assert-equal "12 IOR 10" (bignum->fixnum (bignum-bitwise-ior a b)) 14)  ; 1110
  (assert-equal "12 XOR 10" (bignum->fixnum (bignum-bitwise-xor a b)) 6)   ; 0110
  (assert-equal "NOT 0" (bignum->fixnum (bignum-bitwise-not (bignum-zero))) -1)
  (assert-equal "NOT -1" (bignum->fixnum (bignum-bitwise-not (fixnum->bignum -1))) 0))

;; =======================================================================
;; Group 8: 64-bit Modulo Arithmetic (Modulo 2^64)
;; =======================================================================
(write-string "--- Group 8: 64-bit Modulo Arithmetic ---\n")

(let* ((max-u64 (bignum-sub (bignum-shift-left (bignum-one) 64) (bignum-one)))
       (wrap-add (bignum-u64-add max-u64 (bignum-one)))
       (wrap-sub (bignum-u64-sub (bignum-zero) (bignum-one))))
  (assert-true "max-u64 + 1 == 0 mod 2^64" (bignum-zero? wrap-add))
  (assert-equal "0 - 1 == max-u64 mod 2^64" (bignum->string wrap-sub 16) "ffffffffffffffff")

  ;; u64 multiplication overflow
  (let* ((x (bignum-shift-left (bignum-one) 32))
         (x-sq (bignum-u64-mul x x)))
    (assert-true "(2^32)^2 == 0 mod 2^64" (bignum-zero? x-sq)))

  ;; s64 sign extension
  (let ((s-min (bignum-shift-left (bignum-one) 63)))
    (assert-true "s64-mask negative" (bignum-negative? (bignum-s64-mask s-min)))))

;; =======================================================================
;; Group 9: String Parsing & Formatting (Radix 2, 8, 10, 16)
;; =======================================================================
(write-string "--- Group 9: String Conversions ---\n")

(assert-equal "string->bignum 10" (bignum->string (string->bignum "12345678901234567890" 10) 10) "12345678901234567890")
(assert-equal "string->bignum negative" (bignum->string (string->bignum "-98765432109876543210" 10) 10) "-98765432109876543210")
(assert-equal "string->bignum hex 0xdeadbeef" (bignum->string (string->bignum "0xdeadbeef" 16) 16) "deadbeef")
(assert-equal "string->bignum binary" (bignum->string (string->bignum "11010110" 2) 2) "11010110")
(assert-equal "string->bignum octal" (bignum->string (string->bignum "755" 8) 8) "755")

;; =======================================================================
;; Group 10: Automatic Fixnum Overflow Promotion & Demotion (+, -, *, /, quotient, modulo, gcd, lcm)
;; =======================================================================
(write-string "--- Group 10: Automatic Overflow Promotion & Demotion ---\n")

(let* ((fx-max (+ (* 1073741824 2147483647) 1073741823)) ; 2^61 - 1
       (fx-min (- 0 fx-max))
       (ovf-pos (+ fx-max 1))
       (ovf-neg (- fx-min 2)))
  (assert-true "fx-max is fixnum" (fixnum? fx-max))
  (assert-true "fx-max + 1 promotes to bignum" (bignum? ovf-pos))
  (assert-true "fx-min - 2 promotes to bignum" (bignum? ovf-neg))
  (assert-equal "2^61 decimal string"
                (number->string ovf-pos)
                "2305843009213693952")
  ;; Demotion back to fixnum
  (let ((back (- ovf-pos 1)))
    (assert-true "ovf-pos - 1 demotes back to fixnum" (fixnum? back))
    (assert-equal "ovf-pos - 1 == fx-max" back fx-max))
  (let ((back2 (+ ovf-neg 2)))
    (assert-true "ovf-neg + 2 demotes back to fixnum" (fixnum? back2))
    (assert-equal "ovf-neg + 2 == fx-min" back2 fx-min))
  ;; Unary negation overflow & roundtrip
  (let* ((p58 (+ 288230376151711743 1))
         (p60 (* p58 4))
         (fx-least-val (- (- 0 p60) p60))
         (neg-least (- fx-least-val)))
    (assert-true "-fx-least promotes to bignum" (bignum? neg-least))
    (assert-equal "-fx-least exact value" (number->string neg-least) "2305843009213693952")
    (assert-equal "(- (-fx-least)) equals fx-least" (- neg-least) fx-least-val))
  ;; Multiplication overflow & exact quotient/remainder/modulo demotion
  (let ((big-prod (* 1000000000000 1000000000000)))
    (assert-true "10^12 * 10^12 promotes to bignum" (bignum? big-prod))
    (assert-equal "10^24 decimal string" (number->string big-prod) "1000000000000000000000000")
    (let ((q (quotient big-prod 1000000000000)))
      (assert-true "quotient demotes back to fixnum" (fixnum? q))
      (assert-equal "10^24 / 10^12 == 10^12" q 1000000000000))
    (assert-equal "remainder on bignum" (remainder (+ big-prod 42) 100) 42)
    (assert-equal "modulo on negative bignum" (modulo (- 0 big-prod 3) 10) 7))
  ;; gcd & lcm on bignums
  (let ((g (gcd (* 1000000000000 1000000000000 6)
                (* 1000000000000 1000000000000 15))))
    (assert-equal "gcd on bignums"
                  (number->string g)
                  "3000000000000000000000000"))
  (let ((l (lcm (* 1000000000000 1000000000000 2)
                (* 1000000000000 1000000000000 3))))
    (assert-equal "lcm on bignums"
                  (number->string l)
                  "6000000000000000000000000")))

;; =======================================================================
;; Group 11: 100! Factorial & (expt 2 1000) Exact Arithmetic
;; =======================================================================
(write-string "--- Group 11: 100! Factorial & 2^1000 ---\n")

(let ((fact100
       (let loop ((i 1) (acc 1))
         (if (> i 100)
             acc
             (loop (+ i 1) (* acc i))))))
  (assert-true "100! is bignum" (bignum? fact100))
  (assert-equal "100! exact decimal value"
                (number->string fact100)
                "93326215443944152681699238856266700490715968264381621468592963895217599993229915608941463976156518286253697920827223758251185210916864000000000000000000000000"))

(let ((p1000 (expt 2 1000)))
  (assert-true "2^1000 is bignum" (bignum? p1000))
  (assert-equal "2^1000 exact decimal value"
                (number->string p1000)
                "10715086071862673209484250490600018105614048117055336074437503883703510511249361224931983788156958581275946729175531468251871452856923140435984577574698574803934567774824230985421074605062371141877954182153046474983581941267398767559165543946077062914571196477686542167660429831652624386837205668069376")
  (assert-equal "2^1000 - 2^1000 == 0 (demoted to fixnum)"
                (- p1000 p1000)
                0)
  (assert-true "2^1000 - 2^1000 is fixnum?" (fixnum? (- p1000 p1000))))

;; =======================================================================
;; Group 12: Reader, Writer, string->number & number->string Integration
;; =======================================================================
(write-string "--- Group 12: Reader/Writer & string->number ---\n")

(let ((s100 "1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890")
      (neg-hex "-#x1234567890abcdef1234567890abcdef")
      (bin-big "#b1010101010101010101010101010101010101010101010101010101010101010101010101010101")
      (oct-big "#o777777777777777777777777777"))
  (let ((n100 (string->number s100)))
    (assert-true "string->number 100-digit decimal is bignum" (bignum? n100))
    (assert-equal "number->string roundtrip 100 digits" (number->string n100) s100)
    (let ((port-out (open-output-string)))
      (write n100 port-out)
      (assert-equal "write 100-digit bignum" (get-output-string port-out) s100))
    (let ((port-disp (open-output-string)))
      (display n100 port-disp)
      (assert-equal "display 100-digit bignum" (get-output-string port-disp) s100))
    (let ((rval (read (open-input-string s100))))
      (assert-true "read 100-digit decimal is bignum" (bignum? rval))
      (assert-true "read == string->number via =" (= rval n100))))
  (let ((nh (read (open-input-string neg-hex))))
    (assert-true "read negative hex bignum" (bignum? nh))
    (assert-equal "number->string radix 16" (number->string nh 16) "-1234567890abcdef1234567890abcdef"))
  (let ((nb (string->number bin-big)))
    (assert-true "string->number binary bignum" (bignum? nb))
    (assert-equal "number->string radix 2"
                  (number->string nb 2)
                  "1010101010101010101010101010101010101010101010101010101010101010101010101010101"))
  (let ((no (string->number oct-big)))
    (assert-true "string->number octal bignum" (bignum? no))
    (assert-equal "number->string radix 8" (number->string no 8) "777777777777777777777777777"))
  ;; Large bignum rational literal
  (let ((rat-big (string->number "1000000000000000000000001/1000000000000000000000002")))
    (assert-true "bignum rational is ratnum?" (ratnum? rat-big))
    (assert-true "bignum rational numerator is bignum" (bignum? (numerator rat-big)))
    (assert-true "bignum rational denominator is bignum" (bignum? (denominator rat-big)))
    (assert-equal "bignum rational number->string"
                  (number->string rat-big)
                  "1000000000000000000000001/1000000000000000000000002")))

;; =======================================================================
;; Group 13: Numeric Tower Predicates, Equality, Comparisons & isqrt
;; =======================================================================
(write-string "--- Group 13: Numeric Tower, Predicates, Equality & Comparisons ---\n")

(let ((b1 (expt 10 30))
      (b2 (+ (expt 10 30) 1))
      (b-neg (- (expt 10 30)))
      (b1-copy (string->number "1000000000000000000000000000000")))
  (assert-true "number? on bignum" (number? b1))
  (assert-true "complex? on bignum" (complex? b1))
  (assert-true "real? on bignum" (real? b1))
  (assert-true "rational? on bignum" (rational? b1))
  (assert-true "integer? on bignum" (integer? b1))
  (assert-true "exact-integer? on bignum" (exact-integer? b1))
  (assert-true "exact? on bignum" (exact? b1))
  (assert-false "inexact? on bignum" (inexact? b1))
  (assert-true "finite? on bignum" (finite? b1))
  (assert-false "infinite? on bignum" (infinite? b1))
  (assert-false "nan? on bignum" (nan? b1))
  (assert-true "positive? on bignum" (positive? b1))
  (assert-true "negative? on negative bignum" (negative? b-neg))
  (assert-true "even? on 10^30" (even? b1))
  (assert-true "odd? on 10^30 + 1" (odd? b2))
  (assert-true "eqv? on equal bignums" (eqv? b1 b1-copy))
  (assert-true "equal? on equal bignums" (equal? b1 b1-copy))
  (assert-false "eqv? on unequal bignums" (eqv? b1 b2))
  (assert-true "= on bignums" (= b1 b1-copy))
  (assert-true "< on bignums" (< b1 b2))
  (assert-true "<= on equal bignums" (<= b1 b1-copy))
  (assert-true "<= on unequal bignums" (<= b1 b2))
  (assert-true "> on bignums" (> b2 b1))
  (assert-true ">= on bignums" (>= b2 b1))
  (assert-true "mixed < fixnum and bignum" (< 42 b1))
  (assert-true "mixed > bignum and negative bignum" (> b1 b-neg))
  ;; Rational with bignum numerator & exact-integer-sqrt
  (let ((r (make-rational b1 3)))
    (assert-true "ratnum with bignum numerator" (ratnum? r))
    (assert-equal "numerator of 10^30 / 3" (numerator r) b1)
    (assert-equal "denominator of 10^30 / 3" (denominator r) 3)
    (assert-equal "10^30/3 * 3 demotes to bignum" (* r 3) b1))
  (call-with-values
    (lambda () (exact-integer-sqrt (+ (* b1 b1) 7)))
    (lambda (s r)
      (assert-equal "exact-integer-sqrt bignum s" s b1)
      (assert-equal "exact-integer-sqrt bignum r" r 7))))

(test-end "bignum")
