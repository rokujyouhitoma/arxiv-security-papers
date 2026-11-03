;;; =======================================================================
;;; ULisp Standard Library: Immutable Lists — R7RS-large Red Edition / SRFI 116
;;; Specification: (scheme ilist) / (srfi 116)
;;; Conforms to DSN-33 Architecture Specification & Issue #710
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 116 Core Immutable Pair Type: #(ulisp-ipair-tag <icar> <icdr>)
;; ---------------------------------------------------------------------

(define (ipair a d)
  (let ((v (make-vector 3 #f)))
    (vector-set! v 0 'ulisp-ipair-tag)
    (vector-set! v 1 a)
    (vector-set! v 2 d)
    v))

(define (ipair? obj)
  (and (vector? obj)
       (= (vector-length obj) 3)
       (eq? (vector-ref obj 0) 'ulisp-ipair-tag)))

(define (icar ip) (vector-ref ip 1))
(define (icdr ip) (vector-ref ip 2))

(define (replace-icar ip new-a) (ipair new-a (icdr ip)))
(define (replace-icdr ip new-d) (ipair (icar ip) new-d))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 116 Constructors
;; ---------------------------------------------------------------------

(define (xipair d a) (ipair a d))

(define (list->ilist lst)
  (let loop ((cur lst) (acc '()))
    (if (null? cur)
        (let rev ((xs acc) (res '()))
          (if (null? xs)
              res
              (rev (cdr xs) (ipair (car xs) res))))
        (if (pair? cur)
            (loop (cdr cur) (cons (car cur) acc))
            (let rev ((xs acc) (res cur))
              (if (null? xs)
                  res
                  (rev (cdr xs) (ipair (car xs) res))))))))

(define (ilist->list ilst)
  (let loop ((cur ilst) (acc '()))
    (cond
      ((null? cur) (reverse acc))
      ((ipair? cur) (loop (icdr cur) (cons (icar cur) acc)))
      (else
       (let rev ((xs acc) (res cur))
         (if (null? xs)
             res
             (rev (cdr xs) (cons (car xs) res))))))))

(define ilist
  (case-lambda
    (() '())
    ((a . rest)
     (ipair a (list->ilist rest)))))

(define (%ipair*-list args)
  (if (null? (cdr args))
      (car args)
      (ipair (car args) (%ipair*-list (cdr args)))))

(define ipair*
  (case-lambda
    ((a) a)
    ((a . rest)
     (%ipair*-list (cons a rest)))))

(define make-ilist
  (case-lambda
    ((n) (make-ilist n #f))
    ((n fill)
     (let loop ((i 0) (acc '()))
       (if (>= i n)
           acc
           (loop (+ i 1) (ipair fill acc)))))))

(define (ilist-tabulate n init-proc)
  (let loop ((i (- n 1)) (acc '()))
    (if (< i 0)
        acc
        (loop (- i 1) (ipair (init-proc i) acc)))))

(define (ilist-copy ilst)
  (if (ipair? ilst)
      (ipair (icar ilst) (ilist-copy (icdr ilst)))
      ilst))

(define iiota
  (case-lambda
    ((count) (iiota count 0 1))
    ((count start) (iiota count start 1))
    ((count start step)
     (let loop ((i 0) (val start) (acc '()))
       (if (>= i count)
           (ireverse acc)
           (loop (+ i 1) (+ val step) (ipair val acc)))))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 116 Predicates
;; ---------------------------------------------------------------------

(define (proper-ilist? x)
  (let loop ((fast x) (slow x))
    (cond
      ((null? fast) #t)
      ((not (ipair? fast)) #f)
      ((null? (icdr fast)) #t)
      ((not (ipair? (icdr fast))) #f)
      ((eq? (icdr fast) slow) #f)
      (else (loop (icdr (icdr fast)) (icdr slow))))))

(define ilist? proper-ilist?)

(define (dotted-ilist? x)
  (and (not (proper-ilist? x))
       (not (null? x))))

(define (not-ipair? x) (not (ipair? x)))

(define (null-ilist? x)
  (cond
    ((null? x) #t)
    ((ipair? x) #f)
    (else (error "null-ilist?: non-ilist argument" x))))

(define (%ilist=-2 elt= il1 il2)
  (let loop ((a il1) (b il2))
    (cond
      ((and (null? a) (null? b)) #t)
      ((or (null? a) (null? b)) #f)
      ((elt= (icar a) (icar b)) (loop (icdr a) (icdr b)))
      (else #f))))

(define ilist=
  (case-lambda
    ((elt=) #t)
    ((elt= il1) #t)
    ((elt= il1 il2) (%ilist=-2 elt= il1 il2))
    ((elt= il1 il2 . rest)
     (if (%ilist=-2 elt= il1 il2)
         (let loop ((prev il2) (more rest))
           (if (null? more)
               #t
               (if (%ilist=-2 elt= prev (car more))
                   (loop (car more) (cdr more))
                   #f)))
         #f))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 116 Selectors
;; ---------------------------------------------------------------------

(define (icaar x) (icar (icar x)))
(define (icadr x) (icar (icdr x)))
(define (icdar x) (icdr (icar x)))
(define (icddr x) (icdr (icdr x)))
(define (icaaar x) (icar (icaar x)))
(define (icaadr x) (icar (icadr x)))
(define (icadar x) (icar (icdar x)))
(define (icaddr x) (icar (icddr x)))
(define (icdaar x) (icdr (icaar x)))
(define (icdadr x) (icdr (icadr x)))
(define (icddar x) (icdr (icdar x)))
(define (icdddr x) (icdr (icddr x)))
(define (icaaaar x) (icar (icaaar x)))
(define (icaaadr x) (icar (icaadr x)))
(define (icaadar x) (icar (icadar x)))
(define (icaaddr x) (icar (icaddr x)))
(define (icadaar x) (icar (icdaar x)))
(define (icadadr x) (icar (icdadr x)))
(define (icaddar x) (icar (icddar x)))
(define (icadddr x) (icar (icdddr x)))
(define (icdaaar x) (icdr (icaaar x)))
(define (icdaadr x) (icdr (icaadr x)))
(define (icdadar x) (icdr (icadar x)))
(define (icdaddr x) (icdr (icaddr x)))
(define (icddaar x) (icdr (icdaar x)))
(define (icddadr x) (icdr (icdadr x)))
(define (icdddar x) (icdr (icddar x)))
(define (icddddr x) (icdr (icdddr x)))

(define (ilist-ref ilst k)
  (let loop ((cur ilst) (i k))
    (if (<= i 0)
        (icar cur)
        (loop (icdr cur) (- i 1)))))

(define (ifirst x) (ilist-ref x 0))
(define (isecond x) (ilist-ref x 1))
(define (ithird x) (ilist-ref x 2))
(define (ifourth x) (ilist-ref x 3))
(define (ififth x) (ilist-ref x 4))
(define (isixth x) (ilist-ref x 5))
(define (iseventh x) (ilist-ref x 6))
(define (ieighth x) (ilist-ref x 7))
(define (ininth x) (ilist-ref x 8))
(define (itenth x) (ilist-ref x 9))

(define (icar+icdr ip)
  (values (icar ip) (icdr ip)))

(define (itake x i)
  (let loop ((cur x) (k i) (acc '()))
    (if (<= k 0)
        (ireverse acc)
        (loop (icdr cur) (- k 1) (ipair (icar cur) acc)))))

(define (idrop x i)
  (let loop ((cur x) (k i))
    (if (<= k 0)
        cur
        (loop (icdr cur) (- k 1)))))

(define ilist-tail idrop)

(define (itake-right x i)
  (let ((len (ilength x)))
    (idrop x (- len i))))

(define (idrop-right x i)
  (let ((len (ilength x)))
    (itake x (- len i))))

(define (isplit-at x i)
  (values (itake x i) (idrop x i)))

(define (last-ipair x)
  (let loop ((cur x))
    (if (ipair? (icdr cur))
        (loop (icdr cur))
        cur)))

(define (ilast x)
  (icar (last-ipair x)))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 116 Length, Append, Concatenate, Reverse, Zip & Count
;; ---------------------------------------------------------------------

(define (ilength x)
  (let loop ((cur x) (n 0))
    (if (null? cur)
        n
        (loop (icdr cur) (+ n 1)))))

(define (iappend-reverse rev-head tail)
  (let loop ((cur rev-head) (acc tail))
    (if (null? cur)
        acc
        (loop (icdr cur) (ipair (icar cur) acc)))))

(define (ireverse x)
  (iappend-reverse x '()))

(define (%iappend-2 a b)
  (iappend-reverse (ireverse a) b))

(define (iconcatenate ilist-of-ilists)
  (let loop ((cur (ireverse ilist-of-ilists)) (acc '()))
    (if (null? cur)
        acc
        (loop (icdr cur) (%iappend-2 (icar cur) acc)))))

(define iappend
  (case-lambda
    (() '())
    ((a) a)
    ((a b) (%iappend-2 a b))
    ((a b . rest)
     (let loop ((cur rest) (acc (%iappend-2 a b)))
       (if (null? cur)
           acc
           (loop (cdr cur) (%iappend-2 acc (car cur))))))))

(define izip
  (case-lambda
    ((il1)
     (imap ilist il1))
    ((il1 il2)
     (let loop ((a il1) (b il2) (acc '()))
       (if (or (null? a) (null? b))
           (ireverse acc)
           (loop (icdr a) (icdr b) (ipair (ilist (icar a) (icar b)) acc)))))
    ((il1 il2 . rest)
     (let loop ((lists (cons il1 (cons il2 rest))) (acc '()))
       (if (let any-null ((ls lists))
             (cond ((null? ls) #f)
                   ((null? (car ls)) #t)
                   (else (any-null (cdr ls)))))
           (ireverse acc)
           (loop (map icdr lists)
                 (ipair (list->ilist (map icar lists)) acc)))))))

(define (iunzip1 il) (imap icar il))
(define (iunzip2 il) (values (imap ifirst il) (imap isecond il)))
(define (iunzip3 il) (values (imap ifirst il) (imap isecond il) (imap ithird il)))
(define (iunzip4 il) (values (imap ifirst il) (imap isecond il) (imap ithird il) (imap ifourth il)))
(define-syntax iunzip5
  (syntax-rules ()
    ((_ il)
     (values (imap ifirst il) (imap isecond il) (imap ithird il) (imap ifourth il) (imap ififth il)))))

(define icount
  (case-lambda
    ((pred il1)
     (let loop ((cur il1) (n 0))
       (if (null? cur)
           n
           (loop (icdr cur) (if (pred (icar cur)) (+ n 1) n)))))
    ((pred il1 il2)
     (let loop ((a il1) (b il2) (n 0))
       (if (or (null? a) (null? b))
           n
           (loop (icdr a) (icdr b) (if (pred (icar a) (icar b)) (+ n 1) n)))))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 116 Fold, Unfold & Map
;; ---------------------------------------------------------------------

(define ifold
  (case-lambda
    ((kons knil il1)
     (let loop ((cur il1) (acc knil))
       (if (null? cur)
           acc
           (loop (icdr cur) (kons (icar cur) acc)))))
    ((kons knil il1 il2)
     (let loop ((a il1) (b il2) (acc knil))
       (if (or (null? a) (null? b))
           acc
           (loop (icdr a) (icdr b) (kons (icar a) (icar b) acc)))))))

(define ifold-right
  (case-lambda
    ((kons knil il1)
     (ifold kons knil (ireverse il1)))
    ((kons knil il1 il2)
     (let loop ((a il1) (b il2) (acc '()))
       (if (or (null? a) (null? b))
           (let rloop ((ps acc) (res knil))
             (if (null? ps)
                 res
                 (rloop (cdr ps) (kons (caar ps) (cdar ps) res))))
           (loop (icdr a) (icdr b) (cons (cons (icar a) (icar b)) acc)))))))

(define (ipair-fold kons knil il)
  (let loop ((cur il) (acc knil))
    (if (null? cur)
        acc
        (let ((tail (icdr cur)))
          (loop tail (kons cur acc))))))

(define (ipair-fold-right kons knil il)
  (if (null? il)
      knil
      (kons il (ipair-fold-right kons knil (icdr il)))))

(define (ireduce f ridentity il)
  (if (null? il)
      ridentity
      (ifold f (icar il) (icdr il))))

(define (ireduce-right f ridentity il)
  (if (null? il)
      ridentity
      (let loop ((cur il))
        (if (null? (icdr cur))
            (icar cur)
            (f (icar cur) (loop (icdr cur)))))))

(define iunfold
  (case-lambda
    ((p f g seed)
     (let loop ((s seed) (acc '()))
       (if (p s)
           (ireverse acc)
           (loop (g s) (ipair (f s) acc)))))
    ((p f g seed tail-gen)
     (let loop ((s seed) (acc '()))
       (if (p s)
           (iappend-reverse acc (tail-gen s))
           (loop (g s) (ipair (f s) acc)))))))

(define iunfold-right
  (case-lambda
    ((p f g seed)
     (iunfold-right p f g seed '()))
    ((p f g seed tail)
     (let loop ((s seed) (acc tail))
       (if (p s)
           acc
           (loop (g s) (ipair (f s) acc)))))))

(define imap
  (case-lambda
    ((proc il1)
     (let loop ((cur il1) (acc '()))
       (if (null? cur)
           (ireverse acc)
           (loop (icdr cur) (ipair (proc (icar cur)) acc)))))
    ((proc il1 il2)
     (let loop ((a il1) (b il2) (acc '()))
       (if (or (null? a) (null? b))
           (ireverse acc)
           (loop (icdr a) (icdr b) (ipair (proc (icar a) (icar b)) acc)))))))

(define imap-in-order imap)

(define ifor-each
  (case-lambda
    ((proc il1)
     (let loop ((cur il1))
       (if (not (null? cur))
           (begin
             (proc (icar cur))
             (loop (icdr cur))))))
    ((proc il1 il2)
     (let loop ((a il1) (b il2))
       (if (and (not (null? a)) (not (null? b)))
           (begin
             (proc (icar a) (icar b))
             (loop (icdr a) (icdr b))))))))

(define (ipair-for-each proc il)
  (let loop ((cur il))
    (if (not (null? cur))
        (begin
          (proc cur)
          (loop (icdr cur))))))

(define iappend-map
  (case-lambda
    ((proc il1)
     (iconcatenate (imap proc il1)))
    ((proc il1 il2)
     (iconcatenate (imap proc il1 il2)))))

(define ifilter-map
  (case-lambda
    ((proc il1)
     (let loop ((cur il1) (acc '()))
       (if (null? cur)
           (ireverse acc)
           (let ((res (proc (icar cur))))
             (loop (icdr cur) (if res (ipair res acc) acc))))))
    ((proc il1 il2)
     (let loop ((a il1) (b il2) (acc '()))
       (if (or (null? a) (null? b))
           (ireverse acc)
           (let ((res (proc (icar a) (icar b))))
             (loop (icdr a) (icdr b) (if res (ipair res acc) acc))))))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 116 Filtering, Partitioning, Searching & Deletion
;; ---------------------------------------------------------------------

(define (ifilter pred il)
  (let loop ((cur il) (acc '()))
    (if (null? cur)
        (ireverse acc)
        (loop (icdr cur)
              (if (pred (icar cur))
                  (ipair (icar cur) acc)
                  acc)))))

(define (iremove pred il)
  (let loop ((cur il) (acc '()))
    (if (null? cur)
        (ireverse acc)
        (loop (icdr cur)
              (if (pred (icar cur))
                  acc
                  (ipair (icar cur) acc))))))

(define (ipartition pred il)
  (let loop ((cur il) (in-acc '()) (out-acc '()))
    (if (null? cur)
        (values (ireverse in-acc) (ireverse out-acc))
        (if (pred (icar cur))
            (loop (icdr cur) (ipair (icar cur) in-acc) out-acc)
            (loop (icdr cur) in-acc (ipair (icar cur) out-acc))))))

(define (ifind-tail pred il)
  (let loop ((cur il))
    (cond
      ((null? cur) #f)
      ((pred (icar cur)) cur)
      (else (loop (icdr cur))))))

(define (ifind pred il)
  (let ((tail (ifind-tail pred il)))
    (if tail (icar tail) #f)))

(define (itake-while pred il)
  (let loop ((cur il) (acc '()))
    (if (or (null? cur) (not (pred (icar cur))))
        (ireverse acc)
        (loop (icdr cur) (ipair (icar cur) acc)))))

(define (idrop-while pred il)
  (let loop ((cur il))
    (if (or (null? cur) (not (pred (icar cur))))
        cur
        (loop (icdr cur)))))

(define (ispan pred il)
  (values (itake-while pred il) (idrop-while pred il)))

(define (ibreak pred il)
  (let ((not-pred (lambda (x) (not (pred x)))))
    (values (itake-while not-pred il) (idrop-while not-pred il))))

(define iany
  (case-lambda
    ((pred il1)
     (let loop ((cur il1))
       (if (null? cur)
           #f
           (let ((res (pred (icar cur))))
             (if res res (loop (icdr cur)))))))
    ((pred il1 il2)
     (let loop ((a il1) (b il2))
       (if (or (null? a) (null? b))
           #f
           (let ((res (pred (icar a) (icar b))))
             (if res res (loop (icdr a) (icdr b)))))))))

(define ievery
  (case-lambda
    ((pred il1)
     (let loop ((cur il1) (last #t))
       (if (null? cur)
           last
           (let ((res (pred (icar cur))))
             (if res (loop (icdr cur) res) #f)))))
    ((pred il1 il2)
     (let loop ((a il1) (b il2) (last #t))
       (if (or (null? a) (null? b))
           last
           (let ((res (pred (icar a) (icar b))))
             (if res (loop (icdr a) (icdr b) res) #f)))))))

(define ilist-index
  (case-lambda
    ((pred il1)
     (let loop ((cur il1) (i 0))
       (cond
         ((null? cur) #f)
         ((pred (icar cur)) i)
         (else (loop (icdr cur) (+ i 1))))))
    ((pred il1 il2)
     (let loop ((a il1) (b il2) (i 0))
       (cond
         ((or (null? a) (null? b)) #f)
         ((pred (icar a) (icar b)) i)
         (else (loop (icdr a) (icdr b) (+ i 1))))))))

(define (%imember-core x il elt=)
  (let loop ((cur il))
    (cond
      ((null? cur) #f)
      ((elt= x (icar cur)) cur)
      (else (loop (icdr cur))))))

(define imember
  (case-lambda
    ((x il) (%imember-core x il equal?))
    ((x il elt=) (%imember-core x il elt=))))

(define (imemq x il) (%imember-core x il (lambda (a b) (eq? a b))))
(define (imemv x il) (%imember-core x il (lambda (a b) (eqv? a b))))

(define (%idelete-core x il elt=)
  (let loop ((cur il) (acc '()))
    (if (null? cur)
        (ireverse acc)
        (if (elt= x (icar cur))
            (loop (icdr cur) acc)
            (loop (icdr cur) (ipair (icar cur) acc))))))

(define idelete
  (case-lambda
    ((x il) (%idelete-core x il equal?))
    ((x il elt=) (%idelete-core x il elt=))))

(define (%idelete-dups-core il elt=)
  (let loop ((cur il) (acc '()))
    (if (null? cur)
        (ireverse acc)
        (let ((x (icar cur)))
          (if (%imember-core x acc elt=)
              (loop (icdr cur) acc)
              (loop (icdr cur) (ipair x acc)))))))

(define idelete-duplicates
  (case-lambda
    ((il) (%idelete-dups-core il equal?))
    ((il elt=) (%idelete-dups-core il elt=))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 116 Immutable Association Lists
;; ---------------------------------------------------------------------

(define (%iassoc-core key ialist elt=)
  (let loop ((cur ialist))
    (cond
      ((null? cur) #f)
      ((elt= key (icaar cur)) (icar cur))
      (else (loop (icdr cur))))))

(define iassoc
  (case-lambda
    ((key ialist) (%iassoc-core key ialist equal?))
    ((key ialist elt=) (%iassoc-core key ialist elt=))))

(define (iassq key ialist) (%iassoc-core key ialist (lambda (a b) (eq? a b))))
(define (iassv key ialist) (%iassoc-core key ialist (lambda (a b) (eqv? a b))))

(define (ialist-cons key datum ialist)
  (ipair (ipair key datum) ialist))

(define (%ialist-delete-core key ialist elt=)
  (let loop ((cur ialist) (acc '()))
    (if (null? cur)
        (ireverse acc)
        (if (elt= key (icaar cur))
            (loop (icdr cur) acc)
            (loop (icdr cur) (ipair (icar cur) acc))))))

(define ialist-delete
  (case-lambda
    ((key ialist) (%ialist-delete-core key ialist equal?))
    ((key ialist elt=) (%ialist-delete-core key ialist elt=))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 116 Conversion & Comparators
;; ---------------------------------------------------------------------

(define (pair->ipair p) (ipair (car p) (cdr p)))
(define (ipair->pair ip) (cons (icar ip) (icdr ip)))

(define (tree->itree obj)
  (if (pair? obj)
      (ipair (tree->itree (car obj)) (tree->itree (cdr obj)))
      obj))

(define (itree->tree obj)
  (if (ipair? obj)
      (cons (itree->tree (icar obj)) (itree->tree (icdr obj)))
      obj))

(define (gtree->itree obj)
  (cond
    ((pair? obj) (ipair (gtree->itree (car obj)) (gtree->itree (cdr obj))))
    ((ipair? obj) (ipair (gtree->itree (icar obj)) (gtree->itree (icdr obj))))
    (else obj)))

(define (gtree->tree obj)
  (cond
    ((pair? obj) (cons (gtree->tree (car obj)) (gtree->tree (cdr obj))))
    ((ipair? obj) (cons (gtree->tree (icar obj)) (gtree->tree (icdr obj))))
    (else obj)))

(define iapply
  (case-lambda
    ((proc ilst)
     (apply proc (ilist->list ilst)))
    ((proc a ilst)
     (apply proc (cons a (ilist->list ilst))))
    ((proc a b ilst)
     (apply proc (cons a (cons b (ilist->list ilst)))))))

(define (make-icar-comparator comp)
  (make-comparator
    ipair?
    (lambda (a b) (=? comp (icar a) (icar b)))
    (if (comparator-ordered? comp)
        (lambda (a b) (<? comp (icar a) (icar b)))
        #f)
    (if (comparator-hashable? comp)
        (lambda (x) (comparator-hash comp (icar x)))
        #f)))

(define (make-icdr-comparator comp)
  (make-comparator
    ipair?
    (lambda (a b) (=? comp (icdr a) (icdr b)))
    (if (comparator-ordered? comp)
        (lambda (a b) (<? comp (icdr a) (icdr b)))
        #f)
    (if (comparator-hashable? comp)
        (lambda (x) (comparator-hash comp (icdr x)))
        #f)))

(define (make-ipair-comparator car-comp cdr-comp)
  (make-comparator
    ipair?
    (lambda (a b)
      (and (=? car-comp (icar a) (icar b))
           (=? cdr-comp (icdr a) (icdr b))))
    (if (and (comparator-ordered? car-comp) (comparator-ordered? cdr-comp))
        (lambda (a b)
          (cond
            ((<? car-comp (icar a) (icar b)) #t)
            ((>? car-comp (icar a) (icar b)) #f)
            (else (<? cdr-comp (icdr a) (icdr b)))))
        #f)
    (if (and (comparator-hashable? car-comp) (comparator-hashable? cdr-comp))
        (lambda (x)
          (modulo (+ (* (comparator-hash car-comp (icar x)) 31)
                     (comparator-hash cdr-comp (icdr x)))
                  536870911))
        #f)))

(define (make-ilist-comparator elem-comp)
  (make-comparator
    proper-ilist?
    (lambda (a b) (%ilist=-2 (lambda (x y) (=? elem-comp x y)) a b))
    (if (comparator-ordered? elem-comp)
        (lambda (a b)
          (let loop ((x a) (y b))
            (cond
              ((null? y) #f)
              ((null? x) #t)
              ((<? elem-comp (icar x) (icar y)) #t)
              ((>? elem-comp (icar x) (icar y)) #f)
              (else (loop (icdr x) (icdr y))))))
        #f)
    (if (comparator-hashable? elem-comp)
        (lambda (x)
          (ifold (lambda (el h)
                   (modulo (+ (* h 33) (comparator-hash elem-comp el)) 536870911))
                 5381
                 x))
        #f)))

(define make-improper-ilist-comparator make-ilist-comparator)

(define ipair-comparator
  (make-ipair-comparator (make-default-comparator) (make-default-comparator)))

(define ilist-comparator
  (make-ilist-comparator (make-default-comparator)))
