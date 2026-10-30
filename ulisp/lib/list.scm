;;; =======================================================================
;;; ULisp Standard Library: Lists (R7RS Section 6.4)
;;; Conforms to DSN-33 Architecture Specification, Issue #551 & Issue #561
;;; Traceability: ulisp/docs/r7rs_specification_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §6.4 Pairs and lists: list constructor
;; ---------------------------------------------------------------------
(define list
  (case-lambda
    (() '())
    (args args)))

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

;; ---------------------------------------------------------------------
;; §6.10 Control features: apply & multi-argument map / for-each
;; ---------------------------------------------------------------------
(define (%any-null? lists)
  (cond
    ((null? lists) #f)
    ((null? (car lists)) #t)
    (else (%any-null? (cdr lists)))))

(define (%cars lists)
  (if (null? lists)
      '()
      (cons (car (car lists)) (%cars (cdr lists)))))

(define (%cdrs lists)
  (if (null? lists)
      '()
      (cons (cdr (car lists)) (%cdrs (cdr lists)))))

(define (%apply-list proc vals)
  (let ((n (length vals)))
    (cond
      ((= n 0) (proc))
      ((= n 1) (proc (car vals)))
      ((= n 2) (proc (car vals) (cadr vals)))
      ((= n 3) (proc (car vals) (cadr vals) (caddr vals)))
      ((= n 4) (proc (car vals) (cadr vals) (caddr vals) (cadddr vals)))
      ((= n 5) (proc (car vals) (cadr vals) (caddr vals) (cadddr vals) (list-ref vals 4)))
      ((= n 6) (proc (car vals) (cadr vals) (caddr vals) (cadddr vals) (list-ref vals 4) (list-ref vals 5)))
      ((= n 7) (proc (car vals) (cadr vals) (caddr vals) (cadddr vals) (list-ref vals 4) (list-ref vals 5) (list-ref vals 6)))
      ((= n 8) (proc (car vals) (cadr vals) (caddr vals) (cadddr vals) (list-ref vals 4) (list-ref vals 5) (list-ref vals 6) (list-ref vals 7)))
      ((= n 9) (proc (car vals) (cadr vals) (caddr vals) (cadddr vals) (list-ref vals 4) (list-ref vals 5) (list-ref vals 6) (list-ref vals 7) (list-ref vals 8)))
      ((= n 10) (proc (car vals) (cadr vals) (caddr vals) (cadddr vals) (list-ref vals 4) (list-ref vals 5) (list-ref vals 6) (list-ref vals 7) (list-ref vals 8) (list-ref vals 9)))
      ((= n 11) (proc (car vals) (cadr vals) (caddr vals) (cadddr vals) (list-ref vals 4) (list-ref vals 5) (list-ref vals 6) (list-ref vals 7) (list-ref vals 8) (list-ref vals 9) (list-ref vals 10)))
      ((= n 12) (proc (car vals) (cadr vals) (caddr vals) (cadddr vals) (list-ref vals 4) (list-ref vals 5) (list-ref vals 6) (list-ref vals 7) (list-ref vals 8) (list-ref vals 9) (list-ref vals 10) (list-ref vals 11)))
      (else (error "apply: maximum supported arity exceeded" n)))))

(define (%build-apply-args args)
  (cond
    ((null? args) (error "apply: invalid argument count"))
    ((null? (cdr args)) (car args))
    (else (cons (car args) (%build-apply-args (cdr args))))))

(define apply
  (case-lambda
    ((proc lst)
     (%apply-list proc lst))
    ((proc a1 lst)
     (%apply-list proc (cons a1 lst)))
    ((proc a1 a2 lst)
     (%apply-list proc (cons a1 (cons a2 lst))))
    ((proc a1 a2 a3 lst)
     (%apply-list proc (cons a1 (cons a2 (cons a3 lst)))))
    ((proc a1 a2 a3 . rest)
     (%apply-list proc (cons a1 (cons a2 (cons a3 (%build-apply-args rest))))))))

(define map
  (case-lambda
    ((proc ls)
     (let loop ((l ls))
       (if (null? l)
           '()
           (cons (proc (car l)) (loop (cdr l))))))
    ((proc l1 l2)
     (let loop ((a l1) (b l2))
       (if (or (null? a) (null? b))
           '()
           (cons (proc (car a) (car b)) (loop (cdr a) (cdr b))))))
    ((proc l1 l2 . rest)
     (let ((lists (cons l1 (cons l2 rest))))
       (let loop ((ls lists))
         (if (%any-null? ls)
             '()
             (cons (%apply-list proc (%cars ls))
                   (loop (%cdrs ls)))))))))

(define for-each
  (case-lambda
    ((proc ls)
     (let loop ((l ls))
       (if (null? l)
           63
           (begin
             (proc (car l))
             (loop (cdr l))))))
    ((proc l1 l2)
     (let loop ((a l1) (b l2))
       (if (or (null? a) (null? b))
           63
           (begin
             (proc (car a) (car b))
             (loop (cdr a) (cdr b))))))
    ((proc l1 l2 . rest)
     (let ((lists (cons l1 (cons l2 rest))))
       (let loop ((ls lists))
         (if (%any-null? ls)
             63
             (begin
               (%apply-list proc (%cars ls))
               (loop (%cdrs ls)))))))))


