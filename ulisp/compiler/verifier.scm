;;; =======================================================================
;;; ULisp Compiler: Lightweight IR Verifier & Invariant Pass Checker
;;; Conforms to DSN-33 Architecture Specification & Issue #576
;;; =======================================================================

;;; Verifier Configuration (represented as cons cells to avoid top-level set! in LIR)
;;; Levels: 0 = OFF, 1 = BOUNDARY (LIR only), 2 = STANDARD (all passes), 3 = STRICT/PARANOID
(define *verifier-level* (cons 0 '()))
(define *verifier-enabled* (cons #f '()))
(define *verifier-strict* (cons #f '()))

(define (verifier-level) (car *verifier-level*))
(define (set-verifier-level! lvl)
  (set-car! *verifier-level* lvl)
  (if (> lvl 0)
      (begin
        (set-car! *verifier-enabled* #t)
        (enable-nanopass-verifier!))
      (begin
        (set-car! *verifier-enabled* #f)
        (disable-nanopass-verifier!))))

(define (verifier-enabled?) (> (car *verifier-level*) 0))
(define (enable-verifier!)
  (set-verifier-level! 2))
(define (disable-verifier!)
  (set-verifier-level! 0))
(define (verifier-strict?) (car *verifier-strict*))
(define (set-verifier-strict! flag) (set-car! *verifier-strict* flag))

;;; Dynamic Verifier Context Tracking
(define *verifier-context-stack* (cons '() '()))

(define (current-verifier-context)
  (if (null? (car *verifier-context-stack*))
      '()
      (caar *verifier-context-stack*)))

(define (verifier-push-context! ctx)
  (set-car! *verifier-context-stack* (cons ctx (car *verifier-context-stack*))))

(define (verifier-pop-context!)
  (if (pair? (car *verifier-context-stack*))
      (set-car! *verifier-context-stack* (cdar *verifier-context-stack*))))

(define (with-verifier-context ctx thunk)
  (verifier-push-context! ctx)
  (let ((res (thunk)))
    (verifier-pop-context!)
    res))

;;; Error Reporting Procedure with Contextual Information
(define (verifier-error phase message expr . rest)
  (let* ((ctx (current-verifier-context))
         (fn-entry (and (pair? ctx) (assq 'function ctx)))
         (fn-name (and fn-entry (cdr fn-entry)))
         (blk-entry (and (pair? ctx) (assq 'block ctx)))
         (blk-name (and blk-entry (cdr blk-entry))))
    (display "\n*** [VERIFIER ERROR] Phase: ")
    (display phase)
    (if fn-name
        (begin (display " | Function: ") (display fn-name)))
    (if blk-name
        (begin (display " | Block: ") (display blk-name)))
    (display " - ")
    (display message)
    (display "\n    Expression: ")
    (write expr)
    (if (and (pair? rest) (car rest))
        (begin
          (display "\n    Detail: ")
          (display (car rest))))
    (newline)
    (if (car *verifier-strict*)
        (error "IR Verifier Invariant Violation" expr)
        #f)))

;;; -----------------------------------------------------------------------
;;; 1. Pass 030 Desugar Output Verifier
;;; -----------------------------------------------------------------------
;;; Invariant: No remaining macro/syntactic sugar keywords:
;;;   cond, case, and, or, let*, named-let, let-values, let*-values,
;;;   guard, parameterize, do, when, unless, define-values

(define *prohibited-desugared-keywords*
  '(cond case and or let* let-values let*-values guard parameterize do when unless define-values))

(define (verify-desugared-ast ast)
  (let loop ((expr ast))
    (cond
      ((not (pair? expr)) #t)
      ((eq? (car expr) 'quote) #t)
      ((memq (car expr) *prohibited-desugared-keywords*)
       (verifier-error 'desugar "Prohibited macro/sugar keyword remaining after desugaring" expr))
      ;; Check for named let: (let <name> ((v e) ...) body)
      ((and (eq? (car expr) 'let)
            (pair? (cdr expr))
            (symbol? (cadr expr)))
       (verifier-error 'desugar "Named-let remaining after desugaring" expr))
      (else
       (let rec ((children (cdr expr)))
         (if (null? children)
             #t
             (and (loop (car children))
                  (rec (cdr children)))))))))

;;; -----------------------------------------------------------------------
;;; 2. Pass 070 ANF Output Verifier
;;; -----------------------------------------------------------------------
;;; Invariant: In all applications, call arguments and primitive operands
;;; must be atomic (symbols or constants), no nested compound expressions.

(define *anf-special-forms*
  '(quote if begin let letrec lambda set! define %program %values %call-with-values %raw-call/cc))

(define (verify-anf-ast ast)
  (if (and (assq 'L_anf (nanopass-get-languages))
           (not (nanopass-ast-valid? 'L_anf ast)))
      (verifier-error 'anf "AST violates L_anf schema invariants" ast)
      (let loop ((expr ast))
        (cond
          ((not (pair? expr)) #t)
          ((eq? (car expr) 'quote) #t)
          ((eq? (car expr) 'if)
           (let ((test (cadr expr))
                 (then (caddr expr))
                 (else-e (if (null? (cdddr expr)) '() (cadddr expr))))
             (if (not (atomic-expr? test))
                 (verifier-error 'anf "If-condition is not atomic in ANF" expr)
                 (and (loop then)
                      (if (null? else-e) #t (loop else-e))))))
          ((eq? (car expr) 'let)
           (let ((bindings (cadr expr))
                 (body (caddr expr)))
             (and (let b-loop ((bs bindings))
                    (if (null? bs)
                        #t
                        (and (loop (cadar bs))
                             (b-loop (cdr bs)))))
                  (loop body))))
          ((eq? (car expr) 'lambda)
           (let ((body (caddr expr)))
             (loop body)))
          ((eq? (car expr) 'begin)
           (let b-loop ((es (cdr expr)))
             (if (null? es)
                 #t
                 (and (loop (car es))
                      (b-loop (cdr es))))))
          ((eq? (car expr) '%program)
           (let ((defs (cadr expr))
                 (main (caddr expr)))
             (and (let d-loop ((ds defs))
                    (if (null? ds)
                        #t
                        (and (loop (car ds))
                             (d-loop (cdr ds)))))
                  (loop main))))
          ((memq (car expr) '(define set!))
           (loop (caddr expr)))
          ((eq? (car expr) '%call-with-values)
           (and (loop (cadr expr))
                (loop (caddr expr))))
          ((eq? (car expr) '%values)
           (let a-loop ((args (cdr expr)))
             (if (null? args)
                 #t
                 (if (not (atomic-expr? (car args)))
                     (verifier-error 'anf "%values operand is not atomic in ANF" (car args))
                     (a-loop (cdr args))))))
          ;; General application: (f a1 a2 ...)
          (else
           (let ((op (car expr))
                 (args (cdr expr)))
             (if (and (not (symbol? op)) (not (atomic-expr? op)))
                 (verifier-error 'anf "Application operator is not atomic in ANF" expr)
                 (let a-loop ((as args))
                   (if (null? as)
                       #t
                       (if (not (atomic-expr? (car as)))
                           (verifier-error 'anf "Application argument is not atomic in ANF" (car as))
                           (a-loop (cdr as))))))))))))

;;; -----------------------------------------------------------------------
;;; 3. Pass 110 Closure Convert Output Verifier
;;; -----------------------------------------------------------------------
;;; Invariant: Top-level program contains %program, closures are represented
;;; with %make-closure or lifted labels. No unlifted lambda abstractions.

(define (verify-closure-ast ast)
  (if (and (assq 'L_lifted (nanopass-get-languages))
           (not (nanopass-ast-valid? 'L_lifted ast)))
      (verifier-error 'closure "AST violates L_lifted schema invariants (unlifted lambda or malformed structure)" ast)
      (let loop ((expr ast))
        (cond
          ((not (pair? expr)) #t)
          ((eq? (car expr) 'quote) #t)
          ((eq? (car expr) 'lambda)
           (verifier-error 'closure "Unlifted lambda remaining after closure conversion" expr))
          ((or (eq? (car expr) '%make-closure)
               (eq? (car expr) '%make-closure-env))
           ;; Format: (%make-closure label free-vars ...) or (%make-closure-env label free-vars ...)
           (let ((label (cadr expr)))
             (if (not (symbol? label))
                 (verifier-error 'closure "%make-closure / %make-closure-env label must be a symbol" expr)
                 (let v-loop ((vars (cddr expr)))
                   (if (null? vars)
                       #t
                       (if (not (atomic-expr? (car vars)))
                           (verifier-error 'closure "%make-closure / %make-closure-env environment variable must be atomic" (car vars))
                           (v-loop (cdr vars))))))))
          (else
           (let rec ((children (cdr expr)))
             (if (null? children)
                 #t
                 (and (loop (car children))
                      (rec (cdr children))))))))))

;;; -----------------------------------------------------------------------
;;; 4. Pass 131 Safepoint / Stackmap Verifier
;;; -----------------------------------------------------------------------
;;; Invariant: Stackmaps list exists, each entry is (label frame-size bitmap),
;;; frame-size is 8-byte aligned positive integer, bitmap is non-negative int.

(define (verify-lir-safepoint lir)
  (if (not (and (pair? lir) (eq? (car lir) '%lir-program)))
      (verifier-error 'safepoint "LIR root tag must be %lir-program" lir)
      (let ((stackmaps-clause (assq 'stackmaps (cddr lir))))
        (if (not stackmaps-clause)
            (verifier-error 'safepoint "Missing stackmaps clause in %lir-program" lir)
            (let ((sms (cadr stackmaps-clause)))
              (let loop ((entries sms))
                (if (null? entries)
                    #t
                    (let ((entry (car entries)))
                      (cond
                        ((not (and (pair? entry) (= (length entry) 3)))
                         (verifier-error 'safepoint "Safepoint entry must be a 3-element tuple (label frame-size bitmap)" entry))
                        ((not (or (symbol? (car entry)) (string? (car entry))))
                         (verifier-error 'safepoint "Safepoint label must be symbol or string" entry))
                        ((not (and (integer? (cadr entry)) (> (cadr entry) 0) (= (modulo (cadr entry) 8) 0)))
                         (verifier-error 'safepoint "Safepoint frame-size must be positive 8-byte aligned integer" entry))
                        ((not (and (integer? (caddr entry)) (>= (caddr entry) 0)))
                         (verifier-error 'safepoint "Safepoint bitmap must be non-negative integer" entry))
                        (else
                         (loop (cdr entries))))))))))))

;;; -----------------------------------------------------------------------
;;; 5. Pass 132 Braun SSA / Block Arguments Verifier
;;; -----------------------------------------------------------------------
;;; Invariant: CFG blocks format (%block label (params ...) insts ...),
;;; jump and cjump instructions have consistent block arguments.

(define (verify-ssa-ast lir)
  (let loop ((node lir))
    (cond
      ((not (pair? node)) #t)
      ((eq? (car node) '%block)
       (let ((label (cadr node))
             (params (caddr node)))
         (cond
           ((not (symbol? label))
            (verifier-error 'ssa "%block label must be a symbol" node))
           ((not (list? params))
            (verifier-error 'ssa "%block parameters must be a list" node))
           (else
            (let p-loop ((ps params))
              (if (null? ps)
                  (let i-loop ((insts (cdddr node)))
                    (if (null? insts)
                        #t
                        (and (loop (car insts))
                             (i-loop (cdr insts)))))
                  (if (not (symbol? (car ps)))
                      (verifier-error 'ssa "%block parameter must be a symbol" (car ps))
                      (p-loop (cdr ps)))))))))
      ((eq? (car node) '%jump)
       (let ((target (cadr node))
             (args (cddr node)))
         (if (not (symbol? target))
             (verifier-error 'ssa "%jump target must be a label symbol" node)
             (let a-loop ((as args))
               (if (null? as)
                   #t
                   (if (not (atomic-expr? (car as)))
                       (verifier-error 'ssa "%jump argument must be atomic" (car as))
                       (a-loop (cdr as))))))))
      (else
       (let rec ((children (cdr node)))
         (if (null? children)
             #t
             (and (loop (car children))
                  (rec (cdr children)))))))))

;;; -----------------------------------------------------------------------
;;; Unified Verifier Dispatcher
;;; -----------------------------------------------------------------------
(define (verify-pass-output phase data)
  (let ((lvl (verifier-level)))
    (if (<= lvl 0)
        #t
        (case phase
          ((desugar 030)
           (if (>= lvl 2) (verify-desugared-ast data) #t))
          ((anf 070)
           (if (>= lvl 2) (verify-anf-ast data) #t))
          ((closure 110)
           (if (>= lvl 2) (verify-closure-ast data) #t))
          ((safepoint 131)
           (if (>= lvl 2) (verify-lir-safepoint data) #t))
          ((ssa 132)
           (if (>= lvl 2) (verify-ssa-ast data) #t))
          ((lir canonical-lir 130)
           ;; Level 1 (Boundary) or higher performs full LIR validation
           (validate-lir data))
          (else #t)))))

(define (nanopass-verify-pass-data pass-name lang-name data phase)
  (and (if (>= (verifier-level) 3)
           (nanopass-verify-ast pass-name lang-name data phase)
           #t)
       (verify-pass-output pass-name data)))
