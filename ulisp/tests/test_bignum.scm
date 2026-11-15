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

(test-end "bignum")
