;;; =======================================================================
;;; ULisp Standard Library: Standard Type Predicates (R7RS Section 6.2, 6.4)
;;; Conforms to DSN-33 Architecture Specification, Issue #532 & Issue #711
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §6.2 Boxed Numeric Tower Type Predicates (<ratnum>, <flonum>, <complex>)
;; ---------------------------------------------------------------------

(define (ratnum? x)
  (and (vector? x)
       (= (vector-length x) 3)
       (eq? (vector-ref x 0) 'ulisp-ratnum-tag)))

(define (flonum? x)
  (and (vector? x)
       (= (vector-length x) 2)
       (eq? (vector-ref x 0) 'ulisp-flonum-tag)))

(define (compnum? x)
  (and (vector? x)
       (= (vector-length x) 3)
       (eq? (vector-ref x 0) 'ulisp-complex-tag)))

;; ---------------------------------------------------------------------
;; §6.2.6 Numbers: Numerical Tower Predicates
;; ---------------------------------------------------------------------

(define (%number? x)
  (or (fixnum? x)
      (ratnum? x)
      (flonum? x)
      (compnum? x)))

(define (%complex? x)
  (%number? x))

(define (%real? x)
  (cond
    ((fixnum? x) #t)
    ((ratnum? x) #t)
    ((flonum? x) #t)
    ((compnum? x)
     (let ((im (vector-ref x 2)))
       (and (fixnum? im) (= im 0))))
    (else #f)))

(define (%rational? x)
  (cond
    ((fixnum? x) #t)
    ((ratnum? x) #t)
    ((flonum? x) (fixnum? (vector-ref x 1)))
    ((compnum? x)
     (let ((im (vector-ref x 2)))
       (and (fixnum? im) (= im 0) (%rational? (vector-ref x 1)))))
    (else #f)))

(define (%integer? x)
  (cond
    ((fixnum? x) #t)
    ((flonum? x)
     (let ((v (vector-ref x 1)))
       (and (fixnum? v) (= (modulo v 1000000) 0))))
    ((compnum? x)
     (let ((im (vector-ref x 2)))
       (and (fixnum? im) (= im 0) (%integer? (vector-ref x 1)))))
    (else #f)))

(define (%exact? x)
  (cond
    ((fixnum? x) #t)
    ((ratnum? x) #t)
    ((compnum? x)
     (and (%exact? (vector-ref x 1))
          (%exact? (vector-ref x 2))))
    (else #f)))

(define (%inexact? x)
  (cond
    ((fixnum? x) #f)
    ((flonum? x) #t)
    ((compnum? x)
     (or (%inexact? (vector-ref x 1))
         (%inexact? (vector-ref x 2))))
    (else #f)))

(define (exact-integer? x)
  (fixnum? x))

(define (number? x) (%number? x))
(define (complex? x) (%complex? x))
(define (real? x) (%real? x))
(define (rational? x) (%rational? x))
(define (integer? x) (%integer? x))
(define (exact? x) (%exact? x))
(define (inexact? x) (%inexact? x))

(define-syntax number?
  (syntax-rules ()
    ((_ x) (%number? x))))

(define-syntax complex?
  (syntax-rules ()
    ((_ x) (%complex? x))))

(define-syntax real?
  (syntax-rules ()
    ((_ x) (%real? x))))

(define-syntax rational?
  (syntax-rules ()
    ((_ x) (%rational? x))))

(define-syntax integer?
  (syntax-rules ()
    ((_ x) (%integer? x))))

(define-syntax exact?
  (syntax-rules ()
    ((_ x) (%exact? x))))

(define-syntax inexact?
  (syntax-rules ()
    ((_ x) (%inexact? x))))

;; §6.4 Pairs and lists: list?
(define (list? x)
  (let loop ((cur x))
    (cond
      ((null? cur) #t)
      ((pair? cur) (loop (cdr cur)))
      (else #f))))
