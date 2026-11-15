;;; =======================================================================
;;; ULisp Standard Library: Pure Scheme IEEE 754 Binary64 Module (lib/ieee754.scm)
;;; Exact Clinger's Algorithm Parser & Reversible Round-Trip Formatter
;;; Conforms to DSN-38 §2 A2 & Issue #832
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; §1. Architecture & Binary64 Constants
;;; -----------------------------------------------------------------------
;;; IEEE 754 64-bit Double Precision (Binary64) Format:
;;;   - Sign: 1 bit (bit 63)
;;;   - Biased Exponent: 11 bits (bits 62..52, Bias = 1023)
;;;   - Fraction/Mantissa: 52 bits (bits 51..0)
;;; Special bit patterns:
;;;   - +0.0:  #x0000000000000000
;;;   - -0.0:  #x8000000000000000
;;;   - +inf.0: #x7ff0000000000000
;;;   - -inf.0: #xfff0000000000000
;;;   - +nan.0: #x7ff8000000000000 (Quiet NaN)
;;;   - -nan.0: #xfff8000000000000

(define *ieee754-bias* 1023)
(define *ieee754-frac-bits* 52)
(define *ieee754-exp-bits* 11)

;; Binary64 Constants as 64-bit Bignums
(define (ieee754-pos-zero) (bignum-zero))
(define (ieee754-neg-zero) (bignum-shift-left (bignum-one) 63))
(define (ieee754-pos-inf)  (bignum-shift-left (fixnum->bignum 2047) 52))
(define (ieee754-neg-inf)
  (bignum-bitwise-ior (bignum-shift-left (bignum-one) 63)
                      (bignum-shift-left (fixnum->bignum 2047) 52)))
(define (ieee754-pos-nan)
  (bignum-bitwise-ior (bignum-shift-left (fixnum->bignum 2047) 52)
                      (bignum-shift-left (bignum-one) 51)))
(define (ieee754-neg-nan)
  (bignum-bitwise-ior (bignum-shift-left (bignum-one) 63)
                      (ieee754-pos-nan)))

;;; -----------------------------------------------------------------------
;;; §2. Bit Packing, Unpacking & Predicates
;;; -----------------------------------------------------------------------

(define (ieee754-pack-double sign biased-exp frac-52-bn)
  (let* ((s-part (if (= sign 1) (bignum-shift-left (bignum-one) 63) (bignum-zero)))
         (e-part (bignum-shift-left (fixnum->bignum biased-exp) 52))
         (f-mask (bignum-sub (bignum-shift-left (bignum-one) 52) (bignum-one)))
         (f-part (bignum-bitwise-and frac-52-bn f-mask)))
    (bignum-bitwise-ior s-part (bignum-bitwise-ior e-part f-part))))

