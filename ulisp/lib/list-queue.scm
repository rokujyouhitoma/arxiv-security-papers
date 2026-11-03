;;; =======================================================================
;;; ULisp Standard Library: List Queues — R7RS-large Red Edition / SRFI 117
;;; Specification: (scheme list-queue) / (srfi 117)
;;; Conforms to DSN-33 Architecture Specification & Issue #707
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 117 Internal Representation & GC-Safe Mutators
;;   Vector layout: #(ulisp-list-queue-tag <first-list> <last-pair>)
;; ---------------------------------------------------------------------

(define (%make-raw-lq first last)
  (let ((v (make-vector 3 #f)))
    (vector-set! v 0 'ulisp-list-queue-tag)
    (vector-set! v 1 first)
    (vector-set! v 2 last)
    v))

(define (%lq-first q) (vector-ref q 1))
(define (%lq-last q) (vector-ref q 2))

(define (%lq-set-first! q v) (vector-set! q 1 v))
(define (%lq-set-last! q v) (vector-set! q 2 v))
(define (%lq-set-car! p v) (set-car! p v))
(define (%lq-set-cdr! p v) (set-cdr! p v))

(define (%lq-last-pair ls)
  (if (null? ls)
      '()
      (let loop ((cur ls))
        (if (null? (cdr cur))
            cur
            (loop (cdr cur))))))

(define (%lq-list-copy ls)
  (let loop ((cur ls) (acc '()))
    (if (null? cur)
        (reverse acc)
        (loop (cdr cur) (cons (car cur) acc)))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 117 Predicates
;; ---------------------------------------------------------------------

(define (list-queue? obj)
  (and (vector? obj)
       (= (vector-length obj) 3)
       (eq? (vector-ref obj 0) 'ulisp-list-queue-tag)))

(define (list-queue-empty? q)
  (null? (%lq-first q)))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 117 Constructors
;; ---------------------------------------------------------------------

(define make-list-queue
  (case-lambda
    ((ls)
     (%make-raw-lq ls (%lq-last-pair ls)))
    ((ls last)
     (%make-raw-lq ls last))))

(define list-queue
  (case-lambda
    (() (%make-raw-lq '() '()))
    ((a . rest)
     (let ((ls (cons a rest)))
       (%make-raw-lq ls (%lq-last-pair ls))))))

(define (list-queue-copy q)
  (let ((copied (%lq-list-copy (%lq-first q))))
    (%make-raw-lq copied (%lq-last-pair copied))))

(define list-queue-unfold
  (case-lambda
    ((stop? mapper successor seed)
     (list-queue-unfold stop? mapper successor seed (list-queue)))
    ((stop? mapper successor seed q)
     (let loop ((s seed) (acc '()))
       (if (stop? s)
           (begin
             (let add-loop ((xs acc))
               (if (null? xs)
                   q
                   (begin
                     (list-queue-add-front! q (car xs))
                     (add-loop (cdr xs))))))
           (loop (successor s) (cons (mapper s) acc)))))))

(define list-queue-unfold-right
  (case-lambda
    ((stop? mapper successor seed)
     (list-queue-unfold-right stop? mapper successor seed (list-queue)))
    ((stop? mapper successor seed q)
     (let loop ((s seed) (acc '()))
       (if (stop? s)
           (begin
             (let add-loop ((xs acc))
               (if (null? xs)
                   q
                   (begin
                     (list-queue-add-back! q (car xs))
                     (add-loop (cdr xs))))))
           (loop (successor s) (cons (mapper s) acc)))))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 117 Accessors
;; ---------------------------------------------------------------------

(define (list-queue-front q)
  (if (list-queue-empty? q)
      (error "list-queue-front: empty list-queue" q)
      (car (%lq-first q))))

(define (list-queue-back q)
  (if (list-queue-empty? q)
      (error "list-queue-back: empty list-queue" q)
      (car (%lq-last q))))

(define (list-queue-list q)
  (%lq-first q))

(define (list-queue-first-last q)
  (values (%lq-first q) (%lq-last q)))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 117 Mutators
;; ---------------------------------------------------------------------

(define (list-queue-add-front! q elem)
  (let ((new-pair (cons elem (%lq-first q))))
    (if (list-queue-empty? q)
        (%lq-set-last! q new-pair))
    (%lq-set-first! q new-pair)))

(define (list-queue-add-back! q elem)
  (let ((new-pair (cons elem '())))
    (if (list-queue-empty? q)
        (%lq-set-first! q new-pair)
        (%lq-set-cdr! (%lq-last q) new-pair))
    (%lq-set-last! q new-pair)))

(define (list-queue-remove-front! q)
  (if (list-queue-empty? q)
      (error "list-queue-remove-front!: empty list-queue" q)
      (let* ((first (%lq-first q))
             (elem (car first))
             (next (cdr first)))
        (%lq-set-first! q next)
        (if (null? next)
            (%lq-set-last! q '()))
        elem)))

(define (list-queue-remove-back! q)
  (if (list-queue-empty? q)
      (error "list-queue-remove-back!: empty list-queue" q)
      (let ((first (%lq-first q))
            (last (%lq-last q)))
        (let ((elem (car last)))
          (if (eq? first last)
              (begin
                (%lq-set-first! q '())
                (%lq-set-last! q '()))
              (let loop ((cur first))
                (if (eq? (cdr cur) last)
                    (begin
                      (%lq-set-cdr! cur '())
                      (%lq-set-last! q cur))
                    (loop (cdr cur)))))
          elem))))

(define (list-queue-remove-all! q)
  (let ((res (%lq-first q)))
    (%lq-set-first! q '())
    (%lq-set-last! q '())
    res))

(define list-queue-set-list!
  (case-lambda
    ((q ls)
     (%lq-set-first! q ls)
     (%lq-set-last! q (%lq-last-pair ls)))
    ((q ls last)
     (%lq-set-first! q ls)
     (%lq-set-last! q last))))

;; ---------------------------------------------------------------------
;; §2.1 / SRFI 117 Concatenation & Mapping
;; ---------------------------------------------------------------------

(define (list-queue-concatenate qs)
  (let ((res (list-queue)))
    (let loop ((rest qs))
      (if (null? rest)
          res
          (begin
            (let elem-loop ((xs (%lq-first (car rest))))
              (if (pair? xs)
                  (begin
                    (list-queue-add-back! res (car xs))
                    (elem-loop (cdr xs)))))
            (loop (cdr rest)))))))

(define list-queue-append
  (case-lambda
    (() (list-queue))
    ((q . rest)
     (list-queue-concatenate (cons q rest)))))

(define (%lq-append-two! q1 q2)
  (if (list-queue-empty? q2)
      q1
      (begin
        (if (list-queue-empty? q1)
            (begin
              (%lq-set-first! q1 (%lq-first q2))
              (%lq-set-last! q1 (%lq-last q2)))
            (begin
              (%lq-set-cdr! (%lq-last q1) (%lq-first q2))
              (%lq-set-last! q1 (%lq-last q2))))
        q1)))

(define list-queue-append!
  (case-lambda
    (() (list-queue))
    ((q) q)
    ((q . rest)
     (let loop ((acc q) (qs rest))
       (if (null? qs)
           acc
           (loop (%lq-append-two! acc (car qs)) (cdr qs)))))))

(define (list-queue-map proc q)
  (let ((res (list-queue)))
    (let loop ((cur (%lq-first q)))
      (if (null? cur)
          res
          (begin
            (list-queue-add-back! res (proc (car cur)))
            (loop (cdr cur)))))))

(define (list-queue-map! proc q)
  (let loop ((cur (%lq-first q)))
    (if (pair? cur)
        (begin
          (%lq-set-car! cur (proc (car cur)))
          (loop (cdr cur))))))

(define (list-queue-for-each proc q)
  (let loop ((cur (%lq-first q)))
    (if (pair? cur)
        (begin
          (proc (car cur))
          (loop (cdr cur))))))

