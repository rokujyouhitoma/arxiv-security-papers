;;; =======================================================================
;;; ULisp Standard Library: Parameters (R7RS Section 4.2.6)
;;; Conforms to DSN-33 Architecture Specification & Issue #537
;;; =======================================================================

(define (make-parameter-1 init)
  (let ((val (cons init '())))
    (lambda (arg)
      (if (= (%num-args) 0)
          (car val)
          (begin
            (set-car! val arg)
            arg)))))

(define (make-parameter-2 init conv)
  (let ((val (cons (conv init) '())))
    (lambda (arg)
      (if (= (%num-args) 0)
          (car val)
          (let ((new-val (conv arg)))
            (set-car! val new-val)
            new-val)))))
