;;; =======================================================================
;;; ULisp Standard Library: Sets and Bags (SRFI 113, R7RS-large Red Edition)
;;; Conforms to DSN-33 Architecture Specification & Issue #702
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §1. Type Definitions: <set> and <bag> Records (SRFI 113)
;; ---------------------------------------------------------------------
;; Internal entries representation:
;;   list of (element . count) pairs where count >= 1 (for <set>, count = 1)

(define-record-type <set>
  (%make-set comparator entries)
  set?
  (comparator set-element-comparator)
  (entries %set-entries %set-set-entries!))

(define-record-type <bag>
  (%make-bag comparator entries)
  bag?
  (comparator bag-element-comparator)
  (entries %bag-entries %bag-set-entries!))

;; ---------------------------------------------------------------------
;; §2. Internal Alist Entry Helpers
;; ---------------------------------------------------------------------

(define (%entries-copy entries)
  (let loop ((cur entries) (acc '()))
    (if (null? cur)
        (reverse acc)
        (let ((pair (car cur)))
          (loop (cdr cur) (cons (cons (car pair) (cdr pair)) acc))))))

(define (%entries-find comp entries elem)
  (let loop ((cur entries))
    (cond
      ((null? cur) #f)
      ((comparator-equal? comp (caar cur) elem) (car cur))
      (else (loop (cdr cur))))))

(define (%entries-adjoin-set comp entries elem)
  (comparator-check-type comp elem)
  (if (%entries-find comp entries elem)
      entries
      (cons (cons elem 1) entries)))

(define (%entries-replace comp entries elem)
  (comparator-check-type comp elem)
  (let loop ((cur entries) (acc '()))
    (cond
      ((null? cur) entries)
      ((comparator-equal? comp (caar cur) elem)
       (append (reverse acc) (cons (cons elem (cdar cur)) (cdr cur))))
      (else
       (loop (cdr cur) (cons (car cur) acc))))))

(define (%entries-delete-all comp entries elem)
  (let loop ((cur entries) (acc '()))
    (cond
      ((null? cur) (reverse acc))
      ((comparator-equal? comp (caar cur) elem)
       (append (reverse acc) (cdr cur)))
      (else
       (loop (cdr cur) (cons (car cur) acc))))))

(define (%entries-increment comp entries elem count)
  (comparator-check-type comp elem)
  (if (<= count 0)
      entries
      (let loop ((cur entries) (acc '()))
        (cond
          ((null? cur)
           (cons (cons elem count) entries))
          ((comparator-equal? comp (caar cur) elem)
           (append (reverse acc)
                   (cons (cons (caar cur) (+ (cdar cur) count))
                         (cdr cur))))
          (else
           (loop (cdr cur) (cons (car cur) acc)))))))

(define (%entries-decrement comp entries elem count)
  (if (<= count 0)
      entries
      (let loop ((cur entries) (acc '()))
        (cond
          ((null? cur) entries)
          ((comparator-equal? comp (caar cur) elem)
           (let ((new-cnt (- (cdar cur) count)))
             (if (<= new-cnt 0)
                 (append (reverse acc) (cdr cur))
                 (append (reverse acc)
                         (cons (cons (caar cur) new-cnt) (cdr cur))))))
          (else
           (loop (cdr cur) (cons (car cur) acc)))))))

;; ---------------------------------------------------------------------
;; §3. Set Constructors & Predicates (SRFI 113)
;; ---------------------------------------------------------------------

(define set
  (case-lambda
    ((comp)
     (%make-set comp '()))
    ((comp . elems)
     (list->set comp elems))))

(define (set-unfold stop? mapper successor seed comp)
  (let loop ((s seed) (entries '()))
    (if (stop? s)
        (%make-set comp (reverse entries))
        (let ((elem (mapper s)))
          (loop (successor s)
                (%entries-adjoin-set comp entries elem))))))

(define (set-contains? s elem)
  (if (%entries-find (set-element-comparator s) (%set-entries s) elem)
      #t
      #f))

(define (set-empty? s)
  (null? (%set-entries s)))

(define (set-disjoint? s1 s2)
  (let ((comp (set-element-comparator s2))
        (e2 (%set-entries s2)))
    (let loop ((cur (%set-entries s1)))
      (cond
        ((null? cur) #t)
        ((%entries-find comp e2 (caar cur)) #f)
        (else (loop (cdr cur)))))))

;; ---------------------------------------------------------------------
;; §4. Set Accessors & Updaters (SRFI 113)
;; ---------------------------------------------------------------------

(define (set-member s elem default)
  (let ((found (%entries-find (set-element-comparator s) (%set-entries s) elem)))
    (if found
        (car found)
        default)))

(define set-adjoin
  (case-lambda
    ((s) (set-copy s))
    ((s . elems)
     (let ((comp (set-element-comparator s)))
       (let loop ((es elems) (entries (%entries-copy (%set-entries s))))
         (if (null? es)
             (%make-set comp entries)
             (loop (cdr es) (%entries-adjoin-set comp entries (car es)))))))))

(define set-adjoin!
  (case-lambda
    ((s) s)
    ((s . elems)
     (let ((comp (set-element-comparator s)))
       (let loop ((es elems) (entries (%set-entries s)))
         (if (null? es)
             (begin
               (%set-set-entries! s entries)
               s)
             (loop (cdr es) (%entries-adjoin-set comp entries (car es)))))))))

(define (set-replace s elem)
  (%make-set (set-element-comparator s)
             (%entries-replace (set-element-comparator s)
                               (%entries-copy (%set-entries s))
                               elem)))

(define (set-replace! s elem)
  (%set-set-entries! s (%entries-replace (set-element-comparator s)
                                         (%set-entries s)
                                         elem))
  s)

(define set-delete
  (case-lambda
    ((s) (set-copy s))
    ((s . elems)
     (set-delete-all s elems))))

(define set-delete!
  (case-lambda
    ((s) s)
    ((s . elems)
     (set-delete-all! s elems))))

(define (set-delete-all s elem-list)
  (let ((comp (set-element-comparator s)))
    (let loop ((es elem-list) (entries (%entries-copy (%set-entries s))))
      (if (null? es)
          (%make-set comp entries)
          (loop (cdr es) (%entries-delete-all comp entries (car es)))))))

(define (set-delete-all! s elem-list)
  (let ((comp (set-element-comparator s)))
    (let loop ((es elem-list) (entries (%set-entries s)))
      (if (null? es)
          (begin
            (%set-set-entries! s entries)
            s)
          (loop (cdr es) (%entries-delete-all comp entries (car es)))))))

(define (set-search! s elem failure success)
  (let* ((comp (set-element-comparator s))
         (entries (%set-entries s))
         (found (%entries-find comp entries elem)))
    (if found
        (success (car found)
                 (lambda (new-elem obj)
                   (comparator-check-type comp new-elem)
                   (%set-set-entries! s (%entries-replace comp (%entries-delete-all comp entries elem) new-elem))
                   (values s obj))
                 (lambda (obj)
                   (%set-set-entries! s (%entries-delete-all comp entries elem))
                   (values s obj)))
        (failure (lambda (obj)
                   (comparator-check-type comp elem)
                   (%set-set-entries! s (cons (cons elem 1) entries))
                   (values s obj))
                 (lambda (obj)
                   (values s obj))))))

;; ---------------------------------------------------------------------
;; §5. Whole Set Operations & Higher-Order Iterators (SRFI 113)
;; ---------------------------------------------------------------------

(define (set-size s)
  (length (%set-entries s)))

(define (set-find pred s failure)
  (let loop ((cur (%set-entries s)))
    (cond
      ((null? cur) (failure))
      ((pred (caar cur)) (caar cur))
      (else (loop (cdr cur))))))

(define (set-count pred s)
  (let loop ((cur (%set-entries s)) (cnt 0))
    (cond
      ((null? cur) cnt)
      ((pred (caar cur)) (loop (cdr cur) (+ cnt 1)))
      (else (loop (cdr cur) cnt)))))

(define (set-any? pred s)
  (let loop ((cur (%set-entries s)))
    (cond
      ((null? cur) #f)
      ((pred (caar cur)) #t)
      (else (loop (cdr cur))))))

(define (set-every? pred s)
  (let loop ((cur (%set-entries s)))
    (cond
      ((null? cur) #t)
      ((pred (caar cur)) (loop (cdr cur)))
      (else #f))))

(define (set-map comp proc s)
  (let loop ((cur (%set-entries s)) (entries '()))
    (if (null? cur)
        (%make-set comp (reverse entries))
        (loop (cdr cur)
              (%entries-adjoin-set comp entries (proc (caar cur)))))))

(define (set-for-each proc s)
  (let loop ((cur (%set-entries s)))
    (if (null? cur)
        #t
        (begin
          (proc (caar cur))
          (loop (cdr cur))))))

(define (set-fold proc nil s)
  (let loop ((cur (%set-entries s)) (acc nil))
    (if (null? cur)
        acc
        (loop (cdr cur) (proc (caar cur) acc)))))

(define (set-filter pred s)
  (let ((comp (set-element-comparator s)))
    (let loop ((cur (%set-entries s)) (acc '()))
      (cond
        ((null? cur) (%make-set comp (reverse acc)))
        ((pred (caar cur)) (loop (cdr cur) (cons (car cur) acc)))
        (else (loop (cdr cur) acc))))))

(define (set-filter! pred s)
  (let ((filtered (set-filter pred s)))
    (%set-set-entries! s (%set-entries filtered))
    s))

(define (set-remove pred s)
  (set-filter (lambda (x) (not (pred x))) s))

(define (set-remove! pred s)
  (set-filter! (lambda (x) (not (pred x))) s))

(define (set-partition pred s)
  (let ((comp (set-element-comparator s)))
    (let loop ((cur (%set-entries s)) (yes '()) (no '()))
      (cond
        ((null? cur)
         (values (%make-set comp (reverse yes))
                 (%make-set comp (reverse no))))
        ((pred (caar cur))
         (loop (cdr cur) (cons (car cur) yes) no))
        (else
         (loop (cdr cur) yes (cons (car cur) no)))))))

(define (set-partition! pred s)
  (call-with-values
    (lambda () (set-partition pred s))
    (lambda (yes-set no-set)
      (%set-set-entries! s (%set-entries yes-set))
      (values s no-set))))

;; ---------------------------------------------------------------------
;; §6. Set Copying & Conversion (SRFI 113)
;; ---------------------------------------------------------------------

(define (set-copy s)
  (%make-set (set-element-comparator s)
             (%entries-copy (%set-entries s))))

(define (set->list s)
  (map (lambda (p) (car p)) (%set-entries s)))

(define (list->set comp lst)
  (let loop ((cur lst) (entries '()))
    (if (null? cur)
        (%make-set comp (reverse entries))
        (loop (cdr cur) (%entries-adjoin-set comp entries (car cur))))))

(define (list->set! s lst)
  (let ((comp (set-element-comparator s)))
    (let loop ((cur lst) (entries (%set-entries s)))
      (if (null? cur)
          (begin
            (%set-set-entries! s entries)
            s)
          (loop (cdr cur) (%entries-adjoin-set comp entries (car cur)))))))

;; ---------------------------------------------------------------------
;; §7. Set Subsets & Set Algebra (SRFI 113)
;; ---------------------------------------------------------------------

(define (%set-subset-2? s1 s2)
  (and (<= (set-size s1) (set-size s2))
       (set-every? (lambda (x) (set-contains? s2 x)) s1)))

(define (%set-equal-2? s1 s2)
  (and (= (set-size s1) (set-size s2))
       (%set-subset-2? s1 s2)))

(define (%set-proper-subset-2? s1 s2)
  (and (< (set-size s1) (set-size s2))
       (%set-subset-2? s1 s2)))

(define (%set-cmp-chain pred a b rest)
  (if (not (pred a b))
      #f
      (let loop ((prev b) (cur rest))
        (if (null? cur)
            #t
            (if (pred prev (car cur))
                (loop (car cur) (cdr cur))
                #f)))))

(define set=?
  (case-lambda
    ((s1 s2) (%set-equal-2? s1 s2))
    ((s1 s2 . rest) (%set-cmp-chain %set-equal-2? s1 s2 rest))))

(define set<?
  (case-lambda
    ((s1 s2) (%set-proper-subset-2? s1 s2))
    ((s1 s2 . rest) (%set-cmp-chain %set-proper-subset-2? s1 s2 rest))))

(define set>?
  (case-lambda
    ((s1 s2) (%set-proper-subset-2? s2 s1))
    ((s1 s2 . rest)
     (%set-cmp-chain (lambda (a b) (%set-proper-subset-2? b a)) s1 s2 rest))))

(define set<=?
  (case-lambda
    ((s1 s2) (%set-subset-2? s1 s2))
    ((s1 s2 . rest) (%set-cmp-chain %set-subset-2? s1 s2 rest))))

(define set>=?
  (case-lambda
    ((s1 s2) (%set-subset-2? s2 s1))
    ((s1 s2 . rest)
     (%set-cmp-chain (lambda (a b) (%set-subset-2? b a)) s1 s2 rest))))

(define set-union
  (case-lambda
    ((s1) (set-copy s1))
    ((s1 . rest)
     (let ((res (set-copy s1)))
       (let loop ((rs rest))
         (if (null? rs)
             res
             (begin
               (set-for-each (lambda (x) (set-adjoin! res x)) (car rs))
               (loop (cdr rs)))))))))

(define set-union!
  (case-lambda
    ((s1) s1)
    ((s1 . rest)
     (let loop ((rs rest))
       (if (null? rs)
           s1
           (begin
             (set-for-each (lambda (x) (set-adjoin! s1 x)) (car rs))
             (loop (cdr rs))))))))

(define set-intersection
  (case-lambda
    ((s1) (set-copy s1))
    ((s1 . rest)
     (set-filter
      (lambda (x)
        (let loop ((rs rest))
          (cond
            ((null? rs) #t)
            ((set-contains? (car rs) x) (loop (cdr rs)))
            (else #f))))
      s1))))

(define set-intersection!
  (case-lambda
    ((s1) s1)
    ((s1 . rest)
     (let ((inter (apply set-intersection (cons s1 rest))))
       (%set-set-entries! s1 (%set-entries inter))
       s1))))

(define set-difference
  (case-lambda
    ((s1) (set-copy s1))
    ((s1 . rest)
     (set-filter
      (lambda (x)
        (let loop ((rs rest))
          (cond
            ((null? rs) #t)
            ((set-contains? (car rs) x) #f)
            (else (loop (cdr rs))))))
      s1))))

(define set-difference!
  (case-lambda
    ((s1) s1)
    ((s1 . rest)
     (let ((diff (apply set-difference (cons s1 rest))))
       (%set-set-entries! s1 (%set-entries diff))
       s1))))

(define (set-xor s1 s2)
  (set-union (set-difference s1 s2)
             (set-difference s2 s1)))

(define (set-xor! s1 s2)
  (let ((x (set-xor s1 s2)))
    (%set-set-entries! s1 (%set-entries x))
    s1))

;; ---------------------------------------------------------------------
;; §8. Bag (Multiset) Constructors, Predicates & Operations (SRFI 113)
;; ---------------------------------------------------------------------

(define bag
  (case-lambda
    ((comp)
     (%make-bag comp '()))
    ((comp . elems)
     (list->bag comp elems))))

(define (bag-unfold stop? mapper successor seed comp)
  (let loop ((s seed) (entries '()))
    (if (stop? s)
        (%make-bag comp (reverse entries))
        (let ((elem (mapper s)))
          (loop (successor s)
                (%entries-increment comp entries elem 1))))))

(define (bag-contains? b elem)
  (if (%entries-find (bag-element-comparator b) (%bag-entries b) elem)
      #t
      #f))

(define (bag-empty? b)
  (null? (%bag-entries b)))

(define (bag-disjoint? b1 b2)
  (let ((comp (bag-element-comparator b2))
        (e2 (%bag-entries b2)))
    (let loop ((cur (%bag-entries b1)))
      (cond
        ((null? cur) #t)
        ((%entries-find comp e2 (caar cur)) #f)
        (else (loop (cdr cur)))))))

(define (bag-member b elem default)
  (let ((found (%entries-find (bag-element-comparator b) (%bag-entries b) elem)))
    (if found
        (car found)
        default)))

(define (bag-element-count b elem)
  (let ((found (%entries-find (bag-element-comparator b) (%bag-entries b) elem)))
    (if found
        (cdr found)
        0)))

(define (bag-increment! b elem count)
  (%bag-set-entries! b (%entries-increment (bag-element-comparator b)
                                           (%bag-entries b)
                                           elem
                                           count))
  b)

(define (bag-decrement! b elem count)
  (%bag-set-entries! b (%entries-decrement (bag-element-comparator b)
                                           (%bag-entries b)
                                           elem
                                           count))
  b)

(define bag-adjoin
  (case-lambda
    ((b) (bag-copy b))
    ((b . elems)
     (let ((res (bag-copy b)))
       (let loop ((es elems))
         (if (null? es)
             res
             (begin
               (bag-increment! res (car es) 1)
               (loop (cdr es)))))))))

(define bag-adjoin!
  (case-lambda
    ((b) b)
    ((b . elems)
     (let loop ((es elems))
       (if (null? es)
           b
           (begin
             (bag-increment! b (car es) 1)
             (loop (cdr es))))))))

(define (bag-replace b elem)
  (%make-bag (bag-element-comparator b)
             (%entries-replace (bag-element-comparator b)
                               (%entries-copy (%bag-entries b))
                               elem)))

(define (bag-replace! b elem)
  (%bag-set-entries! b (%entries-replace (bag-element-comparator b)
                                         (%bag-entries b)
                                         elem))
  b)

(define bag-delete
  (case-lambda
    ((b) (bag-copy b))
    ((b . elems)
     (let ((res (bag-copy b)))
       (let loop ((es elems))
         (if (null? es)
             res
             (begin
               (bag-decrement! res (car es) 1)
               (loop (cdr es)))))))))

(define bag-delete!
  (case-lambda
    ((b) b)
    ((b . elems)
     (let loop ((es elems))
       (if (null? es)
           b
           (begin
             (bag-decrement! b (car es) 1)
             (loop (cdr es))))))))

(define (bag-delete-all b elem-list)
  (let ((res (bag-copy b)))
    (bag-delete-all! res elem-list)))

(define (bag-delete-all! b elem-list)
  (let ((comp (bag-element-comparator b)))
    (let loop ((es elem-list) (entries (%bag-entries b)))
      (if (null? es)
          (begin
            (%bag-set-entries! b entries)
            b)
          (loop (cdr es) (%entries-delete-all comp entries (car es)))))))

(define (bag-search! b elem failure success)
  (let* ((comp (bag-element-comparator b))
         (entries (%bag-entries b))
         (found (%entries-find comp entries elem)))
    (if found
        (success (car found)
                 (lambda (new-elem obj)
                   (comparator-check-type comp new-elem)
                   (%bag-set-entries! b (%entries-replace comp entries new-elem))
                   (values b obj))
                 (lambda (obj)
                   (bag-decrement! b elem 1)
                   (values b obj)))
        (failure (lambda (obj)
                   (bag-increment! b elem 1)
                   (values b obj))
                 (lambda (obj)
                   (values b obj))))))

(define (bag-size b)
  (let loop ((cur (%bag-entries b)) (sum 0))
    (if (null? cur)
        sum
        (loop (cdr cur) (+ sum (cdar cur))))))

(define (bag-unique-size b)
  (length (%bag-entries b)))

(define (bag-find pred b failure)
  (let loop ((cur (%bag-entries b)))
    (cond
      ((null? cur) (failure))
      ((pred (caar cur)) (caar cur))
      (else (loop (cdr cur))))))

(define (bag-count pred b)
  (let loop ((cur (%bag-entries b)) (cnt 0))
    (cond
      ((null? cur) cnt)
      ((pred (caar cur)) (loop (cdr cur) (+ cnt (cdar cur))))
      (else (loop (cdr cur) cnt)))))

(define (bag-any? pred b)
  (let loop ((cur (%bag-entries b)))
    (cond
      ((null? cur) #f)
      ((pred (caar cur)) #t)
      (else (loop (cdr cur))))))

(define (bag-every? pred b)
  (let loop ((cur (%bag-entries b)))
    (cond
      ((null? cur) #t)
      ((pred (caar cur)) (loop (cdr cur)))
      (else #f))))

(define (bag-map comp proc b)
  (let ((res (bag comp)))
    (bag-for-each-unique
     (lambda (elem cnt)
       (bag-increment! res (proc elem) cnt))
     b)
    res))

(define (bag-for-each proc b)
  (let loop ((cur (%bag-entries b)))
    (if (null? cur)
        #t
        (let ((elem (caar cur))
              (cnt (cdar cur)))
          (let rpt ((i 0))
            (if (< i cnt)
                (begin
                  (proc elem)
                  (rpt (+ i 1)))
                (loop (cdr cur))))))))

(define (bag-for-each-unique proc b)
  (let loop ((cur (%bag-entries b)))
    (if (null? cur)
        #t
        (begin
          (proc (caar cur) (cdar cur))
          (loop (cdr cur))))))

(define (bag-fold proc nil b)
  (let loop ((cur (%bag-entries b)) (acc nil))
    (if (null? cur)
        acc
        (let ((elem (caar cur))
              (cnt (cdar cur)))
          (let rpt ((i 0) (a acc))
            (if (< i cnt)
                (rpt (+ i 1) (proc elem a))
                (loop (cdr cur) a)))))))

(define (bag-fold-unique proc nil b)
  (let loop ((cur (%bag-entries b)) (acc nil))
    (if (null? cur)
        acc
        (loop (cdr cur) (proc (caar cur) (cdar cur) acc)))))

(define (bag-filter pred b)
  (let ((comp (bag-element-comparator b)))
    (let loop ((cur (%bag-entries b)) (acc '()))
      (cond
        ((null? cur) (%make-bag comp (reverse acc)))
        ((pred (caar cur)) (loop (cdr cur) (cons (cons (caar cur) (cdar cur)) acc)))
        (else (loop (cdr cur) acc))))))

(define (bag-filter! pred b)
  (let ((filtered (bag-filter pred b)))
    (%bag-set-entries! b (%bag-entries filtered))
    b))

(define (bag-remove pred b)
  (bag-filter (lambda (x) (not (pred x))) b))

(define (bag-remove! pred b)
  (bag-filter! (lambda (x) (not (pred x))) b))

(define (bag-partition pred b)
  (let ((comp (bag-element-comparator b)))
    (let loop ((cur (%bag-entries b)) (yes '()) (no '()))
      (cond
        ((null? cur)
         (values (%make-bag comp (reverse yes))
                 (%make-bag comp (reverse no))))
        ((pred (caar cur))
         (loop (cdr cur) (cons (cons (caar cur) (cdar cur)) yes) no))
        (else
         (loop (cdr cur) yes (cons (cons (caar cur) (cdar cur)) no)))))))

(define (bag-partition! pred b)
  (call-with-values
    (lambda () (bag-partition pred b))
    (lambda (yes-bag no-bag)
      (%bag-set-entries! b (%bag-entries yes-bag))
      (values b no-bag))))

(define (bag-copy b)
  (%make-bag (bag-element-comparator b)
             (%entries-copy (%bag-entries b))))

(define (bag->list b)
  (reverse (bag-fold (lambda (x acc) (cons x acc)) '() b)))

(define (list->bag comp lst)
  (let ((res (bag comp)))
    (list->bag! res lst)))

(define (list->bag! b lst)
  (let loop ((cur lst))
    (if (null? cur)
        b
        (begin
          (bag-increment! b (car cur) 1)
          (loop (cdr cur))))))

(define (bag->set b)
  (let ((comp (bag-element-comparator b)))
    (%make-set comp
               (map (lambda (p) (cons (car p) 1))
                    (%bag-entries b)))))

(define (set->bag s)
  (%make-bag (set-element-comparator s)
             (%entries-copy (%set-entries s))))

(define (set->bag! b s)
  (set-for-each (lambda (x) (bag-increment! b x 1)) s)
  b)

(define (bag->alist b)
  (%entries-copy (%bag-entries b)))

(define (alist->bag comp alist)
  (let ((res (bag comp)))
    (let loop ((cur alist))
      (if (null? cur)
          res
          (begin
            (bag-increment! res (caar cur) (cdar cur))
            (loop (cdr cur)))))))

;; ---------------------------------------------------------------------
;; §9. Bag Subbags & Bag Algebra (SRFI 113)
;; ---------------------------------------------------------------------

(define (%bag-subbag-2? b1 b2)
  (and (<= (bag-unique-size b1) (bag-unique-size b2))
       (let loop ((cur (%bag-entries b1)))
         (cond
           ((null? cur) #t)
           ((<= (cdar cur) (bag-element-count b2 (caar cur)))
            (loop (cdr cur)))
           (else #f)))))

(define (%bag-equal-2? b1 b2)
  (and (= (bag-unique-size b1) (bag-unique-size b2))
       (%bag-subbag-2? b1 b2)))

(define (%bag-proper-subbag-2? b1 b2)
  (and (%bag-subbag-2? b1 b2)
       (< (bag-size b1) (bag-size b2))))

(define bag=?
  (case-lambda
    ((b1 b2) (%bag-equal-2? b1 b2))
    ((b1 b2 . rest) (%set-cmp-chain %bag-equal-2? b1 b2 rest))))

(define bag<?
  (case-lambda
    ((b1 b2) (%bag-proper-subbag-2? b1 b2))
    ((b1 b2 . rest) (%set-cmp-chain %bag-proper-subbag-2? b1 b2 rest))))

(define bag>?
  (case-lambda
    ((b1 b2) (%bag-proper-subbag-2? b2 b1))
    ((b1 b2 . rest)
     (%set-cmp-chain (lambda (a b) (%bag-proper-subbag-2? b a)) b1 b2 rest))))

(define bag<=?
  (case-lambda
    ((b1 b2) (%bag-subbag-2? b1 b2))
    ((b1 b2 . rest) (%set-cmp-chain %bag-subbag-2? b1 b2 rest))))

(define bag>=?
  (case-lambda
    ((b1 b2) (%bag-subbag-2? b2 b1))
    ((b1 b2 . rest)
     (%set-cmp-chain (lambda (a b) (%bag-subbag-2? b a)) b1 b2 rest))))

(define bag-union
  (case-lambda
    ((b1) (bag-copy b1))
    ((b1 . rest)
     (let ((res (bag-copy b1)))
       (apply bag-union! (cons res rest))))))

(define bag-union!
  (case-lambda
    ((b1) b1)
    ((b1 . rest)
     (let loop ((rs rest))
       (if (null? rs)
           b1
           (begin
             (bag-for-each-unique
              (lambda (elem cnt)
                (let ((cur-cnt (bag-element-count b1 elem)))
                  (if (> cnt cur-cnt)
                      (bag-increment! b1 elem (- cnt cur-cnt))
                      #t)))
              (car rs))
             (loop (cdr rs))))))))

(define bag-intersection
  (case-lambda
    ((b1) (bag-copy b1))
    ((b1 . rest)
     (let ((res (bag (bag-element-comparator b1))))
       (bag-for-each-unique
        (lambda (elem cnt)
          (let loop ((rs rest) (min-cnt cnt))
            (if (or (null? rs) (<= min-cnt 0))
                (if (> min-cnt 0)
                    (bag-increment! res elem min-cnt)
                    #t)
                (let ((c2 (bag-element-count (car rs) elem)))
                  (loop (cdr rs) (if (< c2 min-cnt) c2 min-cnt))))))
        b1)
       res))))

(define bag-intersection!
  (case-lambda
    ((b1) b1)
    ((b1 . rest)
     (let ((inter (apply bag-intersection (cons b1 rest))))
       (%bag-set-entries! b1 (%bag-entries inter))
       b1))))

(define bag-difference
  (case-lambda
    ((b1) (bag-copy b1))
    ((b1 . rest)
     (let ((res (bag-copy b1)))
       (apply bag-difference! (cons res rest))))))

(define bag-difference!
  (case-lambda
    ((b1) b1)
    ((b1 . rest)
     (let loop ((rs rest))
       (if (null? rs)
           b1
           (begin
             (bag-for-each-unique
              (lambda (elem cnt)
                (bag-decrement! b1 elem cnt))
              (car rs))
             (loop (cdr rs))))))))

(define (bag-xor b1 b2)
  (bag-sum (bag-difference b1 b2)
           (bag-difference b2 b1)))

(define (bag-xor! b1 b2)
  (let ((x (bag-xor b1 b2)))
    (%bag-set-entries! b1 (%bag-entries x))
    b1))

(define bag-sum
  (case-lambda
    ((b1) (bag-copy b1))
    ((b1 . rest)
     (let ((res (bag-copy b1)))
       (apply bag-sum! (cons res rest))))))

(define bag-sum!
  (case-lambda
    ((b1) b1)
    ((b1 . rest)
     (let loop ((rs rest))
       (if (null? rs)
           b1
           (begin
             (bag-for-each-unique
              (lambda (elem cnt)
                (bag-increment! b1 elem cnt))
              (car rs))
             (loop (cdr rs))))))))

(define (bag-product n b)
  (let ((res (bag (bag-element-comparator b))))
    (if (<= n 0)
        res
        (begin
          (bag-for-each-unique
           (lambda (elem cnt)
             (bag-increment! res elem (* cnt n)))
           b)
          res))))

(define (bag-product! n b)
  (let ((prod (bag-product n b)))
    (%bag-set-entries! b (%bag-entries prod))
    b))

