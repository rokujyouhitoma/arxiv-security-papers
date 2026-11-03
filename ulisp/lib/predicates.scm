;;; =======================================================================
;;; ULisp Standard Library: Standard Type Predicates (R7RS Section 6.2, 6.4)
;;; Conforms to DSN-33 Architecture Specification & Issue #532
;;; =======================================================================

;; §6.2.6 Numbers: Numerical predicates
;; In ULisp, all numbers are 62-bit exact signed fixnums.
(define (number? x)
  (fixnum? x))

(define (integer? x)
  (fixnum? x))

(define (exact? x)
  (fixnum? x))

(define (exact-integer? x)
  (fixnum? x))

(define (inexact? x)
  #f)

(define (real? x)
  (fixnum? x))

(define (rational? x)
  (fixnum? x))

(define (complex? x)
  (fixnum? x))

;; §6.4 Pairs and lists: list?
(define (list? x)
  (let loop ((cur x))
    (cond
      ((null? cur) #t)
      ((pair? cur) (loop (cdr cur)))
      (else #f))))
