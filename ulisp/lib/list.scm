;;; =======================================================================
;;; ULisp Standard Library: Lists (R7RS Section 6.4)
;;; Conforms to DSN-33 Architecture Specification, Issue #551 & Issue #561
;;; Traceability: ulisp/docs/r7rs_specification_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §6.4 Pairs and lists: length, reverse & append
;; ---------------------------------------------------------------------
(define (length ls)
  (let loop ((l ls) (n 0))
    (if (null? l)
        n
        (loop (cdr l) (+ n 1)))))

(define (reverse ls)
  (let loop ((l ls) (acc '()))
    (if (null? l)
        acc
        (loop (cdr l) (cons (car l) acc)))))

(define append
  (case-lambda
    (() '())
    ((lst) lst)
    ((l1 l2)
     (let loop ((l (reverse l1)) (acc l2))
       (if (null? l)
           acc
           (loop (cdr l) (cons (car l) acc)))))
    ((l1 l2 . rest)
     (let loop ((acc (append l1 l2)) (rs rest))
       (if (null? rs)
           acc
           (loop (append acc (car rs)) (cdr rs)))))))

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

;; =======================================================================
;; R7RS-large / SRFI 1 (List Library) Extensions (Issue #648)
;; =======================================================================

;; ---------------------------------------------------------------------
;; 1. Constructors
;; ---------------------------------------------------------------------
(define (xcons d a)
  (cons a d))

(define (%cons*-helper args)
  (cond
    ((null? args) (error "cons*: requires at least one argument"))
    ((null? (cdr args)) (car args))
    (else (cons (car args) (%cons*-helper (cdr args))))))

(define cons*
  (case-lambda
    ((arg) arg)
    (args (%cons*-helper args))))

(define (list-tabulate n init-proc)
  (if (< n 0)
      (error "list-tabulate: count must be non-negative" n)
      (let loop ((i (- n 1)) (acc '()))
        (if (< i 0)
            acc
            (loop (- i 1) (cons (init-proc i) acc))))))

(define iota
  (case-lambda
    ((count) (iota count 0 1))
    ((count start) (iota count start 1))
    ((count start step)
     (if (< count 0)
         (error "iota: count must be non-negative" count)
         (let loop ((i (- count 1)) (acc '()))
           (if (< i 0)
               acc
               (loop (- i 1) (cons (+ start (* i step)) acc))))))))

;; ---------------------------------------------------------------------
;; 2. Predicates
;; ---------------------------------------------------------------------
(define (proper-list? x)
  (cond
    ((null? x) #t)
    ((not (pair? x)) #f)
    (else
     (let loop ((fast (cdr x)) (slow x))
       (cond
         ((null? fast) #t)
         ((not (pair? fast)) #f)
         ((null? (cdr fast)) #t)
         ((not (pair? (cdr fast))) #f)
         ((or (eq? fast slow) (eq? (cdr fast) slow)) #f)
         (else
          (loop (cddr fast) (cdr slow))))))))

(define (circular-list? x)
  (if (not (pair? x))
      #f
      (let loop ((fast (cdr x)) (slow x))
        (cond
          ((not (pair? fast)) #f)
          ((not (pair? (cdr fast))) #f)
          ((or (eq? fast slow) (eq? (cdr fast) slow)) #t)
          (else
           (loop (cddr fast) (cdr slow)))))))

(define (dotted-list? x)
  (cond
    ((not (pair? x)) #f)
    (else
     (let loop ((fast (cdr x)) (slow x))
       (cond
         ((null? fast) #f)
         ((not (pair? fast)) #t)
         ((null? (cdr fast)) #f)
         ((not (pair? (cdr fast))) #t)
         ((or (eq? fast slow) (eq? (cdr fast) slow)) #f)
         (else
          (loop (cddr fast) (cdr slow))))))))

(define (not-pair? x)
  (not (pair? x)))

(define (null-list? l)
  (cond
    ((pair? l) #f)
    ((null? l) #t)
    (else (error "null-list?: argument is not a list or pair" l))))

(define list=
  (case-lambda
    ((elt=) #t)
    ((elt= l1) #t)
    ((elt= l1 l2)
     (let loop ((a l1) (b l2))
       (cond
         ((and (null? a) (null? b)) #t)
         ((or (null? a) (null? b)) #f)
         ((not (and (pair? a) (pair? b))) #f)
         ((elt= (car a) (car b)) (loop (cdr a) (cdr b)))
         (else #f))))
    ((elt= l1 l2 . rest)
     (and (list= elt= l1 l2)
          (apply list= elt= (cons l2 rest))))))

;; ---------------------------------------------------------------------
;; 3. Selectors
;; ---------------------------------------------------------------------
(define (first clist) (car clist))
(define (second clist) (cadr clist))
(define (third clist) (caddr clist))
(define (fourth clist) (cadddr clist))
(define (fifth x) (car (cddddr x)))
(define (sixth x) (cadr (cddddr x)))
(define (seventh x) (caddr (cddddr x)))
(define (eighth x) (cadddr (cddddr x)))
(define (ninth x) (car (cddddr (cddddr x))))
(define (tenth x) (cadr (cddddr (cddddr x))))

(define (car+cdr pair)
  (values (car pair) (cdr pair)))

(define (take lst k)
  (let loop ((l lst) (i k) (acc '()))
    (if (<= i 0)
        (reverse acc)
        (if (pair? l)
            (loop (cdr l) (- i 1) (cons (car l) acc))
            (error "take: index out of bounds" k)))))

(define (drop lst k)
  (list-tail lst k))

(define (take-right lst k)
  (let loop ((lead (list-tail lst k)) (lag lst))
    (if (pair? lead)
        (loop (cdr lead) (cdr lag))
        lag)))

(define (drop-right lst k)
  (let loop ((lead (list-tail lst k)) (lag lst) (acc '()))
    (if (pair? lead)
        (loop (cdr lead) (cdr lag) (cons (car lag) acc))
        (reverse acc))))

(define (split-at lst k)
  (let loop ((l lst) (i k) (acc '()))
    (if (<= i 0)
        (values (reverse acc) l)
        (if (pair? l)
            (loop (cdr l) (- i 1) (cons (car l) acc))
            (error "split-at: index out of bounds" k)))))

(define (last lst)
  (if (not (pair? lst))
      (error "last: empty list or non-pair" lst)
      (let loop ((l lst))
        (if (pair? (cdr l))
            (loop (cdr l))
            (car l)))))

(define (last-pair lst)
  (if (not (pair? lst))
      (error "last-pair: empty list or non-pair" lst)
      (let loop ((l lst))
        (if (pair? (cdr l))
            (loop (cdr l))
            l))))

;; ---------------------------------------------------------------------
;; 4. Fold, Unfold & Reductions
;; ---------------------------------------------------------------------
(define count
  (case-lambda
    ((pred ls)
     (let loop ((l ls) (acc 0))
       (cond
         ((null? l) acc)
         ((pred (car l)) (loop (cdr l) (+ acc 1)))
         (else (loop (cdr l) acc)))))
    ((pred l1 l2)
     (let loop ((a l1) (b l2) (acc 0))
       (cond
         ((or (null? a) (null? b)) acc)
         ((pred (car a) (car b)) (loop (cdr a) (cdr b) (+ acc 1)))
         (else (loop (cdr a) (cdr b) acc)))))
    ((pred l1 l2 . rest)
     (let ((lists (cons l1 (cons l2 rest))))
       (let loop ((ls lists) (acc 0))
         (if (%any-null? ls)
             acc
             (let ((val (%apply-list pred (%cars ls))))
               (loop (%cdrs ls) (if val (+ acc 1) acc)))))))))

(define fold
  (case-lambda
    ((kons knil ls)
     (let loop ((l ls) (acc knil))
       (if (null? l)
           acc
           (loop (cdr l) (kons (car l) acc)))))
    ((kons knil l1 l2)
     (let loop ((a l1) (b l2) (acc knil))
       (if (or (null? a) (null? b))
           acc
           (loop (cdr a) (cdr b) (kons (car a) (car b) acc)))))
    ((kons knil l1 l2 . rest)
     (let ((lists (cons l1 (cons l2 rest))))
       (let loop ((ls lists) (acc knil))
         (if (%any-null? ls)
             acc
             (loop (%cdrs ls) (%apply-list kons (append (%cars ls) (list acc))))))))))

(define fold-right
  (case-lambda
    ((kons knil ls)
     (let recur ((l ls))
       (if (null? l)
           knil
           (kons (car l) (recur (cdr l))))))
    ((kons knil l1 l2)
     (let recur ((a l1) (b l2))
       (if (or (null? a) (null? b))
           knil
           (kons (car a) (car b) (recur (cdr a) (cdr b))))))
    ((kons knil l1 l2 . rest)
     (let ((lists (cons l1 (cons l2 rest))))
       (let recur ((ls lists))
         (if (%any-null? ls)
             knil
             (%apply-list kons (append (%cars ls) (list (recur (%cdrs ls)))))))))))

(define unfold
  (case-lambda
    ((p f g seed)
     (unfold p f g seed (lambda (x) '())))
    ((p f g seed tail-gen)
     (let loop ((seed seed) (acc '()))
       (if (p seed)
           (append (reverse acc) (tail-gen seed))
           (loop (g seed) (cons (f seed) acc)))))))

(define unfold-right
  (case-lambda
    ((p f g seed)
     (unfold-right p f g seed '()))
    ((p f g seed tail)
     (let loop ((seed seed) (acc tail))
       (if (p seed)
           acc
           (loop (g seed) (cons (f seed) acc)))))))

(define (reduce f ridentity lst)
  (if (null? lst)
      ridentity
      (fold f (car lst) (cdr lst))))

(define (reduce-right f ridentity lst)
  (if (null? lst)
      ridentity
      (let recur ((l lst))
        (if (null? (cdr l))
            (car l)
            (f (car l) (recur (cdr l)))))))

;; ---------------------------------------------------------------------
;; 5. Searching & Filtering
;; ---------------------------------------------------------------------
(define (filter pred lst)
  (let loop ((l lst) (acc '()))
    (cond
      ((null? l) (reverse acc))
      ((pred (car l)) (loop (cdr l) (cons (car l) acc)))
      (else (loop (cdr l) acc)))))

(define (remove pred lst)
  (filter (lambda (x) (not (pred x))) lst))

(define (partition pred lst)
  (let loop ((l lst) (in '()) (out '()))
    (cond
      ((null? l) (values (reverse in) (reverse out)))
      ((pred (car l)) (loop (cdr l) (cons (car l) in) out))
      (else (loop (cdr l) in (cons (car l) out))))))

(define (find pred lst)
  (let loop ((l lst))
    (cond
      ((null? l) #f)
      ((pred (car l)) (car l))
      (else (loop (cdr l))))))

(define (find-tail pred lst)
  (let loop ((l lst))
    (cond
      ((null? l) #f)
      ((pred (car l)) l)
      (else (loop (cdr l))))))

(define any
  (case-lambda
    ((pred ls)
     (let loop ((l ls))
       (cond
         ((null? l) #f)
         ((null? (cdr l)) (pred (car l)))
         (else
          (let ((val (pred (car l))))
            (if val val (loop (cdr l))))))))
    ((pred l1 l2)
     (let loop ((a l1) (b l2))
       (cond
         ((or (null? a) (null? b)) #f)
         ((or (null? (cdr a)) (null? (cdr b))) (pred (car a) (car b)))
         (else
          (let ((val (pred (car a) (car b))))
            (if val val (loop (cdr a) (cdr b))))))))
    ((pred l1 l2 . rest)
     (let ((lists (cons l1 (cons l2 rest))))
       (let loop ((ls lists))
         (if (%any-null? ls)
             #f
             (if (%any-null? (%cdrs ls))
                 (%apply-list pred (%cars ls))
                 (let ((val (%apply-list pred (%cars ls))))
                   (if val val (loop (%cdrs ls)))))))))))

(define every
  (case-lambda
    ((pred ls)
     (cond
       ((null? ls) #t)
       (else
        (let loop ((l ls))
          (if (null? (cdr l))
              (pred (car l))
              (let ((val (pred (car l))))
                (if val (loop (cdr l)) #f)))))))
    ((pred l1 l2)
     (cond
       ((or (null? l1) (null? l2)) #t)
       (else
        (let loop ((a l1) (b l2))
          (if (or (null? (cdr a)) (null? (cdr b)))
              (pred (car a) (car b))
              (let ((val (pred (car a) (car b))))
                (if val (loop (cdr a) (cdr b)) #f)))))))
    ((pred l1 l2 . rest)
     (let ((lists (cons l1 (cons l2 rest))))
       (if (%any-null? lists)
           #t
           (let loop ((ls lists))
             (if (%any-null? (%cdrs ls))
                 (%apply-list pred (%cars ls))
                 (let ((val (%apply-list pred (%cars ls))))
                   (if val (loop (%cdrs ls)) #f)))))))))

(define list-index
  (case-lambda
    ((pred ls)
     (let loop ((l ls) (i 0))
       (cond
         ((null? l) #f)
         ((pred (car l)) i)
         (else (loop (cdr l) (+ i 1))))))
    ((pred l1 l2)
     (let loop ((a l1) (b l2) (i 0))
       (cond
         ((or (null? a) (null? b)) #f)
         ((pred (car a) (car b)) i)
         (else (loop (cdr a) (cdr b) (+ i 1))))))
    ((pred l1 l2 . rest)
     (let ((lists (cons l1 (cons l2 rest))))
       (let loop ((ls lists) (i 0))
         (if (%any-null? ls)
             #f
             (if (%apply-list pred (%cars ls))
                 i
                 (loop (%cdrs ls) (+ i 1)))))))))

(define (take-while pred lst)
  (let loop ((l lst) (acc '()))
    (cond
      ((null? l) (reverse acc))
      ((pred (car l)) (loop (cdr l) (cons (car l) acc)))
      (else (reverse acc)))))

(define (drop-while pred lst)
  (let loop ((l lst))
    (cond
      ((null? l) '())
      ((pred (car l)) (loop (cdr l)))
      (else l))))

(define (span pred lst)
  (let loop ((l lst) (acc '()))
    (cond
      ((null? l) (values (reverse acc) '()))
      ((pred (car l)) (loop (cdr l) (cons (car l) acc)))
      (else (values (reverse acc) l)))))

(define (break pred lst)
  (span (lambda (x) (not (pred x))) lst))

;; ---------------------------------------------------------------------
;; 6. Deletion & Association Lists
;; ---------------------------------------------------------------------
(define (%default-equal? a b)
  (cond
    ((eq? a b) #t)
    ((and (number? a) (number? b)) (= a b))
    ((and (string? a) (string? b)) (string=? a b))
    ((and (char? a) (char? b)) (char=? a b))
    ((and (pair? a) (pair? b))
     (and (%default-equal? (car a) (car b))
          (%default-equal? (cdr a) (cdr b))))
    ((and (vector? a) (vector? b))
     (and (= (vector-length a) (vector-length b))
          (let loop ((i 0))
            (if (= i (vector-length a))
                #t
                (if (%default-equal? (vector-ref a i) (vector-ref b i))
                    (loop (+ i 1))
                    #f)))))
    (else #f)))

(define delete
  (case-lambda
    ((x lst) (delete x lst %default-equal?))
    ((x lst elt=)
     (let loop ((l lst) (acc '()))
       (cond
         ((null? l) (reverse acc))
         ((elt= x (car l)) (loop (cdr l) acc))
         (else (loop (cdr l) (cons (car l) acc))))))))

(define delete-duplicates
  (case-lambda
    ((lst) (delete-duplicates lst %default-equal?))
    ((lst elt=)
     (let loop ((l lst) (acc '()))
       (cond
         ((null? l) (reverse acc))
         ((let member-loop ((seen acc))
            (cond
              ((null? seen) #f)
              ((elt= (car l) (car seen)) #t)
              (else (member-loop (cdr seen)))))
          (loop (cdr l) acc))
         (else (loop (cdr l) (cons (car l) acc))))))))

(define (alist-cons key datum alist)
  (cons (cons key datum) alist))

(define (alist-copy alist)
  (map (lambda (pair) (cons (car pair) (cdr pair))) alist))

(define alist-delete
  (case-lambda
    ((key alist) (alist-delete key alist %default-equal?))
    ((key alist elt=)
     (let loop ((l alist) (acc '()))
       (cond
         ((null? l) (reverse acc))
         ((elt= key (caar l)) (loop (cdr l) acc))
         (else (loop (cdr l) (cons (car l) acc))))))))



