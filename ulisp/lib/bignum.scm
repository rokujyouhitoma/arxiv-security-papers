;;; =======================================================================
;;; ULisp Standard Library: Pure Scheme Bignum Arithmetic (lib/bignum.scm)
;;; Arbitrary-Precision Integer Arithmetic & 64-bit Modulo Operations
;;; Conforms to DSN-38 §2 A1/B1 & Issue #832
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; §1. Architecture, Radix Constants & Safeguards
;;; -----------------------------------------------------------------------
;;; Radix B = 2^30 = 1073741824.
;;; ULisp fixnums are 62-bit signed integers ([-2^61, 2^61 - 1]).
;;; In radix 2^30, the product of any two limbs plus carry plus accumulator is:
;;;   (2^30 - 1) * (2^30 - 1) + 2*(2^30 - 1) = 2^60 - 1 < 2^61 - 1.
;;; Therefore, all limb-level additions, subtractions, and multiplications
;;; execute directly within native fixnums without intermediate overflow.

(define *bignum-radix-bits* 30)
(define *bignum-radix* 1073741824)        ; 2^30
(define *bignum-radix-mask* 1073741823)   ; 2^30 - 1 = #x3fffffff
(define *bignum-half-radix* 536870912)    ; 2^29

;; THREAT-832-1: Maximum allowed limbs (4096 limbs = ~122,880 bits) to prevent DoS
(define *bignum-max-limbs* 4096)

;; Precomputed powers of 2 for fast O(1) bit shifts within limbs (0 <= k <= 30)
(define *bignum-pow2-table*
  (vector 1 2 4 8 16 32 64 128 256 512 1024 2048 4096 8192 16384 32768
          65536 131072 262144 524288 1048576 2097152 4194304 8388608
          16777216 33554432 67108864 134217728 268435456 536870912 1073741824))

(define (%bignum-pow2 k)
  (if (and (>= k 0) (<= k 30))
      (vector-ref *bignum-pow2-table* k)
      (error "%bignum-pow2: shift out of range [0, 30]" k)))

;;; -----------------------------------------------------------------------
;;; §2. Representation, Constructors, Predicates & Accessors
;;; -----------------------------------------------------------------------
;;; A Bignum is represented as a 3-element vector:
;;;   #(bignum sign limbs-vector)
;;;   - sign: 1 (positive), -1 (negative), 0 (zero)
;;;   - limbs: vector of 30-bit fixnums in [0, 2^30 - 1], little-endian order.
;;;   - Invariant: Zero is #(bignum 0 #()). Non-zero always has limbs[-1] > 0.

