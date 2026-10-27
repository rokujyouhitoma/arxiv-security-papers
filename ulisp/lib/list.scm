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

;; ---------------------------------------------------------------------
;; §6.4 Pairs and lists: Composite pair accessors (cxr)
;; ---------------------------------------------------------------------
(define (caar x) (car (car x)))
(define (cadr x) (car (cdr x)))
(define (cdar x) (cdr (car x)))
(define (cddr x) (cdr (cdr x)))

(define (caaar x) (car (car (car x))))
(define (caadr x) (car (car (cdr x))))
(define (cadar x) (car (cdr (car x))))
(define (caddr x) (car (cdr (cdr x))))
(define (cdaar x) (cdr (car (car x))))
(define (cdadr x) (cdr (car (cdr x))))
(define (cddar x) (cdr (cdr (car x))))
(define (cdddr x) (cdr (cdr (cdr x))))

(define (cadddr x) (car (cdr (cdr (cdr x)))))
(define (cddddr x) (cdr (cdr (cdr (cdr x)))))

;; ---------------------------------------------------------------------
;; §6.4 Pairs and lists: memq & assq
;; ---------------------------------------------------------------------
(define (memq item ls)
  (cond
    ((not (pair? ls)) #f)
    ((eq? (car ls) item) ls)
    (else (memq item (cdr ls)))))

(define (assq item ls)
  (cond
    ((not (pair? ls)) #f)
    ((not (pair? (car ls))) (assq item (cdr ls)))
    ((eq? (caar ls) item) (car ls))
    (else (assq item (cdr ls)))))

