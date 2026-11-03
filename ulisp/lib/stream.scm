;;; =======================================================================
;;; ULisp Standard Library: Streams (SRFI 41, R7RS-large Red Edition)
;;; Conforms to DSN-33 Architecture Specification & Issue #703
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; §1. Primitive Stream Types & Constructors (SRFI 41 stream-primitive)
;; ---------------------------------------------------------------------

(define-record-type <stream>
  (%make-stream promise)
  stream?
  (promise %stream-promise))

(define-record-type <stream-pare>
  (%make-stream-pare kar kdr)
  %stream-pare?
  (kar %stream-kar)
  (kdr %stream-kdr))

(define stream-null (%make-stream (make-promise '())))

(define-syntax stream-cons
  (syntax-rules ()
    ((_ obj strm)
     (%make-stream
      (delay (%make-stream-pare
              (delay obj)
              (%make-stream (delay-force (%stream-promise strm)))))))))

(define (stream-null? obj)
  (and (stream? obj)
       (null? (force (%stream-promise obj)))))

(define (stream-pair? obj)
  (and (stream? obj)
       (%stream-pare? (force (%stream-promise obj)))))

(define (stream-car strm)
  (if (not (stream? strm))
      (error "stream-car: expected a stream" strm)
      (let ((pare (force (%stream-promise strm))))
        (if (%stream-pare? pare)
            (force (%stream-kar pare))
            (error "stream-car: stream is null" strm)))))

(define (stream-cdr strm)
  (if (not (stream? strm))
      (error "stream-cdr: expected a stream" strm)
      (let ((pare (force (%stream-promise strm))))
        (if (%stream-pare? pare)
            (%stream-kdr pare)
            (error "stream-cdr: stream is null" strm)))))

(define-syntax stream-lambda
  (syntax-rules ()
    ((_ formals body)
     (lambda formals
       (%make-stream (delay-force (%stream-promise body)))))
    ((_ formals body1 body2 ...)
     (lambda formals
       (%make-stream (delay-force (%stream-promise (begin body1 body2 ...))))))))

;; ---------------------------------------------------------------------
;; §2. Derived Stream Syntax (SRFI 41 stream-derived)
;; ---------------------------------------------------------------------

(define-syntax define-stream
  (syntax-rules ()
    ((_ (name . formals) body)
     (define name (stream-lambda formals body)))
    ((_ (name . formals) body1 body2 ...)
     (define name (stream-lambda formals body1 body2 ...)))))

(define-syntax stream
  (syntax-rules ()
    ((_) stream-null)
    ((_ x) (stream-cons x stream-null))
    ((_ x y ...) (stream-cons x (stream y ...)))))

(define (%stream-cell-set! cell fn)
  (set-car! cell fn))

(define-syntax stream-let
  (syntax-rules ()
    ((_ tag () body)
     (let ((cell (cons #f '())))
       (let ((fn (stream-lambda ()
                   (let ((tag (car cell)))
                     body))))
         (%stream-cell-set! cell fn)
         (fn))))
    ((_ tag () body1 body2 ...)
     (let ((cell (cons #f '())))
       (let ((fn (stream-lambda ()
                   (let ((tag (car cell)))
                     body1 body2 ...))))
         (%stream-cell-set! cell fn)
         (fn))))
    ((_ tag ((var val) ...) body)
     (let ((cell (cons #f '())))
       (let ((fn (stream-lambda (var ...)
                   (let ((tag (car cell)))
                     body))))
         (%stream-cell-set! cell fn)
         (fn val ...))))
    ((_ tag ((var val) ...) body1 body2 ...)
     (let ((cell (cons #f '())))
       (let ((fn (stream-lambda (var ...)
                   (let ((tag (car cell)))
                     body1 body2 ...))))
         (%stream-cell-set! cell fn)
         (fn val ...))))))

(define-syntax %stream-of-aux
  (syntax-rules (in is)
    ((_ expr base)
     (stream-cons expr base))
    ((_ expr base (var in strm) rest ...)
     (let ((cell (cons #f '())))
       (let ((loop (lambda (s)
                     (%make-stream
                      (delay-force
                       (%stream-promise
                        (let ((loop (car cell)))
                          (if (stream-null? s)
                              base
                              (let ((var (stream-car s)))
                                (%stream-of-aux expr (loop (stream-cdr s)) rest ...))))))))))
         (%stream-cell-set! cell loop)
         (loop strm))))
    ((_ expr base (var is val) rest ...)
     (let ((var val))
       (%stream-of-aux expr base rest ...)))
    ((_ expr base pred rest ...)
     (if pred
         (%stream-of-aux expr base rest ...)
         base))))

(define-syntax stream-of
  (syntax-rules ()
    ((_ expr clause ...)
     (%make-stream
      (delay-force
       (%stream-promise
        (%stream-of-aux expr stream-null clause ...)))))))

;; ---------------------------------------------------------------------
;; §3. Derived Stream Constructors & Converters (SRFI 41)
;; ---------------------------------------------------------------------

(define (%list->stream-core objs)
  (stream-let loop ((ls objs))
    (if (null? ls)
        stream-null
        (stream-cons (car ls) (loop (cdr ls))))))

(define (list->stream objs)
  (if (not (list? objs))
      (error "list->stream: non-list argument" objs)
      (%list->stream-core objs)))

(define port->stream
  (case-lambda
    (() (port->stream (current-input-port)))
    ((p)
     (if (not (input-port? p))
         (error "port->stream: non-input-port argument" p)
         (stream-let loop ()
           (let ((c (read-char p)))
             (if (eof-object? c)
                 stream-null
                 (stream-cons c (loop)))))))))

(define stream->list
  (case-lambda
    ((strm)
     (if (not (stream? strm))
         (error "stream->list: non-stream argument" strm)
         (let loop ((s strm) (acc '()))
           (if (stream-null? s)
               (reverse acc)
               (loop (stream-cdr s) (cons (stream-car s) acc))))))
    ((n strm)
     (if (not (stream? strm))
         (error "stream->list: non-stream argument" strm)
         (if (< n 0)
             (error "stream->list: negative count" n)
             (let loop ((i n) (s strm) (acc '()))
               (if (or (<= i 0) (stream-null? s))
                   (reverse acc)
                   (loop (- i 1) (stream-cdr s) (cons (stream-car s) acc)))))))))

(define stream-from
  (case-lambda
    ((first) (stream-from first 1))
    ((first step)
     (stream-let loop ((cur first))
       (stream-cons cur (loop (+ cur step)))))))

(define stream-range
  (case-lambda
    ((first past)
     (stream-range first past (if (< first past) 1 -1)))
    ((first past step)
     (if (= step 0)
         (error "stream-range: zero step" step)
         (let ((cmp (if (> step 0)
                        (lambda (a b) (< a b))
                        (lambda (a b) (> a b)))))
           (stream-let loop ((cur first))
             (if (cmp cur past)
                 (stream-cons cur (loop (+ cur step)))
                 stream-null)))))))

(define (stream-iterate proc base)
  (stream-let loop ((val base))
    (stream-cons val (loop (proc val)))))

(define stream-constant
  (case-lambda
    (() stream-null)
    (( . objs)
     (stream-let loop ((cur objs))
       (if (null? cur)
           (loop objs)
           (stream-cons (car cur) (loop (cdr cur))))))))

(define (stream-unfold mapper pred? generator seed)
  (stream-let loop ((s seed))
    (if (not (pred? s))
        stream-null
        (stream-cons (mapper s) (loop (generator s))))))

(define (stream-unfolds gen seed)
  (let* ((initial-vals (call-with-values (lambda () (gen seed)) list))
         (n (- (length initial-vals) 1)))
    (let (( make-nth-stream
            (lambda (idx)
              (stream-let loop ((s seed))
                (let* ((vals (call-with-values (lambda () (gen s)) list))
                       (next-s (car vals))
                       (item (list-ref (cdr vals) idx)))
                  (cond
                    ((eq? item #f) (loop next-s))
                    ((null? item) stream-null)
                    ((pair? item) (stream-cons (car item) (loop next-s)))
                    (else (error "stream-unfolds: invalid generator item" item))))))))
      (let build ((i 0) (acc '()))
        (if (>= i n)
            (values-list (reverse acc))
            (build (+ i 1) (cons (make-nth-stream i) acc)))))))

;; ---------------------------------------------------------------------
;; §4. Stream Operations, Transformers & Consumers (SRFI 41)
;; ---------------------------------------------------------------------

(define (%stream-append-list strms)
  (stream-let loop ((rem strms))
    (cond
      ((null? rem) stream-null)
      ((null? (cdr rem)) (car rem))
      (else
       (stream-let inner ((s (car rem)))
         (if (stream-null? s)
             (loop (cdr rem))
             (stream-cons (stream-car s) (inner (stream-cdr s)))))))))

(define stream-append
  (case-lambda
    (() stream-null)
    ((s) s)
    (( . strms)
     (%stream-append-list strms))))

(define (stream-concat strms)
  (stream-let loop ((outer strms))
    (if (stream-null? outer)
        stream-null
        (let ((inner-strm (stream-car outer)))
          (stream-let inner ((s inner-strm))
            (if (stream-null? s)
                (loop (stream-cdr outer))
                (stream-cons (stream-car s) (inner (stream-cdr s)))))))))

(define (stream-reverse strm)
  (stream-let loop ((s strm) (acc stream-null))
    (if (stream-null? s)
        acc
        (loop (stream-cdr s) (stream-cons (stream-car s) acc)))))

(define (stream-ref strm n)
  (if (< n 0)
      (error "stream-ref: negative index" n)
      (let loop ((s strm) (i n))
        (cond
          ((stream-null? s) (error "stream-ref: index out of bounds" n))
          ((= i 0) (stream-car s))
          (else (loop (stream-cdr s) (- i 1)))))))

(define (stream-length strm)
  (let loop ((s strm) (len 0))
    (if (stream-null? s)
        len
        (loop (stream-cdr s) (+ len 1)))))

(define (stream-take n strm)
  (if (< n 0)
      (error "stream-take: negative count" n)
      (stream-let loop ((i n) (s strm))
        (if (or (<= i 0) (stream-null? s))
            stream-null
            (stream-cons (stream-car s) (loop (- i 1) (stream-cdr s)))))))

(define (stream-take-while pred? strm)
  (stream-let loop ((s strm))
    (cond
      ((stream-null? s) stream-null)
      ((pred? (stream-car s))
       (stream-cons (stream-car s) (loop (stream-cdr s))))
      (else stream-null))))

(define (stream-drop n strm)
  (if (< n 0)
      (error "stream-drop: negative count" n)
      (stream-let loop ((i n) (s strm))
        (if (or (<= i 0) (stream-null? s))
            s
            (loop (- i 1) (stream-cdr s))))))

(define (stream-drop-while pred? strm)
  (stream-let loop ((s strm))
    (cond
      ((stream-null? s) stream-null)
      ((pred? (stream-car s)) (loop (stream-cdr s)))
      (else s))))

(define (stream-filter pred? strm)
  (stream-let loop ((s strm))
    (cond
      ((stream-null? s) stream-null)
      ((pred? (stream-car s))
       (stream-cons (stream-car s) (loop (stream-cdr s))))
      (else (loop (stream-cdr s))))))

(define (stream-fold proc base strm)
  (let loop ((s strm) (acc base))
    (if (stream-null? s)
        acc
        (loop (stream-cdr s) (proc acc (stream-car s))))))

(define (stream-scan proc base strm)
  (stream-let loop ((s strm) (acc base))
    (if (stream-null? s)
        (stream-cons acc stream-null)
        (stream-cons acc (loop (stream-cdr s) (proc acc (stream-car s)))))))

(define (%any-stream-null? strms)
  (let loop ((ls strms))
    (cond
      ((null? ls) #f)
      ((stream-null? (car ls)) #t)
      (else (loop (cdr ls))))))

(define stream-map
  (case-lambda
    ((proc s)
     (stream-let loop ((cur s))
       (if (stream-null? cur)
           stream-null
           (stream-cons (proc (stream-car cur))
                        (loop (stream-cdr cur))))))
    ((proc s1 s2)
     (stream-let loop ((a s1) (b s2))
       (if (or (stream-null? a) (stream-null? b))
           stream-null
           (stream-cons (proc (stream-car a) (stream-car b))
                        (loop (stream-cdr a) (stream-cdr b))))))
    ((proc . strms)
     (stream-let loop ((ss strms))
       (if (%any-stream-null? ss)
           stream-null
           (stream-cons (apply proc (map stream-car ss))
                        (loop (map stream-cdr ss))))))))

(define stream-for-each
  (case-lambda
    ((proc s)
     (let loop ((cur s))
       (if (stream-null? cur)
           #t
           (begin
             (proc (stream-car cur))
             (loop (stream-cdr cur))))))
    ((proc s1 s2)
     (let loop ((a s1) (b s2))
       (if (or (stream-null? a) (stream-null? b))
           #t
           (begin
             (proc (stream-car a) (stream-car b))
             (loop (stream-cdr a) (stream-cdr b))))))
    ((proc . strms)
     (let loop ((ss strms))
       (if (%any-stream-null? ss)
           #t
           (begin
             (apply proc (map stream-car ss))
             (loop (map stream-cdr ss))))))))

(define stream-zip
  (case-lambda
    ((s)
     (stream-map (lambda (x) (list x)) s))
    ((s1 s2)
     (stream-map (lambda (a b) (list a b)) s1 s2))
    (( . strms)
     (stream-let loop ((ss strms))
       (if (%any-stream-null? ss)
           stream-null
           (stream-cons (map stream-car ss)
                        (loop (map stream-cdr ss))))))))
