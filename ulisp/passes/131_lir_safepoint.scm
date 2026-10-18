;;; =======================================================================
;;; ULisp Compiler Pass 131: GC Safepoint & Stackmap Bitmaps
;;; =======================================================================

(define *lir-safepoints* (cons '() '()))
(define *safepoint-counter* (cons 0 '()))

(define (reset-safepoints!)
  (set-car! *lir-safepoints* '())
  (set-car! *safepoint-counter* 0))

(define (new-safepoint-label!)
  (let* ((cnt (+ (car *safepoint-counter*) 1))
         (lbl-str (string-append "__safepoint_" (number->string cnt))))
    (set-car! *safepoint-counter* cnt)
    lbl-str))

(define (record-safepoint! lbl frame-size bitmap)
  (set-car! *lir-safepoints*
            (cons (list lbl frame-size bitmap) (car *lir-safepoints*))))

(define (power-of-2 k)
  (let loop ((i 0) (acc 1))
    (if (< i k)
        (loop (+ i 1) (* acc 2))
        acc)))


(define (compute-stackmap-bitmap frame-shift aligned-si args env)
  (let* ((slot-count (quotient frame-shift 8))
         (rvars (get-raw-vars env)))
    (let loop ((k 0) (bitmap 0))
      (if (or (>= k slot-count) (>= k 60))
          bitmap
          (let* ((slot-offset (- (* k 8) frame-shift))
                 (is-ptr
                  (if (= slot-offset -8)
                      #t
                      (let ((arg-res
                             (let check-arg ((cur-args args) (i 0))
                               (if (null? cur-args)
                                   #f
                                   (let ((arg-si (- aligned-si (* i 8))))
                                     (if (= slot-offset arg-si)
                                         (cons #t (not (raw-expr? (car cur-args) rvars)))
                                         (check-arg (cdr cur-args) (+ i 1))))))))
                        (if arg-res
                            (cdr arg-res)
                            (let ((var-res
                                   (let check-var ((e env))
                                     (if (null? e)
                                         #f
                                         (let ((entry (car e)))
                                           (if (and (pair? entry)
                                                    (not (eq? (car entry) '%num-params))
                                                    (not (eq? (car entry) '%raw-vars)))
                                               (let ((v (car entry))
                                                     (info (cdr entry)))
                                                 (if (and (number? info) (= info slot-offset))
                                                     (cons #t (not (memq v rvars)))
                                                     (if (and (pair? info) (eq? (car info) 'param) (= (cdr info) slot-offset))
                                                         (cons #t (not (memq v rvars)))
                                                         (check-var (cdr e)))))
                                               (check-var (cdr e))))))))
                              (if var-res
                                  (cdr var-res)
                                  #f)))))))
            (loop (+ k 1)
                  (if is-ptr (+ bitmap (power-of-2 k)) bitmap)))))))

