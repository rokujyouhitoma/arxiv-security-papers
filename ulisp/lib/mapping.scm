;;; =======================================================================
;;; ULisp Standard Library: Immutable Mappings — R7RS-large Tangerine / SRFI 146
;;; Specification: (scheme mapping), (scheme mapping hash), (srfi 146), (srfi 146 hash)
;;; Conforms to DSN-33 Architecture Specification & Issue #709
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §2.2 / SRFI 146 Internal Representation:
;;   #(ulisp-map-tag <kind: 'ordered | 'hash> <comparator> <entries>)
;; ---------------------------------------------------------------------

(define (%make-raw-map kind comp entries)
  (let ((v (make-vector 4 #f)))
    (vector-set! v 0 'ulisp-map-tag)
    (vector-set! v 1 kind)
    (vector-set! v 2 comp)
    (vector-set! v 3 entries)
    v))

(define (%raw-map? obj)
  (and (vector? obj)
       (= (vector-length obj) 4)
       (eq? (vector-ref obj 0) 'ulisp-map-tag)))

(define (%map-kind m) (vector-ref m 1))
(define (%map-comp m) (vector-ref m 2))
(define (%map-entries m) (vector-ref m 3))

(define (mapping? obj)
  (and (%raw-map? obj) (eq? (%map-kind obj) 'ordered)))

(define (hashmap? obj)
  (and (%raw-map? obj) (eq? (%map-kind obj) 'hash)))

(define (mapping-key-comparator m) (%map-comp m))
(define (hashmap-key-comparator hm) (%map-comp hm))

;; ---------------------------------------------------------------------
;; §2.2 / SRFI 146 Internal Alist Entry Helpers
;; ---------------------------------------------------------------------

(define (%map-entry-find kind comp entries key)
  (let ((ordered? (eq? kind 'ordered)))
    (let loop ((cur entries))
      (cond
        ((null? cur) #f)
        ((=? comp key (caar cur)) (car cur))
        ((and ordered? (<? comp key (caar cur))) #f)
        (else (loop (cdr cur)))))))

(define (%map-entry-adjoin kind comp entries key val)
  (comparator-check-type comp key)
  (let ((ordered? (eq? kind 'ordered)))
    (let loop ((cur entries) (acc '()))
      (cond
        ((null? cur)
         (reverse (cons (cons key val) acc)))
        ((=? comp key (caar cur))
         entries)
        ((and ordered? (<? comp key (caar cur)))
         (append (reverse acc) (cons (cons key val) cur)))
        (else
         (loop (cdr cur) (cons (car cur) acc)))))))

(define (%map-entry-set kind comp entries key val)
  (comparator-check-type comp key)
  (let ((ordered? (eq? kind 'ordered)))
    (let loop ((cur entries) (acc '()))
      (cond
        ((null? cur)
         (reverse (cons (cons key val) acc)))
        ((=? comp key (caar cur))
         (append (reverse acc) (cons (cons key val) (cdr cur))))
        ((and ordered? (<? comp key (caar cur)))
         (append (reverse acc) (cons (cons key val) cur)))
        (else
         (loop (cdr cur) (cons (car cur) acc)))))))

(define (%map-entry-replace kind comp entries key val)
  (comparator-check-type comp key)
  (let ((ordered? (eq? kind 'ordered)))
    (let loop ((cur entries) (acc '()))
      (cond
        ((null? cur)
         entries)
        ((=? comp key (caar cur))
         (append (reverse acc) (cons (cons key val) (cdr cur))))
        ((and ordered? (<? comp key (caar cur)))
         entries)
        (else
         (loop (cdr cur) (cons (car cur) acc)))))))

(define (%map-entry-delete kind comp entries key)
  (let ((ordered? (eq? kind 'ordered)))
    (let loop ((cur entries) (acc '()))
      (cond
        ((null? cur)
         entries)
        ((=? comp key (caar cur))
         (append (reverse acc) (cdr cur)))
        ((and ordered? (<? comp key (caar cur)))
         entries)
        (else
         (loop (cdr cur) (cons (car cur) acc)))))))

;; ---------------------------------------------------------------------
;; §2.2 / SRFI 146 Constructors & Predicates
;; ---------------------------------------------------------------------

(define (%map-adjoin-pairs kind comp entries args)
  (let loop ((rest args) (ens entries))
    (if (or (null? rest) (null? (cdr rest)))
        ens
        (loop (cddr rest)
              (%map-entry-adjoin kind comp ens (car rest) (cadr rest))))))

(define mapping
  (case-lambda
    ((comparator)
     (%make-raw-map 'ordered comparator '()))
    ((comparator . args)
     (%make-raw-map 'ordered comparator (%map-adjoin-pairs 'ordered comparator '() args)))))

(define mapping/ordered mapping)

(define hashmap
  (case-lambda
    ((comparator)
     (%make-raw-map 'hash comparator '()))
    ((comparator . args)
     (%make-raw-map 'hash comparator (%map-adjoin-pairs 'hash comparator '() args)))))

(define (%map-unfold-core kind stop? mapper successor seed comparator)
  (let loop ((s seed) (ens '()))
    (if (stop? s)
        (%make-raw-map kind comparator ens)
        (call-with-values
          (lambda () (mapper s))
          (lambda (k v)
            (loop (successor s)
                  (%map-entry-adjoin kind comparator ens k v)))))))

(define (mapping-unfold stop? mapper successor seed comparator)
  (%map-unfold-core 'ordered stop? mapper successor seed comparator))

(define mapping-unfold/ordered mapping-unfold)

(define (hashmap-unfold stop? mapper successor seed comparator)
  (%map-unfold-core 'hash stop? mapper successor seed comparator))

(define (mapping-empty? m)
  (null? (%map-entries m)))
(define hashmap-empty? mapping-empty?)

(define (mapping-contains? m key)
  (if (%map-entry-find (%map-kind m) (%map-comp m) (%map-entries m) key)
      #t
      #f))
(define hashmap-contains? mapping-contains?)

(define (mapping-disjoint? m1 m2)
  (let ((kind (%map-kind m2))
        (comp (%map-comp m1))
        (e2 (%map-entries m2)))
    (let loop ((e1 (%map-entries m1)))
      (cond
        ((null? e1) #t)
        ((%map-entry-find kind comp e2 (caar e1)) #f)
        (else (loop (cdr e1)))))))
(define hashmap-disjoint? mapping-disjoint?)

;; ---------------------------------------------------------------------
;; §2.2 / SRFI 146 Accessors
;; ---------------------------------------------------------------------

(define (%mapping-ref-core m key failure success)
  (let ((pair (%map-entry-find (%map-kind m) (%map-comp m) (%map-entries m) key)))
    (if pair
        (if success
            (success (cdr pair))
            (cdr pair))
        (if failure
            (failure)
            (error "mapping-ref: key not found" key)))))

(define mapping-ref
  (case-lambda
    ((m key)
     (%mapping-ref-core m key #f #f))
    ((m key failure)
     (%mapping-ref-core m key failure #f))
    ((m key failure success)
     (%mapping-ref-core m key failure success))))
(define hashmap-ref mapping-ref)

(define (mapping-ref/default m key default)
  (let ((pair (%map-entry-find (%map-kind m) (%map-comp m) (%map-entries m) key)))
    (if pair
        (cdr pair)
        default)))
(define hashmap-ref/default mapping-ref/default)

;; ---------------------------------------------------------------------
;; §2.2 / SRFI 146 Updaters
;; ---------------------------------------------------------------------

(define mapping-adjoin
  (case-lambda
    ((m) m)
    ((m . args)
     (%make-raw-map (%map-kind m)
                    (%map-comp m)
                    (%map-adjoin-pairs (%map-kind m) (%map-comp m) (%map-entries m) args)))))
(define mapping-adjoin! mapping-adjoin)
(define hashmap-adjoin mapping-adjoin)
(define hashmap-adjoin! mapping-adjoin)

(define (%map-set-pairs kind comp entries args)
  (let loop ((rest args) (ens entries))
    (if (or (null? rest) (null? (cdr rest)))
        ens
        (loop (cddr rest)
              (%map-entry-set kind comp ens (car rest) (cadr rest))))))

(define mapping-set
  (case-lambda
    ((m) m)
    ((m . args)
     (%make-raw-map (%map-kind m)
                    (%map-comp m)
                    (%map-set-pairs (%map-kind m) (%map-comp m) (%map-entries m) args)))))
(define mapping-set! mapping-set)
(define hashmap-set mapping-set)
(define hashmap-set! mapping-set)

(define (%map-replace-pairs kind comp entries args)
  (let loop ((rest args) (ens entries))
    (if (or (null? rest) (null? (cdr rest)))
        ens
        (loop (cddr rest)
              (%map-entry-replace kind comp ens (car rest) (cadr rest))))))

(define mapping-replace
  (case-lambda
    ((m) m)
    ((m . args)
     (%make-raw-map (%map-kind m)
                    (%map-comp m)
                    (%map-replace-pairs (%map-kind m) (%map-comp m) (%map-entries m) args)))))
(define mapping-replace! mapping-replace)
(define hashmap-replace mapping-replace)
(define hashmap-replace! mapping-replace)

(define (mapping-delete-all m keys)
  (let ((kind (%map-kind m))
        (comp (%map-comp m)))
    (let loop ((ks keys) (ens (%map-entries m)))
      (if (null? ks)
          (%make-raw-map kind comp ens)
          (loop (cdr ks) (%map-entry-delete kind comp ens (car ks)))))))
(define mapping-delete-all! mapping-delete-all)
(define hashmap-delete-all mapping-delete-all)
(define hashmap-delete-all! mapping-delete-all)

(define mapping-delete
  (case-lambda
    ((m) m)
    ((m . keys)
     (mapping-delete-all m keys))))
(define mapping-delete! mapping-delete)
(define hashmap-delete mapping-delete)
(define hashmap-delete! mapping-delete)

(define (mapping-intern m key failure)
  (let ((pair (%map-entry-find (%map-kind m) (%map-comp m) (%map-entries m) key)))
    (if pair
        (values m (cdr pair))
        (let ((val (failure)))
          (values (mapping-set m key val) val)))))
(define mapping-intern! mapping-intern)
(define hashmap-intern mapping-intern)
(define hashmap-intern! mapping-intern)

(define (%mapping-update-core m key updater failure success)
  (let ((pair (%map-entry-find (%map-kind m) (%map-comp m) (%map-entries m) key)))
    (if pair
        (let* ((arg (if success (success (cdr pair)) (cdr pair)))
               (new-val (updater arg)))
          (mapping-set m key new-val))
        (let* ((arg (if failure
                        (failure)
                        (error "mapping-update: key not found" key)))
               (new-val (updater arg)))
          (mapping-set m key new-val)))))

(define mapping-update
  (case-lambda
    ((m key updater)
     (%mapping-update-core m key updater #f #f))
    ((m key updater failure)
     (%mapping-update-core m key updater failure #f))
    ((m key updater failure success)
     (%mapping-update-core m key updater failure success))))
(define mapping-update! mapping-update)
(define hashmap-update mapping-update)
(define hashmap-update! mapping-update)

(define (mapping-update/default m key updater default)
  (let ((old-val (mapping-ref/default m key default)))
    (mapping-set m key (updater old-val))))
(define mapping-update!/default mapping-update/default)
(define hashmap-update/default mapping-update/default)
(define hashmap-update!/default mapping-update/default)

(define (%mapping-pop-core m failure)
  (let ((ens (%map-entries m)))
    (if (null? ens)
        (if failure
            (failure)
            (error "mapping-pop: empty mapping"))
        (let ((first (car ens)))
          (values (%make-raw-map (%map-kind m) (%map-comp m) (cdr ens))
                  (car first)
                  (cdr first))))))

(define mapping-pop
  (case-lambda
    ((m) (%mapping-pop-core m #f))
    ((m failure) (%mapping-pop-core m failure))))
(define mapping-pop! mapping-pop)
(define hashmap-pop mapping-pop)
(define hashmap-pop! mapping-pop)

(define (mapping-search m key failure success)
  (let* ((kind (%map-kind m))
         (comp (%map-comp m))
         (ens (%map-entries m))
         (pair (%map-entry-find kind comp ens key)))
    (if pair
        (success
          (car pair)
          (cdr pair)
          (lambda (new-key new-val obj)
            (let* ((ens1 (%map-entry-delete kind comp ens key))
                   (ens2 (%map-entry-set kind comp ens1 new-key new-val)))
              (values (%make-raw-map kind comp ens2) obj)))
          (lambda (obj)
            (values (%make-raw-map kind comp (%map-entry-delete kind comp ens key)) obj)))
        (failure
          (lambda (val obj)
            (values (%make-raw-map kind comp (%map-entry-set kind comp ens key val)) obj))
          (lambda (obj)
            (values m obj))))))
(define mapping-search! mapping-search)
(define hashmap-search mapping-search)
(define hashmap-search! mapping-search)

;; ---------------------------------------------------------------------
;; §2.2 / SRFI 146 The Whole Mapping
;; ---------------------------------------------------------------------

(define (mapping-size m) (length (%map-entries m)))
(define hashmap-size mapping-size)

(define (mapping-find pred m failure)
  (let loop ((ens (%map-entries m)))
    (if (null? ens)
        (failure)
        (let ((k (caar ens))
              (v (cdar ens)))
          (if (pred k v)
              (values k v)
              (loop (cdr ens)))))))
(define hashmap-find mapping-find)

(define (mapping-count pred m)
  (let loop ((ens (%map-entries m)) (n 0))
    (if (null? ens)
        n
        (loop (cdr ens)
              (if (pred (caar ens) (cdar ens))
                  (+ n 1)
                  n)))))
(define hashmap-count mapping-count)

(define (mapping-any? pred m)
  (let loop ((ens (%map-entries m)))
    (cond
      ((null? ens) #f)
      ((pred (caar ens) (cdar ens)) #t)
      (else (loop (cdr ens))))))
(define hashmap-any? mapping-any?)

(define (mapping-every? pred m)
  (let loop ((ens (%map-entries m)))
    (cond
      ((null? ens) #t)
      ((pred (caar ens) (cdar ens)) (loop (cdr ens)))
      (else #f))))
(define hashmap-every? mapping-every?)

(define (mapping-keys m)
  (let loop ((ens (%map-entries m)) (acc '()))
    (if (null? ens)
        (reverse acc)
        (loop (cdr ens) (cons (caar ens) acc)))))
(define hashmap-keys mapping-keys)

(define (mapping-values m)
  (let loop ((ens (%map-entries m)) (acc '()))
    (if (null? ens)
        (reverse acc)
        (loop (cdr ens) (cons (cdar ens) acc)))))
(define hashmap-values mapping-values)

(define (mapping-entries m)
  (values (mapping-keys m) (mapping-values m)))
(define hashmap-entries mapping-entries)

;; ---------------------------------------------------------------------
;; §2.2 / SRFI 146 Mapping and Folding
;; ---------------------------------------------------------------------

(define (%map-map-core kind proc comparator m)
  (let loop ((ens (%map-entries m)) (res '()))
    (if (null? ens)
        (%make-raw-map kind comparator res)
        (call-with-values
          (lambda () (proc (caar ens) (cdar ens)))
          (lambda (k v)
            (loop (cdr ens) (%map-entry-adjoin kind comparator res k v)))))))

(define (mapping-map proc comparator m)
  (%map-map-core 'ordered proc comparator m))
(define (hashmap-map proc comparator hm)
  (%map-map-core 'hash proc comparator hm))

(define (mapping-map/monotone proc comparator m)
  (mapping-map proc comparator m))
(define mapping-map/monotone! mapping-map/monotone)

(define (mapping-for-each proc m)
  (let loop ((ens (%map-entries m)))
    (if (not (null? ens))
        (begin
          (proc (caar ens) (cdar ens))
          (loop (cdr ens))))))
(define hashmap-for-each mapping-for-each)

(define (mapping-fold proc nil m)
  (let loop ((ens (%map-entries m)) (acc nil))
    (if (null? ens)
        acc
        (loop (cdr ens) (proc (caar ens) (cdar ens) acc)))))
(define hashmap-fold mapping-fold)

(define (mapping-fold/reverse proc nil m)
  (let loop ((ens (reverse (%map-entries m))) (acc nil))
    (if (null? ens)
        acc
        (loop (cdr ens) (proc (caar ens) (cdar ens) acc)))))

(define (mapping-map->list proc m)
  (let loop ((ens (%map-entries m)) (acc '()))
    (if (null? ens)
        (reverse acc)
        (loop (cdr ens) (cons (proc (caar ens) (cdar ens)) acc)))))
(define hashmap-map->list mapping-map->list)

(define (mapping-filter pred m)
  (let loop ((ens (%map-entries m)) (acc '()))
    (if (null? ens)
        (%make-raw-map (%map-kind m) (%map-comp m) (reverse acc))
        (let ((pair (car ens)))
          (if (pred (car pair) (cdr pair))
              (loop (cdr ens) (cons pair acc))
              (loop (cdr ens) acc))))))
(define mapping-filter! mapping-filter)
(define hashmap-filter mapping-filter)
(define hashmap-filter! mapping-filter)

(define (mapping-remove pred m)
  (let loop ((ens (%map-entries m)) (acc '()))
    (if (null? ens)
        (%make-raw-map (%map-kind m) (%map-comp m) (reverse acc))
        (let ((pair (car ens)))
          (if (pred (car pair) (cdr pair))
              (loop (cdr ens) acc)
              (loop (cdr ens) (cons pair acc)))))))
(define mapping-remove! mapping-remove)
(define hashmap-remove mapping-remove)
(define hashmap-remove! mapping-remove)

(define (mapping-partition pred m)
  (let ((kind (%map-kind m))
        (comp (%map-comp m)))
    (let loop ((ens (%map-entries m)) (in-acc '()) (out-acc '()))
      (if (null? ens)
          (values (%make-raw-map kind comp (reverse in-acc))
                  (%make-raw-map kind comp (reverse out-acc)))
          (let ((pair (car ens)))
            (if (pred (car pair) (cdr pair))
                (loop (cdr ens) (cons pair in-acc) out-acc)
                (loop (cdr ens) in-acc (cons pair out-acc))))))))
(define mapping-partition! mapping-partition)
(define hashmap-partition mapping-partition)
(define hashmap-partition! mapping-partition)

;; ---------------------------------------------------------------------
;; §2.2 / SRFI 146 Copying and Conversion
;; ---------------------------------------------------------------------

(define (mapping-copy m)
  (%make-raw-map (%map-kind m)
                 (%map-comp m)
                 (let loop ((ens (%map-entries m)) (acc '()))
                   (if (null? ens)
                       (reverse acc)
                       (loop (cdr ens) (cons (cons (caar ens) (cdar ens)) acc))))))
(define hashmap-copy mapping-copy)

(define (mapping->alist m)
  (let loop ((ens (%map-entries m)) (acc '()))
    (if (null? ens)
        (reverse acc)
        (loop (cdr ens) (cons (cons (caar ens) (cdar ens)) acc)))))
(define hashmap->alist mapping->alist)

(define (alist->mapping! m alist)
  (let ((kind (%map-kind m))
        (comp (%map-comp m)))
    (let loop ((rest alist) (ens (%map-entries m)))
      (if (null? rest)
          (%make-raw-map kind comp ens)
          (let ((pair (car rest)))
            (loop (cdr rest)
                  (%map-entry-adjoin kind comp ens (car pair) (cdr pair))))))))
(define alist->mapping/ordered! alist->mapping!)
(define alist->hashmap! alist->mapping!)

(define (alist->mapping comparator alist)
  (alist->mapping! (%make-raw-map 'ordered comparator '()) alist))
(define alist->mapping/ordered alist->mapping)

(define (alist->hashmap comparator alist)
  (alist->mapping! (%make-raw-map 'hash comparator '()) alist))

;; ---------------------------------------------------------------------
;; §2.2 / SRFI 146 Submappings & Set-Theoretic Operations
;; ---------------------------------------------------------------------

(define (%mapping-submap<=? val-comp m1 m2)
  (let ((kind (%map-kind m2))
        (kcomp (%map-comp m1))
        (e2 (%map-entries m2)))
    (let loop ((e1 (%map-entries m1)))
      (if (null? e1)
          #t
          (let ((found (%map-entry-find kind kcomp e2 (caar e1))))
            (if (and found (=? val-comp (cdar e1) (cdr found)))
                (loop (cdr e1))
                #f))))))

(define (%mapping-equal-2? val-comp m1 m2)
  (and (= (mapping-size m1) (mapping-size m2))
       (%mapping-submap<=? val-comp m1 m2)))

(define (%mapping-proper-submap<? val-comp m1 m2)
  (and (< (mapping-size m1) (mapping-size m2))
       (%mapping-submap<=? val-comp m1 m2)))

(define (%mapping-chain-cmp pred val-comp ms)
  (if (or (null? ms) (null? (cdr ms)))
      #t
      (let loop ((prev (car ms)) (rest (cdr ms)))
        (if (null? rest)
            #t
            (if (pred val-comp prev (car rest))
                (loop (car rest) (cdr rest))
                #f)))))

(define mapping=?
  (case-lambda
    ((val-comp . ms) (%mapping-chain-cmp %mapping-equal-2? val-comp ms))))
(define mapping<=?
  (case-lambda
    ((val-comp . ms) (%mapping-chain-cmp %mapping-submap<=? val-comp ms))))
(define mapping<?
  (case-lambda
    ((val-comp . ms) (%mapping-chain-cmp %mapping-proper-submap<? val-comp ms))))
(define (%mapping-superset>=? vc a b) (%mapping-submap<=? vc b a))
(define (%mapping-proper-superset>? vc a b) (%mapping-proper-submap<? vc b a))
(define mapping>=?
  (case-lambda
    ((val-comp . ms) (%mapping-chain-cmp %mapping-superset>=? val-comp ms))))
(define mapping>?
  (case-lambda
    ((val-comp . ms) (%mapping-chain-cmp %mapping-proper-superset>? val-comp ms))))

(define hashmap=? mapping=?)
(define hashmap<=? mapping<=?)
(define hashmap<? mapping<?)
(define hashmap>=? mapping>=?)
(define hashmap>? mapping>?)

(define (%mapping-union-2 m1 m2)
  (let ((kind (%map-kind m1))
        (comp (%map-comp m1)))
    (let loop ((e2 (%map-entries m2)) (ens (%map-entries m1)))
      (if (null? e2)
          (%make-raw-map kind comp ens)
          (loop (cdr e2)
                (%map-entry-adjoin kind comp ens (caar e2) (cdar e2)))))))

(define mapping-union
  (case-lambda
    ((m1) (mapping-copy m1))
    ((m1 . rest)
     (let loop ((acc (mapping-copy m1)) (more rest))
       (if (null? more)
           acc
           (loop (%mapping-union-2 acc (car more)) (cdr more)))))))
(define mapping-union! mapping-union)
(define hashmap-union mapping-union)
(define hashmap-union! mapping-union)

(define (%mapping-intersection-2 m1 m2)
  (let ((kind1 (%map-kind m1))
        (kind2 (%map-kind m2))
        (comp (%map-comp m1))
        (e2 (%map-entries m2)))
    (let loop ((e1 (%map-entries m1)) (acc '()))
      (if (null? e1)
          (%make-raw-map kind1 comp (reverse acc))
          (if (%map-entry-find kind2 comp e2 (caar e1))
              (loop (cdr e1) (cons (car e1) acc))
              (loop (cdr e1) acc))))))

(define mapping-intersection
  (case-lambda
    ((m1) (mapping-copy m1))
    ((m1 . rest)
     (let loop ((acc (mapping-copy m1)) (more rest))
       (if (null? more)
           acc
           (loop (%mapping-intersection-2 acc (car more)) (cdr more)))))))
(define mapping-intersection! mapping-intersection)
(define hashmap-intersection mapping-intersection)
(define hashmap-intersection! mapping-intersection)

(define (%mapping-difference-2 m1 m2)
  (let ((kind1 (%map-kind m1))
        (kind2 (%map-kind m2))
        (comp (%map-comp m1))
        (e2 (%map-entries m2)))
    (let loop ((e1 (%map-entries m1)) (acc '()))
      (if (null? e1)
          (%make-raw-map kind1 comp (reverse acc))
          (if (%map-entry-find kind2 comp e2 (caar e1))
              (loop (cdr e1) acc)
              (loop (cdr e1) (cons (car e1) acc)))))))

(define mapping-difference
  (case-lambda
    ((m1) (mapping-copy m1))
    ((m1 . rest)
     (let loop ((acc (mapping-copy m1)) (more rest))
       (if (null? more)
           acc
           (loop (%mapping-difference-2 acc (car more)) (cdr more)))))))
(define mapping-difference! mapping-difference)
(define hashmap-difference mapping-difference)
(define hashmap-difference! mapping-difference)

(define (mapping-xor m1 m2)
  (%mapping-union-2 (%mapping-difference-2 m1 m2)
                    (%mapping-difference-2 m2 m1)))
(define mapping-xor! mapping-xor)
(define hashmap-xor mapping-xor)
(define hashmap-xor! mapping-xor)

;; ---------------------------------------------------------------------
;; §2.2 / SRFI 146 Ordered Key Operations
;; ---------------------------------------------------------------------

(define (mapping-min-entry m)
  (let ((ens (%map-entries m)))
    (if (null? ens)
        (error "mapping-min-entry: empty mapping")
        (values (caar ens) (cdar ens)))))

(define (mapping-max-entry m)
  (let ((ens (%map-entries m)))
    (if (null? ens)
        (error "mapping-max-entry: empty mapping")
        (let loop ((cur ens))
          (if (null? (cdr cur))
              (values (caar cur) (cdar cur))
              (loop (cdr cur)))))))

(define (mapping-min-key m)
  (call-with-values (lambda () (mapping-min-entry m)) (lambda (k v) k)))

(define (mapping-min-value m)
  (call-with-values (lambda () (mapping-min-entry m)) (lambda (k v) v)))

(define (mapping-max-key m)
  (call-with-values (lambda () (mapping-max-entry m)) (lambda (k v) k)))

(define (mapping-max-value m)
  (call-with-values (lambda () (mapping-max-entry m)) (lambda (k v) v)))

(define (mapping-key-predecessor m obj failure)
  (let ((comp (%map-comp m)))
    (let loop ((ens (%map-entries m)) (found? #f) (best #f))
      (cond
        ((null? ens)
         (if found? best (failure)))
        ((<? comp (caar ens) obj)
         (loop (cdr ens) #t (caar ens)))
        (else
         (if found? best (failure)))))))

(define (mapping-key-successor m obj failure)
  (let ((comp (%map-comp m)))
    (let loop ((ens (%map-entries m)))
      (cond
        ((null? ens) (failure))
        ((>? comp (caar ens) obj) (caar ens))
        (else (loop (cdr ens)))))))

(define (mapping-range= m obj)
  (let ((comp (%map-comp m)))
    (mapping-filter (lambda (k v) (=? comp k obj)) m)))

(define (mapping-range< m obj)
  (let ((comp (%map-comp m)))
    (mapping-filter (lambda (k v) (<? comp k obj)) m)))

(define (mapping-range<= m obj)
  (let ((comp (%map-comp m)))
    (mapping-filter (lambda (k v) (<=? comp k obj)) m)))

(define (mapping-range> m obj)
  (let ((comp (%map-comp m)))
    (mapping-filter (lambda (k v) (>? comp k obj)) m)))

(define (mapping-range>= m obj)
  (let ((comp (%map-comp m)))
    (mapping-filter (lambda (k v) (>=? comp k obj)) m)))

(define mapping-range=! mapping-range=)
(define mapping-range<! mapping-range<)
(define mapping-range<=! mapping-range<=)
(define mapping-range>! mapping-range>)
(define mapping-range>=! mapping-range>=)

(define-syntax mapping-split
  (syntax-rules ()
    ((_ m obj)
     (values (mapping-range< m obj)
             (mapping-range<= m obj)
             (mapping-range= m obj)
             (mapping-range>= m obj)
             (mapping-range> m obj)))))

(define (mapping-catenate comparator m1 key val m2)
  (let ((u (%mapping-union-2 (%make-raw-map 'ordered comparator (%map-entries m1)) m2)))
    (mapping-set u key val)))

(define mapping-catenate! mapping-catenate)

;; ---------------------------------------------------------------------
;; §2.2 / SRFI 146 Mapping & Hashmap Comparators
;; ---------------------------------------------------------------------

(define (%mapping-compare val-comp m1 m2)
  (let ((kcomp (%map-comp m1)))
    (let loop ((e1 (%map-entries m1)) (e2 (%map-entries m2)))
      (cond
        ((and (null? e1) (null? e2)) 0)
        ((null? e1) -1)
        ((null? e2) 1)
        (else
         (let ((p1 (car e1))
               (p2 (car e2)))
           (cond
             ((<? kcomp (car p1) (car p2)) -1)
             ((>? kcomp (car p1) (car p2)) 1)
             ((not (=? val-comp (cdr p1) (cdr p2)))
              (if (comparator-ordered? val-comp)
                  (if (<? val-comp (cdr p1) (cdr p2)) -1 1)
                  -1))
             (else (loop (cdr e1) (cdr e2))))))))))

(define (%map-symmetric-hash val-comp m)
  (let ((kcomp (%map-comp m)))
    (let loop ((ens (%map-entries m)) (h 0))
      (if (null? ens)
          (modulo h 536870911)
          (let* ((kh (if (comparator-hashable? kcomp)
                         (comparator-hash kcomp (caar ens))
                         0))
                 (vh (if (comparator-hashable? val-comp)
                         (comparator-hash val-comp (cdar ens))
                         0)))
            (loop (cdr ens)
                  (modulo (+ h (+ (* kh 31) vh)) 536870911)))))))

(define (make-mapping-comparator val-comp)
  (make-comparator
    mapping?
    (lambda (m1 m2) (%mapping-equal-2? val-comp m1 m2))
    (lambda (m1 m2) (< (%mapping-compare val-comp m1 m2) 0))
    (lambda (m) (%map-symmetric-hash val-comp m))))

(define mapping-comparator
  (make-mapping-comparator (make-default-comparator)))

(define (make-hashmap-comparator val-comp)
  (make-comparator
    hashmap?
    (lambda (hm1 hm2) (%mapping-equal-2? val-comp hm1 hm2))
    #f
    (lambda (hm) (%map-symmetric-hash val-comp hm))))

(define hashmap-comparator
  (make-hashmap-comparator (make-default-comparator)))
