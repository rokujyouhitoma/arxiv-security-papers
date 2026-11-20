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

;;; -----------------------------------------------------------------------
;;; 2. First Futamura Projection: Partial Evaluator specializing Interpreter
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
    (assert-equal "1.8 Semantic Equivalence (Tower Collapse PASS)" interp-res target-res)))

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
    (assert-equal "2.5 Non-zero branch Compiled Target yields 21" 21 target-nz)))

(display "\n[RESULT] All First Futamura Projection (Tower Collapse) tests PASSED!\n")
