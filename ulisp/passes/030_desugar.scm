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

;;; =======================================================================
;;; Canonical Nanopass DSL Pass: desugar-all
;;; Transforms high-level L_src AST into canonical L_core AST
;;; =======================================================================
(define-pass desugar-all : L_src (ir) -> L_core ()
  (Expr : Expr (ir) -> Expr ()
    ;; 1. Conditionals (Pass 027)
    ((cond . ,clauses) (Expr (desugar-cond clauses)))
    ((case ,key . ,clauses) (Expr (desugar-case key clauses)))
    ((and . ,args) (Expr (desugar-and args)))
    ((or . ,args) (Expr (desugar-or args)))
    ((char<? . ,args)
     (if (or (null? args) (null? (cdr args)) (null? (cddr args)))
         (cons 'char<? (map Expr args))
         (Expr (desugar-chain-cmp 'char<? args))))
    ((char>? . ,args)
     (if (or (null? args) (null? (cdr args)) (null? (cddr args)))
         (cons 'char>? (map Expr args))
         (Expr (desugar-chain-cmp 'char>? args))))
    ((char<=? . ,args)
     (if (or (null? args) (null? (cdr args)) (null? (cddr args)))
         (cons 'char<=? (map Expr args))
         (Expr (desugar-chain-cmp 'char<=? args))))
    ((char>=? . ,args)
     (if (or (null? args) (null? (cdr args)) (null? (cddr args)))
         (cons 'char>=? (map Expr args))
         (Expr (desugar-chain-cmp 'char>=? args))))
    ((char=? . ,args)
     (if (or (null? args) (null? (cdr args)) (null? (cddr args)))
         (cons 'char=? (map Expr args))
         (Expr (desugar-chain-cmp 'char=? args))))

    ;; 2. Local Bindings (Pass 028)
    ((let* ,bindings . ,bodies) (Expr (desugar-let* bindings bodies)))
    ((let ,name ,bindings . ,bodies) (guard (symbol? name))
     (Expr (desugar-named-let (cons 'let (cons name (cons bindings bodies))))))

    ;; 3. Constructors (Pass 026)
    ((list . ,args) (Expr (desugar-list args)))
    ((string-append . ,args) (Expr (desugar-string-append args)))
    ((string-copy . ,args) (Expr (desugar-string-copy (map Expr args))))
    ((string-copy! . ,args) (Expr (desugar-string-copy! (map Expr args))))
    ((string-fill! . ,args) (Expr (desugar-string-fill! (map Expr args))))
    ((string->utf8 . ,args) (Expr (desugar-string->utf8 (map Expr args))))
    ((utf8->string . ,args) (Expr (desugar-utf8->string (map Expr args))))
    ((vector . ,args) (Expr (desugar-vector args)))
    ((vector-append . ,args) (Expr (desugar-vector-append args)))
    ((make-vector . ,args) (Expr (desugar-make-vector (map Expr args))))
    ((vector-copy . ,args) (Expr (desugar-vector-copy (map Expr args))))
    ((vector-copy! . ,args) (Expr (desugar-vector-copy! (map Expr args))))
    ((vector-fill! . ,args) (Expr (desugar-vector-fill! (map Expr args))))
    ((vector->list . ,args) (Expr (desugar-vector->list (map Expr args))))
    ((make-list . ,args) (Expr (desugar-make-list (map Expr args))))
    ((bytevector . ,args) (Expr (desugar-bytevector args)))
    ((bytevector-append . ,args) (Expr (desugar-bytevector-append args)))
    ((make-bytevector . ,args) (Expr (desugar-make-bytevector (map Expr args))))
    ((bytevector-copy . ,args) (Expr (desugar-bytevector-copy (map Expr args))))
    ((bytevector-copy! . ,args) (Expr (desugar-bytevector-copy! (map Expr args))))

    ;; 4. Dynamic & Multiple Values (Pass 029)
    ((guard ,spec . ,bodies) (Expr (desugar-guard spec bodies)))
    ((let-values ,bindings . ,bodies) (Expr (desugar-let-values bindings bodies)))
    ((let*-values ,bindings . ,bodies) (Expr (desugar-let*-values bindings bodies)))
    ((parameterize ,bindings . ,bodies) (Expr (desugar-parameterize bindings bodies)))
    ((delay . ,args) (Expr (desugar-delay (cons 'delay args))))
    ((delay-force . ,args) (Expr (desugar-delay-force (cons 'delay-force args))))
    ((make-parameter . ,args) (Expr (desugar-make-parameter (map Expr args))))
    ((values . ,args) (Expr (desugar-values (map Expr args))))
    ((%raw-call/cc ,arg) (list '%raw-call/cc (Expr arg)))
    ((call-with-values ,p1 ,p2) (list '%call-with-values (Expr p1) (Expr p2)))
    ((%call-with-values ,p1 ,p2) (list '%call-with-values (Expr p1) (Expr p2)))
    ((error . ,args) (Expr (desugar-error (cons 'error args))))
    ((%with-handler ,h ,b) (list '%with-handler (Expr h) (Expr b)))
    ((with-exception-handler ,h ,b) (list '%with-handler (Expr h) (Expr b)))

    ;; 5. List Accessor Shortcuts
    ((caar ,arg) (Expr (list 'car (list 'car arg))))
    ((cadr ,arg) (Expr (list 'car (list 'cdr arg))))
    ((cdar ,arg) (Expr (list 'cdr (list 'car arg))))
    ((cddr ,arg) (Expr (list 'cdr (list 'cdr arg))))
    ((caddr ,arg) (Expr (list 'car (list 'cdr (list 'cdr arg)))))
    ((cdddr ,arg) (Expr (list 'cdr (list 'cdr (list 'cdr arg)))))
    ((cadddr ,arg) (Expr (list 'car (list 'cdr (list 'cdr (list 'cdr arg))))))))
