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

  ;; 1. parse-syntax-rules-def
  (let ((m (parse-syntax-rules-def '(define-syntax when
                                      (syntax-rules ()
                                        ((_ c body ...)
                                         (if c (begin body ...) #f)))))))
    (assert-equal "macro name" 'when (macro-name m))
    (assert-true "is syntax-rules macro" (syntax-rules-macro? m)))

  ;; 2. expand-macros-in-forms with basic when macro
  (let* ((forms '((define-syntax when
                    (syntax-rules ()
                      ((_ c body ...)
                       (if c (begin body ...) #f))))
                  (when (= x 1) (+ x 10))))
         (expanded (expand-macros-in-forms forms)))
    (assert-equal "expand when macro in forms"
                  '((if (= x 1) (begin (+ x 10)) #f))
                  expanded))

  ;; 3. Nested syntax-rules macro expansion
  (let* ((forms '((define-syntax my-const
                    (syntax-rules ()
                      ((_) 42)))
                  (define-syntax twice
                    (syntax-rules ()
                      ((_ x) (+ x x))))
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
                (cp0-optimize '(zero? 0)))

  ;; 4. Dead Code Elimination (DCE) on letrec
  (assert-equal "dce letrec eliminate unused binding"
                '(letrec ((f (lambda (x) (+ x 1)))) (f 10))
                (cp0-optimize '(letrec ((f (lambda (x) (+ x 1)))
                                        (g (lambda (y) (* y 2))))
                                 (f 10))))

  (assert-equal "dce letrec eliminate dead mutual recursion cycle"
                '(letrec ((live (lambda (z) (+ z 1)))) (live 5))
                (cp0-optimize '(letrec ((dead-a (lambda (x) (dead-b x)))
                                        (dead-b (lambda (y) (dead-a y)))
                                        (live (lambda (z) (+ z 1))))
                                 (live 5))))

  (assert-equal "dce letrec degenerate to body when all bindings unused"
                100
                (cp0-optimize '(letrec ((unused (lambda (x) (* x 2)))
                                        (val 42))
                                 100)))

  ;; 5. Dead Code Elimination on let
  (assert-equal "dce let eliminate dead pure bindings"
                '(let ((x 1)) x)
                (cp0-optimize '(let ((x 1) (y (+ 2 3))) x)))

  (assert-equal "dce let degenerate to body when all bindings dead"
                42
                (cp0-optimize '(let ((a 10) (b 20)) 42))))

;;; =======================================================================
;;; Pass 3b: Extended LVN & Accessor Memoization Tests (03b_lvn.scm)
;;; =======================================================================
(define (test-pass3b-lvn)
  (display "=== Running Pass 3b (Extended LVN) Tests ===")
  (newline)

  ;; 1. Pair accessor deduplication
  (let* ((input '(let ((a (car p))) (let ((b (car p))) (+ a b))))
         (opt (lvn-all input)))
    (assert-equal "lvn deduplicate (car p)" '(let ((a (car p))) (+ a a)) opt))

  ;; 2. Pair constructor reduction
  (let* ((input '(let ((p (cons 10 20))) (car p)))
         (opt (lvn-all input)))
    (assert-equal "lvn (car (cons 10 20)) -> 10" '(let ((p (cons 10 20))) 10) opt))

  ;; 3. Algebraic identities
  (assert-equal "lvn (+ x 0) -> x" 'x (lvn-all '(+ x 0)))
  (assert-equal "lvn (* x 1) -> x" 'x (lvn-all '(* x 1)))
  (assert-equal "lvn (- x x) -> 0" 0 (lvn-all '(- x x)))
  (assert-equal "lvn (= x x) -> #t" #t (lvn-all '(= x x)))

  ;; 4. Commutative normalization & CSE
  (let* ((input '(let ((x (+ b a))) (let ((y (+ a b))) (- x y))))
         (opt (lvn-all input)))
    (assert-equal "lvn commutative (- x y) -> 0" '(let ((x (+ b a))) 0) opt))

  ;; 5. Dominance predicate folding
  (let* ((input '(if (fixnum? x) (if (fixnum? x) (+ x 0) 42) 99))
         (opt (lvn-all input)))
    (assert-equal "lvn dominance type check" '(if (fixnum? x) x 99) opt)))

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
;;; Pass 4b: S-Annotator Abstract Interpretation Tests (04b_annotator.scm)
;;; =======================================================================
(define (test-pass4b-annotator)
  (display "=== Running Pass 4b (S-Annotator) Tests ===")
  (newline)

  ;; 1. Lattice operations
  (assert-equal "type-lub bot fixnum"
                'fixnum
                (type-lub (type-bot) (type-fixnum)))

  (assert-equal "type-lub fixnum ranges"
                '(fixnum 1 10)
                (type-lub (type-fixnum-range 1 5) (type-fixnum-range 3 10)))

  (assert-equal "type-lub disjoint types"
                'top
                (type-lub (type-fixnum) (type-boolean)))

  ;; 2. Arithmetic abstract evaluation
  (assert-equal "eval fixnum literal"
                '(fixnum 42 42)
                (abstract-eval-expr 42 '()))

  (assert-equal "eval arithmetic addition"
                '(fixnum 30 30)
                (abstract-eval-expr '(+ 10 20) '()))

  ;; 3. Conditional LUB merge
  (let ((if-type (abstract-eval-expr '(if c 10 20) '((c . boolean)))))
    (assert-equal "eval conditional merge"
                  '(fixnum 10 20)
                  if-type))

  ;; 4. Let variable type recording
  (reset-type-annotations!)
  (let ((let-type (abstract-eval-expr '(let ((x 42)) (+ x 1)) '())))
    (assert-true "let body fixnum type" (type-fixnum? let-type))
    (assert-equal "recorded variable type" '(fixnum 42 42) (get-var-type 'x)))

  ;; 5. Named-let fixpoint iteration
  (reset-type-annotations!)
  (let ((loop-res (abstract-eval-expr '(let loop ((n 10) (acc 0))
                                         (if (= n 0)
                                             acc
                                             (loop (- n 1) (+ acc n))))
                                      '())))
    (assert-true "loop result is fixnum" (type-fixnum? loop-res))
    (assert-true "loop var n is fixnum" (type-fixnum? (get-var-type 'n)))
    (assert-true "loop var acc is fixnum" (type-fixnum? (get-var-type 'acc))))

  ;; 6. annotate-all whole program pass
  (let ((forms (annotate-all '((define (square x) (* x x))
                               (square 5)))))
    (assert-equal "annotate-all preserves forms" 2 (length forms)))

  ;; 7. Lattice GLB / Meet operation
  (assert-equal "type-meet ranges"
                '(fixnum 5 10)
                (type-meet (type-fixnum-range 0 10) (type-fixnum-range 5 20)))

  ;; 8. Flow-sensitive narrowing transfer function
  (assert-equal "flow-sensitive narrowing then"
                (type-fixnum)
                (narrow-var-in-branch 'x '(fixnum? x) #t '((x . top)))))

;;; =======================================================================
;;; Pass 5b: S-RTyper Representation Typing & Unboxing Tests (05b_rtyper.scm)
;;; =======================================================================
(define (test-pass5b-rtyper)
  (display "=== Running Pass 5b (S-RTyper) Tests ===")
  (newline)

  ;; 1. Binary arithmetic lowering on integer constants
  (assert-equal "rtyper lower add constants"
                '(%raw-add 10 20)
                (rtyper-binop '+ 10 20 '()))

  (assert-equal "rtyper lower sub constants"
                '(%raw-sub 30 10)
                (rtyper-binop '- 30 10 '()))

  (assert-equal "rtyper lower mul constants"
                '(%raw-mul 5 6)
                (rtyper-binop '* 5 6 '()))

  ;; 2. Binary arithmetic lowering on raw variables
  (assert-equal "rtyper lower add raw variables"
                '(%raw-add x y)
                (rtyper-binop '+ 'x 'y '(x y)))

  (assert-equal "rtyper preserve dynamic add"
                '(+ x y)
                (rtyper-binop '+ 'x 'y '()))

  ;; 3. Loop exit boundary boxing
  (assert-equal "box raw exit variable"
                '(%box-fixnum x)
                (box-raw-exit 'x '(x) 'loop))

  (assert-equal "preserve recursive call unboxed"
                '(loop 1 2)
                (box-raw-exit '(loop 1 2) '(x) 'loop))

  ;; 4. End-to-end unboxed loop transformation
  (reset-type-annotations!)
  (let* ((orig-ast (desugar-all '(let loop ((i 0) (sum 0))
                                   (if (< i 10)
                                       (loop (+ i 1) (+ sum i))
                                       sum))))
         (anf-ast (anf-all (cp0-optimize orig-ast)))
         (ann-ast (annotate-all anf-ast))
         (typed-ast (rtyper-all ann-ast)))
    (assert-true "typed ast is pair" (pair? typed-ast))
    ;; Verify that typed-ast contains %raw-add and %box-fixnum
    (assert-true "contains %raw-add"
                 (let rec ((e typed-ast))
                   (cond
                     ((not (pair? e)) #f)
                     ((eq? (car e) '%raw-add) #t)
                     (else (or (rec (car e)) (rec (cdr e)))))))
    (assert-true "contains %box-fixnum"
                 (let rec ((e typed-ast))
                   (cond
                     ((not (pair? e)) #f)
                     ((eq? (car e) '%box-fixnum) #t)
                     (else (or (rec (car e)) (rec (cdr e)))))))

    ;; 5. Flow-sensitive narrowing unboxing in branch
    (let ((narrow-res (rtyper-expr '(if (fixnum? x) (+ x 1) 0) '())))
      (assert-true "narrowing unbox in branch" (pair? narrow-res)))

    ;; 6. Path Splitting on join nodes
    (let ((split-res (rtyper-expr '(let ((v (if c 10 "s"))) (if (fixnum? v) (+ v 1) 0)) '())))
      (assert-equal "path splitting let-if" 'if (car split-res)))))

;;; =======================================================================
;;; Pass 4c: Contification & Local Closure Elimination Tests (04c_contify.scm)
;;; =======================================================================
(define (test-pass4c-contify)
  (display "=== Running Pass 4c (Contification) Tests ===")
  (newline)

  ;; 1. Escape analysis
  (assert-true "operator does not escape" (not (escapes? 'loop '(loop 10 0))))
  (assert-true "argument escapes" (escapes? 'loop '(cons loop '())))

  ;; 2. Tail calls only
  (assert-true "tail call only" (tail-calls-only? 'loop '(loop 10 0)))
  (assert-true "non-tail call rejected" (not (tail-calls-only? 'loop '(+ 1 (loop 10 0)))))

  ;; 3. Contifiable binding
  (let ((l '(lambda (n acc) (if (= n 0) acc (loop (- n 1) (+ acc n))))))
    (assert-true "tail loop is contifiable" (contifiable-binding? 'loop l '(loop 10 0))))

  ;; 4. AST transformation
  (let* ((orig '(letrec ((loop (lambda (n acc) (if (= n 0) acc (loop (- n 1) (+ acc n)))))) (loop 10 0)))
         (contified (contify-all orig)))
    (assert-true "contified AST is %cont-fun"
                 (and (pair? contified) (eq? (car contified) '%cont-fun)))
    (assert-equal "retains loop symbol" 'loop (cadr contified))))

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
                       (else (or (rec (car e)) (rec (cdr e)))))))))

  ;; 4. Quoted symbol literal preservation (static interning without string->symbol)
  (let ((res (closure-convert ''a)))
    (assert-equal "preserves quoted symbol" ''a (caddr res))))

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
                          %raw-add %raw-sub %raw-mul %raw-cmp %box-fixnum %unbox-fixnum
                          %neg %imul %cqo %idiv %inc %shl %shr %sar %bit-and
                          %bit-or %bit-xor %cmp %set-boolean %alloc %code-ref
                          %str-ref %c-call %call-closure %label %block %jump
                          %jump-if %jump-if-false %jump-if-zero %return)))
      (for-each
       (lambda (inst)
         (let ((op (car inst)))
           (assert-true (string-append "valid LIR opcode: " (symbol->string op))
                        (memq op valid-opcodes))))
       body))
    ;; Check GC and low-level memory intrinsics LIR generation
    (let* ((ast-get-rsp (closure-convert (anf-all (cp0-optimize (desugar-all '(%get-rsp))))))
           (lir-get-rsp (generate-lir ast-get-rsp)))
      (assert-true "lir %get-rsp generates lir-program" (pair? lir-get-rsp)))
    (let* ((ast-bitwise (closure-convert (anf-all (cp0-optimize (desugar-all '(bitwise-and 15 7))))))
           (lir-bitwise (generate-lir ast-bitwise)))
      (assert-true "lir bitwise-and generates lir-program" (pair? lir-bitwise)))
    (let* ((ast-raw-load (closure-convert (anf-all (cp0-optimize (desugar-all '(%raw-load 100 0))))))
           (lir-raw-load (generate-lir ast-raw-load)))
      (assert-true "lir %raw-load generates lir-program" (pair? lir-raw-load)))
    (let* ((ast-raw-add (closure-convert (anf-all (cp0-optimize (desugar-all '(%raw-add 10 20))))))
           (lir-raw-add (generate-lir ast-raw-add)))
      (assert-true "lir %raw-add generates lir-program" (pair? lir-raw-add)))
    (let* ((ast-box (closure-convert (anf-all (cp0-optimize (desugar-all '(%box-fixnum 42))))))
           (lir-box (generate-lir ast-box)))
      (assert-true "lir %box-fixnum generates lir-program" (pair? lir-box)))
    (let* ((ast-sm (closure-convert (anf-all (cp0-optimize (desugar-all '(%get-stackmap-table))))))
           (lir-sm (generate-lir ast-sm)))
      (assert-true "lir %get-stackmap-table generates lir-program" (pair? lir-sm))
      (assert-true "lir has stackmaps clause" (not (eq? (assq 'stackmaps (cdr lir-sm)) #f))))

    ;; Check Block Arguments in conditional if LIR generation
    (let* ((ast-if (closure-convert (anf-all (cp0-optimize (desugar-all '(if (zero? (read-char)) 10 20))))))
           (lir-if (generate-lir ast-if))
           (main-body (cdr (assq 'body (cdr (assq '%lir-main (cdr lir-if)))))))
      (assert-true "lir if contains %block"
                   (pair? (filter (lambda (i) (and (pair? i) (eq? (car i) '%block))) main-body))))

    ;; Check Braun SSA On-the-Fly Construction Engine
    (let ((cfg (make-braun-cfg)))
      (braun-new-block! cfg 'entry)
      (braun-new-block! cfg 'b_then)
      (braun-new-block! cfg 'b_else)
      (braun-new-block! cfg 'b_join)
      (braun-add-edge! cfg 'entry 'b_then)
      (braun-add-edge! cfg 'entry 'b_else)
      (braun-add-edge! cfg 'b_then 'b_join)
      (braun-add-edge! cfg 'b_else 'b_join)
      (braun-write-variable! cfg 'x 'b_then 100)
      (braun-write-variable! cfg 'x 'b_else 200)
      (braun-seal-block! cfg 'entry)
      (braun-seal-block! cfg 'b_then)
      (braun-seal-block! cfg 'b_else)
      (braun-seal-block! cfg 'b_join)
      (let ((val (braun-read-variable cfg 'x 'b_join)))
        (assert-true "braun join creates block argument symbol" (symbol? val))
        (assert-equal "braun b_join has 1 parameter" 1 (length (braun-get-params cfg 'b_join)))
        (assert-equal "braun incoming from then is 100" 100 (braun-get-incoming cfg val 'b_then))
        (assert-equal "braun incoming from else is 200" 200 (braun-get-incoming cfg val 'b_else))))))

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
;;; Pass 7c: AArch64 (ARM64) Backend Codegen Tests (07_backend_aarch64.scm)
;;; =======================================================================
(define (test-pass7c-backend-aarch64)
  (display "=== Running Pass 7c (AArch64 Backend) Tests ===")
  (newline)

  ;; 1. Register formatting
  (assert-equal "arm reg rax" "x0" (arm-reg->str '%rax))
  (assert-equal "arm reg rdx" "x1" (arm-reg->str '%rdx))
  (assert-equal "arm reg rcx" "x2" (arm-reg->str '%rcx))
  (assert-equal "arm reg r10" "x10" (arm-reg->str '%r10))
  (assert-equal "arm reg r12" "x19" (arm-reg->str '%r12))
  (assert-equal "arm reg rsp" "sp" (arm-reg->str '%rsp))
  (assert-equal "arm reg al" "w0" (arm-reg->str '%al))

  ;; 2. 32-bit register formatting
  (assert-equal "arm w reg rax" "w0" (arm-w-reg->str '%rax))
  (assert-equal "arm w reg rdx" "w1" (arm-w-reg->str '%rdx))
  (assert-equal "arm w reg rcx" "w2" (arm-w-reg->str '%rcx))
  (assert-equal "arm w reg r10" "w10" (arm-w-reg->str '%r10))
  (assert-equal "arm w reg r12" "w19" (arm-w-reg->str '%r12))

  ;; 3. Memory operand formatting
  (assert-equal "arm mem op rsp -8" "[sp, #-8]" (arm-mem-op->str '%rsp -8))
  (assert-equal "arm mem op rax 7" "[x0, #7]" (arm-mem-op->str '%rax 7))
  (assert-equal "arm mem op rdx rax" "[x1, x0]" (arm-mem-op->str '%rdx '%rax))

  ;; 4. Operand formatting
  (assert-equal "arm operand int" "#42" (arm-operand->str 42))
  (assert-equal "arm operand stack" "[sp, #-8]" (arm-operand->str '(%stack -8)))
  (assert-equal "arm operand mem" "[x19, #16]" (arm-operand->str '(%mem %r12 16)))

  ;; 5. Condition code mapping
  (assert-equal "arm cc sete" "eq" (arm-condition-code "sete"))
  (assert-equal "arm cc setl" "lt" (arm-condition-code "setl"))
  (assert-equal "arm cc setle" "le" (arm-condition-code "setle"))
  (assert-equal "arm cc setg" "gt" (arm-condition-code "setg"))
  (assert-equal "arm cc setge" "ge" (arm-condition-code "setge"))
  (assert-equal "arm cc setne" "ne" (arm-condition-code "setne"))

  ;; 6. End-to-end pipeline to LIR verification for AArch64 backend
  (let* ((core-ast (desugar-all '(let ((x 10)) (+ x 32))))
         (opt-ast (cp0-optimize core-ast))
         (anf-ast (anf-all opt-ast))
         (clos-ast (closure-convert anf-ast))
         (lir (generate-lir clos-ast)))
    (assert-true "lir generated for aarch64 backend" (pair? lir))
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
(test-pass3b-lvn)
(test-pass4-anf)
(test-pass4b-annotator)
(test-pass5b-rtyper)
(test-pass4c-contify)
(test-pass5-closure)
(test-pass6-lir)
(test-pass7-backend)
(test-pass7b-backend-c)
(test-pass7c-backend-aarch64)

(display "=======================================================")
(newline)
(display " All ")
(display *pass-tests-passed*)
(display " per-pass unit tests PASSED successfully! (0 failures)")
(newline)
(display "=======================================================")
(newline)
