;;; =======================================================================
;;; ULisp Per-Pass Unit Test Suite
;;; Conforms to Issue #502 & DSN-33 Architecture Specification
;;; Tests Nanopass 1 through Nanopass 7 in isolation.
;;; =======================================================================

(define *pass-tests-passed* 0)
(define *pass-tests-failed* 0)

(define (assert-equal test-name expected actual)
  (if (equal? expected actual)
      (begin
        (set! *pass-tests-passed* (+ *pass-tests-passed* 1))
        (display "  [PASS] ")
        (display test-name)
        (newline))
      (begin
        (set! *pass-tests-failed* (+ *pass-tests-failed* 1))
        (display "  [FAIL] ")
        (display test-name)
        (display " -> Expected: ")
        (display expected)
        (display " but got: ")
        (display actual)
        (newline)
        (exit 1))))

(define (assert-true test-name expr)
  (assert-equal test-name #t (if expr #t #f)))

;;; =======================================================================
;;; Pass 0b: Metacircular Macro Expander Tests (00b_macro_expander.scm)
;;; =======================================================================
(define (test-pass0b-macro)
  (display "=== Running Pass 0b (Macro Expander) Tests ===")
  (newline)

  ;; 1. eval-macro-expr basic evaluation
  (assert-equal "eval quote in macro expr"
                '(if x 1 2)
                (eval-macro-expr '(list 'if 'x 1 2) '()))

  ;; 2. eval-macro-expr with bindings
  (assert-equal "eval macro expr with env"
                '(+ 10 20)
                (eval-macro-expr '(list '+ a b) '((a . 10) (b . 20))))

  ;; 3. parse-macro-def
  (let ((m (parse-macro-def '(define-macro (when c . body)
                               (list 'if c (cons 'begin body) #f)))))
    (assert-equal "macro name" 'when (car m))
    (assert-true "is macro closure" (macro-closure? (cdr m))))

  ;; 4. expand-macros-in-forms
  (let* ((forms '((define-macro (when c . body)
                    (list 'if c (cons 'begin body) #f))
                  (when (= x 1) (+ x 10))))
         (expanded (expand-macros-in-forms forms)))
    (assert-equal "expand when macro in forms"
                  '((if (= x 1) (begin (+ x 10)) #f))
                  expanded))

  ;; 5. Nested macro definitions & expansion
  (let* ((forms '((defmacro my-const () 42)
                  (define-macro (twice x) (list '+ x x))
                  (+ (twice 5) (my-const))))
         (expanded (expand-macros-in-forms forms)))
    (assert-equal "expand multi-macros in forms"
                  '((+ (+ 5 5) 42))
                  expanded)))

;;; =======================================================================
;;; Pass 1: Desugaring Tests (01_desugar.scm)
;;; =======================================================================
(define (test-pass1-desugar)
  (display "=== Running Pass 1 (Desugaring) Tests ===")
  (newline)

  ;; 1. and desugaring
  (assert-equal "and 2 args"
                '(if #t 42 #f)
                (desugar-all '(and #t 42)))

  ;; 2. let* desugaring
  (assert-equal "let* nested let"
                '(let ((x 1)) (let ((y 2)) (+ x y)))
                (desugar-all '(let* ((x 1) (y 2)) (+ x y))))

  ;; 3. cond desugaring
  (assert-equal "cond with else"
                '(if (= 1 2) (begin 10) (begin 20))
                (desugar-all '(cond ((= 1 2) 10) (else 20))))

  ;; 4. list desugaring
  (assert-equal "list desugaring to cons"
                '(cons 1 (cons 2 '()))
                (desugar-all '(list 1 2))))

;;; =======================================================================
;;; Pass 2: Scope & Free Variable Analysis Tests (02_analysis.scm)
;;; =======================================================================
(define (test-pass2-analysis)
  (display "=== Running Pass 2 (Scope Analysis) Tests ===")
  (newline)

  ;; 1. Open expression has free variables
  (assert-equal "free vars in addition"
                '(x y)
                (free-vars '(+ x y) '()))

  ;; 2. Lambda parameter is bound
  (assert-equal "bound parameter excluded"
                '(y)
                (free-vars '(lambda (x) (+ x y)) '()))

  ;; 3. Let-bound variable is bound
  (assert-equal "let binding excluded"
                '(y)
                (free-vars '(let ((x 1)) (+ x y)) '()))

  ;; 4. Completely closed expression has 0 free vars
  (assert-equal "closed lambda"
                '()
                (free-vars '(lambda (x) (+ x 1)) '())))

;;; =======================================================================
;;; Pass 3: CP0 Constant Folding & Dead Code Elimination (03_cp0.scm)
;;; =======================================================================
(define (test-pass3-cp0)
  (display "=== Running Pass 3 (CP0 Optimization) Tests ===")
  (newline)

  ;; 1. Arithmetic constant folding
  (assert-equal "fold addition"
                30
                (cp0-optimize '(+ 10 20)))

  (assert-equal "fold multiplication"
                42
                (cp0-optimize '(* 6 7)))

  ;; 2. Boolean & conditional reduction
  (assert-equal "fold if-true branch"
                10
                (cp0-optimize '(if #t 10 20)))

  (assert-equal "fold if-false branch"
                20
                (cp0-optimize '(if #f 10 20)))

  ;; 3. Primitive predicate folding
  (assert-equal "fold zero?"
                #t
                (cp0-optimize '(zero? 0))))

;;; =======================================================================
;;; Pass 4: A-Normal Form (ANF) Normalization Tests (04_anf.scm)
;;; =======================================================================
(define (test-pass4-anf)
  (display "=== Running Pass 4 (ANF Normalization) Tests ===")
  (newline)

  ;; 1. Immediate expressions remain unchanged
  (assert-equal "atomic integer"
                42
                (anf-all 42))

  ;; 2. Nested compound expressions are normalized with let-bindings
  (let ((anf-res (anf-all '(+ (+ 1 2) 3))))
    (assert-true "anf introduces let for compound arg"
                 (and (pair? anf-res) (eq? (car anf-res) 'let))))

  ;; 3. If condition is normalized
  (let ((anf-if (anf-all '(if (+ 1 2) 10 20))))
    (assert-true "anf normalizes if condition"
                 (and (pair? anf-if) (eq? (car anf-if) 'let)))))

;;; =======================================================================
;;; Pass 5: Explicit Closure Conversion Tests (05_closure_convert.scm)
;;; =======================================================================
(define (test-pass5-closure)
  (display "=== Running Pass 5 (Closure Conversion) Tests ===")
  (newline)

  ;; 1. Top-level program wrapping
  (let ((res (closure-convert 42)))
    (assert-equal "program tag" '%program (car res))
    (assert-equal "main expr" 42 (caddr res)))

  ;; 2. Lambda lifting to %function
  (let* ((res (closure-convert '(lambda (x) (+ x 1))))
         (funcs (cadr res))
         (main-expr (caddr res)))
    (assert-equal "lifts 1 function" 1 (length funcs))
    (assert-equal "function tag" '%function (caar funcs))
    (assert-equal "main is %make-closure" '%make-closure (car main-expr)))

  ;; 3. Free variable capture via %closure-ref
  (let* ((res (closure-convert '(let ((y 10)) (lambda (x) (+ x y)))))
         (funcs (cadr res)))
    (assert-equal "lifts inner lambda" 1 (length funcs))
    (let ((fn-body (cadddr (car funcs))))
      ;; fn-body should contain %closure-ref for y
      (assert-true "body references closure environment"
                   (let rec ((e fn-body))
                     (cond
                       ((not (pair? e)) #f)
                       ((eq? (car e) '%closure-ref) #t)
                       (else (or (rec (car e)) (rec (cdr e))))))))))

;;; =======================================================================
;;; Pass 6: Low-Level Intermediate Representation (LIR) Tests (06_lir.scm)
;;; =======================================================================
(define (test-pass6-lir)
  (display "=== Running Pass 6 (LIR Generation) Tests ===")
  (newline)

  ;; 1. Basic LIR program structure
  (let* ((hir (closure-convert 42))
         (lir (generate-lir hir)))
    (assert-equal "LIR program tag" '%lir-program (car lir))
    (assert-true "has %lir-main clause"
                 (not (eq? (assq '%lir-main (cdr lir)) #f)))
    (assert-true "has %lir-functions clause"
                 (not (eq? (assq '%lir-functions (cdr lir)) #f))))

  ;; 2. Frame size calculation and 16-byte alignment
  (let* ((hir (closure-convert '(let ((a 1) (b 2)) (+ a b))))
         (lir (generate-lir hir))
         (main-clause (assq '%lir-main (cdr lir)))
         (frame-entry (assq 'frame-size (cdr main-clause)))
         (frame-size (cadr frame-entry)))
    (assert-true "frame size is positive" (> frame-size 0))
    ;; Frame size must be a multiple of 8 or 16
    (assert-true "frame size alignment" (= (modulo frame-size 8) 0)))

  ;; 3. LIR Instruction opcodes schema validation
  (let* ((hir (closure-convert '(+ 10 20)))
         (lir (generate-lir hir))
         (main-clause (assq '%lir-main (cdr lir)))
         (body (cdr (assq 'body (cdr main-clause)))))
    (assert-true "main body contains instructions" (not (null? body)))
    ;; Check valid LIR opcodes
    (let ((valid-opcodes '(%mov %load %store %store-byte %load-byte-zx %add %sub
                          %neg %imul %cqo %idiv %inc %shl %shr %sar %bit-and
                          %bit-or %bit-xor %cmp %set-boolean %alloc %code-ref
                          %str-ref %c-call %call-closure %label %jump
                          %jump-if-false %jump-if-zero %return)))
      (for-each
       (lambda (inst)
         (let ((op (car inst)))
           (assert-true (string-append "valid LIR opcode: " (symbol->string op))
                        (memq op valid-opcodes))))
       body))))

;;; =======================================================================
;;; Pass 7: Backend x86-64 Codegen Tests (07_backend_x86_64.scm)
;;; =======================================================================
(define (test-pass7-backend)
  (display "=== Running Pass 7 (x86-64 Backend) Tests ===")
  (newline)

  ;; 1. Register formatting
  (assert-equal "reg rax" "rax" (reg->str '%rax))
  (assert-equal "reg r12" "r12" (reg->str '%r12))
  (assert-equal "reg rsp" "rsp" (reg->str '%rsp))

  ;; 2. Operand formatting
  (assert-equal "integer operand" "42" (operand->str 42))
  (assert-equal "stack operand" "[rsp - 8]" (operand->str '(%stack -8)))
  (assert-equal "stack operand pos" "[rsp + 16]" (operand->str '(%stack 16)))

  ;; 3. Memory operand formatting
  (assert-equal "mem op rsp" "[rsp - 8]" (mem-op->str '%rsp -8))
  (assert-equal "mem op reg" "[rax + 7]" (mem-op->str '%rax 7))

  ;; 4. GAS string escaping
  (assert-equal "escape normal" "hello" (escape-gas-string "hello")))

;;; =======================================================================
;;; Pass 7b: Portable C Backend Codegen Tests (07_backend_c.scm)
;;; =======================================================================
(define (test-pass7b-backend-c)
  (display "=== Running Pass 7b (Portable C Backend) Tests ===")
  (newline)

  ;; 1. Label sanitization
  (assert-equal "c sanitize leading dot" "ulisp_L_else_1" (c-sanitize-label ".L_else_1"))
  (assert-equal "c sanitize normal" "scheme_entry" (c-sanitize-label "scheme_entry"))

  ;; 2. Register formatting
  (assert-equal "c reg rax" "reg_rax" (c-reg->str '%rax))
  (assert-equal "c reg r12" "reg_r12" (c-reg->str '%r12))
  (assert-equal "c reg rsp" "reg_rsp" (c-reg->str '%rsp))

  ;; 3. Memory reference formatting
  (assert-equal "c mem rsp" "(*(uint64_t *)(reg_rsp + (-8)))" (c-mem-ref '%rsp -8))
  (assert-equal "c mem reg" "(*(uint64_t *)(((char *)(uintptr_t)reg_rax) + (7)))" (c-mem-ref '%rax 7))
  (assert-equal "c mem byte" "(*(uint8_t *)(((char *)(uintptr_t)reg_rdx) + (reg_rax)))" (c-mem-byte-ref '%rdx '%rax))

  ;; 4. Operand formatting
  (assert-equal "c operand int" "42" (c-operand->str 42))
  (assert-equal "c operand stack" "(*(uint64_t *)(reg_rsp + (-8)))" (c-operand->str '(%stack -8)))

  ;; 5. Target directive predicate
  (assert-true "c target directive matches" (c-target-directive? '(!target c)))
  (assert-true "c target directive rejects x86" (not (c-target-directive? '(!target x86_64))))
  (assert-true "c target directive rejects other" (not (c-target-directive? '(+ 1 2))))

  ;; 6. End-to-end pipeline to LIR verification for C backend
  (let* ((core-ast (desugar-all '(let ((x 10)) (+ x 32))))
         (opt-ast (cp0-optimize core-ast))
         (anf-ast (anf-all opt-ast))
         (clos-ast (closure-convert anf-ast))
         (lir (generate-lir clos-ast)))
    (assert-true "lir generated for c backend" (pair? lir))
    (assert-equal "lir tag" '%lir-program (car lir))))

;;; =======================================================================
;;; Main Test Suite Runner
;;; =======================================================================
(display "=======================================================")
(newline)
(display " Starting ULisp Full Nanopass Unit Test Suite (Pass 1-7)")
(newline)
(display "=======================================================")
(newline)

(test-pass0b-macro)
(test-pass1-desugar)
(test-pass2-analysis)
(test-pass3-cp0)
(test-pass4-anf)
(test-pass5-closure)
(test-pass6-lir)
(test-pass7-backend)
(test-pass7b-backend-c)

(display "=======================================================")
(newline)
(display " All ")
(display *pass-tests-passed*)
(display " per-pass unit tests PASSED successfully! (0 failures)")
(newline)
(display "=======================================================")
(newline)
