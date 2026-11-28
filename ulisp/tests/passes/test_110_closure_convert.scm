;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 110 (Explicit Closure Conversion)
;;; Conforms to Issue #572, Issue #594 & Nanopass Architecture Quality Standard
;;; =======================================================================





(test-begin "Pass 110 (Closure Conversion)")

;; 1. Top-level program wrapping
(let ((res (closure-convert 42)))
  (assert-equal "program tag" '%program (car res))
  (assert-equal "main expr" 42 (caddr res))
  (assert-true "conforms to L_lifted?" (L_lifted? res)))

;; 2. Lambda lifting to %function
(let* ((res (closure-convert '(lambda (x) (+ x 1))))
       (funcs (cadr res))
       (main-expr (caddr res)))
  (assert-equal "lifts 1 function" 1 (length funcs))
  (assert-equal "function tag" '%function (caar funcs))
  (assert-true "main is %make-closure-env" (memq (car main-expr) '(%make-closure %make-closure-env)))
  (assert-true "conforms to L_lifted?" (L_lifted? res)))

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
                     (else (or (rec (car e)) (rec (cdr e))))))))
  (assert-true "conforms to L_lifted?" (L_lifted? res)))

;; 4. Quoted symbol literal preservation (static interning without string->symbol)
(let ((res (closure-convert ''a)))
  (assert-equal "preserves quoted symbol" ''a (caddr res))
  (assert-true "conforms to L_lifted?" (L_lifted? res)))

;; 5. Mutually recursive functions (letrec) closure conversion
(let* ((res (closure-convert '(letrec ((even? (lambda (n) (if (= n 0) #t (odd? (- n 1))))))
                                      ((odd? (lambda (n) (if (= n 0) #f (even? (- n 1))))))
                                (even? 10)))))
  (assert-equal "lifts 2 mutually recursive functions" 2 (length (cadr res)))
  (assert-true "letrec output conforms to L_lifted?" (L_lifted? res)))

;; 6. Schema Invariant Rejection Tests (L_lifted? rejects unlifted lambdas)
(assert-false "L_lifted? rejects unlifted lambda standalone"
              (L_lifted? '(lambda (x) (+ x 1))))

(assert-false "L_lifted? rejects unlifted lambda in %program main"
              (L_lifted? '(%program () (lambda (x) (+ x 1)))))

(assert-false "L_lifted? rejects unlifted lambda inside %function body"
              (L_lifted? '(%program ((%function L_fn1 (x) (lambda (y) (+ x y)))) 42)))

;; 7. Issue #960: Intra-unit top-level function reachability pruning
(let* ((prog '(%program ((define dead-fn (lambda (x) (+ x 999)))
                         (define helper-fn (lambda (x) (* x 2)))
                         (define used-fn (lambda (x) (+ (helper-fn x) 1))))
                        (used-fn 5)))
       (res (closure-convert prog))
       (funcs (cadr res))
       (fn-names (map cadr funcs)))
  (assert-true "reachability keeps directly called used-fn"
               (and (memq (mangle-fn-label 'used-fn) fn-names) #t))
  (assert-true "reachability keeps transitively called helper-fn"
               (and (memq (mangle-fn-label 'helper-fn) fn-names) #t))
  (assert-false "reachability prunes unreferenced dead-fn"
                (memq (mangle-fn-label 'dead-fn) fn-names))
  (assert-true "pruned output satisfies L_lifted?" (L_lifted? res)))

;; 8. Issue #972: Known-function alias propagation to %direct-call without closure alloc
(let* ((ast '(let ((f (lambda (x) (+ x 1))))
               (let ((g f))
                 (g 41))))
       (res (closure-convert ast))
       (main-e (caddr res)))
  (assert-true "alias call (g 41) devirtualizes to %direct-call"
               (occurs-in? '%direct-call main-e))
  (assert-false "alias call avoids %make-closure-env allocation"
                (occurs-in? '%make-closure-env main-e))
  (assert-true "alias devirt output satisfies L_lifted?" (L_lifted? res)))

(test-end "Pass 110 (Closure Conversion)")
