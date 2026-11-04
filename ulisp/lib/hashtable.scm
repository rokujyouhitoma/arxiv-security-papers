;;; =======================================================================
;;; ULisp Standard Library: Hash Tables (SRFI 69, SRFI 125, R7RS-large)
;;; Conforms to DSN-33 Architecture Specification, Issue #649
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §1. Type Definition: <hash-table> Record
;; ---------------------------------------------------------------------
(define-record-type <hash-table>
  (%make-raw-hash-table buckets size equal-proc hash-proc)
  hash-table?
  (buckets %ht-buckets %ht-buckets-set!)
  (size %ht-size %ht-size-set!)
  (equal-proc %ht-equal)
  (hash-proc %ht-hash))

;; ---------------------------------------------------------------------
;; §2. Standard Hash Functions
;; ---------------------------------------------------------------------

;; 24-bit prime modulus to guarantee zero 32-bit/64-bit fixnum overflow during (* h 33):
;; 16777213 * 33 = 553648029 < 2^30
(define %ht-hash-modulus 16777213)

(define string-hash
  (case-lambda
    ((str)
     (string-hash str %ht-hash-modulus))
    ((str bound)
     (let ((len (string-length str)))
       (let loop ((i 0) (h 5381))
         (if (= i len)
             (modulo (if (< h 0) (- 0 h) h) bound)
             (let ((c (char->integer (string-ref str i))))
               (loop (+ i 1)
                     (modulo (+ (* (modulo h 500000) 33) c) %ht-hash-modulus)))))))))

(define string-ci-hash
  (case-lambda
    ((str)
     (string-ci-hash str %ht-hash-modulus))
    ((str bound)
     (let ((len (string-length str)))
       (let loop ((i 0) (h 5381))
         (if (= i len)
             (modulo (if (< h 0) (- 0 h) h) bound)
             (let* ((c-raw (char->integer (string-ref str i)))
                    (c (if (and (>= c-raw 65) (<= c-raw 90))
                           (+ c-raw 32)
                           c-raw)))
               (loop (+ i 1)
                     (modulo (+ (* (modulo h 500000) 33) c) %ht-hash-modulus)))))))))

(define symbol-hash
  (case-lambda
    ((sym)
     (symbol-hash sym %ht-hash-modulus))
    ((sym bound)
     (string-hash (symbol->string sym) bound))))

(define (%fixnum-hash num bound)
  (let* ((n (if (< num 0) (- 0 num) num))
         (h (modulo (+ (* (modulo n %ht-hash-modulus) 265443) 13) %ht-hash-modulus)))
    (modulo h bound)))

(define number-hash
  (case-lambda
    ((num)
     (number-hash num %ht-hash-modulus))
    ((num bound)
     (cond
       ((fixnum? num)
        (%fixnum-hash num bound))
       ((ratnum? num)
        (let ((h1 (%fixnum-hash (vector-ref num 1) %ht-hash-modulus))
              (h2 (%fixnum-hash (vector-ref num 2) %ht-hash-modulus)))
          (modulo (+ (* (modulo h1 450000) 37) h2) bound)))
       ((flonum? num)
        (let ((v (vector-ref num 1)))
          (if (fixnum? v)
              (%fixnum-hash v bound)
              (symbol-hash v bound))))
       ((compnum? num)
        (let ((h1 (number-hash (vector-ref num 1) %ht-hash-modulus))
              (h2 (number-hash (vector-ref num 2) %ht-hash-modulus)))
          (modulo (+ (* (modulo h1 450000) 41) h2) bound)))
       (else
        (modulo 997 bound))))))

(define hash-by-identity
  (case-lambda
    ((obj)
     (hash-by-identity obj %ht-hash-modulus))
    ((obj bound)
     (cond
       ((number? obj) (number-hash obj bound))
       ((symbol? obj) (symbol-hash obj bound))
       ((char? obj) (modulo (+ 137 (char->integer obj)) bound))
       ((boolean? obj) (if obj (modulo 271 bound) (modulo 277 bound)))
       ((null? obj) (modulo 283 bound))
       (else (modulo 1013 bound))))))

