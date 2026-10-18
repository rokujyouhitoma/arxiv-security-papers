;;; =======================================================================
;;; ULisp Standard Library: Lists (R7RS Section 6.4)
;;; Conforms to DSN-33 Architecture Specification, Issue #551 & Issue #561
;;; Traceability: ulisp/docs/r7rs_specification_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §6.4 Pairs and lists: list-copy
;; ---------------------------------------------------------------------
(define (list-copy obj)
  (if (pair? obj)
      (cons (car obj) (list-copy (cdr obj)))
      obj))

;; ---------------------------------------------------------------------
;; §6.4 Pairs and lists: make-list
;; ---------------------------------------------------------------------
(define (make-list-fill k fill)
  (let loop ((i 0) (acc '()))
    (if (< i k)
        (loop (+ i 1) (cons fill acc))
        acc)))

(define (make-list k)
  (make-list-fill k #f))
