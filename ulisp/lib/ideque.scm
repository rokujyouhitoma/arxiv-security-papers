;;; =======================================================================
;;; ULisp Standard Library: Immutable Deques — R7RS-large Red Edition / SRFI 134
;;; Specification: (scheme ideque) / (srfi 134)
;;; Conforms to DSN-33 Architecture Specification & Issue #710
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 134 Core Immutable Deque Type: #(ulisp-ideque-tag <elements>)
;; ---------------------------------------------------------------------

(define (%make-ideque lst)
  (let ((v (make-vector 2 #f)))
    (vector-set! v 0 'ulisp-ideque-tag)
    (vector-set! v 1 lst)
    v))

(define (ideque? obj)
  (and (vector? obj)
       (= (vector-length obj) 2)
       (eq? (vector-ref obj 0) 'ulisp-ideque-tag)))

(define (%dq-list dq)
  (vector-ref dq 1))

(define (%dq-copy-list lst)
  (let loop ((cur lst) (acc '()))
    (if (null? cur)
        (reverse acc)
        (loop (cdr cur) (cons (car cur) acc)))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 134 Constructors & Conversions
;; ---------------------------------------------------------------------

(define ideque
  (case-lambda
    (() (%make-ideque '()))
    ((a . rest)
     (%make-ideque (cons a (%dq-copy-list rest))))))

(define (list->ideque lst)
  (%make-ideque (%dq-copy-list lst)))

(define (ideque->list dq)
  (%dq-copy-list (%dq-list dq)))

(define (ideque-tabulate n proc)
  (let loop ((i 0) (acc '()))
    (if (>= i n)
        (%make-ideque (reverse acc))
        (loop (+ i 1) (cons (proc i) acc)))))

(define (ideque-unfold p f g seed)
  (let loop ((s seed) (acc '()))
    (if (p s)
        (%make-ideque (reverse acc))
        (loop (g s) (cons (f s) acc)))))

(define (ideque-unfold-right p f g seed)
  (let loop ((s seed) (acc '()))
    (if (p s)
        (%make-ideque acc)
        (loop (g s) (cons (f s) acc)))))

(define (%dq-make-cell a b) (cons a b))
(define (%dq-set-car! c v) (set-car! c v))

(define (ideque->generator dq)
  (let ((cell (%dq-make-cell (%dq-list dq) '())))
    (lambda ()
      (let ((cur (car cell)))
        (if (null? cur)
            (eof-object)
            (begin
              (%dq-set-car! cell (cdr cur))
              (car cur)))))))

(define generator->ideque
  (case-lambda
    ((gen)
     (let loop ((acc '()))
       (let ((v (gen)))
         (if (eof-object? v)
             (%make-ideque (reverse acc))
             (loop (cons v acc))))))
    ((gen n)
     (let loop ((i 0) (acc '()))
       (if (>= i n)
           (%make-ideque (reverse acc))
           (let ((v (gen)))
             (if (eof-object? v)
                 (%make-ideque (reverse acc))
                 (loop (+ i 1) (cons v acc)))))))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 134 Predicates
;; ---------------------------------------------------------------------

(define (ideque-empty? dq)
  (null? (%dq-list dq)))

(define (%ideque=-2 elt= dq1 dq2)
  (let loop ((a (%dq-list dq1)) (b (%dq-list dq2)))
    (cond
      ((and (null? a) (null? b)) #t)
      ((or (null? a) (null? b)) #f)
      ((elt= (car a) (car b)) (loop (cdr a) (cdr b)))
      (else #f))))

(define ideque=
  (case-lambda
    ((elt=) #t)
    ((elt= dq1) #t)
    ((elt= dq1 dq2) (%ideque=-2 elt= dq1 dq2))
    ((elt= dq1 dq2 . rest)
     (if (%ideque=-2 elt= dq1 dq2)
         (let loop ((prev dq2) (more rest))
           (if (null? more)
               #t
               (if (%ideque=-2 elt= prev (car more))
                   (loop (car more) (cdr more))
                   #f)))
         #f))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 134 Queue Operations
;; ---------------------------------------------------------------------

(define (ideque-front dq)
  (let ((xs (%dq-list dq)))
    (if (null? xs)
        (error "ideque-front: empty ideque")
        (car xs))))

(define (ideque-back dq)
  (let ((xs (%dq-list dq)))
    (if (null? xs)
        (error "ideque-back: empty ideque")
        (let loop ((cur xs))
          (if (null? (cdr cur))
              (car cur)
              (loop (cdr cur)))))))

(define (ideque-remove-front dq)
  (let ((xs (%dq-list dq)))
    (if (null? xs)
        (error "ideque-remove-front: empty ideque")
        (%make-ideque (cdr xs)))))

(define (ideque-remove-back dq)
  (let ((xs (%dq-list dq)))
    (if (null? xs)
        (error "ideque-remove-back: empty ideque")
        (%make-ideque (reverse (cdr (reverse xs)))))))

(define (ideque-add-front dq obj)
  (%make-ideque (cons obj (%dq-list dq))))

(define (ideque-add-back dq obj)
  (%make-ideque (append (%dq-list dq) (list obj))))

(define (ideque-ref dq n)
  (list-ref (%dq-list dq) n))

(define (%dq-take-list xs n)
  (let loop ((cur xs) (k n) (acc '()))
    (if (<= k 0)
        (reverse acc)
        (loop (cdr cur) (- k 1) (cons (car cur) acc)))))

(define (%dq-drop-list xs n)
  (let loop ((cur xs) (k n))
    (if (<= k 0)
        cur
        (loop (cdr cur) (- k 1)))))

(define (ideque-take dq n)
  (%make-ideque (%dq-take-list (%dq-list dq) n)))

(define (ideque-drop dq n)
  (%make-ideque (%dq-drop-list (%dq-list dq) n)))

(define (ideque-take-right dq n)
  (let* ((xs (%dq-list dq))
         (len (length xs)))
    (%make-ideque (%dq-drop-list xs (- len n)))))

(define (ideque-drop-right dq n)
  (let* ((xs (%dq-list dq))
         (len (length xs)))
    (%make-ideque (%dq-take-list xs (- len n)))))

(define (ideque-split-at dq n)
  (values (ideque-take dq n) (ideque-drop dq n)))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 134 The Whole Ideque & Higher-Order Operations
;; ---------------------------------------------------------------------

(define (ideque-length dq)
  (length (%dq-list dq)))

(define ideque-append
  (case-lambda
    (() (%make-ideque '()))
    ((dq1) dq1)
    ((dq1 . rest)
     (let loop ((more rest) (acc (%dq-copy-list (%dq-list dq1))))
       (if (null? more)
           (%make-ideque acc)
           (loop (cdr more) (append acc (%dq-list (car more)))))))))

(define (ideque-reverse dq)
  (%make-ideque (reverse (%dq-list dq))))

(define ideque-count
  (case-lambda
    ((pred dq1)
     (let loop ((xs (%dq-list dq1)) (n 0))
       (if (null? xs)
           n
           (loop (cdr xs) (if (pred (car xs)) (+ n 1) n)))))
    ((pred dq1 dq2)
     (let loop ((a (%dq-list dq1)) (b (%dq-list dq2)) (n 0))
       (if (or (null? a) (null? b))
           n
           (loop (cdr a) (cdr b) (if (pred (car a) (car b)) (+ n 1) n)))))))

(define ideque-zip
  (case-lambda
    ((dq1)
     (ideque-map (lambda (x) (list x)) dq1))
    ((dq1 dq2)
     (let loop ((a (%dq-list dq1)) (b (%dq-list dq2)) (acc '()))
       (if (or (null? a) (null? b))
           (%make-ideque (reverse acc))
           (loop (cdr a) (cdr b) (cons (list (car a) (car b)) acc)))))
    ((dq1 dq2 . rest)
     (let loop ((lists (map %dq-list (cons dq1 (cons dq2 rest)))) (acc '()))
       (if (let any-null ((ls lists))
             (cond ((null? ls) #f)
                   ((null? (car ls)) #t)
                   (else (any-null (cdr ls)))))
           (%make-ideque (reverse acc))
           (loop (map (lambda (x) (cdr x)) lists) (cons (map (lambda (x) (car x)) lists) acc)))))))

(define ideque-map
  (case-lambda
    ((proc dq1)
     (%make-ideque (map proc (%dq-list dq1))))
    ((proc dq1 dq2)
     (let loop ((a (%dq-list dq1)) (b (%dq-list dq2)) (acc '()))
       (if (or (null? a) (null? b))
           (%make-ideque (reverse acc))
           (loop (cdr a) (cdr b) (cons (proc (car a) (car b)) acc)))))))

(define ideque-filter-map
  (case-lambda
    ((proc dq1)
     (let loop ((xs (%dq-list dq1)) (acc '()))
       (if (null? xs)
           (%make-ideque (reverse acc))
           (let ((res (proc (car xs))))
             (loop (cdr xs) (if res (cons res acc) acc))))))
    ((proc dq1 dq2)
     (let loop ((a (%dq-list dq1)) (b (%dq-list dq2)) (acc '()))
       (if (or (null? a) (null? b))
           (%make-ideque (reverse acc))
           (let ((res (proc (car a) (car b))))
             (loop (cdr a) (cdr b) (if res (cons res acc) acc))))))))

(define ideque-for-each
  (case-lambda
    ((proc dq1)
     (for-each proc (%dq-list dq1)))
    ((proc dq1 dq2)
     (let loop ((a (%dq-list dq1)) (b (%dq-list dq2)))
       (if (and (not (null? a)) (not (null? b)))
           (begin
             (proc (car a) (car b))
             (loop (cdr a) (cdr b))))))))

(define ideque-for-each-right
  (case-lambda
    ((proc dq1)
     (for-each proc (reverse (%dq-list dq1))))
    ((proc dq1 dq2)
     (ideque-for-each proc (ideque-reverse dq1) (ideque-reverse dq2)))))

(define ideque-fold
  (case-lambda
    ((proc nil dq1)
     (let loop ((xs (%dq-list dq1)) (acc nil))
       (if (null? xs)
           acc
           (loop (cdr xs) (proc (car xs) acc)))))
    ((proc nil dq1 dq2)
     (let loop ((a (%dq-list dq1)) (b (%dq-list dq2)) (acc nil))
       (if (or (null? a) (null? b))
           acc
           (loop (cdr a) (cdr b) (proc (car a) (car b) acc)))))))

(define ideque-fold-right
  (case-lambda
    ((proc nil dq1)
     (let loop ((xs (reverse (%dq-list dq1))) (acc nil))
       (if (null? xs)
           acc
           (loop (cdr xs) (proc (car xs) acc)))))
    ((proc nil dq1 dq2)
     (let loop ((a (%dq-list dq1)) (b (%dq-list dq2)) (pairs '()))
       (if (or (null? a) (null? b))
           (let rloop ((ps pairs) (acc nil))
             (if (null? ps)
                 acc
                 (rloop (cdr ps) (proc (caar ps) (cdar ps) acc))))
           (loop (cdr a) (cdr b) (cons (cons (car a) (car b)) pairs)))))))

(define ideque-append-map
  (case-lambda
    ((proc dq1)
     (let loop ((xs (%dq-list dq1)) (acc '()))
       (if (null? xs)
           (%make-ideque acc)
           (loop (cdr xs) (append acc (proc (car xs)))))))
    ((proc dq1 dq2)
     (let loop ((a (%dq-list dq1)) (b (%dq-list dq2)) (acc '()))
       (if (or (null? a) (null? b))
           (%make-ideque acc)
           (loop (cdr a) (cdr b) (append acc (proc (car a) (car b)))))))))

(define (ideque-filter pred dq)
  (let loop ((xs (%dq-list dq)) (acc '()))
    (if (null? xs)
        (%make-ideque (reverse acc))
        (loop (cdr xs) (if (pred (car xs)) (cons (car xs) acc) acc)))))

(define (ideque-remove pred dq)
  (let loop ((xs (%dq-list dq)) (acc '()))
    (if (null? xs)
        (%make-ideque (reverse acc))
        (loop (cdr xs) (if (pred (car xs)) acc (cons (car xs) acc))))))

(define (ideque-partition pred dq)
  (let loop ((xs (%dq-list dq)) (in-acc '()) (out-acc '()))
    (if (null? xs)
        (values (%make-ideque (reverse in-acc))
                (%make-ideque (reverse out-acc)))
        (if (pred (car xs))
            (loop (cdr xs) (cons (car xs) in-acc) out-acc)
            (loop (cdr xs) in-acc (cons (car xs) out-acc))))))

(define (%dq-find-core pred xs failure)
  (let loop ((cur xs))
    (cond
      ((null? cur) (if failure (failure) #f))
      ((pred (car cur)) (car cur))
      (else (loop (cdr cur))))))

(define ideque-find
  (case-lambda
    ((pred dq) (%dq-find-core pred (%dq-list dq) #f))
    ((pred dq failure) (%dq-find-core pred (%dq-list dq) failure))))

(define ideque-find-right
  (case-lambda
    ((pred dq) (%dq-find-core pred (reverse (%dq-list dq)) #f))
    ((pred dq failure) (%dq-find-core pred (reverse (%dq-list dq)) failure))))

(define (ideque-take-while pred dq)
  (let loop ((xs (%dq-list dq)) (acc '()))
    (if (or (null? xs) (not (pred (car xs))))
        (%make-ideque (reverse acc))
        (loop (cdr xs) (cons (car xs) acc)))))

(define (ideque-drop-while pred dq)
  (let loop ((xs (%dq-list dq)))
    (if (or (null? xs) (not (pred (car xs))))
        (%make-ideque xs)
        (loop (cdr xs)))))

(define (ideque-take-while-right pred dq)
  (let loop ((xs (reverse (%dq-list dq))) (acc '()))
    (if (or (null? xs) (not (pred (car xs))))
        (%make-ideque acc)
        (loop (cdr xs) (cons (car xs) acc)))))

(define (ideque-drop-while-right pred dq)
  (let loop ((xs (reverse (%dq-list dq))))
    (if (or (null? xs) (not (pred (car xs))))
        (%make-ideque (reverse xs))
        (loop (cdr xs)))))

(define (ideque-span pred dq)
  (values (ideque-take-while pred dq)
          (ideque-drop-while pred dq)))

(define (ideque-break pred dq)
  (let ((not-pred (lambda (x) (not (pred x)))))
    (values (ideque-take-while not-pred dq)
            (ideque-drop-while not-pred dq))))

(define ideque-any
  (case-lambda
    ((pred dq1)
     (let loop ((xs (%dq-list dq1)))
       (if (null? xs)
           #f
           (let ((res (pred (car xs))))
             (if res res (loop (cdr xs)))))))
    ((pred dq1 dq2)
     (let loop ((a (%dq-list dq1)) (b (%dq-list dq2)))
       (if (or (null? a) (null? b))
           #f
           (let ((res (pred (car a) (car b))))
             (if res res (loop (cdr a) (cdr b)))))))))

(define ideque-every
  (case-lambda
    ((pred dq1)
     (let loop ((xs (%dq-list dq1)) (last #t))
       (if (null? xs)
           last
           (let ((res (pred (car xs))))
             (if res (loop (cdr xs) res) #f)))))
    ((pred dq1 dq2)
     (let loop ((a (%dq-list dq1)) (b (%dq-list dq2)) (last #t))
       (if (or (null? a) (null? b))
           last
           (let ((res (pred (car a) (car b))))
             (if res (loop (cdr a) (cdr b) res) #f)))))))
