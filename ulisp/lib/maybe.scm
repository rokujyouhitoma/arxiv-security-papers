;;; =======================================================================
;;; ULisp Standard Library: SRFI 189 Maybe and Either (R7RS-large Hypnos Docket)
;;; Conforms to DSN-33 Architecture Specification, Issue #865
;;; Traceability: ulisp/docs/ref_r7rs_compliance.md
;;; =======================================================================

;; ---------------------------------------------------------------------
;; § SRFI 189: Disjoint Record Types & Core Definitions
;; ---------------------------------------------------------------------

(define-record-type <just>
  (raw-just objs)
  just?
  (objs just-objs))

(define-record-type <nothing>
  (make-nothing)
  nothing?)

(define-record-type <left>
  (raw-left objs)
  left?
  (objs left-objs))

(define-record-type <right>
  (raw-right objs)
  right?
  (objs right-objs))

(define nothing-obj (make-nothing))

(define (nothing)
  nothing-obj)

;; ---------------------------------------------------------------------
;; § SRFI 189: Internal Utilities
;; ---------------------------------------------------------------------

(define-syntax const
  (syntax-rules ()
    ((_ obj)
     (case-lambda
       (() obj)
       ((x) obj)
       ((x y) obj)
       (args obj)))))

(define (singleton? lis)
  (and (pair? lis) (null? (cdr lis))))

(define-syntax fast-apply
  (syntax-rules ()
    ((_ proc args)
     (if (singleton? args) (proc (car args)) (apply proc args)))))

(define (fast-list->values vals)
  (cond
    ((null? vals) (values))
    ((singleton? vals) (car vals))
    (else (values-list vals))))

(define %first-class-values
  (case-lambda
    (() (values))
    ((x) x)
    ((x y) (values x y))
    ((x y z) (values x y z))
    (args (values-list args))))

