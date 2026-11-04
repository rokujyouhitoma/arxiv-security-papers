;;; =======================================================================
;;; ULisp Standard Library: Elementary Integer Math (R7RS Section 6.2.6)
;;; Conforms to DSN-33 Architecture Specification & Issue #558
;;; Traceability: ulisp/docs/r7rs_specification_compliance.md
;;;
;;; Notes:
;;;   - `gcd` / `lcm` calls are desugared by Pass 030 into left-folded
;;;     chains of the binary kernels `gcd-2` / `lcm-2` (variadic support,
;;;     0 args -> 0 / 1, 1 arg -> |n|).
;;;   - `max` / `min` calls are desugared by Pass 030 into left-folded
;;;     chains of `max-2` / `min-2` (variadic support, 1 arg -> x,
;;;     2+ args -> (max-2 ...)). Procedural objects are provided via case-lambda.
;;;   - `abs` is intentionally NOT defined here because compiler/helpers.scm
;;;     already defines it inside build/ulisp_core.scm (duplicate top-level
;;;     definition avoidance). `%math-abs` is used internally instead.
;;; =======================================================================

;; ---------------------------------------------------------------------
;; Internal helper: absolute value
;; ---------------------------------------------------------------------
(define (%math-abs x)
  (if (< x 0) (- 0 x) x))

;; ---------------------------------------------------------------------
;; §6.2.6 square
;; ---------------------------------------------------------------------
(define (square z)
  (* z z))

;; ---------------------------------------------------------------------
;; §6.2.6 remainder (truncated division; result has the sign of n1)
;;   (= n1 (+ (* n2 (quotient n1 n2)) (remainder n1 n2)))
;; Implemented via quotient so that semantics are identical on the host
;; Scheme (ILisp) and on native AOT backends.
;; ---------------------------------------------------------------------
(define (remainder n1 n2)
  (- n1 (* (quotient n1 n2) n2)))

;; ---------------------------------------------------------------------
;; §6.2.6 gcd kernel (Euclidean algorithm, non-negative result)
;; ---------------------------------------------------------------------
(define (gcd-2 a b)
  (let loop ((x (%math-abs a)) (y (%math-abs b)))
    (if (= y 0)
        x
        (loop y (remainder x y)))))

;; ---------------------------------------------------------------------
;; §6.2.6 lcm kernel (non-negative result, 0 if any argument is 0)
;; Divide before multiply to reduce fixnum overflow risk.
;; ---------------------------------------------------------------------
(define (lcm-2 a b)
  (if (= a 0)
      0
      (if (= b 0)
          0
          (* (quotient (%math-abs a) (gcd-2 a b)) (%math-abs b)))))

