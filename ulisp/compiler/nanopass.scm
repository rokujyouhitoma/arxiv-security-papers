;;; =======================================================================
;;; ULisp Compiler: Nanopass Framework Core DSL (define-language / define-pass)
;;; Conforms to DSN-33 Architecture Specification & Keep & Dybvig (2013)
;;; =======================================================================

;;; Helper to parse header of define-pass
;;; (define-pass pass-name : L_in (ir extra_in ...) -> L_out (extra_out ...) body ...)
;;; or (define-pass pass-name : L_in (ir extra_in ...) -> * (extra_out ...) body ...)
;;; or (define-pass pass-name (ir extra_in ...) body ...)
(define (nanopass-parse-pass-header form)
  (let ((name (cadr form))
        (rest (cddr form)))
    (if (and (pair? rest) (eq? (car rest) ':))
        (let* ((l-in (cadr rest))
               (in-args (caddr rest))
               (in-arg-list (if (pair? in-args) in-args (list in-args)))
               (after-arrow (cddddr rest))
               (l-out (car after-arrow))
               (has-extra-out? (and (pair? (cdr after-arrow)) (list? (cadr after-arrow))))
               (extra-out (if has-extra-out? (cadr after-arrow) '()))
               (clauses (if has-extra-out? (cddr after-arrow) (cdr after-arrow))))
          (list name l-in in-arg-list l-out extra-out clauses))
        (let* ((in-args (car rest))
               (in-arg-list (if (pair? in-args) in-args (list in-args)))
               (clauses (cdr rest)))
          (list name 'L_src in-arg-list 'L_core '() clauses)))))

;;; Expand a single rule in a nonterminal transformer
(define (nanopass-expand-rule rule nt-name)
  (let* ((pat (car rule))
         (rest (cdr rule))
         (has-guard? (and (pair? rest)
                          (pair? (car rest))
                          (eq? (car (car rest)) 'guard)))
         (guard-expr (if has-guard? (cadr (car rest)) #t))
         (raw-body (if has-guard?
                       (if (null? (cddr rest)) (cadr rest) (cons 'begin (cdr rest)))
                       (if (null? (cdr rest)) (car rest) (cons 'begin rest))))
         (vars (nanopass-extract-pattern-vars pat))
         (body-expr (nanopass-expand-template raw-body vars)))
    (list pat vars guard-expr body-expr)))

;;; Build cascaded if-expression for nonterminal transformer rules
(define (nanopass-build-rules-cascade rules l-in l-out nt-name in-arg-list extra-out)
  (let* ((ir-var (car in-arg-list))
         (extra-in (cdr in-arg-list)))
    (let loop ((rs rules))
      (if (null? rs)
          (if (null? extra-in)
              (list 'nanopass-catamorphism-step
                    (list 'quote l-in)
                    (list 'quote l-out)
                    (list 'quote nt-name)
                    ir-var
                    nt-name
                    ''()
                    (list 'quote extra-out))
              (list 'nanopass-catamorphism-step
                    (list 'quote l-in)
                    (list 'quote l-out)
                    (list 'quote nt-name)
                    ir-var
                    nt-name
                    (cons 'list extra-in)
                    (list 'quote extra-out)))
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
                                         ir-var
                                         nt-name
                                         (list 'lambda vars
                                               (list 'if guard-expr
                                                     (list 'cons #t body-expr)
                                                     #f)))))
                  (list 'if c-var
                        (list 'cdr c-var)
                        (loop (cdr rs)))))))))

;;; Normalize rules whether passed as list of rules or single wrapped list
(define (nanopass-normalize-rules raw-rules)
  (if (and (= (length raw-rules) 1)
           (pair? (car raw-rules))
           (> (length (car raw-rules)) 1)
           (pair? (caar raw-rules))
           (pair? (cadar raw-rules))
           (pair? (cddar raw-rules)))
      (car raw-rules)
      raw-rules))

;;; Parse a nonterminal clause in define-pass
(define (nanopass-parse-nt-clause clause)
  (let ((nt-name (car clause))
        (rest (cdr clause)))
    (if (and (pair? rest) (eq? (car rest) ':))
        ;; (NT : NT_in (ir extra1 ...) -> NT_out (extra_out ...) rules ...)
        ;; or (NT : NT_in (ir extra1 ...) -> * (extra_out ...) rules ...)
        (let* ((nt-in (cadr rest))
               (in-args (caddr rest))
               (in-arg-list (if (pair? in-args) in-args (list in-args)))
               (after-arrow (cddddr rest))
               (nt-out (car after-arrow))
               (has-extra-out? (and (pair? (cdr after-arrow)) (list? (cadr after-arrow))))
               (extra-out (if has-extra-out? (cadr after-arrow) '()))
               (raw-rules (if has-extra-out? (cddr after-arrow) (cdr after-arrow)))
               (rules (nanopass-normalize-rules raw-rules)))
          (list nt-name in-arg-list nt-out extra-out rules))
        ;; Shorthand: (NT (ir extra1 ...) rules ...)
        (let* ((in-args (car rest))
               (in-arg-list (if (pair? in-args) in-args (list in-args)))
               (rules (nanopass-normalize-rules (cdr rest))))
          (list nt-name in-arg-list nt-name '() rules)))))

;;; Expand define-pass AST
(define (nanopass-expand-define-pass-with-trace form force-trace?)
  (let* ((parsed (nanopass-parse-pass-header form))
         (name (car parsed))
         (l-in (cadr parsed))
         (in-arg-list (caddr parsed))
         (l-out (cadddr parsed))
         (extra-out (car (cddddr parsed)))
         (clauses (cadr (cddddr parsed))))
    (let loop ((rest clauses)
               (defs '())
               (nt-procs '())
               (entry-nt #f))
      (if (null? rest)
          (let* ((final-entry (if entry-nt entry-nt 'Expr))
                 (ir-var (car in-arg-list))
                 (res-var (unique-symbol "__res_"))
                 (body-call (cons final-entry in-arg-list)))
            (list 'define (cons name in-arg-list)
                  (list 'letrec
                        (append (reverse defs) (reverse nt-procs))
                        (list 'begin
                              (list 'if (list 'nanopass-verifier-enabled?)
                                    (list 'nanopass-verify-ast (list 'quote name) (list 'quote l-in) ir-var ''entry)
                                    #f)
                              (list 'let (list (list res-var body-call))
                                    (list 'if (list 'nanopass-verifier-enabled?)
                                          (list 'nanopass-verify-ast (list 'quote name) (list 'quote l-out) res-var ''exit)
                                          #f)
                                    (if force-trace?
                                        (list 'begin
                                              (list 'nanopass-display-ast-diff (list 'quote name) ir-var res-var)
                                              res-var)
                                        (list 'begin
                                              (list 'if (list 'nanopass-trace-enabled?)
                                                    (list 'nanopass-display-ast-diff (list 'quote name) ir-var res-var)
                                                    #f)
                                              res-var)))))))
          (let ((c (car rest)))
            (cond
              ;; (definitions def1 def2 ...)
              ((and (pair? c) (eq? (car c) 'definitions))
               (let ((norm-defs
                      (map (lambda (d)
                             (if (and (pair? d) (eq? (car d) 'define))
                                 (let ((spec (cadr d)))
                                   (if (pair? spec)
                                       (list (car spec) (cons 'lambda (cons (cdr spec) (cddr d))))
                                       (list spec (caddr d))))
                                 d))
                           (cdr c))))
                 (loop (cdr rest) (append (reverse norm-defs) defs) nt-procs entry-nt)))
              ;; (entry EntryNT)
              ((and (pair? c) (eq? (car c) 'entry))
               (loop (cdr rest) defs nt-procs (cadr c)))
              ;; (NT : NT_in (ir extra ...) -> NT_out (extra_out ...) rules ...)
              ;; or (NT (ir extra ...) rules ...)
              ((and (pair? c) (symbol? (car c)))
               (let* ((parsed-nt (nanopass-parse-nt-clause c))
                      (nt-name (car parsed-nt))
                      (nt-in-args (cadr parsed-nt))
                      (nt-out (caddr parsed-nt))
                      (nt-extra-out (cadddr parsed-nt))
                      (raw-rules (car (cddddr parsed-nt)))
                      (expanded-rules (map (lambda (r) (nanopass-expand-rule r nt-name)) raw-rules))
                      (body-expr (nanopass-build-rules-cascade expanded-rules l-in nt-out nt-name nt-in-args (if (pair? nt-extra-out) nt-extra-out extra-out)))
                      (proc-binding (list nt-name (list 'lambda nt-in-args body-expr))))
                 (loop (cdr rest)
                       defs
                       (cons proc-binding nt-procs)
                       (if entry-nt entry-nt nt-name))))
              (else
               (loop (cdr rest) defs nt-procs entry-nt))))))))

(define (nanopass-expand-define-pass form)
  (nanopass-expand-define-pass-with-trace form #f))

(define (nanopass-expand-trace-define-pass form)
  (let ((pass-form (cons 'define-pass (cdr form))))
    (nanopass-expand-define-pass-with-trace pass-form #t)))

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

(define-macro (trace-define-pass . args)
  (nanopass-expand-trace-define-pass (cons 'trace-define-pass args)))

(define-macro (define-parser . args)
  (nanopass-expand-define-parser (cons 'define-parser args)))

(define-macro (define-unparser . args)
  (nanopass-expand-define-unparser (cons 'define-unparser args)))

(define-macro (in-context . args)
  (if (= (length args) 2)
      (list (car args) (cadr args))
      (list 'nanopass-parse-nt (list 'quote (car args)) (caddr args) (list 'quote (cadr args)))))

(define-macro (nanopass-template . args)
  (nanopass-expand-template (car args) '()))

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
    (do ((x e1 e2) ...) (e_test e_res ...) e_cmd ...)
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
    (- (do ((x e1 e2) ...) (e_test e_res ...) e_cmd ...))
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
