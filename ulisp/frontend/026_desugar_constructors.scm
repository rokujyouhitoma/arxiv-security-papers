;;; =======================================================================
;;; ULisp Compiler Pass 026: Constructor Desugaring Pass
;;; Conforms to DSN-33 Architecture Specification & Nanopass Standard
;;; Desugars composite literal constructors (list, vector, bytevector,
;;; string operations, math variadics, format, CxR accessors)
;;; Refactored to define-picopass + fuse-rules per Issue #762 (DSN-33-01 T4.1)
;;; =======================================================================

(define (desugar-list args)
  (if (null? args)
      ''()
      (cons 'cons (cons (car args) (cons (desugar-list (cdr args)) '())))))

(define (desugar-string args)
  (let* ((len (length args))
         (str-sym (unique-symbol "str_")))
    (let loop ((rest args) (idx 0) (sets '()))
      (if (null? rest)
          (list 'let (list (list str-sym (list 'make-string len)))
                (cons 'begin (reverse (cons str-sym sets))))
          (loop (cdr rest)
                (+ idx 1)
                (cons (list 'string-set! str-sym idx (car rest)) sets))))))

(define (desugar-string-append args)
  (cond
    ((null? args) "")
    ((null? (cdr args)) (car args))
    ((null? (cddr args)) (list (string->symbol "string-append2") (car args) (cadr args)))
    (else
     ;; Split args into two halves to keep tree depth O(log N)
     (let* ((len (length args))
            (half (quotient len 2)))
       (let loop ((rest args) (i 0) (left '()))
         (if (< i half)
             (loop (cdr rest) (+ i 1) (cons (car rest) left))
             (list (string->symbol "string-append2")
                   (desugar-string-append (reverse left))
                   (desugar-string-append rest))))))))

(define (desugar-string-copy args)
  (cond
    ((null? (cdr args))
     (let ((s-sym (unique-symbol "s_")))
       (list 'let (list (list s-sym (car args)))
             (list 'string-copy-range s-sym 0 (list 'string-length s-sym)))))
    ((null? (cddr args))
     (let ((s-sym (unique-symbol "s_")))
       (list 'let (list (list s-sym (car args)))
             (list 'string-copy-range s-sym (cadr args) (list 'string-length s-sym)))))
    (else
     (cons 'string-copy-range args))))

(define (desugar-string-copy! args)
  (if (null? (cdddr args))
      (let ((from-sym (unique-symbol "from_")))
        (list 'let (list (list from-sym (caddr args)))
              (list 'string-copy-range! (car args) (cadr args)
                    from-sym 0 (list 'string-length from-sym))))
      (cons 'string-copy-range! args)))

(define (desugar-string-fill! args)
  (cond
    ((null? (cddr args))
     (let ((s-sym (unique-symbol "s_")))
       (list 'let (list (list s-sym (car args)))
             (list 'string-fill-range! s-sym (cadr args) 0 (list 'string-length s-sym)))))
    ((null? (cdddr args))
     (let ((s-sym (unique-symbol "s_")))
       (list 'let (list (list s-sym (car args)))
             (list 'string-fill-range! s-sym (cadr args) (caddr args) (list 'string-length s-sym)))))
    (else
     (cons 'string-fill-range! args))))

(define (desugar-string->utf8 args)
  (if (null? (cdr args))
      (let ((str-sym (unique-symbol "str_")))
        (list 'let (list (list str-sym (car args)))
              (list 'string->utf8-range str-sym 0 (list 'string-length str-sym))))
      (cons 'string->utf8-range args)))

(define (desugar-utf8->string args)
  (if (null? (cdr args))
      (let ((bv-sym (unique-symbol "bv_")))
        (list 'let (list (list bv-sym (car args)))
              (list 'utf8->string-range bv-sym 0 (list 'bytevector-length bv-sym))))
      (cons 'utf8->string-range args)))

(define (desugar-string->list args)
  (cond
    ((null? (cdr args))
     (let ((s-sym (unique-symbol "str_")))
       (list 'let (list (list s-sym (car args)))
             (list 'string->list-range s-sym 0 (list 'string-length s-sym)))))
    ((null? (cddr args))
     (let ((s-sym (unique-symbol "str_")))
       (list 'let (list (list s-sym (car args)))
             (list 'string->list-range s-sym (cadr args) (list 'string-length s-sym)))))
    (else
     (cons 'string->list-range args))))

(define (desugar-string->vector args)
  (cond
    ((null? (cdr args))
     (let ((s-sym (unique-symbol "str_")))
       (list 'let (list (list s-sym (car args)))
             (list 'string->vector-range s-sym 0 (list 'string-length s-sym)))))
    ((null? (cddr args))
     (let ((s-sym (unique-symbol "str_")))
       (list 'let (list (list s-sym (car args)))
             (list 'string->vector-range s-sym (cadr args) (list 'string-length s-sym)))))
    (else
     (cons 'string->vector-range args))))

(define (desugar-bytevector args)
  (let* ((len (length args))
         (bv-sym (unique-symbol "bv_")))
    (let loop ((rest args) (idx 0) (sets '()))
      (if (null? rest)
          (list 'let (list (list bv-sym (list '%make-bytevector len)))
                (cons 'begin (reverse (cons bv-sym sets))))
          (loop (cdr rest)
                (+ idx 1)
                (cons (list 'bytevector-u8-set! bv-sym idx (car rest)) sets))))))

(define (desugar-bytevector-append args)
  (cond
    ((null? args) (list '%make-bytevector 0))
    ((null? (cdr args)) (car args))
    ((null? (cddr args)) (list (string->symbol "bytevector-append2") (car args) (cadr args)))
    (else
     (let* ((len (length args))
            (half (quotient len 2)))
       (let loop ((rest args) (i 0) (left '()))
         (if (< i half)
             (loop (cdr rest) (+ i 1) (cons (car rest) left))
             (list (string->symbol "bytevector-append2")
                   (desugar-bytevector-append (reverse left))
                   (desugar-bytevector-append rest))))))))

(define (desugar-make-bytevector args)
  (if (null? (cdr args))
      (list '%make-bytevector (car args))
      (list 'make-bytevector-fill (car args) (cadr args))))

(define (desugar-bytevector-copy args)
  (cond
    ((null? (cdr args))
     (let ((bv-sym (unique-symbol "bv_")))
       (list 'let (list (list bv-sym (car args)))
             (list 'bytevector-copy-range bv-sym 0 (list 'bytevector-length bv-sym)))))
    ((null? (cddr args))
     (let ((bv-sym (unique-symbol "bv_")))
       (list 'let (list (list bv-sym (car args)))
             (list 'bytevector-copy-range bv-sym (cadr args) (list 'bytevector-length bv-sym)))))
    (else
     (cons 'bytevector-copy-range args))))

(define (desugar-bytevector-copy! args)
  (if (null? (cdddr args))
      (let ((from-sym (unique-symbol "from_")))
        (list 'let (list (list from-sym (caddr args)))
              (list 'bytevector-copy-range! (car args) (cadr args)
                    from-sym 0 (list 'bytevector-length from-sym))))
      (cons 'bytevector-copy-range! args)))

(define (desugar-vector args)
  (let* ((len (length args))
         (vec-sym (unique-symbol "vec_")))
    (let loop ((rest args) (idx 0) (sets '()))
      (if (null? rest)
          (list 'let (list (list vec-sym (list '%make-vector len)))
                (cons 'begin (reverse (cons vec-sym sets))))
          (loop (cdr rest)
                (+ idx 1)
                (cons (list 'vector-set! vec-sym idx (car rest)) sets))))))

(define (desugar-vector-append args)
  (cond
    ((null? args) (list '%make-vector 0))
    ((null? (cdr args)) (car args))
    ((null? (cddr args)) (list (string->symbol "vector-append2") (car args) (cadr args)))
    (else
     (let* ((len (length args))
            (half (quotient len 2)))
       (let loop ((rest args) (i 0) (left '()))
         (if (< i half)
             (loop (cdr rest) (+ i 1) (cons (car rest) left))
             (list (string->symbol "vector-append2")
                   (desugar-vector-append (reverse left))
                   (desugar-vector-append rest))))))))

(define (desugar-make-vector args)
  (if (null? (cdr args))
      (list '%make-vector (car args))
      (list 'make-vector-fill (car args) (cadr args))))

(define (desugar-vector-copy args)
  (cond
    ((null? (cdr args))
     (let ((v-sym (unique-symbol "v_")))
       (list 'let (list (list v-sym (car args)))
             (list 'vector-copy-range v-sym 0 (list 'vector-length v-sym)))))
    ((null? (cddr args))
     (let ((v-sym (unique-symbol "v_")))
       (list 'let (list (list v-sym (car args)))
             (list 'vector-copy-range v-sym (cadr args) (list 'vector-length v-sym)))))
    (else
     (cons 'vector-copy-range args))))

(define (desugar-vector-copy! args)
  (if (null? (cdddr args))
      (let ((from-sym (unique-symbol "from_")))
        (list 'let (list (list from-sym (caddr args)))
              (list 'vector-copy-range! (car args) (cadr args)
                    from-sym 0 (list 'vector-length from-sym))))
      (cons 'vector-copy-range! args)))

(define (desugar-vector-fill! args)
  (cond
    ((null? (cddr args))
     (let ((v-sym (unique-symbol "v_")))
       (list 'let (list (list v-sym (car args)))
             (list 'vector-fill-range! v-sym (cadr args) 0 (list 'vector-length v-sym)))))
    ((null? (cdddr args))
     (let ((v-sym (unique-symbol "v_")))
       (list 'let (list (list v-sym (car args)))
             (list 'vector-fill-range! v-sym (cadr args) (caddr args) (list 'vector-length v-sym)))))
    (else
     (cons 'vector-fill-range! args))))

(define (desugar-vector->list args)
  (cond
    ((null? (cdr args))
     (let ((v-sym (unique-symbol "v_")))
       (list 'let (list (list v-sym (car args)))
             (list 'vector->list-range v-sym 0 (list 'vector-length v-sym)))))
    ((null? (cddr args))
     (let ((v-sym (unique-symbol "v_")))
       (list 'let (list (list v-sym (car args)))
             (list 'vector->list-range v-sym (cadr args) (list 'vector-length v-sym)))))
    (else
     (cons 'vector->list-range args))))

(define (desugar-vector->string args)
  (cond
    ((null? (cdr args))
     (let ((v-sym (unique-symbol "v_")))
       (list 'let (list (list v-sym (car args)))
             (list 'vector->string-range v-sym 0 (list 'vector-length v-sym)))))
    ((null? (cddr args))
     (let ((v-sym (unique-symbol "v_")))
       (list 'let (list (list v-sym (car args)))
             (list 'vector->string-range v-sym (cadr args) (list 'vector-length v-sym)))))
    (else
     (cons 'vector->string-range args))))

(define (desugar-make-list args)
  (if (null? (cdr args))
      (list 'make-list-fill (car args) #f)
      (list 'make-list-fill (car args) (cadr args))))

(define (desugar-gcd args)
  (cond
    ((null? args) 0)
    ((null? (cdr args)) (list '%math-abs (car args)))
    ((null? (cddr args)) (list 'gcd-2 (car args) (cadr args)))
    (else
     (let loop ((curr (list 'gcd-2 (car args) (cadr args)))
                (rest (cddr args)))
       (if (null? rest)
           curr
           (loop (list 'gcd-2 curr (car rest)) (cdr rest)))))))

(define (desugar-lcm args)
  (cond
    ((null? args) 1)
    ((null? (cdr args)) (list '%math-abs (car args)))
    ((null? (cddr args)) (list 'lcm-2 (car args) (cadr args)))
    (else
     (let loop ((curr (list 'lcm-2 (car args) (cadr args)))
                (rest (cddr args)))
       (if (null? rest)
           curr
           (loop (list 'lcm-2 curr (car rest)) (cdr rest)))))))

(define (desugar-max args)
  (cond
    ((null? args) (error "max [R7RS §6.2.6]: requires at least one argument"))
    ((null? (cdr args)) (car args))
    ((null? (cddr args)) (list 'max-2 (car args) (cadr args)))
    (else
     (let loop ((curr (list 'max-2 (car args) (cadr args)))
                (rest (cddr args)))
       (if (null? rest)
           curr
           (loop (list 'max-2 curr (car rest)) (cdr rest)))))))

(define (desugar-min args)
  (cond
    ((null? args) (error "min [R7RS §6.2.6]: requires at least one argument"))
    ((null? (cdr args)) (car args))
    ((null? (cddr args)) (list 'min-2 (car args) (cadr args)))
    (else
     (let loop ((curr (list 'min-2 (car args) (cadr args)))
                (rest (cddr args)))
       (if (null? rest)
           curr
           (loop (list 'min-2 curr (car rest)) (cdr rest)))))))

(define (desugar-format args)
  (if (null? args)
      (error "format [SRFI 28]: too few arguments (requires format-string)")
      (list '%format (car args) (cons 'list (cdr args)))))

;;; -----------------------------------------------------------------------
;;; Pass 026 Picopass Rule Definitions (DSN-33-01 T4.1)
;;; -----------------------------------------------------------------------

(define-picopass rule-desugar-list
  (Expr
    ((list . ,args) (desugar-list args))))

(define-picopass rule-desugar-vector
  (Expr
    ((vector . ,args) (desugar-vector args))
    ((vector-append . ,args) (desugar-vector-append args))
    ((make-vector . ,args) (desugar-make-vector args))))

(define-picopass rule-desugar-bytevector
  (Expr
    ((bytevector . ,args) (desugar-bytevector args))
    ((bytevector-append . ,args) (desugar-bytevector-append args))
    ((make-bytevector . ,args) (desugar-make-bytevector args))))

(define-picopass rule-desugar-string-ops
  (Expr
    ((string . ,args) (desugar-string args))
    ((string-append . ,args) (desugar-string-append args))
    ((string-copy . ,args) (desugar-string-copy args))
    ((string-copy! . ,args) (desugar-string-copy! args))
    ((string-fill! . ,args) (desugar-string-fill! args))
    ((string->utf8 . ,args) (desugar-string->utf8 args))
    ((utf8->string . ,args) (desugar-utf8->string args))
    ((string->list . ,args) (desugar-string->list args))
    ((string->vector . ,args) (desugar-string->vector args))))

(define-picopass rule-desugar-vector-ops
  (Expr
    ((vector-copy . ,args) (desugar-vector-copy args))
    ((vector-copy! . ,args) (desugar-vector-copy! args))
    ((vector-fill! . ,args) (desugar-vector-fill! args))
    ((vector->list . ,args) (desugar-vector->list args))
    ((vector->string . ,args) (desugar-vector->string args))
    ((make-list . ,args) (desugar-make-list args))))

(define-picopass rule-desugar-bytevector-ops
  (Expr
    ((bytevector-copy . ,args) (desugar-bytevector-copy args))
    ((bytevector-copy! . ,args) (desugar-bytevector-copy! args))))

(define-picopass rule-desugar-math-variadic
  (Expr
    ((gcd . ,args) (desugar-gcd args))
    ((lcm . ,args) (desugar-lcm args))
    ((max . ,args) (desugar-max args))
    ((min . ,args) (desugar-min args))))

(define-picopass rule-desugar-format
  (Expr
    ((format . ,args) (desugar-format args))))

(define-picopass rule-desugar-cxr
  (Expr
    ((caar ,x) (list 'car (list 'car x)))
    ((cadr ,x) (list 'car (list 'cdr x)))
    ((cdar ,x) (list 'cdr (list 'car x)))
    ((cddr ,x) (list 'cdr (list 'cdr x)))
    ((caddr ,x) (list 'car (list 'cdr (list 'cdr x))))
    ((cdddr ,x) (list 'cdr (list 'cdr (list 'cdr x))))
    ((cadddr ,x) (list 'car (list 'cdr (list 'cdr (list 'cdr x)))))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass Definition: Desugar Constructors (fuse-rules)
;;; -----------------------------------------------------------------------
(define-pass desugar-constructors : L_src (ir) -> L_core ()
  (fuse-rules
    rule-desugar-list
    rule-desugar-vector
    rule-desugar-bytevector
    rule-desugar-string-ops
    rule-desugar-vector-ops
    rule-desugar-bytevector-ops
    rule-desugar-math-variadic
    rule-desugar-format
    rule-desugar-cxr))
