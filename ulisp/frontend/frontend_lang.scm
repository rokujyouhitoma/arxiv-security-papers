;;; =======================================================================
;;; ULisp Compiler: Frontend Intermediate Languages Specification
;;; (L_cst -> L_src -> L_core -> L_anf -> L_lifted)
;;; Conforms to DSN-33, DSN-33-01 Architecture Specification & Issues #594, #753
;;; =======================================================================
;;; Formal intermediate language definitions for the entire Frontend pipeline
;;; using Nanopass DSL (define-language) with a continuous `extends` chain:
;;; - L_cst:    Concrete Syntax Tree (surface syntax including library declarations,
;;;             hygienic macros, and Nanopass/Picopass DSL forms).
;;; - L_src:    Source HIR after library/import desugaring and macro/DSL expansion.
;;; - L_core:   Core HIR where all 18 high-level syntactic sugar forms are removed.
;;; - L_anf:    A-Normal Form intermediate language where all function/primitive
;;;             arguments and conditional tests are atomic operands.
;;; - L_lifted: Flat procedure intermediate language where local lambda abstractions
;;;             have been hoisted into top-level %function definitions, and closures
;;;             are explicitly instantiated via %make-closure / %make-closure-env.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. L_cst: Concrete Syntax Tree (Surface Language)
;;; -----------------------------------------------------------------------
(define-language L_cst
  (entry Program)
  (terminals
    (symbol (x lbl var))
    (constant (c)))
  (Def (d)
    (define-library (x ...) d ...)
    (import d ...)
    (export x ...)
    (include c)
    (include-ci c)
    (define-syntax x e)
    (define-language x d ...)
    (define-pass x d ...)
    (define-picopass x d ...)
    (define-femtopass x d ...)
    (define-attopass x d ...)
    (define x e)
    (define (x x1 ...) e ...)
    e)
  (Expr (e)
    x
    c
    (quote datum)
    (quasiquote datum)
    (let-syntax ((x e1) ...) e ...)
    (letrec-syntax ((x e1) ...) e ...)
    (syntax-rules (x ...) (e1 e2) ...)
    (if e1 e2 e3)
    (if e1 e2)
    (begin e ...)
    (lambda (x ...) e ...)
    (set! x e)
    (let ((x e1) ...) e ...)
    (let x ((x1 e1) ...) e ...)
    (letrec ((x e1) ...) e ...)
    (letrec* ((x e1) ...) e ...)
    (let* ((x e1) ...) e ...)
    (do ((x e1 e2) ...) (e_test e_res ...) e_cmd ...)
    (cond (e1 e2) ... (else e_else))
    (cond-expand (e1 e2 ...) ...)
    (case key (dat e ...) ... (else e_else))
    (and e ...)
    (or e ...)
    (when e1 e2 ...)
    (unless e1 e2 ...)
    (delay e)
    (delay-force e)
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
    (define x e)
    (define (x x1 ...) e ...)
    (e0 e1 ...))
  (Program (p)
    (%program (d ...) e)
    d
    e))

;;; -----------------------------------------------------------------------
;;; 2. L_src: Source HIR (Post-Library & Post-Macro Expansion)
;;; -----------------------------------------------------------------------
(define-language L_src
  (extends L_cst)
  (entry Program)
  (Def (d)
    (- (define-library (x ...) d ...)
       (import d ...)
       (export x ...)
       (include c)
       (include-ci c)
       (define-syntax x e)
       (define-language x d ...)
       (define-pass x d ...)
       (define-picopass x d ...)
       (define-femtopass x d ...)
       (define-attopass x d ...)))
  (Expr (e)
    (- (let-syntax ((x e1) ...) e ...)
       (letrec-syntax ((x e1) ...) e ...)
       (syntax-rules (x ...) (e1 e2) ...))))

;;; -----------------------------------------------------------------------
;;; 3. L_core: Core HIR (All Syntactic Sugar Removed)
;;; -----------------------------------------------------------------------
(define-language L_core
  (extends L_src)
  (entry Program)
  (Def (d)
    (- (define (x x1 ...) e ...)))
  (Expr (e)
    (- (quasiquote datum)
       (let x ((x1 e1) ...) e ...)
       (letrec* ((x e1) ...) e ...)
       (let* ((x e1) ...) e ...)
       (do ((x e1 e2) ...) (e_test e_res ...) e_cmd ...)
       (cond (e1 e2) ... (else e_else))
       (cond-expand (e1 e2 ...) ...)
       (case key (dat e ...) ... (else e_else))
       (and e ...)
       (or e ...)
       (when e1 e2 ...)
       (unless e1 e2 ...)
       (delay e)
       (delay-force e)
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
       (define (x x1 ...) e ...))))

;;; -----------------------------------------------------------------------
;;; 4. L_anf: 3-Address Code / A-Normal Form Language
;;; -----------------------------------------------------------------------
(define-language L_anf
  (extends L_core)
  (entry Program)
  (Atom (a)
    x
    lbl
    var
    c
    (quote datum)
    (%closure-ref a c)
    (%global-ref x))
  (Expr (e)
    (- x
       c
       (quote datum)
       (if e1 e2 e3)
       (if e1 e2)
       (define x e)
       (e0 e1 ...))
    (+ a
       (if a e1 e2)
       (if a e1)
       (%make-closure a1 a ...)
       (%make-closure-env a1 a ...)
       (%closure-ref a c)
       (%closure-set! a1 c a2)
       (%cont-fun x (x ...) e1 e2)
       (%cont-call x a ...)
       (%with-handler a1 a2)
       (%raw-call/cc a)
       (%call-with-values a1 a2)
       (%values a ...)
       (%direct-call a1 a ...)
       (%global-ref x)
       (%global-set! x e)
       (a0 a ...)))
  (Program (p)
    (- d)))

;;; -----------------------------------------------------------------------
;;; 5. L_lifted: Lambda-Lifted & Explicit Closure Converted Language
;;; -----------------------------------------------------------------------
(define-language L_lifted
  (extends L_anf)
  (entry Program)
  (FunctionDecl (fn)
    (%function x (x ...) e))
  (Atom (a)
    (+ (%unbox-fixnum a)))
  (Expr (e)
    (- (lambda (x ...) e ...))
    (+ (if e1 e2 e3)
       (if e1 e2)
       (%direct-call a1 e ...)
       (annotate x e)
       (%stack-cons a1 a2)
       (%box-fixnum e)
       (%unbox-fixnum e)
       (e0 e1 ...)))
  (Program (p)
    (- (%program (d ...) e))
    (+ (%program (fn ...) e))))
