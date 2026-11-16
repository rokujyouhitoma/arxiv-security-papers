(define (%vector-min a b) (if (< a b) a b))
;;; =======================================================================
;;; ULisp Standard Library: Vectors (R7RS Section 6.8, SRFI 133)
;;; Conforms to DSN-33 Architecture Specification, Issue #536 & Issue #853
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §1 Constructors
;; ---------------------------------------------------------------------

(define (make-vector-fill len fill)
  (let ((v (%make-vector len)))
    (let loop ((i 0))
      (if (< i len)
          (begin
            (vector-set! v i fill)
            (loop (+ i 1)))
          v))))

(define vector-unfold
  (case-lambda
    ((f length seed)
     (let ((res (%make-vector length)))
       (let loop ((i 0) (s seed))
         (if (< i length)
             (let ((vals (call-with-values (lambda () (f i s)) list)))
               (vector-set! res i (car vals))
               (loop (+ i 1) (cadr vals)))
             res))))
    ((f length s1 s2)
     (let ((res (%make-vector length)))
       (let loop ((i 0) (a s1) (b s2))
         (if (< i length)
             (let ((vals (call-with-values (lambda () (f i a b)) list)))
               (vector-set! res i (car vals))
               (loop (+ i 1) (cadr vals) (caddr vals)))
             res))))
    ((f length . seeds)
     (let ((res (%make-vector length)))
       (let loop ((i 0) (s seeds))
         (if (< i length)
             (let ((vals (call-with-values (lambda () (apply f (cons i s))) list)))
               (vector-set! res i (car vals))
               (loop (+ i 1) (cdr vals)))
             res))))))

(define vector-unfold-right
  (case-lambda
    ((f length seed)
     (let ((res (%make-vector length)))
       (let loop ((i (- length 1)) (s seed))
         (if (>= i 0)
             (let ((vals (call-with-values (lambda () (f i s)) list)))
               (vector-set! res i (car vals))
               (loop (- i 1) (cadr vals)))
             res))))
    ((f length s1 s2)
     (let ((res (%make-vector length)))
       (let loop ((i (- length 1)) (a s1) (b s2))
         (if (>= i 0)
             (let ((vals (call-with-values (lambda () (f i a b)) list)))
               (vector-set! res i (car vals))
               (loop (- i 1) (cadr vals) (caddr vals)))
             res))))
    ((f length . seeds)
     (let ((res (%make-vector length)))
       (let loop ((i (- length 1)) (s seeds))
         (if (>= i 0)
             (let ((vals (call-with-values (lambda () (apply f (cons i s))) list)))
               (vector-set! res i (car vals))
               (loop (- i 1) (cdr vals)))
             res))))))

(define (vector-copy-range vec start end)
  (let* ((count (- end start))
         (new-v (%make-vector count)))
    (let loop ((i 0))
      (if (< i count)
          (begin
            (vector-set! new-v i (vector-ref vec (+ start i)))
            (loop (+ i 1)))
          new-v))))

(define (vector-copy-range! to at from start end)
  (let ((count (- end start)))
    (if (and (eq? to from) (> at start))
        ;; Backward copy to handle overlapping regions
        (let loop ((i (- count 1)))
          (if (>= i 0)
              (begin
                (vector-set! to (+ at i) (vector-ref from (+ start i)))
                (loop (- i 1)))
              63))
        ;; Forward copy
        (let loop ((i 0))
          (if (< i count)
              (begin
                (vector-set! to (+ at i) (vector-ref from (+ start i)))
                (loop (+ i 1)))
              63)))))

(define (vector-fill-range! vec fill start end)
  (let loop ((i start))
    (if (< i end)
        (begin
          (vector-set! vec i fill)
          (loop (+ i 1)))
        63)))

(define (vector-reverse-copy-range vec start end)
  (let* ((count (- end start))
         (res (%make-vector count)))
    (let loop ((i 0))
      (if (< i count)
          (begin
            (vector-set! res i (vector-ref vec (- (- end 1) i)))
            (loop (+ i 1)))
          res))))

(define vector-reverse-copy
  (case-lambda
    ((vec)
     (vector-reverse-copy-range vec 0 (vector-length vec)))
    ((vec start)
     (vector-reverse-copy-range vec start (vector-length vec)))
    ((vec start end)
     (vector-reverse-copy-range vec start end))))

