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

;; ---------------------------------------------------------------------
;; 6. Inexact Flonums (<flonum>), Exactness Conversions & IEEE Predicates (Issue #712)
;; ---------------------------------------------------------------------
(let ((f-three (inexact 3))
      (f-half (inexact (make-rational 1 2)))
      (f-3-5 (make-flonum 3 500000))
      (f-neg-2-5 (make-flonum -2 -500000)))
  (assert-true "flonum? (inexact 3)" (flonum? f-three))
  (assert-true "number? f-three" (number? f-three))
  (assert-true "complex? f-three" (complex? f-three))
  (assert-true "real? f-three" (real? f-three))
  (assert-true "rational? f-three" (rational? f-three))
  (assert-true "integer? (inexact 3)" (integer? f-three))
  (assert-true "not exact-integer? (inexact 3)" (not (exact-integer? f-three)))
  (assert-true "not integer? 0.5" (not (integer? f-half)))
  (assert-true "inexact? f-three" (inexact? f-three))
  (assert-true "not exact? f-three" (not (exact? f-three)))
  ;; eqv? and equal? distinguish exact vs inexact per R7RS §6.1
  (assert-true "not eqv? 3 (inexact 3)" (not (eqv? 3 f-three)))
  (assert-true "not equal? 3 (inexact 3)" (not (equal? 3 f-three)))
  (assert-true "eqv? (inexact 3) (inexact 3)" (eqv? f-three (inexact 3)))
  ;; exact conversion
  (assert-equal "exact (inexact 3) -> 3 (fixnum)" 3 (exact f-three))
  (assert-true "fixnum? (exact (inexact 3))" (fixnum? (exact f-three)))
  (assert-equal "exact 0.5 -> 1/2 (<ratnum>)" (make-rational 1 2) (exact f-half))
  (assert-equal "exact 3.5 -> 7/2 (<ratnum>)" (make-rational 7 2) (exact f-3-5))
  (assert-equal "inexact->exact alias" (make-rational 7 2) (inexact->exact f-3-5))
  (assert-equal "exact->inexact alias" f-3-5 (exact->inexact (make-rational 7 2)))
  ;; IEEE 754 Special Value Predicates: finite?, infinite?, nan?
  (assert-true "finite? 42" (finite? 42))
  (assert-true "finite? 3/4" (finite? (make-rational 3 4)))
  (assert-true "finite? 3.5" (finite? f-3-5))
  (assert-true "not finite? +inf.0" (not (finite? +inf.0)))
  (assert-true "not finite? -inf.0" (not (finite? -inf.0)))
  (assert-true "not finite? +nan.0" (not (finite? +nan.0)))
  (assert-true "infinite? +inf.0" (infinite? +inf.0))
  (assert-true "infinite? -inf.0" (infinite? -inf.0))
  (assert-true "not infinite? 3.5" (not (infinite? f-3-5)))
  (assert-true "not infinite? +nan.0" (not (infinite? +nan.0)))
  (assert-true "nan? +nan.0" (nan? +nan.0))
  (assert-true "nan? -nan.0" (nan? -nan.0))
  (assert-true "not nan? +inf.0" (not (nan? +inf.0)))
  (assert-true "not nan? 42" (not (nan? 42)))
  (assert-true "not rational? +inf.0" (not (rational? +inf.0)))
  (assert-true "not rational? +nan.0" (not (rational? +nan.0)))
  ;; Inexactness contagion in num+, num-, num*, num/, num=
  (assert-true "inexact? (num+ 1 0.5)" (inexact? (num+ 1 f-half)))
  (assert-equal "exact (num+ 1 0.5) -> 3/2" (make-rational 3 2) (exact (num+ 1 f-half)))
  (assert-equal "exact (num* 3.5 2) -> 7" 7 (exact (num* f-3-5 2)))
  (assert-equal "exact (num/ 3.5 0.5) -> 7" 7 (exact (num/ f-3-5 f-half)))
  (assert-true "num= 3 (inexact 3)" (num= 3 f-three))
  (assert-true "num= 1/2 0.5" (num= (make-rational 1 2) f-half))
  (assert-true "not flo= +nan.0 +nan.0" (not (flo= +nan.0 +nan.0)))
  (assert-true "flo< -inf.0 3.5" (flo< -inf.0 f-3-5))
  (assert-true "flo< 3.5 +inf.0" (flo< f-3-5 +inf.0))
  ;; Rounding on inexact flonum preserves inexactness
  (assert-true "inexact? (floor 3.5)" (inexact? (floor f-3-5)))
  (assert-equal "exact (floor 3.5) -> 3" 3 (exact (floor f-3-5)))
  (assert-equal "exact (ceiling 3.5) -> 4" 4 (exact (ceiling f-3-5)))
  (assert-equal "exact (round 3.5) -> 4 (even)" 4 (exact (round f-3-5)))
  (assert-equal "exact (round -2.5) -> -2 (even)" -2 (exact (round f-neg-2-5)))
  (assert-equal "exact (numerator 3.5) -> 7" 7 (exact (numerator f-3-5)))
  (assert-equal "exact (denominator 3.5) -> 2" 2 (exact (denominator f-3-5))))

;; ---------------------------------------------------------------------
;; 7. (scheme inexact) Transcendental Functions & sqrt (Issue #713)
;; ---------------------------------------------------------------------
(define (assert-approx msg expected-micros actual-flonum tol)
  (let* ((v (if (flonum? actual-flonum)
                (vector-ref actual-flonum 1)
                (* actual-flonum 1000000)))
         (diff (let ((d (- v expected-micros))) (if (< d 0) (- 0 d) d))))
    (assert-true msg (<= diff tol))))

;; sqrt
(assert-equal "sqrt 0 -> 0" 0 (sqrt 0))
(assert-equal "sqrt 9 -> 3 (exact)" 3 (sqrt 9))
(assert-equal "sqrt 144 -> 12 (exact)" 12 (sqrt 144))
(assert-equal "sqrt 9/16 -> 3/4 (exact)" (make-rational 3 4) (sqrt (make-rational 9 16)))
(assert-approx "sqrt 2 -> 1.414214" 1414214 (sqrt 2) 2)
(assert-approx "sqrt 2.25 -> 1.5" 1500000 (sqrt (make-flonum 2 250000)) 2)
(assert-true "sqrt -4 is complex" (compnum? (sqrt -4)))

;; exp and log
(assert-equal "exp 0 -> 1 (exact)" 1 (exp 0))
(assert-approx "exp 1.0 -> 2.718282" 2718282 (exp (inexact 1)) 5)
(assert-approx "exp -1.0 -> 0.367879" 367879 (exp (inexact -1)) 5)
(assert-equal "log 1 -> 0 (exact)" 0 (log 1))
(assert-approx "log(e) -> 1.0" 1000000 (log (exp (inexact 1))) 5)
(assert-approx "log 2.0 -> 0.693147" 693147 (log (inexact 2)) 5)
(assert-approx "log 8 2 -> 3.0" 3000000 (log 8 2) 5)
(assert-approx "log 100 10 -> 2.0" 2000000 (log 100 10) 5)

;; sin, cos, tan
(assert-equal "sin 0 -> 0 (exact)" 0 (sin 0))
(assert-equal "cos 0 -> 1 (exact)" 1 (cos 0))
(assert-equal "tan 0 -> 0 (exact)" 0 (tan 0))
(let ((pi-fl (make-flonum-micros 3141593))
      (half-pi (make-flonum-micros 1570796))
      (quarter-pi (make-flonum-micros 785398)))
  (assert-approx "sin(pi/2) -> 1.0" 1000000 (sin half-pi) 5)
  (assert-approx "cos(pi/2) -> 0.0" 0 (cos half-pi) 5)
  (assert-approx "sin(pi) -> 0.0" 0 (sin pi-fl) 5)
  (assert-approx "cos(pi) -> -1.0" -1000000 (cos pi-fl) 5)
  (assert-approx "tan(pi/4) -> 1.0" 1000000 (tan quarter-pi) 5)
  ;;sin^2(x) + cos^2(x) = 1
  (let* ((s (sin (inexact 1)))
         (c (cos (inexact 1)))
         (sum (flo+ (flo* s s) (flo* c c))))
    (assert-approx "sin^2(1) + cos^2(1) = 1.0" 1000000 sum 5)))

;; atan (1 and 2 args), asin, acos
(assert-equal "atan 0 -> 0 (exact)" 0 (atan 0))
(assert-approx "atan 1.0 -> pi/4 (785398)" 785398 (atan (inexact 1)) 5)
(assert-approx "atan -1.0 -> -pi/4 (-785398)" -785398 (atan (inexact -1)) 5)
(assert-approx "atan2(1, 1) -> pi/4" 785398 (atan 1 1) 5)
(assert-approx "atan2(1, -1) -> 3*pi/4 (2356195)" 2356195 (atan 1 -1) 5)
(assert-approx "atan2(-1, -1) -> -3*pi/4 (-2356195)" -2356195 (atan -1 -1) 5)
(assert-approx "atan2(1, 0) -> pi/2 (1570796)" 1570796 (atan 1 0) 5)
(assert-equal "asin 0 -> 0 (exact)" 0 (asin 0))
(assert-approx "asin 0.5 -> pi/6 (523599)" 523599 (asin (make-flonum 0 500000)) 5)
(assert-approx "asin 1.0 -> pi/2 (1570796)" 1570796 (asin (inexact 1)) 5)
(assert-equal "acos 1 -> 0 (exact)" 0 (acos 1))
(assert-approx "acos 0.5 -> pi/3 (1047198)" 1047198 (acos (make-flonum 0 500000)) 5)
(assert-approx "acos 0.0 -> pi/2 (1570796)" 1570796 (acos (inexact 0)) 5)

;; ---------------------------------------------------------------------
;; 8. (scheme complex) Complex Arithmetic Library (Issue #714)
;; ---------------------------------------------------------------------
(let ((z1 (make-rectangular 3 4))
      (z2 (make-rectangular 1 -2))
      (z-real (make-rectangular 7 0))
      (z-inex (make-rectangular (inexact 3) (inexact 4))))
  (assert-true "compnum? 3+4i" (compnum? z1))
  (assert-true "number? 3+4i" (number? z1))
  (assert-true "complex? 3+4i" (complex? z1))
  (assert-true "not real? 3+4i" (not (real? z1)))
  (assert-true "not rational? 3+4i" (not (rational? z1)))
  (assert-true "not integer? 3+4i" (not (integer? z1)))
  (assert-true "exact? 3+4i" (exact? z1))
  (assert-true "not inexact? 3+4i" (not (inexact? z1)))
  (assert-true "inexact? 3.0+4.0i" (inexact? z-inex))
  (assert-true "make-rectangular 7 0 demotes to fixnum 7" (and (fixnum? z-real) (= z-real 7)))
  ;; real-part and imag-part
  (assert-equal "real-part 3+4i -> 3" 3 (real-part z1))
  (assert-equal "imag-part 3+4i -> 4" 4 (imag-part z1))
  (assert-equal "real-part 42 -> 42" 42 (real-part 42))
  (assert-equal "imag-part 42 -> 0" 0 (imag-part 42))
  ;; magnitude and angle
  (assert-equal "magnitude 3+4i -> 5 (exact)" 5 (magnitude z1))
  (assert-equal "magnitude -5 -> 5" 5 (magnitude -5))
  (assert-equal "magnitude -3/4 -> 3/4" (make-rational 3 4) (magnitude (make-rational -3 4)))
  (assert-approx "angle 1+1i -> pi/4 (785398)" 785398 (angle (make-rectangular 1 1)) 5)
  (assert-approx "angle 0+2i -> pi/2 (1570796)" 1570796 (angle (make-rectangular 0 2)) 5)
  ;; make-polar
  (assert-equal "make-polar 5 0 -> 5 (exact)" 5 (make-polar 5 0))
  (let ((zp (make-polar 2 (make-flonum-micros 1570796))))
    (assert-approx "real-part (make-polar 2 pi/2) -> 0.0" 0 (real-part zp) 5)
    (assert-approx "imag-part (make-polar 2 pi/2) -> 2.0" 2000000 (imag-part zp) 5))
  ;; complex arithmetic: +, -, *, /, =
  (assert-equal "(3+4i) + (1-2i) = 4+2i" (make-rectangular 4 2) (num+ z1 z2))
  (assert-equal "(3+4i) - (1-2i) = 2+6i" (make-rectangular 2 6) (num- z1 z2))
  (assert-equal "-(3+4i) = -3-4i" (make-rectangular -3 -4) (num- z1))
  (assert-equal "(3+4i) * (1-2i) = 11-2i" (make-rectangular 11 -2) (num* z1 z2))
  (assert-equal "(3+4i) * (3-4i) = 25 (demoted to fixnum)" 25 (num* z1 (make-rectangular 3 -4)))
  (assert-equal "(11-2i) / (1-2i) = 3+4i" z1 (num/ (make-rectangular 11 -2) z2))
  (assert-true "num= (3+4i) (3.0+4.0i)" (num= z1 z-inex))
  (assert-true "not eqv? (3+4i) (3.0+4.0i)" (not (eqv? z1 z-inex)))
  (assert-equal "exact (3.0+4.0i) -> 3+4i" z1 (exact z-inex))
  (assert-equal "inexact (3+4i) -> 3.0+4.0i" z-inex (inexact z1)))

;; ---------------------------------------------------------------------
;; 9. Numeric Tower Reader/Printer & Radix Formatting (Issue #715)
;; ---------------------------------------------------------------------
;; number->string radix formatting (2, 8, 10, 16)
(assert-equal "number->string 42 -> 42" "42" (number->string 42))
(assert-equal "number->string 42 2 -> 101010" "101010" (number->string 42 2))
(assert-equal "number->string 42 8 -> 52" "52" (number->string 42 8))
(assert-equal "number->string 42 10 -> 42" "42" (number->string 42 10))
(assert-equal "number->string 255 16 -> ff" "ff" (number->string 255 16))
(assert-equal "number->string -255 16 -> -ff" "-ff" (number->string -255 16))

;; number->string on <ratnum>, <flonum>, <compnum>
(assert-equal "number->string 3/4 -> 3/4" "3/4" (number->string (make-rational 3 4)))
(assert-equal "number->string -3/4 -> -3/4" "-3/4" (number->string (make-rational -3 4)))
(assert-equal "number->string 10/16 16 -> 5/8" "5/8" (number->string (make-rational 10 16) 16))
(assert-equal "number->string 3.5 -> 3.5" "3.5" (number->string (make-flonum 3 500000)))
(assert-equal "number->string 0.0 -> 0.0" "0.0" (number->string (inexact 0)))
(assert-equal "number->string -1.25 -> -1.25" "-1.25" (number->string (make-flonum-micros -1250000)))
(assert-equal "number->string +inf.0 -> +inf.0" "+inf.0" (number->string +inf.0))
(assert-equal "number->string -inf.0 -> -inf.0" "-inf.0" (number->string -inf.0))
(assert-equal "number->string +nan.0 -> +nan.0" "+nan.0" (number->string +nan.0))
(assert-equal "number->string 3+4i -> 3+4i" "3+4i" (number->string (make-rectangular 3 4)))
(assert-equal "number->string 3-4i -> 3-4i" "3-4i" (number->string (make-rectangular 3 -4)))
(assert-equal "number->string 0+1i -> 0+1i" "0+1i" (number->string (make-rectangular 0 1)))

;; string->number on prefixes (#e, #i, #b, #o, #d, #x), rationals, decimals, exponents, inf/nan, complex
(assert-equal "string->number 3/4" (make-rational 3 4) (string->number "3/4"))
(assert-equal "string->number -6/8 -> -3/4" (make-rational -3 4) (string->number "-6/8"))
(assert-true "string->number 1/0 -> #f" (not (string->number "1/0")))
(assert-equal "string->number 3.5 -> flonum 3.5" (make-flonum 3 500000) (string->number "3.5"))
(assert-equal "string->number -0.25 -> flonum -0.25" (make-flonum-micros -250000) (string->number "-0.25"))
(assert-equal "string->number .5 -> flonum 0.5" (make-flonum 0 500000) (string->number ".5"))
(assert-equal "string->number 1.5e2 -> flonum 150.0" (inexact 150) (string->number "1.5e2"))
(assert-equal "string->number #e0.5 -> exact 1/2" (make-rational 1 2) (string->number "#e0.5"))
(assert-equal "string->number #e1.25 -> exact 5/4" (make-rational 5 4) (string->number "#e1.25"))
(assert-equal "string->number #i3/4 -> flonum 0.75" (make-flonum 0 750000) (string->number "#i3/4"))
(assert-equal "string->number #i#x10 -> flonum 16.0" (inexact 16) (string->number "#i#x10"))
(assert-equal "string->number #x#e10/20 -> exact 1/2" (make-rational 1 2) (string->number "#x#e10/20"))
(assert-equal "string->number +inf.0" +inf.0 (string->number "+inf.0"))
(assert-equal "string->number -inf.0" -inf.0 (string->number "-inf.0"))
(assert-true "string->number +nan.0 is nan?" (nan? (string->number "+nan.0")))
(assert-equal "string->number 3+4i" (make-rectangular 3 4) (string->number "3+4i"))
(assert-equal "string->number 3-4i" (make-rectangular 3 -4) (string->number "3-4i"))
(assert-equal "string->number +i -> 0+1i" (make-rectangular 0 1) (string->number "+i"))
(assert-equal "string->number -i -> 0-1i" (make-rectangular 0 -1) (string->number "-i"))
(assert-equal "string->number 3+i -> 3+1i" (make-rectangular 3 1) (string->number "3+i"))
(assert-equal "string->number 1/2-3/4i" (make-rectangular (make-rational 1 2) (make-rational -3 4)) (string->number "1/2-3/4i"))
(assert-equal "string->number 5@0 -> 5" 5 (string->number "5@0"))

;; read and write/display round-trip via string ports
(let ((p (open-input-string "3/4 3.5 +inf.0 3+4i #e0.25 #i1/2")))
  (assert-equal "read 3/4" (make-rational 3 4) (read p))
  (assert-equal "read 3.5" (make-flonum 3 500000) (read p))
  (assert-equal "read +inf.0" +inf.0 (read p))
  (assert-equal "read 3+4i" (make-rectangular 3 4) (read p))
  (assert-equal "read #e0.25 -> 1/4" (make-rational 1 4) (read p))
  (assert-equal "read #i1/2 -> 0.5" (make-flonum 0 500000) (read p)))

(let ((out (open-output-string)))
  (write (make-rational 3 4) out)
  (write-char #\space out)
  (write (make-flonum 3 500000) out)
  (write-char #\space out)
  (write (make-rectangular 3 -4) out)
  (write-char #\space out)
  (write +inf.0 out)
  (assert-equal "write numeric tower values" "3/4 3.5 3-4i +inf.0" (get-output-string out)))

(display "Passed: ")
(display (car *pass-count*))
(display ", Failed: ")
(display (car *fail-count*))
(newline)
(if (> (car *fail-count*) 0)
    (exit 1)
    (exit 0))
