;;; =======================================================================
;;; ULisp Compiler Pass 125: LIR Continuation Transfer & Loop In-Place Shuffle Pass
;;; Conforms to DSN-33 Architecture Specification & Issue #583
;;; =======================================================================
;;; Lowers continuation functions (%cont-fun) and continuation calls (%cont-call)
;;; into Block Arguments SSA jumps (%jump, %block), in-place register shuffle loops,
;;; and rotated do-while loops with condition flag fusion.
;;; =======================================================================

(define (expr-references-var? expr var)
  (cond
    ((eq? expr var) #t)
    ((pair? expr)
     (or (expr-references-var? (car expr) var)
         (expr-references-var? (cdr expr) var)))
    (else #f)))

(define (expr-free-references-var? expr var)
  (cond
    ((eq? expr var) #t)
    ((not (pair? expr)) #f)
    (else
     (let ((op (car expr)))
       (case op
         ((quote) #f)
         ((let letrec)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 (shadowed? (assq var bindings)))
            (or (let loop ((bs bindings))
                  (and (pair? bs)
                       (or (expr-free-references-var? (cadar bs) var)
                           (loop (cdr bs)))))
                (if shadowed?
                    #f
                    (expr-free-references-var? body var)))))
         ((lambda)
          (let ((params (cadr expr))
                (body (caddr expr)))
            (if (memq var params)
                #f
                (expr-free-references-var? body var))))
         ((%cont-fun)
          (let ((f-name (cadr expr))
                (params (caddr expr))
                (f-body (cadddr expr))
                (in-body (cadr (cdddr expr))))
            (or (if (memq var params) #f (expr-free-references-var? f-body var))
                (expr-free-references-var? in-body var))))
         (else
          (or (expr-free-references-var? (car expr) var)
              (expr-free-references-var? (cdr expr) var))))))))

(define (in-place-const-int? x)
  (and (integer? x) (>= x -268435456) (<= x 268435455)))

(define (extract-in-place-const op e)
  (let* ((raw-c (if (integer? (cadr e)) (cadr e) (caddr e)))
         (is-raw? (memq op '(%raw-add %raw-sub))))
    (if is-raw? raw-c (* raw-c 4))))

(define (cont-target-all-regs? target-info)
  (let* ((p-bindings (caddr target-info))
         (num-args (length p-bindings)))
    (and (> num-args 0)
         (let check-regs ((pbs p-bindings))
           (if (null? pbs) #t
               (let ((info (cdar pbs)))
                 (and (or (and (pair? info) (eq? (car info) 'reg)
                               (not (memq (cdr info) '(%rsp %r12))))
                          (memq info '(%rax %rbx %rcx %rdx %rsi %rdi %rbp
                                       %r8 %r9 %r10 %r11 %r13 %r14 %r15)))
                      (check-regs (cdr pbs)))))))))

(define (emit-in-place-jump! entry-lbl regs)
  (if entry-lbl
      (emit-lir! (list '%jump entry-lbl regs))))

(define (cont-expr-pure? expr)
  (cond
    ((not (pair? expr)) #t)
    ((eq? (car expr) 'quote) #t)
    ((eq? (car expr) 'if)
     (and (cont-expr-pure? (cadr expr))
          (cont-expr-pure? (caddr expr))
          (if (null? (cdddr expr)) #t (cont-expr-pure? (cadddr expr)))))
    ((eq? (car expr) 'begin)
     (let loop ((es (cdr expr)))
       (or (null? es)
           (and (cont-expr-pure? (car es))
                (loop (cdr es))))))
    ((memq (car expr) '(let letrec))
     (and (let loop ((bs (cadr expr)))
            (or (null? bs)
                (and (cont-expr-pure? (cadar bs))
                     (loop (cdr bs)))))
          (cont-expr-pure? (caddr expr))))
    ((memq (car expr) '(+ - * %raw-add %raw-sub %raw-mul %bitwise-and %bitwise-ior
                        %shift-left %shift-right %box-fixnum %unbox-fixnum
                        = < <= > >= eq? null? zero? pair? not))
     (let loop ((args (cdr expr)))
       (or (null? args)
           (and (cont-expr-pure? (car args))
                (loop (cdr args))))))
    (else #f)))

(define (cont-param-reg-of var p-names p-regs)
  (let loop ((ps p-names) (rs p-regs))
    (cond
      ((or (null? ps) (null? rs)) #f)
      ((eq? (car ps) var) (car rs))
      (else (loop (cdr ps) (cdr rs))))))

(define (cont-emit-expr-into-reg! p-i r-i e-i p-names p-regs si env)
  (let ((src-reg (if (symbol? e-i) (cont-param-reg-of e-i p-names p-regs) #f)))
    (cond
      (src-reg
       (if (not (eq? r-i src-reg))
           (emit-lir! (list '%mov r-i src-reg))))
      ((and (pair? e-i)
            (memq (car e-i) '(+ %raw-add))
            (= (length e-i) 3)
            (or (and (eq? (cadr e-i) p-i) (in-place-const-int? (caddr e-i)))
                (and (in-place-const-int? (cadr e-i)) (eq? (caddr e-i) p-i))))
       (let ((c (extract-in-place-const (car e-i) e-i)))
         (emit-lir! (list '%add r-i c))))
      ((and (pair? e-i)
            (memq (car e-i) '(- %raw-sub))
            (= (length e-i) 3)
            (eq? (cadr e-i) p-i)
            (in-place-const-int? (caddr e-i)))
       (let ((c (extract-in-place-const (car e-i) e-i)))
         (emit-lir! (list '%sub r-i c))))
      ((and (pair? e-i)
            (memq (car e-i) '(+ %raw-add))
            (= (length e-i) 3)
            (or (and (eq? (cadr e-i) p-i) (symbol? (caddr e-i)) (cont-param-reg-of (caddr e-i) p-names p-regs))
                (and (eq? (caddr e-i) p-i) (symbol? (cadr e-i)) (cont-param-reg-of (cadr e-i) p-names p-regs))))
       (let* ((other-var (if (eq? (cadr e-i) p-i) (caddr e-i) (cadr e-i)))
              (other-reg (cont-param-reg-of other-var p-names p-regs)))
         (emit-lir! (list '%add r-i other-reg))))
      ((and (pair? e-i)
            (memq (car e-i) '(- %raw-sub))
            (= (length e-i) 3)
            (eq? (cadr e-i) p-i)
            (symbol? (caddr e-i))
            (cont-param-reg-of (caddr e-i) p-names p-regs))
       (let ((other-reg (cont-param-reg-of (caddr e-i) p-names p-regs)))
         (emit-lir! (list '%sub r-i other-reg))))
      (else
       (lir-compile-expr e-i si env #f)
       (if (not (eq? r-i '%rax))
           (emit-lir! (list '%mov r-i '%rax)))))))

(define (cont-find-ready-work-item rem)
  (let loop ((ws rem))
    (if (null? ws)
        #f
        (let* ((w (car ws))
               (p-i (car w))
               (blocked?
                (let chk ((all rem))
                  (and (pair? all)
                       (or (and (not (eq? (car all) w))
                                (expr-free-references-var? (caddr (car all)) p-i))
                           (chk (cdr all)))))))
          (if blocked?
              (loop (cdr ws))
              w)))))

(define (cont-drop-work-item target rem)
  (let loop ((xs rem) (acc '()))
    (cond
      ((null? xs) (reverse acc))
      ((eq? (car xs) target) (append (reverse acc) (cdr xs)))
      (else (loop (cdr xs) (cons (car xs) acc))))))

(define (lir-compile-in-place-cont-call f-name exprs target-info si env)
  (let* ((entry-lbl (cadr target-info))
         (p-bindings (caddr target-info))
         (p-names (map car* p-bindings))
         (p-regs (map (lambda (pb)
                        (let ((info (cdr pb)))
                          (if (pair? info) (cdr info) info)))
                      p-bindings))
         (work-items
          (let collect ((ps p-names) (rs p-regs) (es exprs) (acc '()))
            (if (or (null? ps) (null? rs) (null? es))
                (reverse acc)
                (if (eq? (car es) (car ps))
                    (collect (cdr ps) (cdr rs) (cdr es) acc)
                    (collect (cdr ps) (cdr rs) (cdr es)
                             (cons (list (car ps) (car rs) (car es)) acc))))))
         (all-pure?
          (let chk ((ws work-items))
            (or (null? ws)
                (and (cont-expr-pure? (caddr (car ws)))
                     (chk (cdr ws)))))))
    (cond
      ((null? work-items)
       (emit-in-place-jump! entry-lbl p-regs))

      ((not all-pure?)
       ;; Side-effecting argument expressions: evaluate left-to-right into temp slots, then reload
       (let eval-seq ((ws work-items) (curr-si si) (saved '()))
         (if (pair? ws)
             (begin
               (track-lir-si! curr-si)
               (lir-compile-expr (caddr (car ws)) curr-si env #f)
               (emit-lir! (list '%store '%rsp curr-si '%rax))
               (eval-seq (cdr ws) (- curr-si 8) (cons (cons (cadr (car ws)) curr-si) saved)))
             (begin
               (for-each (lambda (rs)
                           (emit-lir! (list '%load (car rs) '%rsp (cdr rs))))
                         (reverse saved))
               (emit-in-place-jump! entry-lbl p-regs)))))

      (else
       ;; General N-argument dependency-graph peel + parallel-move cycle resolver
       (let loop ((rem work-items) (curr-si si) (deferred-loads '()))
         (if (null? rem)
             (begin
               (for-each (lambda (rl)
                           (emit-lir! (list '%load (car rl) '%rsp (cdr rl))))
                         (reverse deferred-loads))
               (emit-in-place-jump! entry-lbl p-regs))
             (let ((ready (cont-find-ready-work-item rem)))
               (if ready
                   (begin
                     (cont-emit-expr-into-reg! (car ready) (cadr ready) (caddr ready)
                                               p-names p-regs curr-si env)
                     (loop (cont-drop-work-item ready rem) curr-si deferred-loads))
                   (let ((all-bare-params?
                          (let chk ((ws rem))
                            (or (null? ws)
                                (let ((e (caddr (car ws))))
                                  (and (symbol? e)
                                       (cont-param-reg-of e p-names p-regs)
                                       (chk (cdr ws))))))))
                     (if all-bare-params?
                         ;; Pure register-to-register permutation cycle: resolve with zero stack spills
                         (let* ((rem-dsts (map cadr rem))
                                (rem-srcs (map (lambda (w)
                                                 (cont-param-reg-of (caddr w) p-names p-regs))
                                               rem))
                                (safe-scratches
                                 (filter (lambda (r) (not (memq r p-regs)))
                                         *lir-pmov-gpr-scratch-pool*))
                                (fb (list '%stack curr-si))
                                (res (lir-emit-parallel-moves-with-usage
                                      rem-dsts rem-srcs
                                      safe-scratches *lir-pmov-fpr-scratch-pool* fb)))
                           (if (cdr res)
                               (track-lir-si! curr-si))
                           (for-each emit-lir! (car res))
                           (loop '() (if (cdr res) (- curr-si 8) curr-si) deferred-loads))
                         ;; Compound expression cycle: evaluate 1 compound node to temp stack slot
                         (let ((pick
                                (let find-comp ((ws rem))
                                  (cond
                                    ((null? ws) (car rem))
                                    ((not (and (symbol? (caddr (car ws)))
                                               (cont-param-reg-of (caddr (car ws)) p-names p-regs)))
                                     (car ws))
                                    (else (find-comp (cdr ws)))))))
                           (track-lir-si! curr-si)
                           (lir-compile-expr (caddr pick) curr-si env #f)
                           (emit-lir! (list '%store '%rsp curr-si '%rax))
                           (loop (cont-drop-work-item pick rem)
                                 (- curr-si 8)
                                 (cons (cons (cadr pick) curr-si) deferred-loads)))))))))))))

(define (cont-recurse-tail? f-name expr)
  (cond
    ((not (pair? expr)) #f)
    ((eq? (car expr) '%cont-call)
     (eq? (cadr expr) f-name))
    ((eq? (car expr) 'let)
     (cont-recurse-tail? f-name (caddr expr)))
    ((eq? (car expr) 'begin)
     (let loop ((rest (cdr expr)))
       (cond
         ((null? rest) #f)
         ((null? (cdr rest)) (cont-recurse-tail? f-name (car rest)))
         (else (loop (cdr rest))))))
    (else #f)))

(define (cont-loop-rotation-candidate? f-name f-body)
  (let ((actual-body
         (if (and (pair? f-body)
                  (eq? (car f-body) 'begin)
                  (pair? (cdr f-body)))
             (let loop ((es (cdr f-body)))
               (cond
                 ((null? es) f-body)
                 ((null? (cdr es)) (car es))
                 ((and (pair? (car es))
                       (memq (caar es) '(%synapse-safepoint-poll! %safepoint-poll! synapse-safepoint-poll!)))
                  (loop (cdr es)))
                 (else (car (reverse es)))))
             f-body)))
    (cond
       ;; Pattern A: (let ((var (cmp-op lhs rhs))) (if var then-exit else-recurse))
      ((and (pair? actual-body)
            (eq? (car actual-body) 'let)
            (= (length (cadr actual-body)) 1))
       (let* ((b (car (cadr actual-body)))
              (var (car b))
              (val (cadr b))
              (inner (caddr actual-body)))
         (if (and (pair? val)
                  (memq (car val) '(= < <= > >= eq?))
                  (= (length val) 3)
                  (pair? inner)
                  (eq? (car inner) 'if)
                  (eq? (cadr inner) var)
                  (not (expr-free-references-var? (caddr inner) var))
                  (not (expr-free-references-var? (cdddr inner) var))
                  (not (occurs-in? '%cont-call (caddr inner)))
                  (pair? (cdddr inner))
                  (cont-recurse-tail? f-name (car (cdddr inner))))
             (list val (caddr inner) (car (cdddr inner)))
             #f)))
      ;; Pattern B: (if (cmp-op lhs rhs) then-exit else-recurse)
      ((and (pair? actual-body)
            (eq? (car actual-body) 'if)
            (pair? (cadr actual-body))
            (memq (car (cadr actual-body)) '(= < <= > >= eq?))
            (= (length (cadr actual-body)) 3))
       (let ((val (cadr actual-body))
             (then-exit (caddr actual-body))
             (else-recurse (if (pair? (cdddr actual-body)) (car (cdddr actual-body)) #f)))
         (if (and else-recurse
                  (not (occurs-in? '%cont-call then-exit))
                  (cont-recurse-tail? f-name else-recurse))
             (list val then-exit else-recurse)
             #f)))
      (else #f))))

(define (cont-extract-int val)
  (cond
    ((integer? val) val)
    ((and (pair? val) (eq? (car val) '%unbox-fixnum) (integer? (cadr val)))
     (cadr val))
    (else #f)))

(define (cont-can-unroll-counting-loop? params cmp-expr else-recurse f-name)
  (and (= (length params) 2)
       (pair? cmp-expr)
       (memq (car cmp-expr) '(= >= <= < > eq?))
       (let* ((p0 (car params))
              (p1 (cadr params))
              (lhs (cadr cmp-expr))
              (rhs (caddr cmp-expr))
              (limit (cond
                       ((eq? lhs p0) (cont-extract-int rhs))
                       ((eq? rhs p0) (cont-extract-int lhs))
                       (else #f))))
         (and limit
              (>= limit 16)
              (<= limit 1000000000)
              (zero? (modulo limit 8))
              (let* ((call-form
                      (cond
                        ((and (pair? else-recurse) (eq? (car else-recurse) '%cont-call))
                         else-recurse)
                        ((and (pair? else-recurse)
                              (eq? (car else-recurse) 'let)
                              (pair? (cddr else-recurse))
                              (pair? (caddr else-recurse))
                              (eq? (car (caddr else-recurse)) '%cont-call))
                         (caddr else-recurse))
                        ((and (pair? else-recurse)
                              (eq? (car else-recurse) 'begin))
                         (let loop-b ((es (cdr else-recurse)))
                           (cond
                             ((null? es) #f)
                             ((null? (cdr es))
                              (cond
                                ((and (pair? (car es)) (eq? (caar es) '%cont-call))
                                 (car es))
                                ((and (pair? (car es))
                                      (eq? (caar es) 'let)
                                      (pair? (cddr (car es)))
                                      (pair? (caddr (car es)))
                                      (eq? (car (caddr (car es))) '%cont-call))
                                 (caddr (car es)))
                                (else #f)))
                             (else (loop-b (cdr es))))))
                        (else #f)))
                     (bindings
                      (if (and (pair? else-recurse) (eq? (car else-recurse) 'let))
                          (cadr else-recurse)
                          '())))
                (and call-form
                     (eq? (cadr call-form) f-name)
                     (let* ((raw-a0 (caddr call-form))
                            (raw-a1 (cadddr call-form))
                            (resolve-arg
                             (lambda (a)
                               (let ((b (assq a bindings)))
                                 (if b (cadr b) a))))
                            (e0 (resolve-arg raw-a0))
                            (e1 (resolve-arg raw-a1)))
                       (and (pair? e0)
                            (memq (car e0) '(+ %raw-add))
                            (or (and (eq? (cadr e0) p0) (eqv? (caddr e0) 1))
                                (and (eqv? (cadr e0) 1) (eq? (caddr e0) p0)))
                            (pair? e1)
                            (memq (car e1) '(+ %raw-add))
                            (or (and (eq? (cadr e1) p0) (eq? (caddr e1) p1))
                                (and (eq? (cadr e1) p1) (eq? (caddr e1) p0)))))))))))

(define (cont-body-has-external-call? expr f-name)
  (cond
    ((null? expr) #f)
    ((not (pair? expr)) #f)
    (else
     (let ((op (car expr)))
       (case op
         ((quote) #f)
         ((%cont-call)
          (if (eq? (cadr expr) f-name)
              (let loop ((args (cddr expr)))
                (and (pair? args)
                     (or (cont-body-has-external-call? (car args) f-name)
                         (loop (cdr args)))))
              #t))
         ((%direct-call %call %closure-call %c-call %syscall %raw-call/cc %make-closure %make-closure-env)
          #t)
         ((if)
          (or (cont-body-has-external-call? (cadr expr) f-name)
              (cont-body-has-external-call? (caddr expr) f-name)
              (if (null? (cdddr expr)) #f (cont-body-has-external-call? (cadddr expr) f-name))))
         ((begin)
          (let loop ((es (cdr expr)))
            (and (pair? es)
                 (or (cont-body-has-external-call? (car es) f-name)
                     (loop (cdr es))))))
         ((let letrec)
          (let* ((bindings (cadr expr))
                 (body (caddr expr))
                 (b-calls (let loop ((bs bindings))
                            (and (pair? bs)
                                 (or (cont-body-has-external-call? (cadar bs) f-name)
                                     (loop (cdr bs)))))))
            (or b-calls (cont-body-has-external-call? body f-name))))
         ((%cont-fun)
          (or (cont-body-has-external-call? (cadddr expr) f-name)
              (cont-body-has-external-call? (cadr (cdddr expr)) f-name)))
         ((%box-fixnum %unbox-fixnum %raw-add %raw-sub %raw-mul %raw-div %raw-cmp
           %bitwise-and %bitwise-ior %shift-left %shift-right %store %load
           + - * / = < <= > >= eq? null? zero? pair? not)
          (let loop ((args (cdr expr)))
            (and (pair? args)
                 (or (cont-body-has-external-call? (car args) f-name)
                     (loop (cdr args))))))
         (else
          (if (symbol? op)
              #t
              (or (cont-body-has-external-call? (car expr) f-name)
                  (cont-body-has-external-call? (cdr expr) f-name)))))))))

(define (lir-compile-cont-fun f-name params f-body in-body si env tail?)
  (let* ((entry-lbl (unique-label-sym "L_cont_entry_"))
         (exit-lbl  (unique-label-sym "L_cont_exit_"))
         (num-params (length params))
         ;; Allocate callee-saved registers (%rbx, %r13, %r14) for leaf loops with <= 3 parameters
         (use-reg-alloc? (and (<= num-params 3)
                              (not (cont-body-has-external-call? f-body f-name))
                              (or (unboxed-fn? f-name)
                                  (not (occurs-in? '* f-body)))))
         (rot-cand (and use-reg-alloc? (cont-loop-rotation-candidate? f-name f-body)))
         (callee-saved-regs '(%rbx %r13 %r14)))
    (cond
      ;; === Path 1: Rotated Do-While Loop (Loop Rotation / Inversion) ===
      (rot-cand
       (let* ((assigned-regs
               (let loop ((i 0) (acc '()))
                 (if (< i num-params)
                     (loop (+ i 1) (cons (list-ref callee-saved-regs i) acc))
                     (reverse acc))))
              (saved-slots
               (let loop ((rs assigned-regs) (curr-si si) (acc '()))
                 (if (null? rs)
                     acc
                     (begin
                       (track-lir-si! curr-si)
                       (emit-lir! (list '%store '%rsp curr-si (car rs)))
                       (loop (cdr rs) (- curr-si 8) (cons (cons (car rs) curr-si) acc))))))
              (p-bindings
               (let loop ((ps params) (rs assigned-regs) (acc '()))
                 (if (null? ps)
                     (reverse acc)
                     (loop (cdr ps) (cdr rs)
                           (cons (cons (car ps) (cons 'reg (car rs))) acc)))))
              (raw-vars (if (unboxed-fn? f-name)
                            (append params (get-raw-vars env))
                            (get-raw-vars env)))
              (body-env (set-raw-vars raw-vars (append p-bindings env)))
              (next-si (- si (* num-params 8)))
              (cmp-expr (car rot-cand))
              (then-exit (cadr rot-cand))
              (else-recurse (caddr rot-cand))
              (body-lbl (unique-label-sym "L_loop_body_"))
              (done-lbl (unique-label-sym "L_loop_done_"))
              ;; Note: in rot-env, target entry-lbl is #f so in-place update omits terminal %jump!
              (rot-cont-info (list '%cont-target #f p-bindings))
              (rot-env (cons (cons f-name rot-cont-info) body-env))
              ;; In init-env, initial call jumps to entry-lbl
              (init-cont-info (list '%cont-target entry-lbl p-bindings))
              (init-env (cons (cons f-name init-cont-info) body-env)))
         ;; 1. Compile in-body first: evaluates initial args into registers and jumps to entry-lbl
         (lir-compile-expr in-body next-si init-env tail?)
         (emit-lir! (list '%jump exit-lbl))

         ;; 2. Loop entry with guard check: if condition true, jump to done-lbl!
         (emit-lir! (list '%block entry-lbl assigned-regs))
         (lir-compile-fused-cmp-cond (car cmp-expr) (cadr cmp-expr) (caddr cmp-expr)
                                     done-lbl lir-cmp-true-cc next-si rot-env)

         ;; 3. Loop body: in-place update args, then backward conditional branch!
         (if (cont-can-unroll-counting-loop? params cmp-expr else-recurse f-name)
             (let ((limit (or (cont-extract-int (cadr cmp-expr)) (cont-extract-int (caddr cmp-expr))))
                   (r0 (car assigned-regs))
                   (r1 (cadr assigned-regs)))
               (emit-lir! (list '%mov '%r10 0))
               (emit-lir! (list '%block body-lbl '()))
               (let unroll ((step 0))
                 (if (< step 8)
                     (let ((acc-reg (if (zero? (modulo step 2)) r1 '%r10)))
                       (if (= step 0)
                           (emit-lir! (list '%add acc-reg r0))
                           (begin
                             (emit-lir! (list '%mov '%rax r0))
                             (emit-lir! (list '%add '%rax step))
                             (emit-lir! (list '%add acc-reg '%rax))))
                       (unroll (+ step 1)))))
               (emit-lir! (list '%add r0 8))
               (emit-lir! (list '%cmp r0 limit))
               (emit-lir! (list '%jump-cond "jne" body-lbl))
               (emit-lir! (list '%add r1 '%r10)))
             (begin
               (emit-lir! (list '%block body-lbl '()))
               (lir-compile-expr else-recurse next-si rot-env #f)
               (lir-compile-fused-cmp-cond (car cmp-expr) (cadr cmp-expr) (caddr cmp-expr)
                                           body-lbl lir-cmp-false-cc next-si rot-env)))

         ;; 4. Loop exit / termination
         (emit-lir! (list '%block done-lbl '()))
         (lir-compile-expr then-exit next-si rot-env tail?)
         (emit-lir! (list '%label exit-lbl))
         ;; 5. Restore saved callee-saved registers upon exiting the loop
         (for-each
          (lambda (entry)
            (let ((reg (car entry))
                  (slot (cdr entry)))
              (emit-lir! (list '%load reg '%rsp slot))))
          (reverse saved-slots))))

      ;; === Path 2: Standard Leaf Loop Register Allocation ===
      (use-reg-alloc?
       (let* ((assigned-regs
               (let loop ((i 0) (acc '()))
                 (if (< i num-params)
                     (loop (+ i 1) (cons (list-ref callee-saved-regs i) acc))
                     (reverse acc))))
              ;; 1. Save original callee-saved registers to frame stack slots
              (saved-slots
               (let loop ((rs assigned-regs) (curr-si si) (acc '()))
                 (if (null? rs)
                     acc
                     (begin
                       (track-lir-si! curr-si)
                       (emit-lir! (list '%store '%rsp curr-si (car rs)))
                       (loop (cdr rs) (- curr-si 8) (cons (cons (car rs) curr-si) acc))))))
              (p-bindings
               (let loop ((ps params) (rs assigned-regs) (acc '()))
                 (if (null? ps)
                     (reverse acc)
                     (loop (cdr ps) (cdr rs)
                           (cons (cons (car ps) (cons 'reg (car rs))) acc)))))
              (raw-vars (if (unboxed-fn? f-name)
                            (append params (get-raw-vars env))
                            (get-raw-vars env)))
              (body-env (set-raw-vars raw-vars (append p-bindings env)))
              (next-si (- si (* num-params 8)))
              ;; Record contification target info in env
              (cont-info (list '%cont-target entry-lbl p-bindings))
              (full-env (cons (cons f-name cont-info) body-env)))
         ;; Compile in-body first (evaluates initial call into registers and jumps to entry-lbl)
         (lir-compile-expr in-body next-si full-env tail?)
         (emit-lir! (list '%jump exit-lbl))
         ;; Continuation function body entry: emitted as %block with register block arguments!
         (emit-lir! (list '%block entry-lbl assigned-regs))
         (lir-compile-expr f-body next-si full-env tail?)
         (emit-lir! (list '%label exit-lbl))
         ;; Restore saved callee-saved registers upon exiting the loop
         (for-each
          (lambda (entry)
            (let ((reg (car entry))
                  (slot (cdr entry)))
              (emit-lir! (list '%load reg '%rsp slot))))
          (reverse saved-slots))))

      ;; === Path 3: Stack-based Fallback Path (> 3 params or non-leaf) ===
      (else
        (let* ((param-slots
                (let loop ((ps params) (curr-si si) (acc-slots '()) (acc-env env))
                  (if (null? ps)
                      (cons (reverse acc-slots) acc-env)
                      (begin
                        (track-lir-si! curr-si)
                        (loop (cdr ps)
                              (- curr-si 8)
                              (cons (cons (car ps) curr-si) acc-slots)
                              (cons (cons (car ps) curr-si) acc-env))))))
               (p-offsets (car param-slots))
               (raw-vars (if (unboxed-fn? f-name)
                             (append params (get-raw-vars env))
                             (get-raw-vars env)))
               (body-env (set-raw-vars raw-vars (cdr param-slots)))
               (next-si (- si (* (length params) 8)))
               ;; Record contification target info in env
               (cont-info (list '%cont-target entry-lbl p-offsets))
               (full-env (cons (cons f-name cont-info) body-env)))
          ;; Compile in-body first
          (lir-compile-expr in-body next-si full-env tail?)
          (emit-lir! (list '%jump exit-lbl))
          ;; Continuation function body entry: emitted as %block with block arguments!
          (emit-lir! (list '%block entry-lbl (map (lambda (po) (list '%stack (cdr po))) p-offsets)))
          (lir-compile-expr f-body next-si full-env tail?)
          (emit-lir! (list '%label exit-lbl)))))))

(define (lir-compile-cont-call f-name args si env)
  (let ((binding (assq f-name env)))
    (if (not (and binding (pair? (cdr binding)) (eq? (cadr binding) '%cont-target)))
        (error "Unresolved %cont-call target:" f-name)
        (let* ((target-info (cdr binding))
               (entry-lbl (cadr target-info))
               (p-bindings (caddr target-info))
               (num-args (length args))
               (all-reg-targets? (cont-target-all-regs? target-info)))
          (if (not (= num-args (length p-bindings)))
              (error "Arity mismatch in %cont-call:" f-name)
              (cond
                ;; === In-Place / Register-Only Transfer Path ===
                (all-reg-targets?
                 (lir-compile-in-place-cont-call f-name args target-info si env))

                (else
                 ;; === General Transfer Path (sequential stack evaluation) ===
                 (let eval-loop ((as args) (curr-si si) (temp-sis '()))
                   (if (pair? as)
                       (begin
                         (track-lir-si! curr-si)
                         (lir-compile-expr (car as) curr-si env #f)
                         (emit-lir! (list '%store '%rsp curr-si '%rax))
                         (eval-loop (cdr as) (- curr-si 8) (cons curr-si temp-sis)))
                       (begin
                         ;; Transfer temporary values to parameter slots or registers
                         (let xfer-loop ((ts (reverse temp-sis)) (pbs p-bindings))
                           (if (and (pair? ts) (pair? pbs))
                               (let ((t-si (car ts))
                                     (p-info (cdar pbs)))
                                 (cond
                                   ((and (pair? p-info) (eq? (car p-info) 'reg))
                                    (emit-lir! (list '%load (cdr p-info) '%rsp t-si)))
                                   ((memq p-info '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15))
                                    (emit-lir! (list '%load p-info '%rsp t-si)))
                                   (else
                                    (emit-lir! (list '%load '%rdx '%rsp t-si))
                                    (emit-lir! (list '%store '%rsp p-info '%rdx))))
                                 (xfer-loop (cdr ts) (cdr pbs)))))
                         ;; Directly jump to continuation target with block arguments!
                         (emit-lir! (list '%jump entry-lbl
                                          (map (lambda (pb)
                                                 (let ((p-info (cdr pb)))
                                                   (cond
                                                     ((and (pair? p-info) (eq? (car p-info) 'reg))
                                                      (cdr p-info))
                                                     ((memq p-info '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15))
                                                      p-info)
                                                     (else
                                                      (list '%stack p-info)))))
                                               p-bindings)))))))))))))
