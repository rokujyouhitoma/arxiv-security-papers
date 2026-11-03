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
;; §6.2.6 expt (exact integer exponent, binary exponentiation O(log n))
;;   z2 = 0  -> 1 (including 0^0 = 1 per R7RS)
;;   z2 < 0  -> exact results only for |z1| = 1; 0^(-k) is an error;
;;              other bases return 0 (no rationals in ULisp fixnum tower).
;; ---------------------------------------------------------------------
(define (expt z1 z2)
  (if (< z2 0)
      (if (= z1 1)
          1
          (if (= z1 -1)
              (if (= (remainder z2 2) 0) 1 -1)
              (if (= z1 0)
                  (error "expt: zero base with negative exponent" z2)
                  0)))
      (let loop ((b z1) (e z2) (acc 1))
        (if (= e 0)
            acc
            (loop (* b b)
                  (quotient e 2)
                  (if (= (remainder e 2) 0) acc (* acc b)))))))

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
