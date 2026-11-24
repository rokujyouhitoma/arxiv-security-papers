;;; =======================================================================
;;; Library: SRFI 151 / (scheme bitwise)
;;; Specification: Bitwise Operations (R7RS-large Tangerine Edition)
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; --- Internal Helper: 2^n Power Calculator ---
(define (%bitwise-expt-2 n)
  (let loop ((k n) (acc 1))
    (if (<= k 0)
        acc
        (loop (- k 1) (* acc 2)))))

;; --- Internal Helper: Floor Integer Division for Negative Shift ---
(define (%bitwise-ashr i shift)
  (if (>= shift 62)
      -1
      (let* ((d (%bitwise-expt-2 shift))
             (q (quotient i d))
             (r (- i (* q d))))
        (if (zero? r)
            q
            (- q 1)))))

;; =======================================================================
;; §1 / SRFI 151: Basic Boolean Operations (11 Procedures)
;; =======================================================================

;; bitwise-not: Returns the bitwise complement (2's complement: -1 - i)
(define (bitwise-not i)
  (- -1 i))

;; Note: bitwise-and and bitwise-ior are compiler builtin primitives desugared
;; variadically (0-ary, 1-ary, 2-ary, and n-ary) by Pass 026 into native CPU instructions.

;; bitwise-xor: n-ary bitwise exclusive OR
(define (%bitwise-xor2 a b)
  (if (or (bignum? a) (bignum? b))
      (bignum-demote (bignum-bitwise-xor (%ensure-bignum a) (%ensure-bignum b)))
      (- (bitwise-ior a b) (bitwise-and a b))))

(define bitwise-xor
  (case-lambda
    (() 0)
    ((a) a)
    ((a b) (%bitwise-xor2 a b))
    ((a b . rest)
     (let loop ((acc (%bitwise-xor2 a b)) (lst rest))
       (if (null? lst)
           acc
           (loop (%bitwise-xor2 acc (car lst)) (cdr lst)))))))

;; bitwise-eqv: n-ary bitwise equivalence (evaluated associatively per SRFI 151)
(define (%bitwise-eqv2 a b)
  (bitwise-not (%bitwise-xor2 a b)))

(define bitwise-eqv
  (case-lambda
    (() -1)
    ((a) a)
    ((a b) (%bitwise-eqv2 a b))
    ((a b . rest)
     (let loop ((acc (%bitwise-eqv2 a b)) (lst rest))
       (if (null? lst)
           acc
           (loop (%bitwise-eqv2 acc (car lst)) (cdr lst)))))))

;; bitwise-nand: NOT (AND i j)
(define (bitwise-nand i j)
  (bitwise-not (bitwise-and i j)))

;; bitwise-nor: NOT (IOR i j)
(define (bitwise-nor i j)
  (bitwise-not (bitwise-ior i j)))

;; bitwise-andc1: (NOT i) AND j
(define (bitwise-andc1 i j)
  (bitwise-and (bitwise-not i) j))

;; bitwise-andc2: i AND (NOT j)
(define (bitwise-andc2 i j)
  (bitwise-and i (bitwise-not j)))

;; bitwise-orc1: (NOT i) IOR j
(define (bitwise-orc1 i j)
  (bitwise-ior (bitwise-not i) j))

;; bitwise-orc2: i IOR (NOT j)
(define (bitwise-orc2 i j)
  (bitwise-ior i (bitwise-not j)))

;; =======================================================================
;; §2 / SRFI 151: Integer Operations & Shift (4 Procedures)
;; =======================================================================

;; arithmetic-shift: Arithmetic shift i by count bits (bignum-safe, Issue #932)
(define (arithmetic-shift i count)
  (cond
    ((zero? count) i)
    ((or (bignum? i) (>= count 60) (<= count -60))
     (bignum-demote
      (if (> count 0)
          (bignum-shift-left (%ensure-bignum i) count)
          (bignum-shift-right (%ensure-bignum i) (- 0 count)))))
    ((> count 0)
     (* i (%bitwise-expt-2 count)))
    (else
     (let ((shift (- count)))
       (if (>= i 0)
           (quotient i (%bitwise-expt-2 shift))
           (%bitwise-ashr i shift))))))

;; bit-count: Population count of set bits (for negative, count of cleared bits)
(define (bit-count i)
  (if (>= i 0)
      (let loop ((n i) (cnt 0))
        (if (zero? n)
            cnt
            (loop (bitwise-and n (- n 1)) (+ cnt 1))))
      (bit-count (bitwise-not i))))

;; integer-length: Number of bits needed to represent i in two's complement
(define (integer-length i)
  (let ((n (if (< i 0) (bitwise-not i) i)))
    (let loop ((val n) (len 0))
      (if (zero? val)
          len
          (loop (quotient val 2) (+ len 1))))))

;; bitwise-if: Bitwise selection: (mask AND i) IOR ((NOT mask) AND j)
(define (bitwise-if mask i j)
  (bitwise-ior (bitwise-and mask i)
               (bitwise-and (bitwise-not mask) j)))

;; =======================================================================
;; §3 / SRFI 151: Single-Bit Operations (6 Procedures)
;; =======================================================================

;; bit-set?: Test if bit at index is 1
(define (bit-set? index i)
  (if (>= index 62)
      (< i 0)
      (not (zero? (bitwise-and (arithmetic-shift i (- index)) 1)))))

;; copy-bit: Set or clear bit at index based on boolean
(define (copy-bit index i boolean)
  (let ((mask (arithmetic-shift 1 index)))
    (if boolean
        (bitwise-ior i mask)
        (bitwise-and i (bitwise-not mask)))))

;; bit-swap: Swap bits at index1 and index2
(define (bit-swap index1 index2 i)
  (let ((b1 (bit-set? index1 i))
        (b2 (bit-set? index2 i)))
    (if (eq? b1 b2)
        i
        (copy-bit index2 (copy-bit index1 i b2) b1))))

;; any-bit-set?: Test if any bits in test-bits are 1 in i
(define (any-bit-set? test-bits i)
  (not (zero? (bitwise-and test-bits i))))

;; every-bit-set?: Test if all bits in test-bits are 1 in i
(define (every-bit-set? test-bits i)
  (= (bitwise-and test-bits i) test-bits))

;; first-set-bit: Index of lowest 1 bit, or -1 if i = 0
(define (first-set-bit i)
  (if (zero? i)
      -1
      (let ((lsb (bitwise-and i (- i))))
        (- (integer-length lsb) 1))))

;; =======================================================================
;; §4 / SRFI 151: Field Operations (9 Procedures)
;; =======================================================================

;; Internal mask for field of given width
(define (%field-mask width)
  (- (arithmetic-shift 1 width) 1))

;; bit-field: Extract field [start, end) and right-shift to bit 0
(define (bit-field i start end)
  (let ((width (- end start)))
    (bitwise-and (arithmetic-shift i (- start)) (%field-mask width))))

;; bit-field-any?: True if any bit in [start, end) is 1
(define (bit-field-any? i start end)
  (not (zero? (bit-field i start end))))

;; bit-field-every?: True if all bits in [start, end) are 1
(define (bit-field-every? i start end)
  (let ((width (- end start)))
    (= (bit-field i start end) (%field-mask width))))

;; bit-field-clear: Clear bits in [start, end) to 0
(define (bit-field-clear i start end)
  (let* ((width (- end start))
         (mask (arithmetic-shift (%field-mask width) start)))
    (bitwise-and i (bitwise-not mask))))

;; bit-field-set: Set bits in [start, end) to 1
(define (bit-field-set i start end)
  (let* ((width (- end start))
         (mask (arithmetic-shift (%field-mask width) start)))
    (bitwise-ior i mask)))

;; bit-field-replace: Replace [start, end) of dst with lower (end - start) bits of src
(define (bit-field-replace dst src start end)
  (let* ((width (- end start))
         (src-field (bitwise-and src (%field-mask width))))
    (bitwise-ior (bit-field-clear dst start end)
                 (arithmetic-shift src-field start))))

;; bit-field-replace-same: Replace [start, end) of dst with [start, end) of src
(define (bit-field-replace-same dst src start end)
  (let* ((width (- end start))
         (mask (arithmetic-shift (%field-mask width) start)))
    (bitwise-if mask src dst)))

;; bit-field-rotate: Cyclic rotate of [start, end) by count bits
(define (bit-field-rotate i count start end)
  (let* ((width (- end start)))
    (if (zero? width)
        i
        (let* ((c (modulo count width))
               (field (bit-field i start end))
               (rotated (if (zero? c)
                            field
                            (bitwise-ior
                              (arithmetic-shift (bit-field field 0 (- width c)) c)
                              (arithmetic-shift field (- c width))))))
          (bit-field-replace i rotated start end)))))

;; bit-field-reverse: Reverse the order of bits in [start, end)
(define (bit-field-reverse i start end)
  (let* ((width (- end start))
         (field (bit-field i start end)))
    (let loop ((idx 0) (val field) (rev 0))
      (if (= idx width)
          (bit-field-replace i rev start end)
          (loop (+ idx 1)
                (quotient val 2)
                (+ (* rev 2) (bitwise-and val 1)))))))

;; =======================================================================
;; §5 / SRFI 151: Bitwise Fold, Unfold & Generation (4 Procedures)
;; =======================================================================

;; bitwise-fold: Fold over bits from bit 0 to (integer-length i) - 1
(define (bitwise-fold proc seed i)
  (let ((len (integer-length i)))
    (let loop ((k 0) (accum seed))
      (if (= k len)
          accum
          (loop (+ k 1) (proc (bit-set? k i) accum))))))

;; bitwise-for-each: Apply proc for effect on each bit
(define (bitwise-for-each proc i)
  (let ((len (integer-length i)))
    (let loop ((k 0))
      (if (< k len)
          (begin
            (proc (bit-set? k i))
            (loop (+ k 1)))))))

;; bitwise-unfold: Construct integer from bits produced by mapper from seed
(define (bitwise-unfold stop? mapper successor seed)
  (let loop ((s seed) (k 0) (res 0))
    (if (stop? s)
        res
        (let ((b (if (mapper s) 1 0)))
          (loop (successor s)
                (+ k 1)
                (bitwise-ior res (arithmetic-shift b k)))))))

;; make-bitwise-generator: Returns a stateful generator producing bit 0, 1, 2...
(define (make-bitwise-generator i)
  (let ((pos-box (vector 0)))
    (lambda ()
      (let* ((p (vector-ref pos-box 0))
             (res (bit-set? p i)))
        (vector-set! pos-box 0 (+ p 1))
        res))))

;; =======================================================================
;; §6 / SRFI 151: Conversions: Bits to/from Lists & Vectors (5 Procedures)
;; =======================================================================

;; bits->list: Convert integer to list of booleans
(define bits->list
  (case-lambda
    ((i) (bits->list i (integer-length i)))
    ((i len)
     (let loop ((k (- len 1)) (acc '()))
       (if (< k 0)
           acc
           (loop (- k 1) (cons (bit-set? k i) acc)))))))

;; list->bits: Convert list of booleans to integer
(define (list->bits bool-list)
  (let loop ((lst bool-list) (k 0) (res 0))
    (if (null? lst)
        res
        (loop (cdr lst)
              (+ k 1)
              (if (car lst)
                  (bitwise-ior res (arithmetic-shift 1 k))
                  res)))))

;; bits->vector: Convert integer to vector of booleans
(define bits->vector
  (case-lambda
    ((i) (bits->vector i (integer-length i)))
    ((i len)
     (let ((v (make-vector len #f)))
       (let loop ((k 0))
         (if (= k len)
             v
             (begin
               (vector-set! v k (bit-set? k i))
               (loop (+ k 1)))))))))

;; vector->bits: Convert vector of booleans to integer
(define (vector->bits bool-vector)
  (let ((len (vector-length bool-vector)))
    (let loop ((k 0) (res 0))
      (if (= k len)
          res
          (loop (+ k 1)
                (if (vector-ref bool-vector k)
                    (bitwise-ior res (arithmetic-shift 1 k))
                    res))))))

;; bits: Varargs constructor: (bits bool ...) -> integer
(define bits
  (case-lambda
    (() 0)
    (bools (list->bits bools))))

;; =======================================================================
;; §7 / SRFI 151: Compatibility Aliases (SRFI 33 / SRFI 60) (7 Procedures)
;; =======================================================================

(define bitwise-merge bitwise-if)
(define extract-bit-field bit-field)
(define test-bit-field? bit-field-any?)
(define clear-bit-field bit-field-clear)
(define replace-bit-field bit-field-replace)
(define (copy-bit-field dst start end src) (bit-field-replace dst src start end))
(define ash arithmetic-shift)
