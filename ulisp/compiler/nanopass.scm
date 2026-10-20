;;; =======================================================================
;;; ULisp Compiler: Nanopass Framework Core DSL (define-language / define-pass)
;;; Conforms to DSN-33 Architecture Specification & Keep & Dybvig (2013)
;;; =======================================================================

;;; Helper to parse header of define-pass
;;; (define-pass pass-name : L_in (ir) -> L_out () body ...)
;;; or (define-pass pass-name (ir) body ...)
(define (nanopass-parse-pass-header form)
  (let ((name (cadr form))
        (rest (cddr form)))
    (if (and (pair? rest) (eq? (car rest) ':))
        (let* ((l-in (cadr rest))
               (var (car (caddr rest)))
               (after-arrow (cddddr rest))
               (l-out (car after-arrow))
               (opts (cadr after-arrow))
               (clauses (cddr after-arrow)))
          (list name l-in var l-out clauses))
        (list name 'L_src (car (car rest)) 'L_core (cdr rest)))))

;;; Expand a single rule in a nonterminal transformer
(define (nanopass-expand-rule rule nt-name)
  (let* ((pat (car rule))
         (rest (cdr rule))
         (has-guard? (and (pair? rest)
                          (pair? (car rest))
                          (eq? (car (car rest)) 'guard)))
         (guard-expr (if has-guard? (cadr (car rest)) #t))
         (body-expr (if has-guard?
                        (if (null? (cddr rest)) (cadr rest) (cons 'begin (cdr rest)))
                        (if (null? (cdr rest)) (car rest) (cons 'begin rest))))
         (vars (nanopass-extract-pattern-vars pat)))
    (list pat vars guard-expr body-expr)))

;;; Build cascaded if-expression for nonterminal transformer rules
(define (nanopass-build-rules-cascade rules l-in l-out nt-name var-name)
  (let loop ((rs rules))
    (if (null? rs)
        (list 'nanopass-catamorphism-step
              (list 'quote l-in)
              (list 'quote l-out)
              (list 'quote nt-name)
              var-name
              nt-name)
        (let* ((r (car rs))
               (pat (car r))
               (vars (cadr r))
               (guard-expr (caddr r))
               (body-expr (cadddr r))
               (c-var (unique-symbol "__c_")))
          (list 'let (list (list c-var
                                 (list 'nanopass-try-clause
                                       (list 'quote pat)
                                       (list 'quote vars)
                                       var-name
                                       nt-name
                                       (list 'lambda vars
                                             (list 'if guard-expr
                                                   (list 'cons #t body-expr)
                                                   #f)))))
                (list 'if c-var
                      (list 'cdr c-var)
                      (loop (cdr rs))))))))

;;; Normalize rules whether passed as list of rules or single wrapped list
(define (nanopass-normalize-rules raw-rules)
  (if (and (= (length raw-rules) 1)
           (pair? (car raw-rules))
           (pair? (caar raw-rules)))
      (car raw-rules)
      raw-rules))

;;; Parse a nonterminal clause in define-pass
(define (nanopass-parse-nt-clause clause)
  (let ((nt-name (car clause))
        (rest (cdr clause)))
    (if (and (pair? rest) (eq? (car rest) ':))
        ;; (NT : NT_in (ir) -> NT_out () rules ...)
        (let* ((ir-var (car (caddr rest)))
               (after-arrow (cddddr rest))
               (rules (nanopass-normalize-rules (cddr after-arrow))))
          (list nt-name ir-var rules))
        ;; Shorthand: (NT (ir) rules ...)
        (let ((ir-var (car (car rest)))
              (rules (nanopass-normalize-rules (cdr rest))))
          (list nt-name ir-var rules)))))

;;; Expand define-pass AST
(define (nanopass-expand-define-pass form)
  (let* ((parsed (nanopass-parse-pass-header form))
         (name (car parsed))
         (l-in (cadr parsed))
         (input-var (caddr parsed))
         (l-out (cadddr parsed))
         (clauses (car (cddddr parsed))))
    (let loop ((rest clauses)
               (defs '())
               (nt-procs '())
               (entry-nt #f))
      (if (null? rest)
          (let ((final-entry (if entry-nt entry-nt 'Expr)))
            (list 'define (list name input-var)
                  (list 'letrec
                        (append (reverse defs) (reverse nt-procs))
                        (list final-entry input-var))))
          (let ((c (car rest)))
            (cond
              ;; (definitions def1 def2 ...)
              ((and (pair? c) (eq? (car c) 'definitions))
               (loop (cdr rest) (append (reverse (cdr c)) defs) nt-procs entry-nt))
              ;; (NT : NT_in (ir) -> NT_out () rules ...)
              ;; or (NT (ir) rules ...)
              ((and (pair? c) (symbol? (car c)))
               (let* ((parsed-nt (nanopass-parse-nt-clause c))
                      (nt-name (car parsed-nt))
                      (ir-var (cadr parsed-nt))
                      (raw-rules (caddr parsed-nt))
                      (expanded-rules (map (lambda (r) (nanopass-expand-rule r nt-name)) raw-rules))
                      (body-expr (nanopass-build-rules-cascade expanded-rules l-in l-out nt-name ir-var))
                      (proc-binding (list nt-name (list 'lambda (list ir-var) body-expr))))
                 (loop (cdr rest)
                       defs
                       (cons proc-binding nt-procs)
                       (if entry-nt entry-nt nt-name))))
              (else
               (loop (cdr rest) defs nt-procs entry-nt))))))))

;;; Expand define-language AST
(define (nanopass-expand-define-language form)
  (let* ((name (cadr form))
         (clauses (cddr form)))
    (list 'begin
          (list 'define (string->symbol (string-append "__lang_" (symbol->string name)))
                (list 'nanopass-register-language!
                      (list 'nanopass-parse-language-spec
                            (list 'quote name)
                            (list 'quote clauses))))
          (list 'define (string->symbol (string-append "parse-" (symbol->string name)))
                (list 'lambda (list 'expr)
                      (list 'nanopass-parse (list 'quote name) 'expr)))
          (list 'define (string->symbol (string-append "unparse-" (symbol->string name)))
                (list 'lambda (list 'ir)
                      (list 'nanopass-unparse (list 'quote name) 'ir)))
          (list 'define (string->symbol (string-append (symbol->string name) "?"))
                (list 'lambda (list 'expr)
                      (list 'nanopass-ast-valid? (list 'quote name) 'expr))))))

;;; Expand define-parser AST
(define (nanopass-expand-define-parser form)
  (let ((proc-name (cadr form))
        (lang-name (caddr form)))
    (list 'define (list proc-name 'expr)
          (list 'nanopass-parse (list 'quote lang-name) 'expr))))

;;; Expand define-unparser AST
(define (nanopass-expand-define-unparser form)
  (let ((proc-name (cadr form))
        (lang-name (caddr form)))
    (list 'define (list proc-name 'ir)
          (list 'nanopass-unparse (list 'quote lang-name) 'ir))))

;;; -----------------------------------------------------------------------
;;; Host / Interpreter Macros (for ilisp and interactive environments)
;;; -----------------------------------------------------------------------
(define-macro (define-language . args)
  (nanopass-expand-define-language (cons 'define-language args)))

(define-macro (define-pass . args)
  (nanopass-expand-define-pass (cons 'define-pass args)))

(define-macro (define-parser . args)
  (nanopass-expand-define-parser (cons 'define-parser args)))

(define-macro (define-unparser . args)
  (nanopass-expand-define-unparser (cons 'define-unparser args)))

;;; -----------------------------------------------------------------------
;;; Canonical Compiler Pipeline Languages: L_src and L_core
;;; -----------------------------------------------------------------------

;;; L_src: Source intermediate language containing full high-level syntactic sugar
(define-language L_src
  (terminals
    (symbol (x))
    (constant (c)))
  (Expr (e)
    x
    c
    (quote datum)
    (if e1 e2 e3)
    (if e1 e2)
    (begin e ...)
    (lambda (x ...) e ...)
    (set! x e)
    (let ((x e1) ...) e ...)
    (letrec ((x e1) ...) e ...)
    (let* ((x e1) ...) e ...)
    (cond (e1 e2) ... (else e_else))
    (case key (dat e ...) ... (else e_else))
    (and e ...)
    (or e ...)
    (list e ...)
    (vector e ...)
    (bytevector e ...)
    (vector-append e ...)
    (bytevector-append e ...)
    (string-append e ...)
    (guard (x c ...) e ...)
    (let-values (((x ...) e1) ...) e ...)
    (let*-values (((x ...) e1) ...) e ...)
    (parameterize ((x e1) ...) e ...)
    (%program defs main)
    (e0 e1 ...)))

;;; L_core: Core intermediate language where all syntactic sugar has been removed
(define-language L_core
  (extends L_src)
  (Expr (e)
    (- (cond (e1 e2) ... (else e_else)))
    (- (case key (dat e ...) ... (else e_else)))
    (- (let* ((x e1) ...) e ...))
    (- (and e ...))
    (- (or e ...))
    (- (list e ...))
    (- (vector e ...))
    (- (bytevector e ...))
    (- (vector-append e ...))
    (- (bytevector-append e ...))
    (- (string-append e ...))
    (- (guard (x c ...) e ...))
    (- (let-values (((x ...) e1) ...) e ...))
    (- (let*-values (((x ...) e1) ...) e ...))
    (- (parameterize ((x e1) ...) e ...))))
