;;; =======================================================================
;;; ULisp Standard Library: SRFI 143 Fixnums特化高速演算ライブラリ
;;; Conforms to R7RS-large Tangerine Edition (scheme fixnum) & SRFI 143
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;;; §1. Fixnum Constants
(define %p58 (+ 288230376151711743 1))
(define %p60 (+ %p58 (+ %p58 (+ %p58 %p58))))

(define fx-width 62)
(define fx-greatest (+ %p60 (- %p60 1)))
(define fx-least (+ (- 0 %p60) (- 0 %p60)))

(define %fx-two-31 2147483648)
(define %fx-two-30 1073741824)
(define %fx-mask31 2147483647)

;;; §2. Predicates
(define fx=?
  (case-lambda
    ((a) #t)
    ((a b) (= a b))
    ((a b c) (and (= a b) (= b c)))
    ((a b c . rest)
     (and (= a b) (= b c)
          (let loop ((prev c) (lst rest))
            (if (null? lst)
                #t
                (if (= prev (car lst))
                    (loop (car lst) (cdr lst))
                    #f)))))))

(define fx<?
  (case-lambda
    ((a) #t)
    ((a b) (< a b))
    ((a b c) (and (< a b) (< b c)))
    ((a b c . rest)
     (and (< a b) (< b c)
          (let loop ((prev c) (lst rest))
            (if (null? lst)
                #t
                (if (< prev (car lst))
                    (loop (car lst) (cdr lst))
                    #f)))))))

(define fx>?
  (case-lambda
    ((a) #t)
    ((a b) (> a b))
    ((a b c) (and (> a b) (> b c)))
    ((a b c . rest)
     (and (> a b) (> b c)
          (let loop ((prev c) (lst rest))
            (if (null? lst)
                #t
                (if (> prev (car lst))
                    (loop (car lst) (cdr lst))
                    #f)))))))

(define fx<=?
  (case-lambda
    ((a) #t)
    ((a b) (<= a b))
    ((a b c) (and (<= a b) (<= b c)))
    ((a b c . rest)
     (and (<= a b) (<= b c)
          (let loop ((prev c) (lst rest))
            (if (null? lst)
                #t
                (if (<= prev (car lst))
                    (loop (car lst) (cdr lst))
                    #f)))))))

(define fx>=?
  (case-lambda
    ((a) #t)
    ((a b) (>= a b))
    ((a b c) (and (>= a b) (>= b c)))
    ((a b c . rest)
     (and (>= a b) (>= b c)
          (let loop ((prev c) (lst rest))
            (if (null? lst)
                #t
                (if (>= prev (car lst))
                    (loop (car lst) (cdr lst))
                    #f)))))))

(define (fxzero? i)
  (= i 0))

(define (fxpositive? i)
  (> i 0))

(define (fxnegative? i)
  (< i 0))

(define (fxodd? i)
  (= (bitwise-and i 1) 1))

(define (fxeven? i)
  (= (bitwise-and i 1) 0))

(define fxmax
  (case-lambda
    ((a) a)
    ((a b) (if (> a b) a b))
    ((a b c) (if (> a b) (if (> a c) a c) (if (> b c) b c)))
    ((a b c . rest)
     (let loop ((m (if (> a b) (if (> a c) a c) (if (> b c) b c))) (lst rest))
       (if (null? lst)
           m
           (loop (if (> (car lst) m) (car lst) m) (cdr lst)))))))

(define fxmin
  (case-lambda
    ((a) a)
    ((a b) (if (< a b) a b))
    ((a b c) (if (< a b) (if (< a c) a c) (if (< b c) b c)))
    ((a b c . rest)
     (let loop ((m (if (< a b) (if (< a c) a c) (if (< b c) b c))) (lst rest))
       (if (null? lst)
           m
           (loop (if (< (car lst) m) (car lst) m) (cdr lst)))))))

;;; §3. Basic Arithmetic
(define fx+
  (case-lambda
    (() 0)
    ((a) a)
    ((a b) (+ a b))
    ((a b . rest)
     (let loop ((acc (+ a b)) (lst rest))
       (if (null? lst)
           acc
           (loop (+ acc (car lst)) (cdr lst)))))))

(define fx-
  (case-lambda
    ((a) (- 0 a))
    ((a b) (- a b))
    ((a b . rest)
     (let loop ((acc (- a b)) (lst rest))
       (if (null? lst)
           acc
           (loop (- acc (car lst)) (cdr lst)))))))

(define (fxneg a)
  (- 0 a))

(define fx*
  (case-lambda
    (() 1)
    ((a) a)
    ((a b) (* a b))
    ((a b . rest)
     (let loop ((acc (* a b)) (lst rest))
       (if (null? lst)
           acc
           (loop (* acc (car lst)) (cdr lst)))))))

(define (fxquotient a b)
  (quotient a b))

(define (fxremainder a b)
  (remainder a b))

(define (fxabs a)
  (if (< a 0) (- 0 a) a))

(define (fxsquare a)
  (* a a))

(define (fxsqrt a)
  (if (< a 0)
      (error "fxsqrt: domain error, negative argument" a)
      (let loop ((x a))
        (let ((next (quotient (+ x (quotient a (if (= x 0) 1 x))) 2)))
          (if (>= next x)
              (if (> (* x x) a)
                  (- x 1)
                  x)
              (loop next))))))

;;; §4. Arithmetic with Carry
(define (%fx-add2 i j)
  (let ((s (+ i j)))
    (cond
      ((and (> i 0) (> j 0) (< s 0))
       (values s 1))
      ((and (< i 0) (< j 0) (>= s 0))
       (values s -1))
      (else
       (values s 0)))))

(define (fx+/carry i j k)
  (call-with-values
    (lambda () (%fx-add2 i j))
    (lambda (s1 c1)
      (call-with-values
        (lambda () (%fx-add2 s1 k))
        (lambda (s c2)
          (values s (+ c1 c2)))))))

(define (%fx-sub2 i j)
  (let ((d (- i j)))
    (cond
      ((and (< i 0) (> j 0) (>= d 0))
       (values d -1))
      ((and (> i 0) (< j 0) (< d 0))
       (values d 1))
      (else
       (values d 0)))))

(define (fx-/carry i j k)
  (call-with-values
    (lambda () (%fx-sub2 i j))
    (lambda (d1 b1)
      (call-with-values
        (lambda () (%fx-sub2 d1 k))
        (lambda (d b2)
          (values d (+ b1 b2)))))))

(define (%fx-split-abs x)
  (cond
    ((= x fx-least)
     (values 0 %fx-two-30))
    ((< x 0)
     (let ((ax (- 0 x)))
       (values (bitwise-and ax %fx-mask31)
               (quotient ax %fx-two-31))))
    (else
     (values (bitwise-and x %fx-mask31)
             (quotient x %fx-two-31)))))

(define (fx*/carry i j k)
  (let* ((neg? (if (< i 0) (not (< j 0)) (< j 0))))
    (call-with-values
      (lambda () (%fx-split-abs i))
      (lambda (a0 a1)
        (call-with-values
          (lambda () (%fx-split-abs j))
          (lambda (b0 b1)
            (let* ((p0 (* a0 b0))
                   (p1 (+ (* a1 b0) (* a0 b1)))
                   (p2 (* a1 b1))
                   (p0-low (bitwise-and p0 %fx-mask31))
                   (p0-high (quotient p0 %fx-two-31))
                   (p1-low (bitwise-and p1 %fx-mask31))
                   (p1-high (quotient p1 %fx-two-31))
                   (w0 p0-low)
                   (w1-raw (+ p0-high p1-low))
                   (c1 (quotient w1-raw %fx-two-31))
                   (w1 (bitwise-and w1-raw %fx-mask31))
                   (w2 (+ (+ p2 p1-high) c1)))
              (let*-values (((u-w0 u-w1 u-high)
                             (if neg?
                                 (if (and (= w0 0) (= w1 0))
                                     (values 0 0 (- 0 w2))
                                     (let* ((inv-w0 (- %fx-two-31 w0))
                                            (cw0 (bitwise-and inv-w0 %fx-mask31))
                                            (c-w0 (quotient inv-w0 %fx-two-31))
                                            (cw1 (+ (- %fx-mask31 w1) c-w0)))
                                       (values cw0 cw1 (- (- 0 w2) 1))))
                                 (values w0 w1 w2))))
                (let*-values (((signed-low signed-high)
                               (if (>= u-w1 %fx-two-30)
                                   (values (+ (* (- u-w1 %fx-two-31) %fx-two-31) u-w0)
                                           (+ u-high 1))
                                   (values (+ (* u-w1 %fx-two-31) u-w0)
                                           u-high))))
                  (call-with-values
                    (lambda () (fx+/carry signed-low 0 k))
                    (lambda (final-low carry-k)
                      (values final-low (+ signed-high carry-k)))))))))))))

;;; §5. Rounding Division
(define (fxtruncate-quotient i j)
  (quotient i j))

(define (fxtruncate-remainder i j)
  (remainder i j))

(define (fxtruncate/ i j)
  (values (quotient i j) (remainder i j)))

(define (fxfloor-quotient i j)
  (let ((q (quotient i j))
        (rem (remainder i j)))
    (if (and (not (= rem 0))
             (if (< i 0) (> j 0) (< j 0)))
        (- q 1)
        q)))

(define (fxfloor-remainder i j)
  (let ((rem (remainder i j)))
    (if (and (not (= rem 0))
             (if (< i 0) (> j 0) (< j 0)))
        (+ rem j)
        rem)))

(define (fxfloor/ i j)
  (values (fxfloor-quotient i j) (fxfloor-remainder i j)))

;;; §6. Bitwise Operations (Conforms to SRFI 151 bitwise semantics)
(define (fxnot i)
  (bitwise-not i))

(define fxand
  (case-lambda
    (() -1)
    ((i) i)
    ((i j) (bitwise-and i j))
    ((i j k . rest)
     (let loop ((acc (bitwise-and (bitwise-and i j) k)) (lst rest))
       (if (null? lst)
           acc
           (loop (bitwise-and acc (car lst)) (cdr lst)))))))

(define fxior
  (case-lambda
    (() 0)
    ((i) i)
    ((i j) (bitwise-ior i j))
    ((i j k . rest)
     (let loop ((acc (bitwise-ior (bitwise-ior i j) k)) (lst rest))
       (if (null? lst)
           acc
           (loop (bitwise-ior acc (car lst)) (cdr lst)))))))

(define fxxor
  (case-lambda
    (() 0)
    ((i) i)
    ((i j) (bitwise-xor i j))
    ((i j k . rest)
     (let loop ((acc (bitwise-xor (bitwise-xor i j) k)) (lst rest))
       (if (null? lst)
           acc
           (loop (bitwise-xor acc (car lst)) (cdr lst)))))))

(define (fxif mask i j)
  (bitwise-if mask i j))

(define (fxarithmetic-shift i count)
  (arithmetic-shift i count))

(define (fxarithmetic-shift-left i count)
  (if (< count 0)
      (error "fxarithmetic-shift-left: count must be non-negative" count)
      (arithmetic-shift i count)))

(define (fxarithmetic-shift-right i count)
  (if (< count 0)
      (error "fxarithmetic-shift-right: count must be non-negative" count)
      (arithmetic-shift i (- 0 count))))

(define (fxbit-count i)
  (bit-count i))

(define (fxlength i)
  (integer-length i))

(define (fxfirst-set-bit i)
  (first-set-bit i))

(define (fxbit-set? index i)
  (bit-set? index i))

(define (fxcopy-bit index i boolean)
  (copy-bit index i boolean))

(define (fxbit-field i start end)
  (bit-field i start end))

(define (fxbit-field-rotate i count start end)
  (bit-field-rotate i count start end))

(define (fxbit-field-reverse i start end)
  (bit-field-reverse i start end))
