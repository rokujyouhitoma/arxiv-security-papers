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

(test-end "Pass 050 (CP0 Optimization)")
