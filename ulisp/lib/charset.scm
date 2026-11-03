;;; =======================================================================
;;; ULisp Standard Library: Character Sets — R7RS-large Red Edition / SRFI 14
;;; Specification: (scheme charset) / (srfi 14)
;;; Conforms to DSN-33 Architecture Specification & Issue #708
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 14 Internal Representation (256-bit Bytevector Bitmap)
;;   Vector layout: #(ulisp-char-set-tag <32-byte-bytevector>)
;; ---------------------------------------------------------------------

(define (%cs-bv-set! bv idx val)
  (bytevector-u8-set! bv idx val))

(define (%make-raw-charset bv)
  (let ((v (make-vector 2 #f)))
    (vector-set! v 0 'ulisp-char-set-tag)
    (vector-set! v 1 bv)
    v))

(define (%make-empty-charset)
  (%make-raw-charset (make-bytevector 32 0)))

(define (%cs-bv cs)
  (vector-ref cs 1))

(define (%cs-bit-mask bit-idx)
  (case bit-idx
    ((0) 1)
    ((1) 2)
    ((2) 4)
    ((3) 8)
    ((4) 16)
    ((5) 32)
    ((6) 64)
    (else 128)))

(define (%cs-xor a b)
  (- (bitwise-ior a b) (bitwise-and a b)))

(define (%cs-bit-ref cs cp)
  (if (or (< cp 0) (>= cp 256))
      #f
      (let* ((bv (%cs-bv cs))
             (byte-idx (quotient cp 8))
             (bit-idx (modulo cp 8))
             (b (bytevector-u8-ref bv byte-idx)))
        (not (= (bitwise-and b (%cs-bit-mask bit-idx)) 0)))))

(define (%cs-bit-set! cs cp val?)
  (if (and (>= cp 0) (< cp 256))
      (let* ((bv (%cs-bv cs))
             (byte-idx (quotient cp 8))
             (bit-idx (modulo cp 8))
             (mask (%cs-bit-mask bit-idx))
             (old (bytevector-u8-ref bv byte-idx))
             (new-b (if val?
                        (bitwise-ior old mask)
                        (bitwise-and old (%cs-xor 255 mask)))))
        (%cs-bv-set! bv byte-idx new-b))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 14 Predicates, Comparison & Hashing
;; ---------------------------------------------------------------------

(define (char-set? obj)
  (and (vector? obj)
       (= (vector-length obj) 2)
       (eq? (vector-ref obj 0) 'ulisp-char-set-tag)))

(define (%cs-equal-2? cs1 cs2)
  (let ((bv1 (%cs-bv cs1))
        (bv2 (%cs-bv cs2)))
    (let loop ((i 0))
      (if (>= i 32)
          #t
          (if (= (bytevector-u8-ref bv1 i) (bytevector-u8-ref bv2 i))
              (loop (+ i 1))
              #f)))))

(define char-set=
  (case-lambda
    (() #t)
    ((cs1) #t)
    ((cs1 cs2) (%cs-equal-2? cs1 cs2))
    ((cs1 cs2 . rest)
     (if (%cs-equal-2? cs1 cs2)
         (let loop ((prev cs2) (more rest))
           (if (null? more)
               #t
               (if (%cs-equal-2? prev (car more))
                   (loop (car more) (cdr more))
                   #f)))
         #f))))

(define (%cs-subset-2? cs1 cs2)
  (let ((bv1 (%cs-bv cs1))
        (bv2 (%cs-bv cs2)))
    (let loop ((i 0))
      (if (>= i 32)
          #t
          (let ((b1 (bytevector-u8-ref bv1 i))
                (b2 (bytevector-u8-ref bv2 i)))
            (if (= (bitwise-and b1 b2) b1)
                (loop (+ i 1))
                #f))))))

(define char-set<=
  (case-lambda
    (() #t)
    ((cs1) #t)
    ((cs1 cs2) (%cs-subset-2? cs1 cs2))
    ((cs1 cs2 . rest)
     (if (%cs-subset-2? cs1 cs2)
         (let loop ((prev cs2) (more rest))
           (if (null? more)
               #t
               (if (%cs-subset-2? prev (car more))
                   (loop (car more) (cdr more))
                   #f)))
         #f))))

(define char-set-hash
  (case-lambda
    ((cs) (char-set-hash cs 536870911))
    ((cs bound)
     (let ((bv (%cs-bv cs))
           (m (if (<= bound 0) 536870911 bound)))
       (let loop ((i 0) (h 5381))
         (if (>= i 32)
             (modulo h m)
             (loop (+ i 1)
                   (modulo (+ (* h 33) (bytevector-u8-ref bv i)) m))))))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 14 Cursors & Iteration
;; ---------------------------------------------------------------------

(define (%cs-next-set-cp cs start-cp)
  (let loop ((cp start-cp))
    (cond
      ((>= cp 256) -1)
      ((%cs-bit-ref cs cp) cp)
      (else (loop (+ cp 1))))))

(define (char-set-cursor cs)
  (%cs-next-set-cp cs 0))

(define (char-set-ref cs cursor)
  (integer->char cursor))

(define (char-set-cursor-next cs cursor)
  (%cs-next-set-cp cs (+ cursor 1)))

(define (end-of-char-set? cursor)
  (< cursor 0))

(define (char-set-fold kons knil cs)
  (let loop ((cp 0) (acc knil))
    (if (>= cp 256)
        acc
        (if (%cs-bit-ref cs cp)
            (loop (+ cp 1) (kons (integer->char cp) acc))
            (loop (+ cp 1) acc)))))

(define (char-set-unfold! p f g seed base-cs)
  (let loop ((s seed))
    (if (p s)
        base-cs
        (begin
          (%cs-bit-set! base-cs (char->integer (f s)) #t)
          (loop (g s))))))

(define char-set-unfold
  (case-lambda
    ((p f g seed)
     (char-set-unfold! p f g seed (%make-empty-charset)))
    ((p f g seed base-cs)
     (char-set-unfold! p f g seed (char-set-copy base-cs)))))

(define (char-set-for-each proc cs)
  (let loop ((cp 0))
    (if (< cp 256)
        (begin
          (if (%cs-bit-ref cs cp)
              (proc (integer->char cp)))
          (loop (+ cp 1))))))

(define (char-set-map proc cs)
  (let ((res (%make-empty-charset)))
    (let loop ((cp 0))
      (if (>= cp 256)
          res
          (begin
            (if (%cs-bit-ref cs cp)
                (%cs-bit-set! res (char->integer (proc (integer->char cp))) #t))
            (loop (+ cp 1)))))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 14 Creating Character Sets
;; ---------------------------------------------------------------------

(define (char-set-copy cs)
  (let ((src (%cs-bv cs))
        (dst (make-bytevector 32 0)))
    (let loop ((i 0))
      (if (< i 32)
          (begin
            (%cs-bv-set! dst i (bytevector-u8-ref src i))
            (loop (+ i 1)))))
    (%make-raw-charset dst)))

(define (list->char-set! char-list base-cs)
  (let loop ((xs char-list))
    (if (null? xs)
        base-cs
        (begin
          (%cs-bit-set! base-cs (char->integer (car xs)) #t)
          (loop (cdr xs))))))

(define list->char-set
  (case-lambda
    ((char-list)
     (list->char-set! char-list (%make-empty-charset)))
    ((char-list base-cs)
     (list->char-set! char-list (char-set-copy base-cs)))))

(define char-set
  (case-lambda
    (() (%make-empty-charset))
    ((c . rest)
     (list->char-set! (cons c rest) (%make-empty-charset)))))

(define (string->char-set! s base-cs)
  (let ((len (string-length s)))
    (let loop ((i 0))
      (if (>= i len)
          base-cs
          (begin
            (%cs-bit-set! base-cs (char->integer (string-ref s i)) #t)
            (loop (+ i 1)))))))

(define string->char-set
  (case-lambda
    ((s)
     (string->char-set! s (%make-empty-charset)))
    ((s base-cs)
     (string->char-set! s (char-set-copy base-cs)))))

(define (char-set-filter! pred cs base-cs)
  (let loop ((cp 0))
    (if (>= cp 256)
        base-cs
        (begin
          (if (and (%cs-bit-ref cs cp) (pred (integer->char cp)))
              (%cs-bit-set! base-cs cp #t))
          (loop (+ cp 1))))))

(define char-set-filter
  (case-lambda
    ((pred cs)
     (char-set-filter! pred cs (%make-empty-charset)))
    ((pred cs base-cs)
     (char-set-filter! pred cs (char-set-copy base-cs)))))

(define (%ucs-range->char-set-core! lower upper base-cs)
  (let ((start (if (< lower 0) 0 lower))
        (end (if (> upper 256) 256 upper)))
    (let loop ((cp start))
      (if (>= cp end)
          base-cs
          (begin
            (%cs-bit-set! base-cs cp #t)
            (loop (+ cp 1)))))))

(define ucs-range->char-set!
  (case-lambda
    ((lower upper error? base-cs)
     (%ucs-range->char-set-core! lower upper base-cs))))

(define ucs-range->char-set
  (case-lambda
    ((lower upper)
     (%ucs-range->char-set-core! lower upper (%make-empty-charset)))
    ((lower upper error?)
     (%ucs-range->char-set-core! lower upper (%make-empty-charset)))
    ((lower upper error? base-cs)
     (%ucs-range->char-set-core! lower upper (char-set-copy base-cs)))))

(define (->char-set x)
  (cond
    ((char-set? x) x)
    ((string? x) (string->char-set x))
    ((char? x) (char-set x))
    (else (error "->char-set: expected char-set, string, or char" x))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 14 Querying Character Sets
;; ---------------------------------------------------------------------

(define (char-set-size cs)
  (let loop ((cp 0) (n 0))
    (if (>= cp 256)
        n
        (loop (+ cp 1) (if (%cs-bit-ref cs cp) (+ n 1) n)))))

(define (char-set-count pred cs)
  (let loop ((cp 0) (n 0))
    (if (>= cp 256)
        n
        (loop (+ cp 1)
              (if (and (%cs-bit-ref cs cp) (pred (integer->char cp)))
                  (+ n 1)
                  n)))))

(define (char-set->list cs)
  (let loop ((cp 255) (acc '()))
    (if (< cp 0)
        acc
        (loop (- cp 1)
              (if (%cs-bit-ref cs cp)
                  (cons (integer->char cp) acc)
                  acc)))))

(define (char-set->string cs)
  (list->string (char-set->list cs)))

(define (char-set-contains? cs ch)
  (%cs-bit-ref cs (char->integer ch)))

(define (char-set-every pred cs)
  (let loop ((cp 0) (last-val #t))
    (if (>= cp 256)
        last-val
        (if (%cs-bit-ref cs cp)
            (let ((res (pred (integer->char cp))))
              (if res
                  (loop (+ cp 1) res)
                  #f))
            (loop (+ cp 1) last-val)))))

(define (char-set-any pred cs)
  (let loop ((cp 0))
    (if (>= cp 256)
        #f
        (if (%cs-bit-ref cs cp)
            (let ((res (pred (integer->char cp))))
              (if res
                  res
                  (loop (+ cp 1))))
            (loop (+ cp 1))))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 14 Character-Set Algebra
;; ---------------------------------------------------------------------

(define char-set-adjoin!
  (case-lambda
    ((cs) cs)
    ((cs . chars)
     (list->char-set! chars cs))))

(define char-set-adjoin
  (case-lambda
    ((cs) (char-set-copy cs))
    ((cs . chars)
     (list->char-set! chars (char-set-copy cs)))))

(define (%cs-delete-list! cs chars)
  (let loop ((xs chars))
    (if (null? xs)
        cs
        (begin
          (%cs-bit-set! cs (char->integer (car xs)) #f)
          (loop (cdr xs))))))

(define char-set-delete!
  (case-lambda
    ((cs) cs)
    ((cs . chars)
     (%cs-delete-list! cs chars))))

(define char-set-delete
  (case-lambda
    ((cs) (char-set-copy cs))
    ((cs . chars)
     (%cs-delete-list! (char-set-copy cs) chars))))

(define (char-set-complement! cs)
  (let ((bv (%cs-bv cs)))
    (let loop ((i 0))
      (if (< i 32)
          (begin
            (%cs-bv-set! bv i (%cs-xor 255 (bytevector-u8-ref bv i)))
            (loop (+ i 1)))))
    cs))

(define (char-set-complement cs)
  (char-set-complement! (char-set-copy cs)))

(define (%cs-union-2! dst src)
  (let ((b1 (%cs-bv dst))
        (b2 (%cs-bv src)))
    (let loop ((i 0))
      (if (< i 32)
          (begin
            (%cs-bv-set! b1 i (bitwise-ior (bytevector-u8-ref b1 i) (bytevector-u8-ref b2 i)))
            (loop (+ i 1)))))
    dst))

(define char-set-union!
  (case-lambda
    ((cs1) cs1)
    ((cs1 . rest)
     (let loop ((acc cs1) (more rest))
       (if (null? more)
           acc
           (loop (%cs-union-2! acc (car more)) (cdr more)))))))

(define char-set-union
  (case-lambda
    (() (%make-empty-charset))
    ((cs1 . rest)
     (let loop ((acc (char-set-copy cs1)) (more rest))
       (if (null? more)
           acc
           (loop (%cs-union-2! acc (car more)) (cdr more)))))))

(define (%cs-inter-2! dst src)
  (let ((b1 (%cs-bv dst))
        (b2 (%cs-bv src)))
    (let loop ((i 0))
      (if (< i 32)
          (begin
            (%cs-bv-set! b1 i (bitwise-and (bytevector-u8-ref b1 i) (bytevector-u8-ref b2 i)))
            (loop (+ i 1)))))
    dst))

(define char-set-intersection!
  (case-lambda
    ((cs1) cs1)
    ((cs1 . rest)
     (let loop ((acc cs1) (more rest))
       (if (null? more)
           acc
           (loop (%cs-inter-2! acc (car more)) (cdr more)))))))

(define char-set-intersection
  (case-lambda
    (() (char-set-complement (%make-empty-charset)))
    ((cs1 . rest)
     (let loop ((acc (char-set-copy cs1)) (more rest))
       (if (null? more)
           acc
           (loop (%cs-inter-2! acc (car more)) (cdr more)))))))

(define (%cs-diff-2! dst src)
  (let ((b1 (%cs-bv dst))
        (b2 (%cs-bv src)))
    (let loop ((i 0))
      (if (< i 32)
          (begin
            (%cs-bv-set! b1 i (bitwise-and (bytevector-u8-ref b1 i)
                                           (%cs-xor 255 (bytevector-u8-ref b2 i))))
            (loop (+ i 1)))))
    dst))

(define char-set-difference!
  (case-lambda
    ((cs1) cs1)
    ((cs1 . rest)
     (let loop ((acc cs1) (more rest))
       (if (null? more)
           acc
           (loop (%cs-diff-2! acc (car more)) (cdr more)))))))

(define char-set-difference
  (case-lambda
    ((cs1) (char-set-copy cs1))
    ((cs1 . rest)
     (let loop ((acc (char-set-copy cs1)) (more rest))
       (if (null? more)
           acc
           (loop (%cs-diff-2! acc (car more)) (cdr more)))))))

(define (%cs-xor-2! dst src)
  (let ((b1 (%cs-bv dst))
        (b2 (%cs-bv src)))
    (let loop ((i 0))
      (if (< i 32)
          (begin
            (%cs-bv-set! b1 i (%cs-xor (bytevector-u8-ref b1 i) (bytevector-u8-ref b2 i)))
            (loop (+ i 1)))))
    dst))

(define char-set-xor!
  (case-lambda
    ((cs1) cs1)
    ((cs1 . rest)
     (let loop ((acc cs1) (more rest))
       (if (null? more)
           acc
           (loop (%cs-xor-2! acc (car more)) (cdr more)))))))

(define char-set-xor
  (case-lambda
    (() (%make-empty-charset))
    ((cs1 . rest)
     (let loop ((acc (char-set-copy cs1)) (more rest))
       (if (null? more)
           acc
           (loop (%cs-xor-2! acc (car more)) (cdr more)))))))

(define char-set-diff+intersection
  (case-lambda
    ((cs1)
     (values (char-set-copy cs1) (%make-empty-charset)))
    ((cs1 . rest)
     (let ((u (let loop ((acc (%make-empty-charset)) (more rest))
                (if (null? more)
                    acc
                    (loop (%cs-union-2! acc (car more)) (cdr more))))))
       (values (%cs-diff-2! (char-set-copy cs1) u)
               (%cs-inter-2! (char-set-copy cs1) u))))))

(define char-set-diff+intersection!
  (case-lambda
    ((cs1 cs2 . rest)
     (let ((u (let loop ((acc (char-set-copy cs2)) (more rest))
                (if (null? more)
                    acc
                    (loop (%cs-union-2! acc (car more)) (cdr more))))))
       (let ((inter (%cs-inter-2! (char-set-copy cs1) u))
             (diff (%cs-diff-2! cs1 u)))
         (values diff inter))))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 14 Standard Character Sets (17 Predefined Sets)
;; ---------------------------------------------------------------------

(define char-set:empty (%make-empty-charset))
(define char-set:full (ucs-range->char-set 0 256))
(define char-set:ascii (ucs-range->char-set 0 128))
(define char-set:lower-case (ucs-range->char-set 97 123))
(define char-set:upper-case (ucs-range->char-set 65 91))
(define char-set:title-case (%make-empty-charset))
(define char-set:letter (char-set-union char-set:lower-case char-set:upper-case))
(define char-set:digit (ucs-range->char-set 48 58))
(define char-set:letter+digit (char-set-union char-set:letter char-set:digit))
(define char-set:hex-digit
  (char-set-union char-set:digit
                  (ucs-range->char-set 65 71)
                  (ucs-range->char-set 97 103)))
(define char-set:whitespace
  (list->char-set (list #\space #\tab #\newline (integer->char 11) (integer->char 12) #\return)))
(define char-set:blank
  (list->char-set (list #\space #\tab)))
(define char-set:iso-control
  (char-set-union (ucs-range->char-set 0 32)
                  (ucs-range->char-set 127 160)))
(define char-set:punctuation
  (string->char-set "!\"#%&'()*,-./:;?@[\\]_{}"))
(define char-set:symbol
  (string->char-set "$+<=>^`|~"))
(define char-set:graphic
  (char-set-union char-set:letter+digit char-set:punctuation char-set:symbol))
(define char-set:printing
  (char-set-adjoin char-set:graphic #\space))
