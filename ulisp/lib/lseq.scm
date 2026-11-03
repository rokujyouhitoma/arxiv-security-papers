;;; =======================================================================
;;; ULisp Standard Library: Lazy Sequences — R7RS-large Red Edition / SRFI 127
;;; Specification: (scheme lseq) / (srfi 127)
;;; Conforms to DSN-33 Architecture Specification & Issue #707
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 127 GC-Safe Mutator & Constructors
;; ---------------------------------------------------------------------

(define (%lseq-cell a b)
  (cons a b))

(define (%lseq-set-car! p v)
  (set-car! p v))

(define (%lseq-set-cdr! p v)
  (set-cdr! p v))

(define (%make-lseq-tail gen)
  (let ((v (make-vector 2 #f)))
    (vector-set! v 0 'ulisp-lseq-gen)
    (vector-set! v 1 gen)
    v))

(define (%lseq-tail-gen? x)
  (and (vector? x)
       (= (vector-length x) 2)
       (eq? (vector-ref x 0) 'ulisp-lseq-gen)))

(define (generator->lseq gen)
  (let ((val (gen)))
    (if (eof-object? val)
        '()
        (cons val (%make-lseq-tail gen)))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 127 Predicates
;; ---------------------------------------------------------------------

(define (lseq? x)
  (cond
    ((null? x) #t)
    ((not (pair? x)) #f)
    ((%lseq-tail-gen? (cdr x)) #t)
    ((procedure? (cdr x)) #t)
    (else (lseq? (cdr x)))))

(define (%lseq-equal-2? elt=? s1 s2)
  (let loop ((a s1) (b s2))
    (cond
      ((and (null? a) (null? b)) #t)
      ((or (null? a) (null? b)) #f)
      ((elt=? (lseq-car a) (lseq-car b))
       (loop (lseq-cdr a) (lseq-cdr b)))
      (else #f))))

(define lseq=?
  (case-lambda
    ((elt=?) #t)
    ((elt=? s1) #t)
    ((elt=? s1 s2) (%lseq-equal-2? elt=? s1 s2))
    ((elt=? s1 s2 . rest)
     (if (%lseq-equal-2? elt=? s1 s2)
         (let loop ((prev s2) (more rest))
           (if (null? more)
               #t
               (if (%lseq-equal-2? elt=? prev (car more))
                   (loop (car more) (cdr more))
                   #f)))
         #f))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 127 Selectors
;; ---------------------------------------------------------------------

(define (lseq-car lseq)
  (car lseq))

(define (lseq-first lseq)
  (car lseq))

(define (lseq-cdr lseq)
  (if (not (pair? lseq))
      (error "lseq-cdr: not a pair" lseq)
      (let ((tail (cdr lseq)))
        (if (%lseq-tail-gen? tail)
            (let* ((gen (vector-ref tail 1))
                   (val (gen)))
              (if (eof-object? val)
                  (begin
                    (%lseq-set-cdr! lseq '())
                    '())
                  (let ((next (cons val tail)))
                    (%lseq-set-cdr! lseq next)
                    next)))
            tail))))

(define (lseq-rest lseq)
  (lseq-cdr lseq))

(define (lseq-ref lseq k)
  (let loop ((cur lseq) (i k))
    (if (null? cur)
        (error "lseq-ref: index out of bounds" k)
        (if (<= i 0)
            (lseq-car cur)
            (loop (lseq-cdr cur) (- i 1))))))

(define (lseq-take lseq k)
  (let ((cell (%lseq-cell lseq k)))
    (generator->lseq
     (lambda ()
       (let ((cur (car cell))
             (rem (cdr cell)))
         (if (or (<= rem 0) (null? cur))
             (eof-object)
             (let ((v (lseq-car cur)))
               (%lseq-set-cdr! cell (- rem 1))
               (%lseq-set-car! cell (lseq-cdr cur))
               v)))))))

(define (lseq-drop lseq k)
  (let loop ((cur lseq) (i k))
    (if (<= i 0)
        cur
        (if (null? cur)
            (error "lseq-drop: index out of bounds" k)
            (loop (lseq-cdr cur) (- i 1))))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 127 Whole Lazy Sequence Procedures
;; ---------------------------------------------------------------------

(define (lseq-realize lseq)
  (let loop ((cur lseq) (acc '()))
    (if (null? cur)
        (reverse acc)
        (loop (lseq-cdr cur) (cons (lseq-car cur) acc)))))

(define (lseq->generator lseq)
  (let ((cell (%lseq-cell lseq '())))
    (lambda ()
      (let ((cur (car cell)))
        (if (null? cur)
            (eof-object)
            (let ((v (lseq-car cur)))
              (%lseq-set-car! cell (lseq-cdr cur))
              v))))))

(define (lseq-length lseq)
  (let loop ((cur lseq) (n 0))
    (if (null? cur)
        n
        (loop (lseq-cdr cur) (+ n 1)))))

(define (%lseq-append-list lseqs)
  (let ((cell (%lseq-cell lseqs '())))
    (generator->lseq
     (lambda ()
       (let loop ()
         (let ((qs (car cell)))
           (if (null? qs)
               (eof-object)
               (let ((cur (car qs)))
                 (if (null? cur)
                     (begin
                       (%lseq-set-car! cell (cdr qs))
                       (loop))
                     (let ((v (lseq-car cur)))
                       (%lseq-set-car! cell (cons (lseq-cdr cur) (cdr qs)))
                       v))))))))))

(define lseq-append
  (case-lambda
    (() '())
    ((s) s)
    ((s1 . rest)
     (%lseq-append-list (cons s1 rest)))))

(define (%lseq-any-null? ls)
  (let loop ((cur ls))
    (if (null? cur)
        #f
        (if (null? (car cur))
            #t
            (loop (cdr cur))))))

(define (%lseq-zip-n seqs)
  (let ((cell (%lseq-cell seqs '())))
    (generator->lseq
     (lambda ()
       (let ((cur (car cell)))
         (if (%lseq-any-null? cur)
             (eof-object)
             (let ((heads (map lseq-car cur))
                   (tails (map lseq-cdr cur)))
               (%lseq-set-car! cell tails)
               heads)))))))

(define lseq-zip
  (case-lambda
    ((s1)
     (%lseq-map-1 (lambda (x) (list x)) s1))
    ((s1 . rest)
     (%lseq-zip-n (cons s1 rest)))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 127 Mapping & Filtering
;; ---------------------------------------------------------------------

(define (%lseq-map-1 proc s1)
  (let ((cell (%lseq-cell s1 '())))
    (generator->lseq
     (lambda ()
       (let ((cur (car cell)))
         (if (null? cur)
             (eof-object)
             (let ((v (proc (lseq-car cur))))
               (%lseq-set-car! cell (lseq-cdr cur))
               v)))))))

(define (%lseq-map-n proc seqs)
  (let ((cell (%lseq-cell seqs '())))
    (generator->lseq
     (lambda ()
       (let ((cur (car cell)))
         (if (%lseq-any-null? cur)
             (eof-object)
             (let ((heads (map lseq-car cur))
                   (tails (map lseq-cdr cur)))
               (%lseq-set-car! cell tails)
               (apply proc heads))))))))

(define lseq-map
  (case-lambda
    ((proc s1)
     (%lseq-map-1 proc s1))
    ((proc s1 . rest)
     (%lseq-map-n proc (cons s1 rest)))))

(define lseq-for-each
  (case-lambda
    ((proc s1)
     (let loop ((cur s1))
       (if (not (null? cur))
           (begin
             (proc (lseq-car cur))
             (loop (lseq-cdr cur))))))
    ((proc s1 . rest)
     (let loop ((cur (cons s1 rest)))
       (if (not (%lseq-any-null? cur))
           (begin
             (apply proc (map lseq-car cur))
             (loop (map lseq-cdr cur))))))))

(define (lseq-filter pred lseq)
  (let ((cell (%lseq-cell lseq '())))
    (generator->lseq
     (lambda ()
       (let loop ()
         (let ((cur (car cell)))
           (if (null? cur)
               (eof-object)
               (let ((v (lseq-car cur)))
                 (%lseq-set-car! cell (lseq-cdr cur))
                 (if (pred v)
                     v
                     (loop))))))))))

(define (lseq-remove pred lseq)
  (lseq-filter (lambda (x) (not (pred x))) lseq))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 127 Searching
;; ---------------------------------------------------------------------

(define (lseq-find-tail pred lseq)
  (let loop ((cur lseq))
    (cond
      ((null? cur) #f)
      ((pred (lseq-car cur)) cur)
      (else (loop (lseq-cdr cur))))))

(define (lseq-find pred lseq)
  (let ((tail (lseq-find-tail pred lseq)))
    (if tail (lseq-car tail) #f)))

(define (lseq-take-while pred lseq)
  (let ((cell (%lseq-cell lseq '())))
    (generator->lseq
     (lambda ()
       (let ((cur (car cell)))
         (if (null? cur)
             (eof-object)
             (let ((v (lseq-car cur)))
               (if (pred v)
                   (begin
                     (%lseq-set-car! cell (lseq-cdr cur))
                     v)
                   (begin
                     (%lseq-set-car! cell '())
                     (eof-object))))))))))

(define (lseq-drop-while pred lseq)
  (let loop ((cur lseq))
    (cond
      ((null? cur) '())
      ((pred (lseq-car cur)) (loop (lseq-cdr cur)))
      (else cur))))

(define lseq-any
  (case-lambda
    ((pred s1)
     (let loop ((cur s1))
       (if (null? cur)
           #f
           (let ((res (pred (lseq-car cur))))
             (if res
                 res
                 (loop (lseq-cdr cur)))))))
    ((pred s1 . rest)
     (let loop ((cur (cons s1 rest)))
       (if (%lseq-any-null? cur)
           #f
           (let ((res (apply pred (map lseq-car cur))))
             (if res
                 res
                 (loop (map lseq-cdr cur)))))))))

(define lseq-every
  (case-lambda
    ((pred s1)
     (let loop ((cur s1) (last-val #t))
       (if (null? cur)
           last-val
           (let ((res (pred (lseq-car cur))))
             (if res
                 (loop (lseq-cdr cur) res)
                 #f)))))
    ((pred s1 . rest)
     (let loop ((cur (cons s1 rest)) (last-val #t))
       (if (%lseq-any-null? cur)
           last-val
           (let ((res (apply pred (map lseq-car cur))))
             (if res
                 (loop (map lseq-cdr cur) res)
                 #f)))))))

(define lseq-index
  (case-lambda
    ((pred s1)
     (let loop ((cur s1) (i 0))
       (if (null? cur)
           #f
           (if (pred (lseq-car cur))
               i
               (loop (lseq-cdr cur) (+ i 1))))))
    ((pred s1 . rest)
     (let loop ((cur (cons s1 rest)) (i 0))
       (if (%lseq-any-null? cur)
           #f
           (if (apply pred (map lseq-car cur))
               i
               (loop (map lseq-cdr cur) (+ i 1))))))))

(define lseq-member
  (case-lambda
    ((x lseq)
     (lseq-member x lseq (lambda (a b) (equal? a b))))
    ((x lseq elt=?)
     (let loop ((cur lseq))
       (cond
         ((null? cur) #f)
         ((elt=? x (lseq-car cur)) cur)
         (else (loop (lseq-cdr cur))))))))

(define (lseq-memq x lseq)
  (lseq-member x lseq (lambda (a b) (eq? a b))))

(define (lseq-memv x lseq)
  (lseq-member x lseq (lambda (a b) (eqv? a b))))
