;;; =======================================================================
;;; ULisp Compiler Pass 026: Constructor Desugaring Pass
;;; Conforms to DSN-33 Architecture Specification & Nanopass Standard
;;; Desugars composite literal constructors (list, vector, bytevector, string-append)
;;; =======================================================================

(define (desugar-list args)
  (if (null? args)
      ''()
      (cons 'cons (cons (car args) (cons (desugar-list (cdr args)) '())))))

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

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass Definition: Desugar Constructors
;;; -----------------------------------------------------------------------
(define-pass desugar-constructors : L_src (ir) -> L_core ()
  (Expr : Expr (ir) -> Expr ()
    ((list . ,args) (desugar-list (map Expr args)))
    ((string-append . ,args) (desugar-string-append (map Expr args)))
    ((vector . ,args) (desugar-vector (map Expr args)))
    ((vector-append . ,args) (desugar-vector-append (map Expr args)))
    ((bytevector . ,args) (desugar-bytevector (map Expr args)))
    ((bytevector-append . ,args) (desugar-bytevector-append (map Expr args)))))