(define (make-bignum sign limbs)
  (vector 'bignum sign limbs))

;; Note: bignum? is defined in lib/predicates.scm

(define (bignum-sign bn) (vector-ref bn 1))
(define (bignum-limbs bn) (vector-ref bn 2))
(define (bignum-num-limbs bn) (vector-length (vector-ref bn 2)))

(define (bignum-zero? bn) (= (vector-ref bn 1) 0))
(define (bignum-positive? bn) (= (vector-ref bn 1) 1))
(define (bignum-negative? bn) (= (vector-ref bn 1) -1))

(define (bignum-zero)
  (vector 'bignum 0 (make-vector 0)))

(define (bignum-one)
  (vector 'bignum 1 (vector 1)))

;; THREAT-832-4: Normalization strips trailing zero limbs and enforces invariants
(define (bignum-normalize sign limbs)
  (let ((len (vector-length limbs)))
    (let loop ((i (- len 1)))
      (cond
        ((< i 0)
         (bignum-zero))
        ((> (vector-ref limbs i) 0)
         (let ((new-len (+ i 1)))
           (if (> new-len *bignum-max-limbs*)
               (error "bignum-normalize: maximum limb count exceeded" new-len)
               (let ((new-limbs (make-vector new-len 0)))
                 (let copy ((j 0))
                   (if (< j new-len)
                       (begin
                         (vector-set! new-limbs j (vector-ref limbs j))
                         (copy (+ j 1)))
                       (vector 'bignum (if (= sign 0) 1 sign) new-limbs)))))))
        (else
         (loop (- i 1)))))))

;;; -----------------------------------------------------------------------
;;; §3. Fixnum <-> Bignum Conversions
;;; -----------------------------------------------------------------------

(define (fixnum->bignum n)
  (cond
    ((= n 0) (bignum-zero))
    ((> n 0)
     (let loop ((val n) (acc '()))
       (if (= val 0)
           (vector 'bignum 1 (list->vector (reverse acc)))
           (let ((l (bitwise-and val *bignum-radix-mask*))
                 (next (quotient val *bignum-radix*)))
             (loop next (cons l acc))))))
    (else
     ;; Safe handling of minimum fixnum (-2^61) without intermediate overflow
     (let* ((safe-pos (- 0 (+ n 1)))
            (bn (fixnum->bignum safe-pos))
            (bn-plus-1 (bignum-add bn (bignum-one))))
       (vector 'bignum -1 (bignum-limbs bn-plus-1))))))

(define (bignum->fixnum bn)
  (let* ((n (bignum-num-limbs bn))
         (s (bignum-sign bn))
         (la (bignum-limbs bn)))
    (cond
      ((= n 0) 0)
      ((= n 1)
       (let ((val (vector-ref la 0)))
         (if (< s 0) (- 0 val) val)))
      ((= n 2)
       (let ((val (+ (vector-ref la 0) (* (vector-ref la 1) *bignum-radix*))))
         (if (< s 0) (- 0 val) val)))
      ((= n 3)
       ;; In 62-bit two's-complement fixnum: [fx-least, fx-greatest] = [-2^61, 2^61 - 1]
       (let ((l0 (vector-ref la 0))
             (l1 (vector-ref la 1))
             (l2 (vector-ref la 2)))
         (cond
           ((<= l2 1)
            (let ((val (+ (+ l0 (* l1 *bignum-radix*))
                          (* l2 (* *bignum-radix* *bignum-radix*)))))
              (if (< s 0) (- 0 val) val)))
           ((and (< s 0) (= l2 2) (= l1 0) (= l0 0))
            (let ((p60 (* *bignum-radix* *bignum-radix*)))
              (+ (- 0 p60) (- 0 p60))))
           (else #f))))
      (else #f))))

(define (%ensure-bignum x)
  (if (bignum? x)
      x
      (fixnum->bignum x)))

(define (bignum-demote x)
  (if (bignum? x)
      (let ((fx (bignum->fixnum x)))
        (if fx fx x))
      x))

;;; -----------------------------------------------------------------------
;;; §4. Comparisons
;;; -----------------------------------------------------------------------

(define (bignum-cmp-abs a b)
  (let* ((la (bignum-limbs a))
         (lb (bignum-limbs b))
         (na (vector-length la))
         (nb (vector-length lb)))
    (cond
      ((> na nb) 1)
      ((< na nb) -1)
      (else
       (let loop ((i (- na 1)))
         (if (< i 0)
             0
             (let ((va (vector-ref la i))
                   (vb (vector-ref lb i)))
               (cond
                 ((> va vb) 1)
                 ((< va vb) -1)
                 (else (loop (- i 1)))))))))))

(define (bignum-cmp a b)
  (let ((sa (bignum-sign a))
        (sb (bignum-sign b)))
    (cond
      ((> sa sb) 1)
      ((< sa sb) -1)
      ((= sa 0) 0)
      ((= sa 1) (bignum-cmp-abs a b))
      (else (- 0 (bignum-cmp-abs a b))))))

(define (bignum=? a b) (= (bignum-cmp a b) 0))
(define (bignum<? a b) (= (bignum-cmp a b) -1))
(define (bignum<=? a b) (<= (bignum-cmp a b) 0))
(define (bignum>? a b) (= (bignum-cmp a b) 1))
(define (bignum>=? a b) (>= (bignum-cmp a b) 0))

;;; -----------------------------------------------------------------------
;;; §5. Addition & Subtraction
;;; -----------------------------------------------------------------------

(define (%raw-add-abs la lb)
  (let* ((na (vector-length la))
         (nb (vector-length lb))
         (n (if (> na nb) na nb))
         (res (make-vector (+ n 1) 0)))
    (let loop ((i 0) (carry 0))
      (if (< i n)
          (let* ((va (if (< i na) (vector-ref la i) 0))
                 (vb (if (< i nb) (vector-ref lb i) 0))
                 (sum (+ (+ va vb) carry))
                 (digit (bitwise-and sum *bignum-radix-mask*))
                 (next-carry (quotient sum *bignum-radix*)))
            (vector-set! res i digit)
            (loop (+ i 1) next-carry))
          (begin
            (vector-set! res n carry)
            res)))))

(define (%raw-sub-abs la lb)
  (let* ((na (vector-length la))
         (nb (vector-length lb))
         (res (make-vector na 0)))
    (let loop ((i 0) (borrow 0))
      (if (< i na)
          (let* ((va (vector-ref la i))
                 (vb (if (< i nb) (vector-ref lb i) 0))
                 (diff (- (- va vb) borrow)))
            (if (< diff 0)
                (begin
                  (vector-set! res i (+ diff *bignum-radix*))
                  (loop (+ i 1) 1))
                (begin
                  (vector-set! res i diff)
                  (loop (+ i 1) 0))))
          res))))

(define (bignum-negate a)
  (if (bignum-zero? a)
      a
      (vector 'bignum (- 0 (bignum-sign a)) (bignum-limbs a))))

(define (bignum-abs a)
  (if (bignum-negative? a)
      (bignum-negate a)
      a))

(define (bignum-add a b)
  (let ((sa (bignum-sign a))
        (sb (bignum-sign b)))
    (cond
      ((= sa 0) b)
      ((= sb 0) a)
      ((= sa sb)
       (let ((res-limbs (%raw-add-abs (bignum-limbs a) (bignum-limbs b))))
         (bignum-normalize sa res-limbs)))
      (else
       (let ((cmp (bignum-cmp-abs a b)))
         (cond
           ((= cmp 0) (bignum-zero))
           ((> cmp 0)
            (let ((res-limbs (%raw-sub-abs (bignum-limbs a) (bignum-limbs b))))
              (bignum-normalize sa res-limbs)))
           (else
            (let ((res-limbs (%raw-sub-abs (bignum-limbs b) (bignum-limbs a))))
              (bignum-normalize sb res-limbs)))))))))

(define (bignum-sub a b)
  (bignum-add a (bignum-negate b)))

;;; -----------------------------------------------------------------------
;;; §6. Multiplication
;;; -----------------------------------------------------------------------

(define (%raw-mul-1limb la d)
  (let* ((na (vector-length la))
         (res (make-vector (+ na 1) 0)))
    (let loop ((i 0) (carry 0))
      (if (< i na)
          (let* ((prod (+ (* (vector-ref la i) d) carry))
                 (digit (bitwise-and prod *bignum-radix-mask*))
                 (next-carry (quotient prod *bignum-radix*)))
            (vector-set! res i digit)
            (loop (+ i 1) next-carry))
          (begin
            (vector-set! res na carry)
            res)))))

(define (%raw-mul-schoolbook la lb)
  (let* ((na (vector-length la))
         (nb (vector-length lb))
         (nres (+ na nb))
         (res (make-vector nres 0)))
    (let loop-i ((i 0))
      (if (< i na)
          (let ((ai (vector-ref la i)))
            (if (= ai 0)
                (loop-i (+ i 1))
                (let loop-j ((j 0) (carry 0))
                  (if (< j nb)
                      (let* ((bj (vector-ref lb j))
                             (cur (vector-ref res (+ i j)))
                             (prod (+ (+ (* ai bj) cur) carry))
                             (digit (bitwise-and prod *bignum-radix-mask*))
                             (next-carry (quotient prod *bignum-radix*)))
                        (vector-set! res (+ i j) digit)
                        (loop-j (+ j 1) next-carry))
                      (let loop-c ((k (+ i nb)) (c carry))
                        (if (> c 0)
                            (let* ((cur (vector-ref res k))
                                   (sum (+ cur c))
                                   (digit (bitwise-and sum *bignum-radix-mask*))
                                   (next-c (quotient sum *bignum-radix*)))
                              (vector-set! res k digit)
                              (loop-c (+ k 1) next-c))
                            (loop-i (+ i 1))))))))
          res))))

(define (bignum-mul a b)
  (if (or (bignum-zero? a) (bignum-zero? b))
      (bignum-zero)
      (let* ((sa (* (bignum-sign a) (bignum-sign b)))
             (la (bignum-limbs a))
             (lb (bignum-limbs b))
             (na (vector-length la))
             (nb (vector-length lb)))
        (cond
          ((and (= na 1) (= (vector-ref la 0) 1))
           (vector 'bignum sa lb))
          ((and (= nb 1) (= (vector-ref lb 0) 1))
           (vector 'bignum sa la))
          ((= nb 1)
           (bignum-normalize sa (%raw-mul-1limb la (vector-ref lb 0))))
          ((= na 1)
           (bignum-normalize sa (%raw-mul-1limb lb (vector-ref la 0))))
          (else
           (bignum-normalize sa (%raw-mul-schoolbook la lb)))))))

;;; -----------------------------------------------------------------------
;;; §7. Division & Remainder (Knuth Algorithm D)
;;; -----------------------------------------------------------------------

(define (%bignum-div-rem-1limb a d)
  (let* ((la (bignum-limbs a))
         (na (vector-length la))
         (q-limbs (make-vector na 0)))
    (let loop ((i (- na 1)) (rem 0))
      (if (< i 0)
          (let ((q-sign (bignum-sign a))
                (r-sign (if (= rem 0) 0 (bignum-sign a))))
            (values (bignum-normalize q-sign q-limbs)
                    (if (= rem 0)
                        (bignum-zero)
                        (vector 'bignum r-sign (vector rem)))))
          (let* ((cur (+ (* rem *bignum-radix*) (vector-ref la i)))
                 (q-digit (quotient cur d))
                 (r-digit (remainder cur d)))
            (vector-set! q-limbs i q-digit)
            (loop (- i 1) r-digit))))))

(define (%bignum-div-rem-knuth-d a b)
  (let* ((la (bignum-limbs a))
         (lb (bignum-limbs b))
         (na (vector-length la))
         (nb (vector-length lb))
         (m (- na nb))
         ;; D1. Normalize: find shift d = floor(B / (v_{n-1} + 1))
         (vn-1 (vector-ref lb (- nb 1)))
         (d (quotient *bignum-radix* (+ vn-1 1))))
    (let* ((u-limbs (%raw-mul-1limb la d))
           (v-limbs (%raw-mul-1limb lb d))
           (v-norm (make-vector nb 0))
           (u-norm (make-vector (+ na 1) 0)))
      ;; v-norm has exactly nb limbs (since d was chosen such that top limb < B)
      (let copy-v ((i 0))
        (if (< i nb)
            (begin
              (vector-set! v-norm i (vector-ref v-limbs i))
              (copy-v (+ i 1)))
            63))
      ;; u-norm has na + 1 limbs (index 0 to na)
      (let copy-u ((i 0))
        (if (< i (vector-length u-limbs))
            (begin
              (vector-set! u-norm i (vector-ref u-limbs i))
              (copy-u (+ i 1)))
            63))

      (let* ((q-limbs (make-vector (+ m 1) 0))
             (v1 (vector-ref v-norm (- nb 1)))
             (v2 (vector-ref v-norm (- nb 2))))
        ;; D2. Loop on j from m down to 0
        (let loop-j ((j m))
          (if (< j 0)
              ;; D8. Unnormalize remainder by dividing u-norm[0..nb-1] by d
              (let* ((rem-scaled-limbs (make-vector nb 0)))
                (let copy-r ((i 0))
                  (if (< i nb)
                      (begin
                        (vector-set! rem-scaled-limbs i (vector-ref u-norm i))
                        (copy-r (+ i 1)))
                      63))
                (let ((rem-scaled (bignum-normalize 1 rem-scaled-limbs)))
                  (call-with-values
                      (lambda () (%bignum-div-rem-1limb rem-scaled d))
                    (lambda (exact-rem ignored)
                      (let ((q-sign (* (bignum-sign a) (bignum-sign b)))
                            (r-sign (if (bignum-zero? exact-rem) 0 (bignum-sign a))))
                        (values (bignum-normalize q-sign q-limbs)
                                (vector 'bignum r-sign (bignum-limbs exact-rem))))))))

              ;; D3. Calculate \hat{q}
              (let* ((ujn (vector-ref u-norm (+ j nb)))
                     (ujn-1 (vector-ref u-norm (+ j (- nb 1))))
                     (ujn-2 (vector-ref u-norm (+ j (- nb 2))))
                     (num (+ (* ujn *bignum-radix*) ujn-1))
                     (q-hat-init
                      (if (= ujn v1)
                          (- *bignum-radix* 1)
                          (quotient num v1)))
                     (r-hat-init
                      (if (= ujn v1)
                          (+ ujn-1 v1)
                          (remainder num v1))))
                ;; Refine \hat{q}
                (let refine ((q-hat q-hat-init) (r-hat r-hat-init))
                  (if (and (< r-hat *bignum-radix*)
                           (> (* q-hat v2) (+ (* r-hat *bignum-radix*) ujn-2)))
                      (refine (- q-hat 1) (+ r-hat v1))

                      ;; D4. Multiply and subtract: u[j..j+nb] -= q_hat * v[0..nb-1]
                      (let loop-sub ((i 0) (carry 0) (borrow 0))
                        (if (< i nb)
                            (let* ((vi (vector-ref v-norm i))
                                   (prod (+ (* q-hat vi) carry))
                                   (p-digit (bitwise-and prod *bignum-radix-mask*))
                                   (p-carry (quotient prod *bignum-radix*))
                                   (cur (vector-ref u-norm (+ j i)))
                                   (diff (- (- cur p-digit) borrow)))
                              (if (< diff 0)
                                  (begin
                                    (vector-set! u-norm (+ j i) (+ diff *bignum-radix*))
                                    (loop-sub (+ i 1) p-carry 1))
                                  (begin
                                    (vector-set! u-norm (+ j i) diff)
                                    (loop-sub (+ i 1) p-carry 0))))
                            ;; Final limb of subtraction at j + nb
                            (let* ((cur (vector-ref u-norm (+ j nb)))
                                   (diff (- (- cur carry) borrow)))
                              (if (< diff 0)
                                  ;; D5 & D6. Test remainder: negative -> add back!
                                  (begin
                                    (vector-set! u-norm (+ j nb) (+ diff *bignum-radix*))
                                    (let loop-add ((i 0) (c 0))
                                      (if (< i nb)
                                          (let* ((cur (vector-ref u-norm (+ j i)))
                                                 (sum (+ (+ cur (vector-ref v-norm i)) c))
                                                 (digit (bitwise-and sum *bignum-radix-mask*))
                                                 (next-c (quotient sum *bignum-radix*)))
                                            (vector-set! u-norm (+ j i) digit)
                                            (loop-add (+ i 1) next-c))
                                          (let ((cur (vector-ref u-norm (+ j nb))))
                                            (vector-set! u-norm (+ j nb)
                                                         (bitwise-and (+ cur c) *bignum-radix-mask*))
                                            (vector-set! q-limbs j (- q-hat 1))
                                            (loop-j (- j 1))))))
                                  (begin
                                    (vector-set! u-norm (+ j nb) diff)
                                    (vector-set! q-limbs j q-hat)
                                    (loop-j (- j 1))))))))))))))))

;; THREAT-832-3: Guaranteed zero divisor check
(define (bignum-div-rem a b)
  (if (bignum-zero? b)
      (error "bignum-div-rem: division by zero")
      (if (bignum-zero? a)
          (values (bignum-zero) (bignum-zero))
          (let ((cmp (bignum-cmp-abs a b)))
            (cond
              ((< cmp 0)
               (values (bignum-zero) a))
              ((= cmp 0)
               (let ((q-sign (* (bignum-sign a) (bignum-sign b))))
                 (values (vector 'bignum q-sign (vector 1))
                         (bignum-zero))))
              (else
               (let ((nb (bignum-num-limbs b)))
                 (if (= nb 1)
                     (let ((d (vector-ref (bignum-limbs b) 0)))
                       (call-with-values
                           (lambda () (%bignum-div-rem-1limb a d))
                         (lambda (q r)
                           (let ((q-sign (* (bignum-sign a) (bignum-sign b))))
                             (values (vector 'bignum (if (bignum-zero? q) 0 q-sign)
                                             (bignum-limbs q))
                                     r)))))
                     (%bignum-div-rem-knuth-d a b)))))))))

(define (bignum-quotient a b)
  (call-with-values (lambda () (bignum-div-rem a b))
    (lambda (q r) q)))

(define (bignum-remainder a b)
  (call-with-values (lambda () (bignum-div-rem a b))
    (lambda (q r) r)))

(define (bignum-modulo a b)
  (call-with-values (lambda () (bignum-div-rem a b))
    (lambda (q r)
      (if (or (bignum-zero? r) (= (bignum-sign r) (bignum-sign b)))
          r
          (bignum-add r b)))))

;;; -----------------------------------------------------------------------
;;; §8. Bitwise Shifts & Logic Operations
;;; -----------------------------------------------------------------------

(define (bignum-shift-left a bits)
  (cond
    ((= bits 0) a)
    ((< bits 0) (bignum-shift-right a (- 0 bits)))
    ((bignum-zero? a) a)
    (else
     (let* ((limb-shift (quotient bits *bignum-radix-bits*))
            (bit-shift (remainder bits *bignum-radix-bits*))
            (la (bignum-limbs a))
            (na (vector-length la))
            (nres (+ (+ na limb-shift) 1))
            (res (make-vector nres 0))
            (multiplier (%bignum-pow2 bit-shift)))
       (let loop ((i 0) (carry 0))
         (if (< i na)
             (let* ((cur (vector-ref la i))
                    (val (+ (* cur multiplier) carry))
                    (digit (bitwise-and val *bignum-radix-mask*))
                    (next-carry (quotient val *bignum-radix*)))
               (vector-set! res (+ i limb-shift) digit)
               (loop (+ i 1) next-carry))
             (begin
               (vector-set! res (+ na limb-shift) carry)
               (bignum-normalize (bignum-sign a) res))))))))

(define (bignum-shift-right a bits)
  (cond
    ((= bits 0) a)
    ((< bits 0) (bignum-shift-left a (- 0 bits)))
    ((bignum-zero? a) a)
    ((bignum-negative? a)
     ;; Exact 2's complement arithmetic right shift: floor(a / 2^bits)
     ;; = - ( ( (|a| - 1) >> bits ) + 1 )
     (let* ((m-minus-1 (bignum-sub (bignum-abs a) (bignum-one)))
            (shifted (bignum-shift-right m-minus-1 bits)))
       (bignum-negate (bignum-add shifted (bignum-one)))))
    (else
     ;; Non-negative
     (let* ((limb-shift (quotient bits *bignum-radix-bits*))
            (bit-shift (remainder bits *bignum-radix-bits*))
            (la (bignum-limbs a))
            (na (vector-length la)))
       (if (>= limb-shift na)
           (bignum-zero)
           (let* ((nres (- na limb-shift))
                  (res (make-vector nres 0))
                  (divisor (%bignum-pow2 bit-shift))
                  (high-mult (%bignum-pow2 (- *bignum-radix-bits* bit-shift))))
             (let loop ((i 0))
               (if (< i nres)
                   (let* ((cur (vector-ref la (+ i limb-shift)))
                          (next (if (< (+ (+ i limb-shift) 1) na)
                                    (vector-ref la (+ (+ i limb-shift) 1))
                                    0))
                          (low-part (quotient cur divisor))
                          (high-part (if (> bit-shift 0)
                                         (bitwise-and (* next high-mult) *bignum-radix-mask*)
                                         0)))
                     (vector-set! res i (+ low-part high-part))
                     (loop (+ i 1)))
                   (bignum-normalize 1 res)))))))))

(define (bignum-bitwise-not a)
  (bignum-sub (fixnum->bignum -1) a))

(define (bignum-bitwise-and a b)
  (cond
    ((and (>= (bignum-sign a) 0) (>= (bignum-sign b) 0))
     (let* ((la (bignum-limbs a))
            (lb (bignum-limbs b))
            (na (vector-length la))
            (nb (vector-length lb))
            (n (if (< na nb) na nb))
            (res (make-vector n 0)))
       (let loop ((i 0))
         (if (< i n)
             (begin
               (vector-set! res i (bitwise-and (vector-ref la i) (vector-ref lb i)))
               (loop (+ i 1)))
             (bignum-normalize 1 res)))))
    ((and (< (bignum-sign a) 0) (< (bignum-sign b) 0))
     ;; ~a AND ~b = ~(a' IOR b')
     (let ((not-a (bignum-bitwise-not a))
           (not-b (bignum-bitwise-not b)))
       (bignum-bitwise-not (bignum-bitwise-ior not-a not-b))))
    ((< (bignum-sign a) 0)
     ;; a < 0, b >= 0: a AND b = b AND a
     (bignum-bitwise-and b a))
    (else
     ;; a >= 0, b < 0: a AND b = a AND NOT (~b)
     (let* ((not-b (bignum-bitwise-not b))
            (la (bignum-limbs a))
            (lb (bignum-limbs not-b))
            (na (vector-length la))
            (nb (vector-length lb))
            (res (make-vector na 0)))
       (let loop ((i 0))
         (if (< i na)
             (let* ((va (vector-ref la i))
                    (vb (if (< i nb) (vector-ref lb i) 0))
                    ;; not-vb within 30-bit limb is (mask - vb)
                    (not-vb (- *bignum-radix-mask* vb)))
               (vector-set! res i (bitwise-and va not-vb))
               (loop (+ i 1)))
             (bignum-normalize 1 res)))))))

(define (bignum-bitwise-ior a b)
  (cond
    ((and (>= (bignum-sign a) 0) (>= (bignum-sign b) 0))
     (let* ((la (bignum-limbs a))
            (lb (bignum-limbs b))
            (na (vector-length la))
            (nb (vector-length lb))
            (n (if (> na nb) na nb))
            (res (make-vector n 0)))
       (let loop ((i 0))
         (if (< i n)
             (let ((va (if (< i na) (vector-ref la i) 0))
                   (vb (if (< i nb) (vector-ref lb i) 0)))
               (vector-set! res i (bitwise-ior va vb))
               (loop (+ i 1)))
             (bignum-normalize 1 res)))))
    (else
     ;; De Morgan: a IOR b = ~(~a AND ~b)
     (let ((not-a (bignum-bitwise-not a))
           (not-b (bignum-bitwise-not b)))
       (bignum-bitwise-not (bignum-bitwise-and not-a not-b))))))

(define (bignum-bitwise-xor a b)
  (cond
    ((and (>= (bignum-sign a) 0) (>= (bignum-sign b) 0))
     (let* ((la (bignum-limbs a))
            (lb (bignum-limbs b))
            (na (vector-length la))
            (nb (vector-length lb))
            (n (if (> na nb) na nb))
            (res (make-vector n 0)))
       (let loop ((i 0))
         (if (< i n)
             (let* ((va (if (< i na) (vector-ref la i) 0))
                    (vb (if (< i nb) (vector-ref lb i) 0))
                    ;; a XOR b = (a IOR b) - (a AND b)
                    (vxor (- (bitwise-ior va vb) (bitwise-and va vb))))
               (vector-set! res i vxor)
               (loop (+ i 1)))
             (bignum-normalize 1 res)))))
    ((and (< (bignum-sign a) 0) (< (bignum-sign b) 0))
     ;; ~a XOR ~b = a XOR b
     (bignum-bitwise-xor (bignum-bitwise-not a) (bignum-bitwise-not b)))
    ((< (bignum-sign a) 0)
     ;; a < 0, b >= 0: ~(~a XOR b)
     (bignum-bitwise-not (bignum-bitwise-xor (bignum-bitwise-not a) b)))
    (else
     ;; a >= 0, b < 0: ~(a XOR ~b)
     (bignum-bitwise-not (bignum-bitwise-xor a (bignum-bitwise-not b))))))

;;; -----------------------------------------------------------------------
;;; §9. 64-bit Modulo Arithmetic (Modulo 2^64)
;;; -----------------------------------------------------------------------
;;; Conforms to DSN-38 §2 B1 (C preprocessor #if expressions & constant folding)

(define (bignum-u64-mask bn)
  (let* ((bn-pos
          (if (bignum-negative? bn)
              ;; 2^64 - (|bn| mod 2^64)
              (let* ((m (bignum-abs bn))
                     (low-m (bignum-u64-mask m)))
                (if (bignum-zero? low-m)
                    (bignum-zero)
                    (let ((two-64 (bignum-shift-left (bignum-one) 64)))
                      (bignum-sub two-64 low-m))))
              bn))
         (la (bignum-limbs bn-pos))
         (na (vector-length la)))
    (cond
      ((= na 0) (bignum-zero))
      ((= na 1) bn-pos)
      ((= na 2) bn-pos)
      (else
       ;; Keep at most 3 limbs: limb 0 (30 bits), limb 1 (30 bits), limb 2 (4 bits)
       (let* ((l0 (vector-ref la 0))
              (l1 (vector-ref la 1))
              (l2 (bitwise-and (vector-ref la 2) 15))
              (res (vector l0 l1 l2)))
         (bignum-normalize 1 res))))))

(define (bignum-s64-mask bn)
  (let* ((u (bignum-u64-mask bn))
         (two-63 (bignum-shift-left (bignum-one) 63)))
    (if (bignum>=? u two-63)
        (let ((two-64 (bignum-shift-left (bignum-one) 64)))
          (bignum-sub u two-64))
        u)))

(define (bignum->u64 bn) (bignum-u64-mask bn))
(define (bignum->s64 bn) (bignum-s64-mask bn))
(define (u64->bignum u) (bignum-u64-mask (if (bignum? u) u (fixnum->bignum u))))
(define (s64->bignum s) (bignum-s64-mask (if (bignum? s) s (fixnum->bignum s))))

(define (bignum-u64-add a b) (bignum-u64-mask (bignum-add a b)))
(define (bignum-u64-sub a b) (bignum-u64-mask (bignum-sub a b)))
(define (bignum-u64-mul a b) (bignum-u64-mask (bignum-mul a b)))
(define (bignum-u64-div a b)
  (let ((ua (bignum-u64-mask a))
        (ub (bignum-u64-mask b)))
    (bignum-u64-mask (bignum-quotient ua ub))))
(define (bignum-u64-rem a b)
  (let ((ua (bignum-u64-mask a))
        (ub (bignum-u64-mask b)))
    (bignum-u64-mask (bignum-remainder ua ub))))
(define (bignum-u64-and a b) (bignum-u64-mask (bignum-bitwise-and a b)))
(define (bignum-u64-ior a b) (bignum-u64-mask (bignum-bitwise-ior a b)))
(define (bignum-u64-xor a b) (bignum-u64-mask (bignum-bitwise-xor a b)))
(define (bignum-u64-not a)   (bignum-u64-mask (bignum-bitwise-not a)))
(define (bignum-u64-shift-left a n) (bignum-u64-mask (bignum-shift-left a n)))
(define (bignum-u64-shift-right a n) (bignum-u64-mask (bignum-shift-right (bignum-u64-mask a) n)))

;;; -----------------------------------------------------------------------
;;; §10. String Conversions (radix 2, 8, 10, 16)
;;; -----------------------------------------------------------------------

(define (%char->digit c)
  (cond
    ((and (char>=? c #\0) (char<=? c #\9))
     (- (char->integer c) 48))
    ((and (char>=? c #\a) (char<=? c #\f))
     (+ (- (char->integer c) 97) 10))
    ((and (char>=? c #\A) (char<=? c #\F))
     (+ (- (char->integer c) 65) 10))
    (else #f)))

(define (%digit->char d)
  (if (< d 10)
      (integer->char (+ 48 d))
      (integer->char (+ 87 d))))

(define (string->bignum str radix)
  (let ((len (string-length str)))
    (if (= len 0)
        (bignum-zero)
        (let* ((c0 (string-ref str 0))
               (neg (char=? c0 #\-))
               (has-sign (or neg (char=? c0 #\+)))
               (start-idx (if has-sign 1 0)))
          ;; Check for hex prefix "0x" or "0X"
          (let* ((is-hex-prefix
                  (and (= radix 16)
                       (<= (+ start-idx 2) len)
                       (char=? (string-ref str start-idx) #\0)
                       (let ((cx (string-ref str (+ start-idx 1))))
                         (or (char=? cx #\x) (char=? cx #\X)))))
                 (digit-start (if is-hex-prefix (+ start-idx 2) start-idx))
                 (radix-bn (fixnum->bignum radix)))
            (let loop ((i digit-start) (acc (bignum-zero)))
              (if (< i len)
                  (let ((d (%char->digit (string-ref str i))))
                    (if (and d (< d radix))
                        (let* ((acc*radix (bignum-mul acc radix-bn))
                               (acc-next (bignum-add acc*radix (fixnum->bignum d))))
                          (loop (+ i 1) acc-next))
                        (error "string->bignum: invalid digit for radix" (string-ref str i) radix)))
                  (if neg (bignum-negate acc) acc))))))))

(define (bignum->string bn radix)
  (if (bignum-zero? bn)
      "0"
      (let* ((neg (bignum-negative? bn))
             (abs-bn (bignum-abs bn))
             (radix-bn (fixnum->bignum radix)))
        (let loop ((cur abs-bn) (chars '()))
          (if (bignum-zero? cur)
              (let* ((chars-rev (if neg (cons #\- chars) chars))
                     (nchars (length chars-rev))
                     (res (make-string nchars)))
                (let copy ((cs chars-rev) (i 0))
                  (if (null? cs)
                      res
                      (begin
                        (string-set! res i (car cs))
                        (copy (cdr cs) (+ i 1))))))
              (call-with-values
                  (lambda () (bignum-div-rem cur radix-bn))
                (lambda (q r)
                  (let* ((digit (bignum->fixnum r))
                         (c (%digit->char digit)))
                    (loop q (cons c chars))))))))))