(define (vector-append2 v1 v2)
  (let* ((len1 (vector-length v1))
         (len2 (vector-length v2))
         (res (%make-vector (+ len1 len2))))
    (vector-copy-range! res 0 v1 0 len1)
    (vector-copy-range! res len1 v2 0 len2)
    res))

(define vector-copy
  (case-lambda
    ((vec)
     (vector-copy-range vec 0 (vector-length vec)))
    ((vec start)
     (vector-copy-range vec start (vector-length vec)))
    ((vec start end)
     (vector-copy-range vec start end))))

(define vector-copy!
  (case-lambda
    ((to at from)
     (vector-copy-range! to at from 0 (vector-length from)))
    ((to at from start)
     (vector-copy-range! to at from start (vector-length from)))
    ((to at from start end)
     (vector-copy-range! to at from start end))))

(define-syntax vector-copy!
  (syntax-rules ()
    ((vector-copy! to at from)
     (let ((f from))
       (vector-copy-range! to at f 0 (vector-length f))))
    ((vector-copy! to at from start)
     (let ((f from))
       (vector-copy-range! to at f start (vector-length f))))
    ((vector-copy! to at from start end)
     (vector-copy-range! to at from start end))))

(define vector-append
  (case-lambda
    (() (%make-vector 0))
    ((v) (vector-copy v))
    ((v1 v2) (vector-append2 v1 v2))
    ((v1 v2 . rest)
     (let loop ((acc (vector-append2 v1 v2)) (rs rest))
       (if (null? rs)
           acc
           (loop (vector-append2 acc (car rs)) (cdr rs)))))))

(define (vector-concatenate list-of-vectors)
  (let* ((total-len (let loop ((vs list-of-vectors) (acc 0))
                      (if (null? vs)
                          acc
                          (loop (cdr vs) (+ acc (vector-length (car vs)))))))
         (res (%make-vector total-len)))
    (let loop ((vs list-of-vectors) (offset 0))
      (if (null? vs)
          res
          (let* ((v (car vs))
                 (len (vector-length v)))
            (vector-copy-range! res offset v 0 len)
            (loop (cdr vs) (+ offset len)))))))

(define vector-append-subvectors
  (case-lambda
    (() (%make-vector 0))
    (args
     (let* ((total-len (let loop ((as args) (acc 0))
                         (if (null? as)
                             acc
                             (loop (cdddr as) (+ acc (- (caddr as) (cadr as)))))))
            (res (%make-vector total-len)))
       (let loop ((as args) (offset 0))
         (if (null? as)
             res
             (let* ((v (car as))
                    (start (cadr as))
                    (end (caddr as))
                    (cnt (- end start)))
               (vector-copy-range! res offset v start end)
               (loop (cdddr as) (+ offset cnt)))))))))

;; ---------------------------------------------------------------------
;; §2 Predicates
;; ---------------------------------------------------------------------

(define (vector-empty? vec)
  (= (vector-length vec) 0))

