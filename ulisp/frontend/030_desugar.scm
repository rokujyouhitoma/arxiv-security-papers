;;; =======================================================================
;;; ULisp Compiler Pass 030: Core Syntax Desugaring & Normalization Pass
;;; Conforms to DSN-33 Architecture Specification & Nanopass Framework Standard
;;; Migrated to Nanopass DSL (Phase 1) per Issue #581.
;;; Eliminates manual Catamorphism recursion boilerplate for Core constructs
;;; (if, begin, lambda, let, letrec, quote, set!, %program, applications).
;;; =======================================================================

;;; Helper transformations for composite types and runtime forms
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

(define (desugar-delay expr)
  (let ((body (if (null? (cddr expr))
                  (cadr expr)
                  (cons 'begin (cdr expr)))))
    (list '%%make-promise ''lazy (list 'lambda '() (list '%%make-promise ''eager body)))))

(define (desugar-delay-force expr)
  (let ((body (if (null? (cddr expr))
                  (cadr expr)
                  (cons 'begin (cdr expr)))))
    (list '%%make-promise ''lazy (list 'lambda '() body))))

(define (desugar-make-parameter args)
  (if (null? (cdr args))
      (list 'make-parameter-1 (car args))
      (list 'make-parameter-2 (car args) (cadr args))))

(define (desugar-values args)
  (cond
    ((null? args) (list '%values))
    ((null? (cdr args)) (car args))
    (else (cons '%values args))))

(define (desugar-error expr)
  (let ((msg (cadr expr))
        (irritants (cddr expr)))
    (list 'raise (cons 'list (cons ''error-object (cons msg irritants))))))

(define (desugar-syntax-error expr)
  (let ((msg (if (and (pair? (cdr expr)) (string? (cadr expr)))
                 (cadr expr)
                 "invalid syntax"))
        (irritants (if (and (pair? (cdr expr)) (string? (cadr expr)))
                       (cddr expr)
                       (cdr expr))))
    (error (string-append "syntax-error [R7RS §4.3.1]: " msg) irritants)))

(define (desugar-assume expr)
  (let ((condition (cadr expr))
        (rest (cddr expr)))
    (let ((tmp (unique-symbol "assume_tmp_")))
      (let* ((msg (if (pair? rest) (car rest) "invalid assumption [SRFI 145]"))
             (objs (if (pair? rest) (cdr rest) '()))
             (err-call (cons 'error (cons msg (cons (list 'quote condition) objs)))))
        (list 'let (list (list tmp condition))
              (list 'if tmp
                    tmp
                    err-call))))))

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

;;; =======================================================================
;;; Canonical Nanopass DSL Pass: desugar-all
;;; Transforms high-level L_src AST into canonical L_core AST
;;; =======================================================================
(define (desugar-dispatch-dyn op args ir Expr)
  (case op
    ((guard)
     (if (pair? args)
         (Expr (desugar-guard (car args) (cdr args)))
         (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())))
    ((let-values)
     (if (pair? args)
         (Expr (desugar-let-values (car args) (cdr args)))
         (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())))
    ((let*-values)
     (if (pair? args)
         (Expr (desugar-let*-values (car args) (cdr args)))
         (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())))
    ((parameterize)
     (if (pair? args)
         (Expr (desugar-parameterize (car args) (cdr args)))
         (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())))
    ((delay) (Expr (desugar-delay (cons 'delay args))))
    ((delay-force) (Expr (desugar-delay-force (cons 'delay-force args))))
    ((make-parameter) (Expr (desugar-make-parameter (map Expr args))))
    ((values) (Expr (desugar-values (map Expr args))))
    ((%raw-call/cc)
     (if (and (pair? args) (null? (cdr args)))
         (list '%raw-call/cc (Expr (car args)))
         (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())))
    ((call-with-values %call-with-values)
     (if (and (pair? args) (pair? (cdr args)) (null? (cddr args)))
         (list '%call-with-values (Expr (car args)) (Expr (cadr args)))
         (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())))
    ((error) (Expr (desugar-error (cons 'error args))))
    ((assume) (Expr (desugar-assume (cons 'assume args))))
    ((assert) (Expr (desugar-assume (cons 'assert args))))
    ((syntax-error) (Expr (desugar-syntax-error (cons 'syntax-error args))))
    ((let-syntax letrec-syntax)
     (error "syntax-error [R7RS §4.3.1]: unexpanded let-syntax encountered in desugar" args))
    ((%with-handler with-exception-handler)
     (if (and (pair? args) (pair? (cdr args)) (null? (cddr args)))
         (list '%with-handler (Expr (car args)) (Expr (cadr args)))
         (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())))
    ((caar cadr cdar cddr caddr cdddr cadddr)
     (if (and (pair? args) (null? (cdr args)))
         (let ((arg (car args)))
           (case op
             ((caar) (Expr (list 'car (list 'car arg))))
             ((cadr) (Expr (list 'car (list 'cdr arg))))
             ((cdar) (Expr (list 'cdr (list 'car arg))))
             ((cddr) (Expr (list 'cdr (list 'cdr arg))))
             ((caddr) (Expr (list 'car (list 'cdr (list 'cdr arg)))))
             ((cdddr) (Expr (list 'cdr (list 'cdr (list 'cdr arg)))))
             ((cadddr) (Expr (list 'car (list 'cdr (list 'cdr (list 'cdr arg))))))
             (else (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '()))))
         (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())))
    (else
     (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '()))))

(define (desugar-dispatch-ctors op args ir Expr)
  (case op
    ((list) (Expr (desugar-list args)))
    ((string-append) (Expr (desugar-string-append args)))
    ((string-copy) (Expr (desugar-string-copy (map Expr args))))
    ((string-copy!) (Expr (desugar-string-copy! (map Expr args))))
    ((string-fill!) (Expr (desugar-string-fill! (map Expr args))))
    ((string->utf8) (Expr (desugar-string->utf8 (map Expr args))))
    ((utf8->string) (Expr (desugar-utf8->string (map Expr args))))
    ((string->list) (Expr (desugar-string->list (map Expr args))))
    ((string->vector) (Expr (desugar-string->vector (map Expr args))))
    ((vector) (Expr (desugar-vector args)))
    ((vector-append) (Expr (desugar-vector-append args)))
    ((make-vector) (Expr (desugar-make-vector (map Expr args))))
    ((vector-copy) (Expr (desugar-vector-copy (map Expr args))))
    ((vector-copy!) (Expr (desugar-vector-copy! (map Expr args))))
    ((vector-fill!) (Expr (desugar-vector-fill! (map Expr args))))
    ((vector->list) (Expr (desugar-vector->list (map Expr args))))
    ((vector->string) (Expr (desugar-vector->string (map Expr args))))
    ((make-list) (Expr (desugar-make-list (map Expr args))))
    ((bytevector) (Expr (desugar-bytevector args)))
    ((bytevector-append) (Expr (desugar-bytevector-append args)))
    ((make-bytevector) (Expr (desugar-make-bytevector (map Expr args))))
    ((bytevector-copy) (Expr (desugar-bytevector-copy (map Expr args))))
    ((bytevector-copy!) (Expr (desugar-bytevector-copy! (map Expr args))))
    ((gcd) (Expr (desugar-gcd (map Expr args))))
    ((lcm) (Expr (desugar-lcm (map Expr args))))
    ((max) (Expr (desugar-max (map Expr args))))
    ((min) (Expr (desugar-min (map Expr args))))
    ((format) (Expr (desugar-format (map Expr args))))
    (else (desugar-dispatch-dyn op args ir Expr))))

(define (desugar-dispatch-bindings op args ir Expr)
  (case op
    ((case-lambda) (Expr (desugar-case-lambda args)))
    ((let*)
     (if (pair? args)
         (Expr (desugar-let* (car args) (cdr args)))
         (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())))
    ((letrec*)
     (if (and (pair? args) (list? (car args)))
         (Expr (desugar-letrec* (car args) (cdr args)))
         (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())))
    ((let)
     (cond
       ((and (pair? args) (symbol? (car args)) (pair? (cdr args)))
        (Expr (desugar-named-let ir)))
       ((and (pair? args) (list? (car args)))
        (let ((bindings (car args))
              (bodies (cdr args)))
          (cond
            ((null? bodies)
             (Expr (list 'let bindings '(begin))))
            ((pair? (cdr bodies))
             (Expr (list 'let bindings (cons 'begin bodies))))
            (else
             (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())))))
       (else
        (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '()))))
    ((letrec)
     (if (and (pair? args) (list? (car args)))
         (let ((bindings (car args))
               (bodies (cdr args)))
           (cond
             ((null? bodies)
              (Expr (list 'letrec bindings '(begin))))
             ((pair? (cdr bodies))
              (Expr (list 'letrec bindings (cons 'begin bodies))))
             (else
              (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '()))))
         (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())))
    ((lambda)
     (if (pair? args)
         (let ((params (car args))
               (bodies (cdr args)))
           (cond
             ((null? bodies)
              (Expr (list 'lambda params '(begin))))
             ((pair? (cdr bodies))
              (Expr (list 'lambda params (cons 'begin bodies))))
             (else
              (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '()))))
         (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())))
    ((do)
     (if (and (pair? args) (pair? (cdr args)))
         (Expr (desugar-do (car args) (cadr args) (cddr args)))
         (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())))
    ((begin)
     (if (and (pair? args) (pair? (car args)))
         (let ((first (car args))
               (rest (cdr args)))
           (cond
             ((eq? (car first) 'begin)
              (Expr (cons 'begin (append (cdr first) rest))))
             ((and (eq? (car first) 'define) (pair? (cdr first)))
              (Expr (desugar-internal-define (cadr first) (cddr first) rest)))
             ((and (eq? (car first) 'define-values)
                   (pair? (cdr first))
                   (pair? (cddr first))
                   (null? (cdddr first)))
              (Expr (desugar-define-values (cadr first) (caddr first) rest)))
             (else
              (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '()))))
         (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())))
    ((define)
     (if (pair? args)
         (Expr (desugar-internal-define (car args) (cdr args) '()))
         (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())))
    ((define-values)
     (if (and (pair? args) (pair? (cdr args)) (null? (cddr args)))
         (Expr (desugar-define-values (car args) (cadr args) '()))
         (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())))
    (else (desugar-dispatch-ctors op args ir Expr))))

(define (desugar-dispatch-expr ir Expr)
  (if (not (pair? ir))
      (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())
      (let ((op (car ir))
            (args (cdr ir)))
        (case op
          ((%program)
           (if (and (pair? args) (pair? (cdr args)))
               (let ((defs (car args))
                     (bodies (cdr args))
                     (map-def (lambda (d)
                                (if (and (pair? d) (eq? (car d) 'define))
                                    (cons 'define (cons (cadr d) (map Expr (cddr d))))
                                    (Expr d)))))
                 (if (null? (cdr bodies))
                     (list '%program (map map-def defs) (Expr (car bodies)))
                     (list '%program (map map-def defs) (map Expr bodies))))
               (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())))
          ((cond-expand) (Expr (desugar-cond-expand args)))
          ((cond) (Expr (desugar-cond args)))
          ((case)
           (if (pair? args)
               (Expr (desugar-case (car args) (cdr args)))
               (nanopass-catamorphism-step 'L_src 'L_core 'Expr ir Expr '() '())))
          ((and) (Expr (desugar-and args)))
          ((or) (Expr (desugar-or args)))
          ((char<? char>? char<=? char>=? char=?
            string<? string>? string<=? string>=? string=?
            char-ci<? char-ci>? char-ci<=? char-ci>=? char-ci=?
            string-ci<? string-ci>? string-ci<=? string-ci>=? string-ci=?)
           (if (or (null? args) (null? (cdr args)) (null? (cddr args)))
               (cons op (map Expr args))
               (Expr (desugar-chain-cmp op args))))
          (else (desugar-dispatch-bindings op args ir Expr))))))

(define-pass desugar-all : L_src (ir) -> L_core ()
  (Expr : Expr (ir) -> Expr ()
    (,e (desugar-dispatch-expr e Expr))))
