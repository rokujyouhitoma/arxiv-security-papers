;;; =======================================================================
;;; ULisp Standard Library: Comparators (SRFI 128, R7RS-large Red Edition)
;;; Conforms to DSN-33 Architecture Specification & Issue #701
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §1. Type Definition: <comparator> Record (SRFI 128)
;; ---------------------------------------------------------------------

(define-record-type <comparator>
  (%make-raw-comparator type-test equality ordering hash ordered? hashable?)
  comparator?
  (type-test comparator-type-test-predicate)
  (equality  comparator-equality-predicate)
  (ordering  comparator-ordering-predicate)
  (hash      comparator-hash-function)
  (ordered?  comparator-ordered?)
  (hashable? comparator-hashable?))

(define (make-comparator type-test equality ordering hash)
  (let* ((real-type-test
          (if (eq? type-test #t)
              (lambda (x) #t)
              type-test))
         (real-equality
          (if (eq? equality #t)
              (if (procedure? ordering)
                  (lambda (a b)
                    (and (not (ordering a b))
                         (not (ordering b a))))
                  (error "make-comparator: equality is #t but ordering is not a procedure" ordering))
              equality))
         (has-ordering (if ordering #t #f))
         (real-ordering
          (if ordering
              ordering
              (lambda (a b)
                (error "comparator-ordering-predicate: comparator does not support ordering" a b))))
         (has-hash (if hash #t #f))
         (real-hash
          (if hash
              hash
              (lambda (x)
                (error "comparator-hash-function: comparator does not support hashing" x)))))
    (%make-raw-comparator
     real-type-test
     real-equality
     real-ordering
     real-hash
     has-ordering
     has-hash)))

;; ---------------------------------------------------------------------
;; §2. Primitive Applicators & Invokers (SRFI 128)
;; ---------------------------------------------------------------------

(define (comparator-test-type comp obj)
  ((comparator-type-test-predicate comp) obj))

(define (comparator-check-type comp obj)
  (if (comparator-test-type comp obj)
      #t
      (error "comparator-check-type: object failed comparator type test" obj)))

(define (comparator-equal? comp a b)
  ((comparator-equality-predicate comp) a b))

(define (comparator-compare comp a b)
  (if (not (comparator-ordered? comp))
      (error "comparator-compare: comparator is not ordered" comp)
      (let ((ord (comparator-ordering-predicate comp))
            (eqp (comparator-equality-predicate comp)))
        (if (eqp a b)
            0
            (if (ord a b) -1 1)))))

(define (comparator-hash comp obj)
  (if (not (comparator-hashable? comp))
      (error "comparator-hash: comparator is not hashable" comp)
      ((comparator-hash-function comp) obj)))

;; ---------------------------------------------------------------------
;; §3. Standard Hash Functions & Hash Bounds (SRFI 128)
;; ---------------------------------------------------------------------

(define (hash-bound)
  %ht-hash-modulus)

(define (hash-salt)
  7199368)

(define (boolean-hash b)
  (if b 271 277))

(define (char-hash c)
  (modulo (+ 137 (* (char->integer c) 31)) %ht-hash-modulus))

(define (char-ci-hash c)
  (char-hash (char-downcase c)))

(define (default-hash obj)
  (hash obj %ht-hash-modulus))

;; ---------------------------------------------------------------------
;; §4. Standard Atomic Comparators (SRFI 128)
;; ---------------------------------------------------------------------

(define boolean-comparator
  (make-comparator
   (lambda (x) (boolean? x))
   boolean=?
   (lambda (a b) (and (not a) b))
   boolean-hash))

(define char-comparator
  (make-comparator
   (lambda (x) (char? x))
   (lambda (a b) (char=? a b))
   char<?
   char-hash))

(define char-ci-comparator
  (make-comparator
   (lambda (x) (char? x))
   char-ci=?
   char-ci<?
   char-ci-hash))

(define string-comparator
  (make-comparator
   (lambda (x) (string? x))
   string=?
   string<?
   (lambda (s) (string-hash s %ht-hash-modulus))))

(define string-ci-comparator
  (make-comparator
   (lambda (x) (string? x))
   string-ci=?
   string-ci<?
   (lambda (s) (string-ci-hash s %ht-hash-modulus))))

(define symbol-comparator
  (make-comparator
   (lambda (x) (symbol? x))
   symbol=?
   (lambda (a b) (string<? (symbol->string a) (symbol->string b)))
   (lambda (s) (symbol-hash s %ht-hash-modulus))))

(define exact-integer-comparator
  (make-comparator
   exact-integer?
   (lambda (a b) (= a b))
   (lambda (a b) (< a b))
   (lambda (n) (number-hash n %ht-hash-modulus))))

(define number-comparator
  (make-comparator
   number?
   (lambda (a b) (= a b))
   (lambda (a b) (< a b))
   (lambda (n) (number-hash n %ht-hash-modulus))))

;; ---------------------------------------------------------------------
;; §5. Composite Comparator Constructors (SRFI 128)
;; ---------------------------------------------------------------------

(define (make-pair-comparator car-comp cdr-comp)
  (make-comparator
   (lambda (x)
     (and (pair? x)
          (comparator-test-type car-comp (car x))
          (comparator-test-type cdr-comp (cdr x))))
   (lambda (a b)
     (and (comparator-equal? car-comp (car a) (car b))
          (comparator-equal? cdr-comp (cdr a) (cdr b))))
   (if (and (comparator-ordered? car-comp)
            (comparator-ordered? cdr-comp))
       (lambda (a b)
         (let ((ord-car (comparator-ordering-predicate car-comp)))
           (if (ord-car (car a) (car b))
               #t
               (if (ord-car (car b) (car a))
                   #f
                   ((comparator-ordering-predicate cdr-comp) (cdr a) (cdr b))))))
       #f)
   (if (and (comparator-hashable? car-comp)
            (comparator-hashable? cdr-comp))
       (lambda (x)
         (let ((h1 (comparator-hash car-comp (car x)))
               (h2 (comparator-hash cdr-comp (cdr x))))
           (modulo (+ (* (modulo h1 450000) 37) h2) %ht-hash-modulus)))
       #f)))

(define (make-list-comparator elem-comp type-test empty? head tail)
  (let* ((elem-ordered? (comparator-ordered? elem-comp))
         (elem-hashable? (comparator-hashable? elem-comp)))
    (make-comparator
     (lambda (obj)
       (and (type-test obj)
            (let loop ((cur obj))
              (cond
                ((empty? cur) #t)
                ((comparator-test-type elem-comp (head cur))
                 (loop (tail cur)))
                (else #f)))))
     (lambda (a b)
       (let loop ((x a) (y b))
         (cond
           ((and (empty? x) (empty? y)) #t)
           ((or (empty? x) (empty? y)) #f)
           ((comparator-equal? elem-comp (head x) (head y))
            (loop (tail x) (tail y)))
           (else #f))))
     (if elem-ordered?
         (lambda (a b)
           (let ((ord (comparator-ordering-predicate elem-comp)))
             (let loop ((x a) (y b))
               (cond
                 ((and (empty? x) (empty? y)) #f)
                 ((empty? x) #t)
                 ((empty? y) #f)
                 ((ord (head x) (head y)) #t)
                 ((ord (head y) (head x)) #f)
                 (else (loop (tail x) (tail y)))))))
         #f)
     (if elem-hashable?
         (lambda (obj)
           (let loop ((cur obj) (h 5381))
             (if (empty? cur)
                 (modulo h %ht-hash-modulus)
                 (let ((eh (comparator-hash elem-comp (head cur))))
                   (loop (tail cur)
                         (modulo (+ (* (modulo h 500000) 33) eh) %ht-hash-modulus))))))
         #f))))

(define (make-vector-comparator elem-comp type-test length-proc ref-proc)
  (let* ((elem-ordered? (comparator-ordered? elem-comp))
         (elem-hashable? (comparator-hashable? elem-comp)))
    (make-comparator
     (lambda (obj)
       (and (type-test obj)
            (let ((len (length-proc obj)))
              (let loop ((i 0))
                (cond
                  ((>= i len) #t)
                  ((comparator-test-type elem-comp (ref-proc obj i))
                   (loop (+ i 1)))
                  (else #f))))))
     (lambda (a b)
       (let ((la (length-proc a))
             (lb (length-proc b)))
         (and (= la lb)
              (let loop ((i 0))
                (cond
                  ((>= i la) #t)
                  ((comparator-equal? elem-comp (ref-proc a i) (ref-proc b i))
                   (loop (+ i 1)))
                  (else #f))))))
     (if elem-ordered?
         (lambda (a b)
           (let ((la (length-proc a))
                 (lb (length-proc b))
                 (ord (comparator-ordering-predicate elem-comp)))
             (cond
               ((< la lb) #t)
               ((> la lb) #f)
               (else
                (let loop ((i 0))
                  (cond
                    ((>= i la) #f)
                    ((ord (ref-proc a i) (ref-proc b i)) #t)
                    ((ord (ref-proc b i) (ref-proc a i)) #f)
                    (else (loop (+ i 1)))))))))
         #f)
     (if elem-hashable?
         (lambda (obj)
           (let ((len (length-proc obj)))
             (let loop ((i 0) (h (+ 521 len)))
               (if (>= i len)
                   (modulo h %ht-hash-modulus)
                   (let ((eh (comparator-hash elem-comp (ref-proc obj i))))
                     (loop (+ i 1)
                           (modulo (+ (* (modulo h 500000) 31) eh) %ht-hash-modulus)))))))
         #f))))

;; ---------------------------------------------------------------------
;; §6. Default Comparator & Custom Type Registry (SRFI 128)
;; ---------------------------------------------------------------------

(define *registered-comparators* (cons '() '()))

(define (comparator-register-default! comp)
  (if (not (comparator? comp))
      (error "comparator-register-default!: expected a comparator" comp)
      (set-car! *registered-comparators*
                (append (car *registered-comparators*) (list comp)))))

(define (%find-registered-comparator obj)
  (let loop ((ls (car *registered-comparators*)) (idx 0))
    (cond
      ((null? ls) #f)
      ((comparator-test-type (car ls) obj)
       (cons idx (car ls)))
      (else
       (loop (cdr ls) (+ idx 1))))))

;; Standard type rank order for SRFI 128 default comparator:
;; 0: empty list '()
;; 1: pair
;; 2: boolean
;; 3: char
;; 4: string
;; 5: symbol
;; 6: number
;; 7: vector
;; 8: bytevector
;; 9 + idx: registered custom comparators
;; 1000: fallback other objects
(define (%default-type-rank obj)
  (cond
    ((null? obj) 0)
    ((pair? obj) 1)
    ((boolean? obj) 2)
    ((char? obj) 3)
    ((string? obj) 4)
    ((symbol? obj) 5)
    ((number? obj) 6)
    ((vector? obj) 7)
    ((bytevector? obj) 8)
    (else
     (let ((reg (%find-registered-comparator obj)))
       (if reg
           (+ 9 (car reg))
           1000)))))

(define (%bytevector-less? a b)
  (let ((la (bytevector-length a))
        (lb (bytevector-length b)))
    (cond
      ((< la lb) #t)
      ((> la lb) #f)
      (else
       (let loop ((i 0))
         (if (>= i la)
             #f
             (let ((ba (bytevector-u8-ref a i))
                   (bb (bytevector-u8-ref b i)))
               (cond
                 ((< ba bb) #t)
                 ((> ba bb) #f)
                 (else (loop (+ i 1)))))))))))

(define (%default-equal? a b)
  (let ((ra (%default-type-rank a))
        (rb (%default-type-rank b)))
    (if (not (= ra rb))
        #f
        (cond
          ((= ra 0) #t)
          ((= ra 1)
           (and (%default-equal? (car a) (car b))
                (%default-equal? (cdr a) (cdr b))))
          ((= ra 2) (boolean=? a b))
          ((= ra 3) (char=? a b))
          ((= ra 4) (string=? a b))
          ((= ra 5) (symbol=? a b))
          ((= ra 6) (= a b))
          ((= ra 7)
           (let ((la (vector-length a))
                 (lb (vector-length b)))
             (and (= la lb)
                  (let loop ((i 0))
                    (cond
                      ((>= i la) #t)
                      ((%default-equal? (vector-ref a i) (vector-ref b i))
                       (loop (+ i 1)))
                      (else #f))))))
          ((= ra 8) (bytevector=? a b))
          ((< ra 1000)
           (let ((reg (%find-registered-comparator a)))
             (if reg
                 (comparator-equal? (cdr reg) a b)
                 (equal? a b))))
          (else (equal? a b))))))

(define (%default-less? a b)
  (let ((ra (%default-type-rank a))
        (rb (%default-type-rank b)))
    (cond
      ((< ra rb) #t)
      ((> ra rb) #f)
      ((= ra 0) #f)
      ((= ra 1)
       (if (%default-less? (car a) (car b))
           #t
           (if (%default-less? (car b) (car a))
               #f
               (%default-less? (cdr a) (cdr b)))))
      ((= ra 2) (and (not a) b))
      ((= ra 3) (char<? a b))
      ((= ra 4) (string<? a b))
      ((= ra 5) (string<? (symbol->string a) (symbol->string b)))
      ((= ra 6) (< a b))
      ((= ra 7)
       (let ((la (vector-length a))
             (lb (vector-length b)))
         (cond
           ((< la lb) #t)
           ((> la lb) #f)
           (else
            (let loop ((i 0))
              (cond
                ((>= i la) #f)
                ((%default-less? (vector-ref a i) (vector-ref b i)) #t)
                ((%default-less? (vector-ref b i) (vector-ref a i)) #f)
                (else (loop (+ i 1)))))))))
      ((= ra 8) (%bytevector-less? a b))
      ((< ra 1000)
       (let ((reg (%find-registered-comparator a)))
         (if (and reg (comparator-ordered? (cdr reg)))
             ((comparator-ordering-predicate (cdr reg)) a b)
             #f)))
      (else #f))))

(define (%default-hash-dispatch obj)
  (let ((r (%default-type-rank obj)))
    (if (and (>= r 9) (< r 1000))
        (let ((reg (%find-registered-comparator obj)))
          (if (and reg (comparator-hashable? (cdr reg)))
              (comparator-hash (cdr reg) obj)
              (default-hash obj)))
        (default-hash obj))))

(define (make-default-comparator)
  (make-comparator
   #t
   %default-equal?
   %default-less?
   %default-hash-dispatch))

(define default-comparator (make-default-comparator))

;; ---------------------------------------------------------------------
;; §7. Equivalence Comparator Constructors (SRFI 128)
;; ---------------------------------------------------------------------

(define (make-eq-comparator)
  (make-comparator
   #t
   (lambda (a b) (eq? a b))
   #f
   (lambda (x) (hash-by-identity x %ht-hash-modulus))))

(define (make-eqv-comparator)
  (make-comparator
   #t
   eqv?
   #f
   (lambda (x) (hash-by-identity x %ht-hash-modulus))))

(define (make-equal-comparator)
  (make-comparator
   #t
   equal?
   #f
   default-hash))

;; ---------------------------------------------------------------------
;; §8. Comparison Predicates & Conditional Syntax (SRFI 128)
;; ---------------------------------------------------------------------

(define (%compare-chain pred comp a b rest)
  (if (not (pred comp a b))
      #f
      (let loop ((prev b) (cur rest))
        (if (null? cur)
            #t
            (let ((next (car cur)))
              (if (pred comp prev next)
                  (loop next (cdr cur))
                  #f))))))

(define =?
  (case-lambda
    ((comp a b)
     (comparator-equal? comp a b))
    ((comp a b . rest)
     (%compare-chain comparator-equal? comp a b rest))))

(define <?
  (case-lambda
    ((comp a b)
     ((comparator-ordering-predicate comp) a b))
    ((comp a b . rest)
     (%compare-chain
      (lambda (c x y)
        ((comparator-ordering-predicate c) x y))
      comp a b rest))))

(define >?
  (case-lambda
    ((comp a b)
     ((comparator-ordering-predicate comp) b a))
    ((comp a b . rest)
     (%compare-chain
      (lambda (c x y)
        ((comparator-ordering-predicate c) y x))
      comp a b rest))))

(define <=?
  (case-lambda
    ((comp a b)
     (not ((comparator-ordering-predicate comp) b a)))
    ((comp a b . rest)
     (%compare-chain
      (lambda (c x y)
        (not ((comparator-ordering-predicate c) y x)))
      comp a b rest))))

(define >=?
  (case-lambda
    ((comp a b)
     (not ((comparator-ordering-predicate comp) a b)))
    ((comp a b . rest)
     (%compare-chain
      (lambda (c x y)
        (not ((comparator-ordering-predicate c) x y)))
      comp a b rest))))

(define-syntax comparator-if<=>
  (syntax-rules ()
    ((_ a b less equal greater)
     (comparator-if<=> default-comparator a b less equal greater))
    ((_ comp a b less equal greater)
     (let ((c (comparator-compare comp a b)))
       (cond
         ((< c 0) less)
         ((= c 0) equal)
         (else greater))))))
