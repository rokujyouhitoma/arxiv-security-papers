;;; =======================================================================
;;; ULisp Standard Library: Lists (R7RS Section 6.4)
;;; Conforms to DSN-33 Architecture Specification & Issue #551
;;; =======================================================================

(define (list-copy obj)
  (if (pair? obj)
      (cons (car obj) (list-copy (cdr obj)))
      obj))

(define (make-list-fill k fill)
  (let loop ((i 0) (acc '()))
    (if (< i k)
        (loop (+ i 1) (cons fill acc))
        acc)))

(define (make-list k)
  (make-list-fill k #f))
