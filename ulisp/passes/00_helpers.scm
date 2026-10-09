;;; =======================================================================
;;; ULisp Compiler Pass 0: Common Helpers & Primitive Predicates
;;; Conforms to DSN-33 Architecture Specification
;;; =======================================================================

;;; Standard Helper Procedures (Self-hosting primitives)
(define (fixnum->char n) (integer->char n))
(define (char->fixnum c) (char->integer c))
(define (safe-car x) (if (pair? x) (car x) '()))
(define (safe-cdr x) (if (pair? x) (cdr x) '()))

(define (car* x) (car x))
(define (cadr x) (safe-car (safe-cdr x)))
(define (cddr x) (safe-cdr (safe-cdr x)))
(define (cdar x) (safe-cdr (safe-car x)))
(define (caar x) (safe-car (safe-car x)))
(define (caddr x) (safe-car (safe-cdr (safe-cdr x))))
(define (cdddr x) (safe-cdr (safe-cdr (safe-cdr x))))
(define (cadar x) (safe-car (safe-cdr (safe-car x))))
(define (cadddr x) (safe-car (safe-cdr (safe-cdr (safe-cdr x)))))

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

(define (append l1 l2)
  (if (null? l1)
      l2
      (cons (car l1) (append (cdr l1) l2))))

(define (map f ls)
  (if (null? ls)
      '()
      (cons (f (car ls)) (map f (cdr ls)))))

(define (for-each proc ls)
  (if (not (null? ls))
      (begin
        (proc (car ls))
        (for-each proc (cdr ls)))))

(define (filter pred ls)
  (cond
    ((null? ls) '())
    ((pred (car ls)) (cons (car ls) (filter pred (cdr ls))))
    (else (filter pred (cdr ls)))))

(define (error msg val)
  (display msg)
  (display " ")
  (display val)
  (newline)
  val)

;;; Deterministic symbol counter for unique variable generation
(define *symbol-counter* (cons 0 '()))
(define (unique-symbol prefix)
  (let ((s (string->symbol (string-append prefix (number->string (car *symbol-counter*))))))
    (set-car! *symbol-counter* (+ (car *symbol-counter*) 1))
    s))

;;; Deterministic label counter for assembly and lifted function labels
(define *label-counter* (cons 0 '()))
(define (unique-label prefix)
  (let ((l (string-append "." prefix "_" (number->string (car *label-counter*)))))
    (set-car! *label-counter* (+ (car *label-counter*) 1))
    l))
(define (unique-label-sym prefix)
  (string->symbol (unique-label prefix)))

;;; Set operations for variable scope analysis
(define (set-diff s1 s2)
  (cond
    ((null? s1) '())
    ((memq (car s1) s2) (set-diff (cdr s1) s2))
    (else (cons (car s1) (set-diff (cdr s1) s2)))))

(define (set-union s1 s2)
  (cond
    ((null? s1) s2)
    ((memq (car s1) s2) (set-union (cdr s1) s2))
    (else (cons (car s1) (set-union (cdr s1) s2)))))

(define (has-symbol? datum)
  (cond
    ((symbol? datum) #t)
    ((pair? datum)
     (or (has-symbol? (car datum))
         (has-symbol? (cdr datum))))
    (else #f)))

;;; Primitive procedure categorization predicates
(define (zero-arg-prim? op)
  (memq op '(read-char peek-char)))

(define (unary-prim? op)
  (memq op '(fxadd1 fxsub1 fixnum->char char->fixnum integer->char char->integer
             integer->symbol symbol->integer
             zero? fixnum? integer? number? boolean? char? null? not symbol?
             car cdr pair? procedure? string?
             write-char eof-object?
             make-string string-length)))

(define (binop-prim? op)
  (memq op '(+ - * = < <= > >= modulo quotient / string-ref cons set-car! set-cdr! eq? char=? %closure-ref)))

(define (triop-prim? op)
  (memq op '(string-set! %closure-set!)))

(define (closure-prim? op)
  (memq op '(%make-closure %closure-ref %closure-set!)))

(define (pure-prim? op)
  (memq op '(fxadd1 fxsub1 fixnum->char char->fixnum integer->char char->integer
             integer->symbol symbol->integer
             zero? fixnum? integer? number? boolean? char? null? not symbol?
             car cdr pair? procedure? string? string-length
             + - * = < <= > >= modulo quotient / eq? char=? %closure-ref)))

(define (const? x)
  (or (number? x)
      (boolean? x)
      (char? x)
      (null? x)
      (and (pair? x) (eq? (car x) 'quote))))

(define (atomic-expr? expr)
  (or (symbol? expr)
      (const? expr)))
