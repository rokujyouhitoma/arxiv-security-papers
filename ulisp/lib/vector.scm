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
;; §6.8 Vectors: vector-append2
;; ---------------------------------------------------------------------
(define (vector-append2 v1 v2)
  (let* ((len1 (vector-length v1))
         (len2 (vector-length v2))
         (res (%make-vector (+ len1 len2))))
    (vector-copy-range! res 0 v1 0 len1)
    (vector-copy-range! res len1 v2 0 len2)
    res))

;; ---------------------------------------------------------------------
;; §6.8 Vectors: vector->list-range / list->vector
;; ---------------------------------------------------------------------
(define (vector->list-range vec start end)
  (let loop ((i (- end 1)) (acc '()))
    (if (< i start)
        acc
        (loop (- i 1) (cons (vector-ref vec i) acc)))))

(define (list->vector lst)
  (let* ((len (length lst))
         (v (%make-vector len)))
    (let loop ((curr lst) (i 0))
      (if (null? curr)
          v
          (begin
            (vector-set! v i (car curr))
            (loop (cdr curr) (+ i 1)))))))

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


