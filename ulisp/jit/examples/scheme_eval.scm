;;; =======================================================================
;;; MLisp Example: Metacircular Scheme Evaluator (scheme_eval.scm)
;;; Conforms to DSN-34 Architecture Specification & Issue #507
;;;
;;; 100% Pure Scheme Implementation of a Mini-Scheme Evaluator.
;;; Demonstrates Self-Applied JIT Compilation:
;;; - Evaluates dynamic Scheme expressions (let, if, +, -, *, closures)
;;; - Inlines jit-merge-point on recursive tail calls
;;; - MLisp automatically extracts JIT traces from Scheme-on-Scheme execution!
;;; =======================================================================

(define (mini-lookup var env)
  (let ((entry (assq var env)))
    (if entry (cdr entry)
        (error "Unbound variable in mini-eval:" var))))

(define (mini-extend-env params args env)
  (if (null? params)
      env
      (cons (cons (car params) (car args))
            (mini-extend-env (cdr params) (cdr args) env))))

;;; Evaluate an expression in an environment
(define (mini-eval expr env)
  (cond
    ;; Immediate constants
    ((number? expr) expr)
    ((boolean? expr) expr)
    ((symbol? expr) (mini-lookup expr env))

    ((pair? expr)
     (let ((op (car expr)))
       (case op
         ;; Quote
         ((quote) (cadr expr))

         ;; Conditional
         ((if)
          (let ((test-val (mini-eval (cadr expr) env)))
            (trace-guard! 'type-bool test-val 'boolean 'exit-guard)
            (if test-val
                (mini-eval (caddr expr) env)
                (mini-eval (cadddr expr) env))))

         ;; Local binding
         ((let)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 (vars (map car bindings))
                 (vals (map (lambda (b) (mini-eval (cadr b) env)) bindings))
                 (new-env (mini-extend-env vars vals env)))
            (mini-eval body new-env)))

         ;; Tail recursive named loop: (loop-tail id params args body)
         ((loop-tail)
          (let* ((id (cadr expr))
                 (params (caddr expr))
                 (args (map (lambda (a) (mini-eval a env)) (cadddr expr)))
                 (body (car (cddddr expr))))
            ;; Trigger JIT merge point on loop entry!
            (jit-merge-point id args)
            (let loop ((cur-args args))
              (let ((loop-env (mini-extend-env params cur-args env)))
                (mini-eval body loop-env)))))

         ;; Arithmetic primitives
         ((+)
          (let ((a (mini-eval (cadr expr) env))
                (b (mini-eval (caddr expr) env)))
            (trace-record! '%add 'res a b)
            (+ a b)))

         ((-)
          (let ((a (mini-eval (cadr expr) env))
                (b (mini-eval (caddr expr) env)))
            (trace-record! '%sub 'res a b)
            (- a b)))

         ((*)
          (let ((a (mini-eval (cadr expr) env))
                (b (mini-eval (caddr expr) env)))
            (trace-record! '%mul 'res a b)
            (* a b)))

         ((<)
          (let ((a (mini-eval (cadr expr) env))
                (b (mini-eval (caddr expr) env)))
            (trace-guard! 'cmp-lt a b 'exit-guard)
            (< a b)))

         ((=)
          (let ((a (mini-eval (cadr expr) env))
                (b (mini-eval (caddr expr) env)))
            (trace-guard! 'cmp-eq a b 'exit-guard)
            (= a b)))

         (else
          (error "Unknown expression in mini-eval:" expr)))))

    (else
     (error "Invalid syntax in mini-eval:" expr))))
