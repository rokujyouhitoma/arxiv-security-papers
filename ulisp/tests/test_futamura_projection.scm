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

(display "\n[RESULT] All First Futamura Projection (Tower Collapse) tests PASSED!\n")
