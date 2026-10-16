;;; =======================================================================
;;; ULisp Standard Library: Multiple Values (R7RS Section 6.10)
;;; =======================================================================

;; Standard multiple values interface.
;; In ULisp, (values ...) and (call-with-values ...) are compiled
;; into zero-heap-allocation native register & sliding buffer ABI.
;; This library provides runtime support and compatibility definitions.

(define (values-list lst)
  (if (null? lst)
      (values)
      (if (null? (cdr lst))
          (car lst)
          (if (null? (cddr lst))
              (values (car lst) (cadr lst))
              (if (null? (cdddr lst))
                  (values (car lst) (cadr lst) (caddr lst))
                  (values (car lst) (cadr lst) (caddr lst) (cadddr lst)))))))
