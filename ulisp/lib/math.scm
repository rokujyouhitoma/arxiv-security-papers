;;; =======================================================================
;;; ULisp Standard Library: Elementary Integer Math (R7RS Section 6.2.6)
;;; Conforms to DSN-33 Architecture Specification & Issue #558
;;; Traceability: ulisp/docs/r7rs_specification_compliance.md
;;;
;;; Notes:
;;;   - `gcd` / `lcm` calls are desugared by Pass 030 into left-folded
;;;     chains of the binary kernels `gcd-2` / `lcm-2` (variadic support,
;;;     0 args -> 0 / 1, 1 arg -> |n|).
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
