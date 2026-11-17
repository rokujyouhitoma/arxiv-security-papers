;;; =======================================================================
;;; ULisp Standard Library: Vectors (R7RS Section 6.8, SRFI-133)
;;; Conforms to DSN-33 Architecture Specification, Issue #536 & Issue #561
;;; Traceability: ulisp/docs/r7rs_specification_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §6.8 Vectors: make-vector-fill
;; ---------------------------------------------------------------------
(define (make-vector-fill len fill)
  (let ((v (%make-vector len)))
    (let loop ((i 0))
      (if (< i len)
          (begin
            (vector-set! v i fill)
            (loop (+ i 1)))
          v))))

;; ---------------------------------------------------------------------
;; §6.8 Vectors: vector-copy-range / vector-copy-range!
;; ---------------------------------------------------------------------
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

;; ---------------------------------------------------------------------
;; §6.8 Vectors: vector-fill-range!
;; ---------------------------------------------------------------------
(define (vector-fill-range! vec fill start end)
  (let loop ((i start))
    (if (< i end)
        (begin
          (vector-set! vec i fill)
          (loop (+ i 1)))
        63)))

;; ---------------------------------------------------------------------
;; §6.8 Vectors: vector-append2 / vector-append
;; ---------------------------------------------------------------------
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
    ((v) v)
    ((v1 v2) (vector-append2 v1 v2))
    ((v1 v2 . rest)
     (let loop ((acc (vector-append2 v1 v2)) (rs rest))
       (if (null? rs)
           acc
           (loop (vector-append2 acc (car rs)) (cdr rs)))))))


;; ---------------------------------------------------------------------
;; §6.8 Vectors: vector->list / vector->list-range / list->vector
;; ---------------------------------------------------------------------
(define (vector->list vec)
  (vector->list-range vec 0 (vector-length vec)))

(define (vector->list-range vec start end)
  (let loop ((i (- end 1)) (acc '()))
    (if (< i start)
        acc
        (loop (- i 1) (cons (vector-ref vec i) acc)))))

(define (list->vector lst)
  (let loop-len ((curr lst) (len 0))
    (if (null? curr)
        (let ((v (%make-vector len)))
          (let loop-fill ((c lst) (i 0))
            (if (< i len)
                (begin
                  (vector-set! v i (car c))
                  (loop-fill (cdr c) (+ i 1)))
                v)))
        (loop-len (cdr curr) (+ len 1)))))

;; ---------------------------------------------------------------------
;; §6.8 Vectors: vector-map / vector-for-each
;; ---------------------------------------------------------------------
(define (vector-map proc vec)
  (let* ((len (vector-length vec))
         (res (%make-vector len)))
    (let loop ((i 0))
      (if (< i len)
          (begin
            (vector-set! res i (proc (vector-ref vec i)))
            (loop (+ i 1)))
          res))))

(define (vector-for-each proc vec)
  (let ((len (vector-length vec)))
    (let loop ((i 0))
      (if (< i len)
          (begin
            (proc (vector-ref vec i))
            (loop (+ i 1)))
          63))))

;; ---------------------------------------------------------------------
;; §6.8 Vectors: vector->string-range
;; ---------------------------------------------------------------------
(define (vector->string-range vec start end)
  (let* ((count (- end start))
         (s (make-string count)))
    (let loop ((i 0))
      (if (< i count)
          (begin
            (string-set! s i (vector-ref vec (+ start i)))
            (loop (+ i 1)))
          s))))

;; ---------------------------------------------------------------------
;; §6.8 Vectors: string->vector-range
;; ---------------------------------------------------------------------
(define (string->vector-range str start end)
  (let* ((count (- end start))
         (v (%make-vector count)))
    (let loop ((i 0))
      (if (< i count)
          (begin
            (vector-set! v i (string-ref str (+ start i)))
            (loop (+ i 1)))
          v))))


