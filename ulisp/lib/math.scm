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
           x)))
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
           x)))
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
           x)))
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
           x)))
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

;; ---------------------------------------------------------------------
;; §6.2.6 Inexact Reals (<flonum>), IEEE Special Values, and Exactness
;;   Conforms to R7RS §6.2.2, §6.2.6 & Issue #712
;; ---------------------------------------------------------------------

(define (make-flonum-micros micros-or-sym)
  (vector 'ulisp-flonum-tag micros-or-sym))

(define (make-flonum int-part micro-frac)
  (vector 'ulisp-flonum-tag (+ (* int-part 1000000) micro-frac)))

(define +inf.0 (vector 'ulisp-flonum-tag 'pos-inf))
(define -inf.0 (vector 'ulisp-flonum-tag 'neg-inf))
(define +nan.0 (vector 'ulisp-flonum-tag 'nan))
(define -nan.0 +nan.0)

(define (inexact z)
  (cond
    ((fixnum? z)
     (vector 'ulisp-flonum-tag (* z 1000000)))
    ((ratnum? z)
     (vector 'ulisp-flonum-tag
             (round-quotient (* (vector-ref z 1) 1000000) (vector-ref z 2))))
    ((flonum? z)
     z)
    ((compnum? z)
     (vector 'ulisp-complex-tag
             (inexact (vector-ref z 1))
             (inexact (vector-ref z 2))))
    (else
     (error "inexact: expected number" z))))

(define (exact z)
  (cond
    ((fixnum? z) z)
    ((ratnum? z) z)
    ((flonum? z)
     (let ((v (vector-ref z 1)))
       (if (fixnum? v)
           (make-rational v 1000000)
           (error "exact: cannot convert non-finite flonum to exact" z))))
    ((compnum? z)
     (let ((re (exact (vector-ref z 1)))
           (im (exact (vector-ref z 2))))
       (if (and (fixnum? im) (= im 0))
           re
           (vector 'ulisp-complex-tag re im))))
    (else
     (error "exact: expected number" z))))

(define (exact->inexact z) (inexact z))
(define (inexact->exact z) (exact z))

(define (%to-flonum-val x)
  (cond
    ((flonum? x) (vector-ref x 1))
    ((fixnum? x) (* x 1000000))
    ((ratnum? x) (round-quotient (* (vector-ref x 1) 1000000) (vector-ref x 2)))
    (else (error "flonum operation: expected real number" x))))

(define (flo+ a b)
  (let ((va (%to-flonum-val a))
        (vb (%to-flonum-val b)))
    (cond
      ((or (eq? va 'nan) (eq? vb 'nan)) +nan.0)
      ((and (eq? va 'pos-inf) (eq? vb 'neg-inf)) +nan.0)
      ((and (eq? va 'neg-inf) (eq? vb 'pos-inf)) +nan.0)
      ((or (eq? va 'pos-inf) (eq? vb 'pos-inf)) +inf.0)
      ((or (eq? va 'neg-inf) (eq? vb 'neg-inf)) -inf.0)
      (else (make-flonum-micros (+ va vb))))))

(define flo-
  (case-lambda
    ((a)
     (let ((va (%to-flonum-val a)))
       (cond
         ((eq? va 'nan) +nan.0)
         ((eq? va 'pos-inf) -inf.0)
         ((eq? va 'neg-inf) +inf.0)
         (else (make-flonum-micros (- 0 va))))))
    ((a b)
     (flo+ a (flo- b)))))

(define (flo* a b)
  (let ((va (%to-flonum-val a))
        (vb (%to-flonum-val b)))
    (cond
      ((or (eq? va 'nan) (eq? vb 'nan)) +nan.0)
      ((or (and (or (eq? va 'pos-inf) (eq? va 'neg-inf)) (and (fixnum? vb) (= vb 0)))
           (and (or (eq? vb 'pos-inf) (eq? vb 'neg-inf)) (and (fixnum? va) (= va 0))))
       +nan.0)
      ((or (eq? va 'pos-inf) (eq? vb 'pos-inf))
       (let ((neg? (or (and (eq? va 'pos-inf) (or (eq? vb 'neg-inf) (and (fixnum? vb) (< vb 0))))
                       (and (eq? vb 'pos-inf) (or (eq? va 'neg-inf) (and (fixnum? va) (< va 0)))))))
         (if neg? -inf.0 +inf.0)))
      ((or (eq? va 'neg-inf) (eq? vb 'neg-inf))
       (let ((pos? (or (and (eq? va 'neg-inf) (or (eq? vb 'neg-inf) (and (fixnum? vb) (< vb 0))))
                       (and (eq? vb 'neg-inf) (or (eq? va 'neg-inf) (and (fixnum? va) (< va 0)))))))
         (if pos? +inf.0 -inf.0)))
      (else
       (make-flonum-micros (round-quotient (* va vb) 1000000))))))

(define flo/
  (case-lambda
    ((a)
     (flo/ (make-flonum-micros 1000000) a))
    ((a b)
     (let ((va (%to-flonum-val a))
           (vb (%to-flonum-val b)))
       (cond
         ((or (eq? va 'nan) (eq? vb 'nan)) +nan.0)
         ((and (or (eq? va 'pos-inf) (eq? va 'neg-inf))
               (or (eq? vb 'pos-inf) (eq? vb 'neg-inf)))
          +nan.0)
         ((or (eq? vb 'pos-inf) (eq? vb 'neg-inf))
          (make-flonum-micros 0))
         ((and (fixnum? vb) (= vb 0))
          (cond
            ((and (fixnum? va) (= va 0)) +nan.0)
            ((or (eq? va 'pos-inf) (and (fixnum? va) (> va 0))) +inf.0)
            (else -inf.0)))
         ((eq? va 'pos-inf)
          (if (< vb 0) -inf.0 +inf.0))
         ((eq? va 'neg-inf)
          (if (< vb 0) +inf.0 -inf.0))
         (else
          (make-flonum-micros (round-quotient (* va 1000000) vb))))))))

(define (flo= a b)
  (let ((va (%to-flonum-val a))
        (vb (%to-flonum-val b)))
    (if (or (eq? va 'nan) (eq? vb 'nan))
        #f
        (eq? va vb))))

(define (flo< a b)
  (let ((va (%to-flonum-val a))
        (vb (%to-flonum-val b)))
    (cond
      ((or (eq? va 'nan) (eq? vb 'nan)) #f)
      ((eq? va vb) #f)
      ((eq? va 'neg-inf) #t)
      ((eq? vb 'pos-inf) #t)
      ((or (eq? va 'pos-inf) (eq? vb 'neg-inf)) #f)
      (else (< va vb)))))

(define (flo<= a b)
  (or (flo= a b) (flo< a b)))

(define (flo> a b)
  (flo< b a))

(define (flo>= a b)
  (or (flo= a b) (flo< b a)))

;; Mixed-exactness real & complex arithmetic with R7RS Inexactness Contagion
(define (%real-num+ a b)
  (cond
    ((and (fixnum? a) (fixnum? b)) (+ a b))
    ((or (inexact? a) (inexact? b)) (flo+ a b))
    (else (rat+ a b))))

(define %real-num-
  (case-lambda
    ((a)
     (cond
       ((fixnum? a) (- 0 a))
       ((inexact? a) (flo- a))
       (else (rat- a))))
    ((a b)
     (cond
       ((and (fixnum? a) (fixnum? b)) (- a b))
       ((or (inexact? a) (inexact? b)) (flo- a b))
       (else (rat- a b))))))

(define (%real-num* a b)
  (cond
    ((and (fixnum? a) (fixnum? b)) (* a b))
    ((or (inexact? a) (inexact? b)) (flo* a b))
    (else (rat* a b))))

(define %real-num/
  (case-lambda
    ((a)
     (if (inexact? a) (flo/ a) (rat/ a)))
    ((a b)
     (if (or (inexact? a) (inexact? b))
         (flo/ a b)
         (rat/ a b)))))

(define (%real-num= a b)
  (cond
    ((and (fixnum? a) (fixnum? b)) (= a b))
    ((or (inexact? a) (inexact? b)) (flo= a b))
    (else (rat= a b))))

;; ---------------------------------------------------------------------
;; §6.2.6 Complex Numbers ((scheme complex), Issue #714)
;;   make-rectangular, make-polar, real-part, imag-part, magnitude, angle
;; ---------------------------------------------------------------------

(define (make-rectangular x1 x2)
  (if (and (fixnum? x2) (= x2 0))
      x1
      (vector 'ulisp-complex-tag x1 x2)))

(define (real-part z)
  (cond
    ((compnum? z) (vector-ref z 1))
    ((%real? z) z)
    (else (error "real-part: expected complex number" z))))

(define (imag-part z)
  (cond
    ((compnum? z) (vector-ref z 2))
    ((%real? z) 0)
    (else (error "imag-part: expected complex number" z))))

(define (comp+ z1 z2)
  (make-rectangular (%real-num+ (real-part z1) (real-part z2))
                    (%real-num+ (imag-part z1) (imag-part z2))))

(define comp-
  (case-lambda
    ((z1)
     (make-rectangular (%real-num- (real-part z1))
                       (%real-num- (imag-part z1))))
    ((z1 z2)
     (make-rectangular (%real-num- (real-part z1) (real-part z2))
                       (%real-num- (imag-part z1) (imag-part z2))))))

(define (comp* z1 z2)
  (let ((a (real-part z1))
        (b (imag-part z1))
        (c (real-part z2))
        (d (imag-part z2)))
    (make-rectangular (%real-num- (%real-num* a c) (%real-num* b d))
                      (%real-num+ (%real-num* a d) (%real-num* b c)))))

(define comp/
  (case-lambda
    ((z1)
     (comp/ 1 z1))
    ((z1 z2)
     (let* ((a (real-part z1))
            (b (imag-part z1))
            (c (real-part z2))
            (d (imag-part z2))
            (denom (%real-num+ (%real-num* c c) (%real-num* d d))))
       (make-rectangular (%real-num/ (%real-num+ (%real-num* a c) (%real-num* b d)) denom)
                         (%real-num/ (%real-num- (%real-num* b c) (%real-num* a d)) denom))))))

(define (comp= z1 z2)
  (and (%real-num= (real-part z1) (real-part z2))
       (%real-num= (imag-part z1) (imag-part z2))))

(define (num+ a b)
  (if (or (compnum? a) (compnum? b))
      (comp+ a b)
      (%real-num+ a b)))

(define num-
  (case-lambda
    ((a)
     (if (compnum? a) (comp- a) (%real-num- a)))
    ((a b)
     (if (or (compnum? a) (compnum? b))
         (comp- a b)
         (%real-num- a b)))))

(define (num* a b)
  (if (or (compnum? a) (compnum? b))
      (comp* a b)
      (%real-num* a b)))

(define num/
  (case-lambda
    ((a)
     (if (compnum? a) (comp/ a) (%real-num/ a)))
    ((a b)
     (if (or (compnum? a) (compnum? b))
         (comp/ a b)
         (%real-num/ a b)))))

(define (num= a b)
  (if (or (compnum? a) (compnum? b))
      (comp= a b)
      (%real-num= a b)))

(define (num< a b)
  (cond
    ((and (fixnum? a) (fixnum? b)) (< a b))
    ((or (inexact? a) (inexact? b)) (flo< a b))
    (else (rat< a b))))

(define (num<= a b)
  (cond
    ((and (fixnum? a) (fixnum? b)) (<= a b))
    ((or (inexact? a) (inexact? b)) (flo<= a b))
    (else (rat<= a b))))

(define (num> a b)
  (cond
    ((and (fixnum? a) (fixnum? b)) (> a b))
    ((or (inexact? a) (inexact? b)) (flo> a b))
    (else (rat> a b))))

(define (num>= a b)
  (cond
    ((and (fixnum? a) (fixnum? b)) (>= a b))
    ((or (inexact? a) (inexact? b)) (flo>= a b))
    (else (rat>= a b))))

;; ---------------------------------------------------------------------
;; §6.2.6 Transcendental Functions & Square Root ((scheme inexact), Issue #713)
;;   Pure Scheme fixed-point micro-unit (10^6) algorithms:
;;   sqrt, exp, log, sin, cos, tan, asin, acos, atan
;; ---------------------------------------------------------------------

(define (%micro-isqrt n)
  (if (<= n 0)
      0
      (call-with-values
        (lambda () (exact-integer-sqrt n))
        (lambda (s r)
          (if (> r s) (+ s 1) s)))))

(define (sqrt z)
  (cond
    ((fixnum? z)
     (if (< z 0)
         (let ((im (sqrt (- 0 z))))
           (vector 'ulisp-complex-tag 0 im))
         (call-with-values
           (lambda () (exact-integer-sqrt z))
           (lambda (s r)
             (if (= r 0)
                 s
                 (make-flonum-micros (%micro-isqrt (* z 1000000000000))))))))
    ((ratnum? z)
     (let ((n (vector-ref z 1))
           (d (vector-ref z 2)))
       (if (< n 0)
           (vector 'ulisp-complex-tag 0 (sqrt (make-rational (- 0 n) d)))
           (call-with-values
             (lambda () (exact-integer-sqrt n))
             (lambda (sn rn)
               (call-with-values
                 (lambda () (exact-integer-sqrt d))
                 (lambda (sd rd)
                   (if (and (= rn 0) (= rd 0))
                       (make-rational sn sd)
                       (let ((v (round-quotient (* n 1000000) d)))
                         (make-flonum-micros (%micro-isqrt (* v 1000000))))))))))))
    ((flonum? z)
     (let ((v (vector-ref z 1)))
       (cond
         ((eq? v 'nan) +nan.0)
         ((eq? v 'pos-inf) +inf.0)
         ((eq? v 'neg-inf) (vector 'ulisp-complex-tag (make-flonum-micros 0) +inf.0))
         ((< v 0)
          (vector 'ulisp-complex-tag
                  (make-flonum-micros 0)
                  (make-flonum-micros (%micro-isqrt (* (- 0 v) 1000000)))))
         (else
          (make-flonum-micros (%micro-isqrt (* v 1000000)))))))
    (else
     (error "sqrt: expected number" z))))

(define (exp z)
  (let ((v (%to-flonum-val z)))
    (cond
      ((eq? v 'nan) +nan.0)
      ((eq? v 'pos-inf) +inf.0)
      ((eq? v 'neg-inf) (make-flonum-micros 0))
      ((= v 0) (if (exact? z) 1 (make-flonum-micros 1000000)))
      (else
       (let* ((k (round-quotient v 693147))
              (r (- (- v (* k 693147)) (round-quotient (* k 181) 1000)))
              (t1 r)
              (t2 (round-quotient (* t1 r) 2000000))
              (t3 (round-quotient (* t2 r) 3000000))
              (t4 (round-quotient (* t3 r) 4000000))
              (t5 (round-quotient (* t4 r) 5000000))
              (t6 (round-quotient (* t5 r) 6000000))
              (t7 (round-quotient (* t6 r) 7000000))
              (er (+ 1000000 (+ t1 (+ t2 (+ t3 (+ t4 (+ t5 (+ t6 t7)))))))))
         (cond
           ((= k 0) (make-flonum-micros er))
           ((> k 0) (make-flonum-micros (* er (%int-expt 2 k))))
           ((< k -30) (make-flonum-micros 0))
           (else (make-flonum-micros (round-quotient er (%int-expt 2 (- 0 k)))))))))))

(define (%log-natural z)
  (let ((v (%to-flonum-val z)))
    (cond
      ((eq? v 'nan) +nan.0)
      ((eq? v 'pos-inf) +inf.0)
      ((eq? v 'neg-inf) +nan.0)
      ((= v 0) (error "log: undefined for zero" z))
      ((< v 0)
       (vector 'ulisp-complex-tag
               (%log-natural (make-flonum-micros (- 0 v)))
               (make-flonum-micros 3141593)))
      ((= v 1000000)
       (if (exact? z) 0 (make-flonum-micros 0)))
      (else
       (let loop ((m v) (k 0))
         (cond
           ((< m 707107)
            (loop (* m 2) (- k 1)))
           ((> m 1414214)
            (loop (round-quotient m 2) (+ k 1)))
           (else
            (let* ((u (round-quotient (* (- m 1000000) 1000000) (+ m 1000000)))
                   (u2 (round-quotient (* u u) 1000000))
                   (u3 (round-quotient (* u u2) 1000000))
                   (u5 (round-quotient (* u3 u2) 1000000))
                   (u7 (round-quotient (* u5 u2) 1000000))
                   (u9 (round-quotient (* u7 u2) 1000000))
                   (ln-m (* 2 (+ u (+ (round-quotient u3 3)
                                      (+ (round-quotient u5 5)
                                         (+ (round-quotient u7 7)
                                            (round-quotient u9 9)))))))
                   (k-ln2 (+ (* k 693147) (round-quotient (* k 181) 1000))))
              (make-flonum-micros (+ k-ln2 ln-m))))))))))

(define log
  (case-lambda
    ((z) (%log-natural z))
    ((z base) (flo/ (%log-natural z) (%log-natural base)))))

(define (%sin-quarter r)
  (let* ((r2 (round-quotient (* r r) 1000000))
         (r3 (round-quotient (* r r2) 1000000))
         (r5 (round-quotient (* r3 r2) 1000000))
         (r7 (round-quotient (* r5 r2) 1000000)))
    (+ (- r (round-quotient r3 6))
       (- (round-quotient r5 120)
          (round-quotient r7 5040)))))

(define (%cos-quarter r)
  (let* ((r2 (round-quotient (* r r) 1000000))
         (r4 (round-quotient (* r2 r2) 1000000))
         (r6 (round-quotient (* r4 r2) 1000000))
         (r8 (round-quotient (* r6 r2) 1000000)))
    (+ (- 1000000 (round-quotient r2 2))
       (- (round-quotient r4 24)
          (- (round-quotient r6 720)
             (round-quotient r8 40320))))))

(define (%sin-half-pi r)
  (cond
    ((< r 0) (- 0 (%sin-half-pi (- 0 r))))
    ((> r 785398) (%cos-quarter (- 1570796 r)))
    (else (%sin-quarter r))))

(define (%cos-half-pi r)
  (let ((ar (if (< r 0) (- 0 r) r)))
    (if (> ar 785398)
        (%sin-quarter (- 1570796 ar))
        (%cos-quarter ar))))

(define (%reduce-angle-pi8 v)
  (let* ((two-pi8 628318531)
         (v8 (* v 100))
         (k (round-quotient v8 two-pi8)))
    (- v8 (* k two-pi8))))

(define (sin z)
  (let ((v (%to-flonum-val z)))
    (cond
      ((or (eq? v 'nan) (eq? v 'pos-inf) (eq? v 'neg-inf)) +nan.0)
      ((= v 0) (if (exact? z) 0 (make-flonum-micros 0)))
      (else
       (let* ((pi8 314159265)
              (half-pi8 157079633)
              (r8 (%reduce-angle-pi8 v))
              (adj8 (cond
                      ((> r8 half-pi8) (- pi8 r8))
                      ((< r8 (- 0 half-pi8)) (- (- 0 pi8) r8))
                      (else r8)))
              (r (round-quotient adj8 100)))
         (make-flonum-micros (%sin-half-pi r)))))))

(define (cos z)
  (let ((v (%to-flonum-val z)))
    (cond
      ((or (eq? v 'nan) (eq? v 'pos-inf) (eq? v 'neg-inf)) +nan.0)
      ((= v 0) (if (exact? z) 1 (make-flonum-micros 1000000)))
      (else
       (let* ((pi8 314159265)
              (half-pi8 157079633)
              (r8-raw (%reduce-angle-pi8 v))
              (r8 (if (< r8-raw 0) (- 0 r8-raw) r8-raw)))
         (if (> r8 half-pi8)
             (let ((r (round-quotient (- pi8 r8) 100)))
               (make-flonum-micros (- 0 (%cos-half-pi r))))
             (let ((r (round-quotient r8 100)))
               (make-flonum-micros (%cos-half-pi r)))))))))

(define (tan z)
  (let ((v (%to-flonum-val z)))
    (cond
      ((or (eq? v 'nan) (eq? v 'pos-inf) (eq? v 'neg-inf)) +nan.0)
      ((= v 0) (if (exact? z) 0 (make-flonum-micros 0)))
      (else (flo/ (sin z) (cos z))))))

(define (%atan-unit u)
  ;; u in [0, 1000000]; apply half-angle reduction twice so u2 <= 198912
  (let* ((s1 (%micro-isqrt (+ 1000000000000 (* u u))))
         (u1 (round-quotient (* u 1000000) (+ 1000000 s1)))
         (s2 (%micro-isqrt (+ 1000000000000 (* u1 u1))))
         (u2 (round-quotient (* u1 1000000) (+ 1000000 s2)))
         (u2-sq (round-quotient (* u2 u2) 1000000))
         (u2-3 (round-quotient (* u2 u2-sq) 1000000))
         (u2-5 (round-quotient (* u2-3 u2-sq) 1000000))
         (u2-7 (round-quotient (* u2-5 u2-sq) 1000000))
         (at2 (+ (- u2 (round-quotient u2-3 3))
                 (- (round-quotient u2-5 5)
                    (round-quotient u2-7 7)))))
    (* 4 at2)))

(define (%atan-micros v)
  (cond
    ((= v 0) 0)
    ((< v 0) (- 0 (%atan-micros (- 0 v))))
    ((= v 1000000) 785398)
    ((> v 1000000)
     (- 1570796 (%atan-unit (round-quotient 1000000000000 v))))
    (else
     (%atan-unit v))))

(define atan
  (case-lambda
    ((z)
     (let ((v (%to-flonum-val z)))
       (cond
         ((eq? v 'nan) +nan.0)
         ((eq? v 'pos-inf) (make-flonum-micros 1570796))
         ((eq? v 'neg-inf) (make-flonum-micros -1570796))
         ((and (= v 0) (exact? z)) 0)
         (else (make-flonum-micros (%atan-micros v))))))
    ((y x)
     (let ((vy (%to-flonum-val y))
           (vx (%to-flonum-val x)))
       (cond
         ((or (eq? vy 'nan) (eq? vx 'nan)) +nan.0)
         ((= vx 0)
          (cond
            ((> vy 0) (make-flonum-micros 1570796))
            ((< vy 0) (make-flonum-micros -1570796))
            (else (make-flonum-micros 0))))
         ((> vx 0)
          (make-flonum-micros (%atan-micros (round-quotient (* vy 1000000) vx))))
         ((>= vy 0)
          (make-flonum-micros (+ (%atan-micros (round-quotient (* vy 1000000) vx)) 3141593)))
         (else
          (make-flonum-micros (- (%atan-micros (round-quotient (* vy 1000000) vx)) 3141593))))))))

(define (asin z)
  (let ((v (%to-flonum-val z)))
    (cond
      ((eq? v 'nan) +nan.0)
      ((and (= v 0) (exact? z)) 0)
      ((or (> v 1000000) (< v -1000000)) +nan.0)
      (else
       (let ((c (%micro-isqrt (- 1000000000000 (* v v)))))
         (atan (make-flonum-micros v) (make-flonum-micros c)))))))

(define (acos z)
  (let ((v (%to-flonum-val z)))
    (cond
      ((eq? v 'nan) +nan.0)
      ((and (= v 1000000) (exact? z)) 0)
      ((or (> v 1000000) (< v -1000000)) +nan.0)
      (else
       (let ((c (%micro-isqrt (- 1000000000000 (* v v)))))
         (atan (make-flonum-micros c) (make-flonum-micros v)))))))

;; §6.2.6 make-polar, magnitude, angle ((scheme complex), Issue #714)

(define (make-polar r theta)
  (cond
    ((and (fixnum? theta) (= theta 0)) r)
    ((and (fixnum? r) (= r 0)) 0)
    (else
     (make-rectangular (%real-num* r (cos theta))
                       (%real-num* r (sin theta))))))

(define (magnitude z)
  (cond
    ((fixnum? z) (if (< z 0) (- 0 z) z))
    ((ratnum? z)
     (let ((n (vector-ref z 1))
           (d (vector-ref z 2)))
       (make-rational (if (< n 0) (- 0 n) n) d)))
    ((flonum? z)
     (let ((v (vector-ref z 1)))
       (cond
         ((eq? v 'nan) +nan.0)
         ((or (eq? v 'pos-inf) (eq? v 'neg-inf)) +inf.0)
         ((< v 0) (make-flonum-micros (- 0 v)))
         (else z))))
    ((compnum? z)
     (let ((re (vector-ref z 1))
           (im (vector-ref z 2)))
       (cond
         ((or (infinite? re) (infinite? im)) +inf.0)
         ((or (nan? re) (nan? im)) +nan.0)
         (else
          (sqrt (%real-num+ (%real-num* re re) (%real-num* im im)))))))
    (else
     (error "magnitude: expected complex number" z))))

(define (angle z)
  (let ((re (real-part z))
        (im (imag-part z)))
    (if (and (%real-num= re 0) (%real-num= im 0))
        (error "angle: undefined for zero" z)
        (atan im re))))
