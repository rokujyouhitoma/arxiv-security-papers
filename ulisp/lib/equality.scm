;;; =======================================================================
;;; ULisp Standard Library: Equivalence and Comparison Predicates (R7RS Section 6.1, 6.3, 6.5, 6.6)
;;; Conforms to DSN-33 Architecture Specification, Issue #532, #556 & Issue #561
;;; Traceability: ulisp/docs/r7rs_specification_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §6.1 Equivalence predicates: eqv?
;; ---------------------------------------------------------------------
(define (%eqv? a b)
  (cond
    ((eq? a b) #t)
    ((and (ratnum? a) (ratnum? b))
     (and (= (vector-ref a 1) (vector-ref b 1))
          (= (vector-ref a 2) (vector-ref b 2))))
    ((and (flonum? a) (flonum? b))
     (eq? (vector-ref a 1) (vector-ref b 1)))
    ((and (compnum? a) (compnum? b))
     (and (%eqv? (vector-ref a 1) (vector-ref b 1))
          (%eqv? (vector-ref a 2) (vector-ref b 2))))
    (else #f)))

(define (eqv? a b)
  (%eqv? a b))

(define-syntax eqv?
  (syntax-rules ()
    ((_ a b) (%eqv? a b))))

;; ---------------------------------------------------------------------
;; §6.1 Equivalence predicates: equal?
;; ---------------------------------------------------------------------
(define (equal? a b)
  (cond
    ((eq? a b) #t)
    ((and (%number? a) (%number? b)) (%eqv? a b))
    ((and (string? a) (string? b)) (string=? a b))
    ((and (char? a) (char? b)) (char=? a b))
    ((and (bytevector? a) (bytevector? b)) (bytevector=? a b))
    ((and (vector? a) (vector? b))
     (let ((len-a (vector-length a))
           (len-b (vector-length b)))
       (if (= len-a len-b)
           (let loop ((i 0))
             (if (= i len-a)
                 #t
                 (if (equal? (vector-ref a i) (vector-ref b i))
                     (loop (+ i 1))
                     #f)))
           #f)))
    ((and (pair? a) (pair? b))
     (and (equal? (car a) (car b))
          (equal? (cdr a) (cdr b))))
    (else #f)))

;; ---------------------------------------------------------------------
;; §6.3 Booleans: boolean=?
;; ---------------------------------------------------------------------
(define (boolean=? a b)
  (if (boolean? a)
      (if (boolean? b)
          (eq? a b)
          #f)
      #f))

;; ---------------------------------------------------------------------
;; §6.5 Symbols: symbol=?
;; ---------------------------------------------------------------------
(define (symbol=? a b)
  (if (symbol? a)
      (if (symbol? b)
          (eq? a b)
          #f)
      #f))

;; ---------------------------------------------------------------------
;; §6.6 Characters: char<?, char>?, char<=?, char>=?
;; ---------------------------------------------------------------------
(define (char<? a b)
  (< (char->integer a) (char->integer b)))

(define (char>? a b)
  (> (char->integer a) (char->integer b)))

(define (char<=? a b)
  (<= (char->integer a) (char->integer b)))

(define (char>=? a b)
  (>= (char->integer a) (char->integer b)))


