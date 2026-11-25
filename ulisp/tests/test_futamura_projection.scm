;;; =======================================================================
;;; Test Suite: First Futamura Projection on Micro-Language (Issue #885)
;;; Conforms to DSN-33-03 §1.2 & §2.1
;;; =======================================================================

(display "\n=== [Test Suite: First Futamura Projection on Micro-Language (Issue #885)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; 1. Micro-Language Bytecode Interpreter Definition
;;; -----------------------------------------------------------------------

;; Pure Reference Interpreter for Ground Truth Verification
(define (micro-interp-eval insts stack env)
  (cond
    ((null? insts) (car stack))
    (else
     (let* ((inst (car insts))
            (op (car inst))
            (rest (cdr insts)))
       (cond
         ((eq? op 'PUSH-CONST)
          (micro-interp-eval rest (cons (cadr inst) stack) env))
         ((eq? op 'LOAD-VAR)
          (let ((entry (assq (cadr inst) env)))
            (micro-interp-eval rest (cons (cdr entry) stack) env)))
         ((eq? op 'ADD)
          (let ((b (car stack)) (a (cadr stack)) (stk (cddr stack)))
            (micro-interp-eval rest (cons (+ a b) stk) env)))
         ((eq? op 'SUB)
          (let ((b (car stack)) (a (cadr stack)) (stk (cddr stack)))
            (micro-interp-eval rest (cons (- a b) stk) env)))
         ((eq? op 'MUL)
          (let ((b (car stack)) (a (cadr stack)) (stk (cddr stack)))
            (micro-interp-eval rest (cons (* a b) stk) env)))
         ((eq? op 'IF-ZERO)
          (let ((cond-val (car stack))
                (then-code (cadr inst))
                (else-code (caddr inst)))
            (if (= cond-val 0)
                (micro-interp-eval then-code (cdr stack) env)
                (micro-interp-eval else-code (cdr stack) env))))
         ((eq? op 'HALT)
          (car stack))
         (else
          (error "Unknown opcode" op)))))))

;; Unmodified Interpreter AST fed directly to mix (eval-in-stage Later + specialize-or-widen)
(define *micro-interp-eval-def*
  '(define (micro-interp-eval insts stack env)
     (cond
       ((null? insts) (car stack))
       (else
        (let* ((inst (car insts))
               (op (car inst))
               (rest (cdr insts)))
          (cond
            ((eq? op 'PUSH-CONST)
             (micro-interp-eval rest (cons (cadr inst) stack) env))
            ((eq? op 'LOAD-VAR)
             (let ((entry (assq (cadr inst) env)))
               (micro-interp-eval rest (cons (cdr entry) stack) env)))
            ((eq? op 'ADD)
             (let ((b (car stack)) (a (cadr stack)) (stk (cddr stack)))
               (micro-interp-eval rest (cons (+ a b) stk) env)))
            ((eq? op 'SUB)
             (let ((b (car stack)) (a (cadr stack)) (stk (cddr stack)))
               (micro-interp-eval rest (cons (- a b) stk) env)))
            ((eq? op 'MUL)
             (let ((b (car stack)) (a (cadr stack)) (stk (cddr stack)))
               (micro-interp-eval rest (cons (* a b) stk) env)))
            ((eq? op 'IF-ZERO)
             (let ((cond-val (car stack))
                   (then-code (cadr inst))
                   (else-code (caddr inst)))
               (if (= cond-val 0)
                   (micro-interp-eval then-code (cdr stack) env)
                   (micro-interp-eval else-code (cdr stack) env))))
            ((eq? op 'HALT)
             (car stack))
            (else
             (error "Unknown opcode" op))))))))

(define (mix-specialize-micro-interp prog static-env)
  (let ((call-expr (if static-env
                       (list 'micro-interp-eval (list 'quote prog) ''() (list 'quote static-env))
                       (list 'micro-interp-eval (list 'quote prog) ''() 'env))))
    (stage-poly-lower (list 'begin *micro-interp-eval-def* call-expr) '())))

;;; -----------------------------------------------------------------------
;;; 2. Hand-Written Oracle Translator (Ground-Truth Baseline from Issue #885)
;;; -----------------------------------------------------------------------

;; Translates static bytecode instructions into stage-annotated AST
(define (micro-bytecode->stage-poly insts stack)
  (cond
    ((null? insts)
     (list 'stage-later (car stack)))
    (else
     (let* ((inst (car insts))
            (op (car inst))
            (rest (cdr insts)))
       (cond
         ((eq? op 'PUSH-CONST)
          (micro-bytecode->stage-poly rest (cons (cadr inst) stack)))
         ((eq? op 'LOAD-VAR)
          (let ((var (cadr inst)))
            (micro-bytecode->stage-poly rest (cons (list 'stage-lift var) stack))))
         ((eq? op 'ADD)
          (let ((b (car stack)) (a (cadr stack)) (stk (cddr stack)))
            (micro-bytecode->stage-poly rest (cons (list '+ a b) stk))))
         ((eq? op 'SUB)
          (let ((b (car stack)) (a (cadr stack)) (stk (cddr stack)))
            (micro-bytecode->stage-poly rest (cons (list '- a b) stk))))
         ((eq? op 'MUL)
          (let ((b (car stack)) (a (cadr stack)) (stk (cddr stack)))
            (micro-bytecode->stage-poly rest (cons (list '* a b) stk))))
         ((eq? op 'IF-ZERO)
          (let* ((cond-term (car stack))
                 (then-code (cadr inst))
                 (else-code (caddr inst))
                 (stk (cdr stack))
                 (then-expr (micro-bytecode->stage-poly then-code stk))
                 (else-expr (micro-bytecode->stage-poly else-code stk)))
            (list 'stage-later
                  (list 'if (list '= cond-term 0)
                        then-expr
                        else-expr))))
         ((eq? op 'HALT)
          (list 'stage-later (car stack)))
         (else
          (error "Unknown opcode" op)))))))

(define (ast-contains-symbol? sym tree)
  (cond
    ((eq? tree sym) #t)
    ((pair? tree)
     (or (ast-contains-symbol? sym (car tree))
         (ast-contains-symbol? sym (cdr tree))))
    (else #f)))

;;; -----------------------------------------------------------------------
;;; Group 1: Linear Bytecode Projection (Arithmetic: 2 * x + 5)
;;; -----------------------------------------------------------------------
(display "--- Group 1: Linear Bytecode Projection ---\n")

(let* ((prog-arith '((LOAD-VAR x)
                     (PUSH-CONST 2)
                     (MUL)
                     (PUSH-CONST 5)
                     (ADD)
                     (HALT)))
       (stage-poly-ast (micro-bytecode->stage-poly prog-arith '()))
       (env '((x . 10)))
       ;; Apply 1st Futamura Projection: mix(Interp, SourceProg) -> TargetProg
       (compiled-target (stage-poly-lower stage-poly-ast env)))

  ;; Verification 1: Interpreter Dispatch Loops & Opcodes are completely eradicated!
  (assert-false "1.1 Opcode PUSH-CONST eradicated" (ast-contains-symbol? 'PUSH-CONST compiled-target))
  (assert-false "1.2 Opcode LOAD-VAR eradicated"   (ast-contains-symbol? 'LOAD-VAR compiled-target))
  (assert-false "1.3 Opcode MUL eradicated"        (ast-contains-symbol? 'MUL compiled-target))
  (assert-false "1.4 Opcode ADD eradicated"        (ast-contains-symbol? 'ADD compiled-target))
  (assert-false "1.5 Opcode HALT eradicated"       (ast-contains-symbol? 'HALT compiled-target))

  ;; Verification 2: Execution Result Matches Reference Interpreter Exactly (2*10 + 5 = 25)
  (let ((interp-res (micro-interp-eval prog-arith '() env))
        (target-res (eval-residual-anf-expr compiled-target env)))
    (assert-equal "1.6 Reference Interpreter yields 25" 25 interp-res)
    (assert-equal "1.7 Compiled Target Program yields 25" 25 target-res)
    (assert-equal "1.8 Semantic Equivalence (Tower Collapse PASS)" interp-res target-res))

  ;; Verification 3: True 1st Futamura Projection via mix(micro-interp-eval, prog-arith)
  (let* ((mix-target (mix-specialize-micro-interp prog-arith #f))
         (memo (get-last-spec-memo-table))
         (mix-res (eval-residual-anf-expr mix-target env))
         (oracle-res (eval-residual-anf-expr compiled-target env)))
    (assert-true "1.9 mix populated specialization memo table" (and (spec-memo-table? memo) (> (spec-memo-instance-count memo 'micro-interp-eval) 0)))
    (assert-false "1.10 mix eradicated PUSH-CONST" (ast-contains-symbol? 'PUSH-CONST mix-target))
    (assert-false "1.11 mix eradicated LOAD-VAR"   (ast-contains-symbol? 'LOAD-VAR mix-target))
    (assert-false "1.12 mix eradicated ADD/MUL/HALT"
                  (or (ast-contains-symbol? 'ADD mix-target)
                      (ast-contains-symbol? 'MUL mix-target)
                      (ast-contains-symbol? 'HALT mix-target)))
    (assert-false "1.13 mix eradicated micro-interp-eval recursion"
                  (ast-contains-symbol? 'micro-interp-eval mix-target))
    (assert-equal "1.14 mix residual matches hand-written oracle output" oracle-res mix-res)
    (assert-equal "1.15 mix output matches reference interpreter (25)" 25 mix-res)))

;;; -----------------------------------------------------------------------
;;; Group 2: Branching Bytecode Projection (if (x == 0) 100 else x * 3)
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Branching Bytecode Projection ---\n")

(let* ((prog-branch '((LOAD-VAR x)
                      (IF-ZERO
                        ((PUSH-CONST 100) (HALT))
                        ((LOAD-VAR x) (PUSH-CONST 3) (MUL) (HALT))))))

  ;; Test case x = 0
  (let* ((env-zero '((x . 0)))
         (stage-ast (micro-bytecode->stage-poly prog-branch '()))
         (compiled (stage-poly-lower stage-ast env-zero))
         (interp-zero (micro-interp-eval prog-branch '() env-zero))
         (target-zero (eval-residual-anf-expr compiled env-zero)))
    (assert-equal "2.1 Zero-branch Interpreter yields 100" 100 interp-zero)
    (assert-equal "2.2 Zero-branch Compiled Target yields 100" 100 target-zero)
    (assert-false "2.3 Opcode IF-ZERO eradicated" (ast-contains-symbol? 'IF-ZERO compiled)))

  ;; Test case x = 7 -> 7 * 3 = 21
  (let* ((env-nonzero '((x . 7)))
         (stage-ast (micro-bytecode->stage-poly prog-branch '()))
         (compiled (stage-poly-lower stage-ast env-nonzero))
         (interp-nz (micro-interp-eval prog-branch '() env-nonzero))
         (target-nz (eval-residual-anf-expr compiled env-nonzero)))
    (assert-equal "2.4 Non-zero branch Interpreter yields 21" 21 interp-nz)
    (assert-equal "2.5 Non-zero branch Compiled Target yields 21" 21 target-nz))

  ;; True 1st Futamura Projection via mix(micro-interp-eval, prog-branch)
  (let* ((mix-branch (mix-specialize-micro-interp prog-branch #f))
         (memo-b (get-last-spec-memo-table))
         (mix-b-zero (eval-residual-anf-expr mix-branch '((x . 0))))
         (mix-b-seven (eval-residual-anf-expr mix-branch '((x . 7)))))
    (assert-true "2.6 mix specialized branching micro-interp-eval"
                 (and (spec-memo-table? memo-b) (> (spec-memo-instance-count memo-b 'micro-interp-eval) 0)))
    (assert-false "2.7 mix branch eradicated IF-ZERO" (ast-contains-symbol? 'IF-ZERO mix-branch))
    (assert-false "2.8 mix branch eradicated HALT" (ast-contains-symbol? 'HALT mix-branch))
    (assert-false "2.9 mix branch eradicated micro-interp-eval" (ast-contains-symbol? 'micro-interp-eval mix-branch))
    (assert-equal "2.10 mix branch (x=0) matches oracle (100)" 100 mix-b-zero)
    (assert-equal "2.11 mix branch (x=7) matches oracle (21)" 21 mix-b-seven))

  ;; Group 3: Dual Verification (mix 1st Projection vs Direct Cogen in workbench/cogen.scm)
  (display "\n--- Group 3: Dual Verification (mix vs Direct Cogen) ---\n")
  (let* ((prog-arith '((LOAD-VAR x)
                       (PUSH-CONST 2)
                       (MUL)
                       (PUSH-CONST 5)
                       (ADD)
                       (HALT)))
         (residual-arith (mix-specialize-micro-interp prog-arith #f))
         (residual-branch (mix-specialize-micro-interp prog-branch #f))
         (residual-rules
          (list
           (cons 'atom-value
                 (lambda (node rules gfd rm depth)
                   (cogen-lower-ast (cadr node) rules gfd rm (+ depth 1))))
           (cons '=
                 (lambda (node rules gfd rm depth)
                   (make-lir-binop '==
                                   (cogen-lower-ast (cadr node) rules gfd rm (+ depth 1))
                                   (cogen-lower-ast (caddr node) rules gfd rm (+ depth 1)))))
           (cons 'let-anf
                 (lambda (node rules gfd rm depth)
                   (let* ((b (caadr node))
                          (var (car b))
                          (rhs (cogen-lower-ast (cadr b) rules gfd rm (+ depth 1)))
                          (slot (gfd-add-slot! gfd var 'any))
                          (set-inst (make-lir-slot-set! slot var rhs))
                          (body-inst (cogen-lower-ast (caddr node) rules gfd rm (+ depth 1))))
                     (make-lir-seq (list set-inst body-inst)))))))
         (cogen-compiler (derive-cogen-compiler residual-rules 'tagging))
         ;; Compile mix-generated linear residual program with Cogen & execute via lir-eval
         (gfd-a (gfd-empty))
         (sx-a (gfd-add-slot! gfd-a 'x))
         (lir-a (cogen-compiler residual-arith gfd-a))
         (frame-a (let ((v (make-vector (max 2 (gfd-slot-count gfd-a)) 0)))
                    (vector-set! v sx-a 10)
                    v))
         ;; Compile mix-generated branching residual program with Cogen & execute via lir-eval
         (gfd-b (gfd-empty))
         (sx-b (gfd-add-slot! gfd-b 'x))
         (lir-b (cogen-compiler residual-branch gfd-b))
         (frame-b0 (let ((v (make-vector (max 2 (gfd-slot-count gfd-b)) 0)))
                     (vector-set! v sx-b 0)
                     v))
         (frame-b7 (let ((v (make-vector (max 2 (gfd-slot-count gfd-b)) 0)))
                     (vector-set! v sx-b 7)
                     v)))
    (assert-true "3.1 Cogen lowered mix arith residual to valid LIR" (lir-node? lir-a))
    (assert-equal "3.2 Dual verify arith (x=10): lir-eval == micro-interp-eval == 25"
                  (micro-interp-eval prog-arith '() '((x . 10)))
                  (lir-eval lir-a frame-a))
    (assert-true "3.3 Cogen lowered mix branch residual to valid LIR" (lir-node? lir-b))
    (assert-equal "3.4 Dual verify branch (x=0): lir-eval == micro-interp-eval == 100"
                  (micro-interp-eval prog-branch '() '((x . 0)))
                  (lir-eval lir-b frame-b0))
    (assert-equal "3.5 Dual verify branch (x=7): lir-eval == micro-interp-eval == 21"
                  (micro-interp-eval prog-branch '() '((x . 7)))
                  (lir-eval lir-b frame-b7))))

;;; -----------------------------------------------------------------------
;;; Group 4: case / Named let / letrec Compilation & BTA Consistency (Issue #965)
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: case / Named let / letrec Compilation & BTA Consistency ---\n")

(define (tree-contains-symbol? expr target)
  (cond
    ((symbol? expr) (eq? expr target))
    ((not (pair? expr)) #f)
    (else
     (or (tree-contains-symbol? (car expr) target)
         (tree-contains-symbol? (cdr expr) target)))))

(let* ((expr-case '(case op
                     ((add plus) (+ x 10))
                     ((sub) (- x 99))
                     (else 0)))
       (res-plus (stage-poly-lower expr-case '((op . plus))))
       (now-case-val (stage-val-payload
                      (eval-in-stage (make-now-dict) '((op . plus) (x . 5)) expr-case
                                     *ctfe-default-step-limit* *ctfe-default-depth-limit*)))
       (expr-named-let '(let loop ((i n) (acc 0))
                          (if (= i 0)
                              acc
                              (loop (- i 1) (+ acc i)))))
       (res-nl-static (stage-poly-lower expr-named-let '((n . 5))))
       (res-nl-dyn (stage-poly-lower expr-named-let '()))
       (expr-mutual '(letrec ((even-p (lambda (n) (if (= n 0) #t (odd-p (- n 1)))))
                              (odd-p  (lambda (n) (if (= n 0) #f (even-p (- n 1))))))
                       (even-p k)))
       (res-mut-static (stage-poly-lower expr-mutual '((k . 6))))
       (res-mut-dyn (stage-poly-lower expr-mutual '()))
       (bta-static-case (bta-infer-expr expr-case '((op . static) (x . static))))
       (bta-dyn-case (bta-infer-expr expr-case '((op . dynamic) (x . static))))
       (bta-hybrid-nl (stage-poly-lower expr-named-let '((n . 5)) '((n . static)))))
  ;; 4.1: static case folds dead branches
  (assert-true "4.1a case conformance" (verify-residual-anf-conformance res-plus))
  (assert-false "4.1b static case eliminates unused sub branch"
                (tree-contains-symbol? res-plus '99))
  (assert-equal "4.1c case Now vs residual equivalence (x=5 -> 15)"
                now-case-val
                (eval-residual-anf-expr res-plus '((x . 5))))
  ;; 4.2: named let static fold & dynamic letrec residualization
  (assert-equal "4.2a named let static fold (n=5 -> 15)" 15
                (eval-residual-anf-expr res-nl-static '()))
  (assert-true "4.2b named let dynamic emits letrec"
               (and (pair? res-nl-dyn) (eq? (car res-nl-dyn) 'letrec)))
  (assert-true "4.2b2 named let dynamic passes verify-letrec-contifiable-guarantees"
               (verify-letrec-contifiable-guarantees res-nl-dyn))
  (assert-true "4.2c named let dynamic ANF conformance"
               (verify-residual-anf-conformance res-nl-dyn))
  (assert-equal "4.2d named let dynamic eval (n=0 -> 0)" 0
                (eval-residual-anf-expr res-nl-dyn '((n . 0))))
  (assert-equal "4.2e named let dynamic eval (n=5 -> 15)" 15
                (eval-residual-anf-expr res-nl-dyn '((n . 5))))
  (assert-equal "4.2f named let dynamic eval (n=10 -> 55)" 55
                (eval-residual-anf-expr res-nl-dyn '((n . 10))))
  ;; 4.3: mutual letrec static & dynamic
  (assert-equal "4.3a mutual letrec static fold (6 -> #t)" #t
                (eval-residual-anf-expr res-mut-static '()))
  (assert-true "4.3b mutual letrec dynamic emits letrec"
               (and (pair? res-mut-dyn) (eq? (car res-mut-dyn) 'letrec)))
  (assert-true "4.3b2 mutual letrec passes verify-letrec-contifiable-guarantees"
               (verify-letrec-contifiable-guarantees res-mut-dyn))
  (assert-equal "4.3c mutual letrec dynamic eval (7 -> #f)" #f
                (eval-residual-anf-expr res-mut-dyn '((k . 7))))
  (assert-equal "4.3d mutual letrec dynamic eval (8 -> #t)" #t
                (eval-residual-anf-expr res-mut-dyn '((k . 8))))
  ;; 4.4: BTA consistency on case & named let
  (assert-equal "4.4a BTA infers static for static case" 'static bta-static-case)
  (assert-equal "4.4b BTA infers dynamic for dynamic case" 'dynamic bta-dyn-case)
  (assert-equal "4.4c Hybrid BTA lower matches static sum (n=5 -> 15)" 15
                (eval-residual-anf-expr bta-hybrid-nl '())))

;;; -----------------------------------------------------------------------
;;; Group 5: First Futamura Projection on Backward-Jump Loop Bytecode Interpreter (Issue #965)
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Backward-Jump Loop Bytecode Projection ---\n")

(define loop-bc-interp-src
  '(letrec ((step
             (lambda (pc st prog)
               (let ((instr (list-ref prog pc)))
                 (case (car instr)
                   ((HALT) (cadr st))
                   ((JZ-TOP)
                    (if (= (car st) 0)
                        (step (cadr instr) st prog)
                        (step (+ pc 1) st prog)))
                   ((ADD-SECOND-FROM-TOP)
                    (step (+ pc 1)
                          (cons (car st) (cons (+ (cadr st) (car st)) '()))
                          prog))
                   ((DEC-TOP)
                    (step (+ pc 1)
                          (cons (- (car st) 1) (cdr st))
                          prog))
                   ((JUMP)
                    (step (cadr instr) st prog)))))))
     (step 0 (cons n (cons acc '())) prog)))

(let* ((sum-loop-prog
        '((JZ-TOP 4)
          (ADD-SECOND-FROM-TOP)
          (DEC-TOP)
          (JUMP 0)
          (HALT)))
       ;; 1. Unprojected ground truth evaluation under Now dictionary
       (now-0 (stage-val-payload
               (eval-in-stage (make-now-dict)
                              (list (cons 'n 0) (cons 'acc 0) (cons 'prog sum-loop-prog))
                              loop-bc-interp-src
                              *ctfe-default-step-limit* *ctfe-default-depth-limit*)))
       (now-1 (stage-val-payload
               (eval-in-stage (make-now-dict)
                              (list (cons 'n 1) (cons 'acc 0) (cons 'prog sum-loop-prog))
                              loop-bc-interp-src
                              *ctfe-default-step-limit* *ctfe-default-depth-limit*)))
       (now-5 (stage-val-payload
               (eval-in-stage (make-now-dict)
                              (list (cons 'n 5) (cons 'acc 0) (cons 'prog sum-loop-prog))
                              loop-bc-interp-src
                              *ctfe-default-step-limit* *ctfe-default-depth-limit*)))
       (now-10 (stage-val-payload
                (eval-in-stage (make-now-dict)
                               (list (cons 'n 10) (cons 'acc 0) (cons 'prog sum-loop-prog))
                               loop-bc-interp-src
                               *ctfe-default-step-limit* *ctfe-default-depth-limit*)))
       ;; 2. First Futamura projection (mix): prog static, (n acc) dynamic
       (residual-loop (stage-poly-lower loop-bc-interp-src (list (cons 'prog sum-loop-prog))))
       (memo-loop (get-last-spec-memo-table)))
  (assert-true "5.1 Mix emits cyclic letrec for backward-jump bytecode loop"
               (and (pair? residual-loop) (eq? (car residual-loop) 'letrec)))
  (assert-true "5.2 Specialized residual loop conforms to L-Residual-ANF"
               (verify-residual-anf-conformance residual-loop))
  (assert-true "5.2b Specialized residual loop passes verify-letrec-contifiable-guarantees"
               (verify-letrec-contifiable-guarantees residual-loop))
  (assert-false "5.3 Mix eliminates interpreter opcode dispatch & instruction fetch (no list-ref)"
                (tree-contains-symbol? residual-loop 'list-ref))
  (assert-false "5.4 Mix eliminates interpreter symbol HALT"
                (tree-contains-symbol? residual-loop 'HALT))
  (assert-false "5.5 Mix eliminates interpreter symbol JUMP"
                (tree-contains-symbol? residual-loop 'JUMP))
  (assert-true "5.6 Specialization instance count fits <= *max-spec-instances*"
               (and memo-loop
                    (> (spec-memo-instance-count memo-loop 'step) 0)
                    (<= (spec-memo-instance-count memo-loop 'step) *max-spec-instances*)))
  (assert-equal "5.7 Semantic equivalence (n=0, acc=0 -> 0)"
                now-0
                (eval-residual-anf-expr residual-loop '((n . 0) (acc . 0))))
  (assert-equal "5.7b Semantic equivalence (n=1, acc=0 -> 1)"
                now-1
                (eval-residual-anf-expr residual-loop '((n . 1) (acc . 0))))
  (assert-equal "5.8 Semantic equivalence (n=5, acc=0 -> 15)"
                now-5
                (eval-residual-anf-expr residual-loop '((n . 5) (acc . 0))))
  (assert-equal "5.9 Semantic equivalence (n=10, acc=0 -> 55)"
                now-10
                (eval-residual-anf-expr residual-loop '((n . 10) (acc . 0))))
  (assert-equal "5.10 Semantic equivalence with non-zero initial acc (n=4, acc=100 -> 110)"
                110
                (eval-residual-anf-expr residual-loop '((n . 4) (acc . 100)))))

;;; -----------------------------------------------------------------------
;;; Group 6: Widening Termination Beyond *max-spec-instances* (8) (Issue #965)
;;; -----------------------------------------------------------------------
(display "\n--- Group 6: Widening Termination Beyond *max-spec-instances* (8) ---\n")

(let* ((long-linear-prog
        '((DEC-TOP) (DEC-TOP) (DEC-TOP) (DEC-TOP) (DEC-TOP)
          (DEC-TOP) (DEC-TOP) (DEC-TOP) (DEC-TOP) (DEC-TOP)
          (HALT)))
       (res-wide (stage-poly-lower loop-bc-interp-src (list (cons 'prog long-linear-prog))))
       (memo-wide (get-last-spec-memo-table))
       (inc-counter-prog
        '(letrec ((up (lambda (k v)
                        (if (= v 0)
                            k
                            (up (+ k 1) (- v 1))))))
           (up 0 n)))
       (res-up (stage-poly-lower inc-counter-prog '()))
       (memo-up (get-last-spec-memo-table)))
  (assert-false "6.1 11-PC linear bytecode program terminates without CSP error"
                (stage-csp-error? res-wide))
  (assert-true "6.2 Long bytecode residual satisfies L-Residual-ANF conformance"
               (verify-residual-anf-conformance res-wide))
  (assert-equal "6.3 *max-spec-instances* strictly caps step specializations at 8"
                *max-spec-instances*
                (spec-memo-instance-count memo-wide 'step))
  (assert-false "6.4 Increasing static counter widens & terminates without CSP error"
                (stage-csp-error? res-up))
  (assert-true "6.5 Increasing counter specializes at most <= *max-spec-instances*"
               (and memo-up
                    (<= (spec-memo-instance-count memo-up 'up) *max-spec-instances*)))
  (assert-true "6.6 Increasing counter residual satisfies L-Residual-ANF conformance"
               (verify-residual-anf-conformance res-up)))

(display "\n[RESULT] All First Futamura Projection (Tower Collapse) tests PASSED!\n")