;; ---------------------------------------------------------------------
;; §6.2.6 Exact Rationals (<ratnum>), numerator, denominator (Issue #711)
;;   Canonical invariants:
;;   - Denominator d > 0
;;   - gcd(|n|, d) = 1
;;   - If d = 1, automatically demotes to immediate Fixnum n.
;;   - Otherwise boxed as #(ulisp-ratnum-tag n d)
;; ---------------------------------------------------------------------
(define (make-rational n d)
  (if (= d 0)
      (error "make-rational: division by zero" n d)
      (let* ((num0 (if (< d 0) (- 0 n) n))
             (den0 (if (< d 0) (- 0 d) d))
             (g (gcd-2 num0 den0))
             (num (quotient num0 g))
             (den (quotient den0 g)))
        (if (= den 1)
            num
            (vector 'ulisp-ratnum-tag num den)))))

(define (numerator q)
  (cond
    ((fixnum? q) q)
    ((ratnum? q) (vector-ref q 1))
    ((flonum? q)
     (let ((v (vector-ref q 1)))
       (if (fixnum? v)
           (let ((r (make-rational v 1000000)))
             (vector 'ulisp-flonum-tag
                     (* (if (fixnum? r) r (vector-ref r 1)) 1000000)))
           (error "numerator: non-rational flonum" q))))
    (else (error "numerator: expected rational number" q))))

(define (denominator q)
  (cond
    ((fixnum? q) 1)
    ((ratnum? q) (vector-ref q 2))
    ((flonum? q)
     (let ((v (vector-ref q 1)))
       (if (fixnum? v)
           (let ((r (make-rational v 1000000)))
             (vector 'ulisp-flonum-tag
                     (* (if (fixnum? r) 1 (vector-ref r 2)) 1000000)))
           (error "denominator: non-rational flonum" q))))
    (else (error "denominator: expected rational number" q))))

(define (%exact-rat-num x)
  (cond
    ((fixnum? x) x)
    ((ratnum? x) (vector-ref x 1))
    ((and (flonum? x) (fixnum? (vector-ref x 1)))
     (let ((r (make-rational (vector-ref x 1) 1000000)))
       (if (fixnum? r) r (vector-ref r 1))))
    (else (error "rational operation: expected rational number" x))))

(define (%exact-rat-den x)
  (cond
    ((fixnum? x) 1)
    ((ratnum? x) (vector-ref x 2))
    ((and (flonum? x) (fixnum? (vector-ref x 1)))
     (let ((r (make-rational (vector-ref x 1) 1000000)))
       (if (fixnum? r) 1 (vector-ref r 2))))
    (else (error "rational operation: expected rational number" x))))

(define (rat+ a b)
  (let ((na (%exact-rat-num a))
        (da (%exact-rat-den a))
        (nb (%exact-rat-num b))
        (db (%exact-rat-den b)))
    (make-rational (+ (* na db) (* nb da)) (* da db))))

(define rat-
  (case-lambda
    ((a)
     (make-rational (- 0 (%exact-rat-num a)) (%exact-rat-den a)))
    ((a b)
     (let ((na (%exact-rat-num a))
           (da (%exact-rat-den a))
           (nb (%exact-rat-num b))
           (db (%exact-rat-den b)))
       (make-rational (- (* na db) (* nb da)) (* da db))))))

(define (rat* a b)
  (let ((na (%exact-rat-num a))
        (da (%exact-rat-den a))
        (nb (%exact-rat-num b))
        (db (%exact-rat-den b)))
    (make-rational (* na nb) (* da db))))

(define rat/
  (case-lambda
    ((a)
     (make-rational (%exact-rat-den a) (%exact-rat-num a)))
    ((a b)
     (let ((na (%exact-rat-num a))
           (da (%exact-rat-den a))
           (nb (%exact-rat-num b))
           (db (%exact-rat-den b)))
       (make-rational (* na db) (* da nb))))))

(define (rat= a b)
  (and (= (%exact-rat-num a) (%exact-rat-num b))
       (= (%exact-rat-den a) (%exact-rat-den b))))

(define (rat< a b)
  (< (* (%exact-rat-num a) (%exact-rat-den b))
     (* (%exact-rat-num b) (%exact-rat-den a))))

(define (rat<= a b)
  (<= (* (%exact-rat-num a) (%exact-rat-den b))
      (* (%exact-rat-num b) (%exact-rat-den a))))

(define (rat> a b)
  (> (* (%exact-rat-num a) (%exact-rat-den b))
     (* (%exact-rat-num b) (%exact-rat-den a))))

(define (rat>= a b)
  (>= (* (%exact-rat-num a) (%exact-rat-den b))
      (* (%exact-rat-num b) (%exact-rat-den a))))

(define (%int-expt base exp)
  (let loop ((b base) (e exp) (acc 1))
    (if (= e 0)
        acc
        (loop (* b b)
              (quotient e 2)
              (if (= (remainder e 2) 0) acc (* acc b))))))

;; ---------------------------------------------------------------------
;; §6.2.6 expt (exact integer/rational exponentiation, O(log n))
;;   z2 = 0  -> 1 (including 0^0 = 1 per R7RS)
;;   z2 < 0  -> exact rational 1 / z1^|z2|; 0^(-k) raises an error.
;; ---------------------------------------------------------------------
(define (expt z1 z2)
  (cond
    ((= z2 0) 1)
    ((ratnum? z1)
     (let ((n (vector-ref z1 1))
           (d (vector-ref z1 2)))
       (if (< z2 0)
           (let ((pos-e (- 0 z2)))
             (make-rational (%int-expt d pos-e) (%int-expt n pos-e)))
           (make-rational (%int-expt n z2) (%int-expt d z2)))))
    ((< z2 0)
     (if (= z1 0)
         (error "expt: zero base with negative exponent" z2)
         (make-rational 1 (%int-expt z1 (- 0 z2)))))
    (else
     (%int-expt z1 z2))))

;; ---------------------------------------------------------------------
;; §6.2.6 Truncated & Floored Integer Division (SRFI 141)
;; ---------------------------------------------------------------------
(define (truncate-quotient n1 n2)
  (quotient n1 n2))

(define (truncate-remainder n1 n2)
  (remainder n1 n2))

(define (truncate/ n1 n2)
  (let ((q (quotient n1 n2)))
    (values q (- n1 (* q n2)))))

(define (floor-quotient n1 n2)
  (let* ((q (quotient n1 n2))
         (r (- n1 (* q n2))))
    (if (or (= r 0)
            (if (< n1 0)
                (< n2 0)
                (>= n2 0)))
        q
        (- q 1))))

(define (floor-remainder n1 n2)
  (let ((r (remainder n1 n2)))
    (if (or (= r 0)
            (if (< n1 0)
                (< n2 0)
                (>= n2 0)))
        r
        (+ r n2))))

(define (floor/ n1 n2)
  (let* ((q (quotient n1 n2))
         (r (- n1 (* q n2))))
    (if (or (= r 0)
            (if (< n1 0)
                (< n2 0)
                (>= n2 0)))
        (values q r)
        (values (- q 1) (+ r n2)))))

;; §6.2.6 Ceiling Integer Division (SRFI 141)
(define (ceiling/ n1 n2)
  (let* ((q (quotient n1 n2))
         (r (- n1 (* q n2))))
    (if (or (= r 0)
            (if (> n1 0)
                (<= n2 0)
                (>= n2 0)))
        (values q r)
        (values (+ q 1) (- r n2)))))

(define (ceiling-quotient n1 n2)
  (call-with-values (lambda () (ceiling/ n1 n2)) (lambda (q r) q)))

(define (ceiling-remainder n1 n2)
  (call-with-values (lambda () (ceiling/ n1 n2)) (lambda (q r) r)))

;; §6.2.6 Round Integer Division (SRFI 141)
(define (round/ n1 n2)
  (let* ((q-t (quotient n1 n2))
         (r-t (- n1 (* q-t n2)))
         (r-abs (if (< r-t 0) (- 0 r-t) r-t))
         (d-abs (if (< n2 0) (- 0 n2) n2))
         (same-sign? (or (and (> n1 0) (> n2 0)) (and (< n1 0) (< n2 0)))))
    (cond
      ((= r-t 0)
       (values q-t 0))
      ((< (* 2 r-abs) d-abs)
       (values q-t r-t))
      ((> (* 2 r-abs) d-abs)
       (if same-sign?
           (values (+ q-t 1) (- r-t n2))
           (values (- q-t 1) (+ r-t n2))))
      (else
       ;; Half-way tie: round to nearest even quotient
       (if (= (modulo q-t 2) 0)
           (values q-t r-t)
           (if same-sign?
               (values (+ q-t 1) (- r-t n2))
               (values (- q-t 1) (+ r-t n2))))))))

(define (round-quotient n1 n2)
  (call-with-values (lambda () (round/ n1 n2)) (lambda (q r) q)))

(define (round-remainder n1 n2)
  (call-with-values (lambda () (round/ n1 n2)) (lambda (q r) r)))

;; §6.2.6 Euclidean Integer Division (SRFI 141)
(define (euclidean/ n1 n2)
  (if (> n2 0)
      (floor/ n1 n2)
      (ceiling/ n1 n2)))

(define (euclidean-quotient n1 n2)
  (call-with-values (lambda () (euclidean/ n1 n2)) (lambda (q r) q)))

(define (euclidean-remainder n1 n2)
  (call-with-values (lambda () (euclidean/ n1 n2)) (lambda (q r) r)))

;; §6.2.6 Centered Integer Division (SRFI 141)
(define (centered/ n1 n2)
  (call-with-values (lambda () (euclidean/ n1 n2))
    (lambda (q r)
      (let ((d-abs (if (< n2 0) (- 0 n2) n2)))
        (if (>= (* 2 r) d-abs)
            (if (> n2 0)
                (values (+ q 1) (- r d-abs))
                (values (- q 1) (+ r d-abs)))
            (values q r))))))

(define (centered-quotient n1 n2)
  (call-with-values (lambda () (centered/ n1 n2)) (lambda (q r) q)))

(define (centered-remainder n1 n2)
  (call-with-values (lambda () (centered/ n1 n2)) (lambda (q r) r)))

;; ---------------------------------------------------------------------
;; §6.2.6 exact-integer-sqrt (R7RS Section 6.2.6)
;; ---------------------------------------------------------------------
(define (exact-integer-sqrt k)
  (if (< k 0)
      (error "exact-integer-sqrt: argument must be non-negative" k)
      (if (<= k 1)
          (values k 0)
          (let loop ((low 1)
                     (high (if (< k 500000000) k 500000000))
                     (ans 1))
            (if (<= low high)
                (let* ((mid (quotient (+ low high) 2))
                       (sq (* mid mid)))
                  (cond
                    ((= sq k)
                     (values mid 0))
                    ((< sq k)
                     (loop (+ mid 1) high mid))
                    (else
                     (loop low (- mid 1) ans))))
                (values ans (- k (* ans ans))))))))

;; ---------------------------------------------------------------------
;; §6.2.6 max and min (variadic support, Issue #653)
;; Binary kernels for desugared inlined comparisons and first-class procedures.
;; ---------------------------------------------------------------------
(define (max-2 a b)
  (if (> a b) a b))

(define (min-2 a b)
  (if (< a b) a b))

(define max
  (case-lambda
    ((a) a)
    ((a b) (max-2 a b))
    ((a b c) (max-2 (max-2 a b) c))
    ((a b c d) (max-2 (max-2 (max-2 a b) c) d))
    ((a b c d . rest)
     (let loop ((m (max-2 (max-2 (max-2 a b) c) d)) (r rest))
       (if (null? r)
           m
           (loop (max-2 m (car r)) (cdr r)))))))

(define min
  (case-lambda
    ((a) a)
    ((a b) (min-2 a b))
    ((a b c) (min-2 (min-2 a b) c))
    ((a b c d) (min-2 (min-2 (min-2 a b) c) d))
    ((a b c d . rest)
     (let loop ((m (min-2 (min-2 (min-2 a b) c) d)) (r rest))
       (if (null? r)
           m
           (loop (min-2 m (car r)) (cdr r)))))))

;; ---------------------------------------------------------------------
;; §6.2.6 Rounding & Simplest Rational (floor, ceiling, truncate, round, rationalize)
;;   Conforms to R7RS §6.2.6 & Issue #711
;; ---------------------------------------------------------------------

(define (floor x)
  (cond
    ((fixnum? x) x)
    ((ratnum? x)
     (floor-quotient (vector-ref x 1) (vector-ref x 2)))
    ((flonum? x)
     (let ((v (vector-ref x 1)))
       (if (fixnum? v)
           (vector 'ulisp-flonum-tag (* (floor-quotient v 1000000) 1000000))
           (error "floor: non-finite flonum" x))))
    (else (error "floor: expected real number" x))))

(define (ceiling x)
  (cond
    ((fixnum? x) x)
    ((ratnum? x)
     (ceiling-quotient (vector-ref x 1) (vector-ref x 2)))
    ((flonum? x)
     (let ((v (vector-ref x 1)))
       (if (fixnum? v)
           (vector 'ulisp-flonum-tag (* (ceiling-quotient v 1000000) 1000000))
           (error "ceiling: non-finite flonum" x))))
    (else (error "ceiling: expected real number" x))))

(define (truncate x)
  (cond
    ((fixnum? x) x)
    ((ratnum? x)
     (truncate-quotient (vector-ref x 1) (vector-ref x 2)))
    ((flonum? x)
     (let ((v (vector-ref x 1)))
       (if (fixnum? v)
           (vector 'ulisp-flonum-tag (* (truncate-quotient v 1000000) 1000000))
           (error "truncate: non-finite flonum" x))))
    (else (error "truncate: expected real number" x))))

(define (round x)
  (cond
    ((fixnum? x) x)
    ((ratnum? x)
     (round-quotient (vector-ref x 1) (vector-ref x 2)))
    ((flonum? x)
     (let ((v (vector-ref x 1)))
       (if (fixnum? v)
           (vector 'ulisp-flonum-tag (* (round-quotient v 1000000) 1000000))
           (error "round: non-finite flonum" x))))
    (else (error "round: expected real number" x))))

;; Continued-fraction / Stern-Brocot simplest rational in [n1/d1, n2/d2]
;; Preconditions: 0 < n1/d1 <= n2/d2, d1 > 0, d2 > 0
(define (%simplest-pos-rational n1 d1 n2 d2)
  (let ((q1 (quotient n1 d1))
        (r1 (remainder n1 d1))
        (q2 (quotient n2 d2))
        (r2 (remainder n2 d2)))
    (cond
      ((= r1 0)
       (cons q1 1))
      ((< q1 q2)
       (cons (+ q1 1) 1))
      (else
       (let ((sub (%simplest-pos-rational d2 r2 d1 r1)))
         (cons (+ (* q1 (car sub)) (cdr sub))
               (car sub)))))))

(define (rationalize x y)
  (let* ((inex? (or (flonum? x) (flonum? y)))
         (nx (%exact-rat-num x))
         (dx (%exact-rat-den x))
         (ny0 (%exact-rat-num y))
         (dy (%exact-rat-den y))
         (ny (if (< ny0 0) (- 0 ny0) ny0))
         (lo (rat- (make-rational nx dx) (make-rational ny dy)))
         (hi (rat+ (make-rational nx dx) (make-rational ny dy)))
         (n1 (%exact-rat-num lo))
         (d1 (%exact-rat-den lo))
         (n2 (%exact-rat-num hi))
         (d2 (%exact-rat-den hi))
         (exact-res
          (cond
            ((and (<= n1 0) (>= n2 0))
             0)
            ((< n2 0)
             (let ((pq (%simplest-pos-rational (- 0 n2) d2 (- 0 n1) d1)))
               (make-rational (- 0 (car pq)) (cdr pq))))
            (else
             (let ((pq (%simplest-pos-rational n1 d1 n2 d2)))
               (make-rational (car pq) (cdr pq)))))))
    (if inex?
        (let ((rn (%exact-rat-num exact-res))
              (rd (%exact-rat-den exact-res)))
          (vector 'ulisp-flonum-tag (round-quotient (* rn 1000000) rd)))
        exact-res)))
