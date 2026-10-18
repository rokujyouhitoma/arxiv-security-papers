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

;; ---------------------------------------------------------------------
;; §6.4 Pairs and lists: list-tail
;; ---------------------------------------------------------------------
(define (list-tail lst k)
  (let loop ((l lst) (i k))
    (if (<= i 0)
        l
        (if (pair? l)
            (loop (cdr l) (- i 1))
            (error "list-tail: index out of bounds" k)))))

;; ---------------------------------------------------------------------
;; §6.4 Pairs and lists: list-ref
;; ---------------------------------------------------------------------
(define (list-ref lst k)
  (car (list-tail lst k)))

;; ---------------------------------------------------------------------
;; §6.4 Pairs and lists: list-set!
;; ---------------------------------------------------------------------
(define (list-set! lst k obj)
  (let ((p (list-tail lst k)))
    (if (pair? p)
        (set-car! p obj)
        (error "list-set!: index out of bounds" k))))
