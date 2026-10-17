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
(define (caaar x) (safe-car (safe-car (safe-car x))))
(define (cdaar x) (safe-cdr (safe-car (safe-car x))))
(define (caadar x) (safe-car (safe-car (safe-cdr (safe-car x)))))
(define (cddar x) (safe-cdr (safe-cdr (safe-car x))))

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

(define (string-equal? s1 s2)
  (and (string? s1) (string? s2)
       (not (boolean? s1)) (not (boolean? s2))
       (= (string-length s1) (string-length s2))
       (let loop ((i 0) (len (string-length s1)))
         (if (= i len)
             #t
             (if (char=? (string-ref s1 i) (string-ref s2 i))
                 (loop (+ i 1) len)
                 #f)))))

(define (equal? a b)
  (cond
    ((eq? a b) #t)
    ((and (number? a) (number? b)) (= a b))
    ((and (string? a) (string? b)) (string-equal? a b))
    ((and (char? a) (char? b)) (char=? a b))
    ((and (pair? a) (pair? b))
     (and (equal? (car a) (car b))
          (equal? (cdr a) (cdr b))))
    (else #f)))

(define (assoc item ls)
  (cond
    ((not (pair? ls)) #f)
    ((not (pair? (car ls))) (assoc item (cdr ls)))
    ((equal? (caar ls) item) (car ls))
    (else (assoc item (cdr ls)))))

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
  (let loop ((cur ls) (acc '()))
    (if (null? cur)
        (reverse acc)
        (loop (cdr cur) (cons (f (car cur)) acc)))))

(define (for-each proc ls)
  (let loop ((cur ls))
    (if (not (null? cur))
        (begin
          (proc (car cur))
          (loop (cdr cur))))))

(define (filter pred ls)
  (let loop ((cur ls) (acc '()))
    (cond
      ((null? cur) (reverse acc))
      ((pred (car cur)) (loop (cdr cur) (cons (car cur) acc)))
      (else (loop (cdr cur) acc)))))

(define (list-ref ls n)
  (if (<= n 0)
      (car ls)
      (list-ref (cdr ls) (- n 1))))

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
    ((null? s2) s1)
    ((eq? s1 s2) '())
    ((memq (car s1) s2) (set-diff (cdr s1) s2))
    (else (cons (car s1) (set-diff (cdr s1) s2)))))

(define (set-union s1 s2)
  (cond
    ((null? s1) s2)
    ((null? s2) s1)
    ((eq? s1 s2) s1)
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
  (memq op '(read-char %read-char peek-char %peek-char eof-object flush-output-port ulisp-flush %get-rsp %get-heap-ptr %get-gc-state-ptr %get-stackmap-table)))

(define (unary-prim? op)
  (memq op '(fxadd1 fxsub1 fixnum->char char->fixnum integer->char char->integer
             integer->symbol symbol->integer
             zero? fixnum? integer? number? exact? exact-integer? inexact? real? rational? complex?
             boolean? char? null? not symbol?
             car cdr pair? procedure? string?
             write-char %write-char write-string %write-string flush-output-port ulisp-flush eof-object?
             make-string string-length
             bytevector? bytevector-length make-bytevector %make-bytevector
             vector? vector-length make-vector %make-vector
             raise %raise
             %set-heap-ptr! %ptr-tag %ptr-untag
             %to-raw %to-fixnum
             %box-fixnum %unbox-fixnum)))

(define (binop-prim? op)
  (memq op '(+ - * = < <= > >= modulo quotient / string-ref cons set-car! set-cdr! eq? eqv? char=? boolean=? symbol=?
             bytevector-u8-ref vector-ref
             %raw-load %ptr-add %ptr-tag-add bitwise-and bitwise-ior bitwise-arithmetic-shift
             %raw-add %raw-sub %raw-mul %raw-cmp)))

(define (triop-prim? op)
  (memq op '(string-set! bytevector-u8-set! vector-set! %raw-store!)))

(define (septop-prim? op)
  (memq op '(%raw-syscall)))

(define (closure-prim? op)
  (memq op '(%make-closure %closure-ref %closure-set!)))

(define (pure-prim? op)
  (memq op '(fxadd1 fxsub1 fixnum->char char->fixnum integer->char char->integer
             integer->symbol symbol->integer
             zero? fixnum? integer? number? exact? exact-integer? inexact? real? rational? complex?
             boolean? char? null? not symbol? list?
             car cdr pair? procedure? string? string-length %ptr-add %ptr-tag %ptr-untag %ptr-tag-add
             bytevector? bytevector-length vector? vector-length
             %to-raw %to-fixnum %box-fixnum %unbox-fixnum
             + - * = < <= > >= modulo quotient / eq? eqv? char=? boolean=? symbol=? cons %closure-ref
             %raw-add %raw-sub %raw-mul %raw-cmp)))

(define (const? x)
  (or (number? x)
      (boolean? x)
      (char? x)
      (null? x)
      (and (pair? x) (eq? (car x) 'quote))))

(define (atomic-expr? expr)
  (or (symbol? expr)
      (const? expr)))

(define (extract-const-val c)
  (if (and (pair? c) (eq? (car c) 'quote))
      (cadr c)
      c))

(define (val->ast-const v)
  (cond
    ((number? v) v)
    ((boolean? v) v)
    ((char? v) v)
    ((null? v) '(quote ()))
    (else (list 'quote v))))

(define (commutative-op? op)
  (memq op '(+ * = eq? eqv? char=? boolean=? symbol=?)))

(define (type-predicate-op? op)
  (memq op '(fixnum? integer? number? exact? exact-integer? inexact? real? rational? complex?
             pair? null? boolean? char? symbol? list? zero? procedure? string?)))

(define (pure-accessor-op? op)
  (memq op '(car cdr)))

(define (pure-expr? expr)
  (cond
    ((atomic-expr? expr) #t)
    ((pair? expr)
     (let ((op (car expr)))
       (case op
         ((quote) #t)
         ((lambda) #t)
         ((if) (and (pure-expr? (cadr expr))
                    (pure-expr? (caddr expr))
                    (if (null? (cdddr expr)) #t (pure-expr? (cadddr expr)))))
         ((begin)
          (let loop ((es (cdr expr)))
            (if (null? es) #t
                (and (pure-expr? (car es)) (loop (cdr es))))))
         ((let)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (and (let loop ((bs bindings))
                   (if (null? bs) #t
                       (and (pure-expr? (cadar bs)) (loop (cdr bs)))))
                 (pure-expr? body))))
         ((letrec)
          (let ((bindings (cadr expr))
                (body (caddr expr)))
            (and (let loop ((bs bindings))
                   (if (null? bs) #t
                       (and (pure-expr? (cadar bs)) (loop (cdr bs)))))
                 (pure-expr? body))))
         (else
          (and (pure-prim? op)
               (let loop ((args (cdr expr)))
                 (if (null? args) #t
                     (and (pure-expr? (car args)) (loop (cdr args))))))))))
    (else #f)))

(define (fold-const-op op args)
  (let ((nargs (length args)))
    (cond
      ;; Unary arithmetic / predicates
      ((and (= nargs 1) (const? (car args)))
       (let ((v (extract-const-val (car args))))
         (case op
           ((fxadd1) (if (number? v) (val->ast-const (+ v 1)) #f))
           ((fxsub1) (if (number? v) (val->ast-const (- v 1)) #f))
           ((zero?) (if (number? v) (val->ast-const (= v 0)) #f))
           ((not) (val->ast-const (if (eq? v #f) #t #f)))
           ((null?) (val->ast-const (null? v)))
           ((pair?) (val->ast-const (pair? v)))
           ((number? fixnum? integer? exact? exact-integer? real? rational? complex?)
            (val->ast-const (number? v)))
           ((inexact?) (val->ast-const #f))
           ((boolean?) (val->ast-const (boolean? v)))
           ((char?) (val->ast-const (char? v)))
           ((symbol?) (val->ast-const (symbol? v)))
           ((car) (if (pair? v) (val->ast-const (car v)) #f))
           ((cdr) (if (pair? v) (val->ast-const (cdr v)) #f))
           (else #f))))
      ;; Binary arithmetic / predicates
      ((and (= nargs 2) (const? (car args)) (const? (cadr args)))
       (let ((v1 (extract-const-val (car args)))
             (v2 (extract-const-val (cadr args))))
         (case op
           ((+) (if (and (number? v1) (number? v2)) (val->ast-const (+ v1 v2)) #f))
           ((-) (if (and (number? v1) (number? v2)) (val->ast-const (- v1 v2)) #f))
           ((*) (if (and (number? v1) (number? v2)) (val->ast-const (* v1 v2)) #f))
           ((quotient /)
            (if (and (number? v1) (number? v2) (not (= v2 0)))
                (val->ast-const (quotient v1 v2))
                #f))
           ((modulo)
            (if (and (number? v1) (number? v2) (not (= v2 0)))
                (val->ast-const (modulo v1 v2))
                #f))
           ((=) (if (and (number? v1) (number? v2)) (val->ast-const (= v1 v2)) #f))
           ((<) (if (and (number? v1) (number? v2)) (val->ast-const (< v1 v2)) #f))
           ((<=) (if (and (number? v1) (number? v2)) (val->ast-const (<= v1 v2)) #f))
           ((>) (if (and (number? v1) (number? v2)) (val->ast-const (> v1 v2)) #f))
           ((>=) (if (and (number? v1) (number? v2)) (val->ast-const (>= v1 v2)) #f))
           ((eq? eqv?) (val->ast-const (eq? v1 v2)))
           ((char=?) (if (and (char? v1) (char? v2)) (val->ast-const (char=? v1 v2)) #f))
           ((boolean=?) (if (and (boolean? v1) (boolean? v2)) (val->ast-const (eq? v1 v2)) #f))
           ((symbol=?) (if (and (symbol? v1) (symbol? v2)) (val->ast-const (eq? v1 v2)) #f))
           (else #f))))
      (else #f))))

;;; Symbol table for interned symbols
(define *symbol-table* (cons '() '()))
(define (reset-symbol-table!)
  (set-car! *symbol-table* '()))

(define (symbol-hash-str str)
  (let ((len (string-length str)))
    (let loop ((i 0) (h 5381))
      (if (= i len)
          (modulo h 16777213)
          (let ((c (char->integer (string-ref str i))))
            (loop (+ i 1)
                  (modulo (+ (* h 33) c) 16777213)))))))

(define (intern-symbol sym)
  (let ((entry (assq sym (car *symbol-table*))))
    (if entry
        (cadr entry)
        (let* ((str (symbol->string sym))
               (h (symbol-hash-str str))
               (id (+ (* h 256) 2)))
          (set-car! *symbol-table* (cons (list sym id str) (car *symbol-table*)))
          id))))

(define (symbol->raw-name sym)
  (let ((entry (assq sym (car *symbol-table*))))
    (if (and entry (pair? (cdr entry)) (pair? (cddr entry)))
        (caddr entry)
        (symbol->string sym))))

;;; String table for interned string literals
(define *string-counter* (cons 0 '()))
(define *strings* (cons '() '()))
(define (intern-string str)
  (let ((label (string-append ".L_str_" (number->string (car *string-counter*)))))
    (set-car! *string-counter* (+ (car *string-counter*) 1))
    (set-car! *strings* (cons (cons label str) (car *strings*)))
    label))

(define (offset->string offset)
  (if (< offset 0)
      (string-append "- " (number->string (- 0 offset)))
      (string-append "+ " (number->string offset))))

(define (align-frame-shift needed)
  (if (= (modulo needed 16) 8)
      needed
      (+ needed 8)))

(define (expr-has-arithmetic-on-var? expr var)
  (cond
    ((not (pair? expr)) #f)
    ((and (memq (car expr) '(+ - *)) (memq var (cdr expr))) #t)
    (else (or (expr-has-arithmetic-on-var? (car expr) var)
              (expr-has-arithmetic-on-var? (cdr expr) var)))))

(define (expr-has-conditional-or-pred-on-var? expr var)
  (cond
    ((not (pair? expr)) #f)
    ((and (memq (car expr) '(fixnum? integer? number? pair? boolean? null? symbol? string? char?))
          (memq var (cdr expr)))
     #t)
    ((and (eq? (car expr) 'if) (pair? (cdr expr)))
     (or (expr-has-conditional-or-pred-on-var? (cadr expr) var)
         (expr-has-conditional-or-pred-on-var? (caddr expr) var)
         (if (null? (cdddr expr)) #f (expr-has-conditional-or-pred-on-var? (cadddr expr) var))))
    (else (or (expr-has-conditional-or-pred-on-var? (car expr) var)
              (expr-has-conditional-or-pred-on-var? (cdr expr) var)))))

(define (expr-size expr)
  (cond
    ((not (pair? expr)) 1)
    (else (+ 1 (expr-size (car expr)) (expr-size (cdr expr))))))
