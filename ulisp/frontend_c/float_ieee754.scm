;;; =======================================================================
;;; ULisp C99 Frontend: Deterministic IEEE 754 Binary64 & Binary32 Codec
;;; Pure-Scheme Arbitrary-Precision Clinger Exact-Ratio Encoder (Issue #923)
;;; Conforms to ISO C99 §6.4.4.2, IEEE 754-2008 & ULisp AOT (zero local set!)
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Canonical IEEE 754 Bit-Pattern Constants
;;; -----------------------------------------------------------------------

(define *c99-f64-pos-zero* 0)
(define *c99-f64-neg-zero* #x8000000000000000)
(define *c99-f64-pos-inf*  #x7ff0000000000000)
(define *c99-f64-neg-inf*  #xfff0000000000000)
(define *c99-f64-qnan*     #x7ff8000000000000)
(define *c99-f64-one*      #x3ff0000000000000)

(define *c99-f32-pos-zero* 0)
(define *c99-f32-neg-zero* #x80000000)
(define *c99-f32-pos-inf*  #x7f800000)
(define *c99-f32-neg-inf*  #xff800000)
(define *c99-f32-qnan*     #x7fc00000)
(define *c99-f32-one*      #x3f800000)

(define (c99-ieee754-signed-zero sign f64?)
  (if f64?
      (if (= sign 1) *c99-f64-neg-zero* *c99-f64-pos-zero*)
      (if (= sign 1) *c99-f32-neg-zero* *c99-f32-pos-zero*)))

(define (c99-ieee754-signed-inf sign f64?)
  (if f64?
      (if (= sign 1) *c99-f64-neg-inf* *c99-f64-pos-inf*)
      (if (= sign 1) *c99-f32-neg-inf* *c99-f32-pos-inf*)))

(define (c99-ieee754-f64-bits-neg u64)
  (bitwise-xor (bitwise-and u64 #xffffffffffffffff) #x8000000000000000))

(define (c99-ieee754-f32-bits-neg u32)
  (bitwise-xor (bitwise-and u32 #xffffffff) #x80000000))

;;; -----------------------------------------------------------------------
;;; 2. Exact Arbitrary-Precision Helpers
;;; -----------------------------------------------------------------------

(define (%c99-int-bit-length n)
  (if (<= n 0)
      0
      (let chunk-loop ((x n) (bits 0))
        (let ((hi (arithmetic-shift x -24)))
          (if (> hi 0)
              (chunk-loop hi (+ bits 24))
              (let bit-loop ((y x) (b bits))
                (if (= y 0)
                    b
                    (bit-loop (arithmetic-shift y -1) (+ b 1)))))))))

(define (%c99-exact-expt base exp)
  (let loop ((b base) (e exp) (acc 1))
    (cond
      ((<= e 0) acc)
      ((= (remainder e 2) 1)
       (loop (* b b) (quotient e 2) (* acc b)))
      (else
       (loop (* b b) (quotient e 2) acc)))))

(define (%c99-hex-digit-val ch)
  (let ((c (char->integer ch)))
    (cond
      ((and (>= c 48) (<= c 57)) (- c 48))
      ((and (>= c 97) (<= c 102)) (+ 10 (- c 97)))
      ((and (>= c 65) (<= c 70)) (+ 10 (- c 65)))
      (else -1))))

(define (%c99-dec-digit-val ch)
  (let ((c (char->integer ch)))
    (if (and (>= c 48) (<= c 57)) (- c 48) -1)))

;;; -----------------------------------------------------------------------
;;; 3. Parameterized Exact-Ratio -> IEEE 754 Single-Rounding Encoder
;;; -----------------------------------------------------------------------
;;; Computes exact IEEE 754 bit pattern for (-1)^sign * (num / den) with
;;; round-to-nearest, ties-to-even (no intermediate double rounding).
;;;   - Binary64 (f64): prec = 53, exp-bits = 11
;;;   - Binary32 (f32): prec = 24, exp-bits = 8

(define (%c99-pack-ieee754 sign biased-exp frac-val frac-bits)
  (let* ((total-shift (+ frac-bits (if (= frac-bits 52) 11 8)))
         (s-part (if (= sign 1) (arithmetic-shift 1 total-shift) 0))
         (e-part (arithmetic-shift biased-exp frac-bits))
         (f-mask (- (arithmetic-shift 1 frac-bits) 1))
         (f-part (bitwise-and frac-val f-mask)))
    (bitwise-ior s-part (bitwise-ior e-part f-part))))

(define (%c99-pow2-cmp-le num den p)
  ;; #t iff 2^p <= num / den
  (if (>= p 0)
      (<= (arithmetic-shift den p) num)
      (<= den (arithmetic-shift num (- 0 p)))))

(define (%c99-pow2-cmp-gt num den p)
  ;; #t iff 2^p > num / den
  (not (%c99-pow2-cmp-le num den p)))

(define (%c99-round-ties-to-even Q R)
  (let* ((S (arithmetic-shift Q -1))
         (r-bit (bitwise-and Q 1))
         (sticky (not (= R 0))))
    (if (= r-bit 1)
        (if (or sticky (= (bitwise-and S 1) 1))
            (+ S 1)
            S)
        S)))

(define (c99-ratio->ieee754-bits sign num den prec exp-bits)
  (let ((f64? (= prec 53)))
    (if (= num 0)
        (c99-ieee754-signed-zero sign f64?)
        (let* ((bias (- (arithmetic-shift 1 (- exp-bits 1)) 1))
               (frac-bits (- prec 1))
               (max-bexp (- (arithmetic-shift 1 exp-bits) 1))
               (min-norm-p (- 1 bias))
               (min-sub-p (- min-norm-p frac-bits))
               (p-est (- (%c99-int-bit-length num) (%c99-int-bit-length den)))
               (p (let adjust-down ((cur-p p-est))
                    (if (%c99-pow2-cmp-gt num den cur-p)
                        (adjust-down (- cur-p 1))
                        (let adjust-up ((cand cur-p))
                          (if (%c99-pow2-cmp-le num den (+ cand 1))
                              (adjust-up (+ cand 1))
                              cand))))))
          (cond
            ((> p bias)
             (c99-ieee754-signed-inf sign f64?))
            ((< p (- min-sub-p 1))
             (c99-ieee754-signed-zero sign f64?))
            ((>= p min-norm-p)
             (let* ((bexp (+ p bias))
                    (shift (- prec p))
                    (s-num (if (>= shift 0) (arithmetic-shift num shift) num))
                    (s-den (if (< shift 0) (arithmetic-shift den (- 0 shift)) den))
                    (Q (quotient s-num s-den))
                    (R (remainder s-num s-den))
                    (rounded-S (%c99-round-ties-to-even Q R))
                    (carry-limit (arithmetic-shift 1 prec))
                    (final-S (if (>= rounded-S carry-limit)
                                 (arithmetic-shift rounded-S -1)
                                 rounded-S))
                    (final-bexp (if (>= rounded-S carry-limit) (+ bexp 1) bexp)))
               (if (>= final-bexp max-bexp)
                   (c99-ieee754-signed-inf sign f64?)
                   (%c99-pack-ieee754 sign final-bexp final-S frac-bits))))
            (else
             (let* ((shift (- 1 min-sub-p))
                    (s-num (arithmetic-shift num shift))
                    (Q (quotient s-num den))
                    (R (remainder s-num den))
                    (rounded-S (%c99-round-ties-to-even Q R))
                    (norm-limit (arithmetic-shift 1 frac-bits)))
               (if (>= rounded-S norm-limit)
                   (%c99-pack-ieee754 sign 1 rounded-S frac-bits)
                   (%c99-pack-ieee754 sign 0 rounded-S frac-bits)))))))))

;;; -----------------------------------------------------------------------
;;; 4. Bit-Level Conversions, Int <-> Float & Exact Inexact Evaluators
;;; -----------------------------------------------------------------------

(define (c99-ieee754-int->f64-bits n)
  (let ((sign (if (< n 0) 1 0))
        (mag (if (< n 0) (- 0 n) n)))
    (c99-ratio->ieee754-bits sign mag 1 53 11)))

(define (c99-ieee754-int->f32-bits n)
  (let ((sign (if (< n 0) 1 0))
        (mag (if (< n 0) (- 0 n) n)))
    (c99-ratio->ieee754-bits sign mag 1 24 8)))

(define (c99-ieee754-f32-bits->f64-bits u32)
  (let* ((u (bitwise-and u32 #xffffffff))
         (sign (bitwise-and (arithmetic-shift u -31) 1))
         (bexp (bitwise-and (arithmetic-shift u -23) #xff))
         (frac (bitwise-and u #x7fffff)))
    (cond
      ((= bexp 255)
       (if (= frac 0)
           (c99-ieee754-signed-inf sign #t)
           (bitwise-ior (if (= sign 1) *c99-f64-neg-zero* 0)
                        (bitwise-ior #x7ff8000000000000
                                     (arithmetic-shift frac 29)))))
      ((= bexp 0)
       (if (= frac 0)
           (c99-ieee754-signed-zero sign #t)
           (let* ((bl (%c99-int-bit-length frac))
                  (lead-pos (- bl 1))
                  (p (- lead-pos 149))
                  (f64-bexp (+ p 1023))
                  (norm-frac (bitwise-and (arithmetic-shift frac (- 52 lead-pos))
                                          #xfffffffffffff)))
             (%c99-pack-ieee754 sign f64-bexp norm-frac 52))))
      (else
       (%c99-pack-ieee754 sign (+ (- bexp 127) 1023) (arithmetic-shift frac 29) 52)))))

(define (c99-ieee754-f64-bits->f32-bits u64)
  (let* ((u (bitwise-and u64 #xffffffffffffffff))
         (sign (bitwise-and (arithmetic-shift u -63) 1))
         (bexp (bitwise-and (arithmetic-shift u -52) #x7ff))
         (frac (bitwise-and u #xfffffffffffff)))
    (cond
      ((= bexp 2047)
       (if (= frac 0)
           (c99-ieee754-signed-inf sign #f)
           (bitwise-ior (if (= sign 1) *c99-f32-neg-zero* 0)
                        (bitwise-ior #x7fc00000
                                     (bitwise-and (arithmetic-shift frac -29) #x3fffff)))))
      ((and (= bexp 0) (= frac 0))
       (c99-ieee754-signed-zero sign #f))
      (else
       (let* ((sig (if (= bexp 0) frac (bitwise-ior (arithmetic-shift 1 52) frac)))
              (e (if (= bexp 0) -1074 (- bexp 1075))))
         (cond
           ((> e 100) (c99-ieee754-signed-inf sign #f))
           ((< e -220) (c99-ieee754-signed-zero sign #f))
           ((>= e 0) (c99-ratio->ieee754-bits sign (arithmetic-shift sig e) 1 24 8))
           (else (c99-ratio->ieee754-bits sign sig (arithmetic-shift 1 (- 0 e)) 24 8))))))))

(define (%c99-pow2-inexact-safe exp)
  (if (= exp 0)
      1.0
      (let* ((neg? (< exp 0))
             (e (if neg? (- 0 exp) exp))
             (b (if neg? 0.5 2.0)))
        (let loop ((k e) (base b) (acc 1.0))
          (if (<= k 0)
              acc
              (loop (quotient k 2)
                    (* base base)
                    (if (= (remainder k 2) 1) (* acc base) acc)))))))

(define (c99-ieee754-f64-bits->inexact u64)
  (let* ((u (bitwise-and u64 #xffffffffffffffff))
         (sign (bitwise-and (arithmetic-shift u -63) 1))
         (bexp (bitwise-and (arithmetic-shift u -52) #x7ff))
         (frac (bitwise-and u #xfffffffffffff))
         (abs-f
          (cond
            ((= bexp 2047)
             (let ((pinf (* 1e308 2.0)))
               (if (= frac 0) pinf (- pinf pinf))))
            ((= bexp 0)
             (if (= frac 0)
                 0.0
                 (* (* (exact->inexact frac) (%c99-pow2-inexact-safe -512))
                    (%c99-pow2-inexact-safe -562))))
            (else
             (let ((m (+ 1.0 (* (exact->inexact frac) (%c99-pow2-inexact-safe -52))))
                   (e (- bexp 1023)))
               (if (< e -1000)
                   (* (* m (%c99-pow2-inexact-safe -512))
                      (%c99-pow2-inexact-safe (+ e 512)))
                   (* m (%c99-pow2-inexact-safe e))))))))
    (if (= sign 1) (* -1.0 abs-f) abs-f)))

(define (c99-ieee754-f32-bits->inexact u32)
  (c99-ieee754-f64-bits->inexact (c99-ieee754-f32-bits->f64-bits u32)))

(define (c99-ieee754-bits->hex bits digits)
  (let loop ((i 0) (x bits) (chars '()))
    (if (>= i digits)
        (list->string chars)
        (let ((nib (bitwise-and x #xf)))
          (loop (+ i 1)
                (arithmetic-shift x -4)
                (cons (string-ref "0123456789abcdef" nib) chars))))))

(define (c99-ieee754-u64->hex16 u64)
  (c99-ieee754-bits->hex (bitwise-and u64 #xffffffffffffffff) 16))

(define (c99-ieee754-u32->hex8 u32)
  (c99-ieee754-bits->hex (bitwise-and u32 #xffffffff) 8))

(define (c99-ieee754-bits->le-bytes bits nbytes)
  (let loop ((i 0) (x bits) (acc '()))
    (if (>= i nbytes)
        (reverse acc)
        (loop (+ i 1)
              (arithmetic-shift x -8)
              (cons (bitwise-and x #xff) acc)))))

;;; -----------------------------------------------------------------------
;;; 5. C99 Decimal & Hexadecimal Floating-Point Literal Parser
;;; -----------------------------------------------------------------------
;;; Returns: (list 'ok ctype bits approx-inexact) | (list 'error msg)

(define (%c99-parse-digits-signed str start end)
  (if (>= start end)
      #f
      (let* ((c0 (string-ref str start))
             (neg? (char=? c0 #\-))
             (pos? (or neg? (char=? c0 #\+)))
             (d-start (if pos? (+ start 1) start)))
        (if (>= d-start end)
            #f
            (let loop ((i d-start) (acc 0))
              (if (>= i end)
                  (if neg? (- 0 acc) acc)
                  (let ((d (%c99-dec-digit-val (string-ref str i))))
                    (if (< d 0)
                        #f
                        (loop (+ i 1) (+ (* acc 10) d))))))))))

(define (%c99-scan-mantissa str start end radix)
  ;; Returns (list ok? mantissa-int frac-digits digit-count)
  (let loop ((i start) (seen-dot? #f) (mant 0) (frac-cnt 0) (dig-cnt 0))
    (if (>= i end)
        (list #t mant frac-cnt dig-cnt)
        (let ((c (string-ref str i)))
          (cond
            ((char=? c #\.)
             (if seen-dot?
                 (list #f 0 0 0)
                 (loop (+ i 1) #t mant frac-cnt dig-cnt)))
            (else
             (let ((d (if (= radix 16) (%c99-hex-digit-val c) (%c99-dec-digit-val c))))
               (if (< d 0)
                   (list #f 0 0 0)
                   (loop (+ i 1)
                         seen-dot?
                         (+ (* mant radix) d)
                         (if seen-dot? (+ frac-cnt 1) frac-cnt)
                         (+ dig-cnt 1))))))))))

(define (c99-parse-float-literal lex)
  (let ((len (if (string? lex) (string-length lex) 0)))
    (if (= len 0)
        (list 'error "Empty floating-point literal")
        (let* ((c0 (string-ref lex 0))
               (neg? (char=? c0 #\-))
               (sign (if neg? 1 0))
               (start (if (or neg? (char=? c0 #\+)) 1 0))
               (last-ch (string-ref lex (- len 1)))
               (is-f32? (or (char=? last-ch #\f) (char=? last-ch #\F)))
               (is-long? (or (char=? last-ch #\l) (char=? last-ch #\L)))
               (end (if (or is-f32? is-long?) (- len 1) len))
               (cty (if is-f32? 'f32 'f64))
               (prec (if is-f32? 24 53))
               (ebits (if is-f32? 8 11)))
          (cond
            ((<= end start)
             (list 'error (string-append "Malformed floating-point literal: " lex)))
            ;; Double or trailing extra suffix letter check
            ((let ((prev (string-ref lex (- end 1))))
               (and (not (char=? prev #\.))
                    (< (%c99-hex-digit-val prev) 0)))
             (list 'error (string-append "Invalid floating-point suffix in literal: " lex)))
            ;; Hexadecimal floating-point constant: 0x...p±...
            ((and (>= (- end start) 2)
                  (char=? (string-ref lex start) #\0)
                  (or (char=? (string-ref lex (+ start 1)) #\x)
                      (char=? (string-ref lex (+ start 1)) #\X)))
             (let ((m-start (+ start 2)))
               (let find-p ((i m-start) (p-idx #f))
                 (if (>= i end)
                     (if (not p-idx)
                         (list 'error (string-append "Hexadecimal floating-point literal requires binary 'p'/'P' exponent: " lex))
                         (let ((m-info (%c99-scan-mantissa lex m-start p-idx 16))
                               (exp-val (%c99-parse-digits-signed lex (+ p-idx 1) end)))
                           (if (or (not (car m-info))
                                   (= (cadddr m-info) 0)
                                   (not exp-val))
                               (list 'error (string-append "Malformed hexadecimal floating-point literal: " lex))
                               (let* ((M (cadr m-info))
                                      (frac-hex (caddr m-info))
                                      (E2 (- exp-val (* 4 frac-hex)))
                                      (bits (cond
                                              ((= M 0) (c99-ieee754-signed-zero sign (not is-f32?)))
                                              ((> E2 2200) (c99-ieee754-signed-inf sign (not is-f32?)))
                                              ((< E2 -2200) (c99-ieee754-signed-zero sign (not is-f32?)))
                                              ((>= E2 0)
                                               (c99-ratio->ieee754-bits sign (arithmetic-shift M E2) 1 prec ebits))
                                              (else
                                               (c99-ratio->ieee754-bits sign M (arithmetic-shift 1 (- 0 E2)) prec ebits)))))
                                 (list 'ok cty bits
                                       (if is-f32?
                                           (c99-ieee754-f32-bits->inexact bits)
                                           (c99-ieee754-f64-bits->inexact bits)))))))
                     (let ((ch (string-ref lex i)))
                       (if (or (char=? ch #\p) (char=? ch #\P))
                           (if p-idx
                               (list 'error (string-append "Multiple exponent markers in literal: " lex))
                               (find-p (+ i 1) i))
                           (find-p (+ i 1) p-idx)))))))
            ;; Decimal floating-point constant
            (else
             (let find-e ((i start) (e-idx #f) (has-dot? #f))
               (if (>= i end)
                   (if (and (not e-idx) (not has-dot?))
                       (list 'error (string-append "Malformed floating-point literal: " lex))
                       (let* ((m-end (or e-idx end))
                              (m-info (%c99-scan-mantissa lex start m-end 10))
                              (exp-val (if e-idx (%c99-parse-digits-signed lex (+ e-idx 1) end) 0)))
                         (if (or (not (car m-info))
                                 (= (cadddr m-info) 0)
                                 (not exp-val))
                             (list 'error (string-append "Malformed decimal floating-point literal: " lex))
                             (let* ((M (cadr m-info))
                                    (dec-places (caddr m-info))
                                    (E (- exp-val dec-places))
                                    (bits (cond
                                            ((= M 0) (c99-ieee754-signed-zero sign (not is-f32?)))
                                            ((> E 320) (c99-ieee754-signed-inf sign (not is-f32?)))
                                            ((< E -350) (c99-ieee754-signed-zero sign (not is-f32?)))
                                            ((>= E 0)
                                             (c99-ratio->ieee754-bits sign (* M (%c99-exact-expt 10 E)) 1 prec ebits))
                                            (else
                                             (c99-ratio->ieee754-bits sign M (%c99-exact-expt 10 (- 0 E)) prec ebits)))))
                               (list 'ok cty bits
                                     (if is-f32?
                                         (c99-ieee754-f32-bits->inexact bits)
                                         (c99-ieee754-f64-bits->inexact bits)))))))
                   (let ((ch (string-ref lex i)))
                     (cond
                       ((or (char=? ch #\e) (char=? ch #\E))
                        (if e-idx
                            (list 'error (string-append "Multiple exponents in literal: " lex))
                            (find-e (+ i 1) i has-dot?)))
                       ((char=? ch #\.)
                        (find-e (+ i 1) e-idx #t))
                       (else
                        (find-e (+ i 1) e-idx has-dot?))))))))))))
