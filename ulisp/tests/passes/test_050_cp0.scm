;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 050 (CP0 Constant Folding & DCE)
;;; Conforms to Issue #572 & Nanopass Architecture Quality Standard
;;; =======================================================================



(test-begin "Pass 050 (CP0 Optimization)")

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
              (cp0-optimize '(let ((dead1 10) (dead2 (+ 3 4))) 42)))

;; 6. Bottom-up nested constant folding + branch pruning + eq? structural sharing
(assert-equal "bottom-up nested fold and branch prune"
              100
              (cp0-optimize '(if (= (+ 1 2) 3) (* 10 10) (foo bar))))

(let* ((untouched '(unknown-fn arg1 arg2))
       (ast (list 'let (list (list 'u untouched)) '(if (= (+ 2 3) 5) (+ 7 8) (baz))))
       (opt (cp0-optimize ast)))
  (assert-equal "bottom-up child fold before parent branch prune inside let"
                15
                (caddr opt))
  (assert-equal "eq? structural sharing preserved on untouched impure binding"
                #t
                (eq? untouched (cadr (car (cadr opt))))))

;; 7. Inline unary lambda map -> tail-recursive letrec
(let* ((opt (cp0-optimize '(map (lambda (x) (+ x 1)) '(1 2 3))))
       (opt-empty (cp0-optimize '(map (lambda (x) (+ x 1)) '()))))
  (assert-equal "map with unary lambda expands to letrec"
                'letrec
                (car opt))
  (assert-equal "inlined map evaluates identically on non-empty list"
                '(2 3 4)
                (eval opt (interaction-environment)))
  (assert-equal "inlined map evaluates identically on empty list"
                '()
                (eval opt-empty (interaction-environment))))

;; 8. Inline unary lambda for-each -> tail-recursive letrec preserving order
(let* ((opt (cp0-optimize '(for-each (lambda (x) (set! acc (cons x acc))) '(1 2 3))))
       (opt-empty (cp0-optimize '(for-each (lambda (x) (set! acc (cons x acc))) '()))))
  (assert-equal "for-each with unary lambda expands to letrec"
                'letrec
                (car opt))
  (assert-equal "inlined for-each preserves left-to-right side-effect order"
                '(3 2 1)
                (eval `(let ((acc '())) ,opt acc) (interaction-environment)))
  (assert-equal "inlined for-each handles empty list without running body"
                '()
                (eval `(let ((acc '())) ,opt-empty acc) (interaction-environment))))

;; 9. Multi-arg map, non-lambda fn, and rest-arg lambda remain unexpanded
(assert-equal "multi-arg map is left unexpanded"
              'map
              (car (cp0-optimize '(map + xs ys))))
(assert-equal "for-each with variable fn is left unexpanded"
              'for-each
              (car (cp0-optimize '(for-each f xs))))
(assert-equal "map with rest-arg lambda is left unexpanded"
              'map
              (car (cp0-optimize '(map (lambda xs (length xs)) '(1 2)))))

;; 10. Hygienic shadowing and contify compatibility (%cont-fun lowering)
(let* ((opt-shadow (cp0-optimize '(map (lambda (cons) (+ cons 10)) '(1 2 3))))
       (opt-open (cp0-optimize '(map (lambda (x) (+ x 1)) xs)))
       (contified (contify-opt opt-open)))
  (assert-equal "map expansion stays hygienic when parameter shadows cons"
                '(11 12 13)
                (eval opt-shadow (interaction-environment)))
  (assert-equal "inlined map letrec lowers to %cont-fun via pass-100-contify"
                #t
                (let has-sym? ((node contified))
                  (cond
                    ((eq? node '%cont-fun) #t)
                    ((pair? node) (or (has-sym? (car node)) (has-sym? (cdr node))))
                    (else #f)))))

;; 11. Quoted-list memq lowering in boolean contexts (Issue #938)
(let ((has-sym? (lambda (tree target)
                  (let walk ((x tree))
                    (cond
                      ((eq? x target) #t)
                      ((pair? x) (or (walk (car x)) (walk (cdr x))))
                      (else #f))))))
  (let ((opt-if (cp0-optimize '(if (memq x '(alpha beta gamma)) 'hit 'miss)))
        (opt-not (cp0-optimize '(not (memq x '(one two)))))
        (opt-val (cp0-optimize '(memq x '(alpha beta gamma))))
        (opt-const (cp0-optimize '(if (memq 'beta '(alpha beta gamma)) 10 20))))
    (assert-equal "if memq quoted list eliminates memq allocation"
                  #f
                  (has-sym? opt-if 'memq))
    (assert-equal "if memq quoted list behaves identically on hit"
                  'hit
                  (eval `(let ((x 'beta)) ,opt-if) (interaction-environment)))
    (assert-equal "if memq quoted list behaves identically on miss"
                  'miss
                  (eval `(let ((x 'delta)) ,opt-if) (interaction-environment)))
    (assert-equal "not memq quoted list eliminates memq allocation"
                  #f
                  (has-sym? opt-not 'memq))
    (assert-equal "not memq quoted list evaluates #f on match"
                  #f
                  (eval `(let ((x 'one)) ,opt-not) (interaction-environment)))
    (assert-equal "not memq quoted list evaluates #t on miss"
                  #t
                  (eval `(let ((x 'three)) ,opt-not) (interaction-environment)))
    (assert-equal "value-position memq preserves R7RS sublist return value"
                  '(beta gamma)
                  (eval `(let ((x 'beta)) ,opt-val) (interaction-environment)))
    (assert-equal "constant memq inside if folds statically"
                  10
                  opt-const)))

;; 12. Small accessor & 1-2 primitive leaf function inlining (Issue #958)
(let* ((prog-rec '(%program
                   ((define scope-node-children-cell
                      (lambda (rec_)
                        (declare (no-safepoints))
                        (vector-ref rec_ 3)))
                    (define scope-node-children
                      (lambda (node)
                        (car (scope-node-children-cell node)))))
                   (scope-node-children node)))
       (opt-rec (cp0-optimize prog-rec))
       (opt-local (cp0-optimize
                   '(letrec ((get-tag (lambda (p) (car p)))
                             (is-foo? (lambda (p) (eq? (get-tag p) 'foo))))
                      (is-foo? obj))))
       (opt-nonatom (cp0-optimize
                     '(%program
                       ((define get-f1 (lambda (r) (vector-ref r 1))))
                       (get-f1 (make-rec 1 2)))))
       (opt-mutated (cp0-optimize
                     '(%program
                       ((define f (lambda (x) (car x))))
                       (begin (set! f (lambda (x) (cdr x))) (f pair)))))
       (opt-shadowed (cp0-optimize
                      '(%program
                        ((define get-car (lambda (p) (car p))))
                        (let ((car (lambda (x) 99)))
                          (cons (get-car p) (list car)))))))
  (assert-equal "composed record accessor inlines directly to (car (vector-ref node 3))"
                '(car (vector-ref node 3))
                (caddr opt-rec))
  (assert-equal "letrec local accessors inline and dead bindings are eliminated"
                '(eq? (car obj) 'foo)
                opt-local)
  (assert-equal "non-atomic arg inlines via hygienic temporary let binding"
                'let
                (car (caddr opt-nonatom)))
  (assert-equal "mutated binding via set! is not inlined"
                '(f pair)
                (caddr (caddr opt-mutated)))
  (assert-equal "shadowed primitive car prevents unsafe inlining"
                '(cons (get-car p) (list car))
                (caddr (caddr opt-shadowed))))

(test-end "Pass 050 (CP0 Optimization)")
