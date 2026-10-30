;;; =======================================================================
;;; ULisp Compiler: Frontend Intermediate Languages Specification
;;; (L_anf and L_lifted)
;;; Conforms to DSN-33 Architecture Specification & Issue #594
;;; =======================================================================
;;; Formal intermediate language definitions for the late Frontend pipeline
;;; using Nanopass DSL (define-language).
;;; - L_anf: A-Normal Form intermediate language where all function/primitive
;;;          arguments and conditional tests are atomic operands.
;;; - L_lifted: Flat procedure intermediate language where local lambda abstractions
;;;             have been hoisted into top-level %function definitions, and closures
;;;             are explicitly instantiated via %make-closure / %make-closure-env.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; L_anf: 3-Address Code / A-Normal Form Language
;;; -----------------------------------------------------------------------
(define-language L_anf
  (entry Program)
  (terminals
    (symbol (x lbl var))
    (constant (c)))
  (Atom (a)
    x
    lbl
    var
    c
    (quote datum)
    (%closure-ref a c)
    (%global-ref x))
  (Def (d)
    (define x e)
    e)
  (Expr (e)
    a
    (if a e1 e2)
    (if a e1)
    (begin e ...)
    (let ((x e1) ...) e ...)
    (letrec ((x e1) ...) e ...)
    (lambda (x ...) e ...)
    (set! x e)
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
    (a0 a ...))
  (Program (p)
    (%program (d ...) e)
    e))

;;; -----------------------------------------------------------------------
;;; L_lifted: Lambda-Lifted & Explicit Closure Converted Language
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
    (+ (annotate x e)
       (%stack-cons a1 a2)
       (%box-fixnum e)
       (%unbox-fixnum e)))
  (Program (p)
    (- (%program (d ...) e))
    (+ (%program (fn ...) e))))
