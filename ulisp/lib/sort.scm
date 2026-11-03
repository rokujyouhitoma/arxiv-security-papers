;;; =======================================================================
;;; ULisp Standard Library: R7RS-large / SRFI 132 / SRFI 95 Sort Procedures
;;; Conforms to DSN-33 Architecture Specification & Issue #655
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; §SRFI-132 1. Sorted Predicates: list-sorted?, vector-sorted?
;;; -----------------------------------------------------------------------

(define (list-sorted? less? lst)
  (if (or (null? lst) (null? (cdr lst)))
      #t
      (let loop ((prev (car lst)) (rest (cdr lst)))
        (if (null? rest)
            #t
            (let ((curr (car rest)))
              (if (less? curr prev)
                  #f
                  (loop curr (cdr rest))))))))

(define (%vector-sorted? less? vec start end)
  (let ((len (vector-length vec)))
    (if (or (< start 0) (> start end) (> end len))
        (error "vector-sorted?: index out of range" start end len)
        (if (<= (- end start) 1)
            #t
            (let loop ((i (+ start 1)))
              (if (>= i end)
                  #t
                  (let ((prev (vector-ref vec (- i 1)))
                        (curr (vector-ref vec i)))
                    (if (less? curr prev)
                        #f
                        (loop (+ i 1))))))))))

(define vector-sorted?
  (case-lambda
    ((less? vec)
     (%vector-sorted? less? vec 0 (vector-length vec)))
    ((less? vec start)
     (%vector-sorted? less? vec start (vector-length vec)))
    ((less? vec start end)
     (%vector-sorted? less? vec start end))))

;;; -----------------------------------------------------------------------
;;; §SRFI-132 2. Merge Procedures: list-merge, vector-merge
;;; -----------------------------------------------------------------------

