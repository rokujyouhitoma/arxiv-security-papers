;;; =======================================================================
;;; ULisp Standard Library: Purely Functional Random-Access Lists — R7RS-large Red Edition / SRFI 101
;;; Specification: (scheme rlist) / (srfi 101)
;;; Conforms to DSN-33 Architecture Specification & Issue #854
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 101 Core Types & Invariants (Okasaki Skew Binary Random-Access Trees)
;; ---------------------------------------------------------------------
;; A random-access list is either the empty list '() or a sequence (forest)
;; of complete binary trees where tree sizes follow skew binary numbers:
;;   w = 2^{k+1} - 1 (1, 3, 7, 15, 31, ...)
;;
;; Pair representation: #(ulisp-ra-pair-tag size tree rest)
;; Internal tree node: #(ulisp-ra-node-tag val left right)
;; For tree size = 1: tree is stored directly as the value (leaf optimization).
;; For tree size > 1: tree is stored as a node #(ulisp-ra-node-tag val left right).
;; ---------------------------------------------------------------------

(define (%make-ra-node val left right)
  (let ((v (make-vector 4 #f)))
    (vector-set! v 0 'ulisp-ra-node-tag)
    (vector-set! v 1 val)
    (vector-set! v 2 left)
    (vector-set! v 3 right)
    v))

(define (%ra-node? obj)
  (and (vector? obj)
       (= (vector-length obj) 4)
       (eq? (vector-ref obj 0) 'ulisp-ra-node-tag)))

(define (%ra-node-val n) (vector-ref n 1))
(define (%ra-node-left n) (vector-ref n 2))
(define (%ra-node-right n) (vector-ref n 3))

(define (%make-ra-pair size tree rest)
  (let ((v (make-vector 4 #f)))
    (vector-set! v 0 'ulisp-ra-pair-tag)
    (vector-set! v 1 size)
    (vector-set! v 2 tree)
    (vector-set! v 3 rest)
    v))

(define (ra-pair? obj)
  (and (vector? obj)
       (= (vector-length obj) 4)
       (eq? (vector-ref obj 0) 'ulisp-ra-pair-tag)))

(define (%ra-pair-size p) (vector-ref p 1))
(define (%ra-pair-tree p) (vector-ref p 2))
(define (%ra-pair-rest p) (vector-ref p 3))

(define (%ra-half n)
  (quotient n 2))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 101 Fundamental Pair Operations (cons, car, cdr)
;; ---------------------------------------------------------------------

(define (ra-cons x ls)
  (if (ra-pair? ls)
      (let ((s (%ra-pair-size ls)))
        (let ((r (%ra-pair-rest ls)))
          (if (and (ra-pair? r)
                   (= (%ra-pair-size r) s))
              ;; Two leading trees of equal size s: combine into tree of size 2s + 1
              (let ((new-node (%make-ra-node x (%ra-pair-tree ls) (%ra-pair-tree r))))
                (%make-ra-pair (+ (+ 1 s) s) new-node (%ra-pair-rest r)))
              ;; Leading trees have distinct sizes: prepend single-element tree of size 1
              (%make-ra-pair 1 x ls))))
      (%make-ra-pair 1 x ls)))

(define (ra-car p)
  (if (not (ra-pair? p))
      (error "ra-car: expected ra-pair" p)
      (let ((s (%ra-pair-size p)))
        (if (= s 1)
            (%ra-pair-tree p)
            (%ra-node-val (%ra-pair-tree p))))))

(define (ra-cdr p)
  (if (not (ra-pair? p))
      (error "ra-cdr: expected ra-pair" p)
      (let ((s (%ra-pair-size p)))
        (if (= s 1)
            (%ra-pair-rest p)
            (let ((half-s (%ra-half s))
                  (node (%ra-pair-tree p))
                  (rest (%ra-pair-rest p)))
              (%make-ra-pair half-s
                             (%ra-node-left node)
                             (%make-ra-pair half-s
                                            (%ra-node-right node)
                                            rest)))))))

(define (ra-car+cdr p)
  (if (not (ra-pair? p))
      (error "ra-car+cdr: expected ra-pair" p)
      (let ((s (%ra-pair-size p)))
        (if (= s 1)
            (values (%ra-pair-tree p) (%ra-pair-rest p))
            (let ((half-s (%ra-half s))
                  (node (%ra-pair-tree p))
                  (rest (%ra-pair-rest p)))
              (values (%ra-node-val node)
                      (%make-ra-pair half-s
                                     (%ra-node-left node)
                                     (%make-ra-pair half-s
                                                    (%ra-node-right node)
                                                    rest))))))))

;; All 28 standard cxr compositions
(define (ra-caar x) (ra-car (ra-car x)))
(define (ra-cadr x) (ra-car (ra-cdr x)))
(define (ra-cdar x) (ra-cdr (ra-car x)))
(define (ra-cddr x) (ra-cdr (ra-cdr x)))

(define (ra-caaar x) (ra-car (ra-caar x)))
(define (ra-caadr x) (ra-car (ra-cadr x)))
(define (ra-cadar x) (ra-car (ra-cdar x)))
(define (ra-caddr x) (ra-car (ra-cddr x)))
(define (ra-cdaar x) (ra-cdr (ra-caar x)))
(define (ra-cdadr x) (ra-cdr (ra-cadr x)))
(define (ra-cddar x) (ra-cdr (ra-cdar x)))
(define (ra-cdddr x) (ra-cdr (ra-cddr x)))

(define (ra-caaaar x) (ra-car (ra-caaar x)))
(define (ra-caaadr x) (ra-car (ra-caadr x)))
(define (ra-caadar x) (ra-car (ra-cadar x)))
(define (ra-caaddr x) (ra-car (ra-caddr x)))
(define (ra-cadaar x) (ra-car (ra-cdaar x)))
(define (ra-cadadr x) (ra-car (ra-cdadr x)))
(define (ra-caddar x) (ra-car (ra-cddar x)))
(define (ra-cadddr x) (ra-car (ra-cdddr x)))
(define (ra-cdaaar x) (ra-cdr (ra-caaar x)))
(define (ra-cdaadr x) (ra-cdr (ra-caadr x)))
(define (ra-cdadar x) (ra-cdr (ra-cadar x)))
(define (ra-cdaddr x) (ra-cdr (ra-caddr x)))
(define (ra-cddaar x) (ra-cdr (ra-cdaar x)))
(define (ra-cddadr x) (ra-cdr (ra-cdadr x)))
(define (ra-cdddar x) (ra-cdr (ra-cddar x)))
(define (ra-cddddr x) (ra-cdr (ra-cdddr x)))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 101 Conversion Procedures
;; ---------------------------------------------------------------------

(define (linear-access-list->random-access-list lst)
  (let loop ((cur (reverse lst)) (acc '()))
    (if (null? cur)
        acc
        (loop (cdr cur) (ra-cons (car cur) acc)))))

(define list->rlist linear-access-list->random-access-list)

(define (random-access-list->linear-access-list rlst)
  (let loop ((cur rlst) (acc '()))
    (cond
      ((null? cur) (reverse acc))
      ((ra-pair? cur)
       (loop (ra-cdr cur) (cons (ra-car cur) acc)))
      (else
       (error "random-access-list->linear-access-list: expected proper list" rlst)))))

(define rlist->list random-access-list->linear-access-list)

(define (datum->rlist obj)
  (cond
    ((pair? obj)
     (ra-cons (datum->rlist (car obj)) (datum->rlist (cdr obj))))
    (else obj)))

(define (rlist->datum obj)
  (cond
    ((ra-pair? obj)
     (cons (rlist->datum (ra-car obj)) (rlist->datum (ra-cdr obj))))
    (else obj)))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 101 Constructors
;; ---------------------------------------------------------------------

(define-syntax ra-list
  (syntax-rules ()
    ((_) '())
    ((_ a b ...) (ra-cons a (ra-list b ...)))))

(define ra-make-list
  (case-lambda
    ((k) (ra-make-list k 0))
    ((k obj)
     (if (or (not (integer? k)) (< k 0))
         (error "ra-make-list: length must be a non-negative integer" k)
         (let loop ((n k) (acc '()))
           (if (<= n 0)
               acc
               (loop (- n 1) (ra-cons obj acc))))))))

(define-syntax ra-quote
  (syntax-rules ()
    ((_ datum)
     (datum->rlist `datum))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 101 Predicates
;; ---------------------------------------------------------------------

(define (ra-null? obj)
  (null? obj))

(define (ra-list? obj)
  (let loop ((cur obj))
    (cond
      ((null? cur) #t)
      ((ra-pair? cur) (loop (%ra-pair-rest cur)))
      (else #f))))

(define (ra-length<=? obj k)
  (if (<= k 0)
      #t
      (let loop ((cur obj) (rem k))
        (cond
          ((<= rem 0) #t)
          ((not (ra-pair? cur)) #f)
          (else
           (let ((s (%ra-pair-size cur)))
             (if (<= rem s)
                 #t
                 (loop (%ra-pair-rest cur) (- rem s)))))))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 101 Random-Access Selectors (O(log n))
;; ---------------------------------------------------------------------

(define (%ra-tree-ref size tree i)
  (if (zero? i)
      (if (= size 1) tree (%ra-node-val tree))
      (let ((half-s (%ra-half size)))
        (if (<= i half-s)
            (%ra-tree-ref half-s (%ra-node-left tree) (- i 1))
            (%ra-tree-ref half-s (%ra-node-right tree) (- (- i half-s) 1))))))

(define (ra-list-ref ls i)
  (if (or (not (integer? i)) (< i 0))
      (error "ra-list-ref: index must be a non-negative integer" i)
      (let loop ((cur ls) (j i))
        (if (not (ra-pair? cur))
            (error "ra-list-ref: index out of bounds" i)
            (let ((s (%ra-pair-size cur)))
              (if (< j s)
                  (%ra-tree-ref s (%ra-pair-tree cur) j)
                  (loop (%ra-pair-rest cur) (- j s))))))))

(define (ra-list-tail ls k)
  (if (or (not (integer? k)) (< k 0))
      (error "ra-list-tail: index must be a non-negative integer" k)
      (let loop ((cur ls) (j k))
        (cond
          ((zero? j) cur)
          ((not (ra-pair? cur))
           (error "ra-list-tail: index out of bounds" k))
          (else
           (let ((s (%ra-pair-size cur)))
             (if (>= j s)
                 (loop (%ra-pair-rest cur) (- j s))
                 (loop (ra-cdr cur) (- j 1)))))))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 101 Purely Functional Updaters (O(log n))
;; ---------------------------------------------------------------------

(define (%ra-tree-set size tree i val)
  (if (zero? i)
      (if (= size 1)
          val
          (%make-ra-node val (%ra-node-left tree) (%ra-node-right tree)))
      (let ((half-s (%ra-half size)))
        (if (<= i half-s)
            (%make-ra-node (%ra-node-val tree)
                           (%ra-tree-set half-s (%ra-node-left tree) (- i 1) val)
                           (%ra-node-right tree))
            (%make-ra-node (%ra-node-val tree)
                           (%ra-node-left tree)
                           (%ra-tree-set half-s (%ra-node-right tree) (- (- i half-s) 1) val))))))

(define (ra-list-set ls i val)
  (if (or (not (integer? i)) (< i 0))
      (error "ra-list-set: index must be a non-negative integer" i)
      (let loop ((cur ls) (j i))
        (if (not (ra-pair? cur))
            (error "ra-list-set: index out of bounds" i)
            (let ((s (%ra-pair-size cur)))
              (if (< j s)
                  (%make-ra-pair s
                                 (%ra-tree-set s (%ra-pair-tree cur) j val)
                                 (%ra-pair-rest cur))
                  (%make-ra-pair s
                                 (%ra-pair-tree cur)
                                 (loop (%ra-pair-rest cur) (- j s)))))))))

(define (%ra-tree-ref-update size tree i proc)
  (if (zero? i)
      (if (= size 1)
          (values tree (proc tree))
          (let ((old-val (%ra-node-val tree)))
            (values old-val
                    (%make-ra-node (proc old-val)
                                   (%ra-node-left tree)
                                   (%ra-node-right tree)))))
      (let ((half-s (%ra-half size)))
        (if (<= i half-s)
            (call-with-values
              (lambda ()
                (%ra-tree-ref-update half-s (%ra-node-left tree) (- i 1) proc))
              (lambda (old-val new-left)
                (values old-val
                        (%make-ra-node (%ra-node-val tree)
                                       new-left
                                       (%ra-node-right tree)))))
            (call-with-values
              (lambda ()
                (%ra-tree-ref-update half-s (%ra-node-right tree) (- (- i half-s) 1) proc))
              (lambda (old-val new-right)
                (values old-val
                        (%make-ra-node (%ra-node-val tree)
                                       (%ra-node-left tree)
                                       new-right))))))))

(define (ra-list-ref/update ls i proc)
  (if (or (not (integer? i)) (< i 0))
      (error "ra-list-ref/update: index must be a non-negative integer" i)
      (let loop ((cur ls) (j i))
        (if (not (ra-pair? cur))
            (error "ra-list-ref/update: index out of bounds" i)
            (let ((s (%ra-pair-size cur)))
              (if (< j s)
                  (call-with-values
                    (lambda () (%ra-tree-ref-update s (%ra-pair-tree cur) j proc))
                    (lambda (old-val new-tree)
                      (values old-val
                              (%make-ra-pair s new-tree (%ra-pair-rest cur)))))
                  (call-with-values
                    (lambda () (loop (%ra-pair-rest cur) (- j s)))
                    (lambda (old-val new-rest)
                      (values old-val
                              (%make-ra-pair s (%ra-pair-tree cur) new-rest))))))))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 101 Iteration, Length, Append, Reverse & Higher-Order Procedures
;; ---------------------------------------------------------------------

(define (ra-length ls)
  (let loop ((cur ls) (acc 0))
    (cond
      ((null? cur) acc)
      ((ra-pair? cur)
       (loop (%ra-pair-rest cur) (+ acc (%ra-pair-size cur))))
      (else
       (error "ra-length: expected proper list" ls)))))

(define (%ra-append-2 a b)
  (if (null? a)
      b
      (let rev-loop ((cur a) (rev '()))
        (if (null? cur)
            (let unrev-loop ((cur rev) (acc b))
              (if (null? cur)
                  acc
                  (unrev-loop (cdr cur) (ra-cons (car cur) acc))))
            (if (ra-pair? cur)
                (rev-loop (ra-cdr cur) (cons (ra-car cur) rev))
                (error "ra-append: expected proper list" a))))))

(define ra-append
  (case-lambda
    (() '())
    ((a) a)
    ((a b) (%ra-append-2 a b))
    ((a b . rest)
     (let loop ((cur rest) (acc (%ra-append-2 a b)))
       (if (null? cur)
           acc
           (loop (cdr cur) (%ra-append-2 acc (car cur))))))))

(define (ra-reverse ls)
  (let loop ((cur ls) (acc '()))
    (if (null? cur)
        acc
        (if (ra-pair? cur)
            (loop (ra-cdr cur) (ra-cons (ra-car cur) acc))
            (error "ra-reverse: expected proper list" ls)))))

(define (%ra-tree-map proc size tree)
  (if (= size 1)
      (proc tree)
      (let ((half-s (%ra-half size)))
        (%make-ra-node (proc (%ra-node-val tree))
                       (%ra-tree-map proc half-s (%ra-node-left tree))
                       (%ra-tree-map proc half-s (%ra-node-right tree))))))

(define (%ra-map-1 proc ls)
  (let loop ((cur ls))
    (if (null? cur)
        '()
        (if (ra-pair? cur)
            (let ((s (%ra-pair-size cur)))
              (%make-ra-pair s
                             (%ra-tree-map proc s (%ra-pair-tree cur))
                             (loop (%ra-pair-rest cur))))
            (error "ra-map: expected proper list" ls)))))

(define (%ra-map-2 proc ls1 ls2)
  (let loop ((a ls1) (b ls2) (acc '()))
    (if (or (null? a) (null? b))
        (let unrev ((cur acc) (res '()))
          (if (null? cur)
              res
              (unrev (cdr cur) (ra-cons (car cur) res))))
        (loop (ra-cdr a) (ra-cdr b) (cons (proc (ra-car a) (ra-car b)) acc)))))

(define (%ra-any-null? lss)
  (cond
    ((null? lss) #f)
    ((null? (car lss)) #t)
    (else (%ra-any-null? (cdr lss)))))

(define (%ra-map-n proc lss)
  (let loop ((cur-lss lss) (acc '()))
    (if (or (null? cur-lss) (%ra-any-null? cur-lss))
        (let unrev ((cur acc) (res '()))
          (if (null? cur)
              res
              (unrev (cdr cur) (ra-cons (car cur) res))))
        (let ((heads (map ra-car cur-lss))
              (tails (map ra-cdr cur-lss)))
          (loop tails (cons (apply proc heads) acc))))))

(define ra-map
  (case-lambda
    ((proc ls) (%ra-map-1 proc ls))
    ((proc ls1 ls2) (%ra-map-2 proc ls1 ls2))
    ((proc ls1 . lss) (%ra-map-n proc (cons ls1 lss)))))

(define (%ra-tree-for-each proc size tree)
  (if (= size 1)
      (proc tree)
      (let ((half-s (%ra-half size)))
        (proc (%ra-node-val tree))
        (%ra-tree-for-each proc half-s (%ra-node-left tree))
        (%ra-tree-for-each proc half-s (%ra-node-right tree)))))

(define (%ra-for-each-1 proc ls)
  (let loop ((cur ls))
    (when (ra-pair? cur)
      (let ((s (%ra-pair-size cur)))
        (%ra-tree-for-each proc s (%ra-pair-tree cur))
        (loop (%ra-pair-rest cur))))))

(define (%ra-for-each-2 proc ls1 ls2)
  (let loop ((a ls1) (b ls2))
    (when (and (ra-pair? a) (ra-pair? b))
      (proc (ra-car a) (ra-car b))
      (loop (ra-cdr a) (ra-cdr b)))))

(define (%ra-for-each-n proc lss)
  (let loop ((cur-lss lss))
    (when (and (pair? cur-lss) (not (%ra-any-null? cur-lss)))
      (apply proc (map ra-car cur-lss))
      (loop (map ra-cdr cur-lss)))))

(define ra-for-each
  (case-lambda
    ((proc ls) (%ra-for-each-1 proc ls))
    ((proc ls1 ls2) (%ra-for-each-2 proc ls1 ls2))
    ((proc ls1 . lss) (%ra-for-each-n proc (cons ls1 lss)))))
