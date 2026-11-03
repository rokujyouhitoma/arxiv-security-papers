;;; =======================================================================
;;; ULisp Standard Library: Generators and Accumulators (SRFI 121, SRFI 158)
;;; R7RS-large Red & Tangerine Editions: (scheme generator)
;;; Conforms to DSN-33 Architecture Specification & Issue #704
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §1. Internal State Mutation Helpers (Safe Stack Frame Helpers)
;; ---------------------------------------------------------------------

(define (%gen-cell-set! cell val)
  (set-car! cell val))

(define (%gen-vec-set! vec idx val)
  (vector-set! vec idx val))

(define (%gen-bv-set! bv idx val)
  (bytevector-u8-set! bv idx val))

;; ---------------------------------------------------------------------
;; §2. Generator Constructors (SRFI 121 / SRFI 158)
;; ---------------------------------------------------------------------

(define generator
  (case-lambda
    (() (lambda () (eof-object)))
    (( . args)
     (list->generator args))))

(define circular-generator
  (case-lambda
    (( . args)
     (if (null? args)
         (error "circular-generator: requires at least one argument" args)
         (let ((cell (cons args '())))
           (lambda ()
             (let* ((cur (car cell))
                    (val (car cur))
                    (next (if (null? (cdr cur)) args (cdr cur))))
               (%gen-cell-set! cell next)
               val)))))))

(define make-iota-generator
  (case-lambda
    ((count) (make-iota-generator count 0 1))
    ((count start) (make-iota-generator count start 1))
    ((count start step)
     (let ((rem-cell (cons count '()))
           (val-cell (cons start '())))
       (lambda ()
         (let ((rem (car rem-cell)))
           (if (<= rem 0)
               (eof-object)
               (let ((v (car val-cell)))
                 (%gen-cell-set! rem-cell (- rem 1))
                 (%gen-cell-set! val-cell (+ v step))
                 v))))))))

(define (%make-infinite-range-generator start)
  (let ((val-cell (cons start '())))
    (lambda ()
      (let ((v (car val-cell)))
        (%gen-cell-set! val-cell (+ v 1))
        v))))

(define (%make-bounded-range-generator start end step)
  (let ((val-cell (cons start '()))
        (cmp (if (> step 0)
                 (lambda (a b) (< a b))
                 (lambda (a b) (> a b)))))
    (lambda ()
      (let ((v (car val-cell)))
        (if (cmp v end)
            (begin
              (%gen-cell-set! val-cell (+ v step))
              v)
            (eof-object))))))

(define make-range-generator
  (case-lambda
    ((start)
     (%make-infinite-range-generator start))
    ((start end)
     (%make-bounded-range-generator start end 1))
    ((start end step)
     (%make-bounded-range-generator start end step))))

(define (make-coroutine-generator proc)
  (let ((return-cell (cons #f '()))
        (resume-cell (cons #f '()))
        (done-cell   (cons #f '())))
    (let ((yield (lambda (v)
                   (call/cc
                    (lambda (r)
                      (%gen-cell-set! resume-cell r)
                      ((car return-cell) v))))))
      (lambda ()
        (if (car done-cell)
            (eof-object)
            (call/cc
             (lambda (ret)
               (%gen-cell-set! return-cell ret)
               (let ((res (car resume-cell)))
                 (if res
                     (res #f)
                     (begin
                       (proc yield)
                       (%gen-cell-set! done-cell #t)
                       (%gen-cell-set! resume-cell #f)
                       ((car return-cell) (eof-object))))))))))))

(define (list->generator lst)
  (let ((cell (cons lst '())))
    (lambda ()
      (let ((cur (car cell)))
        (if (null? cur)
            (eof-object)
            (begin
              (%gen-cell-set! cell (cdr cur))
              (car cur)))))))

(define (%vector->generator-core vec start end)
  (let ((idx-cell (cons start '())))
    (lambda ()
      (let ((i (car idx-cell)))
        (if (>= i end)
            (eof-object)
            (begin
              (%gen-cell-set! idx-cell (+ i 1))
              (vector-ref vec i)))))))

(define vector->generator
  (case-lambda
    ((vec) (%vector->generator-core vec 0 (vector-length vec)))
    ((vec start) (%vector->generator-core vec start (vector-length vec)))
    ((vec start end) (%vector->generator-core vec start end))))

(define (%reverse-vector->generator-core vec start end)
  (let ((idx-cell (cons (- end 1) '())))
    (lambda ()
      (let ((i (car idx-cell)))
        (if (< i start)
            (eof-object)
            (begin
              (%gen-cell-set! idx-cell (- i 1))
              (vector-ref vec i)))))))

(define reverse-vector->generator
  (case-lambda
    ((vec) (%reverse-vector->generator-core vec 0 (vector-length vec)))
    ((vec start) (%reverse-vector->generator-core vec start (vector-length vec)))
    ((vec start end) (%reverse-vector->generator-core vec start end))))

(define (%string->generator-core str start end)
  (let ((idx-cell (cons start '())))
    (lambda ()
      (let ((i (car idx-cell)))
        (if (>= i end)
            (eof-object)
            (begin
              (%gen-cell-set! idx-cell (+ i 1))
              (string-ref str i)))))))

(define string->generator
  (case-lambda
    ((str) (%string->generator-core str 0 (string-length str)))
    ((str start) (%string->generator-core str start (string-length str)))
    ((str start end) (%string->generator-core str start end))))

(define (%bytevector->generator-core bv start end)
  (let ((idx-cell (cons start '())))
    (lambda ()
      (let ((i (car idx-cell)))
        (if (>= i end)
            (eof-object)
            (begin
              (%gen-cell-set! idx-cell (+ i 1))
              (bytevector-u8-ref bv i)))))))

(define bytevector->generator
  (case-lambda
    ((bv) (%bytevector->generator-core bv 0 (bytevector-length bv)))
    ((bv start) (%bytevector->generator-core bv start (bytevector-length bv)))
    ((bv start end) (%bytevector->generator-core bv start end))))

(define (make-for-each-generator for-each-proc obj)
  (make-coroutine-generator
   (lambda (yield)
     (for-each-proc yield obj))))

(define (make-unfold-generator stop? mapper successor seed)
  (let ((seed-cell (cons seed '()))
        (done-cell (cons #f '())))
    (lambda ()
      (if (car done-cell)
          (eof-object)
          (let ((s (car seed-cell)))
            (if (stop? s)
                (begin
                  (%gen-cell-set! done-cell #t)
                  (eof-object))
                (let ((val (mapper s)))
                  (%gen-cell-set! seed-cell (successor s))
                  val)))))))

;; ---------------------------------------------------------------------
;; §3. Generator Operations & Combinators (SRFI 121 / SRFI 158)
;; ---------------------------------------------------------------------

(define (%gcons*-core items gen)
  (let ((cell (cons items '())))
    (lambda ()
      (let ((cur (car cell)))
        (if (null? cur)
            (gen)
            (begin
              (%gen-cell-set! cell (cdr cur))
              (car cur)))))))

(define gcons*
  (case-lambda
    ((gen) gen)
    ((a gen) (%gcons*-core (list a) gen))
    ((a b gen) (%gcons*-core (list a b) gen))
    (( . args)
     (let loop ((cur args) (prefix '()))
       (if (null? (cdr cur))
           (%gcons*-core (reverse prefix) (car cur))
           (loop (cdr cur) (cons (car cur) prefix)))))))

(define (%gappend-list gens)
  (let ((cell (cons gens '())))
    (lambda ()
      (let loop ()
        (let ((cur (car cell)))
          (if (null? cur)
              (eof-object)
              (let ((v ((car cur))))
                (if (eof-object? v)
                    (begin
                      (%gen-cell-set! cell (cdr cur))
                      (loop))
                    v))))))))

(define gappend
  (case-lambda
    (() (generator))
    (( . gens) (%gappend-list gens))))

(define (gflatten gen)
  (let ((cur-cell (cons '() '())))
    (lambda ()
      (let loop ()
        (let ((cur (car cur-cell)))
          (if (pair? cur)
              (begin
                (%gen-cell-set! cur-cell (cdr cur))
                (car cur))
              (let ((next-list (gen)))
                (if (eof-object? next-list)
                    (eof-object)
                    (begin
                      (%gen-cell-set! cur-cell next-list)
                      (loop))))))))))

(define (%ggroup-simple gen k)
  (let ((done-cell (cons #f '())))
    (lambda ()
      (if (car done-cell)
          (eof-object)
          (let loop ((i 0) (acc '()))
            (if (>= i k)
                (reverse acc)
                (let ((v (gen)))
                  (if (eof-object? v)
                      (begin
                        (%gen-cell-set! done-cell #t)
                        (if (null? acc)
                            (eof-object)
                            (reverse acc)))
                      (loop (+ i 1) (cons v acc))))))))))

(define (%ggroup-padded gen k padding)
  (let ((done-cell (cons #f '())))
    (lambda ()
      (if (car done-cell)
          (eof-object)
          (let ((first (gen)))
            (if (eof-object? first)
                (begin
                  (%gen-cell-set! done-cell #t)
                  (eof-object))
                (let loop ((i 1) (acc (list first)))
                  (if (>= i k)
                      (reverse acc)
                      (let ((v (gen)))
                        (if (eof-object? v)
                            (begin
                              (%gen-cell-set! done-cell #t)
                              (let pad-loop ((j i) (pacc acc))
                                (if (>= j k)
                                    (reverse pacc)
                                    (pad-loop (+ j 1) (cons padding pacc)))))
                            (loop (+ i 1) (cons v acc))))))))))))

(define ggroup
  (case-lambda
    ((gen k) (%ggroup-simple gen k))
    ((gen k padding) (%ggroup-padded gen k padding))))

(define (%gmerge-2 less? g1 g2)
  (let ((v1-cell (cons (g1) '()))
        (v2-cell (cons (g2) '())))
    (lambda ()
      (let ((v1 (car v1-cell))
            (v2 (car v2-cell)))
        (cond
          ((and (eof-object? v1) (eof-object? v2))
           (eof-object))
          ((eof-object? v1)
           (%gen-cell-set! v2-cell (g2))
           v2)
          ((eof-object? v2)
           (%gen-cell-set! v1-cell (g1))
           v1)
          ((less? v2 v1)
           (%gen-cell-set! v2-cell (g2))
           v2)
          (else
           (%gen-cell-set! v1-cell (g1))
           v1))))))

(define gmerge
  (case-lambda
    ((less? g1) g1)
    ((less? g1 g2) (%gmerge-2 less? g1 g2))
    ((less? g1 g2 . rest)
     (let loop ((acc (%gmerge-2 less? g1 g2)) (rs rest))
       (if (null? rs)
           acc
           (loop (%gmerge-2 less? acc (car rs)) (cdr rs)))))))

(define (%any-eof? vals)
  (let loop ((ls vals))
    (cond
      ((null? ls) #f)
      ((eof-object? (car ls)) #t)
      (else (loop (cdr ls))))))

(define gmap
  (case-lambda
    ((proc gen)
     (let ((done-cell (cons #f '())))
       (lambda ()
         (if (car done-cell)
             (eof-object)
             (let ((v (gen)))
               (if (eof-object? v)
                   (begin
                     (%gen-cell-set! done-cell #t)
                     (eof-object))
                   (proc v)))))))
    ((proc g1 g2)
     (let ((done-cell (cons #f '())))
       (lambda ()
         (if (car done-cell)
             (eof-object)
             (let ((v1 (g1))
                   (v2 (g2)))
               (if (or (eof-object? v1) (eof-object? v2))
                   (begin
                     (%gen-cell-set! done-cell #t)
                     (eof-object))
                   (proc v1 v2)))))))
    ((proc . gens)
     (let ((done-cell (cons #f '())))
       (lambda ()
         (if (car done-cell)
             (eof-object)
             (let ((vals (map (lambda (g) (g)) gens)))
               (if (%any-eof? vals)
                   (begin
                     (%gen-cell-set! done-cell #t)
                     (eof-object))
                   (apply proc vals)))))))))

(define gcombine
  (case-lambda
    ((proc seed gen)
     (let ((seed-cell (cons seed '()))
           (done-cell (cons #f '())))
       (lambda ()
         (if (car done-cell)
             (eof-object)
             (let ((v (gen)))
               (if (eof-object? v)
                   (begin
                     (%gen-cell-set! done-cell #t)
                     (eof-object))
                   (call-with-values
                     (lambda () (proc v (car seed-cell)))
                     (lambda (out-val next-seed)
                       (%gen-cell-set! seed-cell next-seed)
                       out-val))))))))
    ((proc seed . gens)
     (let ((seed-cell (cons seed '()))
           (done-cell (cons #f '())))
       (lambda ()
         (if (car done-cell)
             (eof-object)
             (let ((vals (map (lambda (g) (g)) gens)))
               (if (%any-eof? vals)
                   (begin
                     (%gen-cell-set! done-cell #t)
                     (eof-object))
                   (call-with-values
                     (lambda () (apply proc (append vals (list (car seed-cell)))))
                     (lambda (out-val next-seed)
                       (%gen-cell-set! seed-cell next-seed)
                       out-val))))))))))

(define (gfilter pred gen)
  (let ((done-cell (cons #f '())))
    (lambda ()
      (if (car done-cell)
          (eof-object)
          (let loop ()
            (let ((v (gen)))
              (cond
                ((eof-object? v)
                 (%gen-cell-set! done-cell #t)
                 (eof-object))
                ((pred v) v)
                (else (loop)))))))))

(define (gremove pred gen)
  (gfilter (lambda (x) (not (pred x))) gen))

(define (gstate-filter proc seed gen)
  (let ((seed-cell (cons seed '()))
        (done-cell (cons #f '())))
    (lambda ()
      (if (car done-cell)
          (eof-object)
          (let loop ()
            (let ((v (gen)))
              (if (eof-object? v)
                  (begin
                    (%gen-cell-set! done-cell #t)
                    (eof-object))
                  (call-with-values
                    (lambda () (proc v (car seed-cell)))
                    (lambda (keep? next-seed)
                      (%gen-cell-set! seed-cell next-seed)
                      (if keep?
                          v
                          (loop)))))))))))

(define (%gtake-core gen k padded? padding)
  (let ((rem-cell (cons k '()))
        (eof-seen (cons #f '())))
    (lambda ()
      (let ((rem (car rem-cell)))
        (if (<= rem 0)
            (eof-object)
            (begin
              (%gen-cell-set! rem-cell (- rem 1))
              (if (car eof-seen)
                  (if padded? padding (eof-object))
                  (let ((v (gen)))
                    (if (eof-object? v)
                        (begin
                          (%gen-cell-set! eof-seen #t)
                          (if padded? padding (eof-object)))
                        v)))))))))

(define gtake
  (case-lambda
    ((gen k) (%gtake-core gen k #f #f))
    ((gen k padding) (%gtake-core gen k #t padding))))

(define (gdrop gen k)
  (let ((dropped-cell (cons #f '())))
    (lambda ()
      (if (not (car dropped-cell))
          (begin
            (%gen-cell-set! dropped-cell #t)
            (let loop ((i 0))
              (if (< i k)
                  (let ((v (gen)))
                    (if (eof-object? v)
                        #t
                        (loop (+ i 1))))
                  #t)))
          #t)
      (gen))))

(define (gtake-while pred gen)
  (let ((done-cell (cons #f '())))
    (lambda ()
      (if (car done-cell)
          (eof-object)
          (let ((v (gen)))
            (if (or (eof-object? v) (not (pred v)))
                (begin
                  (%gen-cell-set! done-cell #t)
                  (eof-object))
                v))))))

(define (gdrop-while pred gen)
  (let ((started-cell (cons #f '())))
    (lambda ()
      (if (car started-cell)
          (gen)
          (let loop ()
            (let ((v (gen)))
              (cond
                ((eof-object? v)
                 (%gen-cell-set! started-cell #t)
                 (eof-object))
                ((pred v)
                 (loop))
                (else
                 (%gen-cell-set! started-cell #t)
                 v))))))))

(define (%gdelete-core item gen eq-pred)
  (gfilter (lambda (x) (not (eq-pred item x))) gen))

(define gdelete
  (case-lambda
    ((item gen) (%gdelete-core item gen equal?))
    ((item gen eq-pred) (%gdelete-core item gen eq-pred))))

(define (%gdelete-neighbor-dups-core gen eq-pred)
  (let ((has-prev-cell (cons #f '()))
        (prev-cell     (cons #f '()))
        (done-cell     (cons #f '())))
    (lambda ()
      (if (car done-cell)
          (eof-object)
          (let loop ()
            (let ((v (gen)))
              (cond
                ((eof-object? v)
                 (%gen-cell-set! done-cell #t)
                 (eof-object))
                ((not (car has-prev-cell))
                 (%gen-cell-set! has-prev-cell #t)
                 (%gen-cell-set! prev-cell v)
                 v)
                ((eq-pred (car prev-cell) v)
                 (loop))
                (else
                 (%gen-cell-set! prev-cell v)
                 v))))))))

(define gdelete-neighbor-dups
  (case-lambda
    ((gen) (%gdelete-neighbor-dups-core gen equal?))
    ((gen eq-pred) (%gdelete-neighbor-dups-core gen eq-pred))))

(define (gindex value-gen index-gen)
  (let ((pos-cell  (cons 0 '()))
        (done-cell (cons #f '())))
    (lambda ()
      (if (car done-cell)
          (eof-object)
          (let ((target-idx (index-gen)))
            (if (eof-object? target-idx)
                (begin
                  (%gen-cell-set! done-cell #t)
                  (eof-object))
                (let loop ()
                  (let ((v (value-gen))
                        (cur-pos (car pos-cell)))
                    (if (eof-object? v)
                        (begin
                          (%gen-cell-set! done-cell #t)
                          (eof-object))
                        (begin
                          (%gen-cell-set! pos-cell (+ cur-pos 1))
                          (if (= cur-pos target-idx)
                              v
                              (loop))))))))))))

(define (gselect value-gen truth-gen)
  (let ((done-cell (cons #f '())))
    (lambda ()
      (if (car done-cell)
          (eof-object)
          (let loop ()
            (let ((v (value-gen))
                  (t (truth-gen)))
              (if (or (eof-object? v) (eof-object? t))
                  (begin
                    (%gen-cell-set! done-cell #t)
                    (eof-object))
                  (if t
                      v
                      (loop)))))))))

;; ---------------------------------------------------------------------
;; §4. Generator Consumers (SRFI 121 / SRFI 158)
;; ---------------------------------------------------------------------

(define (%generator->reverse-list-all gen)
  (let loop ((acc '()))
    (let ((v (gen)))
      (if (eof-object? v)
          acc
          (loop (cons v acc))))))

(define (%generator->reverse-list-k gen k)
  (let loop ((i 0) (acc '()))
    (if (>= i k)
        acc
        (let ((v (gen)))
          (if (eof-object? v)
              acc
              (loop (+ i 1) (cons v acc)))))))

(define generator->reverse-list
  (case-lambda
    ((gen) (%generator->reverse-list-all gen))
    ((gen k) (%generator->reverse-list-k gen k))))

(define generator->list
  (case-lambda
    ((gen) (reverse (%generator->reverse-list-all gen)))
    ((gen k) (reverse (%generator->reverse-list-k gen k)))))

(define generator->vector
  (case-lambda
    ((gen) (list->vector (generator->list gen)))
    ((gen k) (list->vector (generator->list gen k)))))

(define (%generator->vector!-core vec at gen)
  (let ((len (vector-length vec)))
    (let loop ((i at) (cnt 0))
      (if (>= i len)
          cnt
          (let ((v (gen)))
            (if (eof-object? v)
                cnt
                (begin
                  (%gen-vec-set! vec i v)
                  (loop (+ i 1) (+ cnt 1)))))))))

(define (generator->vector! vec at gen)
  (%generator->vector!-core vec at gen))

(define generator->string
  (case-lambda
    ((gen) (list->string (generator->list gen)))
    ((gen k) (list->string (generator->list gen k)))))

(define generator-fold
  (case-lambda
    ((proc knil gen)
     (let loop ((acc knil))
       (let ((v (gen)))
         (if (eof-object? v)
             acc
             (loop (proc v acc))))))
    ((proc knil . gens)
     (let loop ((acc knil))
       (let ((vals (map (lambda (g) (g)) gens)))
         (if (%any-eof? vals)
             acc
             (loop (apply proc (append vals (list acc))))))))))

(define generator-for-each
  (case-lambda
    ((proc gen)
     (let loop ()
       (let ((v (gen)))
         (if (eof-object? v)
             #t
             (begin
               (proc v)
               (loop))))))
    ((proc . gens)
     (let loop ()
       (let ((vals (map (lambda (g) (g)) gens)))
         (if (%any-eof? vals)
             #t
             (begin
               (apply proc vals)
               (loop))))))))

(define generator-map->list
  (case-lambda
    ((proc gen)
     (let loop ((acc '()))
       (let ((v (gen)))
         (if (eof-object? v)
             (reverse acc)
             (loop (cons (proc v) acc))))))
    ((proc . gens)
     (let loop ((acc '()))
       (let ((vals (map (lambda (g) (g)) gens)))
         (if (%any-eof? vals)
             (reverse acc)
             (loop (cons (apply proc vals) acc))))))))

(define (generator-find pred gen)
  (let loop ()
    (let ((v (gen)))
      (cond
        ((eof-object? v) #f)
        ((pred v) v)
        (else (loop))))))

(define (generator-count pred gen)
  (let loop ((cnt 0))
    (let ((v (gen)))
      (cond
        ((eof-object? v) cnt)
        ((pred v) (loop (+ cnt 1)))
        (else (loop cnt))))))

(define (generator-any pred gen)
  (let loop ()
    (let ((v (gen)))
      (if (eof-object? v)
          #f
          (let ((res (pred v)))
            (if res
                res
                (loop)))))))

(define (generator-every pred gen)
  (let loop ((last #t))
    (let ((v (gen)))
      (if (eof-object? v)
          last
          (let ((res (pred v)))
            (if res
                (loop res)
                #f))))))

(define generator-unfold
  (case-lambda
    ((gen unfold-proc)
     (unfold-proc (lambda (x) (eof-object? x)) (lambda (x) x) (lambda (x) (gen)) (gen)))
    ((gen unfold-proc . args)
     (apply unfold-proc (cons (lambda (x) (eof-object? x)) (cons (lambda (x) x) (cons (lambda (x) (gen)) (cons (gen) args))))))))

;; ---------------------------------------------------------------------
;; §5. Accumulators (SRFI 158)
;; ---------------------------------------------------------------------

(define (make-accumulator kons knil finalize)
  (let ((state-cell (cons knil '())))
    (lambda (obj)
      (if (eof-object? obj)
          (finalize (car state-cell))
          (begin
            (%gen-cell-set! state-cell (kons obj (car state-cell)))
            #t)))))

(define (count-accumulator)
  (make-accumulator
   (lambda (obj cnt) (+ cnt 1))
   0
   (lambda (cnt) cnt)))

(define (list-accumulator)
  (make-accumulator
   (lambda (obj ls) (cons obj ls))
   '()
   reverse))

(define (reverse-list-accumulator)
  (make-accumulator
   (lambda (obj ls) (cons obj ls))
   '()
   (lambda (ls) ls)))

(define (vector-accumulator)
  (make-accumulator
   (lambda (obj ls) (cons obj ls))
   '()
   (lambda (ls) (list->vector (reverse ls)))))

(define (reverse-vector-accumulator)
  (make-accumulator
   (lambda (obj ls) (cons obj ls))
   '()
   list->vector))

(define (vector-accumulator! vec at)
  (let ((idx-cell (cons at '())))
    (lambda (obj)
      (if (eof-object? obj)
          vec
          (let ((i (car idx-cell)))
            (%gen-vec-set! vec i obj)
            (%gen-cell-set! idx-cell (+ i 1))
            #t)))))

(define (string-accumulator)
  (make-accumulator
   (lambda (obj ls) (cons obj ls))
   '()
   (lambda (ls) (list->string (reverse ls)))))

(define (bytevector-accumulator)
  (make-accumulator
   (lambda (obj ls) (cons obj ls))
   '()
   (lambda (ls)
     (let* ((rev (reverse ls))
            (len (length rev))
            (bv (make-bytevector len)))
       (let loop ((cur rev) (i 0))
         (if (null? cur)
             bv
             (begin
               (%gen-bv-set! bv i (car cur))
               (loop (cdr cur) (+ i 1)))))))))

(define (bytevector-accumulator! bv at)
  (let ((idx-cell (cons at '())))
    (lambda (obj)
      (if (eof-object? obj)
          bv
          (let ((i (car idx-cell)))
            (%gen-bv-set! bv i obj)
            (%gen-cell-set! idx-cell (+ i 1))
            #t)))))

(define (sum-accumulator)
  (make-accumulator
   (lambda (obj sum) (+ sum obj))
   0
   (lambda (sum) sum)))

(define (product-accumulator)
  (make-accumulator
   (lambda (obj prod) (* prod obj))
   1
   (lambda (prod) prod)))