(define vector=
  (case-lambda
    ((elt=?) #t)
    ((elt=? v) #t)
    ((elt=? v1 v2)
     (let ((len1 (vector-length v1))
           (len2 (vector-length v2)))
       (if (= len1 len2)
           (let loop ((i 0))
             (if (< i len1)
                 (if (elt=? (vector-ref v1 i) (vector-ref v2 i))
                     (loop (+ i 1))
                     #f)
                 #t))
           #f)))
    ((elt=? v1 v2 . rest)
     (let ((vecs (cons v1 (cons v2 rest))))
       (let* ((len0 (vector-length v1))
              (same-len? (let loop ((vs (cdr vecs)))
                           (if (null? vs)
                               #t
                               (if (= (vector-length (car vs)) len0)
                                   (loop (cdr vs))
                                   #f)))))
         (if (not same-len?)
             #f
             (let loop ((i 0))
               (if (< i len0)
                   (let check-pair ((v0 (car vecs)) (vs (cdr vecs)))
                     (if (null? vs)
                         (loop (+ i 1))
                         (if (elt=? (vector-ref v0 i) (vector-ref (car vs) i))
                             (check-pair (car vs) (cdr vs))
                             #f)))
                   #t))))))))

;; ---------------------------------------------------------------------
;; §3 Selectors & Iterators
;; ---------------------------------------------------------------------

(define vector-fold
  (case-lambda
    ((kons knil vec)
     (let ((len (vector-length vec)))
       (let loop ((i 0) (acc knil))
         (if (< i len)
             (loop (+ i 1) (kons acc (vector-ref vec i)))
             acc))))
    ((kons knil v1 v2)
     (let ((min-len (%vector-min (vector-length v1) (vector-length v2))))
       (let loop ((i 0) (acc knil))
         (if (< i min-len)
             (loop (+ i 1) (kons acc (vector-ref v1 i) (vector-ref v2 i)))
             acc))))
    ((kons knil v1 v2 . rest)
     (let* ((vecs (cons v1 (cons v2 rest)))
            (min-len (let loop ((vs vecs) (m (vector-length v1)))
                       (if (null? vs) m (loop (cdr vs) (%vector-min m (vector-length (car vs))))))))
       (let loop ((i 0) (acc knil))
         (if (< i min-len)
             (let ((elts (map (lambda (v) (vector-ref v i)) vecs)))
               (loop (+ i 1) (apply kons (cons acc elts))))
             acc))))))

(define vector-fold-right
  (case-lambda
    ((kons knil vec)
     (let ((len (vector-length vec)))
       (let loop ((i (- len 1)) (acc knil))
         (if (>= i 0)
             (loop (- i 1) (kons acc (vector-ref vec i)))
             acc))))
    ((kons knil v1 v2)
     (let ((min-len (%vector-min (vector-length v1) (vector-length v2))))
       (let loop ((i (- min-len 1)) (acc knil))
         (if (>= i 0)
             (loop (- i 1) (kons acc (vector-ref v1 i) (vector-ref v2 i)))
             acc))))
    ((kons knil v1 v2 . rest)
     (let* ((vecs (cons v1 (cons v2 rest)))
            (min-len (let loop ((vs vecs) (m (vector-length v1)))
                       (if (null? vs) m (loop (cdr vs) (%vector-min m (vector-length (car vs))))))))
         (let loop ((i (- min-len 1)) (acc knil))
           (if (>= i 0)
               (let ((elts (map (lambda (v) (vector-ref v i)) vecs)))
                 (loop (- i 1) (apply kons (cons acc elts))))
               acc))))))

(define vector-map
  (case-lambda
    ((f vec)
     (let* ((len (vector-length vec))
            (res (%make-vector len)))
       (let loop ((i 0))
         (if (< i len)
             (begin
               (vector-set! res i (f (vector-ref vec i)))
               (loop (+ i 1)))
             res))))
    ((f v1 v2)
     (let* ((min-len (%vector-min (vector-length v1) (vector-length v2)))
            (res (%make-vector min-len)))
       (let loop ((i 0))
         (if (< i min-len)
             (begin
               (vector-set! res i (f (vector-ref v1 i) (vector-ref v2 i)))
               (loop (+ i 1)))
             res))))
    ((f v1 v2 . rest)
     (let* ((vecs (cons v1 (cons v2 rest)))
            (min-len (let loop ((vs vecs) (m (vector-length v1)))
                       (if (null? vs) m (loop (cdr vs) (%vector-min m (vector-length (car vs)))))))
            (res (%make-vector min-len)))
       (let loop ((i 0))
         (if (< i min-len)
             (begin
               (vector-set! res i (apply f (map (lambda (v) (vector-ref v i)) vecs)))
               (loop (+ i 1)))
             res))))))

(define vector-map!
  (case-lambda
    ((f target vec)
     (let ((min-len (%vector-min (vector-length target) (vector-length vec))))
       (let loop ((i 0))
         (if (< i min-len)
             (begin
               (vector-set! target i (f (vector-ref vec i)))
               (loop (+ i 1)))
             63))))
    ((f target v1 v2)
     (let ((min-len (%vector-min (vector-length target)
                         (%vector-min (vector-length v1) (vector-length v2)))))
       (let loop ((i 0))
         (if (< i min-len)
             (begin
               (vector-set! target i (f (vector-ref v1 i) (vector-ref v2 i)))
               (loop (+ i 1)))
             63))))
    ((f target v1 v2 . rest)
     (let* ((vecs (cons v1 (cons v2 rest)))
            (min-len (let loop ((vs vecs) (m (vector-length target)))
                       (if (null? vs) m (loop (cdr vs) (%vector-min m (vector-length (car vs))))))))
       (let loop ((i 0))
         (if (< i min-len)
             (begin
               (vector-set! target i (apply f (map (lambda (v) (vector-ref v i)) vecs)))
               (loop (+ i 1)))
             63))))))

(define vector-for-each
  (case-lambda
    ((f vec)
     (let ((len (vector-length vec)))
       (let loop ((i 0))
         (if (< i len)
             (begin
               (f (vector-ref vec i))
               (loop (+ i 1)))
             63))))
    ((f v1 v2)
     (let ((min-len (%vector-min (vector-length v1) (vector-length v2))))
       (let loop ((i 0))
         (if (< i min-len)
             (begin
               (f (vector-ref v1 i) (vector-ref v2 i))
               (loop (+ i 1)))
             63))))
    ((f v1 v2 . rest)
     (let* ((vecs (cons v1 (cons v2 rest)))
            (min-len (let loop ((vs vecs) (m (vector-length v1)))
                       (if (null? vs) m (loop (cdr vs) (%vector-min m (vector-length (car vs))))))))
       (let loop ((i 0))
         (if (< i min-len)
             (begin
               (apply f (map (lambda (v) (vector-ref v i)) vecs))
               (loop (+ i 1)))
             63))))))

(define vector-count
  (case-lambda
    ((pred? vec)
     (let ((len (vector-length vec)))
       (let loop ((i 0) (cnt 0))
         (if (< i len)
             (loop (+ i 1) (if (pred? (vector-ref vec i)) (+ cnt 1) cnt))
             cnt))))
    ((pred? v1 v2)
     (let ((min-len (%vector-min (vector-length v1) (vector-length v2))))
       (let loop ((i 0) (cnt 0))
         (if (< i min-len)
             (loop (+ i 1) (if (pred? (vector-ref v1 i) (vector-ref v2 i)) (+ cnt 1) cnt))
             cnt))))
    ((pred? v1 v2 . rest)
     (let* ((vecs (cons v1 (cons v2 rest)))
            (min-len (let loop ((vs vecs) (m (vector-length v1)))
                       (if (null? vs) m (loop (cdr vs) (%vector-min m (vector-length (car vs))))))))
       (let loop ((i 0) (cnt 0))
         (if (< i min-len)
             (let ((m? (apply pred? (map (lambda (v) (vector-ref v i)) vecs))))
               (loop (+ i 1) (if m? (+ cnt 1) cnt)))
             cnt))))))

(define (vector-cumulate f knil vec)
  (let* ((len (vector-length vec))
         (res (%make-vector len)))
    (let loop ((i 0) (acc knil))
      (if (< i len)
          (let ((next-acc (f acc (vector-ref vec i))))
            (vector-set! res i next-acc)
            (loop (+ i 1) next-acc))
          res))))

;; ---------------------------------------------------------------------
;; §4 Searching
;; ---------------------------------------------------------------------

(define vector-index
  (case-lambda
    ((pred? vec)
     (let ((len (vector-length vec)))
       (let loop ((i 0))
         (if (< i len)
             (if (pred? (vector-ref vec i))
                 i
                 (loop (+ i 1)))
             #f))))
    ((pred? v1 v2)
     (let ((min-len (%vector-min (vector-length v1) (vector-length v2))))
       (let loop ((i 0))
         (if (< i min-len)
             (if (pred? (vector-ref v1 i) (vector-ref v2 i))
                 i
                 (loop (+ i 1)))
             #f))))
    ((pred? v1 v2 . rest)
     (let* ((vecs (cons v1 (cons v2 rest)))
            (min-len (let loop ((vs vecs) (m (vector-length v1)))
                       (if (null? vs) m (loop (cdr vs) (%vector-min m (vector-length (car vs))))))))
       (let loop ((i 0))
         (if (< i min-len)
             (if (apply pred? (map (lambda (v) (vector-ref v i)) vecs))
                 i
                 (loop (+ i 1)))
             #f))))))

(define vector-index-right
  (case-lambda
    ((pred? vec)
     (let ((len (vector-length vec)))
       (let loop ((i (- len 1)))
         (if (>= i 0)
             (if (pred? (vector-ref vec i))
                 i
                 (loop (- i 1)))
             #f))))
    ((pred? v1 v2)
     (let ((min-len (%vector-min (vector-length v1) (vector-length v2))))
       (let loop ((i (- min-len 1)))
         (if (>= i 0)
             (if (pred? (vector-ref v1 i) (vector-ref v2 i))
                 i
                 (loop (- i 1)))
             #f))))
    ((pred? v1 v2 . rest)
     (let* ((vecs (cons v1 (cons v2 rest)))
            (min-len (let loop ((vs vecs) (m (vector-length v1)))
                       (if (null? vs) m (loop (cdr vs) (%vector-min m (vector-length (car vs))))))))
       (let loop ((i (- min-len 1)))
         (if (>= i 0)
             (if (apply pred? (map (lambda (v) (vector-ref v i)) vecs))
                 i
                 (loop (- i 1)))
             #f))))))

(define vector-skip
  (case-lambda
    ((pred? vec)
     (let ((len (vector-length vec)))
       (let loop ((i 0))
         (if (< i len)
             (if (not (pred? (vector-ref vec i)))
                 i
                 (loop (+ i 1)))
             #f))))
    ((pred? v1 v2)
     (let ((min-len (%vector-min (vector-length v1) (vector-length v2))))
       (let loop ((i 0))
         (if (< i min-len)
             (if (not (pred? (vector-ref v1 i) (vector-ref v2 i)))
                 i
                 (loop (+ i 1)))
             #f))))
    ((pred? v1 v2 . rest)
     (let* ((vecs (cons v1 (cons v2 rest)))
            (min-len (let loop ((vs vecs) (m (vector-length v1)))
                       (if (null? vs) m (loop (cdr vs) (%vector-min m (vector-length (car vs))))))))
         (let loop ((i 0))
           (if (< i min-len)
               (if (not (apply pred? (map (lambda (v) (vector-ref v i)) vecs)))
                   i
                   (loop (+ i 1)))
               #f))))))

(define vector-skip-right
  (case-lambda
    ((pred? vec)
     (let ((len (vector-length vec)))
       (let loop ((i (- len 1)))
         (if (>= i 0)
             (if (not (pred? (vector-ref vec i)))
                 i
                 (loop (- i 1)))
             #f))))
    ((pred? v1 v2)
     (let ((min-len (%vector-min (vector-length v1) (vector-length v2))))
       (let loop ((i (- min-len 1)))
         (if (>= i 0)
             (if (not (pred? (vector-ref v1 i) (vector-ref v2 i)))
                 i
                 (loop (- i 1)))
             #f))))
    ((pred? v1 v2 . rest)
     (let* ((vecs (cons v1 (cons v2 rest)))
            (min-len (let loop ((vs vecs) (m (vector-length v1)))
                       (if (null? vs) m (loop (cdr vs) (%vector-min m (vector-length (car vs))))))))
         (let loop ((i (- min-len 1)))
           (if (>= i 0)
               (if (not (apply pred? (map (lambda (v) (vector-ref v i)) vecs)))
                   i
                   (loop (- i 1)))
               #f))))))

(define (vector-binary-search-range vec value cmp start end)
  (let loop ((low start) (high (- end 1)))
    (if (<= low high)
        (let* ((mid (+ low (quotient (- high low) 2)))
               (mid-val (vector-ref vec mid))
               (c (cmp mid-val value)))
          (cond
            ((= c 0) mid)
            ((< c 0) (loop (+ mid 1) high))
            (else (loop low (- mid 1)))))
        #f)))

(define vector-binary-search
  (case-lambda
    ((vec value cmp)
     (vector-binary-search-range vec value cmp 0 (vector-length vec)))
    ((vec value cmp start)
     (vector-binary-search-range vec value cmp start (vector-length vec)))
    ((vec value cmp start end)
     (vector-binary-search-range vec value cmp start end))))

(define vector-any
  (case-lambda
    ((pred? vec)
     (let ((len (vector-length vec)))
       (let loop ((i 0))
         (if (< i len)
             (let ((res (pred? (vector-ref vec i))))
               (if res res (loop (+ i 1))))
             #f))))
    ((pred? v1 v2)
     (let ((min-len (%vector-min (vector-length v1) (vector-length v2))))
       (let loop ((i 0))
         (if (< i min-len)
             (let ((res (pred? (vector-ref v1 i) (vector-ref v2 i))))
               (if res res (loop (+ i 1))))
             #f))))
    ((pred? v1 v2 . rest)
     (let* ((vecs (cons v1 (cons v2 rest)))
            (min-len (let loop ((vs vecs) (m (vector-length v1)))
                       (if (null? vs) m (loop (cdr vs) (%vector-min m (vector-length (car vs))))))))
       (let loop ((i 0))
         (if (< i min-len)
             (let ((res (apply pred? (map (lambda (v) (vector-ref v i)) vecs))))
               (if res res (loop (+ i 1))))
             #f))))))

(define vector-every
  (case-lambda
    ((pred? vec)
     (let ((len (vector-length vec)))
       (if (= len 0)
           #t
           (let loop ((i 0))
             (let ((res (pred? (vector-ref vec i))))
               (if (not res)
                   #f
                   (if (= i (- len 1))
                       res
                       (loop (+ i 1)))))))))
    ((pred? v1 v2)
     (let ((min-len (%vector-min (vector-length v1) (vector-length v2))))
       (if (= min-len 0)
           #t
           (let loop ((i 0))
             (let ((res (pred? (vector-ref v1 i) (vector-ref v2 i))))
               (if (not res)
                   #f
                   (if (= i (- min-len 1))
                       res
                       (loop (+ i 1)))))))))
    ((pred? v1 v2 . rest)
     (let* ((vecs (cons v1 (cons v2 rest)))
            (min-len (let loop ((vs vecs) (m (vector-length v1)))
                       (if (null? vs) m (loop (cdr vs) (%vector-min m (vector-length (car vs))))))))
       (if (= min-len 0)
           #t
           (let loop ((i 0))
             (let ((res (apply pred? (map (lambda (v) (vector-ref v i)) vecs))))
               (if (not res)
                   #f
                   (if (= i (- min-len 1))
                       res
                       (loop (+ i 1)))))))))))

(define (vector-partition pred? vec)
  (let* ((len (vector-length vec))
         (res (%make-vector len)))
    (let loop ((i 0) (left 0) (right (- len 1)))
      (if (< i len)
          (let ((x (vector-ref vec i)))
            (if (pred? x)
                (begin
                  (vector-set! res left x)
                  (loop (+ i 1) (+ left 1) right))
                (begin
                  (vector-set! res right x)
                  (loop (+ i 1) left (- right 1)))))
          (begin
            ;; Reverse right partition to preserve relative order
            (let rev-loop ((l left) (r (- len 1)))
              (if (< l r)
                  (begin
                    (let ((tmp (vector-ref res l)))
                      (vector-set! res l (vector-ref res r))
                      (vector-set! res r tmp))
                    (rev-loop (+ l 1) (- r 1)))
                  63))
            (values res left))))))

;; ---------------------------------------------------------------------
;; §5 Mutators
;; ---------------------------------------------------------------------

(define (vector-swap! vec i j)
  (let ((tmp (vector-ref vec i)))
    (vector-set! vec i (vector-ref vec j))
    (vector-set! vec j tmp)
    63))

(define (vector-reverse-range! vec start end)
  (let loop ((i start) (j (- end 1)))
    (if (< i j)
        (begin
          (vector-swap! vec i j)
          (loop (+ i 1) (- j 1)))
        63)))

(define vector-reverse!
  (case-lambda
    ((vec)
     (vector-reverse-range! vec 0 (vector-length vec)))
    ((vec start)
     (vector-reverse-range! vec start (vector-length vec)))
    ((vec start end)
     (vector-reverse-range! vec start end))))

(define (vector-reverse-copy-range! target tstart source sstart send)
  (let ((count (- send sstart)))
    (if (eq? target source)
        (let ((tmp (vector-reverse-copy-range source sstart send)))
          (vector-copy-range! target tstart tmp 0 count))
        (let loop ((i 0))
          (if (< i count)
              (begin
                (vector-set! target (+ tstart i) (vector-ref source (- (- send 1) i)))
                (loop (+ i 1)))
              63)))))

(define vector-reverse-copy!
  (case-lambda
    ((to at from)
     (vector-reverse-copy-range! to at from 0 (vector-length from)))
    ((to at from start)
     (vector-reverse-copy-range! to at from start (vector-length from)))
    ((to at from start end)
     (vector-reverse-copy-range! to at from start end))))

(define vector-unfold!
  (case-lambda
    ((f target start end seed)
     (let loop ((i start) (s seed))
       (if (< i end)
           (let ((vals (call-with-values (lambda () (f i s)) list)))
             (vector-set! target i (car vals))
             (loop (+ i 1) (cadr vals)))
           63)))
    ((f target start end s1 s2)
     (let loop ((i start) (a s1) (b s2))
       (if (< i end)
           (let ((vals (call-with-values (lambda () (f i a b)) list)))
             (vector-set! target i (car vals))
             (loop (+ i 1) (cadr vals) (caddr vals)))
           63)))
    ((f target start end . seeds)
     (let loop ((i start) (s seeds))
       (if (< i end)
           (let ((vals (call-with-values (lambda () (apply f (cons i s))) list)))
             (vector-set! target i (car vals))
             (loop (+ i 1) (cdr vals)))
           63)))))

(define vector-unfold-right!
  (case-lambda
    ((f target start end seed)
     (let loop ((i (- end 1)) (s seed))
       (if (>= i start)
           (let ((vals (call-with-values (lambda () (f i s)) list)))
             (vector-set! target i (car vals))
             (loop (- i 1) (cadr vals)))
           63)))
    ((f target start end s1 s2)
     (let loop ((i (- end 1)) (a s1) (b s2))
       (if (>= i start)
           (let ((vals (call-with-values (lambda () (f i a b)) list)))
             (vector-set! target i (car vals))
             (loop (- i 1) (cadr vals) (caddr vals)))
           63)))
    ((f target start end . seeds)
     (let loop ((i (- end 1)) (s seeds))
       (if (>= i start)
           (let ((vals (call-with-values (lambda () (apply f (cons i s))) list)))
             (vector-set! target i (car vals))
             (loop (- i 1) (cdr vals)))
           63)))))

;; ---------------------------------------------------------------------
;; §6 Conversion
;; ---------------------------------------------------------------------

(define (vector->list vec)
  (vector->list-range vec 0 (vector-length vec)))

(define (vector->list-range vec start end)
  (let loop ((i (- end 1)) (acc '()))
    (if (< i start)
        acc
        (loop (- i 1) (cons (vector-ref vec i) acc)))))

(define (reverse-vector->list-range vec start end)
  (let loop ((i start) (acc '()))
    (if (< i end)
        (loop (+ i 1) (cons (vector-ref vec i) acc))
        acc)))

(define reverse-vector->list
  (case-lambda
    ((vec)
     (reverse-vector->list-range vec 0 (vector-length vec)))
    ((vec start)
     (reverse-vector->list-range vec start (vector-length vec)))
    ((vec start end)
     (reverse-vector->list-range vec start end))))

(define (list->vector-range lst start end)
  (let* ((count (- end start))
         (v (%make-vector count)))
    (let loop ((curr (list-tail lst start)) (i 0))
      (if (< i count)
          (begin
            (vector-set! v i (car curr))
            (loop (cdr curr) (+ i 1)))
          v))))

(define list->vector
  (case-lambda
    ((lst)
     (let* ((len (length lst))
            (v (%make-vector len)))
       (let loop ((curr lst) (i 0))
         (if (null? curr)
             v
             (begin
               (vector-set! v i (car curr))
               (loop (cdr curr) (+ i 1)))))))
    ((lst start)
     (list->vector-range lst start (length lst)))
    ((lst start end)
     (list->vector-range lst start end))))

(define (reverse-list->vector-range lst start end)
  (let* ((count (- end start))
         (v (%make-vector count)))
    (let loop ((curr (list-tail lst start)) (i (- count 1)))
      (if (>= i 0)
          (begin
            (vector-set! v i (car curr))
            (loop (cdr curr) (- i 1)))
          v))))

(define reverse-list->vector
  (case-lambda
    ((lst)
     (reverse-list->vector-range lst 0 (length lst)))
    ((lst start)
     (reverse-list->vector-range lst start (length lst)))
    ((lst start end)
     (reverse-list->vector-range lst start end))))

(define (vector->string-range vec start end)
  (let* ((count (- end start))
         (s (make-string count)))
    (let loop ((i 0))
      (if (< i count)
          (begin
            (string-set! s i (vector-ref vec (+ start i)))
            (loop (+ i 1)))
          s))))

(define (string->vector-range str start end)
  (let* ((count (- end start))
         (v (%make-vector count)))
    (let loop ((i 0))
      (if (< i count)
          (begin
            (vector-set! v i (string-ref str (+ start i)))
            (loop (+ i 1)))
          v))))
