;;; =======================================================================
;;; ULisp R7RS Numeric Tower Test Suite (Issues #711 - #715)
;;; Tests Exact Rationals (<ratnum>), Rounding (floor, ceiling, truncate,
;;; round), rationalize, and Numerical Tower Predicates
;;; =======================================================================

(define *pass-count* (cons 0 '()))
(define *fail-count* (cons 0 '()))

(define (assert-true msg cond-val)
  (if cond-val
      (set-car! *pass-count* (+ (car *pass-count*) 1))
      (begin
        (display "FAIL: ")
        (display msg)
        (newline)
        (set-car! *fail-count* (+ (car *fail-count*) 1)))))

(define (assert-equal msg expected actual)
  (if (equal? expected actual)
      (set-car! *pass-count* (+ (car *pass-count*) 1))
      (begin
        (display "FAIL: ")
        (display msg)
        (display " expected=")
        (write expected)
        (display " actual=")
        (write actual)
        (newline)
        (set-car! *fail-count* (+ (car *fail-count*) 1)))))

;; ---------------------------------------------------------------------
;; 1. Exact Rationals (<ratnum>) & Canonical GCD Reduction
;; ---------------------------------------------------------------------
(let ((r1 (make-rational 6 8))
      (r2 (make-rational -9 -12))
      (r3 (make-rational 6 -8))
      (r4 (make-rational 12 4))
      (r5 (make-rational 0 9)))
  (assert-true "6/8 is ratnum?" (ratnum? r1))
  (assert-equal "numerator 6/8 -> 3" 3 (numerator r1))
  (assert-equal "denominator 6/8 -> 4" 4 (denominator r1))
  (assert-true "eqv? 6/8 and -9/-12" (eqv? r1 r2))
  (assert-true "equal? 6/8 and -9/-12" (equal? r1 r2))
  (assert-equal "numerator 6/-8 -> -3" -3 (numerator r3))
  (assert-equal "denominator 6/-8 -> 4" 4 (denominator r3))
  (assert-true "12/4 demotes to fixnum 3" (and (fixnum? r4) (= r4 3)))
  (assert-equal "numerator of integer 3 -> 3" 3 (numerator r4))
  (assert-equal "denominator of integer 3 -> 1" 1 (denominator r4))
  (assert-true "0/9 demotes to fixnum 0" (and (fixnum? r5) (= r5 0)))
  (assert-equal "numerator 0 -> 0" 0 (numerator 0))
  (assert-equal "denominator 0 -> 1" 1 (denominator 0)))

;; ---------------------------------------------------------------------
;; 2. Numerical Tower Predicates on Exact Integers & Rationals
;; ---------------------------------------------------------------------
(let ((r (make-rational 3 4)))
  (assert-true "number? 3/4" (number? r))
  (assert-true "complex? 3/4" (complex? r))
  (assert-true "real? 3/4" (real? r))
  (assert-true "rational? 3/4" (rational? r))
  (assert-true "not integer? 3/4" (not (integer? r)))
  (assert-true "not exact-integer? 3/4" (not (exact-integer? r)))
  (assert-true "exact? 3/4" (exact? r))
  (assert-true "not inexact? 3/4" (not (inexact? r)))
  (assert-true "integer? 42" (integer? 42))
  (assert-true "rational? 42" (rational? 42)))

;; ---------------------------------------------------------------------
;; 3. Exact Rational Arithmetic & Comparisons
;; ---------------------------------------------------------------------
(let ((half (make-rational 1 2))
      (third (make-rational 1 3))
      (sixth (make-rational 1 6))
      (five-sixths (make-rational 5 6)))
  (assert-equal "1/2 + 1/3 = 5/6" five-sixths (rat+ half third))
  (assert-equal "1/2 - 1/3 = 1/6" sixth (rat- half third))
  (assert-equal "unary rat- 1/2 = -1/2" (make-rational -1 2) (rat- half))
  (assert-equal "1/2 * 1/3 = 1/6" sixth (rat* half third))
  (assert-equal "1/2 / 1/3 = 3/2" (make-rational 3 2) (rat/ half third))
  (assert-equal "unary rat/ 2/3 = 3/2" (make-rational 3 2) (rat/ (make-rational 2 3)))
  (assert-equal "1/2 + 1/2 = 1 (fixnum)" 1 (rat+ half half))
  (assert-true "rat= 2/4 1/2" (rat= (make-rational 2 4) half))
  (assert-true "rat< 1/3 1/2" (rat< third half))
  (assert-true "rat<= 1/3 1/2" (rat<= third half))
  (assert-true "rat> 1/2 1/3" (rat> half third))
  (assert-true "rat>= 1/2 1/2" (rat>= half half))
  (assert-equal "expt 2 -3 = 1/8" (make-rational 1 8) (expt 2 -3))
  (assert-equal "expt 2/3 3 = 8/27" (make-rational 8 27) (expt (make-rational 2 3) 3))
  (assert-equal "expt 2/3 -2 = 9/4" (make-rational 9 4) (expt (make-rational 2 3) -2)))

;; ---------------------------------------------------------------------
;; 4. R7RS Rounding Procedures: floor, ceiling, truncate, round (round-to-even)
;; ---------------------------------------------------------------------
(let ((pos-7-2 (make-rational 7 2))    ;; 3.5
      (pos-5-2 (make-rational 5 2))    ;; 2.5
      (pos-7-3 (make-rational 7 3))    ;; 2.333...
      (pos-8-3 (make-rational 8 3))    ;; 2.666...
      (neg-7-2 (make-rational -7 2))   ;; -3.5
      (neg-5-2 (make-rational -5 2))   ;; -2.5
      (neg-7-3 (make-rational -7 3))   ;; -2.333...
      (neg-8-3 (make-rational -8 3)))  ;; -2.666...
  ;; floor
  (assert-equal "floor 7/2 -> 3" 3 (floor pos-7-2))
  (assert-equal "floor -7/2 -> -4" -4 (floor neg-7-2))
  (assert-equal "floor 5 -> 5" 5 (floor 5))
  ;; ceiling
  (assert-equal "ceiling 7/2 -> 4" 4 (ceiling pos-7-2))
  (assert-equal "ceiling -7/2 -> -3" -3 (ceiling neg-7-2))
  (assert-equal "ceiling -5 -> -5" -5 (ceiling -5))
  ;; truncate
  (assert-equal "truncate 7/2 -> 3" 3 (truncate pos-7-2))
  (assert-equal "truncate -7/2 -> -3" -3 (truncate neg-7-2))
  (assert-equal "truncate 8/3 -> 2" 2 (truncate pos-8-3))
  (assert-equal "truncate -8/3 -> -2" -2 (truncate neg-8-3))
  ;; round (round-to-even per R7RS §6.2.6)
  (assert-equal "round 7/2 (3.5) -> 4 (even)" 4 (round pos-7-2))
  (assert-equal "round 5/2 (2.5) -> 2 (even)" 2 (round pos-5-2))
  (assert-equal "round -7/2 (-3.5) -> -4 (even)" -4 (round neg-7-2))
  (assert-equal "round -5/2 (-2.5) -> -2 (even)" -2 (round neg-5-2))
  (assert-equal "round 7/3 (2.33) -> 2" 2 (round pos-7-3))
  (assert-equal "round 8/3 (2.67) -> 3" 3 (round pos-8-3))
  (assert-equal "round -7/3 (-2.33) -> -2" -2 (round neg-7-3))
  (assert-equal "round -8/3 (-2.67) -> -3" -3 (round neg-8-3)))

;; ---------------------------------------------------------------------
;; 5. R7RS rationalize (Stern-Brocot / Continued Fraction Simplest Rational)
;; ---------------------------------------------------------------------
(assert-equal "rationalize 3/10 1/10 -> 1/3"
              (make-rational 1 3)
              (rationalize (make-rational 3 10) (make-rational 1 10)))
(assert-equal "rationalize -3/10 1/10 -> -1/3"
              (make-rational -1 3)
              (rationalize (make-rational -3 10) (make-rational 1 10)))
(assert-equal "rationalize 3/10 -1/10 -> 1/3"
              (make-rational 1 3)
              (rationalize (make-rational 3 10) (make-rational -1 10)))
(assert-equal "rationalize 1/4 1/2 -> 0 (contains 0)"
              0
              (rationalize (make-rational 1 4) (make-rational 1 2)))
(assert-equal "rationalize 5 2 -> 3"
              3
              (rationalize 5 2))
(assert-equal "rationalize 3/7 0 -> 3/7"
              (make-rational 3 7)
              (rationalize (make-rational 3 7) 0))

(display "Passed: ")
(display (car *pass-count*))
(display ", Failed: ")
(display (car *fail-count*))
(newline)
(if (> (car *fail-count*) 0)
    (exit 1)
    (exit 0))