(define (list-merge less? l1 l2)
  (let loop ((r1 l1) (r2 l2) (acc '()))
    (cond
      ((null? r1) (append (reverse acc) r2))
      ((null? r2) (append (reverse acc) r1))
      (else
       (let ((h1 (car r1))
             (h2 (car r2)))
         (if (less? h2 h1)
             (loop r1 (cdr r2) (cons h2 acc))
             (loop (cdr r1) r2 (cons h1 acc))))))))

(define (vector-merge less? v1 v2)
  (let* ((len1 (vector-length v1))
         (len2 (vector-length v2))
         (out (make-vector (+ len1 len2))))
    (let loop ((i 0) (j 0) (k 0))
      (cond
        ((and (= i len1) (= j len2))
         out)
        ((= i len1)
         (vector-set! out k (vector-ref v2 j))
         (loop i (+ j 1) (+ k 1)))
        ((= j len2)
         (vector-set! out k (vector-ref v1 i))
         (loop (+ i 1) j (+ k 1)))
        (else
         (let ((e1 (vector-ref v1 i))
               (e2 (vector-ref v2 j)))
           (if (less? e2 e1)
               (begin
                 (vector-set! out k e2)
                 (loop i (+ j 1) (+ k 1)))
               (begin
                 (vector-set! out k e1)
                 (loop (+ i 1) j (+ k 1))))))))))

;;; -----------------------------------------------------------------------
;;; §SRFI-132 3. List Sorting (Stable Merge Sort): list-sort, list-sort!
;;; -----------------------------------------------------------------------

(define (list-sort less? lst)
  (cond
    ((or (null? lst) (null? (cdr lst)))
     lst)
    ((null? (cddr lst))
     (let ((a (car lst))
           (b (cadr lst)))
       (if (less? b a)
           (list b a)
           (list a b))))
    (else
     (let* ((len (length lst))
            (half (quotient len 2)))
       (let split-loop ((i 0) (curr lst) (left '()))
         (if (= i half)
             (let ((l-sorted (list-sort less? (reverse left)))
                   (r-sorted (list-sort less? curr)))
               (list-merge less? l-sorted r-sorted))
             (split-loop (+ i 1) (cdr curr) (cons (car curr) left))))))))

(define (%list-merge! less? l1 l2)
  (cond
    ((null? l1) l2)
    ((null? l2) l1)
    (else
     (let* ((take-l2 (less? (car l2) (car l1)))
            (head (if take-l2 l2 l1)))
       (let loop ((tail head)
                  (p1 (if take-l2 l1 (cdr l1)))
                  (p2 (if take-l2 (cdr l2) l2)))
         (cond
           ((null? p1)
            (set-cdr! tail p2)
            head)
           ((null? p2)
            (set-cdr! tail p1)
            head)
           (else
            (if (less? (car p2) (car p1))
                (begin
                  (set-cdr! tail p2)
                  (loop p2 p1 (cdr p2)))
                (begin
                  (set-cdr! tail p1)
                  (loop p1 (cdr p1) p2))))))))))

(define (list-sort! less? lst)
  (cond
    ((or (null? lst) (null? (cdr lst)))
     lst)
    ((null? (cddr lst))
     (let ((a (car lst))
           (b (cadr lst)))
       (if (less? b a)
           (begin
             (set-car! lst b)
             (set-car! (cdr lst) a)
             lst)
           lst)))
    (else
     (let* ((len (length lst))
            (half (quotient len 2)))
       (let split-loop ((i 1) (curr lst))
         (if (= i half)
             (let ((right (cdr curr)))
               (set-cdr! curr '())
               (let ((l-sorted (list-sort! less? lst))
                     (r-sorted (list-sort! less? right)))
                 (%list-merge! less? l-sorted r-sorted)))
             (split-loop (+ i 1) (cdr curr))))))))

(define list-stable-sort list-sort)

;;; -----------------------------------------------------------------------
;;; §SRFI-132 4. Vector Sorting (Stable Merge Sort): vector-sort, vector-sort!
;;; -----------------------------------------------------------------------

(define (%vector-sort! less? vec start end)
  (let ((len (vector-length vec)))
    (if (or (< start 0) (> start end) (> end len))
        (error "vector-sort!: index out of range" start end len)
        (let ((count (- end start)))
          (if (<= count 1)
              vec
              (let ((temp (make-vector count)))
                (let sort-range ((l 0) (r count))
                  (if (<= (- r l) 1)
                      #t
                      (let* ((mid (+ l (quotient (- r l) 2))))
                        (sort-range l mid)
                        (sort-range mid r)
                        (let merge-loop ((p1 l) (p2 mid) (k l))
                          (cond
                            ((and (= p1 mid) (= p2 r))
                             (let copy-back ((idx l))
                               (if (< idx r)
                                   (begin
                                     (vector-set! vec (+ start idx) (vector-ref temp idx))
                                     (copy-back (+ idx 1)))
                                   #t)))
                            ((= p1 mid)
                             (vector-set! temp k (vector-ref vec (+ start p2)))
                             (merge-loop p1 (+ p2 1) (+ k 1)))
                            ((= p2 r)
                             (vector-set! temp k (vector-ref vec (+ start p1)))
                             (merge-loop (+ p1 1) p2 (+ k 1)))
                            (else
                             (let ((val1 (vector-ref vec (+ start p1)))
                                   (val2 (vector-ref vec (+ start p2))))
                               (if (less? val2 val1)
                                   (begin
                                     (vector-set! temp k val2)
                                     (merge-loop p1 (+ p2 1) (+ k 1)))
                                   (begin
                                     (vector-set! temp k val1)
                                     (merge-loop (+ p1 1) p2 (+ k 1)))))))))))
                vec))))))

(define vector-sort!
  (case-lambda
    ((less? vec)
     (%vector-sort! less? vec 0 (vector-length vec)))
    ((less? vec start)
     (%vector-sort! less? vec start (vector-length vec)))
    ((less? vec start end)
     (%vector-sort! less? vec start end))))

(define (%vector-sort less? vec start end)
  (let ((len (vector-length vec)))
    (if (or (< start 0) (> start end) (> end len))
        (error "vector-sort: index out of range" start end len)
        (let ((cp (vector-copy vec start end)))
          (%vector-sort! less? cp 0 (- end start))))))

(define vector-sort
  (case-lambda
    ((less? vec)
     (%vector-sort less? vec 0 (vector-length vec)))
    ((less? vec start)
     (%vector-sort less? vec start (vector-length vec)))
    ((less? vec start end)
     (%vector-sort less? vec start end))))

(define vector-stable-sort vector-sort)

;;; -----------------------------------------------------------------------
;;; §SRFI-95 5. SRFI 95 / SLIB Compatibility Procedures: sort, sort!, sorted?, merge, merge!
;;; -----------------------------------------------------------------------

(define (sorted? seq less?)
  (cond
    ((vector? seq) (vector-sorted? less? seq))
    ((pair? seq) (list-sorted? less? seq))
    ((null? seq) #t)
    (else (error "sorted?: sequence must be a list or vector" seq))))

(define (merge l1 l2 less?)
  (list-merge less? l1 l2))

(define (merge! l1 l2 less?)
  (%list-merge! less? l1 l2))

(define (sort seq less?)
  (cond
    ((vector? seq) (vector-sort less? seq))
    ((pair? seq) (list-sort less? seq))
    ((null? seq) '())
    (else (error "sort: sequence must be a list or vector" seq))))

(define (sort! seq less?)
  (cond
    ((vector? seq) (vector-sort! less? seq))
    ((pair? seq) (list-sort! less? seq))
    ((null? seq) '())
    (else (error "sort!: sequence must be a list or vector" seq))))
