;;; =======================================================================
;;; Unit Test Suite: ULisp Nanopass Framework DSL (Phase 1)
;;; Conforms to Issue #581 & Keep & Dybvig (2013) Specification
;;; =======================================================================

(define *nanopass-tests-passed* 0)
(define *nanopass-tests-failed* 0)

(define (assert-equal label expected actual)
  (if (equal? expected actual)
      (begin
        (set! *nanopass-tests-passed* (+ *nanopass-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (set! *nanopass-tests-failed* (+ *nanopass-tests-failed* 1))
        (display "  [FAIL] ") (display label)
        (display " -> Expected: ") (write expected)
        (display " but got: ") (write actual) (newline)
        (error "Assertion failed:" label))))

(define (assert-true label cond)
  (assert-equal label #t (if cond #t #f)))

(define (assert-false label cond)
  (assert-equal label #f (if cond #t #f)))

(display "=======================================================") (newline)
(display " Starting Nanopass Framework DSL Unit Test Suite") (newline)
(display "=======================================================") (newline)

;;; -----------------------------------------------------------------------
;;; Host / Interpreter Macros (for ilisp and test environments)
;;; -----------------------------------------------------------------------
(define-macro (define-language . args)
  (nanopass-expand-define-language (cons 'define-language args)))

(define-macro (define-pass . args)
  (nanopass-expand-define-pass (cons 'define-pass args)))

(define-macro (define-parser . args)
  (nanopass-expand-define-parser (cons 'define-parser args)))

(define-macro (define-unparser . args)
  (nanopass-expand-define-unparser (cons 'define-unparser args)))

(define-macro (define-picopass . args)
  (nanopass-expand-define-picopass (cons 'define-picopass args)))

(define-macro (define-femtopass . args)
  (nanopass-expand-define-femtopass (cons 'define-femtopass args)))

(define-macro (define-attopass . args)
  (nanopass-expand-define-attopass (cons 'define-attopass args)))

(define-macro (in-context . args)
  (if (= (length args) 2)
      (list (car args) (cadr args))
      (list 'nanopass-parse-nt (list 'quote (car args)) (caddr args) (list 'quote (cadr args)))))

(define-macro (nanopass-template . args)
  (nanopass-expand-template (car args) '()))

(define-macro (picopass-seq* . rules)
  (if (null? rules)
      '(lambda (ir) #f)
      (if (null? (cdr rules))
          (car rules)
          (let loop ((rem (cdr rules)) (acc (car rules)))
            (if (null? rem)
                acc
                (loop (cdr rem) (list 'picopass-seq acc (car rem))))))))

(define-macro (picopass-choice* . rules)
  (if (null? rules)
      '(lambda (ir) #f)
      (if (null? (cdr rules))
          (car rules)
          (let loop ((rem (cdr rules)) (acc (car rules)))
            (if (null? rem)
                acc
                (loop (cdr rem) (list 'picopass-choice acc (car rem))))))))

;;; -----------------------------------------------------------------------
;;; 1. define-language & Language Reflection
;;; -----------------------------------------------------------------------

(define-language L_test_src
  (terminals
    (symbol (x))
    (constant (c)))
  (Expr (e)
    x
    c
    (quote datum)
    (if e1 e2 e3)
    (cond (e1 e2) ... (else e_else))
    (let ((x e1) ...) e2)
    (e0 e1 ...)))

(assert-true "L_test_src is registered"
             (nanopass-language? (nanopass-lookup-language 'L_test_src)))

(let ((s-exp (language->s-expression 'L_test_src)))
  (assert-equal "language->s-expression root" 'language (car s-exp))
  (assert-equal "language->s-expression name" 'L_test_src (cadr s-exp)))

(assert-true "L_test_src? symbol" (L_test_src? 'foo))
(assert-true "L_test_src? number" (L_test_src? 42))
(assert-true "L_test_src? if expr" (L_test_src? '(if #t 1 2)))
(assert-true "L_test_src? cond expr" (L_test_src? '(cond ((= a 1) 10) (else 20))))
(assert-true "L_test_src? call expr" (L_test_src? '(+ 1 2)))

;;; -----------------------------------------------------------------------
;;; 2. Language Derivation via `extends` and Invariant Diffs
;;; -----------------------------------------------------------------------

(define-language L_test_core
  (extends L_test_src)
  (Expr (e)
    (- (cond (e1 e2) ... (else e_else)))
    (+ (core-op e1 e2))))

(assert-true "L_test_core? if expr" (L_test_core? '(if #t 1 2)))
(assert-true "L_test_core? core-op" (L_test_core? '(core-op 1 2)))

;; Verification of removed invariant: cond is removed from L_test_core!
(assert-false "L_test_core? rejects removed cond"
              (L_test_core? '(cond ((= a 1) 10) (else 20))))

(let ((diff (language-diff 'L_test_src 'L_test_core)))
  (assert-true "language-diff removed has cond"
               (let ((rm (cadr (assq 'removed diff))))
                 (and (pair? rm) (eq? (caar rm) 'cond))))
  (assert-true "language-diff added has core-op"
               (let ((add (cadr (assq 'added diff))))
                 (and (pair? add) (eq? (caar add) 'core-op)))))

;;; -----------------------------------------------------------------------
;;; 3. define-parser & define-unparser
;;; -----------------------------------------------------------------------

(define-parser parse-src L_test_src)
(define-parser parse-core L_test_core)
(define-unparser unparse-core L_test_core)

(assert-equal "parse-src accepts cond"
              '(cond ((= a 1) 10) (else 20))
              (parse-src '(cond ((= a 1) 10) (else 20))))

(assert-equal "unparse-core preserves ir"
              '(if #t 1 2)
              (unparse-core '(if #t 1 2)))

;;; -----------------------------------------------------------------------
;;; 4. define-pass & Catamorphism Traversal Synthesis
;;; -----------------------------------------------------------------------

;; Pass that desugars cond into if
(define-pass desugar-test-cond : L_test_src (ir) -> L_test_core ()
  (Expr : Expr (ir) -> Expr ()
    ((cond (else . ,bodies))
     (cons 'begin (map Expr bodies)))
    ((cond (,test . ,bodies) . ,rest)
     (list 'if (Expr test)
           (cons 'begin (map Expr bodies))
           (Expr (cons 'cond rest))))))

(assert-equal "desugar-test-cond simple cond"
              '(if (= a 1) (begin 10) (begin 20))
              (desugar-test-cond '(cond ((= a 1) 10) (else 20))))

;; Test automatic Catamorphism synthesis across untouched constructs (let, if, calls):
(assert-equal "desugar-test-cond nested in let and if"
              '(let ((x 1)) (if x (if (= a 1) (begin 10) (begin 20)) 99))
              (desugar-test-cond '(let ((x 1)) (if x (cond ((= a 1) 10) (else 20)) 99))))

;; Verify output of pass conforms to target language L_test_core
(assert-true "desugar-test-cond output is valid L_test_core"
             (L_test_core? (desugar-test-cond '(let ((x 1)) (if x (cond ((= a 1) 10) (else 20)) 99)))))

;;; -----------------------------------------------------------------------
;;; 5. define-pass with Guards
;;; -----------------------------------------------------------------------

(define-pass guard-test-pass : L_test_src (ir) -> L_test_src ()
  (Expr : Expr (ir) -> Expr ()
    ((special ,x) (guard (number? x))
     (list 'special-number (* x 2)))
    ((special ,x)
     (list 'special-other x))))

(assert-equal "guard matches number branch"
              '(special-number 84)
              (guard-test-pass '(special 42)))

(assert-equal "guard falls through to second branch on non-number"
              '(special-other "hello")
              (guard-test-pass '(special "hello")))

;;; -----------------------------------------------------------------------
;;; 6. Canonical L_src and L_core Standard Pipeline Verification
;;; -----------------------------------------------------------------------

(assert-true "Canonical L_src recognizes high-level forms"
             (L_src? '(let* ((x 1) (y 2)) (and x y))))

(assert-false "Canonical L_core rejects un-desugared forms"
              (L_core? '(let* ((x 1) (y 2)) (and x y))))

(assert-true "Canonical L_core accepts canonical core forms"
             (L_core? '(let ((x 1)) (let ((y 2)) (if x y #f)))))

;;; -----------------------------------------------------------------------
;;; 7. Ellipsis (...) Pattern Matching & Template Splice Reconstruction
;;; -----------------------------------------------------------------------

;; Pass that matches let bindings via ellipsis and rewrites them
(define-pass test-ellipsis-let : L_test_src (ir) -> L_test_src ()
  (Expr : Expr (ir) -> Expr ()
    ((let ((,x* ,e*) ...) ,body)
     `(let ((,x* (* ,e* 2)) ...) ,body))))


(assert-equal "test-ellipsis-let unpacks and reconstructs multiple bindings"
              '(let ((a (* 10 2)) (b (* 20 2))) (+ a b))
              (test-ellipsis-let '(let ((a 10) (b 20)) (+ a b))))

(assert-equal "test-ellipsis-let handles empty bindings list"
              '(let () 42)
              (test-ellipsis-let '(let () 42)))

;; Trailing elements after ellipsis: (foo ,x ... ,y)
(define-pass test-ellipsis-trailing : L_test_src (ir) -> L_test_src ()
  (Expr : Expr (ir) -> Expr ()
    ((sum-last ,x ... ,y)
     (list 'result-sum (cons 'list x) y))))

(assert-equal "test-ellipsis-trailing matches prefix list and tail element"
              '(result-sum (list 1 2 3) 4)
              (test-ellipsis-trailing '(sum-last 1 2 3 4)))

(assert-equal "test-ellipsis-trailing matches empty prefix with tail"
              '(result-sum (list) 99)
              (test-ellipsis-trailing '(sum-last 99)))

;; Template splice with ellipsis: (result ,(map ...) ...)
(define-pass test-template-splice : L_test_src (ir) -> L_test_src ()
  (Expr : Expr (ir) -> Expr ()
    ((double-all ,x* ...)
     `(result ,(map (lambda (x) (* x 2)) x*) ...))))

(assert-equal "test-template-splice expands ellipsis in output template"
              '(result 2 4 6)
              (test-template-splice '(double-all 1 2 3)))

;; Nested ellipsis: ((,x ...) ...)
(let ((m (nanopass-match-pattern-inner '((,x ...) ...) '((1 2) (3 4 5) ()) (lambda (x) x))))
  (assert-true "nested ellipsis matches list of lists" (and (pair? m) (car m)))
  (assert-equal "nested ellipsis binds multi-level list"
                '((1 2) (3 4 5) ())
                (cdr (assq 'x (cdr m)))))

;;; -----------------------------------------------------------------------
;;; 8. Subform Local Handlers (in-context) and Multi-Nonterminal Passes
;;; -----------------------------------------------------------------------

(define-language L_test_prog
  (terminals
    (symbol (x))
    (constant (c)))
  (Program (p)
    (%program (d ...) e))
  (Def (d)
    (define x e))
  (Expr (e)
    x
    c
    (if e1 e2 e3)
    (+ e1 e2)
    (e0 e1 ...)))

(define-pass test-multi-nt-pass : L_test_prog (ir) -> L_test_prog ()
  (entry Program)
  (Program : Program (ir) -> Program ()
    ((%program ,defs ,main)
     (list '%program
           (map (lambda (d) (in-context Def d)) defs)
           (in-context Expr main))))
  (Def : Def (ir) -> Def ()
    ((define ,x ,e)
     (list 'define x (in-context Expr e))))
  (Expr : Expr (ir) -> Expr ()
    ((+ ,a ,b)
     (list '+ (in-context Expr a) (in-context Expr b)))
    (,c (guard (number? c))
     (* c 10))))

(let* ((input '(%program ((define val 5) (define base 2)) (+ 5 2)))
       (res (test-multi-nt-pass input)))
  (assert-equal "in-context transforms subforms at Program, Def, and Expr levels"
                '(%program ((define val 50) (define base 20)) (+ 50 20))
                res))

;;; -----------------------------------------------------------------------
;;; 9. Extra Values: Downwards Inherited Attributes
;;; -----------------------------------------------------------------------

(define-pass test-inherited-depth : L_test_src (ir depth) -> L_test_src ()
  (Expr : Expr (ir depth) -> Expr ()
    (,c (guard (number? c))
     (+ c depth))
    ((+ ,a ,b)
     (list '+ (Expr a (+ depth 1)) (Expr b (+ depth 1))))))

(assert-equal "test-inherited-depth propagates depth downward"
              '(+ 12 22)
              (test-inherited-depth '(+ 1 11) 10))

;;; -----------------------------------------------------------------------
;;; 10. Extra Values: Pure Analyzer with Synthesized Accumulator (*)
;;; -----------------------------------------------------------------------

(define-pass test-count-symbols : L_test_src (ir acc) -> * (acc)
  (Expr : Expr (ir acc) -> * (acc)
    (,x (guard (symbol? x))
     (+ acc 1))
    (,c (guard (number? c))
     acc)))

(assert-equal "test-count-symbols counts symbols across subnodes"
              3
              (test-count-symbols '(+ x (* y z)) 0))

;;; -----------------------------------------------------------------------
;;; 11. Extra Values: Free Variable Analysis with Bound and Acc (*)
;;; -----------------------------------------------------------------------

(define-pass test-analyze-frees : L_test_src (ir bound acc) -> * (acc)
  (Expr : Expr (ir bound acc) -> * (acc)
    ((quote ,datum)
     acc)
    (,x (guard (symbol? x))
     (if (or (memq x bound) (memq x acc))
         acc
         (cons x acc)))
    ((lambda (,params ...) ,body)
     (Expr body (append params bound) acc))
    ((let ((,x* ,e*) ...) ,body)
     (let* ((new-acc (let loop ((es e*) (cur-acc acc))
                       (if (null? es)
                           cur-acc
                           (loop (cdr es) (Expr (car es) bound cur-acc)))))
            (new-bound (append x* bound)))
       (Expr body new-bound new-acc)))))

(assert-equal "test-analyze-frees captures free variables"
              '(c a)
              (test-analyze-frees '(let ((x a) (y 1)) (+ x b ((lambda (z) (+ z c)) 2))) '(b) '()))

;;; -----------------------------------------------------------------------
;;; 12. Phase 4: Reflection Hierarchy & AST Diff Engine
;;; -----------------------------------------------------------------------

(assert-true "nanopass-get-all-languages returns registered languages"
             (memq 'L_test_core (nanopass-get-all-languages)))

(assert-equal "language-parent-chain tracks L_test_src -> L_test_core"
              '(L_test_src L_test_core)
              (language-parent-chain 'L_test_core))

;;; -----------------------------------------------------------------------
;;; 13. Issue #753 (DSN-33-01 T1.1): Continuous `extends` Hierarchy & All Languages
;;; -----------------------------------------------------------------------

(assert-equal "language-parent-chain for L_lifted is L_cst -> L_src -> L_core -> L_anf -> L_lifted"
              '(L_cst L_src L_core L_anf L_lifted)
              (language-parent-chain 'L_lifted))

(assert-equal "language-parent-chain for L_lir_canonical is L_lir_raw -> L_lir_canonical"
              '(L_lir_raw L_lir_canonical)
              (language-parent-chain 'L_lir_canonical))

(assert-true "L_cst? accepts define-library and let-syntax"
             (and (L_cst? '(define-library (foo bar) (export x) (define x 42)))
                  (L_cst? '(let-syntax ((m (syntax-rules () ((m a) a)))) (m 10)))))

(assert-false "L_src? rejects define-library and let-syntax"
              (or (L_src? '(define-library (foo bar) (export x) (define x 42)))
                  (L_src? '(let-syntax ((m (syntax-rules () ((m a) a)))) (m 10)))))

(assert-true "language-diff L_core -> L_anf computes non-empty removed and added sets"
             (let ((d (language-diff 'L_core 'L_anf)))
               (and (pair? (cadr (assq 'removed d)))
                    (pair? (cadr (assq 'added d))))))

(assert-false "L_core removed-prods does not falsely mark active keyword 'let or 'define as removed"
              (let ((rm (cdr (assq 'removed (cddr (language-declaration 'L_core))))))
                (or (memq 'let rm) (memq 'define rm))))

(assert-true "L_lir_raw? accepts raw (%nop) while L_lir_canonical? rejects (%nop)"
             (let ((raw-prog '(%lir-program (strings ()) (stackmaps ()) (%lir-functions) (%lir-main (frame-size 0) (body (%nop) (%return))))))
               (and (L_lir_raw? raw-prog)
                    (not (L_lir_canonical? raw-prog)))))

(assert-true "L_asm_x86 and L_asm_aarch64 are registered"
             (let ((all-langs (nanopass-get-all-languages)))
               (and (memq 'L_asm_x86 all-langs)
                    (memq 'L_asm_aarch64 all-langs))))

(assert-equal "nanopass-ast-diff identifies identical expressions"
              #f
              (nanopass-ast-diff '(if a b c) '(if a b c)))

(assert-equal "nanopass-ast-diff detects modified node"
              '(if a (diff:modified b 42) c)
              (nanopass-ast-diff '(if a b c) '(if a 42 c)))

;;; -----------------------------------------------------------------------
;;; 14. Issue #754 (DSN-33-01 T1.2): Schema-Driven Catamorphism & Pure Traversal
;;; -----------------------------------------------------------------------

;; 14.1 Verify catamorphism does NOT implicitly wrap multi-expression bodies in (begin ...)
;;      when running a pass that does not explicitly desugar lambda/let/letrec bodies.
(define-pass test-inc-constants-src : L_src (ir) -> L_src ()
  (Expr : Expr (ir) -> Expr ()
    (,c (guard (number? c))
     (+ c 1))))

(assert-equal "schema catamorphism preserves multi-body lambda in L_src without implicit (begin ...)"
              '(lambda (x y) (set! x 11) (+ x 21))
              (test-inc-constants-src '(lambda (x y) (set! x 10) (+ x 20))))

(assert-equal "schema catamorphism preserves multi-body let and letrec in L_src without implicit (begin ...)"
              '(let ((a 2) (b 3)) (display a) (+ a b 4))
              (test-inc-constants-src '(let ((a 1) (b 2)) (display a) (+ a b 3))))

(assert-equal "schema catamorphism preserves multi-body named-let in L_src without implicit (begin ...)"
              '(let loop ((i 1)) (display i) (loop (+ i 2)))
              (test-inc-constants-src '(let loop ((i 0)) (display i) (loop (+ i 1)))))

;; 14.2 Verify schema-driven catamorphism over L_lifted (%program and %function)
;;      without needing explicit boilerplate rules for %program or %function
(define-pass test-lifted-inc : L_lifted (ir) -> L_lifted ()
  (Expr : Expr (ir) -> Expr ()
    ((%box-fixnum ,e)
     (list '%box-fixnum (list '%unbox-fixnum (Expr e))))))

(let* ((lifted-in '(%program ((%function fn_add (a b) (%box-fixnum x)))
                             (if #t (%box-fixnum y) 0)))
       (lifted-out (test-lifted-inc lifted-in)))
  (assert-equal "schema catamorphism traverses L_lifted %program and %function automatically"
                '(%program ((%function fn_add (a b) (%box-fixnum (%unbox-fixnum x))))
                           (if #t (%box-fixnum (%unbox-fixnum y)) 0))
                lifted-out)
  (assert-true "schema catamorphism output on L_lifted satisfies L_lifted?"
               (L_lifted? lifted-out)))

;; 14.3 Verify schema-driven catamorphism over L_lir_raw / L_lir_canonical
;;      (%lir-program, %lir-function, %lir-main, %block) with ONLY an Inst rule!
(define-pass test-lir-nop-to-inc : L_lir_raw (ir) -> L_lir_canonical ()
  (Inst : Inst (ir) -> Inst ()
    ((%nop)
     '(%inc %rax))))

(let* ((lir-in '(%lir-program
                  (strings ((L_str0 "hello")))
                  (stackmaps ((L_sp0 16 3)))
                  (%lir-functions
                    (%lir-function L_fn1 (params (x y)) (frame-size 16)
                      (body
                        (%block L_entry (x y)
                          (%nop)
                          (%mov %rax 10)
                          (%return %rax)))))
                  (%lir-main (frame-size 8)
                    (body
                      (%nop)
                      (%return 0)))))
       (lir-out (test-lir-nop-to-inc lir-in)))
  (assert-equal "schema catamorphism traverses LIR %lir-program, %lir-function, %block, and %lir-main automatically"
                '(%lir-program
                  (strings ((L_str0 "hello")))
                  (stackmaps ((L_sp0 16 3)))
                  (%lir-functions
                    (%lir-function L_fn1 (params (x y)) (frame-size 16)
                      (body
                        (%block L_entry (x y)
                          (%inc %rax)
                          (%mov %rax 10)
                          (%return %rax)))))
                  (%lir-main (frame-size 8)
                    (body
                      (%inc %rax)
                      (%return 0))))
                lir-out)
  (assert-true "schema catamorphism output on LIR satisfies L_lir_canonical?"
               (L_lir_canonical? lir-out)))

;; 14.4 Verify schema-driven catamorphism over Backend L_asm_x86 and L_asm_aarch64
(define-pass test-asm-x86-rewrite : L_asm_x86 (ir) -> L_asm_x86 ()
  (Inst : Inst (ir) -> Inst ()
    ((inc ,opnd)
     (list 'add opnd 1))))

(let* ((asm-in '(%asm-program
                  (strings ((L_s0 "msg")))
                  (stackmaps ((L_sp0 8 1)))
                  (%asm-functions
                    (%asm-function L_f0 (frame-size 8)
                      (body
                        (%label L_f0)
                        (inc rax)
                        (ret))))
                  (%asm-main (frame-size 0)
                    (body
                      (inc rbx)
                      (ret)))))
       (asm-out (test-asm-x86-rewrite asm-in)))
  (assert-equal "schema catamorphism traverses L_asm_x86 %asm-program, %asm-function, and %asm-main automatically"
                '(%asm-program
                  (strings ((L_s0 "msg")))
                  (stackmaps ((L_sp0 8 1)))
                  (%asm-functions
                    (%asm-function L_f0 (frame-size 8)
                      (body
                        (%label L_f0)
                        (add rax 1)
                        (ret))))
                  (%asm-main (frame-size 0)
                    (body
                      (add rbx 1)
                      (ret))))
                asm-out)
  (assert-true "schema catamorphism output satisfies L_asm_x86?"
               (L_asm_x86? asm-out)))

;; 14.5 Verify schema-driven pure analyzer (lang-out = '*) over LIR only visits nonterminals
;;      and does NOT visit terminal labels or parameter symbols.
(define-pass test-count-lir-movs : L_lir_canonical (ir acc) -> * (acc)
  (Inst : Inst (ir acc) -> * (acc)
    ((%mov ,dst ,src)
     (+ acc 1))))

(let ((lir-sample '(%lir-program
                     (strings ((L_str0 "hello")))
                     (stackmaps ((L_sp0 16 3)))
                     (%lir-functions
                       (%lir-function L_fn1 (params (x y)) (frame-size 16)
                         (body
                           (%block L_entry (x y)
                             (%mov %rax 1)
                             (%mov %rbx 2)
                             (%return %rax)))))
                     (%lir-main (frame-size 8)
                       (body
                         (%mov %rcx 3)
                         (%return 0))))))
  (assert-equal "schema-driven pure analyzer counts %mov instructions across LIR blocks and functions"
                3
                (test-count-lir-movs lir-sample 0)))

;;; -----------------------------------------------------------------------
;;; 15. Catamorphism Structural Sharing / Smart Reconstruction (DSN-33-01 T1.3)
;;; -----------------------------------------------------------------------

;; 15.1 Direct helper tests: nanopass-cons-sharing & nanopass-map-sharing
(let* ((p '(a . b))
       (same-p (nanopass-cons-sharing p 'a 'b))
       (diff-p (nanopass-cons-sharing p 'x 'b))
       (lst '(1 2 3 4))
       (same-lst (nanopass-map-sharing (lambda (x) x) lst))
       (part-lst (nanopass-map-sharing (lambda (x) (if (= x 2) 20 x)) lst)))
  (assert-true "nanopass-cons-sharing returns identical pair (eq?) when car and cdr are unchanged"
               (eq? p same-p))
  (assert-false "nanopass-cons-sharing allocates new pair when car changes"
                (eq? p diff-p))
  (assert-true "nanopass-map-sharing returns identical list (eq?) when all elements are unchanged"
               (eq? lst same-lst))
  (assert-false "nanopass-map-sharing allocates new list prefix when an element changes"
                (eq? lst part-lst))
  (assert-true "nanopass-map-sharing shares unchanged tail spine (cddr) via eq?"
               (eq? (cddr lst) (cddr part-lst))))

;; 15.2 Unchanged AST traversal across HIR (L_core) preserves root pointer identity (eq?)
(define-pass test-noop-core-pass : L_core (ir) -> L_core ()
  (Expr : Expr (ir) -> Expr ()
    ((%nonexistent-sentinel ,x) x)))

(let* ((core-ast '(%program
                   ((define f (lambda (x y) (if (< x y) (+ x 1) (begin (set! x 0) (* y 2))))))
                   (let ((a 10) (b 20))
                     (f a b))))
       (core-out (test-noop-core-pass core-ast)))
  (assert-true "noop pass over L_core preserves root pointer identity (eq?)"
               (eq? core-ast core-out)))

;; 15.3 Partial AST modification in L_core shares untouched sibling subtrees via eq?
(define-pass test-rewrite-sentinel-core : L_core (ir) -> L_core ()
  (Expr : Expr (ir) -> Expr ()
    ((rewrite-me ,x) (list '+ x 999))))

(let* ((untouched-def '(define helper (lambda (n) (* n n))))
       (untouched-else '(let ((z 42)) (+ z 100)))
       (core-in (list '%program
                      (list untouched-def)
                      (list 'if '(#t)
                            '(rewrite-me 1)
                            untouched-else)))
       (core-out (test-rewrite-sentinel-core core-in)))
  (assert-false "modified L_core root is a new pair"
                (eq? core-in core-out))
  (assert-equal "modified L_core target branch is rewritten"
                '(+ 1 999)
                (caddr (caddr core-out)))
  (assert-true "untouched top-level define list in %program is shared via eq?"
               (eq? (cadr core-in) (cadr core-out)))
  (assert-true "untouched top-level define node in %program is shared via eq?"
               (eq? untouched-def (car (cadr core-out))))
  (assert-true "untouched else-branch subtree in if is shared via eq?"
               (eq? untouched-else (cadddr (caddr core-out)))))

;; 15.4 Unchanged and partially modified LIR (L_lir_raw -> L_lir_canonical) preserves eq? sharing
(let* ((untouched-fn '(%lir-function L_unchanged (params (a)) (frame-size 8)
                        (body
                          (%block L_entry (a)
                            (%mov %rax a)
                            (%return %rax)))))
       (modified-fn '(%lir-function L_target (params (b)) (frame-size 8)
                       (body
                         (%block L_b0 (b)
                           (%nop)
                           (%return %rax)))))
       (lir-noop-in (list '%lir-program
                          '(strings ((L_str0 "hello")))
                          '(stackmaps ((L_sp0 8 1)))
                          (list '%lir-functions untouched-fn)
                          '(%lir-main (frame-size 0)
                             (body
                               (%mov %rbx 5)
                               (%return %rbx)))))
       (lir-noop-out (test-lir-nop-to-inc lir-noop-in))
       (lir-part-in (list '%lir-program
                          '(strings ((L_str0 "hello")))
                          '(stackmaps ((L_sp0 8 1)))
                          (list '%lir-functions untouched-fn modified-fn)
                          '(%lir-main (frame-size 0)
                             (body
                               (%mov %rbx 5)
                               (%return %rbx)))))
       (lir-part-out (test-lir-nop-to-inc lir-part-in)))
  (assert-true "L_lir_canonical pass with no matching rules returns eq? root AST"
               (eq? lir-noop-in lir-noop-out))
  (assert-false "L_lir_canonical pass with partial rewrite allocates new root"
                (eq? lir-part-in lir-part-out))
  (assert-true "untouched %lir-function in %lir-functions is shared via eq?"
               (eq? untouched-fn (cadr (cadddr lir-part-out))))
  (assert-true "untouched %lir-main is shared via eq?"
               (eq? (car (cddddr lir-part-in)) (car (cddddr lir-part-out)))))

;; 15.5 Unchanged L_asm_x86 AST preserves eq? root identity
(let* ((asm-noop-in '(%asm-program
                      (strings ((L_s0 "msg")))
                      (stackmaps ((L_sp0 8 1)))
                      (%asm-functions
                        (%asm-function L_f0 (frame-size 8)
                          (body
                            (%label L_f0)
                            (mov rax 1)
                            (ret))))
                      (%asm-main (frame-size 0)
                        (body
                          (mov rbx 2)
                          (ret)))))
       (asm-noop-out (test-asm-x86-rewrite asm-noop-in)))
  (assert-true "L_asm_x86 pass with no matching instructions returns eq? root AST"
               (eq? asm-noop-in asm-noop-out)))

;;; -----------------------------------------------------------------------
;;; 16. Picopass / Femtopass / Attopass DSL & First-Class Rule Descriptors (DSN-33-01 T2.1)
;;; -----------------------------------------------------------------------

;; 16.1 define-picopass: local syntax rewriting with 1-line standalone execution
(define-picopass rule-test-and
  (Expr
    ((and) #t)
    ((and ,e) e)
    ((and ,e1 ,e2 ...) `(if ,e1 (and ,e2 ...) #f))))

(assert-equal "define-picopass rule-test-and on (and) returns #t"
              #t
              (rule-test-and '(and)))

(assert-equal "define-picopass rule-test-and on single-arg (and x) returns x"
              'x
              (rule-test-and '(and x)))

(assert-equal "define-picopass rule-test-and on (and a b) desugars to 1-step if"
              '(if a (and b) #f)
              (rule-test-and '(and a b)))

(assert-equal "define-picopass rule-test-and on unmatched form returns #f (fall-through)"
              #f
              (rule-test-and '(or a b)))

(define-picopass rule-test-letrec
  (Expr
    ((letrec ((,x ,e1) ...) ,body ...)
     `(let ((,x (void)) ...)
        (begin (set! ,x ,e1) ... ,body ...)))))

(assert-equal "define-picopass rule-test-letrec rewrites to let with void bindings"
              '(let ((f (void))) (begin (set! f (lambda (x) x)) (f 1)))
              (rule-test-letrec '(letrec ((f (lambda (x) x))) (f 1))))

;; 16.2 define-femtopass: non-destructive attribute computation
(define-femtopass femto-test-free-vars
  (Expr : (bound-env) -> (free-set)
    (,x (guard (symbol? x))
        (if (memq x bound-env) '() (list x)))
    ((lambda (,params ...) ,body)
     (femto-recurse body (append params bound-env)))))

(assert-equal "define-femtopass on unbound symbol returns singleton list"
              '(x)
              (femto-test-free-vars 'x '()))

(assert-equal "define-femtopass on bound symbol returns empty list"
              '()
              (femto-test-free-vars 'x '(x)))

(assert-equal "define-femtopass on bound lambda returns empty list"
              '()
              (femto-test-free-vars '(lambda (x) x) '()))

(assert-equal "define-femtopass on lambda with free variable returns free var"
              '(y)
              (femto-test-free-vars '(lambda (x) y) '()))

(assert-equal "define-femtopass on unmatched constant returns #f"
              #f
              (femto-test-free-vars 42 '()))

;; 16.3 define-attopass: atomic proposition assertions
(define-attopass atto-test-no-raw-syntax
  (Expr
    ((let-syntax ,_ ...)
     (picopass-fail "unexpanded let-syntax encountered" ir))
    ((letrec-syntax ,_ ...)
     (picopass-fail "unexpanded letrec-syntax encountered" ir))))

(assert-equal "define-attopass on valid AST returns #t"
              #t
              (atto-test-no-raw-syntax '(if a b c)))

(let ((caught-let-syntax
       (guard (ex (else 'caught-let-syntax-error))
         (atto-test-no-raw-syntax '(let-syntax ((m (syntax-rules ()))) 42)))))
  (assert-equal "define-attopass raises picopass-fail on let-syntax violation"
                'caught-let-syntax-error
                caught-let-syntax))

(let ((caught-letrec-syntax
       (guard (ex (else 'caught-letrec-syntax-error))
         (atto-test-no-raw-syntax '(letrec-syntax ((m (syntax-rules ()))) 42)))))
  (assert-equal "define-attopass raises picopass-fail on letrec-syntax violation"
                'caught-letrec-syntax-error
                caught-letrec-syntax))

;; 16.4 First-Class Rule Descriptor Reflection & Global Registry Lookup
(let* ((desc-and (nanopass-lookup-rule 'rule-test-and))
       (desc-by-proc (nanopass-lookup-rule rule-test-and))
       (desc-letrec (nanopass-lookup-rule 'rule-test-letrec))
       (desc-femto (nanopass-lookup-rule 'femto-test-free-vars))
       (desc-atto (nanopass-lookup-rule 'atto-test-no-raw-syntax)))
  (assert-true "rule-descriptor? returns #t for registered picopass"
               (rule-descriptor? desc-and))
  (assert-true "nanopass-lookup-rule resolves identical descriptor by symbol and by proc"
               (eq? desc-and desc-by-proc))
  (assert-true "rule-descriptor alias resolves descriptor"
               (eq? desc-and (rule-descriptor 'rule-test-and)))
  (assert-equal "rule-name matches defined symbol"
                'rule-test-and
                (rule-name desc-and))
  (assert-equal "rule-kind is 'pico for define-picopass"
                'pico
                (rule-kind desc-and))
  (assert-equal "rule-nt-name is 'Expr"
                'Expr
                (rule-nt-name desc-and))
  (assert-equal "rule-head-tags for rule-test-and is '(and)"
                '(and)
                (rule-head-tags desc-and))
  (assert-equal "rule-reads for rule-test-and contains 'and"
                '(and)
                (rule-reads desc-and))
  (assert-true "rule-writes for rule-test-and contains 'if"
               (if (memq 'if (rule-writes desc-and)) #t #f))
  (assert-equal "rule-head-tags for rule-test-letrec is '(letrec)"
                '(letrec)
                (rule-head-tags desc-letrec))
  (assert-equal "rule-eliminates for rule-test-letrec is '(letrec)"
                '(letrec)
                (rule-eliminates desc-letrec))
  (assert-equal "rule-kind is 'femto for define-femtopass"
                'femto
                (rule-kind desc-femto))
  (assert-equal "rule-head-tags for femto-test-free-vars is wildcard '*"
                '*
                (rule-head-tags desc-femto))
  (assert-equal "rule-kind is 'atto for define-attopass"
                'atto
                (rule-kind desc-atto))
  (assert-equal "rule-head-tags for atto-test-no-raw-syntax is '(let-syntax letrec-syntax)"
                '(let-syntax letrec-syntax)
                (rule-head-tags desc-atto))
  (assert-true "rule-proc returns executable procedure"
               (procedure? (rule-proc desc-and)))
  (assert-equal "executing (rule-proc desc) produces same result as direct call"
                '(if a (and b) #f)
                ((rule-proc desc-and) '(and a b)))
  (assert-true "nanopass-get-all-rules contains rule-test-and"
               (if (memq desc-and (nanopass-get-all-rules)) #t #f)))

;;; -----------------------------------------------------------------------
;;; 17. Picopass Strategy Combinators (DSN-33-01 T2.2)
;;; -----------------------------------------------------------------------

;; 17.1 picopass-seq: sequential composition (p1 ▷ p2)
(define-picopass rule-seq-step1
  (Expr
    ((inc-double ,x)
     (list 'double (list '+ x 1)))))

(define-picopass rule-seq-step2
  (Expr
    ((double ,y)
     (list '* y 2))))

(define-picopass rule-seq-step3
  (Expr
    ((* ,a 2)
     (list 'half-shift a))))

(define seq-step1-2 (picopass-seq rule-seq-step1 rule-seq-step2))

(assert-equal "picopass-seq applies p1 then p2 on matching input"
              '(* (+ 5 1) 2)
              (seq-step1-2 '(inc-double 5)))

(assert-equal "picopass-seq returns #f if p1 does not match"
              #f
              (seq-step1-2 '(other-tag 5)))

(define-picopass rule-only-literal
  (Expr
    ((double 999) 12345)))

(define seq-partial (picopass-seq rule-seq-step1 rule-only-literal))

(assert-equal "picopass-seq preserves p1 result if p2 falls through"
              '(double (+ 10 1))
              (seq-partial '(inc-double 10)))

(define seq-list-3 (picopass-compose-list (list rule-seq-step1 rule-seq-step2 rule-seq-step3)))

(assert-equal "picopass-compose-list chains 3 rules sequentially"
              '(half-shift (+ 3 1))
              (seq-list-3 '(inc-double 3)))

(define seq-macro-3 (picopass-seq* rule-seq-step1 rule-seq-step2 rule-seq-step3))

(assert-equal "picopass-seq* macro chains multiple rules"
              '(half-shift (+ 7 1))
              (seq-macro-3 '(inc-double 7)))

;; 17.2 picopass-choice: deterministic priority choice (p1 ⊕ p2)
(define-picopass rule-choice-zero
  (Expr
    ((fast-add 0 ,x)
     x)))

(define-picopass rule-choice-general
  (Expr
    ((fast-add ,x ,y)
     (list '+ x y))))

(define-picopass rule-choice-fallback
  (Expr
    ((fallback-op ,x)
     (list 'fallback x))))

(define choice-combined (picopass-choice rule-choice-zero rule-choice-general))

(assert-equal "picopass-choice selects specialized rule when matched"
              'foo
              (choice-combined '(fast-add 0 foo)))

(assert-equal "picopass-choice falls through to general rule when special fails"
              '(+ 3 4)
              (choice-combined '(fast-add 3 4)))

(assert-equal "picopass-choice returns #f when neither rule matches"
              #f
              (choice-combined '(unrelated-op 1 2)))

(define choice-list-3 (picopass-choice-list (list rule-choice-zero rule-choice-general rule-choice-fallback)))

(assert-equal "picopass-choice-list selects third rule in chain"
              '(fallback 99)
              (choice-list-3 '(fallback-op 99)))

(define choice-macro-3 (picopass-choice* rule-choice-zero rule-choice-general rule-choice-fallback))

(assert-equal "picopass-choice* macro matches first rule"
              'bar
              (choice-macro-3 '(fast-add 0 bar)))

(assert-equal "picopass-choice* macro matches third rule"
              '(fallback 77)
              (choice-macro-3 '(fallback-op 77)))

;; 17.3 picopass-fixpoint: local fixpoint iteration (p*)
(define-picopass rule-peel-nest
  (Expr
    ((nest (nest ,x))
     (list 'nest x))))

(define fp-peel (picopass-fixpoint rule-peel-nest))

(assert-equal "picopass-fixpoint iteratively peels nested constructs"
              '(nest 42)
              (fp-peel '(nest (nest (nest (nest 42))))))

(assert-equal "picopass-fixpoint returns #f when rule never matches"
              #f
              (fp-peel '(nest 42)))

;; Infinite rewrite loop detection and fail-closed termination
(define-picopass rule-infinite-cycle
  (Expr
    ((flip ,x) (list 'flop x))
    ((flop ,x) (list 'flip x))))

(let ((caught-cycle
       (guard (ex (else 'caught-cycle-error))
         ((picopass-fixpoint-limit rule-infinite-cycle 16) '(flip 100)))))
  (assert-equal "picopass-fixpoint aborts with picopass-fail on infinite cycle"
                'caught-cycle-error
                caught-cycle))

;; 17.4 picopass-when: guarded rule application (guard ⇒ pico)
(define (test-guard-predicate expr)
  (and (pair? expr)
       (pair? (cdr expr))
       (number? (cadr expr))
       (> (cadr expr) 10)))

(define-picopass rule-guarded-target
  (Expr
    ((scale ,n)
     (list '* n 100))))

(define when-rule (picopass-when test-guard-predicate rule-guarded-target))

(assert-equal "picopass-when applies rule when guard predicate is satisfied"
              '(* 25 100)
              (when-rule '(scale 25)))

(assert-equal "picopass-when returns #f when guard predicate is not satisfied"
              #f
              (when-rule '(scale 5)))

(assert-equal "picopass-when returns #f on non-matching AST tag"
              #f
              (when-rule '(unrelated 50)))

;; 17.5 Metadata retention & Reflection on combined rules
(let ((desc-seq (rule-descriptor seq-step1-2))
      (desc-choice (rule-descriptor choice-combined))
      (desc-fp (rule-descriptor fp-peel))
      (desc-when (rule-descriptor when-rule)))
  (assert-true "rule-descriptor? returns #t for picopass-seq"
               (rule-descriptor? desc-seq))
  (assert-equal "rule-kind is 'pico for picopass-seq"
                'pico
                (rule-kind desc-seq))
  (assert-equal "rule-head-tags for picopass-seq matches initial rule head-tags"
                '(inc-double)
                (rule-head-tags desc-seq))
  (assert-true "rule-reads for picopass-seq contains inc-double and double"
               (and (memq 'inc-double (rule-reads desc-seq))
                    (memq 'double (rule-reads desc-seq))))
  (assert-true "rule-descriptor? returns #t for picopass-choice"
               (rule-descriptor? desc-choice))
  (assert-equal "rule-head-tags for picopass-choice contains fast-add"
                '(fast-add)
                (rule-head-tags desc-choice))
  (assert-true "rule-descriptor? returns #t for picopass-fixpoint"
               (rule-descriptor? desc-fp))
  (assert-equal "rule-head-tags for picopass-fixpoint is '(nest)"
                '(nest)
                (rule-head-tags desc-fp))
  (assert-true "rule-descriptor? returns #t for picopass-when"
               (rule-descriptor? desc-when))
  (assert-equal "rule-head-tags for picopass-when is '(scale)"
                '(scale)
                (rule-head-tags desc-when)))

;;; =======================================================================
;;; 18. define-pass fuse-rules & Head-Tag O(1) Dispatch (DSN-33-01 T3.1)
;;; =======================================================================

;; 18.1 Define picopasses for rule fusion
(define-picopass rule-fuse-add-zero
  (Expr
    ((+ ,x 0) x)))

(define-picopass rule-fuse-mul-one
  (Expr
    ((* ,x 1) x)))

(define-picopass rule-fuse-mul-zero
  (Expr
    ((* ,x 0) 0)))

;; 18.2 Top-level (fuse-rules ...) in define-pass
(define-pass test-pass-fused-top : L_src (ir) -> L_src ()
  (fuse-rules rule-fuse-add-zero rule-fuse-mul-one rule-fuse-mul-zero))

(assert-equal "top-level fuse-rules rewrites (+ a 0) -> a"
              'a
              (test-pass-fused-top '(+ a 0)))

(assert-equal "top-level fuse-rules rewrites (* b 1) -> b"
              'b
              (test-pass-fused-top '(* b 1)))

(assert-equal "top-level fuse-rules rewrites (* c 0) -> 0"
              0
              (test-pass-fused-top '(* c 0)))

(assert-equal "top-level fuse-rules catamorphism on nested tree (list (+ a 0) (* b 1)) -> (list a b)"
              '(list a b)
              (test-pass-fused-top '(list (+ a 0) (* b 1))))

(assert-equal "top-level fuse-rules leaves unmatched construct untouched (- a 0)"
              '(- a 0)
              (test-pass-fused-top '(- a 0)))

;; 18.3 Inline (fuse-rules ...) mixed with custom rules in NT clause
(define-pass test-pass-fused-inline : L_src (ir) -> L_src ()
  (Expr : Expr (ir) -> Expr ()
    (fuse-rules rule-fuse-add-zero rule-fuse-mul-one)
    ((- ,x 0) x)
    ((/ ,x 1) x)))

(assert-equal "inline fuse-rules handles fused rule (+ x 0) -> x"
              'foo
              (test-pass-fused-inline '(+ foo 0)))

(assert-equal "inline fuse-rules handles fused rule (* x 1) -> x"
              'bar
              (test-pass-fused-inline '(* bar 1)))

(assert-equal "inline fuse-rules handles inline rule (- x 0) -> x"
              'baz
              (test-pass-fused-inline '(- baz 0)))

(assert-equal "inline fuse-rules handles inline rule (/ x 1) -> x"
              'qux
              (test-pass-fused-inline '(/ qux 1)))

;; 18.4 fuse-tree-rules alias compatibility
(define-pass test-pass-fused-tree : L_src (ir) -> L_src ()
  (Expr : Expr (ir) -> Expr ()
    (fuse-tree-rules rule-fuse-add-zero rule-fuse-mul-zero)))

(assert-equal "fuse-tree-rules rewrites (+ z 0) -> z"
              'z
              (test-pass-fused-tree '(+ z 0)))

(assert-equal "fuse-tree-rules rewrites (* z 0) -> 0"
              0
              (test-pass-fused-tree '(* z 0)))

;; 18.5 O(1) Head-Tag dispatch: multiple tags with atom fast-path & fallbacks
(define-pass test-pass-head-tag-dispatch : L_src (ir) -> L_src ()
  (Expr : Expr (ir) -> Expr ()
    ((tag-alpha ,x) (list 'alpha-rewritten x))
    ((tag-beta ,x ,y) (list 'beta-rewritten x y))
    ((tag-gamma ,x) (list 'gamma-rewritten x))
    ;; Atom fast-path rule (guard on numbers)
    (,c (guard (number? c)) (+ c 1000))))

(assert-equal "head-tag dispatch jumps to tag-alpha"
              '(alpha-rewritten 42)
              (test-pass-head-tag-dispatch '(tag-alpha 42)))

(assert-equal "head-tag dispatch jumps to tag-beta"
              '(beta-rewritten 10 20)
              (test-pass-head-tag-dispatch '(tag-beta 10 20)))

(assert-equal "head-tag dispatch jumps to tag-gamma"
              '(gamma-rewritten 99)
              (test-pass-head-tag-dispatch '(tag-gamma 99)))

(assert-equal "head-tag dispatch atom fast-path rewrites constant 7 -> 1007"
              1007
              (test-pass-head-tag-dispatch 7))

(assert-equal "head-tag dispatch unlisted tag falls through to catamorphism and rewrites children"
              '(unlisted-tag (alpha-rewritten 1))
              (test-pass-head-tag-dispatch '(unlisted-tag (tag-alpha 1))))

(assert-equal "head-tag dispatch unlisted tag with untouched subforms is preserved"
              '(unlisted-tag (untouched symbol-x))
              (test-pass-head-tag-dispatch '(unlisted-tag (untouched symbol-x))))

;; 18.6 Rule order preservation within the same tag bucket
(define-picopass rule-head-tag-first
  (Expr
    ((same-tag 0) 'first-match)))

(define-picopass rule-head-tag-second
  (Expr
    ((same-tag ,x) (list 'second-match x))))

(define-pass test-pass-bucket-order : L_src (ir) -> L_src ()
  (fuse-rules rule-head-tag-first rule-head-tag-second))

(assert-equal "same tag bucket evaluates first rule first when matching"
              'first-match
              (test-pass-bucket-order '(same-tag 0)))

(assert-equal "same tag bucket falls through to second rule when first fails"
              '(second-match 42)
              (test-pass-bucket-order '(same-tag 42)))

;;; =======================================================================
;;; Section 19: Local Re-dispatch and Schema Coverage Validation (DSN-33-01 T3.2)
;;; =======================================================================

(display "\n--- [Section 19: Local Re-dispatch & Schema Coverage Validation] ---") (newline)

;; 19.1 Schema Coverage API: nanopass-get-language-removed-tags
(assert-equal "intra-language (L_src -> L_src) has no removed tags"
              '()
              (nanopass-get-language-removed-tags 'L_src 'L_src))

(assert-equal "nanopass-get-language-removed-tags detects removed cond in L_test_core"
              '(cond)
              (nanopass-get-language-removed-tags 'L_test_src 'L_test_core))

;; 19.2 Schema Coverage API: nanopass-collect-rule-eliminates
(define-picopass rule-test-elim-cond
  (Expr
    ((cond (else ,b)) b))
  :eliminates (cond))

(define-picopass rule-test-elim-case
  (Expr
    ((case ,k ((,c) ,b)) b))
  :eliminates (case))

(let ((elims (nanopass-collect-rule-eliminates (list rule-test-elim-cond rule-test-elim-case))))
  (assert-true "collect-rule-eliminates contains cond" (memq 'cond elims))
  (assert-true "collect-rule-eliminates contains case" (memq 'case elims)))

;; 19.3 Schema Coverage API: nanopass-verify-fusion-coverage
(let ((missing (nanopass-verify-fusion-coverage 'L_test_src 'L_test_core (list rule-test-elim-cond))))
  (assert-equal "verify-fusion-coverage returns empty on 100% coverage of removed cond"
                '()
                missing))

(let ((missing (nanopass-verify-fusion-coverage 'L_test_src 'L_test_core (list rule-test-elim-case))))
  (assert-equal "verify-fusion-coverage detects missing cond when only case is provided"
                '(cond)
                missing))

;; 19.4 Multi-Stage Desugaring via Local Re-dispatch
;; rule-stage-case produces a template containing (stage-or ...)
;; rule-stage-or desugars (stage-or ...) into (if ...)
;; Neither rule manually recurses or calls (Expr ...)
(define-picopass rule-stage-case
  (Expr
    ((stage-case ,key ((,c) ,b))
     (list 'if (list 'stage-or (list 'eqv? key (list 'quote c))) b (list 'void)))))

(define-picopass rule-stage-or
  (Expr
    ((stage-or ,e) e)
    ((stage-or ,e1 ,e2 ...)
     (list 'if e1 #t (cons 'stage-or e2)))))

(define-pass test-pass-multistage-desugar : L_src (ir) -> L_src ()
  (fuse-rules rule-stage-case rule-stage-or))

(assert-equal "multistage desugaring completely lowers stage-case through stage-or in 1 pass"
              '(if (eqv? x '1) 100 (void))
              (test-pass-multistage-desugar '(stage-case x ((1) 100))))

;; 19.5 Repeated Rewriting on Same Node Position (Peeling)
(define-picopass rule-stage-peel
  (Expr
    ((peel (peel . ,rest)) (cons 'peel rest))))

(define-pass test-pass-peel-fusion : L_src (ir) -> L_src ()
  (fuse-rules rule-stage-peel))

(assert-equal "local re-dispatch peels nested 3-deep construct on same node position down to 1"
              '(peel 999)
              (test-pass-peel-fusion '(peel (peel (peel 999)))))

;; 19.6 NT clause with explicit (redispatch) directive
(define-pass test-pass-inline-redispatch : L_src (ir) -> L_src ()
  (Expr : Expr (ir) -> Expr ()
    (redispatch)
    ((inline-peel (inline-peel . ,rest)) (cons 'inline-peel rest))))

(assert-equal "inline NT clause with explicit (redispatch) directive performs multi-step peeling"
              '(inline-peel 555)
              (test-pass-inline-redispatch '(inline-peel (inline-peel 555))))

;; 19.7 Fuel Guard: Infinite Rewrite Cycle Detection (CWE-400 mitigation)
(define-picopass rule-cycle-ping
  (Expr
    ((ping ,x) (list 'pong x))))

(define-picopass rule-cycle-pong
  (Expr
    ((pong ,x) (list 'ping x))))

(define-pass test-pass-infinite-cycle : L_src (ir) -> L_src ()
  (fuse-rules rule-cycle-ping rule-cycle-pong))

(let ((caught-fuel-error
       (guard (ex (else 'fuel-exhausted-caught))
         (test-pass-infinite-cycle '(ping 12345)))))
  (assert-equal "fuel guard aborts infinite cyclic rewrite loop cleanly and terminates"
                'fuel-exhausted-caught
                caught-fuel-error))

;; 19.8 Dynamic Fuel Limit Reconfiguration
(let* ((orig-limit *nanopass-redispatch-limit*)
       (caught-early-fuel
        (begin
          (set! *nanopass-redispatch-limit* 4)
          (let ((res (guard (ex (else 'fuel-limit-4-caught))
                       (test-pass-infinite-cycle '(ping 99)))))
            (set! *nanopass-redispatch-limit* orig-limit)
            res))))
  (assert-equal "reconfigured fuel limit of 4 traps infinite cycle at 4 steps"
                'fuel-limit-4-caught
                caught-early-fuel))

;;; =======================================================================
;;; 20. LIR Sliding Window Rules & Fixpoint Convergence (DSN-33-01 T3.3)
;;; =======================================================================
(display (string-append (string #\newline) "--- [Section 20: LIR fuse-window-rules & Sliding Window Convergence] ---" (string #\newline)))

;; 20.1 InstWindow Picopass Definitions
(define-picopass test-rule-lir-self-mov-elim
  (InstWindow
    (((%mov ,r ,r) . ,rest) rest)))

(define-picopass test-rule-lir-store-load-forward
  (InstWindow
    (((%store %rsp ,off ,src) (%load ,dst %rsp ,off) . ,rest)
     (if (equal? dst src)
         (cons `(%store %rsp ,off ,src) rest)
         (cons `(%store %rsp ,off ,src) (cons `(%mov ,dst ,src) rest))))))

(define-picopass test-rule-lir-zero-add-elim
  (InstWindow
    (((%add ,r 0) . ,rest) rest)
    (((%raw-add ,r 0) . ,rest) rest)))

(define-picopass test-rule-lir-load-add-store
  (InstWindow
    (((%load ,r %rsp ,off) (%add ,r 1) (%store %rsp ,off ,r) . ,rest)
     (cons `(%inc-mem %rsp ,off) rest))))

;; 20.2 Top-level (fuse-window-rules ...) in define-pass
(define-pass test-pass-lir-peephole : L_lir_raw (lir) -> L_lir_canonical ()
  (entry InstructionList)
  (fuse-window-rules
    test-rule-lir-self-mov-elim
    test-rule-lir-store-load-forward
    test-rule-lir-zero-add-elim
    test-rule-lir-load-add-store))

;; Test 1: Single instruction elimination (%mov %rax %rax)
(assert-equal "fuse-window-rules eliminates redundant self-move (%mov %rax %rax)"
              '((%mov %rbx %rcx))
              (test-pass-lir-peephole '((%mov %rax %rax) (%mov %rbx %rcx))))

;; Test 2: Store-Load forwarding (same register)
(assert-equal "fuse-window-rules eliminates reload into same register"
              '((%store %rsp 8 %rax))
              (test-pass-lir-peephole '((%store %rsp 8 %rax) (%load %rax %rsp 8))))

;; Test 3: Store-Load forwarding (different register -> %mov)
(assert-equal "fuse-window-rules forwards store to mov into different register"
              '((%store %rsp 16 %rax) (%mov %rbx %rax))
              (test-pass-lir-peephole '((%store %rsp 16 %rax) (%load %rbx %rsp 16))))

;; Test 4: Multi-pattern rule (%add and %raw-add by 0)
(assert-equal "fuse-window-rules eliminates %add and %raw-add by 0"
              '((%sub %rcx 1))
              (test-pass-lir-peephole '((%add %rax 0) (%raw-add %rbx 0) (%sub %rcx 1))))

;; Test 5: 3-instruction peephole fusion
(assert-equal "fuse-window-rules fuses 3-instruction load-add-store into %inc-mem"
              '((%inc-mem %rsp 24))
              (test-pass-lir-peephole '((%load %rax %rsp 24) (%add %rax 1) (%store %rsp 24 %rax))))

;; Test 6: Sliding window advancement without match
(assert-equal "fuse-window-rules preserves unmatched instructions in order"
              '((%jump L1) (%sub %rax 5) (%direct-call foo 0))
              (test-pass-lir-peephole '((%jump L1) (%sub %rax 5) (%direct-call foo 0))))

;; Test 7: Multistage Fixpoint Cascading (Pass 1 enables Pass 2)
(assert-equal "fuse-window-rules cascades multiple iterations to fixed-point"
              '((%store %rsp 8 %rax) (%mov %rbx %rax))
              (test-pass-lir-peephole '((%store %rsp 8 %rax)
                                        (%mov %rdi %rdi)
                                        (%load %rbx %rsp 8))))

;; 20.3 Inline NT clause with (fuse-window-rules ...)
(define-pass test-pass-inline-window : L_lir_raw (lir) -> L_lir_canonical ()
  (InstructionList (insts)
    (fuse-window-rules
      test-rule-lir-self-mov-elim
      test-rule-lir-zero-add-elim)))

(assert-equal "inline NT clause with fuse-window-rules performs peephole pass"
              '((%return))
              (test-pass-inline-window '((%mov %r12 %r12) (%add %r13 0) (%return))))

;; 20.4 Dual-Mode %lir-program Traversal & Reconstruction
(let* ((orig-prog
        (list '%lir-program
              '(strings ((s1 "hello")))
              '(stackmaps ())
              (list '%lir-functions
                    '(%lir-function f1 (params (%rdi)) (frame-size 16)
                                    (body (%mov %rax %rax) (%add %rax 0) (%return %rax)))
                    '(%lir-function f2 (params ()) (frame-size 32)
                                    (body (%store %rsp 8 %rdx) (%load %rdx %rsp 8) (%return))))
              '(%lir-main (frame-size 8)
                          (body (%raw-add %rsi 0) (%mov %rcx %rcx) (%return)))))
       (opt-prog (test-pass-lir-peephole orig-prog)))
  (assert-equal "fuse-window-rules preserves %lir-program header"
                '%lir-program
                (car opt-prog))
  (assert-equal "fuse-window-rules preserves strings and stackmaps entries"
                '((strings ((s1 "hello"))) (stackmaps ()))
                (list (cadr opt-prog) (caddr opt-prog)))
  (assert-equal "fuse-window-rules optimizes f1 body"
                '(body (%return %rax))
                (car (cddddr (car (cdr (cadddr opt-prog))))))
  (assert-equal "fuse-window-rules optimizes f2 body"
                '(body (%store %rsp 8 %rdx) (%return))
                (car (cddddr (cadr (cdr (cadddr opt-prog))))))
  (assert-equal "fuse-window-rules optimizes main body"
                '(body (%return))
                (caddr (car (cddddr opt-prog)))))

;; 20.5 Single %lir-function input
(assert-equal "fuse-window-rules handles single %lir-function node"
              '(%lir-function fn_test (params ()) (frame-size 0) (body))
              (test-pass-lir-peephole '(%lir-function fn_test (params ()) (frame-size 0) (body (%mov %rax %rax)))))

;; 20.6 Single %lir-main input
(assert-equal "fuse-window-rules handles single %lir-main node"
              '(%lir-main (frame-size 0) (body))
              (test-pass-lir-peephole '(%lir-main (frame-size 0) (body (%mov %rbx %rbx)))))

;; 20.7 Bounded Fixpoint Loop terminates safely on circular rewrite rules (CWE-400 mitigation)
(define-picopass rule-win-ping
  (InstWindow
    (((%w-ping ,x) . ,rest) (cons (list '%w-pong x) rest))))

(define-picopass rule-win-pong
  (InstWindow
    (((%w-pong ,x) . ,rest) (cons (list '%w-ping x) rest))))

(define-pass test-pass-win-loop : L_lir_raw (lir) -> L_lir_canonical ()
  (fuse-window-rules rule-win-ping rule-win-pong))

;; Test circular rewrite termination: must finish without hang
(let* ((orig-limit *nanopass-window-step-limit*)
       (res (begin
              (set! *nanopass-window-step-limit* 10)
              (let ((out (test-pass-win-loop '((%w-ping 42)))))
                (set! *nanopass-window-step-limit* orig-limit)
                out))))
  (assert-equal "window fuel guard terminates circular rewrite safely without hang"
                #t
                (pair? res)))

;;; =======================================================================
;;; 21. Rule Dependency DAG & Graph Analysis (DSN-33-01 T5.1)
;;; =======================================================================

(define-picopass rule-test-dag-a
  (Expr
    ((tag-a ,x) (list 'tag-b x))))
;; Manually attach reads/writes to rule descriptors for DAG testing
(let ((desc-a (rule-descriptor 'rule-test-dag-a)))
  (nanopass-register-rule!
   (nanopass-make-rule-descriptor 'rule-test-dag-a 'pico 'Expr '(tag-a) '(rx) '(ry) '()
                                  (rule-clauses desc-a) (rule-proc desc-a))))

(define-picopass rule-test-dag-b
  (Expr
    ((tag-b ,x) (list 'tag-c x))))
(let ((desc-b (rule-descriptor 'rule-test-dag-b)))
  (nanopass-register-rule!
   (nanopass-make-rule-descriptor 'rule-test-dag-b 'pico 'Expr '(tag-b) '(ry) '(rz) '()
                                  (rule-clauses desc-b) (rule-proc desc-b))))

(define-picopass rule-test-dag-c
  (Expr
    ((tag-c ,x) (list 'tag-c x))))
(let ((desc-c (rule-descriptor 'rule-test-dag-c)))
  (nanopass-register-rule!
   (nanopass-make-rule-descriptor 'rule-test-dag-c 'pico 'Expr '(tag-c) '(rw) '(rv) '()
                                  (rule-clauses desc-c) (rule-proc desc-c))))

;; 21.1 DAG Construction and Edge Detection
(let ((dag (nanopass-build-rule-dag '(rule-test-dag-a rule-test-dag-b rule-test-dag-c))))
  (assert-equal "rule-dag? predicate" #t (rule-dag? dag))
  (assert-equal "rule-dag nodes count" 3 (length (nanopass-rule-dag-nodes dag)))
  ;; Edge A -> B exists because A writes ry and B reads ry
  (assert-equal "rule-dag edges contains A -> B"
                #t
                (let ((edges (nanopass-rule-dag-edges dag)))
                  (and (pair? (member '(rule-test-dag-a . rule-test-dag-b) edges)) #t)))
  ;; In-degree and out-degree check
  (assert-equal "rule-dag in-degree of A is 0"
                0
                (cdr (assq 'rule-test-dag-a (nanopass-rule-dag-in-degrees dag))))
  (assert-equal "rule-dag in-degree of B is 1"
                1
                (cdr (assq 'rule-test-dag-b (nanopass-rule-dag-in-degrees dag))))
  (assert-equal "rule-dag in-degree of C is 0"
                0
                (cdr (assq 'rule-test-dag-c (nanopass-rule-dag-in-degrees dag))))

  ;; 21.2 Topological Sorting & Stratified Levels
  (let ((topo (nanopass-rule-dag-topological-sort dag))
        (levels (nanopass-rule-dag-stratify-levels dag)))
    (assert-equal "topological sort succeeds" #t (list? topo))
    (assert-equal "topological sort length" 3 (length topo))
    ;; A must appear before B in topological sort
    (let ((pos-a (length (member 'rule-test-dag-a topo)))
          (pos-b (length (member 'rule-test-dag-b topo))))
      (assert-equal "A precedes B in topological order" #t (> pos-a pos-b)))
    (assert-equal "stratify-levels returns 2 levels" 2 (length levels))
    (assert-equal "level 0 contains A and C" #t
                  (and (memq 'rule-test-dag-a (car levels))
                       (memq 'rule-test-dag-c (car levels))
                       #t))
    (assert-equal "level 1 contains B" '(rule-test-dag-b) (cadr levels)))

  ;; 21.3 Antichains & Independent Pairs
  (let ((antichains (nanopass-rule-dag-antichains dag)))
    (assert-equal "antichains count" 2 (length antichains))
    (assert-equal "A and C are independent pair"
                  #t
                  (nanopass-rule-dag-independent-pair? dag 'rule-test-dag-a 'rule-test-dag-c))
    (assert-equal "A and B are NOT independent pair (dependency path exists)"
                  #f
                  (nanopass-rule-dag-independent-pair? dag 'rule-test-dag-a 'rule-test-dag-b))))

;; 21.4 Cyclic Dependency Detection (SCC)
(define-picopass rule-test-cyc-1 (Expr ((cyc-1 ,x) x)))
(let ((desc-c1 (rule-descriptor 'rule-test-cyc-1)))
  (nanopass-register-rule!
   (nanopass-make-rule-descriptor 'rule-test-cyc-1 'pico 'Expr '(cyc-1) '(tag-p) '(tag-q) '()
                                  (rule-clauses desc-c1) (rule-proc desc-c1))))

(define-picopass rule-test-cyc-2 (Expr ((cyc-2 ,x) x)))
(let ((desc-c2 (rule-descriptor 'rule-test-cyc-2)))
  (nanopass-register-rule!
   (nanopass-make-rule-descriptor 'rule-test-cyc-2 'pico 'Expr '(cyc-2) '(tag-q) '(tag-p) '()
                                  (rule-clauses desc-c2) (rule-proc desc-c2))))

(define-picopass rule-test-cyc-3 (Expr ((cyc-3 ,x) x)))
(let ((desc-c3 (rule-descriptor 'rule-test-cyc-3)))
  (nanopass-register-rule!
   (nanopass-make-rule-descriptor 'rule-test-cyc-3 'pico 'Expr '(cyc-3) '(tag-p) '(tag-r) '()
                                  (rule-clauses desc-c3) (rule-proc desc-c3))))

(let ((cyc-dag (nanopass-build-rule-dag '(rule-test-cyc-1 rule-test-cyc-2 rule-test-cyc-3))))
  ;; Topological sort must return #f due to cycle
  (assert-equal "topological sort detects cycle and returns #f"
                #f
                (nanopass-rule-dag-topological-sort cyc-dag))
  ;; Tarjan SCC finds the cyclic component
  (let ((sccs (nanopass-rule-dag-scc cyc-dag))
        (cycles (nanopass-rule-dag-cycles cyc-dag)))
    (assert-equal "SCC finds components" #t (> (length sccs) 0))
    (assert-equal "cycles identifies 1 cycle group" 1 (length cycles))
    (let ((c (car cycles)))
      (assert-equal "cycle group has length 2" 2 (length c))
      (assert-equal "cycle group contains cyc-1" #t (and (memq 'rule-test-cyc-1 c) #t))
      (assert-equal "cycle group contains cyc-2" #t (and (memq 'rule-test-cyc-2 c) #t)))))

;;; =======================================================================
;;; 22. Femtopass Analysis Cache & Invalidation Protocol (DSN-33-01 T5.1)
;;; =======================================================================

;; 22.1 Basic Cache Hit, Miss, and Counting
(femto-cache-reset!)
(let* ((node-fn1 (list 'lambda '(x) '(+ x 1)))
       (node-fn2 (list 'define 'foo 42))
       (compute-count 0)
       (thunk (lambda ()
                (set! compute-count (+ compute-count 1))
                '(x))))
  ;; First call: miss
  (let ((res1 (femto-get-cached-attr 'free-vars node-fn1 thunk)))
    (assert-equal "femto cache returns computed value" '(x) res1)
    (assert-equal "compute count after miss is 1" 1 compute-count))
  ;; Second call on same node: hit!
  (let ((res2 (femto-get-cached-attr 'free-vars node-fn1 thunk)))
    (assert-equal "femto cache returns cached value" '(x) res2)
    (assert-equal "compute count after hit is still 1" 1 compute-count))

  ;; Stats inspection
  (let ((stats (femto-cache-stats)))
    (assert-equal "femto cache hits count is 1" 1 (cdr (assq 'hits stats)))
    (assert-equal "femto cache misses count is 1" 1 (cdr (assq 'misses stats)))
    (assert-equal "femto cache entries count is 1" 1 (cdr (assq 'entries stats))))
  (assert-equal "femto cache hit rate is 50%" 50 (femto-cache-hit-rate))

  ;; Distinct attribute on same node
  (let ((res-use (femto-get-cached-attr 'use-counts node-fn1 (lambda () 5))))
    (assert-equal "second attr on same node" 5 res-use))

  ;; Distinct node
  (let ((res-fn2 (femto-get-cached-attr 'free-vars node-fn2 (lambda () '()))))
    (assert-equal "attr on distinct node" '() res-fn2))

  ;; 22.2 Node-based Invalidation
  (femto-cache-invalidate-node! node-fn1)
  ;; node-fn2 is still cached
  (let ((old-compute compute-count))
    (femto-get-cached-attr 'free-vars node-fn2 (lambda () (set! compute-count (+ compute-count 1)) '()))
    (assert-equal "node-fn2 survives node-fn1 invalidation" old-compute compute-count)
    ;; node-fn1 was invalidated, so it must recompute
    (femto-get-cached-attr 'free-vars node-fn1 thunk)
    (assert-equal "node-fn1 recomputed after invalidation" (+ old-compute 1) compute-count)))

;; 22.3 Tag-based Selective Invalidation
(femto-cache-reset!)
(femto-register-attr-dependencies! 'free-vars '(lambda let letrec set!))
(femto-register-attr-dependencies! 'type-sig '(define :type))

(let ((node (list 'lambda '(a b) '(+ a b))))
  ;; Populate both attributes
  (femto-get-cached-attr 'free-vars node (lambda () '(a b)))
  (femto-get-cached-attr 'type-sig node (lambda () '(-> (int int) int)))

  (let ((misses-before (cdr (assq 'misses (femto-cache-stats)))))
    ;; Invalidate unrelated tags (e.g. vector bytevector) -> neither attribute invalidated!
    (femto-cache-invalidate-tags! '(vector bytevector))
    (femto-get-cached-attr 'free-vars node (lambda () (error "should not recompute")))
    (femto-get-cached-attr 'type-sig node (lambda () (error "should not recompute")))
    (assert-equal "unrelated tag invalidation preserves cache"
                  misses-before
                  (cdr (assq 'misses (femto-cache-stats))))

    ;; Invalidate 'lambda tag -> free-vars must be invalidated, but type-sig remains cached!
    (femto-cache-invalidate-tags! '(lambda))
    (let ((recomputed-free #f))
      (femto-get-cached-attr 'free-vars node (lambda () (set! recomputed-free #t) '(a b)))
      (assert-equal "free-vars recomputed after lambda tag invalidation" #t recomputed-free))
    ;; type-sig still cached (should not recompute)
    (let ((recomputed-type #f))
      (femto-get-cached-attr 'type-sig node (lambda () (set! recomputed-type #t) '(-> (int int) int)))
      (assert-equal "type-sig not recomputed because disjoint tags" #f recomputed-type))

    ;; Wildcard invalidation -> clears all
    (femto-cache-invalidate-tags! '*)
    (assert-equal "wildcard invalidation clears all entries"
                  0
                  (cdr (assq 'entries (femto-cache-stats))))))

;;; =======================================================================
;;; Section 23: Term DAG Hash-Consing & Memoized Catamorphism (DSN-33-01 T5.2)
;;; =======================================================================
(display "--- [Section 23: Term DAG Hash-Consing & Memoized Catamorphism] ---") (newline)

;; 23.1 Hash-Consing Constructor
(nanopass-hash-cons-reset!)
(let* ((p1 (nanopass-hash-cons 'a 'b))
       (p2 (nanopass-hash-cons 'a 'b))
       (p3 (nanopass-hash-cons 'a 'c)))
  (assert-equal "nanopass-hash-cons returns eq? pair for identical components"
                #t
                (eq? p1 p2))
  (assert-equal "nanopass-hash-cons returns different pair for different components"
                #f
                (eq? p1 p3)))

(let* ((l1 (nanopass-hash-cons-list '(1 2 3)))
       (l2 (nanopass-hash-cons-list '(1 2 3))))
  (assert-equal "nanopass-hash-cons-list returns eq? list for identical elements"
                #t
                (eq? l1 l2)))

;; 23.2 Scoped Term DAG Catamorphism Memoization
(nanopass-term-memo-reset!)
(let* ((shared-term (list '+ 1 2))
       (compound-ast (list 'begin shared-term shared-term shared-term))
       (visit-count 0)
       (transform-node
        (lambda (node)
          (set! visit-count (+ visit-count 1))
          (if (equal? node '(+ 1 2))
              3
              node))))
  (let* ((stats #f)
         (memo-res
          (with-nanopass-term-memo
            (lambda ()
              (let ((res (map (lambda (n) (nanopass-memoize-step n transform-node))
                              (cdr compound-ast))))
                (set! stats (nanopass-term-memo-stats))
                res)))))
    (assert-equal "shared node transformed once across 3 occurrences" 1 visit-count)
    (assert-equal "memoized results match expected" '(3 3 3) memo-res)
    (assert-equal "term memo hits count is 2" 2 (cdr (assq 'hits stats)))
    (assert-equal "term memo misses count is 1" 1 (cdr (assq 'misses stats)))
    (assert-equal "term memo entries count is 1" 1 (cdr (assq 'entries stats)))
    (assert-equal "term memo hit rate is 66%" 66 (nanopass-term-memo-hit-rate))))

;; 23.3 Scope Isolation & Cleanup
(let ((stats-after (nanopass-term-memo-stats)))
  (assert-equal "memo table is empty outside with-nanopass-term-memo scope"
                0
                (cdr (assq 'entries stats-after))))

;; 23.4 Catamorphism Integration with Shared Subtree in define-pass
(define-language L_test_memo
  (terminals
    (symbol (x))
    (number (n)))
  (Expr (e)
    x
    n
    (+ e1 e2)
    (begin e* ...)))

(define *memo-pass-visit-count* 0)

(define-pass test-pass-memo-count : L_test_memo (ir) -> L_test_memo ()
  (Expr : Expr (ir) -> Expr ()
    ((+ ,e1 ,e2)
     (begin
       (set! *memo-pass-visit-count* (+ *memo-pass-visit-count* 1))
       (list '+ (Expr e1) (Expr e2))))))

(let* ((shared-add (list '+ 10 20))
       (dag-ast (list 'begin shared-add shared-add shared-add)))
  (with-nanopass-term-memo
    (lambda ()
      (set! *memo-pass-visit-count* 0)
      (let ((res (test-pass-memo-count dag-ast)))
        (assert-equal "catamorphism visits shared add node once"
                      1
                      *memo-pass-visit-count*)
        (assert-equal "catamorphism result preserves begin structure"
                      '(begin (+ 10 20) (+ 10 20) (+ 10 20))
                      res)))))

;; 23.5 CP0 & Contify First-Class Picopass / Femtopass Rules Verification
(assert-equal "rule-cp0-prune-if-3 simplifies true condition"
              10
              (rule-cp0-prune-if-3 '(if #t 10 20)))

(assert-equal "rule-cp0-prune-if-3 simplifies false condition"
              20
              (rule-cp0-prune-if-3 '(if #f 10 20)))

(assert-equal "rule-cp0-flatten-begin inlines nested begin"
              '(begin 1 2 3)
              (rule-cp0-flatten-begin '(begin 1 (begin 2 3))))

(assert-equal "rule-cp0-const-fold computes addition"
              30
              (rule-cp0-const-fold '(+ 10 20)))

(assert-equal "rule-cp0-dead-let eliminates pure dead binding"
              '(let ((x 1)) x)
              (rule-cp0-dead-let '(let ((x 1) (y (+ 2 3))) x)))

(assert-equal "rule-contify-letrec converts tail loop to %cont-fun"
              '(%cont-fun loop (n acc)
                          (if (= n 0) acc (%cont-call loop (- n 1) (+ acc n)))
                          (%cont-call loop 10 0))
              (rule-contify-letrec
                '(letrec ((loop (lambda (n acc)
                                  (if (= n 0) acc (loop (- n 1) (+ acc n))))))
                   (loop 10 0))))

;; 23.6 fuse-rules :order post (Bottom-Up Fusion) & Structural Sharing / Femto Cache
(define-picopass rule-post-leaf
  (Expr
    ((p-leaf ,x) (list 'p-val x))))

(define-picopass rule-post-wrap
  (Expr
    ((p-wrap (p-val ,x)) (list 'p-done x))))

(define-picopass rule-post-peel
  (Expr
    ((p-done (p-done ,x)) (list 'p-done x))))

(define-pass test-pass-pre-order-ref : L_src (ir) -> L_src ()
  (fuse-rules rule-post-leaf rule-post-wrap))

(define-pass test-pass-post-order-top : L_src (ir) -> L_src ()
  (fuse-rules :order post rule-post-leaf rule-post-wrap rule-post-peel))

(define-pass test-pass-post-order-nt : L_src (ir) -> L_src ()
  (Expr : Expr (ir) -> Expr ()
    (fuse-rules :order post rule-post-leaf rule-post-wrap rule-post-peel)))

(assert-equal "pre-order fuse-rules only transforms child without re-matching parent pattern"
              '(p-wrap (p-val 42))
              (test-pass-pre-order-ref '(p-wrap (p-leaf 42))))

(assert-equal "post-order fuse-rules (:order post) optimizes child then fires parent rule"
              '(p-done 42)
              (test-pass-post-order-top '(p-wrap (p-leaf 42))))

(assert-equal "NT-level fuse-rules (:order post) cascades bottom-up with local re-dispatch"
              '(p-done 99)
              (test-pass-post-order-nt '(p-wrap (p-val (p-done (p-wrap (p-leaf 99)))))))

;; Verify cp0-optimize eq? structural sharing on unchanged subtrees via :order post
(let* ((untouched-call '(foo x y))
       (unchanged-let (list 'let (list (list 'u untouched-call)) '(u 1)))
       (res-unchanged (cp0-optimize unchanged-let))
       (partial-let (list 'let (list (list 'u untouched-call)) '(+ 10 20)))
       (res-partial (cp0-optimize partial-let)))
  (assert-true "cp0-optimize preserves eq? identity on completely unchanged AST"
               (eq? unchanged-let res-unchanged))
  (assert-true "cp0-optimize preserves eq? sharing on untouched child subtree"
               (eq? untouched-call (cadr (car (cadr res-partial)))))
  (assert-equal "cp0-optimize reduces sibling branch bottom-up"
                30
                (caddr res-partial)))

;; Verify define-femtopass cache integration & automatic tag invalidation
(femto-cache-reset!)
(let* ((sample-loop '(letrec ((lp (lambda (n) (if (= n 0) 0 (lp (- n 1)))))) (lp 5)))
       (res1 (femto-contifiable? sample-loop))
       (stats1 (femto-cache-stats))
       (res2 (femto-contifiable? sample-loop))
       (stats2 (femto-cache-stats)))
  (assert-equal "femto-contifiable? detects contifiable binding on miss" '(lp) res1)
  (assert-equal "femto-contifiable? returns identical cached list on hit" '(lp) res2)
  (assert-equal "femto cache misses recorded on first call" 1 (cdr (assq 'misses stats1)))
  (assert-equal "femto cache hits incremented on second call" 1 (cdr (assq 'hits stats2))))

;; Verify contify-all exercises femto-contifiable? cache and invalidates rewritten node
(femto-cache-reset!)
(let* ((prog-loop '(letrec ((lp (lambda (n) (if (= n 0) 0 (lp (- n 1)))))) (lp 5)))
       (opt (contify-all prog-loop))
       (stats (femto-cache-stats)))
  (assert-true "contify-all converts loop to %cont-fun via femto-contifiable?"
               (and (pair? opt) (eq? (car opt) '%cont-fun)))
  (assert-true "contify-all records femto cache hit during guard+body evaluation"
               (>= (cdr (assq 'hits stats)) 1))
  (assert-equal "record-picopass-firing! invalidates transformed letrec node from femto cache"
                0
                (cdr (assq 'entries stats))))

;;; =======================================================================
;;; Section 24: LIR Data Dependency DAG & Distance-Independent Store-Reload (DSN-33-01 T5.3)
;;; =======================================================================
(display "--- [Section 24: LIR Data Dependency DAG & Store-Reload Forwarding] ---") (newline)

;; 24.1 Basic Block Data Dependency DAG Extraction
(let* ((insts '((%store %rsp 8 %rax)
                (%mov %rbx 42)
                (%store %rsp 16 %rcx)
                (%load %rdx %rsp 8)))
       (dag (lir-build-block-data-dag insts))
       (raw-edges (lir-data-dag-raw-edges dag)))
  (assert-equal "lir-build-block-data-dag extracts RAW edge from store to load across distance 3"
                '((0 . 3))
                raw-edges))

;; 24.2 Branch Fusion First-Class Picopasses
(assert-equal "rule-lir-fuse-cmp-branch-invert fuses cmp and jump-if-false into jump-cond"
              '((%cmp %rax 10) (%jump-cond "jne" L_else))
              (rule-lir-fuse-cmp-branch-invert
                '((%cmp %rax 10)
                  (%set-boolean %rbx "je")
                  (%jump-if-false %rbx L_else))))

(assert-equal "rule-lir-fuse-set-boolean-branch fuses set-boolean and jump-if-false"
              '((%jump-cond "jne" L_target))
              (rule-lir-fuse-set-boolean-branch
                '((%set-boolean %r12 "je")
                  (%jump-if-false %r12 L_target))))

(assert-equal "rule-lir-fuse-cmp-jne-branch fuses raw-cmp and jump-if-false"
              '((%raw-cmp %rax 0) (%jump-cond "jne" L_next))
              (rule-lir-fuse-cmp-jne-branch
                '((%raw-cmp %rax 0)
                  (%jump-if-false %rbx L_next))))

;; 24.3 Peephole First-Class Picopasses
(assert-equal "rule-lir-self-mov-elim eliminates (%mov %rax %rax)"
              '((%return))
              (rule-lir-self-mov-elim '((%mov %rax %rax) (%return))))

(assert-equal "rule-lir-roundtrip-mov-elim keeps first mov and eliminates reverse"
              '((%mov %rax %rbx) (%return))
              (rule-lir-roundtrip-mov-elim '((%mov %rax %rbx) (%mov %rbx %rax) (%return))))

(assert-equal "rule-lir-jump-next-label-elim removes jump directly preceding target label"
              '((%label L_loop) (%return))
              (rule-lir-jump-next-label-elim '((%jump L_loop) (%label L_loop) (%return))))

(assert-equal "rule-lir-identity-arith-elim eliminates identity add and sub zero"
              '((%return))
              (rule-lir-identity-arith-elim '((%add %rax 0) (%return))))

(assert-equal "rule-lir-identity-mul-elim eliminates multiplication by one"
              '((%return))
              (rule-lir-identity-mul-elim '((%imul %rdx 1) (%return))))

(assert-equal "rule-lir-unreachable-dce purges dead instructions up to label"
              '((%jump L2) (%label L1) (%return))
              (rule-lir-unreachable-dce '((%jump L2) (%mov %rax 42) (%add %rax 10) (%label L1) (%return))))

;; 24.4 Distance-Independent Store-Reload Forwarding via Picopass
(let* ((in-insts '((%store %rsp 8 %rax)
                   (%mov %r8 1)
                   (%mov %r9 2)
                   (%store %rsp 16 %rcx)
                   (%load %rdx %rsp 8)
                   (%return)))
       (fwd (rule-lir-store-load-forward in-insts)))
  (assert-equal "rule-lir-store-load-forward forwards across 4 instructions"
                '((%store %rsp 8 %rax)
                  (%mov %r8 1)
                  (%mov %r9 2)
                  (%store %rsp 16 %rcx)
                  (%mov %rdx %rax)
                  (%return))
                fwd))

;;; =======================================================================
;;; Section 25: Shallow Production Dispatch, 256-Bucket Term Memo & Symbol Hash (Issue #815)
;;; =======================================================================

;; 25.1 Shallow production dispatch distinguishes arities and avoids recursive re-validation
(let ((l-core (nanopass-lookup-language 'L_core)))
  (let ((m-if2 (nanopass-find-matching-production-shallow '(if #t 1) 'Expr l-core))
        (m-if3 (nanopass-find-matching-production-shallow '(if #t 1 2) 'Expr l-core))
        (m-let (nanopass-find-matching-production-shallow '(let ((x 1)) x) 'Expr l-core))
        (m-quote (nanopass-find-matching-production-shallow '(quote foo) 'Expr l-core))
        (m-app (nanopass-find-matching-production-shallow '(f x y) 'Expr l-core))
        (m-shallow-nested (nanopass-find-matching-production-shallow '(if (let* ((z 1)) z) 1 2) 'Expr l-core))
        (m-deep-nested (nanopass-find-matching-production '(if (let* ((z 1)) z) 1 2) 'Expr l-core)))
    (assert-true "Shallow dispatch matches 2-arg if" (pair? m-if2))
    (assert-equal "Shallow dispatch 2-arg if arity" 3 (length (cdr m-if2)))
    (assert-true "Shallow dispatch matches 3-arg if" (pair? m-if3))
    (assert-equal "Shallow dispatch 3-arg if arity" 4 (length (cdr m-if3)))
    (assert-equal "Shallow dispatch matches let head" 'let (car (cdr m-let)))
    (assert-equal "Shallow dispatch matches quote head" 'quote (car (cdr m-quote)))
    (assert-equal "Shallow dispatch matches application NT" 'Expr (car m-app))
    (assert-true "Shallow dispatch accepts nested un-desugared child" (pair? m-shallow-nested))
    (assert-false "Deep dispatch rejects nested un-desugared child" m-deep-nested)))

;; 25.2 256-bucket *nanopass-term-memo* hit/miss/entries & bucket depth limit
(assert-equal "Term memo bucket count is 256" 256 *nanopass-term-memo-bucket-count*)
(assert-equal "Term memo bucket depth limit is 16" 16 *nanopass-term-memo-bucket-limit*)

(with-nanopass-term-memo
  (lambda ()
    (nanopass-term-memo-reset!)
    (let* ((node (list '+ 1 2))
           (r1 (nanopass-memoize-step node (lambda (n) (list 'tx n))))
           (r2 (nanopass-memoize-step node (lambda (n) (list 'should-not-recompute n))))
           (st (nanopass-term-memo-stats)))
      (assert-equal "256-bucket term memo returns cached result on hit" r1 r2)
      (assert-equal "256-bucket term memo records 1 hit" 1 (cdr (assq 'hits st)))
      (assert-equal "256-bucket term memo records 1 miss" 1 (cdr (assq 'misses st)))
      (assert-equal "256-bucket term memo records 1 entry" 1 (cdr (assq 'entries st))))
    (nanopass-term-memo-reset!)
    ;; Force exact same hash bucket for 25 distinct cons cells sharing (car), (cadr), (caddr)
    (let loop ((i 0))
      (if (< i 25)
          (let ((n (list '+ 1 2 i)))
            (nanopass-memoize-step n (lambda (x) i))
            (loop (+ i 1)))))
    (let* ((probe (list '+ 1 2 99))
           (b-idx (nanopass-term-memo-bucket-idx probe))
           (bucket-len (length (vector-ref (car *nanopass-term-memo*) b-idx)))
           (st (nanopass-term-memo-stats)))
      (assert-equal "Same-bucket collision caps chain length at 16"
                    *nanopass-term-memo-bucket-limit*
                    bucket-len)
      (assert-equal "Same-bucket collision caps total entries at 16"
                    *nanopass-term-memo-bucket-limit*
                    (cdr (assq 'entries st))))))

;; 25.3 nanopass-classify-meta-var cache hit/miss consistency
(let ((l-core (nanopass-lookup-language 'L_core)))
  (let ((c1 (nanopass-classify-meta-var 'e0 l-core))
        (c2 (nanopass-classify-meta-var 'e0 l-core))
        (cx1 (nanopass-classify-meta-var 'x* l-core))
        (cx2 (nanopass-classify-meta-var 'x* l-core))
        (cn1 (nanopass-classify-meta-var 'not-a-mv-xyz l-core))
        (cn2 (nanopass-classify-meta-var 'not-a-mv-xyz l-core)))
    (assert-equal "classify-meta-var hit matches miss for e0" c1 c2)
    (assert-true "classify-meta-var recognizes e0" (pair? c1))
    (assert-equal "classify-meta-var hit matches miss for x*" cx1 cx2)
    (assert-true "classify-meta-var recognizes x*" (pair? cx1))
    (assert-equal "classify-meta-var hit matches miss for non-meta-var" cn1 cn2)
    (assert-false "classify-meta-var returns #f for non-meta-var" cn1)
    (assert-false "classify-meta-var returns #f for non-symbol"
                  (nanopass-classify-meta-var 123 l-core))))

;;; =======================================================================
;;; 26. Direct Pattern Compilation, Unchanged Window Sharing & expr-size-le? (Issue #816)
;;; =======================================================================
(display (string-append (string #\newline) "--- [Section 26: Direct Pattern Compilation & Window Sharing (#816)] ---" (string #\newline)))

;; 26.1 nanopass-direct-matchable-pattern?
(assert-true "direct-matchable accepts nested LIR window pattern"
             (nanopass-direct-matchable-pattern? '((%mov ,r ,r) (%add _ 0) . ,rest)))
(assert-true "direct-matchable accepts literals, wildcards, and null"
             (nanopass-direct-matchable-pattern? '(const 42 _ ())))
(assert-false "direct-matchable rejects ellipsis pattern"
              (nanopass-direct-matchable-pattern? '(begin ,e ...)))
(assert-false "direct-matchable rejects catamorphism pattern"
              (nanopass-direct-matchable-pattern? '(if ,(c) ,(t) ,(e))))

;; 26.2 Direct pattern compilation with fuse-window-rules (duplicate linearization, guards, wildcards)
(define-picopass test-direct-guard-rule
  (InstWindow
    (((%add _ ,n) . ,rest)
     (guard (> n 0))
     (cons `(%pos-add ,n) rest))
    (((%mov ,r ,r) . ,rest)
     rest)))

(define-pass test-pass-direct-window : L_lir_raw (lir) -> L_lir_canonical ()
  (entry InstructionList)
  (fuse-window-rules test-direct-guard-rule))

(assert-equal "direct pattern matches guarded positive add and linearized duplicate mov"
              '((%pos-add 5) (%add %rbx -3))
              (test-pass-direct-window '((%add %rax 5) (%mov %rcx %rcx) (%add %rbx -3))))

(assert-equal "direct pattern rejects non-equal duplicate register"
              '((%mov %rax %rbx))
              (test-pass-direct-window '((%mov %rax %rbx))))

;; 26.3 Direct pattern preserves explicit #f return value in define-picopass
(define-picopass test-direct-false-body
  (Expr
    ((check ,x) (eq? x 'ok))
    ((check _) 'fallback)))

(assert-equal "direct-compiled picopass returns #t on eq? ok"
              #t
              (test-direct-false-body '(check ok)))
(assert-equal "direct-compiled picopass returns #f without falling through on mismatch"
              #f
              (test-direct-false-body '(check nope)))

;; 26.4 nanopass-sliding-window-pass preserves eq? identity when unchanged and preserves prefix on match
(let ((insts '((%mov %rax %rbx) (%add %rcx 1) (%ret))))
  (let ((res-unchanged (nanopass-sliding-window-pass (lambda (xs) #f) insts)))
    (assert-false "unchanged window pass reports #f changed flag" (cdr res-unchanged))
    (assert-true "unchanged window pass preserves eq? spine without copying"
                 (eq? (car res-unchanged) insts)))
  (let ((res-changed
         (nanopass-sliding-window-pass
           (lambda (xs)
             (if (and (pair? xs) (pair? (car xs)) (eq? (caar xs) '%add))
                 (cons #t (cdr xs))
                 #f))
           insts)))
    (assert-true "mid-list window match reports #t changed flag" (cdr res-changed))
    (assert-equal "mid-list window match preserves prefix and suffix"
                  '((%mov %rax %rbx) (%ret))
                  (car res-changed))))

;; 26.5 expr-size-le? bounded cutoff
(assert-true "expr-size-le? matches exact atom count" (expr-size-le? '(a b) 5))
(assert-false "expr-size-le? rejects one node above limit" (expr-size-le? '(a b) 4))
(let ((deep (let loop ((i 0) (e 'x)) (if (= i 100) e (loop (+ i 1) (list 'f e))))))
  (assert-false "expr-size-le? quickly rejects deep AST over budget 40"
                (expr-size-le? deep 40)))

;;; =======================================================================
;;; Section 27: Hash-Bucketed Rule Registry & Femtopass Analysis Cache (#817)
;;; =======================================================================

;; 27.1 Hash-bucketed *nanopass-rule-buckets* preserves rule lookup & deduplication
(define-picopass test-rule-bucket-alpha
  (Expr
    ((bucket-probe ,x) (list 'bucket-ok x))))

(let ((desc-sym (nanopass-lookup-rule 'test-rule-bucket-alpha))
      (desc-proc (nanopass-lookup-rule test-rule-bucket-alpha))
      (desc-prev (nanopass-lookup-rule 'test-direct-guard-rule)))
  (assert-true "nanopass-lookup-rule finds symbol in hash bucket"
               (rule-descriptor? desc-sym))
  (assert-true "nanopass-lookup-rule finds procedure via proc alist"
               (rule-descriptor? desc-proc))
  (assert-true "nanopass-lookup-rule returns identical descriptor for sym and proc"
               (eq? desc-sym desc-proc))
  (assert-true "previously registered rule remains accessible in hash bucket"
               (rule-descriptor? desc-prev))
  (assert-false "nanopass-lookup-rule-opt returns #f for missing symbol"
                (nanopass-lookup-rule-opt 'nonexistent-bucket-rule-xyz)))

;; Re-registering test-rule-bucket-alpha must update in-place without duplicating entry
(define count-before-rereg
  (length (filter (lambda (r) (eq? (rule-name r) 'test-rule-bucket-alpha))
                  (nanopass-get-all-rules))))

(define-picopass test-rule-bucket-alpha
  (Expr
    ((bucket-probe ,x) (list 'bucket-ok-v2 x))))

(let ((matches (filter (lambda (r) (eq? (rule-name r) 'test-rule-bucket-alpha))
                       (nanopass-get-all-rules)))
      (res (test-rule-bucket-alpha '(bucket-probe 42))))
  (assert-equal "prior rule-name count before re-registration is 1"
                1
                count-before-rereg)
  (assert-equal "re-registering rule updates bucket without duplicating ordered list"
                1
                (length matches))
  (assert-equal "re-registered rule descriptor executes updated body"
                '(bucket-ok-v2 42)
                res))

;; 27.2 Hash-bucketed *femto-analysis-cache* (lookup, hit/miss stats, node & tag invalidation)
(femto-cache-reset!)
(femto-register-attr-dependencies! 'bucket-test-attr '(pure const))
(femto-register-attr-dependencies! 'bucket-other-attr '(effects))

(let ((n1 '(+ 1 2))
      (n2 '(let ((a 10)) (+ a 20)))
      (n3 '(set! x 99))
      (calls 0))
  (let ((v1 (femto-get-cached-attr 'bucket-test-attr n1
              (lambda () (set! calls (+ calls 1)) 101)))
        (v2 (femto-get-cached-attr 'bucket-other-attr n2
              (lambda () (set! calls (+ calls 1)) 202)))
        (v1-hit (femto-get-cached-attr 'bucket-test-attr n1
                  (lambda () (set! calls (+ calls 1)) 999)))
        (v3 (femto-get-cached-attr 'bucket-test-attr n3
              (lambda () (set! calls (+ calls 1)) 303))))
    (assert-equal "femto cache miss computes initial value" 101 v1)
    (assert-equal "femto cache hit returns cached value without recomputing" 101 v1-hit)
    (assert-equal "femto cache miss invoked compute-thunk exact number of misses" 3 calls)
    (assert-equal "second distinct node computes expected attr" 202 v2)
    (assert-equal "third distinct node computes expected attr" 303 v3))
  (let ((st1 (femto-cache-stats)))
    (assert-equal "femto-cache-stats tracks hits=1" 1 (cdr (assq 'hits st1)))
    (assert-equal "femto-cache-stats tracks misses=3" 3 (cdr (assq 'misses st1)))
    (assert-equal "femto-cache-stats tracks entries=3" 3 (cdr (assq 'entries st1))))
  ;; Per-node invalidation drops n1 only (entries: 3 -> 2)
  (femto-cache-invalidate-node! n1)
  (assert-equal "femto-cache-invalidate-node! reduces entries count to 2"
                2
                (cdr (assq 'entries (femto-cache-stats))))
  ;; Tag invalidation drops bucket-test-attr (n3) while preserving bucket-other-attr (n2)
  (femto-cache-invalidate-tags! '(const))
  (assert-equal "tag invalidation preserves unaffected attribute node entries=1"
                1
                (cdr (assq 'entries (femto-cache-stats))))
  ;; Wildcard tag invalidation clears all remaining entries (entries: 1 -> 0)
  (femto-cache-invalidate-tags! '*)
  (assert-equal "wildcard tag invalidation empties hash buckets entries=0"
                0
                (cdr (assq 'entries (femto-cache-stats)))))

(display "=======================================================") (newline)
(display " Nanopass Framework: All ")
(display *nanopass-tests-passed*)
(display " tests passed!") (newline)
(display "=======================================================") (newline)

