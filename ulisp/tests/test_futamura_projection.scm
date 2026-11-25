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

;;; -----------------------------------------------------------------------
;;; Group 7 & Group 8: First Futamura Projection on Direct-Style PEG Interpreter
;;; vs emit_scheme.scm (Issue #950)
;;; -----------------------------------------------------------------------

(define (%peg950-cc-spec->items spec)
  (let* ((tokens (%tokenize-char-class-spec spec))
         (ranges
          (let loop ((ts tokens) (acc '()))
            (cond
              ((null? ts) (reverse acc))
              ((and (pair? (cdr ts))
                    (pair? (cddr ts))
                    (eq? (caadr ts) 'raw)
                    (char=? (cdadr ts) #\-))
               (loop (cdddr ts)
                     (cons (list 'range (cdar ts) (cdaddr ts)) acc)))
              (else
               (loop (cdr ts)
                     (cons (list 'single (cdar ts)) acc)))))))
    ranges))

(define (%peg950-fold-right-bin tag items empty-val)
  (cond
    ((null? items) empty-val)
    ((null? (cdr items)) (car items))
    (else (list tag (car items) (%peg950-fold-right-bin tag (cdr items) empty-val)))))

(define (%peg950-string->seq str)
  (let ((len (string-length str)))
    (if (= len 0)
        'eps
        (let loop ((i (- len 1)) (acc #f))
          (if (< i 0)
              acc
              (let ((cnode (list 'char (string-ref str i))))
                (loop (- i 1) (if acc (list 'seq cnode acc) cnode))))))))

(define (%peg950-ast-expr->stage-expr expr)
  (cond
    ((peg-lit-expr? expr)
     (%peg950-string->seq (peg-lit-expr-val expr)))
    ((peg-char-class-expr? expr)
     (cons 'char-class
           (cons (peg-char-class-expr-inverted? expr)
                 (%peg950-cc-spec->items (peg-char-class-expr-spec expr)))))
    ((peg-any-char-expr? expr)
     'any-char)
    ((peg-regex-expr? expr)
     (let* ((pat (peg-regex-expr-pattern expr))
            (rk (%emit-regex-kind pat)))
       (cond
         ((eq? rk 'any-char) 'any-char)
         ((and (pair? rk) (eq? (car rk) 'cc))
          (let* ((kind (cadr rk))
                 (spec (caddr rk))
                 (inv? (cadddr rk))
                 (cc-node (cons 'char-class (cons inv? (%peg950-cc-spec->items spec)))))
            (cond
              ((eq? kind 'plus) (list 'plus cc-node))
              ((eq? kind 'star) (list 'star cc-node))
              (else cc-node))))
         (else
          (%peg950-string->seq pat)))))
    ((peg-seq-expr? expr)
     (%peg950-fold-right-bin
      'seq
      (map %peg950-ast-expr->stage-expr (peg-seq-expr-elements expr))
      'eps))
    ((peg-choice-expr? expr)
     (%peg950-fold-right-bin
      'choice
      (map %peg950-ast-expr->stage-expr (peg-choice-expr-alternatives expr))
      '(pred-not eps)))
    ((peg-repeat-expr? expr)
     (let ((inner (%peg950-ast-expr->stage-expr (peg-repeat-expr-expr expr))))
       (if (= (peg-repeat-expr-min-count expr) 1)
           (list 'plus inner)
           (list 'star inner))))
    ((peg-opt-expr? expr)
     (list 'opt (%peg950-ast-expr->stage-expr (peg-opt-expr-expr expr))))
    ((peg-pred-expr? expr)
     (let ((inner (%peg950-ast-expr->stage-expr (peg-pred-expr-expr expr))))
       (if (peg-pred-expr-positive? expr)
           (list 'pred-and inner)
           (list 'pred-not inner))))
    ((peg-rule-ref-expr? expr)
     (list 'rule-ref (peg-rule-ref-expr-name expr)))
    ((peg-named-expr? expr)
     (%peg950-ast-expr->stage-expr (peg-named-expr-expr expr)))
    ((peg-action-expr? expr)
     (%peg950-ast-expr->stage-expr (peg-action-expr-expr expr)))
    (else
     (error "Unsupported PEG AST node for futamura staging" expr))))

(define (peg950-grammar-ast->stage-rules grammar)
  (map (lambda (r)
         (cons (peg-rule-def-name r)
               (%peg950-ast-expr->stage-expr (peg-rule-def-expr r))))
       (peg-grammar-def-rules grammar)))

;; Unmodified Direct-Style PEG Interpreter passed directly to mix (stage-poly-lower)
(define *peg950-match-cc-def*
  '(define (peg-match-cc items inv? ch)
     (if (null? items)
         inv?
         (let ((item (car items)))
           (if (eq? (car item) 'range)
               (if (and (char>=? ch (cadr item))
                        (char<=? ch (caddr item)))
                   (not inv?)
                   (peg-match-cc (cdr items) inv? ch))
               (if (char=? ch (cadr item))
                   (not inv?)
                   (peg-match-cc (cdr items) inv? ch)))))))

(define *peg950-interp-expr-def*
  '(define (peg-interp-expr expr rules text len pos)
     (if (symbol? expr)
         (if (eq? expr 'eps)
             pos
             (if (< pos len) (+ pos 1) -1))
         (case (car expr)
           ((char)
            (if (< pos len)
                (if (char=? (string-ref text pos) (cadr expr))
                    (+ pos 1)
                    -1)
                -1))
           ((char-class)
            (if (< pos len)
                (if (peg-match-cc (cddr expr) (cadr expr) (string-ref text pos))
                    (+ pos 1)
                    -1)
                -1))
           ((seq)
            (let ((p1 (peg-interp-expr (cadr expr) rules text len pos)))
              (if (< p1 0)
                  -1
                  (peg-interp-expr (caddr expr) rules text len p1))))
           ((choice)
            (let ((p1 (peg-interp-expr (cadr expr) rules text len pos)))
              (if (< p1 0)
                  (peg-interp-expr (caddr expr) rules text len pos)
                  p1)))
           ((opt)
            (let ((p1 (peg-interp-expr (cadr expr) rules text len pos)))
              (if (< p1 0) pos p1)))
           ((star)
            (let loop ((cur pos))
              (let ((nxt (peg-interp-expr (cadr expr) rules text len cur)))
                (if (> nxt cur)
                    (loop nxt)
                    cur))))
           ((plus)
            (let ((first-p (peg-interp-expr (cadr expr) rules text len pos)))
              (if (< first-p 0)
                  -1
                  (if (<= first-p pos)
                      first-p
                      (let loop ((cur first-p))
                        (let ((nxt (peg-interp-expr (cadr expr) rules text len cur)))
                          (if (> nxt cur)
                              (loop nxt)
                              cur)))))))
           ((pred-and)
            (let ((p1 (peg-interp-expr (cadr expr) rules text len pos)))
              (if (< p1 0) -1 pos)))
           ((pred-not)
            (let ((p1 (peg-interp-expr (cadr expr) rules text len pos)))
              (if (< p1 0) pos -1)))
           ((rule-ref)
            (let ((entry (assq (cadr expr) rules)))
              (if entry
                  (peg-interp-expr (cdr entry) rules text len pos)
                  -1)))
           (else -1)))))

(define (peg950-mix-stage-grammar rules start-rule)
  (let* ((start-entry (assq start-rule rules))
         (start-expr (if start-entry (cdr start-entry) (error "Unknown start rule" start-rule)))
         (call-expr (list 'peg-interp-expr
                          (list 'quote start-expr)
                          (list 'quote rules)
                          'text 'len 'pos)))
    (with-spec-limits
     256 64 500000 1024
     (lambda ()
       (stage-poly-lower
        (list 'begin *peg950-match-cc-def* *peg950-interp-expr-def* call-expr)
        '())))))

(define (peg950-eval-now rules start-rule inp)
  (let* ((start-entry (assq start-rule rules))
         (start-expr (cdr start-entry))
         (call-expr (list 'peg-interp-expr
                          (list 'quote start-expr)
                          (list 'quote rules)
                          'text 'len 'pos))
         (sv (eval-in-stage
              (make-now-dict)
              (list (cons 'text inp) (cons 'len (string-length inp)) (cons 'pos 0))
              (list 'begin *peg950-match-cc-def* *peg950-interp-expr-def* call-expr)
              500000 1024)))
    (if (stage-csp-error? sv)
        (error "Now PEG evaluation hit CSP error" sv)
        (stage-val-payload sv))))

(define (peg950-eval-residual residual-parser inp)
  (eval-residual-anf-expr
   residual-parser
   (list (cons 'text inp) (cons 'len (string-length inp)) (cons 'pos 0))))

(define (peg950-assert-evaporation label residual-ast)
  (assert-false (string-append label " has no CSP error")
                (stage-csp-error? residual-ast))
  (assert-true (string-append label " conforms to L-Residual-ANF")
               (verify-residual-anf-conformance residual-ast))
  (assert-true (string-append label " passes verify-letrec-contifiable-guarantees")
               (verify-letrec-contifiable-guarantees residual-ast))
  (for-each
   (lambda (sym)
     (assert-false (string-append label " evaporates PEG AST/dispatch symbol: " (symbol->string sym))
                   (tree-contains-symbol? residual-ast sym)))
   '(eps any-char char char-class range single seq choice star plus opt
     pred-and pred-not rule-ref assq peg-match-cc peg-interp-expr)))

(define (peg950-assert-dual-verification label rules start-rule residual-parser ds-parse-partial ds-parse inputs)
  (for-each
   (lambda (inp)
     (let* ((now-pos (peg950-eval-now rules start-rule inp))
            (mix-pos (peg950-eval-residual residual-parser inp))
            (ds-part (ds-parse-partial inp))
            (ds-pos  (if ds-part (cdr ds-part) -1))
            (len     (string-length inp))
            (now-full? (and (>= now-pos 0) (= now-pos len)))
            (mix-full? (and (>= mix-pos 0) (= mix-pos len)))
            (ds-full?  (and ds-part (= ds-pos len))))
       (assert-equal (string-append label " Now == mix [pos: " inp "]") now-pos mix-pos)
       (assert-equal (string-append label " mix == emit_scheme [pos: " inp "]") ds-pos mix-pos)
       (assert-equal (string-append label " Now == emit_scheme [full?: " inp "]") now-full? ds-full?)
       (assert-equal (string-append label " mix == emit_scheme [full?: " inp "]") mix-full? ds-full?)
       (if ds-full?
           (assert-true (string-append label " emit_scheme full parse succeeds: " inp)
                        (begin (ds-parse inp) #t)))))
   inputs))

(define (%peg950-write-and-load! path code-str)
  (call-with-output-file path
    (lambda (port)
      (display code-str port)))
  (load path))

(display "\n--- Group 7: calc.peg First Futamura Projection (mix) vs emit_scheme.scm ---\n")

(let* ((calc-ast (parse-peg-grammar (read-all-file-text "../tools/grammars/calc.peg")))
       (calc-rules (peg950-grammar-ast->stage-rules calc-ast))
       (calc-residual (peg950-mix-stage-grammar calc-rules 'expr))
       (calc-scm (emit-peg-grammar->scheme calc-ast '((prefix . "fcalc950-") (entry . expr)))))
  (%peg950-write-and-load! "build/test_emit_scm/_futamura950_calc.scm" calc-scm)
  (peg950-assert-evaporation "calc.peg" calc-residual)
  (peg950-assert-dual-verification
   "calc.peg"
   calc-rules
   'expr
   calc-residual
   (eval 'fcalc950-parse-partial (interaction-environment))
   (eval 'fcalc950-parse (interaction-environment))
   '("42"
     "0"
     "1 + 2"
     "10 + 20 * 3"
     "(10 + 20) * 3"
     "((7 - 2) / 5) + 9 * 10"
     "  123 + 456  "
     "10 + 20 abc"
     "1 +"
     "(10 + 20"
     "bad"
     "")))

(display "\n--- Group 8: cti_ql.peg First Futamura Projection (mix) vs emit_scheme.scm ---\n")

(define (%peg950-cti-attach-ws expr)
  (cond
    ((peg-lit-expr? expr)
     (make-peg-seq-expr (list expr (make-peg-rule-ref-expr 'ws))))
    ((peg-seq-expr? expr)
     (make-peg-seq-expr (map %peg950-cti-attach-ws (peg-seq-expr-elements expr))))
    ((peg-choice-expr? expr)
     (make-peg-choice-expr (map %peg950-cti-attach-ws (peg-choice-expr-alternatives expr))))
    ((peg-repeat-expr? expr)
     (make-peg-repeat-expr (%peg950-cti-attach-ws (peg-repeat-expr-expr expr))
                           (peg-repeat-expr-min-count expr)
                           (peg-repeat-expr-max-count expr)))
    ((peg-opt-expr? expr)
     (make-peg-opt-expr (%peg950-cti-attach-ws (peg-opt-expr-expr expr))))
    ((peg-pred-expr? expr)
     (make-peg-pred-expr (%peg950-cti-attach-ws (peg-pred-expr-expr expr))
                         (peg-pred-expr-positive? expr)))
    (else expr)))

(define (%peg950-build-cti-ql-ast raw-ast)
  (let* ((raw-rules (peg-grammar-def-rules raw-ast))
         (_ (for-each
             (lambda (req)
               (assert-true (string-append "cti_ql.peg defines rule " (symbol->string req))
                            (let loop ((rs raw-rules))
                              (cond ((null? rs) #f)
                                    ((eq? (peg-rule-def-name (car rs)) req) #t)
                                    (else (loop (cdr rs)))))))
             '(query expr term factor predicate field_name op_cmp literal_val)))
         (updated-rules
          (map (lambda (r)
                 (let ((rname (peg-rule-def-name r))
                       (rexpr (peg-rule-def-expr r)))
                   (if (eq? rname 'query)
                       (make-peg-rule-def
                        rname
                        (make-peg-seq-expr
                         (list (make-peg-rule-ref-expr 'ws) rexpr))
                        (peg-rule-def-memoize? r)
                        (peg-rule-def-return-type r))
                       (make-peg-rule-def
                        rname
                        (%peg950-cti-attach-ws rexpr)
                        (peg-rule-def-memoize? r)
                        (peg-rule-def-return-type r)))))
               raw-rules))
         (token-rules
          (list
           (make-peg-rule-def
            'ws
            (make-peg-repeat-expr (make-peg-char-class-expr " \\t" #f) 0 #f)
            #f #f)
           (make-peg-rule-def
            'NEWLINE
            (make-peg-choice-expr
             (list (make-peg-seq-expr (list (make-peg-lit-expr "\r") (make-peg-lit-expr "\n")))
                   (make-peg-lit-expr "\n")
                   (make-peg-lit-expr "\r")))
            #f #f)
           (make-peg-rule-def
            'ENDMARKER
            (make-peg-pred-expr (make-peg-any-char-expr) #f)
            #f #f)
           (make-peg-rule-def
            'STRING
            (make-peg-seq-expr
             (list (make-peg-lit-expr "\"")
                   (make-peg-repeat-expr (make-peg-char-class-expr "\"\\r\\n" #t) 0 #f)
                   (make-peg-lit-expr "\"")
                   (make-peg-rule-ref-expr 'ws)))
            #t #f)
           (make-peg-rule-def
            'NUMBER
            (make-peg-seq-expr
             (list (make-peg-repeat-expr (make-peg-char-class-expr "0-9" #f) 1 #f)
                   (make-peg-opt-expr
                    (make-peg-seq-expr
                     (list (make-peg-lit-expr ".")
                           (make-peg-repeat-expr (make-peg-char-class-expr "0-9" #f) 1 #f))))
                   (make-peg-rule-ref-expr 'ws)))
            #t #f))))
    (make-peg-grammar-def
     (peg-grammar-def-name raw-ast)
     (append updated-rules token-rules)
     (peg-grammar-def-directives raw-ast))))

(let* ((cti-raw-ast (parse-peg-grammar (read-all-file-text "workbench/examples/cti_ql.peg")))
       (cti-ast (%peg950-build-cti-ql-ast cti-raw-ast))
       (cti-rules (peg950-grammar-ast->stage-rules cti-ast))
       (cti-residual (peg950-mix-stage-grammar cti-rules 'query))
       (cti-scm (emit-peg-grammar->scheme cti-ast '((prefix . "fcti950-") (entry . query)))))
  (%peg950-write-and-load! "build/test_emit_scm/_futamura950_cti_ql.scm" cti-scm)
  (peg950-assert-evaporation "cti_ql.peg" cti-residual)
  (peg950-assert-dual-verification
   "cti_ql.peg"
   cti-rules
   'query
   cti-residual
   (eval 'fcti950-parse-partial (interaction-environment))
   (eval 'fcti950-parse (interaction-environment))
   '("threat == \"ransomware\""
     "cve-score >= 8"
     "cve-score >= 8.5\n"
     "port == 443 AND threat != \"benign\""
     "ip-addr == \"10.0.0.1\" OR ip == \"192.168.1.1\""
     "(threat == \"ransomware\" OR cve > 7) AND port <= 1024"
     "threat == \"unclosed"
     "threat == 123 AND"
     "unknown_field == 1"
     "port == 80 GARBAGE"
     "(port == 80"
     "")))

(display "\n[RESULT] All First Futamura Projection (Tower Collapse + PEG Staging) tests PASSED!\n")