(define (ieee754-unpack-double u64-bn)
  (let* ((u (bignum-u64-mask u64-bn))
         (sign (if (bignum-zero? (bignum-shift-right u 63)) 0 1))
         (exp-mask (fixnum->bignum 2047))
         (biased-exp (bignum->fixnum (bignum-bitwise-and (bignum-shift-right u 52) exp-mask)))
         (frac-mask (bignum-sub (bignum-shift-left (bignum-one) 52) (bignum-one)))
         (frac (bignum-bitwise-and u frac-mask)))
    (cond
      ((= biased-exp 2047)
       (if (bignum-zero? frac)
           (values sign biased-exp frac 'infinity)
           (values sign biased-exp frac 'nan)))
      ((= biased-exp 0)
       (if (bignum-zero? frac)
           (values sign biased-exp frac 'zero)
           (values sign biased-exp frac 'subnormal)))
      (else
       (values sign biased-exp frac 'normal)))))

(define (ieee754-nan? u)
  (call-with-values (lambda () (ieee754-unpack-double u))
    (lambda (s e f kind) (eq? kind 'nan))))

(define (ieee754-infinite? u)
  (call-with-values (lambda () (ieee754-unpack-double u))
    (lambda (s e f kind) (eq? kind 'infinity))))

(define (ieee754-zero? u)
  (call-with-values (lambda () (ieee754-unpack-double u))
    (lambda (s e f kind) (eq? kind 'zero))))

(define (ieee754-subnormal? u)
  (call-with-values (lambda () (ieee754-unpack-double u))
    (lambda (s e f kind) (eq? kind 'subnormal))))

(define (ieee754-finite? u)
  (call-with-values (lambda () (ieee754-unpack-double u))
    (lambda (s e f kind)
      (or (eq? kind 'normal) (eq? kind 'subnormal) (eq? kind 'zero)))))

;;; -----------------------------------------------------------------------
;;; §3. Helpers: Power of 10 & Bit Length
;;; -----------------------------------------------------------------------

(define (bignum-expt base exp)
  (cond
    ((= exp 0) (bignum-one))
    ((= exp 1) base)
    (else
     (let loop ((b base) (e exp) (acc (bignum-one)))
       (cond
         ((= e 0) acc)
         ((= (remainder e 2) 1)
          (loop (bignum-mul b b) (quotient e 2) (bignum-mul acc b)))
         (else
          (loop (bignum-mul b b) (quotient e 2) acc)))))))

(define (bignum-pow-10 k)
  (if (<= k 0)
      (bignum-one)
      (bignum-expt (fixnum->bignum 10) k)))

(define (%bignum-bit-length bn)
  (if (bignum-zero? bn)
      0
      (let* ((la (bignum-limbs bn))
             (na (vector-length la))
             (top (vector-ref la (- na 1))))
        (let loop ((v top) (bits 0))
          (if (= v 0)
              (+ (* (- na 1) 30) bits)
              (loop (quotient v 2) (+ bits 1)))))))

;;; -----------------------------------------------------------------------
;;; §4. Clinger's Exact Ratio Parsing Algorithm (string -> IEEE 754 Binary64)
;;; -----------------------------------------------------------------------
;;; References:
;;;   - Clinger, William D. "How to Read Floating Point Numbers Accurately." PLDI '90.
;;;   - IEEE Standard 754-2008 for Floating-Point Arithmetic.

(define (%string-trim-spaces s)
  (let ((len (string-length s)))
    (let loop-start ((i 0))
      (if (and (< i len) (char-whitespace? (string-ref s i)))
          (loop-start (+ i 1))
          (let loop-end ((j (- len 1)))
            (if (and (>= j i) (char-whitespace? (string-ref s j)))
                (loop-end (- j 1))
                (substring s i (+ j 1))))))))

(define (string->ieee754-u64 str-raw)
  (let ((s (%string-trim-spaces str-raw)))
    (cond
      ;; Special Tokens
      ((or (string=? s "+0.0") (string=? s "0.0") (string=? s "0") (string=? s "+0"))
       (ieee754-pos-zero))
      ((or (string=? s "-0.0") (string=? s "-0"))
       (ieee754-neg-zero))
      ((or (string=? s "+inf.0") (string=? s "inf.0") (string=? s "+inf") (string=? s "inf")
           (string=? s "+infinity") (string=? s "infinity"))
       (ieee754-pos-inf))
      ((or (string=? s "-inf.0") (string=? s "-inf") (string=? s "-infinity"))
       (ieee754-neg-inf))
      ((or (string=? s "+nan.0") (string=? s "nan.0") (string=? s "+nan") (string=? s "nan"))
       (ieee754-pos-nan))
      ((or (string=? s "-nan.0") (string=? s "-nan"))
       (ieee754-neg-nan))
      (else
       (%string->ieee754-clinger s)))))

(define (%string->ieee754-clinger s)
  (let* ((len (string-length s))
         (c0 (string-ref s 0))
         (is-neg (char=? c0 #\-))
         (has-sign (or is-neg (char=? c0 #\+)))
         (body (if has-sign (substring s 1 len) s))
         (body-len (string-length body)))

    ;; Split body into mantissa-str and exp-int
    (let* ((e-pos (let loop ((i 0))
                    (if (< i body-len)
                        (let ((c (string-ref body i)))
                          (if (or (char=? c #\e) (char=? c #\E))
                              i
                              (loop (+ i 1))))
                        #f)))
           (mant-part (if e-pos (substring body 0 e-pos) body))
           (exp-part (if e-pos (substring body (+ e-pos 1) body-len) "0"))
           (exp-val (string->number exp-part)))

      (if (not exp-val)
          (error "string->ieee754-u64: invalid exponent in float string" s)
          ;; Extract decimal point in mant-part
          (let* ((dot-pos (let loop ((i 0))
                            (if (< i (string-length mant-part))
                                (if (char=? (string-ref mant-part i) #\.)
                                    i
                                    (loop (+ i 1)))
                                #f)))
                 (dec-places (if dot-pos (- (- (string-length mant-part) 1) dot-pos) 0))
                 (clean-digits
                  (if dot-pos
                      (string-append (substring mant-part 0 dot-pos)
                                     (substring mant-part (+ dot-pos 1) (string-length mant-part)))
                      mant-part))
                 (E (- exp-val dec-places))
                 (M (string->bignum clean-digits 10)))

            (cond
              ((bignum-zero? M)
               (if is-neg (ieee754-neg-zero) (ieee754-pos-zero)))

              ;; Extreme range guards (THREAT-832-1)
              ((> E 310)
               (if is-neg (ieee754-neg-inf) (ieee754-pos-inf)))
              ((< E -350)
               (if is-neg (ieee754-neg-zero) (ieee754-pos-zero)))

              (else
               ;; Exact Clinger's ratio: Num / Den
               (let* ((Num (if (>= E 0) (bignum-mul M (bignum-pow-10 E)) M))
                      (Den (if (< E 0) (bignum-pow-10 (- 0 E)) (bignum-one)))

                      ;; Estimate binary exponent p such that 2^p <= Num/Den < 2^(p+1)
                      ;; log2(V) = log2(M) + E * log2(10)
                      (m-bits (%bignum-bit-length M))
                      (p-est (+ (- m-bits 1) (quotient (* E 3321928) 1000000)))

                      ;; Adjust p exactly using Bignum comparisons
                      (p
                       (let adjust-down ((cur-p p-est))
                         (let ((den-shifted
                                (if (>= cur-p 0)
                                    (bignum-shift-left Den cur-p)
                                    Den))
                               (num-shifted
                                (if (>= cur-p 0)
                                    Num
                                    (bignum-shift-left Num (- 0 cur-p)))))
                           (if (bignum>? den-shifted num-shifted)
                               (adjust-down (- cur-p 1))
                               (let adjust-up ((p-cand cur-p))
                                 (let* ((next-p (+ p-cand 1))
                                        (den-next
                                         (if (>= next-p 0)
                                             (bignum-shift-left Den next-p)
                                             Den))
                                        (num-next
                                         (if (>= next-p 0)
                                             Num
                                             (bignum-shift-left Num (- 0 next-p)))))
                                   (if (bignum<=? den-next num-next)
                                       (adjust-up next-p)
                                       p-cand))))))))

                 (cond
                   ;; Overflow to Infinity
                   ((> p 1023)
                    (if is-neg (ieee754-neg-inf) (ieee754-pos-inf)))

                   ;; Underflow to Zero (below 2^(-1075))
                   ((< p -1075)
                    (if is-neg (ieee754-neg-zero) (ieee754-pos-zero)))

                   ;; Normalized numbers (p >= -1022)
                   ((>= p -1022)
                    (let* ((bias-exp (+ p *ieee754-bias*))
                           (shift (- 53 p))
                           (sNum (if (>= shift 0) (bignum-shift-left Num shift) Num))
                           (sDen (if (< shift 0) (bignum-shift-left Den (- 0 shift)) Den)))
                      (call-with-values (lambda () (bignum-div-rem sNum sDen))
                        (lambda (Q R)
                          (let* ((S (bignum-shift-right Q 1))
                                 (R-bit (bignum->fixnum (bignum-bitwise-and Q (bignum-one))))
                                 (sticky (if (bignum-zero? R) 0 1))
                                 ;; Round to nearest, ties to even (THREAT-832-2)
                                 (rounded-S
                                  (if (= R-bit 1)
                                      (if (or (= sticky 1)
                                              (= (bignum->fixnum (bignum-bitwise-and S (bignum-one))) 1))
                                          (bignum-add S (bignum-one))
                                          S)
                                      S))
                                 (two-53 (bignum-shift-left (bignum-one) 53)))
                            ;; Carry out into bit 54 check
                            (let* ((final-S (if (bignum>=? rounded-S two-53)
                                                (bignum-shift-right rounded-S 1)
                                                rounded-S))
                                   (final-exp (if (bignum>=? rounded-S two-53)
                                                  (+ bias-exp 1)
                                                  bias-exp)))
                              (if (> final-exp 2046)
                                  (if is-neg (ieee754-neg-inf) (ieee754-pos-inf))
                                  (ieee754-pack-double (if is-neg 1 0) final-exp final-S))))))))

                   ;; Subnormal numbers (p < -1022)
                   (else
                    (let* ((shift 1075)
                           (sNum (bignum-shift-left Num shift)))
                      (call-with-values (lambda () (bignum-div-rem sNum Den))
                        (lambda (Q R)
                          (let* ((S (bignum-shift-right Q 1))
                                 (R-bit (bignum->fixnum (bignum-bitwise-and Q (bignum-one))))
                                 (sticky (if (bignum-zero? R) 0 1))
                                 (rounded-S
                                  (if (= R-bit 1)
                                      (if (or (= sticky 1)
                                              (= (bignum->fixnum (bignum-bitwise-and S (bignum-one))) 1))
                                          (bignum-add S (bignum-one))
                                          S)
                                      S))
                                 (two-52 (bignum-shift-left (bignum-one) 52)))
                            ;; Check if subnormal rounded up into normal (2^(-1022))
                            (if (bignum>=? rounded-S two-52)
                                (ieee754-pack-double (if is-neg 1 0) 1 rounded-S)
                                (ieee754-pack-double (if is-neg 1 0) 0 rounded-S))))))))))))))))

;;; -----------------------------------------------------------------------
;;; §5. Reversible Round-Trip Decimal Formatter (Binary64 -> string)
;;; -----------------------------------------------------------------------

(define (ieee754-u64->string u64-bn)
  (call-with-values (lambda () (ieee754-unpack-double u64-bn))
    (lambda (sign biased-exp frac kind)
      (cond
        ((eq? kind 'infinity)
         (if (= sign 1) "-inf.0" "+inf.0"))
        ((eq? kind 'nan)
         (if (= sign 1) "-nan.0" "+nan.0"))
        ((eq? kind 'zero)
         (if (= sign 1) "-0.0" "0.0"))
        (else
         (let* ((two-52 (bignum-shift-left (bignum-one) 52))
                (M (if (eq? kind 'normal)
                       (bignum-bitwise-ior two-52 frac)
                       frac))
                (e (if (eq? kind 'normal)
                       (- biased-exp 1075)
                       -1074))
                (Num (if (>= e 0) (bignum-shift-left M e) M))
                (Den (if (< e 0) (bignum-shift-left (bignum-one) (- 0 e)) (bignum-one)))

                ;; Estimate decimal power K such that 10^K <= Num/Den < 10^(K+1)
                (m-bits (%bignum-bit-length M))
                (k-est (quotient (* (+ (- m-bits 1) e) 301030) 1000000))

                ;; Adjust K exactly using Bignum comparisons
                (K
                 (let adjust-down ((cur-k k-est))
                   (let ((den-k (if (>= cur-k 0) (bignum-mul Den (bignum-pow-10 cur-k)) Den))
                         (num-k (if (>= cur-k 0) Num (bignum-mul Num (bignum-pow-10 (- 0 cur-k))))))
                     (if (bignum>? den-k num-k)
                         (adjust-down (- cur-k 1))
                         (let adjust-up ((k-cand cur-k))
                           (let* ((next-k (+ k-cand 1))
                                  (den-next (if (>= next-k 0) (bignum-mul Den (bignum-pow-10 next-k)) Den))
                                  (num-next (if (>= next-k 0) Num (bignum-mul Num (bignum-pow-10 (- 0 next-k))))))
                             (if (bignum<=? den-next num-next)
                                 (adjust-up next-k)
                                 k-cand)))))))

                ;; Scale R and S to generate 17 digits
                (R (if (>= K 0) Num (bignum-mul Num (bignum-pow-10 (- 0 K)))))
                (S (if (>= K 0) (bignum-mul Den (bignum-pow-10 K)) Den)))

           ;; Digit generation loop (up to 17 digits)
           (let generate ((step 0) (cur-R R) (digits '()))
             (if (= step 17)
                 ;; 17th digit rounding
                 (let* ((two-R (bignum-shift-left cur-R 1))
                        (round-up (bignum>=? two-R S))
                        (dig-list (reverse digits)))
                   (let ((rounded-digs
                          (if round-up
                              (let carry-prop ((ds (reverse dig-list)) (c 1))
                                (if (null? ds)
                                    (if (> c 0) (list c) '())
                                    (let ((sum (+ (car ds) c)))
                                      (if (= sum 10)
                                          (cons 0 (carry-prop (cdr ds) 1))
                                          (cons sum (carry-prop (cdr ds) 0))))))
                              dig-list)))
                     (%format-digits-to-string (if round-up (reverse rounded-digs) dig-list)
                                               (if (and round-up (> (length rounded-digs) (length dig-list)))
                                                   (+ K 1)
                                                   K)
                                               (= sign 1))))
                 (call-with-values (lambda () (bignum-div-rem cur-R S))
                   (lambda (Q rem-R)
                     (let* ((d (bignum->fixnum Q))
                            (new-digits (cons d digits)))
                       (if (bignum-zero? rem-R)
                           (%format-digits-to-string (reverse new-digits) K (= sign 1))
                           (generate (+ step 1) (bignum-mul rem-R (fixnum->bignum 10)) new-digits)))))))))))))

(define (%make-string-fill len ch)
  (let ((s (make-string len)))
    (let loop ((i 0))
      (if (< i len)
          (begin
            (string-set! s i ch)
            (loop (+ i 1)))
          s))))

(define (%format-digits-to-string raw-digits K is-neg)
  ;; Strip trailing zeros but keep at least 1 digit
  (let* ((digits-no-trailing
          (let loop ((rev-ds (reverse raw-digits)))
            (if (and (> (length rev-ds) 1) (= (car rev-ds) 0))
                (loop (cdr rev-ds))
                (reverse rev-ds))))
         (dig-str (let* ((n (length digits-no-trailing))
                         (s (make-string n)))
                    (let copy ((ds digits-no-trailing) (i 0))
                      (if (null? ds)
                          s
                          (begin
                            (string-set! s i (integer->char (+ 48 (car ds))))
                            (copy (cdr ds) (+ i 1)))))))
         (n-digs (string-length dig-str)))

    (let ((formatted-body
           (if (and (>= K -4) (<= K 15))
               ;; Fixed point notation
               (cond
                 ((>= K 0)
                  (if (>= (+ K 1) n-digs)
                      (string-append dig-str
                                     (%make-string-fill (- (+ K 1) n-digs) #\0) ".0")
                      (string-append (substring dig-str 0 (+ K 1))
                                     "." (substring dig-str (+ K 1) n-digs))))
                 (else
                  (string-append "0."
                                 (%make-string-fill (- (- 0 K) 1) #\0)
                                 dig-str)))
               ;; Scientific notation
               (let* ((exp-str (number->string K))
                      (exp-clean (if (>= K 0) (string-append "+" exp-str) exp-str)))
                 (if (= n-digs 1)
                     (string-append dig-str ".0e" exp-clean)
                     (string-append (substring dig-str 0 1)
                                    "."
                                    (substring dig-str 1 n-digs)
                                    "e" exp-clean))))))
      (if is-neg
          (string-append "-" formatted-body)
          formatted-body))))

;;; -----------------------------------------------------------------------
;;; §6. Hexadecimal Bit Representation Formatter & Parser
;;; -----------------------------------------------------------------------

(define (ieee754-u64->hex-string u64-bn)
  (let* ((u (bignum-u64-mask u64-bn))
         (raw-hex (bignum->string u 16))
         (len (string-length raw-hex)))
    (if (< len 16)
        (string-append (%make-string-fill (- 16 len) #\0) raw-hex)
        raw-hex)))

(define (hex-string->ieee754-u64 hex-str)
  (string->bignum hex-str 16))
