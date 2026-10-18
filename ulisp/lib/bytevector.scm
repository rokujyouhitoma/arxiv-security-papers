;;; =======================================================================
;;; ULisp Standard Library: Bytevectors (R7RS Section 6.9)
;;; Conforms to DSN-33 Architecture Specification & Issue #535
;;; =======================================================================

(define (make-bytevector-fill len fill)
  (let ((bv (%make-bytevector len)))
    (if (= fill 0)
        bv
        (let loop ((i 0))
          (if (< i len)
              (begin
                (bytevector-u8-set! bv i fill)
                (loop (+ i 1)))
              bv)))))

(define (bytevector-copy-range bv start end)
  (let* ((count (- end start))
         (new-bv (%make-bytevector count)))
    (let loop ((i 0))
      (if (< i count)
          (begin
            (bytevector-u8-set! new-bv i (bytevector-u8-ref bv (+ start i)))
            (loop (+ i 1)))
          new-bv))))

(define (bytevector-copy-range! to at from start end)
  (let ((count (- end start)))
    (if (and (eq? to from) (> at start))
        ;; Backward copy to handle overlapping regions
        (let loop ((i (- count 1)))
          (if (>= i 0)
              (begin
                (bytevector-u8-set! to (+ at i) (bytevector-u8-ref from (+ start i)))
                (loop (- i 1)))
              63))
        ;; Forward copy
        (let loop ((i 0))
          (if (< i count)
              (begin
                (bytevector-u8-set! to (+ at i) (bytevector-u8-ref from (+ start i)))
                (loop (+ i 1)))
              63)))))

(define (bytevector=? bv1 bv2)
  (let ((l1 (bytevector-length bv1))
        (l2 (bytevector-length bv2)))
    (if (not (= l1 l2))
        #f
        (let loop ((i 0))
          (if (= i l1)
              #t
              (if (= (bytevector-u8-ref bv1 i) (bytevector-u8-ref bv2 i))
                  (loop (+ i 1))
                  #f))))))

(define (bytevector-append2 bv1 bv2)
  (let* ((len1 (bytevector-length bv1))
         (len2 (bytevector-length bv2))
         (res (%make-bytevector (+ len1 len2))))
    (bytevector-copy-range! res 0 bv1 0 len1)
    (bytevector-copy-range! res len1 bv2 0 len2)
    res))

(define (string->utf8-range str start end)
  (let* ((count (- end start))
         (bv (%make-bytevector count)))
    (let loop ((i 0))
      (if (< i count)
          (begin
            (bytevector-u8-set! bv i (char->integer (string-ref str (+ start i))))
            (loop (+ i 1)))
          bv))))

(define (utf8->string-range bv start end)
  (let* ((count (- end start))
         (str (make-string count)))
    (let loop ((i 0))
      (if (< i count)
          (begin
            (string-set! str i (integer->char (bytevector-u8-ref bv (+ start i))))
            (loop (+ i 1)))
          str))))