(define (%deep-hash obj depth bound)
  (if (<= depth 0)
      (modulo 431 bound)
      (cond
        ((number? obj) (number-hash obj bound))
        ((symbol? obj) (symbol-hash obj bound))
        ((string? obj) (string-hash obj bound))
        ((char? obj) (modulo (+ 137 (char->integer obj)) bound))
        ((boolean? obj) (if obj (modulo 271 bound) (modulo 277 bound)))
        ((null? obj) (modulo 283 bound))
        ((pair? obj)
         (let ((h1 (%deep-hash (car obj) (- depth 1) %ht-hash-modulus))
               (h2 (%deep-hash (cdr obj) (- depth 1) %ht-hash-modulus)))
           (modulo (+ (* (modulo h1 450000) 37) h2) bound)))
        ((vector? obj)
         (let ((len (vector-length obj)))
           (if (= len 0)
               (modulo 521 bound)
               (let loop ((i 0) (h (modulo len %ht-hash-modulus)))
                 (if (or (= i len) (>= i 4))
                     (modulo h bound)
                     (loop (+ i 1)
                           (modulo (+ (* (modulo h 500000) 31)
                                      (%deep-hash (vector-ref obj i) (- depth 1) %ht-hash-modulus))
                                   bound)))))))
        ((bytevector? obj)
         (let ((len (bytevector-length obj)))
           (let loop ((i 0) (h (modulo len %ht-hash-modulus)))
             (if (or (= i len) (>= i 8))
                 (modulo h bound)
                 (loop (+ i 1)
                       (modulo (+ (* (modulo h 500000) 33) (bytevector-u8-ref obj i)) bound))))))
        (else (modulo 997 bound)))))

(define hash
  (case-lambda
    ((obj)
     (%deep-hash obj 4 %ht-hash-modulus))
    ((obj bound)
     (%deep-hash obj 4 bound))))

;; ---------------------------------------------------------------------
;; §3. Internal Helpers & Bucket Indexing
;; ---------------------------------------------------------------------

(define (%ht-equal? a b) (equal? a b))

(define (%ht-bucket-index ht key)
  (let* ((buckets (%ht-buckets ht))
         (cap (vector-length buckets))
         (hash-fn (%ht-hash ht))
         (h (hash-fn key))
         (h-abs (if (< h 0) (- 0 h) h)))
    (modulo h-abs cap)))

