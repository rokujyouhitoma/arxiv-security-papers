;;; =======================================================================
;;; Test Suite: Language Workbench Guest Frame Descriptor & Slot Lowering
;;; Conforms to DSN-33-04 §2.1 & §2.2, Issue #892
;;; =======================================================================

(display "\n=== [Test Suite: Language Workbench Guest Frame Descriptor (Issue #892)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; Group 1: Basic FrameDescriptor Operations & Slot Resolution
;;; -----------------------------------------------------------------------

(display "--- Group 1: Basic FrameDescriptor API ---\n")

(let ((gfd (gfd-empty)))
  (assert-equal "initial count is 0" 0 (gfd-slot-count gfd))
  (assert-true "empty descriptor is guest-frame-descriptor" (guest-frame-descriptor? gfd))

  (let ((idx-x (gfd-add-slot! gfd 'x 'fixnum))
        (idx-y (gfd-add-slot! gfd 'y 'any))
        (idx-z (gfd-add-slot! gfd 'z 'fixnum)))
    (assert-equal "idx x is 0" 0 idx-x)
    (assert-equal "idx y is 1" 1 idx-y)
    (assert-equal "idx z is 2" 2 idx-z)
    (assert-equal "slot count is 3" 3 (gfd-slot-count gfd))

    ;; Idempotent add returns existing index
    (assert-equal "re-adding x returns 0" 0 (gfd-add-slot! gfd 'x))
    (assert-equal "count remains 3" 3 (gfd-slot-count gfd))

    ;; Lookup
    (assert-equal "lookup x" 0 (gfd-lookup-slot gfd 'x))
    (assert-equal "lookup y" 1 (gfd-lookup-slot gfd 'y))
    (assert-equal "lookup z" 2 (gfd-lookup-slot gfd 'z))
    (assert-false "lookup non-existent w" (gfd-lookup-slot gfd 'w))

    ;; Name and type inspection
    (assert-equal "name of slot 0 is x" 'x (gfd-slot-name gfd 0))
    (assert-equal "name of slot 1 is y" 'y (gfd-slot-name gfd 1))
    (assert-equal "name of slot 2 is z" 'z (gfd-slot-name gfd 2))
    (assert-equal "type of slot 0 is fixnum" 'fixnum (gfd-slot-type gfd 0))
    (assert-equal "type of slot 1 is any" 'any (gfd-slot-type gfd 1))

    ;; Escape marking
    (assert-false "slot 0 does not escape initially" (gfd-escapes? gfd 0))
    (assert-false "slot 1 does not escape initially" (gfd-escapes? gfd 1))
    (assert-false "slot 2 does not escape initially" (gfd-escapes? gfd 2))

    (gfd-mark-escape! gfd 1)
    (assert-false "slot 0 still does not escape" (gfd-escapes? gfd 0))
    (assert-true "slot 1 now escapes" (gfd-escapes? gfd 1))
    (assert-false "slot 2 still does not escape" (gfd-escapes? gfd 2))))

;;; -----------------------------------------------------------------------
;;; Group 2: Residual Code Generation Helpers
;;; -----------------------------------------------------------------------

(display "\n--- Group 2: Code Generation & Lowering Helpers ---\n")

(let ((gfd (make-guest-frame-descriptor '(a b c))))
  (assert-equal "slot count 3" 3 (gfd-slot-count gfd))
  (gfd-mark-escape! gfd 1) ; b escapes

  ;; Slot reference emissions
  (assert-equal "non-escaping slot ref" '(local-slot-ref 0) (gfd-emit-slot-ref 'frame 0 #f))
  (assert-equal "escaping slot ref" '(vector-ref frame 1) (gfd-emit-slot-ref 'frame 1 #t))

  ;; Slot mutation emissions
  (assert-equal "non-escaping slot set" '(local-slot-set! 0 42) (gfd-emit-slot-set! 'frame 0 42 #f))
  (assert-equal "escaping slot set" '(vector-set! frame 1 99) (gfd-emit-slot-set! 'frame 1 99 #t))

  ;; Frame allocation emission
  (assert-equal "frame alloc" '(make-vector 3 #f) (gfd-emit-frame-alloc gfd)))

;;; -----------------------------------------------------------------------
;;; Group 3: AST Lowering: Eliminating Dynamic Alist Lookups
;;; -----------------------------------------------------------------------

(display "\n--- Group 3: AST Lowering Transformer ---\n")

(let* ((gfd (gfd-empty))
       (_x (gfd-add-slot! gfd 'x))
       (_y (gfd-add-slot! gfd 'y)))
  (gfd-mark-escape! gfd 1) ; y escapes, x does not

  ;; Pattern 1: (cdr (assq 'x env)) -> (local-slot-ref 0)
  (let* ((orig-ast '(cdr (assq (quote x) env)))
         (lowered (lower-guest-env-to-frame orig-ast gfd 'frame)))
    (assert-equal "lowered (cdr (assq 'x env))" '(local-slot-ref 0) lowered))

  ;; Pattern 2: (cdr (assq 'y env)) -> (vector-ref frame 1)
  (let* ((orig-ast '(cdr (assq (quote y) env)))
         (lowered (lower-guest-env-to-frame orig-ast gfd 'frame)))
    (assert-equal "lowered (cdr (assq 'y env))" '(vector-ref frame 1) lowered))

  ;; Pattern 3: Compound expression with multiple lookups
  (let* ((orig-ast '(+ (cdr (assq (quote x) env))
                       (* (cdr (assq (quote y) env)) 2)))
         (lowered (lower-guest-env-to-frame orig-ast gfd 'frame)))
    (assert-equal "lowered compound lookup"
                  '(+ (local-slot-ref 0) (* (vector-ref frame 1) 2))
                  lowered))

  ;; Pattern 4: env-lookup and ctfe-env-lookup
  (let* ((orig-ast '(env-lookup env (quote x)))
         (lowered (lower-guest-env-to-frame orig-ast gfd 'frame)))
    (assert-equal "lowered env-lookup" '(local-slot-ref 0) lowered)))

;;; -----------------------------------------------------------------------
;;; Group 4: First Futamura Projection (Tower Collapse) with Frame Lowering
;;; -----------------------------------------------------------------------

(display "\n--- Group 4: First Futamura Projection with Frame Lowering ---\n")

;; Interpreter definition with environment
(define (test-micro-eval insts stack env)
  (cond
    ((null? insts) (car stack))
    (else
     (let* ((inst (car insts))
            (op (car inst))
            (rest (cdr insts)))
       (cond
         ((eq? op 'PUSH-CONST)
          (test-micro-eval rest (cons (cadr inst) stack) env))
         ((eq? op 'LOAD-VAR)
          (let ((entry (assq (cadr inst) env)))
            (test-micro-eval rest (cons (cdr entry) stack) env)))
         ((eq? op 'ADD)
          (let ((b (car stack)) (a (cadr stack)) (stk (cddr stack)))
            (test-micro-eval rest (cons (+ a b) stk) env)))
         ((eq? op 'MUL)
          (let ((b (car stack)) (a (cadr stack)) (stk (cddr stack)))
            (test-micro-eval rest (cons (* a b) stk) env)))
         ((eq? op 'HALT)
          (car stack))
         (else (error "Unknown opcode" op)))))))

;; Micro bytecode to stage-annotated AST
(define (test-bytecode->stage-poly insts stack)
  (cond
    ((null? insts)
     (list 'stage-later (car stack)))
    (else
     (let* ((inst (car insts))
            (op (car inst))
            (rest (cdr insts)))
       (cond
         ((eq? op 'PUSH-CONST)
          (test-bytecode->stage-poly rest (cons (cadr inst) stack)))
         ((eq? op 'LOAD-VAR)
          (let* ((var-sym (cadr inst))
                 (load-expr (list 'cdr (list 'assq (list 'quote var-sym) 'env))))
            (test-bytecode->stage-poly rest (cons load-expr stack))))
         ((eq? op 'ADD)
          (let* ((b (car stack))
                 (a (cadr stack))
                 (stk (cddr stack))
                 (add-expr (list '+ a b)))
            (test-bytecode->stage-poly rest (cons add-expr stk))))
         ((eq? op 'MUL)
          (let* ((b (car stack))
                 (a (cadr stack))
                 (stk (cddr stack))
                 (mul-expr (list '* a b)))
            (test-bytecode->stage-poly rest (cons mul-expr stk))))
         ((eq? op 'HALT)
          (list 'stage-later (car stack)))
         (else
          (error "Unknown opcode" op)))))))

;; Ground-truth evaluation
(let* ((bytecode '((LOAD-VAR x) (LOAD-VAR y) (ADD) (PUSH-CONST 5) (MUL) (HALT)))
       (test-env '((x . 10) (y . 20)))
       (ref-res (test-micro-eval bytecode '() test-env)))
  (assert-equal "reference evaluation: (10 + 20) * 5 = 150" 150 ref-res)

  ;; Now compile using stage-poly-lower WITH guest-frame-descriptor!
  (let* ((gfd (gfd-empty))
         (idx-x (gfd-add-slot! gfd 'x))
         (idx-y (gfd-add-slot! gfd 'y)))
    (gfd-mark-escape! gfd 0) ; x escapes (stored in vector)
    (gfd-mark-escape! gfd 1) ; y escapes (stored in vector)

    (let* ((stage-poly-ast (test-bytecode->stage-poly bytecode '()))
           ;; Lower using stage-poly-lower with GFD context
           (residual-anf (with-guest-frame-descriptor gfd
                           (lambda ()
                             (stage-poly-lower stage-poly-ast '())))))

      (display "Residual ANF with Frame Lowering: ")
      (write residual-anf)
      (newline)

      ;; Verification 1: assq must NOT appear anywhere in residual code!
      (define (contains-symbol? tree sym)
        (cond
          ((eq? tree sym) #t)
          ((pair? tree)
           (or (contains-symbol? (car tree) sym)
               (contains-symbol? (cdr tree) sym)))
          (else #f)))

      (assert-false "residual code does NOT contain assq" (contains-symbol? residual-anf 'assq))
      (assert-false "residual code does NOT contain cons" (contains-symbol? residual-anf 'cons))
      (assert-false "residual code does NOT contain pair?" (contains-symbol? residual-anf 'pair?))

      ;; Verification 2: vector-ref for slots must be present
      (assert-true "residual code contains vector-ref" (contains-symbol? residual-anf 'vector-ref))

      ;; Verification 3: Execution of residual code with vector frame produces identical result
      (let* ((frame-vec (vector 10 20))
             (eval-env (list (cons 'env frame-vec)))
             (res-val (eval-residual-anf-expr residual-anf eval-env)))
        (assert-equal "residual code execution with vector frame yields 150" 150 res-val)))))

(display "\n[RESULT] All Language Workbench Guest Frame Descriptor tests PASSED!\n")
