;;; =======================================================================
;;; Unit & Integration Test Suite: Unified Binding & Scope Engine (Issue #837)
;;; Conforms to DSN-33-02 §3.2, DSN-38 §2 (B3/B4) & Issue #837
;;; =======================================================================

(test-begin "Unified Symbol Binding & Multi-Namespace Scope (Issue #837)")

;;; -----------------------------------------------------------------------
;;; Group 1: <binding> Records, Registry & Binding ID Set Algebra
;;; -----------------------------------------------------------------------
(print-group "--- Group 1: <binding> Records, Registry & Binding ID Sets ---")

(reset-alpha-symbol-counter!)
(define b-span1 (make-source-span "src/test.c" 10 5 10 12 #f (next-source-span-id!)))

(define b0 (make-binding (next-binding-id!) 'count 'count$0 'variable 'ordinary 1 'lexical 'i64 'local '(3 1) b-span1))
(assert-true "1.1 binding? identifies <binding> record" (binding? b0))
(assert-false "1.2 binding? rejects non-binding pair" (binding? '(not-a-binding 1 2)))
(assert-equal "1.3 binding-id is 0" 0 (binding-id b0))
(assert-equal "1.4 binding-source-name is count" 'count (binding-source-name b0))
(assert-equal "1.5 binding-unique-sym is count$0" 'count$0 (binding-unique-sym b0))
(assert-equal "1.6 binding-kind is variable" 'variable (binding-kind b0))
(assert-equal "1.7 binding-namespace is ordinary" 'ordinary (binding-namespace b0))
(assert-equal "1.8 binding-scope-id is 1" 1 (binding-scope-id b0))
(assert-equal "1.9 binding-storage-class is lexical" 'lexical (binding-storage-class b0))
(assert-equal "1.10 binding-type-attr is i64" 'i64 (binding-type-attr b0))
(assert-equal "1.11 binding-visibility is local" 'local (binding-visibility b0))
(assert-equal "1.12 binding-scope-set is canonically sorted" '(1 3) (binding-scope-set b0))
(assert-equal "1.13 binding-source-span preserved" b-span1 (binding-source-span b0))

;; Mutators
(set-binding-type-attr! b0 'u64)
(set-binding-storage-class! b0 'static)
(set-binding-visibility! b0 'file)
(define b-span2 (make-source-span "src/test.c" 20 1 20 8 #f (next-source-span-id!)))
(set-binding-source-span! b0 b-span2)
(assert-equal "1.14 set-binding-type-attr! updates type" 'u64 (binding-type-attr b0))
(assert-equal "1.15 set-binding-storage-class! updates storage class" 'static (binding-storage-class b0))
(assert-equal "1.16 set-binding-visibility! updates visibility" 'file (binding-visibility b0))
(assert-equal "1.17 set-binding-source-span! updates span" b-span2 (binding-source-span b0))

;; Invalid make-binding validation caught cleanly by guard
(define bad-binding-err
  (guard (ex (else ex))
    (make-binding -1 'x 'x$0 'variable 'ordinary 0 'lexical #f 'local '() #f)))
(assert-true "1.18 invalid negative binding id raises binding-error"
             (and (pair? bad-binding-err) (eq? (car bad-binding-err) 'binding-error)))

;; Global Registry lookup by ID and symbol
(register-binding! b0)
(define b1 (make-binding (next-binding-id!) 'limit 'limit$1 'parameter 'ordinary 2 'lexical 'i32 'local '() #f))
(define b2 (make-binding (next-binding-id!) 'node 'node$2 'tag-struct 'tag 1 'global #f 'file '() #f))
(register-binding! b1)
(register-binding! b2)

(assert-equal "1.19 lookup-binding-by-id finds b0" b0 (lookup-binding-by-id 0))
(assert-equal "1.20 lookup-binding-by-symbol finds b1" b1 (lookup-binding-by-symbol 'limit$1))
(assert-false "1.21 lookup-binding-by-id returns #f on missing ID" (lookup-binding-by-id 999))
(assert-equal "1.22 all-registered-bindings preserves chronological order"
              (list b0 b1 b2)
              (all-registered-bindings))

;; Binding ID Set Algebra (strictly ascending deduplicated integer lists)
(define bs-a (binding-id-set-add 2 (binding-id-set-add 0 binding-id-set-empty)))
(define bs-b (binding-id-set-add 1 (binding-id-set-add 2 binding-id-set-empty)))
(assert-equal "1.23 binding-id-set union merges cleanly" '(0 1 2) (binding-id-set-union bs-a bs-b))
(assert-equal "1.24 binding-id-set intersection finds common elements" '(2) (binding-id-set-intersection bs-a bs-b))
(assert-equal "1.25 binding-id-set difference subtracts cleanly" '(0) (binding-id-set-difference bs-a bs-b))
(assert-true "1.26 binding-id-set subset? holds" (binding-id-set-subset? '(0 2) '(0 1 2)))
(assert-false "1.27 binding-id-set subset? rejects extra item" (binding-id-set-subset? '(0 3) '(0 1 2)))
(assert-equal "1.28 symbols->binding-id-set resolves unique symbols"
              '(0 2)
              (symbols->binding-id-set '(node$2 unknown$99 count$0)))
(assert-equal "1.29 binding-id-set->symbols maps back to unique symbols"
              '(count$0 limit$1)
              (binding-id-set->symbols '(0 1)))

;;; -----------------------------------------------------------------------
;;; Group 2: Multi-Namespace Isolation, Function Label Hoisting & Strict Redef
;;; -----------------------------------------------------------------------
(print-group "--- Group 2: Multi-Namespace Isolation & Redefinition Guard ---")

(reset-alpha-symbol-counter!)
(define ns-root (make-scope-node #f 'top-level))
(define ns-fn1 (scope-enter ns-root 'function))
(define ns-blk1 (scope-enter ns-fn1 'block))
(define ns-blk2 (scope-enter ns-fn1 'block))
(define ns-fn2 (scope-enter ns-root 'function))

;; Same name 'foo in ordinary, tag, and label namespaces simultaneously
(define foo-typedef (scope-define! ns-root 'foo 'typedef))
(define foo-tag     (scope-define! ns-root 'foo 'tag-struct))
(define foo-label   (scope-define! ns-blk1 'foo 'label))

(assert-equal "2.1 tag namespace resolves struct foo separately from typedef"
              'tag-struct
              (binding-kind (scope-lookup-binding ns-blk1 'foo 'tag)))
(assert-equal "2.2 ordinary namespace resolves typedef foo"
              'typedef
              (binding-kind (scope-lookup-binding ns-blk1 'foo 'ordinary)))
(assert-equal "2.3 label defined inside blk1 is hoisted to enclosing function and visible in sibling blk2"
              (binding-id foo-label)
              (binding-id (scope-lookup-binding ns-blk2 'foo 'label)))
(assert-false "2.4 label in fn1 is NOT visible inside sibling fn2"
              (scope-lookup-binding ns-fn2 'foo 'label))
(assert-equal "2.5 label scope-id matches enclosing function scope id"
              (scope-node-id ns-fn1)
              (binding-scope-id foo-label))

;; THREAT-837-3: strict same-scope redefinition in same namespace must raise scope-error
(define redef-err
  (guard (ex (else ex))
    (with-strict-scope-redefinition
     (lambda ()
       (scope-define! ns-root 'foo 'variable)))))
(assert-true "2.6 duplicate same-namespace symbol in strict mode raises scope-error"
             (and (pair? redef-err) (eq? (car redef-err) 'scope-error)))

;; Same name in different namespace inside same strict scope MUST succeed
(define macro-foo
  (with-strict-scope-redefinition
   (lambda ()
     (scope-define! ns-root 'foo 'macro))))
(assert-equal "2.7 defining macro foo alongside typedef/tag foo succeeds"
              'macro
              (binding-kind macro-foo))

;;; -----------------------------------------------------------------------
;;; Group 3: C99 Lexer Hack & Scope Manager Push/Pop Lifecycle
;;; -----------------------------------------------------------------------
(print-group "--- Group 3: C99 Lexer Hack & Scope Manager Lifecycle ---")

(reset-alpha-symbol-counter!)
(define mgr (make-scope-manager))
(assert-true "3.1 scope-manager? identifies manager" (scope-manager? mgr))

;; Top-level: typedef int T;
(scope-manager-define! mgr 'T 'typedef)
(assert-true "3.2 top-level T is typedef name (TYPEDEF_NAME)" (scope-manager-typedef-name? mgr 'T))
(assert-equal "3.3 top-level lookup-kind returns typedef" 'typedef (scope-manager-lookup-kind mgr 'T))
(assert-false "3.4 undefined U is not typedef name" (scope-manager-typedef-name? mgr 'U))

;; Enter function scope: T is still typedef
(scope-manager-push! mgr 'function)
(assert-true "3.5 inside function, outer typedef T remains visible" (scope-manager-typedef-name? mgr 'T))

;; Enter block1: int T = 10; (ordinary variable shadows typedef T)
(scope-manager-push! mgr 'block)
(define var-T (scope-manager-define! mgr 'T 'variable))
(assert-false "3.6 block1 variable T shadows outer typedef (IDENTIFIER)" (scope-manager-typedef-name? mgr 'T))
(assert-equal "3.7 block1 lookup-kind returns variable" 'variable (scope-manager-lookup-kind mgr 'T))

;; Enter block2: typedef double T; (nested typedef shadows block1 variable T)
(scope-manager-push! mgr 'block)
(scope-manager-define! mgr 'T 'typedef)
(assert-true "3.8 block2 nested typedef T restores TYPEDEF_NAME" (scope-manager-typedef-name? mgr 'T))

;; Pop block2 -> back in block1 (should see variable T)
(scope-manager-pop! mgr)
(assert-false "3.9 after popping block2, block1 variable T is active again" (scope-manager-typedef-name? mgr 'T))
(assert-equal "3.10 block1 binding preserved" (binding-id var-T) (binding-id (scope-manager-lookup mgr 'T)))

;; Pop block1 -> back in function (should see top-level typedef T)
(scope-manager-pop! mgr)
(assert-true "3.11 after popping block1, top-level typedef T is restored" (scope-manager-typedef-name? mgr 'T))

;; Pop function -> back in root
(scope-manager-pop! mgr)
(assert-true "3.12 popped back to root scope" (eq? (scope-manager-root mgr) (scope-manager-current mgr)))

;; THREAT-837-3: Root scope pop underflow guard
(define underflow-err
  (guard (ex (else ex))
    (scope-manager-pop! mgr)))
(assert-true "3.13 popping root scope raises scope-error"
             (and (pair? underflow-err) (eq? (car underflow-err) 'scope-error)))
(assert-true "3.14 scope manager remains at root after underflow error"
             (eq? (scope-manager-root mgr) (scope-manager-current mgr)))

;;; -----------------------------------------------------------------------
;;; Group 4: Hygienic Macro Scope Sets (Flatt 2016)
;;; -----------------------------------------------------------------------
(print-group "--- Group 4: Hygienic Macro Scope Sets ---")

(reset-alpha-symbol-counter!)
(define hyg-root (make-scope-node #f 'top-level))
(define sc-mod (fresh-hygiene-scope!))
(define sc-mac1 (fresh-hygiene-scope!))
(define sc-mac2 (fresh-hygiene-scope!))

;; Flipped mark toggles presence deterministically
(define flip1 (scope-set-flip sc-mac1 (list sc-mod)))
(assert-true "4.1 scope-set-flip adds absent mark" (scope-set-member? sc-mac1 flip1))
(define flip2 (scope-set-flip sc-mac1 flip1))
(assert-false "4.2 second scope-set-flip removes existing mark" (scope-set-member? sc-mac1 flip2))

;; Outer 'tmp bound with {sc-mod}, macro-introduced 'tmp bound with {sc-mod, sc-mac1}
(define outer-tmp (scope-define! hyg-root 'tmp 'variable ':scope-set (list sc-mod)))
(define macro-tmp (scope-define! hyg-root 'tmp 'variable ':scope-set (list sc-mod sc-mac1)))

;; Call-site ref with {sc-mod} sees ONLY outer-tmp
(assert-equal "4.3 use-site {sc-mod} resolves outer-tmp (no macro capture)"
              (binding-id outer-tmp)
              (binding-id (scope-lookup-hygienic hyg-root 'tmp (list sc-mod))))

;; Macro template ref with {sc-mod, sc-mac1} picks most specific subset (macro-tmp)
(assert-equal "4.4 macro use-site {sc-mod, sc-mac1} resolves macro-tmp"
              (binding-id macro-tmp)
              (binding-id (scope-lookup-hygienic hyg-root 'tmp (list sc-mod sc-mac1))))

;; THREAT-837-4: Incomparable maximal candidates {sc-mod, sc-mac1} and {sc-mod, sc-mac2} for use {sc-mod, sc-mac1, sc-mac2}
(define amb-mac2 (scope-define! hyg-root 'amb 'variable ':scope-set (list sc-mod sc-mac2)))
(define amb-mac1 (scope-define! hyg-root 'amb 'variable ':scope-set (list sc-mod sc-mac1)))
(define amb-err
  (guard (ex (else ex))
    (scope-lookup-hygienic hyg-root 'amb (list sc-mod sc-mac1 sc-mac2))))
(assert-true "4.5 incomparable maximal scope sets raise binding-error"
             (and (pair? amb-err) (eq? (car amb-err) 'binding-error)))

;;; -----------------------------------------------------------------------
;;; Group 5: Pass 035 Alpha-Conversion, Span Propagation & Free Binding IDs
;;; -----------------------------------------------------------------------
(print-group "--- Group 5: Pass 035 Integration, Spans & Free Binding IDs ---")

(reset-alpha-symbol-counter!)
(define p-span (make-source-span "src/closure.scm" 42 3 45 20 #f (next-source-span-id!)))
(define nested-ast
  (list '%program
        (list (list 'define 'g-helper '(lambda (z) (+ z 1))))
        (ast-with-span
         '(let ((x 10))
            (let ((y 20))
              (lambda (y)
                (g-helper (+ x y)))))
         p-span)))

(define resolved-ast (scope-resolve-all nested-ast))
(define main-resolved (caddr resolved-ast))
(assert-true "5.1 alpha-converted main preserves outer %source-span" (ast-has-span? main-resolved))
(assert-equal "5.2 preserved span matches original p-span" p-span (ast-source-span main-resolved))

;; Check registered bindings: top-level g-helper + inner z + outer x + outer y + inner lambda y
(define all-bs (all-registered-bindings))
(assert-true "5.3 multiple bindings registered during Pass 035" (>= (length all-bs) 5))
(define b-ghelper (lookup-binding-by-symbol 'g-helper))
(assert-true "5.4 top-level g-helper registered as function binding"
             (and (binding? b-ghelper)
                  (eq? (binding-kind b-ghelper) 'function)
                  (eq? (binding-storage-class b-ghelper) 'global)))

;; Distinct alpha symbols & spans for shadowed variables
(define stripped-main (ast-strip-span main-resolved))
(define outer-x-sym (caar (cadr stripped-main)))
(define inner-let (caddr stripped-main))
(define outer-y-sym (caar (cadr inner-let)))
(define inner-lam (caddr inner-let))
(define inner-y-sym (car (cadr inner-lam)))

(define b-outer-x (lookup-binding-by-symbol outer-x-sym))
(define b-outer-y (lookup-binding-by-symbol outer-y-sym))
(define b-inner-y (lookup-binding-by-symbol inner-y-sym))
(assert-true "5.5 outer x binding carries p-span from Pass 035"
             (and (binding? b-outer-x)
                  (equal? p-span (binding-source-span b-outer-x))))
(assert-true "5.6 shadowed y variables received distinct binding IDs"
             (and (binding? b-outer-y)
                  (binding? b-inner-y)
                  (not (= (binding-id b-outer-y) (binding-id b-inner-y)))))

;; Free Binding IDs & Closure Capture Binding IDs (excluding global g-helper and builtins)
(define lam-captures (closure-capture-binding-ids inner-lam '()))
(assert-equal "5.7 closure-capture-binding-ids captures ONLY outer x (not shadowed y or global g-helper)"
              (list (binding-id b-outer-x))
              lam-captures)

(define lam-free-ids (free-binding-ids inner-lam '()))
(assert-true "5.8 free-binding-ids contains both b-outer-x and b-ghelper"
             (and (binding-id-set-member? (binding-id b-outer-x) lam-free-ids)
                  (binding-id-set-member? (binding-id b-ghelper) lam-free-ids)))

;; Scope tree check from *last-resolved-scope-tree*
(define last-root (get-last-resolved-scope-tree))
(assert-true "5.9 get-last-resolved-scope-tree returns top-level scope node"
             (and (scope-node? last-root) (eq? (scope-node-kind last-root) 'top-level)))
(define let-x-scope (cadr (scope-node-children last-root)))
(define let-y-scope (car (scope-node-children let-x-scope)))
(define inner-lam-scope (car (scope-node-children let-y-scope)))
(assert-equal "5.10 inner lambda scope contour recorded free binding ID of outer x"
              (list (binding-id b-outer-x))
              (scope-node-free-binding-ids inner-lam-scope))

(test-end "Unified Symbol Binding & Multi-Namespace Scope (Issue #837)")
