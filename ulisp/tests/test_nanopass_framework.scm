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

(define-macro (in-context . args)
  (if (= (length args) 2)
      (list (car args) (cadr args))
      (list 'nanopass-parse-nt (list 'quote (car args)) (caddr args) (list 'quote (cadr args)))))

(define-macro (nanopass-template . args)
  (nanopass-expand-template (car args) '()))

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

(display "=======================================================") (newline)
(display " Nanopass Framework: All ")
(display *nanopass-tests-passed*)
(display " tests passed!") (newline)
(display "=======================================================") (newline)

