;;; =======================================================================
;;; ULisp Compiler: Scheme Binary Interface (.sbi v2) IR Serialization Engine
;;; Conforms to DSN-33-02, DSN-38, and Issue #839
;;; =======================================================================
;;; Provides:
;;;   1. Portable pure-Scheme FIPS 180-4 SHA-256 checksum engine
;;;   2. Bounded ULEB128 / SLEB128 varint codecs & UTF-8 codecs
;;;   3. Topological Acyclic DAG IR Serializer / Deserializer (".sbi" v2)
;;;      covering CST, HIR (L_src/L_core), MIR (L_anf/L_lifted), Typed LIR
;;;      (L_lir_core/L_lir_canonical including %inline-asm), <source-span>,
;;;      and <binding> records
;;;   4. Precompiled Header (PCH) dependency SHA-256 cache validation
;;;   5. Multi-module LIR Link-Time Optimization (LTO) merger
;;;   6. Legacy text .sbi v1 backward compatibility fallback
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Constants & Structured Error Reporting
;;; -----------------------------------------------------------------------

(define *sbi-magic-0* #x55) ; 'U'
(define *sbi-magic-1* #x53) ; 'S'
(define *sbi-magic-2* #x42) ; 'B'
(define *sbi-magic-3* #x49) ; 'I'
(define *sbi-version* 2)
(define *sbi-header-size* 56)

;; Security bounds (THREAT-839-2)
(define *sbi-max-entries* 1000000)
(define *sbi-max-bytes* 67108864)

;; IR kind codes
(define *sbi-ir-pch* 0)
(define *sbi-ir-cst* 1)
(define *sbi-ir-hir* 2)
(define *sbi-ir-mir* 3)
(define *sbi-ir-lir* 4)
(define *sbi-ir-bundle* 5)

;; DAG Node Type Tags
(define *sbi-tag-nil* #x00)
(define *sbi-tag-bool* #x01)
(define *sbi-tag-fixnum* #x02)
(define *sbi-tag-flonum* #x03)
(define *sbi-tag-char* #x04)
(define *sbi-tag-string* #x05)
(define *sbi-tag-symbol* #x06)
(define *sbi-tag-pair* #x07)
(define *sbi-tag-list* #x08)
(define *sbi-tag-vector* #x09)
(define *sbi-tag-bytevector* #x0A)
(define *sbi-tag-source-span* #x0B)
(define *sbi-tag-binding* #x0C)
(define *sbi-tag-bignum* #x0D)

;; Fixnum range fitting comfortably inside exact double-precision & 64-bit SLEB128
(define *sbi-fixnum-min* -140737488355328)
(define *sbi-fixnum-max* 140737488355327)

(define (sbi-error! msg detail)
  (raise (list 'sbi-error msg detail)))

(define (sbi-mod-pos a m)
  (let ((r (modulo a m)))
    (if (< r 0) (+ r m) r)))

;;; -----------------------------------------------------------------------
;;; 2. Portable Deep Equality & Hash Tables
;;; -----------------------------------------------------------------------
;;; Note: helpers.scm redefines equal? without vector?/bytevector?, so
;;; sbi-equal? provides complete R7RS structural comparison everywhere.

(define (sbi-bytevector=? a b)
  (let ((la (bytevector-length a))
        (lb (bytevector-length b)))
    (if (not (= la lb))
        #f
        (let loop ((i 0))
          (cond
            ((>= i la) #t)
            ((= (bytevector-u8-ref a i) (bytevector-u8-ref b i))
             (loop (+ i 1)))
            (else #f))))))

(define (sbi-equal? a b)
  (cond
    ((eq? a b) #t)
    ((and (number? a) (number? b))
     (and (eq? (exact? a) (exact? b))
          (= a b)))
    ((and (string? a) (string? b))
     (string=? a b))
    ((and (char? a) (char? b))
     (char=? a b))
    ((and (bytevector? a) (bytevector? b))
     (sbi-bytevector=? a b))
    ((and (vector? a) (vector? b))
     (let ((la (vector-length a))
           (lb (vector-length b)))
       (if (not (= la lb))
           #f
           (let loop ((i 0))
             (cond
               ((>= i la) #t)
               ((sbi-equal? (vector-ref a i) (vector-ref b i))
                (loop (+ i 1)))
               (else #f))))))
    ((and (pair? a) (pair? b))
     (and (sbi-equal? (car a) (car b))
          (sbi-equal? (cdr a) (cdr b))))
    (else #f)))

;; Portable FNV-1a-style string & integer-list hashes (kept within 28-bit positive range)
(define (sbi-hash-string s)
  (let ((len (string-length s)))
    (let loop ((i 0) (h 5381))
      (if (>= i len)
          h
          (let ((c (char->integer (string-ref s i))))
            (loop (+ i 1)
                  (sbi-mod-pos (+ (* h 33) c) 268435455)))))))

(define (sbi-hash-int-list ls)
  (let loop ((cur ls) (h 216613626))
    (if (null? cur)
        h
        (loop (cdr cur)
              (sbi-mod-pos (+ (* h 131) (sbi-mod-pos (car cur) 268435455))
                           268435455)))))

(define (sbi-hash-key k)
  (cond
    ((integer? k) (sbi-mod-pos (if (< k 0) (- 0 k) k) 268435455))
    ((string? k) (sbi-hash-string k))
    ((pair? k) (sbi-hash-int-list k))
    (else 0)))

(define (sbi-key=? a b)
  (cond
    ((and (integer? a) (integer? b)) (= a b))
    ((and (string? a) (string? b)) (string=? a b))
    ((and (pair? a) (pair? b))
     (let loop ((xs a) (ys b))
       (cond
         ((and (null? xs) (null? ys)) #t)
         ((or (null? xs) (null? ys) (not (pair? xs)) (not (pair? ys))) #f)
         ((= (car xs) (car ys)) (loop (cdr xs) (cdr ys)))
         (else #f))))
    (else #f)))

;; Hash Table: (vector buckets count cap)
(define (sbi-make-ht initial-cap)
  (vector (make-vector initial-cap '()) 0 initial-cap))

(define (sbi-ht-rehash! ht)
  (let* ((old-b (vector-ref ht 0))
         (old-cap (vector-ref ht 2))
         (new-cap (* old-cap 2))
         (new-b (make-vector new-cap '())))
    (let loop-idx ((i 0))
      (if (< i old-cap)
          (begin
            (let loop-entries ((es (vector-ref old-b i)))
              (if (pair? es)
                  (let* ((e (car es))
                         (h (sbi-mod-pos (sbi-hash-key (car e)) new-cap)))
                    (vector-set! new-b h (cons e (vector-ref new-b h)))
                    (loop-entries (cdr es)))))
            (loop-idx (+ i 1)))))
    (vector-set! ht 0 new-b)
    (vector-set! ht 2 new-cap)))

(define (sbi-ht-ref ht key default-val)
  (let* ((buckets (vector-ref ht 0))
         (cap (vector-ref ht 2))
         (idx (sbi-mod-pos (sbi-hash-key key) cap)))
    (let loop ((es (vector-ref buckets idx)))
      (cond
        ((null? es) default-val)
        ((sbi-key=? (car (car es)) key) (cdr (car es)))
        (else (loop (cdr es)))))))

(define (sbi-ht-set! ht key val)
  (let* ((cap (vector-ref ht 2))
         (count (vector-ref ht 1)))
    (if (> (* (+ count 1) 4) (* cap 3))
        (sbi-ht-rehash! ht))
    (let* ((buckets (vector-ref ht 0))
           (new-cap (vector-ref ht 2))
           (idx (sbi-mod-pos (sbi-hash-key key) new-cap))
           (bucket (vector-ref buckets idx)))
      (let loop ((es bucket))
        (cond
          ((null? es)
           (vector-set! buckets idx (cons (cons key val) bucket))
           (vector-set! ht 1 (+ count 1)))
          ((sbi-key=? (car (car es)) key)
           (set-cdr! (car es) val))
          (else (loop (cdr es))))))))

;;; -----------------------------------------------------------------------
;;; 3. Chunked Mutable Bytebuffer Writer
;;; -----------------------------------------------------------------------

(define *sbi-chunk-size* 4096)

(define (sbi-make-writer)
  ;; (vector cur-bv cur-pos completed-chunks-rev total-len)
  (vector (make-bytevector *sbi-chunk-size* 0) 0 '() 0))

(define (sbi-writer-length w)
  (+ (vector-ref w 3) (vector-ref w 1)))

(define (sbi-buf-u8! w b)
  (let ((pos (vector-ref w 1))
        (bv (vector-ref w 0)))
    (if (>= pos *sbi-chunk-size*)
        (let ((next-bv (make-bytevector *sbi-chunk-size* 0)))
          (vector-set! w 2 (cons (cons bv *sbi-chunk-size*) (vector-ref w 2)))
          (vector-set! w 3 (+ (vector-ref w 3) *sbi-chunk-size*))
          (bytevector-u8-set! next-bv 0 (sbi-mod-pos b 256))
          (vector-set! w 0 next-bv)
          (vector-set! w 1 1))
        (begin
          (bytevector-u8-set! bv pos (sbi-mod-pos b 256))
          (vector-set! w 1 (+ pos 1))))))

(define (sbi-buf-bytes! w src)
  (let ((slen (bytevector-length src)))
    (let loop ((i 0))
      (if (< i slen)
          (begin
            (sbi-buf-u8! w (bytevector-u8-ref src i))
            (loop (+ i 1)))))))

(define (sbi-buf-u16-le! w val)
  (let ((u (sbi-mod-pos val 65536)))
    (sbi-buf-u8! w (modulo u 256))
    (sbi-buf-u8! w (quotient u 256))))

(define (sbi-buf-u32-le! w val)
  (let* ((u (sbi-mod-pos val 4294967296))
         (b0 (modulo u 256))
         (q0 (quotient u 256))
         (b1 (modulo q0 256))
         (q1 (quotient q0 256))
         (b2 (modulo q1 256))
         (b3 (quotient q1 256)))
    (sbi-buf-u8! w b0)
    (sbi-buf-u8! w b1)
    (sbi-buf-u8! w b2)
    (sbi-buf-u8! w b3)))

(define (sbi-writer->bytevector w)
  (let* ((tail-bv (vector-ref w 0))
         (tail-len (vector-ref w 1))
         (chunks (reverse (cons (cons tail-bv tail-len) (vector-ref w 2))))
         (total (+ (vector-ref w 3) tail-len))
         (out (make-bytevector total 0)))
    (let loop ((cs chunks) (off 0))
      (if (null? cs)
          out
          (let* ((c (car cs))
                 (cbv (car c))
                 (clen (cdr c)))
            (let copy-loop ((i 0))
              (if (< i clen)
                  (begin
                    (bytevector-u8-set! out (+ off i) (bytevector-u8-ref cbv i))
                    (copy-loop (+ i 1)))))
            (loop (cdr cs) (+ off clen)))))))

;;; -----------------------------------------------------------------------
;;; 4. Bounded ULEB128 / SLEB128 Varint Codecs
;;; -----------------------------------------------------------------------

(define (sbi-buf-uleb128! w n)
  (if (< n 0)
      (sbi-error! "sbi-buf-uleb128!: negative value" n))
  (let loop ((val n))
    (let ((b (modulo val 128))
          (rest (quotient val 128)))
      (if (= rest 0)
          (sbi-buf-u8! w b)
          (begin
            (sbi-buf-u8! w (+ b 128))
            (loop rest))))))

(define (sbi-buf-sleb128! w n)
  (let loop ((val n))
    (let* ((byte (sbi-mod-pos val 128))
           (q (quotient (- val byte) 128))
           (sign-bit (>= byte 64))
           (done? (or (and (= q 0) (not sign-bit))
                      (and (= q -1) sign-bit))))
      (if done?
          (sbi-buf-u8! w byte)
          (begin
            (sbi-buf-u8! w (+ byte 128))
            (loop q))))))

(define (sbi-write-uleb128 n)
  (let ((w (sbi-make-writer)))
    (sbi-buf-uleb128! w n)
    (sbi-writer->bytevector w)))

(define (sbi-write-sleb128 n)
  (let ((w (sbi-make-writer)))
    (sbi-buf-sleb128! w n)
    (sbi-writer->bytevector w)))

(define (sbi-read-uleb128 bv offset)
  (let ((len (bytevector-length bv)))
    (let loop ((pos offset) (shift 0) (acc 0) (pow 1))
      (if (>= shift 64)
          (sbi-error! "ULEB128 integer overflow (>64 bits)" pos))
      (if (>= pos len)
          (sbi-error! "Unexpected EOF while reading ULEB128" pos))
      (let ((b (bytevector-u8-ref bv pos)))
        (if (< b 128)
            (cons (+ acc (* b pow)) (+ pos 1))
            (loop (+ pos 1)
                  (+ shift 7)
                  (+ acc (* (- b 128) pow))
                  (* pow 128)))))))

(define (sbi-read-sleb128 bv offset)
  (let ((len (bytevector-length bv)))
    (let loop ((pos offset) (shift 0) (acc 0) (pow 1))
      (if (>= shift 64)
          (sbi-error! "SLEB128 integer overflow (>64 bits)" pos))
      (if (>= pos len)
          (sbi-error! "Unexpected EOF while reading SLEB128" pos))
      (let* ((b (bytevector-u8-ref bv pos))
             (low (modulo b 128))
             (next-acc (+ acc (* low pow)))
             (next-pow (* pow 128)))
        (if (< b 128)
            (let ((val (if (>= b 64) (- next-acc next-pow) next-acc)))
              (cons val (+ pos 1)))
            (loop (+ pos 1) (+ shift 7) next-acc next-pow))))))

;;; -----------------------------------------------------------------------
;;; 5. Portable UTF-8 Encoder & Decoder
;;; -----------------------------------------------------------------------

(define (sbi-string->utf8-bytes str)
  (let* ((slen (string-length str))
         (ascii? (let check ((i 0))
                   (cond
                     ((>= i slen) #t)
                     ((< (char->integer (string-ref str i)) 128) (check (+ i 1)))
                     (else #f)))))
    (if ascii?
        (let ((bv (make-bytevector slen 0)))
          (let loop ((i 0))
            (if (< i slen)
                (begin
                  (bytevector-u8-set! bv i (char->integer (string-ref str i)))
                  (loop (+ i 1)))))
          bv)
        (let ((w (sbi-make-writer)))
          (let loop ((i 0))
            (if (< i slen)
                (let ((cp (char->integer (string-ref str i))))
                  (cond
                    ((< cp #x80)
                     (sbi-buf-u8! w cp))
                    ((< cp #x800)
                     (sbi-buf-u8! w (+ #xC0 (quotient cp 64)))
                     (sbi-buf-u8! w (+ #x80 (modulo cp 64))))
                    ((< cp #x10000)
                     (sbi-buf-u8! w (+ #xE0 (quotient cp 4096)))
                     (sbi-buf-u8! w (+ #x80 (modulo (quotient cp 64) 64)))
                     (sbi-buf-u8! w (+ #x80 (modulo cp 64))))
                    (else
                     (sbi-buf-u8! w (+ #xF0 (quotient cp 262144)))
                     (sbi-buf-u8! w (+ #x80 (modulo (quotient cp 4096) 64)))
                     (sbi-buf-u8! w (+ #x80 (modulo (quotient cp 64) 64)))
                     (sbi-buf-u8! w (+ #x80 (modulo cp 64)))))
                  (loop (+ i 1)))))
          (sbi-writer->bytevector w)))))

(define (sbi-utf8-slice->string bv start end)
  (let ((blen (bytevector-length bv)))
    (if (or (< start 0) (< end start) (> end blen))
        (sbi-error! "UTF-8 slice out of bounds" (list start end blen)))
    (let ((ascii? (let check ((i start))
                    (cond
                      ((>= i end) #t)
                      ((< (bytevector-u8-ref bv i) 128) (check (+ i 1)))
                      (else #f)))))
      (if ascii?
          (let* ((slen (- end start))
                 (s (make-string slen)))
            (let loop ((i 0))
              (if (< i slen)
                  (begin
                    (string-set! s i (integer->char (bytevector-u8-ref bv (+ start i))))
                    (loop (+ i 1)))))
            s)
          (let loop ((i start) (acc '()))
            (if (>= i end)
                (list->string (reverse acc))
                (let ((b0 (bytevector-u8-ref bv i)))
                  (cond
                    ((< b0 #x80)
                     (loop (+ i 1) (cons (integer->char b0) acc)))
                    ((and (>= b0 #xC2) (<= b0 #xDF) (< (+ i 1) end))
                     (let ((b1 (bytevector-u8-ref bv (+ i 1))))
                       (if (not (= (quotient b1 64) 2))
                           (sbi-error! "Malformed 2-byte UTF-8 sequence" i))
                       (loop (+ i 2)
                             (cons (integer->char (+ (* (- b0 #xC0) 64) (- b1 #x80)))
                                   acc))))
                    ((and (>= b0 #xE0) (<= b0 #xEF) (< (+ i 2) end))
                     (let ((b1 (bytevector-u8-ref bv (+ i 1)))
                           (b2 (bytevector-u8-ref bv (+ i 2))))
                       (if (or (not (= (quotient b1 64) 2))
                               (not (= (quotient b2 64) 2)))
                           (sbi-error! "Malformed 3-byte UTF-8 sequence" i))
                       (loop (+ i 3)
                             (cons (integer->char (+ (* (- b0 #xE0) 4096)
                                                     (+ (* (- b1 #x80) 64) (- b2 #x80))))
                                   acc))))
                    ((and (>= b0 #xF0) (<= b0 #xF4) (< (+ i 3) end))
                     (let ((b1 (bytevector-u8-ref bv (+ i 1)))
                           (b2 (bytevector-u8-ref bv (+ i 2)))
                           (b3 (bytevector-u8-ref bv (+ i 3))))
                       (if (or (not (= (quotient b1 64) 2))
                               (not (= (quotient b2 64) 2))
                               (not (= (quotient b3 64) 2)))
                           (sbi-error! "Malformed 4-byte UTF-8 sequence" i))
                       (loop (+ i 4)
                             (cons (integer->char (+ (* (- b0 #xF0) 262144)
                                                     (+ (* (- b1 #x80) 4096)
                                                        (+ (* (- b2 #x80) 64) (- b3 #x80)))))
                                   acc))))
                    (else
                     (sbi-error! "Invalid UTF-8 byte sequence in SBI pool" i))))))))))

;;; -----------------------------------------------------------------------
;;; 6. Portable Pure-Scheme FIPS 180-4 SHA-256 Checksum Engine
;;; -----------------------------------------------------------------------

(define *sbi-pow2*
  (let ((v (make-vector 33 1)))
    (let loop ((i 1) (p 1))
      (if (<= i 32)
          (let ((np (* p 2)))
            (vector-set! v i np)
            (loop (+ i 1) np))))
    v))

(define (sbi-u32-add a b)
  (bitwise-and (+ a b) 4294967295))

(define (sbi-u32-rotr x n)
  (let* ((p (vector-ref *sbi-pow2* n))
         (q (quotient x p))
         (r (bitwise-and x (- p 1))))
    (+ (* r (vector-ref *sbi-pow2* (- 32 n))) q)))

(define (sbi-u32-shr x n)
  (quotient x (vector-ref *sbi-pow2* n)))

(define (sbi-u32-and x y)
  (bitwise-and x y))

(define (sbi-u32-xor x y)
  (- (bitwise-ior x y) (bitwise-and x y)))

(define (sbi-u32-xor3 x y z)
  (let ((xy (- (bitwise-ior x y) (bitwise-and x y))))
    (- (bitwise-ior xy z) (bitwise-and xy z))))

(define (sbi-sha256-sigma0 x)
  (let* ((q3 (quotient x 8))
         (q7 (quotient q3 16))
         (r7 (+ (* (bitwise-and x 127) 33554432) q7))
         (q18 (quotient q7 2048))
         (r18 (+ (* (bitwise-and x 262143) 16384) q18)))
    (sbi-u32-xor3 r7 r18 q3)))

(define (sbi-sha256-sigma1 x)
  (let* ((q10 (quotient x 1024))
         (q17 (quotient q10 128))
         (r17 (+ (* (bitwise-and x 131071) 32768) q17))
         (q19 (quotient q17 4))
         (r19 (+ (* (bitwise-and x 524287) 8192) q19)))
    (sbi-u32-xor3 r17 r19 q10)))

(define (sbi-sha256-Sigma0 x)
  (let* ((q2 (quotient x 4))
         (r2 (+ (* (bitwise-and x 3) 1073741824) q2))
         (q13 (quotient q2 2048))
         (r13 (+ (* (bitwise-and x 8191) 524288) q13))
         (q22 (quotient q13 512))
         (r22 (+ (* (bitwise-and x 4194303) 1024) q22)))
    (sbi-u32-xor3 r2 r13 r22)))

(define (sbi-sha256-Sigma1 x)
  (let* ((q6 (quotient x 64))
         (r6 (+ (* (bitwise-and x 63) 67108864) q6))
         (q11 (quotient q6 32))
         (r11 (+ (* (bitwise-and x 2047) 2097152) q11))
         (q25 (quotient q11 16384))
         (r25 (+ (* (bitwise-and x 33554431) 128) q25)))
    (sbi-u32-xor3 r6 r11 r25)))

(define *sbi-sha256-k*
  (vector
    #x428a2f98 #x71374491 #xb5c0fbcf #xe9b5dba5 #x3956c25b #x59f111f1 #x923f82a4 #xab1c5ed5
    #xd807aa98 #x12835b01 #x243185be #x550c7dc3 #x72be5d74 #x80deb1fe #x9bdc06a7 #xc19bf174
    #xe49b69c1 #xefbe4786 #x0fc19dc6 #x240ca1cc #x2de92c6f #x4a7484aa #x5cb0a9dc #x76f988da
    #x983e5152 #xa831c66d #xb00327c8 #xbf597fc7 #xc6e00bf3 #xd5a79147 #x06ca6351 #x14292967
    #x27b70a85 #x2e1b2138 #x4d2c6dfc #x53380d13 #x650a7354 #x766a0abb #x81c2c92e #x92722c85
    #xa2bfe8a1 #xa81a664b #xc24b8b70 #xc76c51a3 #xd192e819 #xd6990624 #xf40e3585 #x106aa070
    #x19a4c116 #x1e376c08 #x2748774c #x34b0bcb5 #x391c0cb3 #x4ed8aa4a #x5b9cca4f #x682e6ff3
    #x748f82ee #x78a5636f #x84c87814 #x8cc70208 #x90befffa #xa4506ceb #xbef9a3f7 #xc67178f2))

(define (sbi-sha256-pad-bytevector bv start-off total-len)
  (let* ((rem (- total-len start-off))
         (mod64 (modulo (+ rem 9) 64))
         (pad-zeros (if (= mod64 0) 0 (- 64 mod64)))
         (padded-len (+ (+ (+ rem 1) pad-zeros) 8))
         (out (make-bytevector padded-len 0)))
    (let copy-loop ((i 0))
      (if (< i rem)
          (begin
            (bytevector-u8-set! out i (bytevector-u8-ref bv (+ start-off i)))
            (copy-loop (+ i 1)))))
    (bytevector-u8-set! out rem #x80)
    ;; Append 64-bit big-endian bit length
    (let ((bit-len (* rem 8))
          (tail-pos (- padded-len 8)))
      (let bit-loop ((k 7) (v bit-len))
        (if (>= k 0)
            (begin
              (bytevector-u8-set! out (+ tail-pos k) (modulo v 256))
              (bit-loop (- k 1) (quotient v 256))))))
    out))

(define (sbi-sha256-bytevector-range bv start-off end-off)
  (let* ((padded (sbi-sha256-pad-bytevector bv start-off end-off))
         (plen (bytevector-length padded))
         (num-blocks (quotient plen 64))
         (h (vector #x6a09e667 #xbb67ae85 #x3c6ef372 #xa54ff53a
                    #x510e527f #x9b05688c #x1f83d9ab #x5be0cd19))
         (w (make-vector 64 0)))
    (let block-loop ((blk 0))
      (if (< blk num-blocks)
          (let ((base (* blk 64)))
            ;; W[0..15] from big-endian 32-bit words
            (let load-loop ((i 0))
              (if (< i 16)
                  (let* ((p (+ base (* i 4)))
                         (wval (+ (+ (* (bytevector-u8-ref padded p) 16777216)
                                     (* (bytevector-u8-ref padded (+ p 1)) 65536))
                                  (+ (* (bytevector-u8-ref padded (+ p 2)) 256)
                                     (bytevector-u8-ref padded (+ p 3))))))
                    (vector-set! w i wval)
                    (load-loop (+ i 1)))))
            ;; W[16..63]
            (let exp-loop ((i 16))
              (if (< i 64)
                  (let* ((w15 (vector-ref w (- i 15)))
                         (w2 (vector-ref w (- i 2)))
                         (s0 (sbi-sha256-sigma0 w15))
                         (s1 (sbi-sha256-sigma1 w2))
                         (wval (sbi-u32-add
                                 (sbi-u32-add (vector-ref w (- i 16)) s0)
                                 (sbi-u32-add (vector-ref w (- i 7)) s1))))
                    (vector-set! w i wval)
                    (exp-loop (+ i 1)))))
            ;; Compression rounds
            (let round-loop ((i 0)
                             (a (vector-ref h 0)) (b (vector-ref h 1))
                             (c (vector-ref h 2)) (d (vector-ref h 3))
                             (e (vector-ref h 4)) (f (vector-ref h 5))
                             (g (vector-ref h 6)) (hh (vector-ref h 7)))
              (if (< i 64)
                  (let* ((S1 (sbi-sha256-Sigma1 e))
                         ;; Ch(e,f,g) = g ^ (e & (f ^ g))
                         (ch (sbi-u32-xor g (sbi-u32-and e (sbi-u32-xor f g))))
                         (temp1 (sbi-u32-add
                                  (sbi-u32-add hh S1)
                                  (sbi-u32-add
                                    (sbi-u32-add ch (vector-ref *sbi-sha256-k* i))
                                    (vector-ref w i))))
                         (S0 (sbi-sha256-Sigma0 a))
                         ;; Maj(a,b,c) = (a & b) + ((a ^ b) & c)
                         (maj (+ (sbi-u32-and a b)
                                 (sbi-u32-and (sbi-u32-xor a b) c)))
                         (temp2 (sbi-u32-add S0 maj)))
                    (round-loop (+ i 1)
                                (sbi-u32-add temp1 temp2) a b c
                                (sbi-u32-add d temp1) e f g))
                  (begin
                    (vector-set! h 0 (sbi-u32-add (vector-ref h 0) a))
                    (vector-set! h 1 (sbi-u32-add (vector-ref h 1) b))
                    (vector-set! h 2 (sbi-u32-add (vector-ref h 2) c))
                    (vector-set! h 3 (sbi-u32-add (vector-ref h 3) d))
                    (vector-set! h 4 (sbi-u32-add (vector-ref h 4) e))
                    (vector-set! h 5 (sbi-u32-add (vector-ref h 5) f))
                    (vector-set! h 6 (sbi-u32-add (vector-ref h 6) g))
                    (vector-set! h 7 (sbi-u32-add (vector-ref h 7) hh)))))
            (block-loop (+ blk 1)))))
    ;; Pack 8x u32 big-endian words into 32-byte digest
    (let ((digest (make-bytevector 32 0)))
      (let pack-loop ((i 0))
        (if (< i 8)
            (let* ((word (vector-ref h i))
                   (base (* i 4))
                   (b3 (quotient word 16777216)) (r3 (- word (* b3 16777216)))
                   (b2 (quotient r3 65536))      (r2 (- r3 (* b2 65536)))
                   (b1 (quotient r2 256))        (b0 (- r2 (* b1 256))))
              (bytevector-u8-set! digest base b3)
              (bytevector-u8-set! digest (+ base 1) b2)
              (bytevector-u8-set! digest (+ base 2) b1)
              (bytevector-u8-set! digest (+ base 3) b0)
              (pack-loop (+ i 1)))))
      digest)))

(define (sbi-sha256-bytevector bv)
  (sbi-sha256-bytevector-range bv 0 (bytevector-length bv)))

(define (sbi-sha256-string str)
  (sbi-sha256-bytevector (sbi-string->utf8-bytes str)))

(define (sbi-bytes->hex bv)
  (let* ((hex-chars "0123456789abcdef")
         (len (bytevector-length bv))
         (out (make-string (* len 2))))
    (let loop ((i 0))
      (if (< i len)
          (let ((b (bytevector-u8-ref bv i)))
            (string-set! out (* i 2) (string-ref hex-chars (quotient b 16)))
            (string-set! out (+ (* i 2) 1) (string-ref hex-chars (modulo b 16)))
            (loop (+ i 1)))))
    out))

(define (sbi-sha256-hex x)
  (cond
    ((bytevector? x) (sbi-bytes->hex (sbi-sha256-bytevector x)))
    ((string? x) (sbi-bytes->hex (sbi-sha256-string x)))
    (else (sbi-error! "sbi-sha256-hex: expected bytevector or string" x))))

;;; -----------------------------------------------------------------------
;;; 7. Binary File I/O Helpers & Dependency Path Security
;;; -----------------------------------------------------------------------

(define (sbi-coerce-path path)
  (if (and (string? path) (> (string-length path) 0))
      (symbol->string (string->symbol path))
      path))

(define (sbi-read-file-bytes path)
  (let ((port (guard (ex (else #f)) (open-binary-input-file (sbi-coerce-path path)))))
    (if (not port)
        #f
        (let ((w (sbi-make-writer)))
          (guard (ex (else
                       (guard (ex2 (else #f)) (close-input-port port))
                       (sbi-writer->bytevector w)))
            (let loop ()
              (let ((b (read-u8 port)))
                (if (eof-object? b)
                    (begin
                      (guard (ex (else #f)) (close-input-port port))
                      (sbi-writer->bytevector w))
                    (begin
                      (sbi-buf-u8! w b)
                      (loop))))))))))

(define (sbi-write-file-bytes path bv)
  (let ((port (open-binary-output-file (sbi-coerce-path path))))
    (write-bytevector bv port)
    (close-output-port port)
    #t))

(define (sbi-sha256-file path)
  (let ((bytes (sbi-read-file-bytes path)))
    (if bytes
        (sbi-sha256-bytevector bytes)
        #f)))

(define (sbi-safe-dep-path? p)
  (if (or (not (string? p)) (= (string-length p) 0))
      #f
      (let ((len (string-length p)))
        (let loop ((i 0))
          (cond
            ((>= i len) #t)
            ((= (char->integer (string-ref p i)) 0) #f)
            ((and (char=? (string-ref p i) #\.)
                  (< (+ i 1) len)
                  (char=? (string-ref p (+ i 1)) #\.))
             (let ((prev-sep? (or (= i 0)
                                  (char=? (string-ref p (- i 1)) #\/)
                                  (char=? (string-ref p (- i 1)) #\\)))
                   (next-sep? (or (= (+ i 2) len)
                                  (char=? (string-ref p (+ i 2)) #\/)
                                  (char=? (string-ref p (+ i 2)) #\\))))
               (if (and prev-sep? next-sep?)
                   #f
                   (loop (+ i 1)))))
            (else (loop (+ i 1))))))))

(define (sbi-ir-kind->code kind)
  (cond
    ((integer? kind)
     (if (and (>= kind 0) (<= kind 5))
         kind
         (sbi-error! "Invalid SBI IR kind code" kind)))
    ((eq? kind 'pch) *sbi-ir-pch*)
    ((eq? kind 'cst) *sbi-ir-cst*)
    ((eq? kind 'hir) *sbi-ir-hir*)
    ((eq? kind 'mir) *sbi-ir-mir*)
    ((eq? kind 'lir) *sbi-ir-lir*)
    ((eq? kind 'bundle) *sbi-ir-bundle*)
    (else (sbi-error! "Unknown SBI IR kind symbol" kind))))

(define (sbi-code->ir-kind code)
  (cond
    ((= code *sbi-ir-pch*) 'pch)
    ((= code *sbi-ir-cst*) 'cst)
    ((= code *sbi-ir-hir*) 'hir)
    ((= code *sbi-ir-mir*) 'mir)
    ((= code *sbi-ir-lir*) 'lir)
    ((= code *sbi-ir-bundle*) 'bundle)
    (else (sbi-error! "Unsupported SBI IR kind code in header" code))))

;;; -----------------------------------------------------------------------
;;; 8. Acyclic DAG IR Serializer (.sbi v2 Writer)
;;; -----------------------------------------------------------------------

(define (sbi-split-list xs)
  (let loop ((cur xs) (steps 0) (acc '()))
    (cond
      ((>= steps *sbi-max-entries*)
       (sbi-error! "SBI serialization exceeded maximum list length / cycle guard" steps))
      ((null? cur)
       (cons #t (reverse acc)))
      ((pair? cur)
       ;; Break before descending into a <binding> inside an improper tail
       (if (and (> steps 0) (binding? cur))
           (cons #f (cons cur acc))
           (loop (cdr cur) (+ steps 1) (cons (car cur) acc))))
      (else
       (cons #f (cons cur acc))))))

(define (sbi-normalize-deps deps)
  (if (not (list? deps))
      (sbi-error! "sbi-serialize: deps must be a list" deps))
  (let loop ((ds deps) (acc '()))
    (if (null? ds)
        (reverse acc)
        (let ((d (car ds)))
          (cond
            ((string? d)
             (if (not (sbi-safe-dep-path? d))
                 (sbi-error! "Path traversal rejected in SBI dependency path" d))
             (let ((h (sbi-sha256-file d)))
               (if (not h)
                   (sbi-error! "Missing dependency file when building SBI header checksum" d))
               (loop (cdr ds) (cons (cons d h) acc))))
            ((and (pair? d) (string? (car d)) (bytevector? (cdr d))
                  (= (bytevector-length (cdr d)) 32))
             (if (not (sbi-safe-dep-path? (car d)))
                 (sbi-error! "Path traversal rejected in SBI dependency path" (car d)))
             (loop (cdr ds) (cons d acc)))
            (else
             (sbi-error! "Invalid dependency entry (expected path string or (path . 32B-sha256))" d)))))))

(define (sbi-make-enc-state)
  ;; #(sym-ht sym-count sym-writer node-ht node-count node-writer
  ;;   nil-idx false-idx true-idx fix-ht symnode-ht strnode-ht char-ht has-spans? has-bindings?)
  (vector (sbi-make-ht 128)
          0
          (sbi-make-writer)
          (sbi-make-ht 256)
          0
          (sbi-make-writer)
          -1
          -1
          -1
          (sbi-make-ht 64)
          (sbi-make-ht 128)
          (sbi-make-ht 64)
          (sbi-make-ht 32)
          #f
          #f))

(define (sbi-intern-string! st str)
  (let ((sym-ht (vector-ref st 0)))
    (let ((existing (sbi-ht-ref sym-ht str #f)))
      (if existing
          existing
          (let ((idx (vector-ref st 1))
                (sw (vector-ref st 2))
                (utf8 (sbi-string->utf8-bytes str)))
            (if (>= idx *sbi-max-entries*)
                (sbi-error! "SBI string pool exceeded max entries" idx))
            (sbi-buf-uleb128! sw (bytevector-length utf8))
            (sbi-buf-bytes! sw utf8)
            (sbi-ht-set! sym-ht str idx)
            (vector-set! st 1 (+ idx 1))
            idx)))))

(define (sbi-alloc-node-idx! st)
  (let ((idx (vector-ref st 4)))
    (if (>= idx *sbi-max-entries*)
        (sbi-error! "SBI DAG node table exceeded max entries" idx))
    (vector-set! st 4 (+ idx 1))
    idx))

(define (sbi-encode-compound-node! st key emit-fn)
  (let* ((node-ht (vector-ref st 3))
         (existing (sbi-ht-ref node-ht key #f)))
    (if existing
        existing
        (let ((idx (sbi-alloc-node-idx! st)))
          (emit-fn (vector-ref st 5))
          (sbi-ht-set! node-ht key idx)
          idx))))

(define (sbi-emit-node! st x depth)
  (if (> depth 4096)
      (sbi-error! "SBI DAG nesting depth limit exceeded (possible cycle)" depth))
  (cond
    ((null? x)
     (let ((c (vector-ref st 6)))
       (if (>= c 0)
           c
           (let ((idx (sbi-alloc-node-idx! st)))
             (sbi-buf-u8! (vector-ref st 5) *sbi-tag-nil*)
             (vector-set! st 6 idx)
             idx))))

    ((boolean? x)
     (let* ((slot (if x 8 7))
            (c (vector-ref st slot)))
       (if (>= c 0)
           c
           (let ((idx (sbi-alloc-node-idx! st)))
             (sbi-buf-u8! (vector-ref st 5) *sbi-tag-bool*)
             (sbi-buf-u8! (vector-ref st 5) (if x 1 0))
             (vector-set! st slot idx)
             idx))))

    ;; <source-span> MUST precede (vector? x) because it is an SRFI-9 vector record
    ((source-span? x)
     (vector-set! st 13 #t)
     (let* ((f-idx (sbi-emit-node! st (span-file x) (+ depth 1)))
            (mo-idx (sbi-emit-node! st (span-macro-origin x) (+ depth 1)))
            (sl (span-start-line x))
            (sc (span-start-col x))
            (el (span-end-line x))
            (ec (span-end-col x))
            (nid (span-node-id x))
            (sline (if (and (integer? sl) (>= sl 0)) sl 1))
            (scol (if (and (integer? sc) (>= sc 0)) sc 1))
            (eline (if (and (integer? el) (>= el 0)) el 1))
            (ecol (if (and (integer? ec) (>= ec 0)) ec 1))
            (n-id (if (integer? nid) nid 0))
            (key (list *sbi-tag-source-span* f-idx sline scol eline ecol mo-idx n-id)))
       (sbi-encode-compound-node! st key
         (lambda (nw)
           (sbi-buf-u8! nw *sbi-tag-source-span*)
           (sbi-buf-uleb128! nw f-idx)
           (sbi-buf-uleb128! nw sline)
           (sbi-buf-uleb128! nw scol)
           (sbi-buf-uleb128! nw eline)
           (sbi-buf-uleb128! nw ecol)
           (sbi-buf-uleb128! nw mo-idx)
           (sbi-buf-sleb128! nw n-id)))))

    ;; <binding> MUST precede (pair? x) because it is a tagged list
    ((binding? x)
     (vector-set! st 14 #t)
     (let* ((bid (binding-id x))
            (sname-idx (sbi-emit-node! st (binding-source-name x) (+ depth 1)))
            (usym-idx (sbi-emit-node! st (binding-unique-sym x) (+ depth 1)))
            (kind-idx (sbi-emit-node! st (binding-kind x) (+ depth 1)))
            (ns-idx (sbi-emit-node! st (binding-namespace x) (+ depth 1)))
            (sid (let ((v (binding-scope-id x))) (if (integer? v) v 0)))
            (sc-idx (sbi-emit-node! st (binding-storage-class x) (+ depth 1)))
            (ty-idx (sbi-emit-node! st (binding-type-attr x) (+ depth 1)))
            (vis-idx (sbi-emit-node! st (binding-visibility x) (+ depth 1)))
            (sset-idx (sbi-emit-node! st (binding-scope-set x) (+ depth 1)))
            (span-idx (sbi-emit-node! st (binding-source-span x) (+ depth 1)))
            (key (list *sbi-tag-binding* bid sname-idx usym-idx kind-idx ns-idx
                       sid sc-idx ty-idx vis-idx sset-idx span-idx)))
       (sbi-encode-compound-node! st key
         (lambda (nw)
           (sbi-buf-u8! nw *sbi-tag-binding*)
           (sbi-buf-uleb128! nw bid)
           (sbi-buf-uleb128! nw sname-idx)
           (sbi-buf-uleb128! nw usym-idx)
           (sbi-buf-uleb128! nw kind-idx)
           (sbi-buf-uleb128! nw ns-idx)
           (sbi-buf-sleb128! nw sid)
           (sbi-buf-uleb128! nw sc-idx)
           (sbi-buf-uleb128! nw ty-idx)
           (sbi-buf-uleb128! nw vis-idx)
           (sbi-buf-uleb128! nw sset-idx)
           (sbi-buf-uleb128! nw span-idx)))))

    ((symbol? x)
     (let* ((sidx (sbi-intern-string! st (symbol->string x)))
            (sym-node-ht (vector-ref st 10))
            (existing (sbi-ht-ref sym-node-ht sidx #f)))
       (if existing
           existing
           (let ((idx (sbi-alloc-node-idx! st))
                 (nw (vector-ref st 5)))
             (sbi-buf-u8! nw *sbi-tag-symbol*)
             (sbi-buf-uleb128! nw sidx)
             (sbi-ht-set! sym-node-ht sidx idx)
             idx))))

    ((string? x)
     (let* ((sidx (sbi-intern-string! st x))
            (str-node-ht (vector-ref st 11))
            (existing (sbi-ht-ref str-node-ht sidx #f)))
       (if existing
           existing
           (let ((idx (sbi-alloc-node-idx! st))
                 (nw (vector-ref st 5)))
             (sbi-buf-u8! nw *sbi-tag-string*)
             (sbi-buf-uleb128! nw sidx)
             (sbi-ht-set! str-node-ht sidx idx)
             idx))))

    ((char? x)
     (let* ((cp (char->integer x))
            (cht (vector-ref st 12))
            (existing (sbi-ht-ref cht cp #f)))
       (if existing
           existing
           (let ((idx (sbi-alloc-node-idx! st))
                 (nw (vector-ref st 5)))
             (sbi-buf-u8! nw *sbi-tag-char*)
             (sbi-buf-uleb128! nw cp)
             (sbi-ht-set! cht cp idx)
             idx))))

    ((number? x)
     (cond
       ((and (exact? x) (integer? x) (>= x *sbi-fixnum-min*) (<= x *sbi-fixnum-max*))
        (let* ((fht (vector-ref st 9))
               (existing (sbi-ht-ref fht x #f)))
          (if existing
              existing
              (let ((idx (sbi-alloc-node-idx! st))
                    (nw (vector-ref st 5)))
                (sbi-buf-u8! nw *sbi-tag-fixnum*)
                (sbi-buf-sleb128! nw x)
                (sbi-ht-set! fht x idx)
                idx))))
       ((and (vector? x) (= (vector-length x) 2) (eq? (vector-ref x 0) 'ulisp-flonum-tag))
        (let* ((sidx (sbi-intern-string! st (number->string x)))
               (key (list *sbi-tag-flonum* sidx)))
          (sbi-encode-compound-node! st key
            (lambda (nw)
              (sbi-buf-u8! nw *sbi-tag-flonum*)
              (sbi-buf-uleb128! nw sidx)))))
       (else
        (let* ((sidx (sbi-intern-string! st (number->string x)))
               (key (list *sbi-tag-bignum* sidx)))
          (sbi-encode-compound-node! st key
            (lambda (nw)
              (sbi-buf-u8! nw *sbi-tag-bignum*)
              (sbi-buf-uleb128! nw sidx)))))))

    ((bytevector? x)
     (let ((idx (sbi-alloc-node-idx! st))
           (nw (vector-ref st 5)))
       (sbi-buf-u8! nw *sbi-tag-bytevector*)
       (sbi-buf-uleb128! nw (bytevector-length x))
       (sbi-buf-bytes! nw x)
       idx))

    ((vector? x)
     (let ((vlen (vector-length x)))
       (let loop ((i 0) (rev-idxs '()))
         (if (< i vlen)
             (loop (+ i 1)
                   (cons (sbi-emit-node! st (vector-ref x i) (+ depth 1))
                         rev-idxs))
             (let* ((elem-idxs (reverse rev-idxs))
                    (key (cons *sbi-tag-vector* (cons vlen elem-idxs))))
               (sbi-encode-compound-node! st key
                 (lambda (nw)
                   (sbi-buf-u8! nw *sbi-tag-vector*)
                   (sbi-buf-uleb128! nw vlen)
                   (for-each (lambda (ei) (sbi-buf-uleb128! nw ei)) elem-idxs))))))))

    ((pair? x)
     (let ((split (sbi-split-list x)))
       (if (car split)
           ;; Proper list (O(1) recursion depth along the spine!)
           (let ((elems (cdr split)))
             (let loop ((es elems) (cnt 0) (rev-idxs '()))
               (if (pair? es)
                   (loop (cdr es)
                         (+ cnt 1)
                         (cons (sbi-emit-node! st (car es) (+ depth 1))
                               rev-idxs))
                   (let* ((elem-idxs (reverse rev-idxs))
                          (key (cons *sbi-tag-list* (cons cnt elem-idxs))))
                     (sbi-encode-compound-node! st key
                       (lambda (nw)
                         (sbi-buf-u8! nw *sbi-tag-list*)
                         (sbi-buf-uleb128! nw cnt)
                         (for-each (lambda (ei) (sbi-buf-uleb128! nw ei)) elem-idxs)))))))
           ;; Dotted pair spine: (cdr split) is (tail rev-elems...)
           (let* ((rev-all (cdr split))
                  (tail-datum (car rev-all))
                  (rev-heads (cdr rev-all))
                  (init-cdr-idx (sbi-emit-node! st tail-datum (+ depth 1))))
             (let loop ((hs rev-heads) (cur-cdr-idx init-cdr-idx))
               (if (null? hs)
                   cur-cdr-idx
                   (let* ((car-idx (sbi-emit-node! st (car hs) (+ depth 1)))
                          (key (list *sbi-tag-pair* car-idx cur-cdr-idx))
                          (pair-idx
                            (sbi-encode-compound-node! st key
                              (lambda (nw)
                                (sbi-buf-u8! nw *sbi-tag-pair*)
                                (sbi-buf-uleb128! nw car-idx)
                                (sbi-buf-uleb128! nw cur-cdr-idx)))))
                     (loop (cdr hs) pair-idx))))))))

    (else
     (sbi-error! "Unsupported Scheme object type in SBI serializer" x))))

(define (sbi-serialize-impl ir rest)
  (let* ((ir-kind (if (pair? rest) (sbi-ir-kind->code (car rest)) *sbi-ir-hir*))
         (raw-deps (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) '()))
         (deps (sbi-normalize-deps raw-deps))
         (st (sbi-make-enc-state))
         (root-idx (sbi-emit-node! st ir 0))
         (dep-count (length deps))
         (sym-count (vector-ref st 1))
         (node-count (vector-ref st 4))
         (flags (+ (+ (if (vector-ref st 13) 1 0)
                      (if (vector-ref st 14) 2 0))
                   (if (> dep-count 0) 4 0)))
         (payload-w (sbi-make-writer)))
    ;; Section 1: Dependency header table
    (for-each
      (lambda (d)
        (let ((pbytes (sbi-string->utf8-bytes (car d))))
          (sbi-buf-uleb128! payload-w (bytevector-length pbytes))
          (sbi-buf-bytes! payload-w pbytes)
          (sbi-buf-bytes! payload-w (cdr d))))
      deps)
    ;; Section 2: Interned string / symbol pool
    (let ((sym-bv (sbi-writer->bytevector (vector-ref st 2))))
      (sbi-buf-bytes! payload-w sym-bv))
    ;; Section 3: Acyclic DAG node table
    (let ((node-bv (sbi-writer->bytevector (vector-ref st 5))))
      (sbi-buf-bytes! payload-w node-bv))
    (let* ((payload-bv (sbi-writer->bytevector payload-w))
           (digest (sbi-sha256-bytevector payload-bv))
           (hdr-w (sbi-make-writer)))
      (sbi-buf-u8! hdr-w *sbi-magic-0*)
      (sbi-buf-u8! hdr-w *sbi-magic-1*)
      (sbi-buf-u8! hdr-w *sbi-magic-2*)
      (sbi-buf-u8! hdr-w *sbi-magic-3*)
      (sbi-buf-u16-le! hdr-w *sbi-version*)
      (sbi-buf-u8! hdr-w ir-kind)
      (sbi-buf-u8! hdr-w flags)
      (sbi-buf-u32-le! hdr-w dep-count)
      (sbi-buf-u32-le! hdr-w sym-count)
      (sbi-buf-u32-le! hdr-w node-count)
      (sbi-buf-u32-le! hdr-w root-idx)
      (sbi-buf-bytes! hdr-w digest)
      (sbi-buf-bytes! hdr-w payload-bv)
      (sbi-writer->bytevector hdr-w))))

(define sbi-serialize
  (case-lambda
    ((ir) (sbi-serialize-impl ir '()))
    ((ir ir-kind) (sbi-serialize-impl ir (list ir-kind)))
    ((ir ir-kind deps) (sbi-serialize-impl ir (list ir-kind deps)))))

;;; -----------------------------------------------------------------------
;;; 9. Acyclic DAG IR Deserializer (.sbi v2 Reader & Security Verifier)
;;; -----------------------------------------------------------------------

(define (sbi-read-u16-le bv off)
  (+ (bytevector-u8-ref bv off)
     (* (bytevector-u8-ref bv (+ off 1)) 256)))

(define (sbi-read-u32-le bv off)
  (+ (+ (bytevector-u8-ref bv off)
        (* (bytevector-u8-ref bv (+ off 1)) 256))
     (+ (* (bytevector-u8-ref bv (+ off 2)) 65536)
        (* (bytevector-u8-ref bv (+ off 3)) 16777216))))

(define (sbi-binary-bytevector? bv)
  (and (bytevector? bv)
       (>= (bytevector-length bv) 4)
       (= (bytevector-u8-ref bv 0) *sbi-magic-0*)
       (= (bytevector-u8-ref bv 1) *sbi-magic-1*)
       (= (bytevector-u8-ref bv 2) *sbi-magic-2*)
       (= (bytevector-u8-ref bv 3) *sbi-magic-3*)))

(define (sbi-binary-file? path)
  (let ((port (guard (ex (else #f)) (open-binary-input-file (sbi-coerce-path path)))))
    (if (not port)
        #f
        (let* ((b0 (guard (ex (else -1)) (read-u8 port)))
               (b1 (guard (ex (else -1)) (read-u8 port)))
               (b2 (guard (ex (else -1)) (read-u8 port)))
               (b3 (guard (ex (else -1)) (read-u8 port))))
          (guard (ex (else #f)) (close-input-port port))
          (and (integer? b0) (= b0 *sbi-magic-0*)
               (integer? b1) (= b1 *sbi-magic-1*)
               (integer? b2) (= b2 *sbi-magic-2*)
               (integer? b3) (= b3 *sbi-magic-3*))))))

(define (sbi-sub-bytevector bv start len)
  (let ((out (make-bytevector len 0)))
    (let loop ((i 0))
      (if (< i len)
          (begin
            (bytevector-u8-set! out i (bytevector-u8-ref bv (+ start i)))
            (loop (+ i 1)))))
    out))

(define (sbi-verify-header-and-digest bv)
  (if (not (bytevector? bv))
      (sbi-error! "sbi-deserialize: expected bytevector" bv))
  (let ((total-len (bytevector-length bv)))
    (if (< total-len *sbi-header-size*)
        (sbi-error! "Truncated SBI header (< 56 bytes)" total-len))
    (if (> total-len *sbi-max-bytes*)
        (sbi-error! "SBI payload exceeds security size limit" total-len))
    (if (not (sbi-binary-bytevector? bv))
        (sbi-error! "Invalid SBI magic bytes (expected USBI)"
                    (list (bytevector-u8-ref bv 0) (bytevector-u8-ref bv 1)
                          (bytevector-u8-ref bv 2) (bytevector-u8-ref bv 3))))
    (let ((version (sbi-read-u16-le bv 4)))
      (if (not (= version *sbi-version*))
          (sbi-error! "Unsupported SBI format version" version)))
    (let* ((ir-kind-code (bytevector-u8-ref bv 6))
           (ir-kind (sbi-code->ir-kind ir-kind-code))
           (flags (bytevector-u8-ref bv 7))
           (dep-count (sbi-read-u32-le bv 8))
           (sym-count (sbi-read-u32-le bv 12))
           (node-count (sbi-read-u32-le bv 16))
           (root-idx (sbi-read-u32-le bv 20)))
      (if (or (> dep-count *sbi-max-entries*)
              (> sym-count *sbi-max-entries*)
              (> node-count *sbi-max-entries*))
          (sbi-error! "SBI header section count exceeds security bound"
                      (list dep-count sym-count node-count)))
      (if (= node-count 0)
          (sbi-error! "SBI node table cannot be empty" node-count))
      (if (>= root-idx node-count)
          (sbi-error! "SBI root node index out of bounds" (list root-idx node-count)))
      ;; Verify payload SHA-256 (THREAT-839-1)
      (let* ((expected-digest (sbi-sub-bytevector bv 24 32))
             (actual-digest (sbi-sha256-bytevector-range bv *sbi-header-size* total-len)))
        (if (not (sbi-bytevector=? expected-digest actual-digest))
            (sbi-error! "SBI SHA-256 payload integrity verification failed"
                        (sbi-bytes->hex actual-digest))))
      (list ir-kind flags dep-count sym-count node-count root-idx total-len))))

(define (sbi-read-deps-section bv start-pos dep-count total-len)
  (let loop ((i 0) (pos start-pos) (acc '()))
    (if (>= i dep-count)
        (cons (reverse acc) pos)
        (let* ((len-res (sbi-read-uleb128 bv pos))
               (plen (car len-res))
               (p-start (cdr len-res))
               (p-end (+ p-start plen)))
          (if (or (> plen 65536) (> (+ p-end 32) total-len))
              (sbi-error! "Corrupted SBI dependency entry length" plen))
          (let ((dep-path (sbi-utf8-slice->string bv p-start p-end)))
            (if (not (sbi-safe-dep-path? dep-path))
                (sbi-error! "Path traversal rejected in SBI dependency table" dep-path))
            (let ((sha (sbi-sub-bytevector bv p-end 32)))
              (loop (+ i 1) (+ p-end 32) (cons (cons dep-path sha) acc))))))))

(define (sbi-read-child-idx bv pos max-idx)
  (let* ((res (sbi-read-uleb128 bv pos))
         (cidx (car res)))
    (if (or (< cidx 0) (>= cidx max-idx))
        (sbi-error! "Cyclic or out-of-bounds DAG child reference" (list cidx max-idx)))
    res))

(define (sbi-deserialize-full bv)
  (let* ((hdr (sbi-verify-header-and-digest bv))
         (ir-kind (car hdr))
         (flags (cadr hdr))
         (dep-count (caddr hdr))
         (sym-count (cadddr hdr))
         (node-count (list-ref hdr 4))
         (root-idx (list-ref hdr 5))
         (total-len (list-ref hdr 6))
         ;; Section 1: Dependency header table
         (dep-res (sbi-read-deps-section bv *sbi-header-size* dep-count total-len))
         (deps (car dep-res))
         (pos-sec2 (cdr dep-res))
         ;; Section 2: Interned string/symbol pool
         (strs (make-vector sym-count ""))
         (syms (make-vector sym-count 'sbi-uninit))
         (pos-sec3
           (let loop ((i 0) (pos pos-sec2))
             (if (>= i sym-count)
                 pos
                 (let* ((len-res (sbi-read-uleb128 bv pos))
                        (slen (car len-res))
                        (s-start (cdr len-res))
                        (s-end (+ s-start slen)))
                   (if (or (> slen *sbi-max-bytes*) (> s-end total-len))
                       (sbi-error! "Corrupted SBI string pool entry length" slen))
                   (let ((s (sbi-utf8-slice->string bv s-start s-end)))
                     (vector-set! strs i s)
                     (vector-set! syms i (string->symbol s))
                     (loop (+ i 1) s-end))))))
         ;; Section 3: Acyclic DAG nodes
         (nodes (make-vector node-count #f)))
    (let node-loop ((i 0) (pos pos-sec3))
      (if (>= i node-count)
          (if (not (= pos total-len))
              (sbi-error! "Trailing bytes after SBI DAG node table" (list pos total-len)))
          (begin
            (if (>= pos total-len)
                (sbi-error! "Unexpected EOF inside SBI DAG node table" i))
            (let ((tag (bytevector-u8-ref bv pos))
                  (p1 (+ pos 1)))
              (cond
                ((= tag *sbi-tag-nil*)
                 (vector-set! nodes i '())
                 (node-loop (+ i 1) p1))

                ((= tag *sbi-tag-bool*)
                 (if (>= p1 total-len)
                     (sbi-error! "Unexpected EOF reading boolean node" i))
                 (let ((b (bytevector-u8-ref bv p1)))
                   (vector-set! nodes i (if (= b 0) #f #t))
                   (node-loop (+ i 1) (+ p1 1))))

                ((= tag *sbi-tag-fixnum*)
                 (let ((r (sbi-read-sleb128 bv p1)))
                   (vector-set! nodes i (car r))
                   (node-loop (+ i 1) (cdr r))))

                ((or (= tag *sbi-tag-flonum*) (= tag *sbi-tag-bignum*))
                 (let* ((r (sbi-read-uleb128 bv p1))
                        (sidx (car r)))
                   (if (>= sidx sym-count)
                       (sbi-error! "Number string pool index out of bounds" sidx))
                   (let* ((str (vector-ref strs sidx))
                          (num (string->number str)))
                     (if (not num)
                         (sbi-error! "Invalid numeric representation in SBI pool" str))
                     (vector-set! nodes i num)
                     (node-loop (+ i 1) (cdr r)))))

                ((= tag *sbi-tag-char*)
                 (let* ((r (sbi-read-uleb128 bv p1))
                        (cp (car r)))
                   (if (or (< cp 0) (> cp #x10FFFF))
                       (sbi-error! "Invalid Unicode code point in SBI char node" cp))
                   (vector-set! nodes i (integer->char cp))
                   (node-loop (+ i 1) (cdr r))))

                ((= tag *sbi-tag-string*)
                 (let* ((r (sbi-read-uleb128 bv p1))
                        (sidx (car r)))
                   (if (>= sidx sym-count)
                       (sbi-error! "String pool index out of bounds" sidx))
                   (vector-set! nodes i (vector-ref strs sidx))
                   (node-loop (+ i 1) (cdr r))))

                ((= tag *sbi-tag-symbol*)
                 (let* ((r (sbi-read-uleb128 bv p1))
                        (sidx (car r)))
                   (if (>= sidx sym-count)
                       (sbi-error! "Symbol pool index out of bounds" sidx))
                   (vector-set! nodes i (vector-ref syms sidx))
                   (node-loop (+ i 1) (cdr r))))

                ((= tag *sbi-tag-pair*)
                 (let* ((r1 (sbi-read-child-idx bv p1 i))
                        (r2 (sbi-read-child-idx bv (cdr r1) i)))
                   (vector-set! nodes i (cons (vector-ref nodes (car r1))
                                              (vector-ref nodes (car r2))))
                   (node-loop (+ i 1) (cdr r2))))

                ((= tag *sbi-tag-list*)
                 (let* ((lr (sbi-read-uleb128 bv p1))
                        (cnt (car lr)))
                   (if (> cnt *sbi-max-entries*)
                       (sbi-error! "SBI list length exceeds security limit" cnt))
                   (let elem-loop ((k 0) (ep (cdr lr)) (rev-acc '()))
                     (if (< k cnt)
                         (let ((er (sbi-read-child-idx bv ep i)))
                           (elem-loop (+ k 1)
                                      (cdr er)
                                      (cons (vector-ref nodes (car er)) rev-acc)))
                         (begin
                           (vector-set! nodes i (reverse rev-acc))
                           (node-loop (+ i 1) ep))))))

                ((= tag *sbi-tag-vector*)
                 (let* ((lr (sbi-read-uleb128 bv p1))
                        (cnt (car lr)))
                   (if (> cnt *sbi-max-entries*)
                       (sbi-error! "SBI vector length exceeds security limit" cnt))
                   (let ((vec (make-vector cnt #f)))
                     (let elem-loop ((k 0) (ep (cdr lr)))
                       (if (< k cnt)
                           (let ((er (sbi-read-child-idx bv ep i)))
                             (vector-set! vec k (vector-ref nodes (car er)))
                             (elem-loop (+ k 1) (cdr er)))
                           (begin
                             (vector-set! nodes i vec)
                             (node-loop (+ i 1) ep)))))))

                ((= tag *sbi-tag-bytevector*)
                 (let* ((lr (sbi-read-uleb128 bv p1))
                        (blen (car lr))
                        (b-start (cdr lr))
                        (b-end (+ b-start blen)))
                   (if (or (> blen *sbi-max-bytes*) (> b-end total-len))
                       (sbi-error! "SBI bytevector node out of bounds" blen))
                   (vector-set! nodes i (sbi-sub-bytevector bv b-start blen))
                   (node-loop (+ i 1) b-end)))

                ((= tag *sbi-tag-source-span*)
                 (let* ((r-file (sbi-read-child-idx bv p1 i))
                        (r-sl (sbi-read-uleb128 bv (cdr r-file)))
                        (r-sc (sbi-read-uleb128 bv (cdr r-sl)))
                        (r-el (sbi-read-uleb128 bv (cdr r-sc)))
                        (r-ec (sbi-read-uleb128 bv (cdr r-el)))
                        (r-mo (sbi-read-child-idx bv (cdr r-ec) i))
                        (r-id (sbi-read-sleb128 bv (cdr r-mo)))
                        (fval (vector-ref nodes (car r-file)))
                        (moval (vector-ref nodes (car r-mo)))
                        (clean-f (if (string? fval)
                                     (begin
                                       (if (not (sbi-safe-dep-path? fval))
                                           (sbi-error! "Unsafe source path in deserialized span" fval))
                                       fval)
                                     "<unknown>"))
                        (span (if (or (not moval) (source-span? moval))
                                  (make-source-span clean-f (car r-sl) (car r-sc)
                                                    (car r-el) (car r-ec) moval (car r-id))
                                  (%make-source-span-raw clean-f (car r-sl) (car r-sc)
                                                         (car r-el) (car r-ec) moval (car r-id)))))
                   (vector-set! nodes i span)
                   (node-loop (+ i 1) (cdr r-id))))

                ((= tag *sbi-tag-binding*)
                 (let* ((r-id (sbi-read-uleb128 bv p1))
                        (r-sname (sbi-read-child-idx bv (cdr r-id) i))
                        (r-usym (sbi-read-child-idx bv (cdr r-sname) i))
                        (r-kind (sbi-read-child-idx bv (cdr r-usym) i))
                        (r-ns (sbi-read-child-idx bv (cdr r-kind) i))
                        (r-sid (sbi-read-sleb128 bv (cdr r-ns)))
                        (r-sc (sbi-read-child-idx bv (cdr r-sid) i))
                        (r-ty (sbi-read-child-idx bv (cdr r-sc) i))
                        (r-vis (sbi-read-child-idx bv (cdr r-ty) i))
                        (r-sset (sbi-read-child-idx bv (cdr r-vis) i))
                        (r-span (sbi-read-child-idx bv (cdr r-sset) i))
                        (b (make-binding
                             (car r-id)
                             (vector-ref nodes (car r-sname))
                             (vector-ref nodes (car r-usym))
                             (vector-ref nodes (car r-kind))
                             (vector-ref nodes (car r-ns))
                             (car r-sid)
                             (vector-ref nodes (car r-sc))
                             (vector-ref nodes (car r-ty))
                             (vector-ref nodes (car r-vis))
                             (vector-ref nodes (car r-sset))
                             (vector-ref nodes (car r-span)))))
                   (vector-set! nodes i b)
                   (node-loop (+ i 1) (cdr r-span))))

                (else
                 (sbi-error! "Unknown SBI DAG node tag" tag)))))))
    (list (cons 'ir (vector-ref nodes root-idx))
          (cons 'ir-kind ir-kind)
          (cons 'version *sbi-version*)
          (cons 'flags flags)
          (cons 'deps deps)
          (cons 'node-count node-count)
          (cons 'sym-count sym-count))))

(define (sbi-deserialize bv)
  (cdr (assq 'ir (sbi-deserialize-full bv))))

;;; -----------------------------------------------------------------------
;;; 10. File Read/Write API, PCH Cache Validation & Compatibility Layer
;;; -----------------------------------------------------------------------

(define sbi-write-file
  (case-lambda
    ((path ir)
     (let ((bv (sbi-serialize-impl ir '())))
       (sbi-write-file-bytes path bv)
       bv))
    ((path ir ir-kind)
     (let ((bv (sbi-serialize-impl ir (list ir-kind))))
       (sbi-write-file-bytes path bv)
       bv))
    ((path ir ir-kind deps)
     (let ((bv (sbi-serialize-impl ir (list ir-kind deps))))
       (sbi-write-file-bytes path bv)
       bv))))

(define (sbi-read-file-full path)
  (let ((bytes (sbi-read-file-bytes path)))
    (if (not bytes)
        (sbi-error! "Cannot read SBI file" path))
    (sbi-deserialize-full bytes)))

(define (sbi-read-file path)
  (cdr (assq 'ir (sbi-read-file-full path))))

(define (sbi-deps-all-fresh? deps)
  (let loop ((ds deps))
    (if (null? ds)
        #t
        (let* ((d (car ds))
               (dep-path (car d))
               (expected-sha (cdr d)))
          (if (not (sbi-safe-dep-path? dep-path))
              #f
              (let ((actual-sha (sbi-sha256-file dep-path)))
                (if (and actual-sha (sbi-bytevector=? expected-sha actual-sha))
                    (loop (cdr ds))
                    #f)))))))

(define (sbi-cache-valid? sbi-path)
  (guard (ex (else #f))
    (if (not (sbi-binary-file? sbi-path))
        #f
        (let* ((meta (sbi-read-file-full sbi-path))
               (deps (cdr (assq 'deps meta))))
          (sbi-deps-all-fresh? deps)))))

(define (sbi-deps-cover? cached-deps required-paths)
  (let loop ((ps required-paths))
    (if (null? ps)
        #t
        (let* ((p (car ps))
               (found (assoc p cached-deps)))
          (if found
              (loop (cdr ps))
              #f)))))

(define (sbi-load-or-build-pch sbi-path dep-paths builder-thunk)
  (let ((cached
          (guard (ex (else #f))
            (if (sbi-binary-file? sbi-path)
                (let* ((meta (sbi-read-file-full sbi-path))
                       (deps (cdr (assq 'deps meta))))
                  (if (and (sbi-deps-cover? deps dep-paths)
                           (sbi-deps-all-fresh? deps))
                      (cdr (assq 'ir meta))
                      #f))
                #f))))
    (if cached
        cached
        (let ((ir (builder-thunk)))
          (sbi-write-file sbi-path ir 'pch dep-paths)
          ir))))

(define (sbi-import-forms path)
  (let ((cpath (sbi-coerce-path path)))
    (if (sbi-binary-file? cpath)
        (let ((datum (sbi-read-file cpath)))
          (cond
            ((null? datum) '())
            ((and (pair? datum) (eq? (car datum) '%lir-program)) (list datum))
            ((list? datum) datum)
            (else (list datum))))
        ;; Backward compatibility with legacy text S-expression .sbi v1 headers
        (slurp-single-file cpath))))

;;; -----------------------------------------------------------------------
;;; 11. Multi-Module LTO LIR Merger (sbi-merge-lir-modules)
;;; -----------------------------------------------------------------------

(define (sbi-coerce-lir-program mod)
  (let ((prog (cond
                ((bytevector? mod) (sbi-deserialize mod))
                ((string? mod) (sbi-read-file mod))
                (else mod))))
    (if (or (not (pair? prog))
            (not (eq? (car prog) '%lir-program))
            (< (length prog) 5))
        (sbi-error! "sbi-merge-lir-modules: expected %lir-program form" prog))
    prog))

(define (sbi-merge-assoc-by-key entries get-key)
  (let ((ht (sbi-make-ht 64)))
    (let loop ((es entries) (order-rev '()))
      (if (null? es)
          (map (lambda (k) (sbi-ht-ref ht k #f)) (reverse order-rev))
          (let* ((e (car es))
                 (k (symbol->string (get-key e)))
                 (seen? (sbi-ht-ref ht k #f)))
            (sbi-ht-set! ht k e)
            (loop (cdr es) (if seen? order-rev (cons k order-rev))))))))

(define (sbi-strip-trailing-main-ret insts)
  (let loop ((is insts) (acc '()))
    (cond
      ((null? is) (reverse acc))
      ((and (null? (cdr is))
            (pair? (car is))
            (eq? (caar is) '%return))
       (reverse acc))
      (else (loop (cdr is) (cons (car is) acc))))))

(define (sbi-extract-lir-clause-list decl head)
  (if (and (pair? decl) (eq? (car decl) head) (pair? (cdr decl)))
      (cadr decl)
      '()))

(define (sbi-merge-lir-modules modules)
  (if (or (not (list? modules)) (null? modules))
      (sbi-error! "sbi-merge-lir-modules: expected non-empty module list" modules))
  (let loop ((ms modules)
             (all-strings-rev '())
             (all-stackmaps-rev '())
             (all-funcs-rev '())
             (max-frame 0)
             (main-bodies-rev '()))
    (if (null? ms)
        (let* ((merged-strings (sbi-merge-assoc-by-key
                                 (reverse all-strings-rev) car*))
               (merged-stackmaps (reverse all-stackmaps-rev))
               (merged-funcs (sbi-merge-assoc-by-key
                               (reverse all-funcs-rev) cadr))
               (ordered-bodies (reverse main-bodies-rev))
               (combined-main
                 (let mloop ((bs ordered-bodies) (acc '()))
                   (cond
                     ((null? bs) (reverse acc))
                     ((null? (cdr bs))
                      (let append-tail ((ts (car bs)) (out acc))
                        (if (null? ts)
                            (reverse out)
                            (append-tail (cdr ts) (cons (car ts) out)))))
                     (else
                      (let append-init ((ts (sbi-strip-trailing-main-ret (car bs))) (out acc))
                        (if (null? ts)
                            (mloop (cdr bs) out)
                            (append-init (cdr ts) (cons (car ts) out)))))))))
          (list '%lir-program
                (list 'strings merged-strings)
                (list 'stackmaps merged-stackmaps)
                (cons '%lir-functions merged-funcs)
                (list '%lir-main
                      (list 'frame-size max-frame)
                      (cons 'body combined-main))))
        (let* ((prog (sbi-coerce-lir-program (car ms)))
               (strings-decl (list-ref prog 1))
               (stackmaps-decl (list-ref prog 2))
               (funcs-decl (list-ref prog 3))
               (main-decl (list-ref prog 4))
               (strs (sbi-extract-lir-clause-list strings-decl 'strings))
               (smaps (sbi-extract-lir-clause-list stackmaps-decl 'stackmaps))
               (fns (if (and (pair? funcs-decl) (eq? (car funcs-decl) '%lir-functions))
                        (cdr funcs-decl)
                        '()))
               (m-frame (if (and (pair? main-decl) (pair? (cdr main-decl))
                                 (pair? (cadr main-decl)) (eq? (caadr main-decl) 'frame-size))
                            (cadr (cadr main-decl))
                            0))
               (m-body (if (and (pair? main-decl) (>= (length main-decl) 3)
                                (pair? (caddr main-decl)) (eq? (car (caddr main-decl)) 'body))
                           (cdr (caddr main-decl))
                           '()))
               (s1 (let push-loop ((xs strs) (acc all-strings-rev))
                     (if (null? xs) acc (push-loop (cdr xs) (cons (car xs) acc)))))
               (s2 (let push-loop ((xs smaps) (acc all-stackmaps-rev))
                     (if (null? xs) acc (push-loop (cdr xs) (cons (car xs) acc)))))
               (f1 (let push-loop ((xs fns) (acc all-funcs-rev))
                     (if (null? xs) acc (push-loop (cdr xs) (cons (car xs) acc))))))
          (loop (cdr ms)
                s1
                s2
                f1
                (if (> m-frame max-frame) m-frame max-frame)
                (cons m-body main-bodies-rev))))))

;;; =======================================================================
;;; Freeze Graph Serialization & .rodata Bloat Guard
;;; Conforms to DSN-33-03 §7.3 & Issue #883
;;; =======================================================================

(define *max-rodata-size* 67108864) ; 64MB

(define (sbi-node-byte-size node)
  (cond
    ((number? node) 8)
    ((boolean? node) 8)
    ((char? node) 8)
    ((symbol? node) (+ 8 (string-length (symbol->string node))))
    ((string? node) (+ 8 (string-length node)))
    ((bytevector? node) (+ 8 (bytevector-length node)))
    ((pair? node) 16)
    ((vector? node) (+ 8 (* (vector-length node) 8)))
    (else 8)))

(define (freeze-graph-internal obj id-counter visited size-box max-size)
  (let ((cur-size (car size-box)))
    (if (> cur-size max-size)
        (error "E-RODATA-OVERFLOW" cur-size)
        (cond
          ((or (number? obj) (boolean? obj) (char? obj) (null? obj))
           (set-car! size-box (+ cur-size (sbi-node-byte-size obj)))
           obj)
          ((symbol? obj)
           (set-car! size-box (+ cur-size (sbi-node-byte-size obj)))
           obj)
          ((string? obj)
           (set-car! size-box (+ cur-size (sbi-node-byte-size obj)))
           obj)
          ((bytevector? obj)
           (set-car! size-box (+ cur-size (sbi-node-byte-size obj)))
           obj)
          ((pair? obj)
           (let ((entry (assq obj (car visited))))
             (if entry
                 ;; Cycle detected: return cycle-ref placeholder
                 (list 'cycle-ref (cdr entry))
                 (let* ((node-id (car id-counter))
                        (_1 (set-car! id-counter (+ node-id 1)))
                        (_2 (set-car! visited (cons (cons obj node-id) (car visited))))
                        (_3 (set-car! size-box (+ (car size-box) 16)))
                        (frozen-car (freeze-graph-internal (car obj) id-counter visited size-box max-size))
                        (frozen-cdr (freeze-graph-internal (cdr obj) id-counter visited size-box max-size)))
                   (cons frozen-car frozen-cdr)))))
          ((vector? obj)
           (let ((entry (assq obj (car visited))))
             (if entry
                 (list 'cycle-ref (cdr entry))
                 (let* ((node-id (car id-counter))
                        (len (vector-length obj))
                        (_1 (set-car! id-counter (+ node-id 1)))
                        (_2 (set-car! visited (cons (cons obj node-id) (car visited))))
                        (_3 (set-car! size-box (+ (car size-box) (+ 8 (* len 8)))))
                        (new-vec (make-vector len)))
                   (let vloop ((i 0))
                     (if (< i len)
                         (begin
                           (vector-set! new-vec i
                             (freeze-graph-internal (vector-ref obj i) id-counter visited size-box max-size))
                           (vloop (+ i 1)))
                         new-vec))))))
          (else
           (set-car! size-box (+ cur-size 8))
           obj)))))

(define (freeze! obj)
  (let ((id-counter (cons 1 '()))
        (visited (cons '() '()))
        (size-box (cons 0 '())))
    (freeze-graph-internal obj id-counter visited size-box *max-rodata-size*)))

(define (freeze-serialize-to-rodata obj max-size)
  (let* ((id-counter (cons 1 '()))
         (visited (cons '() '()))
         (size-box (cons 0 '()))
         (limit (if max-size max-size *max-rodata-size*))
         (frozen (freeze-graph-internal obj id-counter visited size-box limit)))
    (if (> (car size-box) limit)
        (error "E-RODATA-OVERFLOW" (car size-box))
        (list 'rodata-segment
              (cons 'size (car size-box))
              (cons 'max-limit limit)
              (cons 'payload frozen)))))