(define unspecified (if #f #f))

(define-syntax assume
  (syntax-rules ()
    ((_ condition . _)
     (unless condition
       (error "assumption failed")))))

;; ---------------------------------------------------------------------
;; § SRFI 189: Constructors
;; ---------------------------------------------------------------------

(define just
  (case-lambda
    (() (raw-just '()))
    ((x) (raw-just (list x)))
    ((x y) (raw-just (list x y)))
    (objs (raw-just objs))))

(define left
  (case-lambda
    (() (raw-left '()))
    ((x) (raw-left (list x)))
    ((x y) (raw-left (list x y)))
    (objs (raw-left objs))))

(define right
  (case-lambda
    (() (raw-right '()))
    ((x) (raw-right (list x)))
    ((x y) (raw-right (list x y)))
    (objs (raw-right objs))))

(define (list->just lis)
  (assume (or (null? lis) (pair? lis)))
  (raw-just (list-copy lis)))

(define (list->right lis)
  (assume (or (null? lis) (pair? lis)))
  (raw-right (list-copy lis)))

(define (list->left lis)
  (assume (or (null? lis) (pair? lis)))
  (raw-left (list-copy lis)))

(define maybe->either
  (case-lambda
    ((maybe)
     (assume (maybe? maybe))
     (if (nothing? maybe)
         (raw-left '())
         (raw-right (just-objs maybe))))
    ((maybe def)
     (assume (maybe? maybe))
     (if (nothing? maybe)
         (raw-left (list def))
         (raw-right (just-objs maybe))))
    ((maybe . default-objs)
     (assume (maybe? maybe))
     (if (nothing? maybe)
         (raw-left default-objs)
         (raw-right (just-objs maybe))))))

(define (either->maybe either)
  (assume (either? either))
  (if (left? either)
      nothing-obj
      (raw-just (right-objs either))))

(define (either-swap either)
  (assume (either? either))
  (if (right? either)
      (raw-left (right-objs either))
      (raw-right (left-objs either))))

;; ---------------------------------------------------------------------
;; § SRFI 189: Predicates
;; ---------------------------------------------------------------------

(define (maybe? obj)
  (or (just? obj) (nothing? obj)))

(define (%maybe=2 equal maybe1 maybe2)
  (or (eqv? maybe1 maybe2)
      (and (just? maybe1)
           (just? maybe2)
           (list= equal (just-objs maybe1) (just-objs maybe2)))))

(define maybe=
  (case-lambda
    ((equal maybe1) #t)
    ((equal maybe1 maybe2) (%maybe=2 equal maybe1 maybe2))
    ((equal maybe1 . maybes)
     (assume (procedure? equal))
     (every (lambda (maybe2) (%maybe=2 equal maybe1 maybe2))
            maybes))))

(define (either? obj)
  (or (left? obj) (right? obj)))

(define (%either=2 equal either1 either2)
  (let ((e= (lambda (acc) (list= equal (acc either1) (acc either2)))))
    (or (eqv? either1 either2)
        (and (left? either1) (left? either2) (e= left-objs))
        (and (right? either1) (right? either2) (e= right-objs)))))

(define either=
  (case-lambda
    ((equal either1) #t)
    ((equal either1 either2) (%either=2 equal either1 either2))
    ((equal either1 . eithers)
     (assume (procedure? equal))
     (every (lambda (either2) (%either=2 equal either1 either2))
            eithers))))

;; ---------------------------------------------------------------------
;; § SRFI 189: Accessors
;; ---------------------------------------------------------------------

(define maybe-ref
  (case-lambda
    ((maybe failure)
     (assume (maybe? maybe))
     (assume (procedure? failure))
     (if (just? maybe)
         (fast-list->values (just-objs maybe))
         (failure)))
    ((maybe failure success)
     (assume (maybe? maybe))
     (assume (procedure? failure))
     (assume (procedure? success))
     (if (just? maybe)
         (let ((objs (just-objs maybe)))
           (fast-apply success objs))
         (failure)))))

(define maybe-ref/default
  (case-lambda
    ((maybe)
     (assume (maybe? maybe))
     (if (just? maybe)
         (fast-list->values (just-objs maybe))
         (values)))
    ((maybe default)
     (assume (maybe? maybe))
     (if (just? maybe)
         (fast-list->values (just-objs maybe))
         default))
    ((maybe . default-objs)
     (assume (maybe? maybe))
     (if (just? maybe)
         (fast-list->values (just-objs maybe))
         (fast-list->values default-objs)))))

(define (%either-ref-single either accessor cont)
  (let ((objs (accessor either)))
    (fast-apply cont objs)))

(define either-ref
  (case-lambda
    ((either failure)
     (assume (either? either))
     (assume (procedure? failure))
     (if (right? either)
         (fast-list->values (right-objs either))
         (%either-ref-single either left-objs failure)))
    ((either failure success)
     (assume (either? either))
     (assume (procedure? failure))
     (assume (procedure? success))
     (if (right? either)
         (%either-ref-single either right-objs success)
         (%either-ref-single either left-objs failure)))))

(define either-ref/default
  (case-lambda
    ((either)
     (assume (either? either))
     (if (right? either)
         (fast-list->values (right-objs either))
         (values)))
    ((either default)
     (assume (either? either))
     (if (right? either)
         (fast-list->values (right-objs either))
         default))
    ((either . default-objs)
     (assume (either? either))
     (if (right? either)
         (fast-list->values (right-objs either))
         (fast-list->values default-objs)))))

;; ---------------------------------------------------------------------
;; § SRFI 189: Join and Bind (Monadic Operations)
;; ---------------------------------------------------------------------

(define (maybe-join maybe)
  (assume (maybe? maybe))
  (if (nothing? maybe)
      nothing-obj
      (let ((objs (just-objs maybe)))
        (assume (and (singleton? objs) (maybe? (car objs)))
                "maybe-join: invalid payload")
        (car objs))))

(define (%maybe-bind-loop m mp mprocs)
  (maybe-ref m
             nothing
             (case-lambda
               (()
                (if (null? mprocs)
                    (mp)
                    (%maybe-bind-loop (mp) (car mprocs) (cdr mprocs))))
               ((x)
                (if (null? mprocs)
                    (mp x)
                    (%maybe-bind-loop (mp x) (car mprocs) (cdr mprocs))))
               (objs
                (if (null? mprocs)
                    (apply mp objs)
                    (%maybe-bind-loop (apply mp objs) (car mprocs) (cdr mprocs)))))))

(define maybe-bind
  (case-lambda
    ((maybe mproc)
     (assume (maybe? maybe))
     (maybe-ref maybe nothing mproc))
    ((maybe mproc . mprocs)
     (assume (maybe? maybe))
     (%maybe-bind-loop maybe mproc mprocs))))

(define (%run-maybe-compose mprocs args)
  (let lp ((args args) (mproc (car mprocs)) (rest (cdr mprocs)))
    (if (null? rest)
        (fast-apply mproc args)
        (maybe-ref (fast-apply mproc args)
                   nothing
                   (case-lambda
                     (() (lp '() (car rest) (cdr rest)))
                     ((x) (lp (list x) (car rest) (cdr rest)))
                     (objs (lp objs (car rest) (cdr rest))))))))

(define maybe-compose
  (case-lambda
    ((mproc) mproc)
    ((mproc . rest)
     (let ((all (cons mproc rest)))
       (case-lambda
         (() (%run-maybe-compose all '()))
         ((x) (%run-maybe-compose all (list x)))
         ((x y) (%run-maybe-compose all (list x y)))
         (args (%run-maybe-compose all args)))))))

(define (either-join either)
  (assume (either? either))
  (if (left? either)
      either
      (let ((objs (right-objs either)))
        (assume (and (singleton? objs) (either? (car objs)))
                "either-join: invalid payload")
        (car objs))))

(define (%either-bind-loop e mp mprocs)
  (either-ref e
              (const e)
              (case-lambda
                (()
                 (if (null? mprocs)
                     (mp)
                     (%either-bind-loop (mp) (car mprocs) (cdr mprocs))))
                ((x)
                 (if (null? mprocs)
                     (mp x)
                     (%either-bind-loop (mp x) (car mprocs) (cdr mprocs))))
                (objs
                 (if (null? mprocs)
                     (apply mp objs)
                     (%either-bind-loop (apply mp objs) (car mprocs) (cdr mprocs)))))))

(define either-bind
  (case-lambda
    ((either mproc)
     (assume (either? either))
     (either-ref either (const either) mproc))
    ((either mproc . mprocs)
     (assume (either? either))
     (%either-bind-loop either mproc mprocs))))

(define (%run-either-compose mprocs args)
  (let lp ((args args) (mproc (car mprocs)) (rest (cdr mprocs)))
    (if (null? rest)
        (fast-apply mproc args)
        (either-ref (fast-apply mproc args)
                    left
                    (case-lambda
                      (() (lp '() (car rest) (cdr rest)))
                      ((x) (lp (list x) (car rest) (cdr rest)))
                      (objs (lp objs (car rest) (cdr rest))))))))

(define either-compose
  (case-lambda
    ((mproc) mproc)
    ((mproc . rest)
     (let ((all (cons mproc rest)))
       (case-lambda
         (() (%run-either-compose all '()))
         ((x) (%run-either-compose all (list x)))
         ((x y) (%run-either-compose all (list x y)))
         (args (%run-either-compose all args)))))))

;; ---------------------------------------------------------------------
;; § SRFI 189: Sequence Operations
;; ---------------------------------------------------------------------

(define (maybe-length maybe)
  (assume (maybe? maybe))
  (if (just? maybe) 1 0))

(define (maybe-filter pred maybe)
  (assume (procedure? pred))
  (assume (maybe? maybe))
  (if (and (just? maybe) (fast-apply pred (just-objs maybe)))
      maybe
      nothing-obj))

(define (maybe-remove pred maybe)
  (assume (procedure? pred))
  (assume (maybe? maybe))
  (if (and (just? maybe)
           (not (fast-apply pred (just-objs maybe))))
      maybe
      nothing-obj))

(define maybe-sequence
  (case-lambda
   ((container cmap) (maybe-sequence container cmap list))
   ((container cmap aggregator)
    (assume (procedure? cmap))
    (assume (procedure? aggregator))
    (call-with-current-continuation
     (lambda (return)
       (just (cmap (lambda (m)
                     (maybe-ref m (lambda () (return m)) aggregator))
                   container)))))))

(define (either-length either)
  (assume (either? either))
  (if (right? either) 1 0))

(define either-filter
  (case-lambda
    ((pred either)
     (assume (procedure? pred))
     (assume (either? either))
     (if (and (right? either) (fast-apply pred (right-objs either)))
         either
         (raw-left '())))
    ((pred either def)
     (assume (procedure? pred))
     (assume (either? either))
     (if (and (right? either) (fast-apply pred (right-objs either)))
         either
         (raw-left (list def))))
    ((pred either . default-objs)
     (assume (procedure? pred))
     (assume (either? either))
     (if (and (right? either) (fast-apply pred (right-objs either)))
         either
         (raw-left default-objs)))))

(define either-remove
  (case-lambda
    ((pred either)
     (assume (procedure? pred))
     (assume (either? either))
     (if (and (right? either) (not (fast-apply pred (right-objs either))))
         either
         (raw-left '())))
    ((pred either def)
     (assume (procedure? pred))
     (assume (either? either))
     (if (and (right? either) (not (fast-apply pred (right-objs either))))
         either
         (raw-left (list def))))
    ((pred either . default-objs)
     (assume (procedure? pred))
     (assume (either? either))
     (if (and (right? either) (not (fast-apply pred (right-objs either))))
         either
         (raw-left default-objs)))))

(define either-sequence
  (case-lambda
   ((container cmap) (either-sequence container cmap list))
   ((container cmap aggregator)
    (assume (procedure? cmap))
    (assume (procedure? aggregator))
    (call-with-current-continuation
     (lambda (return)
       (right (cmap (lambda (e)
                      (either-ref e (const (return e)) aggregator))
                    container)))))))

;; ---------------------------------------------------------------------
;; § SRFI 189: Protocol Conversion
;; ---------------------------------------------------------------------

(define (maybe->list maybe)
  (assume (maybe? maybe))
  (if (nothing? maybe) '() (just-objs maybe)))

(define (either->list either)
  (assume (either? either))
  ((if (right? either) right-objs left-objs) either))

(define (list->maybe lis)
  (assume (or (null? lis) (pair? lis)))
  (if (null? lis) nothing-obj (raw-just (list-copy lis))))

(define list->either
  (case-lambda
    ((lis)
     (assume (or (null? lis) (pair? lis)))
     (if (null? lis) (raw-left '()) (raw-right (list-copy lis))))
    ((lis def)
     (assume (or (null? lis) (pair? lis)))
     (if (null? lis) (raw-left (list def)) (raw-right (list-copy lis))))
    ((lis . default-objs)
     (assume (or (null? lis) (pair? lis)))
     (if (null? lis) (raw-left default-objs) (raw-right (list-copy lis))))))

(define (maybe->truth maybe)
  (assume (maybe? maybe))
  (if (nothing? maybe)
      #f
      (begin
       (assume (singleton? (just-objs maybe))
               "maybe->truth: invalid payload")
       (car (just-objs maybe)))))

(define (either->truth either)
  (assume (either? either))
  (if (left? either)
      #f
      (begin
       (assume (singleton? (right-objs either))
               "either->truth: invalid payload")
       (car (right-objs either)))))

(define (truth->maybe obj)
  (if obj (just obj) nothing-obj))

(define truth->either
  (case-lambda
    ((obj) (if obj (right obj) (raw-left '())))
    ((obj def) (if obj (right obj) (raw-left (list def))))
    ((obj . default-objs) (if obj (right obj) (raw-left default-objs)))))

(define (maybe->list-truth maybe)
  (assume (maybe? maybe))
  (if (just? maybe) (just-objs maybe) #f))

(define (either->list-truth either)
  (assume (either? either))
  (if (right? either) (right-objs either) #f))

(define (list-truth->maybe list-or-false)
  (if list-or-false
      (begin
       (assume (or (null? list-or-false) (pair? list-or-false)))
       (raw-just (list-copy list-or-false)))
      nothing-obj))

(define list-truth->either
  (case-lambda
    ((list-or-false)
     (if list-or-false
         (begin
          (assume (or (null? list-or-false) (pair? list-or-false)))
          (raw-right (list-copy list-or-false)))
         (raw-left '())))
    ((list-or-false def)
     (if list-or-false
         (begin
          (assume (or (null? list-or-false) (pair? list-or-false)))
          (raw-right (list-copy list-or-false)))
         (raw-left (list def))))
    ((list-or-false . default-objs)
     (if list-or-false
         (begin
          (assume (or (null? list-or-false) (pair? list-or-false)))
          (raw-right (list-copy list-or-false)))
         (raw-left default-objs)))))

(define (maybe->generation maybe)
  (assume (maybe? maybe))
  (if (nothing? maybe)
      (eof-object)
      (begin
       (assume (singleton? (just-objs maybe))
               "maybe->generation: invalid payload")
       (car (just-objs maybe)))))

(define (either->generation either)
  (assume (either? either))
  (if (left? either)
      (eof-object)
      (begin
       (assume (singleton? (right-objs either))
               "either->generation: invalid payload")
       (car (right-objs either)))))

(define (generation->maybe obj)
  (if (eof-object? obj) nothing-obj (just obj)))

(define generation->either
  (case-lambda
    ((obj) (if (eof-object? obj) (raw-left '()) (right obj)))
    ((obj def) (if (eof-object? obj) (raw-left (list def)) (right obj)))
    ((obj . default-objs) (if (eof-object? obj) (raw-left default-objs) (right obj)))))

(define (maybe->values maybe)
  (assume (maybe? maybe))
  (if (just? maybe)
      (fast-list->values (just-objs maybe))
      (values)))

(define (values->maybe producer)
  (assume (procedure? producer))
  (call-with-values
   producer
   (case-lambda
     (() nothing-obj)
     ((x) (raw-just (list x)))
     ((x y) (raw-just (list x y)))
     (objs (raw-just objs)))))

(define (maybe->two-values maybe)
  (assume (maybe? maybe))
  (if (nothing? maybe)
      (values #f #f)
      (begin
       (assume (singleton? (just-objs maybe))
               "maybe->two-values: invalid payload")
       (values (car (just-objs maybe)) #t))))

(define (two-values->maybe producer)
  (assume (procedure? producer))
  (call-with-values
   producer
   (lambda (obj success)
     (if success (just obj) nothing-obj))))

(define (either->values either)
  (either-ref/default either))

(define values->either
  (case-lambda
    ((producer)
     (assume (procedure? producer))
     (call-with-values
      producer
      (case-lambda
        (() (raw-left '()))
        ((x) (raw-right (list x)))
        (objs (raw-right objs)))))
    ((producer def)
     (assume (procedure? producer))
     (call-with-values
      producer
      (case-lambda
        (() (raw-left (list def)))
        ((x) (raw-right (list x)))
        (objs (raw-right objs)))))
    ((producer . default-objs)
     (assume (procedure? producer))
     (call-with-values
      producer
      (case-lambda
        (() (raw-left default-objs))
        ((x) (raw-right (list x)))
        (objs (raw-right objs)))))))

(define (exception->either pred thunk)
  (assume (procedure? pred))
  (assume (procedure? thunk))
  (guard (obj ((pred obj) (left obj)))
    (call-with-values thunk right)))

;; ---------------------------------------------------------------------
;; § SRFI 189: Map, Fold, and Unfold
;; ---------------------------------------------------------------------

(define (maybe-map proc maybe)
  (assume (procedure? proc))
  (assume (maybe? maybe))
  (if (nothing? maybe)
      nothing-obj
      (call-with-values (lambda () (fast-apply proc (just-objs maybe)))
                        just)))

(define (maybe-for-each proc maybe)
  (assume (procedure? proc))
  (maybe-ref maybe (const #f) proc)
  unspecified)

(define (maybe-fold kons nil maybe)
  (assume (procedure? kons))
  (assume (maybe? maybe))
  (if (nothing? maybe)
      nil
      (let ((objs (just-objs maybe)))
        (if (singleton? objs)
            (kons (car objs) nil)
            (apply kons (append objs (list nil)))))))

(define maybe-unfold
  (case-lambda
    ((stop? mapper successor seed)
     (assume (procedure? stop?))
     (assume (procedure? mapper))
     (if (stop? seed)
         nothing-obj
         (begin
          (assume (call-with-values (lambda () (successor seed)) stop?))
          (call-with-values (lambda () (mapper seed)) just))))
    ((stop? mapper successor . seeds)
     (assume (procedure? stop?))
     (assume (procedure? mapper))
     (if (apply stop? seeds)
         nothing-obj
         (begin
          (assume (call-with-values (lambda () (apply successor seeds)) stop?))
          (call-with-values (lambda () (apply mapper seeds)) just))))))

(define (either-map proc either)
  (assume (procedure? proc))
  (assume (either? either))
  (if (left? either)
      either
      (call-with-values (lambda () (fast-apply proc (right-objs either)))
                        right)))

(define (either-for-each proc either)
  (assume (procedure? proc))
  (either-ref either (const #f) proc)
  unspecified)

(define (either-fold kons nil either)
  (assume (procedure? kons))
  (assume (either? either))
  (if (left? either)
      nil
      (let ((objs (right-objs either)))
        (if (singleton? objs)
            (kons (car objs) nil)
            (apply kons (append objs (list nil)))))))

(define either-unfold
  (case-lambda
    ((stop? mapper successor seed)
     (assume (procedure? stop?))
     (assume (procedure? mapper))
     (if (stop? seed)
         (raw-left (list seed))
         (begin
          (assume (call-with-values (lambda () (successor seed)) stop?))
          (call-with-values (lambda () (mapper seed)) right))))
    ((stop? mapper successor . seeds)
     (assume (procedure? stop?))
     (assume (procedure? mapper))
     (if (apply stop? seeds)
         (raw-left seeds)
         (begin
          (assume (call-with-values (lambda () (apply successor seeds)) stop?))
          (call-with-values (lambda () (apply mapper seeds)) right))))))

;; ---------------------------------------------------------------------
;; § SRFI 189: Trivalent Logic
;; ---------------------------------------------------------------------

(define (just->boolean maybe)
  (not (equal? (just-objs maybe) '(#f))))

(define (tri-not maybe)
  (maybe-bind maybe (lambda (x) (just (not x)))))

(define tri=?
  (case-lambda
    ((maybe) #t)
    ((m1 m2)
     (if (or (nothing? m1) (nothing? m2))
         (just #f)
         (if (eqv? (just->boolean m1) (just->boolean m2))
             (just #t)
             (just #f))))
    ((maybe . ms)
     (let ((make-pred
            (lambda (b)
              (lambda (m)
                (assume (maybe? m))
                (and (just? m) (eqv? (just->boolean m) b))))))
       (if (nothing? maybe)
           (just #f)
           (let ((tri-same? (make-pred (just->boolean maybe))))
             (if (every tri-same? ms) (just #t) (just #f))))))))

(define tri-and
  (case-lambda
    (() (just #t))
    ((m) m)
    ((m1 m2)
     (if (or (nothing? m1) (not (just->boolean m1)))
         m1
         m2))
    (maybes
     (or (find (lambda (m)
                 (assume (maybe? m))
                 (or (nothing? m) (not (just->boolean m))))
               maybes)
         (just #t)))))

(define tri-or
  (case-lambda
    (() (just #f))
    ((m) m)
    ((m1 m2)
     (if (or (nothing? m1) (just->boolean m1))
         m1
         m2))
    (maybes
     (or (find (lambda (m)
                 (assume (maybe? m))
                 (or (nothing? m) (just->boolean m)))
               maybes)
         (just #f)))))

(define tri-merge
  (case-lambda
    (() nothing-obj)
    ((m) m)
    ((m1 m2) (if (just? m1) m1 m2))
    (maybes
     (or (find just? maybes) nothing-obj))))

;; ---------------------------------------------------------------------
;; § SRFI 189: Syntax Forms
;; ---------------------------------------------------------------------

(define-syntax maybe-if
  (syntax-rules ()
    ((_ maybe-expr just-expr nothing-expr)
     (let ((mval maybe-expr))
       (unless (maybe? mval)
         (error "maybe-if: ill-typed value"))
       (if (just? mval) just-expr nothing-expr)))))

(define-syntax %guard-value
  (syntax-rules ()
    ((_ pred expr)
     (let ((val expr))
       (unless (pred val)
         (error "ill-typed value" val))
       val))))

(define-syntax maybe-and
  (syntax-rules ()
    ((_) (just unspecified))
    ((_ maybe-expr) (%guard-value maybe? maybe-expr))
    ((_ maybe-expr maybe-expr* ...)
     (let ((maybe maybe-expr))
       (cond ((just? maybe) (maybe-and maybe-expr* ...))
             ((nothing? maybe) nothing-obj)
             (else
              (error "maybe-and: ill-typed value" maybe)))))))

(define-syntax maybe-or
  (syntax-rules ()
    ((_) (nothing))
    ((_ maybe-expr) (%guard-value maybe? maybe-expr))
    ((_ maybe-expr maybe-expr* ...)
     (let ((maybe maybe-expr))
       (cond ((just? maybe) maybe)
             ((nothing? maybe) (maybe-or maybe-expr* ...))
             (else
              (error "maybe-or: ill-typed value" maybe)))))))

(define-syntax maybe-let*
  (syntax-rules ()
    ((_ () expr1 expr2 ...)
     (call-with-values (lambda () expr1 expr2 ...) just))
    ((_ ((id maybe-expr) . claws) . body)
     (let ((maybe maybe-expr))
       (cond ((and (just? maybe) (singleton? (just-objs maybe)))
              (let ((id (car (just-objs maybe))))
                (maybe-let* claws . body)))
             ((nothing? maybe) nothing-obj)
             (else (error "ill-typed value" maybe)))))
    ((_ ((maybe-expr) . claws) . body)
     (let ((maybe maybe-expr))
       (cond ((just? maybe) (maybe-let* claws . body))
             ((nothing? maybe) nothing-obj)
             (else (error "ill-typed value" maybe)))))
    ((_ (id . claws) . body)
     (cond ((just? id) (maybe-let* claws . body))
           ((nothing? id) nothing-obj)
           (else (error "ill-typed value" id))))
    ((_ . _)
     (error "ill-formed maybe-let* form"))))

(define-syntax maybe-let*-values
  (syntax-rules ()
    ((_ () expr1 expr2 ...)
     (call-with-values (lambda () expr1 expr2 ...) just))
    ((_ (((id id* ...) maybe-expr) . claws) . body)
     (maybe-bind (%guard-value maybe? maybe-expr)
                 (lambda (id id* ...)
                   (maybe-let*-values claws . body))))
    ((_ ((ids maybe-expr) . claws) . body)
     (maybe-bind (%guard-value maybe? maybe-expr)
                 (case-lambda
                   (ids (maybe-let*-values claws . body)))))
    ((_ ((maybe-expr) . claws) . body)
     (let ((maybe maybe-expr))
       (cond ((just? maybe) (maybe-let*-values claws . body))
             ((nothing? maybe) nothing-obj)
             (else (error "ill-typed value" maybe)))))
    ((_ (id . claws) . body)
     (cond ((just? id) (maybe-let*-values claws . body))
           ((nothing? id) nothing-obj)
           (else (error "ill-typed value" id))))
    ((_ . _)
     (error "ill-formed maybe-let*-values form"))))

(define-syntax either-and
  (syntax-rules ()
    ((_) (right unspecified))
    ((_ either-expr) (%guard-value either? either-expr))
    ((_ either-expr either-expr* ...)
     (let ((either either-expr))
       (cond ((right? either) (either-and either-expr* ...))
             ((left? either) either)
             (else (error "ill-typed value" either)))))))

(define-syntax either-or
  (syntax-rules ()
    ((_) (left unspecified))
    ((_ either-expr) (%guard-value either? either-expr))
    ((_ either-expr either-expr* ...)
     (let ((either either-expr))
       (cond ((right? either) either)
             ((left? either) (either-or either-expr* ...))
             (else (error "ill-typed value" either)))))))

(define-syntax either-let*
  (syntax-rules ()
    ((_ () expr1 expr2 ...)
     (call-with-values (lambda () expr1 expr2 ...) right))
    ((_ ((id either-expr) . claws) . body)
     (let ((either either-expr))
       (cond ((and (right? either) (singleton? (right-objs either)))
              (let ((id (car (right-objs either))))
                (either-let* claws . body)))
             ((left? either) either)
             (else (error "ill-typed value" either)))))
    ((_ ((either-expr) . claws) . body)
     (let ((either either-expr))
       (cond ((right? either) (either-let* claws . body))
             ((left? either) either)
             (else (error "ill-typed value" either)))))
    ((_ (id . claws) . body)
     (cond ((right? id) (either-let* claws . body))
           ((left? id) id)
           (else (error "ill-typed value" id))))
    ((_ . _)
     (error "ill-formed either-let* form"))))

(define-syntax either-let*-values
  (syntax-rules ()
    ((_ () expr1 expr2 ...)
     (call-with-values (lambda () expr1 expr2 ...) right))
    ((_ (((id id* ...) either-expr) . claws) . body)
     (either-bind (%guard-value either? either-expr)
                  (lambda (id id* ...)
                    (either-let*-values claws . body))))
    ((_ ((ids either-expr) . claws) . body)
     (either-bind (%guard-value either? either-expr)
                  (case-lambda
                    (ids (either-let*-values claws . body)))))
    ((_ ((either-expr) . claws) . body)
     (let ((either either-expr))
       (cond ((right? either) (either-let*-values claws . body))
             ((left? either) either)
             (else (error "ill-typed value" either)))))
    ((_ (id . claws) . body)
     (cond ((right? id) (either-let*-values claws . body))
           ((left? id) id)
           (else (error "ill-typed value" id))))
    ((_ . _)
     (error "ill-formed either-let*-values form"))))

(define-syntax either-guard
  (syntax-rules ()
    ((_ pred-expr expr1 expr2 ...)
     (exception->either pred-expr (lambda () expr1 expr2 ...)))))
