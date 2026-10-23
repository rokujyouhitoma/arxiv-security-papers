;;; =======================================================================
;;; ULisp Compiler Pass 028: Local Bindings Desugaring Pass
;;; Conforms to DSN-33 Architecture Specification & Nanopass Standard
;;; Desugars local binding constructs (let*, named let) and body sequences
;;; =======================================================================

(define (make-body-expr bodies)
  (cond
    ((null? bodies) (list 'begin))
    ((null? (cdr bodies)) (car bodies))
    (else (cons 'begin bodies))))

(define (desugar-let* bindings bodies)
  (if (null? bindings)
      (make-body-expr bodies)
      (list 'let (list (car bindings))
            (desugar-let* (cdr bindings) bodies))))

(define (desugar-named-let expr)
  (let* ((name (cadr expr))
         (bindings (caddr expr))
         (bodies (cdddr expr))
         (params (map car* bindings))
         (inits (map cadr bindings)))
    (list 'letrec
          (list (list name (cons 'lambda (cons params bodies))))
          (cons name inits))))

(define (desugar-do bindings exit-clause commands)
  (let* ((loop-sym (unique-symbol "do_loop_"))
         (init-bindings
          (map (lambda (b) (list (car b) (cadr b))) bindings))
         (test (car exit-clause))
         (res (cdr exit-clause))
         (then-expr
          (if (null? res)
              #f
              (make-body-expr res)))
         (step-exprs
          (map (lambda (b)
                 (if (pair? (cddr b))
                     (caddr b)
                     (car b)))
               bindings))
         (loop-call (cons loop-sym step-exprs))
         (else-expr
          (make-body-expr (append commands (list loop-call)))))
    (list 'let loop-sym init-bindings
          (list 'if test
                then-expr
                else-expr))))

(define (normalize-define-spec spec bodies)
  (cond
    ((pair? spec)
     (let ((actual-bodies (if (null? bodies) (list #f) bodies)))
       (if (pair? (car spec))
           ;; カリー化短縮構文: (define ((f x) y) ...) -> (define (f x) (lambda (y) ...))
           (normalize-define-spec (car spec) (list (cons 'lambda (cons (cdr spec) actual-bodies))))
           ;; 通常短縮構文: (define (f x ...) ...) -> (define f (lambda (x ...) ...))
           (cons (car spec) (cons 'lambda (cons (cdr spec) actual-bodies))))))
    ((symbol? spec)
     ;; 変数定義: (define x val)
     (cons spec (if (pair? bodies) (car bodies) #f)))
    (else
     (error "Malformed define specification in internal define:" spec))))

(define (desugar-internal-define spec rest-def rest)
  (let* ((norm (normalize-define-spec spec rest-def))
         (name (car norm))
         (val (cdr norm))
         (is-proc? (and (pair? val) (eq? (car val) 'lambda))))
    (if is-proc?
        ;; 連続する手続き定義を単一の letrec 節へ集約（相互再帰対応）
        (let loop ((cur-rest rest)
                   (proc-bindings (list (list name val))))
          (if (and (pair? cur-rest)
                   (pair? (car cur-rest))
                   (eq? (caar cur-rest) 'define)
                   (pair? (cdar cur-rest)))
              (let* ((next-def (car cur-rest))
                     (next-norm (normalize-define-spec (cadr next-def) (cddr next-def)))
                     (next-name (car next-norm))
                     (next-val (cdr next-norm)))
                (if (and (pair? next-val) (eq? (car next-val) 'lambda))
                    (loop (cdr cur-rest) (cons (list next-name next-val) proc-bindings))
                    (list 'letrec (reverse proc-bindings) (if (null? cur-rest) #f (make-body-expr cur-rest)))))
              (list 'letrec (reverse proc-bindings) (if (null? cur-rest) #f (make-body-expr cur-rest)))))
        ;; 通常の変数定義: let で包み、後続の定義・式を body に配置
        (list 'let (list (list name val)) (if (null? rest) #f (make-body-expr rest))))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass Definition: Desugar Bindings
;;; -----------------------------------------------------------------------
(define-pass desugar-bindings : L_src (ir) -> L_core ()
  (Expr : Expr (ir) -> Expr ()
    ((let* ,bindings . ,bodies) (Expr (desugar-let* bindings bodies)))
    ((let ,name ,bindings . ,bodies) (guard (symbol? name))
     (Expr (desugar-named-let (cons 'let (cons name (cons bindings bodies))))))
    ((let ,bindings ,b1 ,b2 . ,rest) (guard (list? bindings))
     (Expr (list 'let bindings (cons 'begin (cons b1 (cons b2 rest))))))
    ((letrec ,bindings ,b1 ,b2 . ,rest) (guard (list? bindings))
     (Expr (list 'letrec bindings (cons 'begin (cons b1 (cons b2 rest))))))
    ((lambda ,params ,b1 ,b2 . ,rest)
     (Expr (list 'lambda params (cons 'begin (cons b1 (cons b2 rest))))))
    ((do ,bindings ,exit-clause . ,commands)
     (Expr (desugar-do bindings exit-clause commands)))
    ((begin (begin . ,inner) . ,rest)
     (Expr (cons 'begin (append inner rest))))
    ((begin (define ,spec . ,rest-def) . ,rest)
     (Expr (desugar-internal-define spec rest-def rest)))
    ((define ,spec . ,rest-def)
     (Expr (desugar-internal-define spec rest-def '())))))
