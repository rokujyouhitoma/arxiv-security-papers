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
;;; R7RS case-lambda Desugaring (Issue #609)
;;; -----------------------------------------------------------------------

(define (analyze-case-lambda-formals formals)
  (cond
    ((null? formals)
     (list 'exact 0 '() #f))
    ((symbol? formals)
     (list 'rest 0 '() formals))
    ((pair? formals)
     (let loop ((cur formals) (fixed '()))
       (cond
         ((null? cur)
          (list 'exact (length fixed) (reverse fixed) #f))
         ((symbol? cur)
          (list 'rest (length fixed) (reverse fixed) cur))
         ((pair? cur)
          (loop (cdr cur) (cons (car cur) fixed)))
         (else
          (error "Malformed formals in case-lambda:" formals)))))
    (else
     (error "Malformed formals in case-lambda:" formals))))

(define (make-cl-params count)
  (let loop ((i 0) (acc '()))
    (if (>= i count)
        (reverse acc)
        (loop (+ i 1)
              (cons (string->symbol (string-append "__cl_p" (number->string i)))
                    acc)))))

(define (symbols->cons-expr syms)
  (if (null? syms)
      ''()
      (list 'cons (car syms) (symbols->cons-expr (cdr syms)))))

(define (build-cl-rest-expr n-sym k num-params params)
  (let ((sub-params (let loop ((ps params) (i 0))
                      (cond
                        ((null? ps) '())
                        ((< i k) (loop (cdr ps) (+ i 1)))
                        (else ps)))))
    (let loop ((i 0))
      (let ((actual-cnt (+ k i)))
        (if (>= actual-cnt num-params)
            (symbols->cons-expr sub-params)
            (let ((slice (let take-loop ((ps sub-params) (cnt 0) (acc '()))
                           (if (or (null? ps) (>= cnt i))
                               (reverse acc)
                               (take-loop (cdr ps) (+ cnt 1) (cons (car ps) acc))))))
              (list 'if (list '= n-sym actual-cnt)
                    (symbols->cons-expr slice)
                    (loop (+ i 1)))))))))

(define (desugar-case-lambda-clause clause n-sym num-params params)
  (if (or (not (pair? clause)) (null? (cdr clause)))
      (error "Malformed case-lambda clause:" clause)
      (let* ((formals (car clause))
             (bodies (cdr clause))
             (info (analyze-case-lambda-formals formals))
             (type (car info))
             (k (cadr info))
             (fixed-vars (caddr info))
             (rest-var (cadddr info))
             (test-expr
              (if (eq? type 'exact)
                  (list '= n-sym k)
                  (if (= k 0)
                      #t
                      (list '>= n-sym k))))
             (fixed-bindings
              (let loop ((fvs fixed-vars) (ps params) (acc '()))
                (if (null? fvs)
                    (reverse acc)
                    (loop (cdr fvs) (cdr ps) (cons (list (car fvs) (car ps)) acc)))))
             (all-bindings
              (if (eq? type 'rest)
                  (append fixed-bindings
                          (list (list rest-var (build-cl-rest-expr n-sym k num-params params))))
                  fixed-bindings))
             (clause-body
              (if (null? all-bindings)
                  (make-body-expr bodies)
                  (list 'let all-bindings (make-body-expr bodies)))))
        (list test-expr clause-body))))

(define (desugar-case-lambda clauses)
  (if (null? clauses)
      (let ((n-sym (unique-symbol "cl_n_")))
        (list 'lambda '()
              (list 'let (list (list n-sym '(%num-args)))
                    (list 'error "case-lambda: no matching clause for arity" n-sym))))
      (let* ((clause-infos
              (map (lambda (cl) (analyze-case-lambda-formals (car cl))) clauses))
             (has-rest? (let loop ((infos clause-infos))
                          (and (pair? infos)
                               (or (eq? (caar infos) 'rest)
                                   (loop (cdr infos))))))
             (max-k (let loop ((infos clause-infos) (m 0))
                      (if (null? infos)
                          m
                          (let ((k (cadar infos)))
                            (loop (cdr infos) (if (> k m) k m))))))
             (num-params (let ((target (if has-rest? (+ max-k 4) max-k)))
                           (if (> target 8) target 8)))
             (params (make-cl-params num-params))
             (n-sym (unique-symbol "cl_n_"))
             (dispatch-expr
              (let loop ((cls clauses))
                (if (null? cls)
                    (list 'error "case-lambda: no matching clause for arity" n-sym)
                    (let* ((cl (car cls))
                           (desugared-cl (desugar-case-lambda-clause cl n-sym num-params params))
                           (test (car desugared-cl))
                           (body (cadr desugared-cl)))
                      (if (eq? test #t)
                          body
                          (list 'if test
                                body
                                (loop (cdr cls))))))))
             (sanitized-bindings
              (let loop ((ps params) (i 0) (acc '()))
                (if (null? ps)
                    (reverse acc)
                    (loop (cdr ps) (+ i 1)
                          (cons (list (car ps) (list 'if (list '< i n-sym) (car ps) #f))
                                acc))))))
        (list 'lambda params
              (list 'let (list (list n-sym '(%num-args)))
                    (list 'let sanitized-bindings
                          dispatch-expr))))))

;;; -----------------------------------------------------------------------
;;; Nanopass DSL Pass Definition: Desugar Bindings
;;; -----------------------------------------------------------------------
(define-pass desugar-bindings : L_src (ir) -> L_core ()
  (Expr : Expr (ir) -> Expr ()
    ((case-lambda . ,clauses) (Expr (desugar-case-lambda clauses)))
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
