;;; =======================================================================
;;; ULisp Compiler Primitives & Predicate Categorization
;;; =======================================================================

;;; Primitive procedure categorization predicates
(define (zero-arg-prim? op)
  (memq op '(read-char %read-char peek-char %peek-char eof-object flush-output-port ulisp-flush %get-rsp %get-heap-ptr %get-heap-limit-ptr %get-gc-state-ptr %get-environ-ptr %get-stackmap-table %num-args)))

(define (unary-prim? op)
  (memq op '(fxadd1 fxsub1 fixnum->char char->fixnum integer->char char->integer
             integer->symbol symbol->integer
             zero? fixnum? integer? number? exact? exact-integer? inexact? real? rational? complex?
             boolean? char? null? not symbol?
             car cdr pair? procedure? string?
             write-char %write-char write-byte write-u8 write-string %write-string flush-output-port ulisp-flush eof-object?
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
             %raw-load %raw-load-u8 %ptr-add %ptr-tag-add bitwise-and bitwise-ior bitwise-arithmetic-shift
             %raw-add %raw-sub %raw-mul %raw-cmp)))

(define (triop-prim? op)
  (memq op '(string-set! bytevector-u8-set! vector-set! %raw-store!)))

(define (septop-prim? op)
  (memq op '(%raw-syscall)))

(define (closure-prim? op)
  (memq op '(%make-closure %make-closure-env %closure-ref %closure-set!)))

(define (lir-primitive? op)
  (or (zero-arg-prim? op)
      (unary-prim? op)
      (binop-prim? op)
      (triop-prim? op)
      (septop-prim? op)
      (closure-prim? op)))

(define (pure-prim? op)
  (memq op '(fxadd1 fxsub1 fixnum->char char->fixnum integer->char char->integer
             integer->symbol symbol->integer
             zero? fixnum? integer? number? exact? exact-integer? inexact? real? rational? complex?
             boolean? char? null? not symbol? list?
             car cdr pair? procedure? string? string-length %ptr-add %ptr-tag %ptr-untag %ptr-tag-add
             bytevector? bytevector-length vector? vector-length %num-args
             %to-raw %to-fixnum %box-fixnum %unbox-fixnum
             + - * = < <= > >= modulo quotient / eq? eqv? char=? boolean=? symbol=? cons %closure-ref
             %raw-load-u8 %raw-add %raw-sub %raw-mul %raw-cmp)))

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
           ((list?) (val->ast-const (list? v)))
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
           ((boolean=?) (val->ast-const (if (and (boolean? v1) (boolean? v2)) (eq? v1 v2) #f)))
           ((symbol=?) (val->ast-const (if (and (symbol? v1) (symbol? v2)) (eq? v1 v2) #f)))
           (else #f))))
      (else #f))))

;;; -----------------------------------------------------------------------
;;; Builtin & Primitive Arity Signatures (Issue #629)
;;; -----------------------------------------------------------------------

(define (builtin-fixed-arity op)
  (cond
    ((eq? op '-) #f)
    ((zero-arg-prim? op) 0)
    ((memq op '(open-output-string)) 0)
    ((unary-prim? op) 1)
    ((binop-prim? op) 2)
    ((triop-prim? op) 3)
    ((septop-prim? op) 7)
    ((memq op '(caar cadr cdar cddr caaar caadr cadar caddr cdaar cdadr cddar cdddr
                cadddr cddddr caaaar caaadr caadar caaddr cadaar cadadr caddar cadddr
                cdaaar cdaadr cdadar cdaddr cddaar cddadr cdddar cddddr
                reverse length
                string->list list->string string->vector vector->string
                utf8->string string->utf8
                close-port close-input-port close-output-port get-output-string
                open-input-string force promise?
                abs exact-integer-sqrt
                char-alphabetic? char-numeric? char-whitespace?
                char-upper-case? char-lower-case? digit-value
                char-upcase char-downcase char-foldcase
                string-upcase string-downcase string-foldcase)) 1)
    ((memq op '(append equal? memq assq memv assv member assoc string=?
                string-append2 bytevector-append2 list-ref list-tail
                modulo floor/ floor-quotient floor-remainder
                truncate/ truncate-quotient truncate-remainder)) 2)
    (else #f)))

(define (builtin-min-arity op)
  (cond
    ((memq op '(list vector string-append string)) 0)
    ((memq op '(string<=? string>=? string<? string>?
                string-ci=? string-ci<? string-ci>? string-ci<=? string-ci>=?
                char-ci=? char-ci<? char-ci>? char-ci<=? char-ci>=?)) 1)
    ((memq op '(%with-handler map for-each apply)) 2)
    (else #f)))