(define (%make-buckets cap)
  (let ((v (make-vector cap '())))
    v))

(define (%make-hash-table-full eq-fn hash-fn initial-cap)
  (let ((cap (if (< initial-cap 8) 8 initial-cap)))
    (%make-raw-hash-table (%make-buckets cap) 0 eq-fn hash-fn)))

(define (%ht-rehash! ht new-cap)
  (let* ((old-buckets (%ht-buckets ht))
         (old-len (vector-length old-buckets))
         (new-buckets (make-vector new-cap '()))
         (hash-fn (%ht-hash ht)))
    (let loop-b ((b-idx 0))
      (if (< b-idx old-len)
          (let loop-chain ((chain (vector-ref old-buckets b-idx)))
            (if (pair? chain)
                (let* ((entry (car chain))
                       (key (car entry))
                       (h (hash-fn key))
                       (h-abs (if (< h 0) (- 0 h) h))
                       (new-idx (modulo h-abs new-cap))
                       (cur (vector-ref new-buckets new-idx)))
                  (vector-set! new-buckets new-idx (cons entry cur))
                  (loop-chain (cdr chain)))
                (loop-b (+ b-idx 1))))
          (%ht-buckets-set! ht new-buckets)))))

;; ---------------------------------------------------------------------
;; §4. Constructors
;; ---------------------------------------------------------------------

(define make-hash-table
  (case-lambda
    (()
     (%make-hash-table-full %ht-equal? hash 64))
    ((eq-fn)
     (%make-hash-table-full eq-fn hash 64))
    ((eq-fn hash-fn)
     (%make-hash-table-full eq-fn hash-fn 64))
    ((eq-fn hash-fn initial-cap)
     (%make-hash-table-full eq-fn hash-fn initial-cap))))

;; ---------------------------------------------------------------------
;; §5. Predicates
;; ---------------------------------------------------------------------

(define (hash-table-contains? ht key)
  (let* ((b-idx (%ht-bucket-index ht key))
         (buckets (%ht-buckets ht))
         (chain (vector-ref buckets b-idx))
         (eq-fn (%ht-equal ht)))
    (let loop ((c chain))
      (if (pair? c)
          (if (eq-fn (caar c) key)
              #t
              (loop (cdr c)))
          #f))))

(define hash-table-exists? hash-table-contains?)

(define (hash-table-empty? ht)
  (= (%ht-size ht) 0))

(define (hash-table=? val=? ht1 ht2)
  (and (= (%ht-size ht1) (%ht-size ht2))
       (let* ((buckets (%ht-buckets ht1))
              (len (vector-length buckets)))
         (let loop-b ((b-idx 0))
           (if (< b-idx len)
               (let loop-chain ((chain (vector-ref buckets b-idx)))
                 (if (pair? chain)
                     (let* ((entry (car chain))
                            (k (car entry))
                            (v1 (cdr entry)))
                       (if (hash-table-contains? ht2 k)
                           (let ((v2 (hash-table-ref ht2 k)))
                             (if (val=? v1 v2)
                                 (loop-chain (cdr chain))
                                 #f))
                           #f))
                     (loop-b (+ b-idx 1))))
               #t)))))

;; ---------------------------------------------------------------------
;; §6. Accessors & Mutators
;; ---------------------------------------------------------------------

(define hash-table-ref
  (case-lambda
    ((ht key)
     (let* ((b-idx (%ht-bucket-index ht key))
            (buckets (%ht-buckets ht))
            (chain (vector-ref buckets b-idx))
            (eq-fn (%ht-equal ht)))
       (let loop ((c chain))
         (if (pair? c)
             (if (eq-fn (caar c) key)
                 (cdar c)
                 (loop (cdr c)))
             (error "hash-table-ref: key not found in table" key)))))
    ((ht key failure-thunk)
     (let* ((b-idx (%ht-bucket-index ht key))
            (buckets (%ht-buckets ht))
            (chain (vector-ref buckets b-idx))
            (eq-fn (%ht-equal ht)))
       (let loop ((c chain))
         (if (pair? c)
             (if (eq-fn (caar c) key)
                 (cdar c)
                 (loop (cdr c)))
             (failure-thunk)))))
    ((ht key failure-thunk success-proc)
     (let* ((b-idx (%ht-bucket-index ht key))
            (buckets (%ht-buckets ht))
            (chain (vector-ref buckets b-idx))
            (eq-fn (%ht-equal ht)))
       (let loop ((c chain))
         (if (pair? c)
             (if (eq-fn (caar c) key)
                 (success-proc (cdar c))
                 (loop (cdr c)))
             (failure-thunk)))))))

(define (hash-table-ref/default ht key default-val)
  (let* ((b-idx (%ht-bucket-index ht key))
         (buckets (%ht-buckets ht))
         (chain (vector-ref buckets b-idx))
         (eq-fn (%ht-equal ht)))
    (let loop ((c chain))
      (if (pair? c)
          (if (eq-fn (caar c) key)
              (cdar c)
              (loop (cdr c)))
          default-val))))

(define (%ht-set-single! ht key val)
  (let* ((b-idx (%ht-bucket-index ht key))
         (buckets (%ht-buckets ht))
         (chain (vector-ref buckets b-idx))
         (eq-fn (%ht-equal ht)))
    (let loop ((c chain))
      (if (pair? c)
          (if (eq-fn (caar c) key)
              (begin
                (set-cdr! (car c) val)
                #f)
              (loop (cdr c)))
          ;; Key not found: insert new entry at head
          (begin
            (vector-set! buckets b-idx (cons (cons key val) chain))
            (let ((new-size (+ (%ht-size ht) 1)))
              (%ht-size-set! ht new-size)
              ;; Dynamic Rehash threshold: size * 2 > cap * 3 (load factor > 1.5)
              (let ((cap (vector-length buckets)))
                (if (> (* new-size 2) (* cap 3))
                    (%ht-rehash! ht (* cap 2))
                    #f)))
            #t)))))

(define hash-table-set!
  (case-lambda
    ((ht key val)
     (%ht-set-single! ht key val))
    ((ht key val . rest)
     (%ht-set-single! ht key val)
     (let loop ((args rest))
       (if (and (pair? args) (pair? (cdr args)))
           (begin
             (%ht-set-single! ht (car args) (cadr args))
             (loop (cddr args)))
           #t)))))

(define (%ht-delete-single! ht key)
  (let* ((b-idx (%ht-bucket-index ht key))
         (buckets (%ht-buckets ht))
         (chain (vector-ref buckets b-idx))
         (eq-fn (%ht-equal ht)))
    (if (null? chain)
        #f
        (if (eq-fn (caar chain) key)
            (begin
              (vector-set! buckets b-idx (cdr chain))
              (%ht-size-set! ht (- (%ht-size ht) 1))
              #t)
            (let loop ((prev chain) (curr (cdr chain)))
              (if (pair? curr)
                  (if (eq-fn (caar curr) key)
                      (begin
                        (set-cdr! prev (cdr curr))
                        (%ht-size-set! ht (- (%ht-size ht) 1))
                        #t)
                      (loop curr (cdr curr)))
                  #f))))))

(define hash-table-delete!
  (case-lambda
    ((ht key)
     (%ht-delete-single! ht key))
    ((ht key . rest)
     (%ht-delete-single! ht key)
     (let loop ((keys rest))
       (if (pair? keys)
           (begin
             (%ht-delete-single! ht (car keys))
             (loop (cdr keys)))
           #t)))))

(define hash-table-update!
  (case-lambda
    ((ht key updater)
     (let ((val (hash-table-ref ht key)))
       (hash-table-set! ht key (updater val))))
    ((ht key updater failure-thunk)
     (let ((val (hash-table-ref ht key failure-thunk)))
       (hash-table-set! ht key (updater val))))
    ((ht key updater failure-thunk success-proc)
     (let ((val (hash-table-ref ht key failure-thunk success-proc)))
       (hash-table-set! ht key (updater val))))))

(define (hash-table-update!/default ht key updater default-val)
  (let ((val (hash-table-ref/default ht key default-val)))
    (hash-table-set! ht key (updater val))))

(define (hash-table-clear! ht)
  (let* ((buckets (%ht-buckets ht))
         (len (vector-length buckets)))
    (vector-fill! buckets '())
    (%ht-size-set! ht 0)
    #t))

(define (hash-table-pop! ht)
  (if (= (%ht-size ht) 0)
      (error "hash-table-pop!: table is empty")
      (let* ((buckets (%ht-buckets ht))
             (len (vector-length buckets)))
        (let loop ((i 0))
          (if (< i len)
              (let ((chain (vector-ref buckets i)))
                (if (pair? chain)
                    (let* ((entry (car chain))
                           (k (car entry))
                           (v (cdr entry)))
                      (vector-set! buckets i (cdr chain))
                      (%ht-size-set! ht (- (%ht-size ht) 1))
                      (values k v))
                    (loop (+ i 1))))
              (error "hash-table-pop!: no elements found"))))))

;; ---------------------------------------------------------------------
;; §7. Advanced Constructors (alist->hash-table & hash-table)
;; ---------------------------------------------------------------------

(define alist->hash-table
  (case-lambda
    ((alist)
     (let ((ht (%make-hash-table-full %ht-equal? hash 64)))
       (let loop ((pairs alist))
         (if (pair? pairs)
             (let ((entry (car pairs)))
               (if (pair? entry)
                   (%ht-set-single! ht (car entry) (cdr entry))
                   #f)
               (loop (cdr pairs)))
             ht))))
    ((alist eq-fn)
     (let ((ht (%make-hash-table-full eq-fn hash 64)))
       (let loop ((pairs alist))
         (if (pair? pairs)
             (let ((entry (car pairs)))
               (if (pair? entry)
                   (%ht-set-single! ht (car entry) (cdr entry))
                   #f)
               (loop (cdr pairs)))
             ht))))
    ((alist eq-fn hash-fn)
     (let ((ht (%make-hash-table-full eq-fn hash-fn 64)))
       (let loop ((pairs alist))
         (if (pair? pairs)
             (let ((entry (car pairs)))
               (if (pair? entry)
                   (%ht-set-single! ht (car entry) (cdr entry))
                   #f)
               (loop (cdr pairs)))
             ht))))
    ((alist eq-fn hash-fn initial-cap)
     (let ((ht (%make-hash-table-full eq-fn hash-fn initial-cap)))
       (let loop ((pairs alist))
         (if (pair? pairs)
             (let ((entry (car pairs)))
               (if (pair? entry)
                   (%ht-set-single! ht (car entry) (cdr entry))
                   #f)
               (loop (cdr pairs)))
             ht))))))

(define (hash-table-copy ht)
  (let* ((new-ht (%make-hash-table-full (%ht-equal ht) (%ht-hash ht) (vector-length (%ht-buckets ht))))
         (buckets (%ht-buckets ht))
         (len (vector-length buckets)))
    (let loop-b ((b-idx 0))
      (if (< b-idx len)
          (let loop-chain ((chain (vector-ref buckets b-idx)))
            (if (pair? chain)
                (begin
                  (%ht-set-single! new-ht (caar chain) (cdar chain))
                  (loop-chain (cdr chain)))
                (loop-b (+ b-idx 1))))
          new-ht))))

(define hash-table
  (case-lambda
    (()
     (make-hash-table %ht-equal? hash))
    ((comparator-or-first-key)
     (if (hash-table? comparator-or-first-key)
         (hash-table-copy comparator-or-first-key)
         (make-hash-table %ht-equal? hash)))
    ((first-key first-val . rest)
     (let ((ht (make-hash-table %ht-equal? hash)))
       (%ht-set-single! ht first-key first-val)
       (let loop ((args rest))
         (if (and (pair? args) (pair? (cdr args)))
             (begin
               (%ht-set-single! ht (car args) (cadr args))
               (loop (cddr args)))
             ht))))))

;; ---------------------------------------------------------------------
;; §8. Whole-Table Operations
;; ---------------------------------------------------------------------

(define (hash-table-size ht)
  (%ht-size ht))

(define (hash-table-keys ht)
  (let* ((buckets (%ht-buckets ht))
         (len (vector-length buckets)))
    (let loop-b ((b-idx 0) (acc '()))
      (if (< b-idx len)
          (let loop-chain ((chain (vector-ref buckets b-idx)) (inner-acc acc))
            (if (pair? chain)
                (loop-chain (cdr chain) (cons (caar chain) inner-acc))
                (loop-b (+ b-idx 1) inner-acc)))
          acc))))

(define (hash-table-values ht)
  (let* ((buckets (%ht-buckets ht))
         (len (vector-length buckets)))
    (let loop-b ((b-idx 0) (acc '()))
      (if (< b-idx len)
          (let loop-chain ((chain (vector-ref buckets b-idx)) (inner-acc acc))
            (if (pair? chain)
                (loop-chain (cdr chain) (cons (cdar chain) inner-acc))
                (loop-b (+ b-idx 1) inner-acc)))
          acc))))

(define (hash-table->alist ht)
  (let* ((buckets (%ht-buckets ht))
         (len (vector-length buckets)))
    (let loop-b ((b-idx 0) (acc '()))
      (if (< b-idx len)
          (let loop-chain ((chain (vector-ref buckets b-idx)) (inner-acc acc))
            (if (pair? chain)
                (loop-chain (cdr chain) (cons (cons (caar chain) (cdar chain)) inner-acc))
                (loop-b (+ b-idx 1) inner-acc)))
          acc))))

(define (hash-table-merge! ht1 ht2)
  (let* ((buckets (%ht-buckets ht2))
         (len (vector-length buckets)))
    (let loop-b ((b-idx 0))
      (if (< b-idx len)
          (let loop-chain ((chain (vector-ref buckets b-idx)))
            (if (pair? chain)
                (begin
                  (%ht-set-single! ht1 (caar chain) (cdar chain))
                  (loop-chain (cdr chain)))
                (loop-b (+ b-idx 1))))
          ht1))))

;; ---------------------------------------------------------------------
;; §9. Iteration & Mapping
;; ---------------------------------------------------------------------

(define hash-table-for-each
  (case-lambda
    ((proc ht)
     (let* ((buckets (%ht-buckets ht))
            (len (vector-length buckets)))
       (let loop-b ((b-idx 0))
         (if (< b-idx len)
             (let loop-chain ((chain (vector-ref buckets b-idx)))
               (if (pair? chain)
                   (begin
                     (proc (caar chain) (cdar chain))
                     (loop-chain (cdr chain)))
                   (loop-b (+ b-idx 1))))
             #t))))
    ((ht proc dummy)
     ;; SRFI 69 style argument order: (hash-table-walk ht proc)
     (hash-table-for-each proc ht))))

(define (hash-table-walk ht proc)
  (hash-table-for-each proc ht))

(define (hash-table-fold ht kons knil)
  (let* ((buckets (%ht-buckets ht))
         (len (vector-length buckets)))
    (let loop-b ((b-idx 0) (acc knil))
      (if (< b-idx len)
          (let loop-chain ((chain (vector-ref buckets b-idx)) (inner-acc acc))
            (if (pair? chain)
                (loop-chain (cdr chain) (kons (caar chain) (cdar chain) inner-acc))
                (loop-b (+ b-idx 1) inner-acc)))
          acc))))

(define (hash-table-map proc ht)
  (let ((new-ht (make-hash-table (%ht-equal ht) (%ht-hash ht))))
    (hash-table-for-each
     (lambda (k v)
       (%ht-set-single! new-ht k (proc k v)))
     ht)
    new-ht))

(define (hash-table-map->list proc ht)
  (hash-table-fold
   ht
   (lambda (k v acc)
     (cons (proc k v) acc))
   '()))
