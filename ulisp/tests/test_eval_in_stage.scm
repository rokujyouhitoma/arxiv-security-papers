;;; =======================================================================
;;; Unit Test Suite: Stage-Polymorphic Evaluator Core Loop (Issue #872)
;;; Conforms to DSN-33-03 §2.6, §3.5, §3.7
;;; =======================================================================

(test-begin "Stage-Polymorphic Evaluator Core Loop (Issue #872)")

(define now-d (make-now-dict))
(define later-d (make-later-dict))

;;; -----------------------------------------------------------------------
;;; Group 1: Now Dictionary Immediate Evaluation
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Now Dictionary Immediate Evaluation ---\n")

;; 1.1 Constants
(let ((res (eval-in-stage now-d '() 42 1000 100)))
  (assert-equal "1.1 Constant number" #t (stage-val-pure-static? res))
  (assert-equal "1.1 Payload" 42 (stage-val-payload res)))

(let ((res (eval-in-stage now-d '() #t 1000 100)))
  (assert-equal "1.2 Constant boolean" #t (stage-val-pure-static? res))
  (assert-equal "1.2 Payload" #t (stage-val-payload res)))

;; 1.2 Known Primitives
(let ((res (eval-in-stage now-d '() '(+ 10 32) 1000 100)))
  (assert-equal "1.3 Primitive addition (+ 10 32)" #t (stage-val-pure-static? res))
  (assert-equal "1.3 Payload is 42" 42 (stage-val-payload res)))

(let ((res (eval-in-stage now-d '() '(* 6 7) 1000 100)))
  (assert-equal "1.4 Primitive multiplication (* 6 7)" 42 (stage-val-payload res)))

;; 1.3 Static Branch Pruning
(let ((res (eval-in-stage now-d '() '(if #t 42 (/ 1 0)) 1000 100)))
  (assert-equal "1.5 Static if truthy branch pruned" 42 (stage-val-payload res)))

(let ((res (eval-in-stage now-d '() '(if #f (/ 1 0) 99) 1000 100)))
  (assert-equal "1.6 Static if falsy branch pruned" 99 (stage-val-payload res)))

;; 1.4 Let Bindings
(let ((res (eval-in-stage now-d '() '(let ((x 10) (y 32)) (+ x y)) 1000 100)))
  (assert-equal "1.7 Let bindings evaluation" 42 (stage-val-payload res)))

;; 1.5 Begin Sequence
(let ((res (eval-in-stage now-d '() '(begin 1 2 (+ 20 22)) 1000 100)))
  (assert-equal "1.8 Begin sequence" 42 (stage-val-payload res)))

;; 1.6 Quote
(let ((res (eval-in-stage now-d '() '(quote (a b c)) 1000 100)))
  (assert-equal "1.9 Quoted datum" '(a b c) (stage-val-payload res)))

;;; -----------------------------------------------------------------------
;;; Group 2: Later Dictionary Residual Code Generation & Constant Folding
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Later Dictionary Residualization & Constant Folding ---\n")

;; 2.1 Pure Static Folding under Later Dict
(let ((res (eval-in-stage later-d '() '(+ 10 32) 1000 100)))
  (assert-equal "2.1 Static folding in Later dict is pure-static" #t (stage-val-pure-static? res))
  (assert-equal "2.1 Folded payload is 42" 42 (stage-val-payload res)))

;; 2.2 Dynamic Expression Residualization
(let ((res (eval-in-stage later-d '() '(+ x 1) 1000 100)))
  (assert-equal "2.2 Dynamic expr is pure-dynamic" #t (stage-val-pure-dynamic? res))
  (assert-equal "2.2 Residual payload (+ x 1)" '(+ x 1) (stage-val-payload res)))

;; 2.3 Static Branch Pruning in Later Dict (Futamura Projection Property!)
(let ((res (eval-in-stage later-d '() '(if #t (+ x 1) (/ 1 0)) 1000 100)))
  (assert-equal "2.3 Static if collapses completely without residual if-anf!" '(+ x 1) (stage-val-payload res)))

;; 2.4 Dynamic Conditional Emission
(let ((res (eval-in-stage later-d '() '(if (< x 0) (- 0 x) x) 1000 100)))
  (assert-equal "2.4 Dynamic if emits residual if-anf"
                '(if-anf (< x 0) (- 0 x) x)
                (stage-val-payload res)))

;; 2.5 Static Let Inlining
(let ((res (eval-in-stage later-d '() '(let ((a 10)) (+ a x)) 1000 100)))
  (assert-equal "2.5 Static let variable inlined directly into residual expression"
                '(+ 10 x)
                (stage-val-payload res)))

;; 2.6 Dynamic Let Residualization
(let ((res (eval-in-stage later-d '() '(let ((y (+ x 1))) (* y 2)) 1000 100)))
  (assert-equal "2.6 Dynamic let emits residual let-anf"
                '(let-anf ((y (+ x 1))) (* y 2))
                (stage-val-payload res)))

;; 2.7 PSDS Static Spine Elimination via eval-in-stage
(let ((res (eval-in-stage later-d '() '(car (cons 42 x)) 1000 100)))
  (assert-equal "2.7 PSDS car/cons collapses static element at compile time!"
                42
                (stage-val-payload res)))

;;; -----------------------------------------------------------------------
;;; Group 3: Resource Bounds Guards (CWE-400 Protection)
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Resource Bounds Guards (Fuel & Depth) ---\n")

;; 3.1 Fuel Exhaustion Guard
(let ((res (eval-in-stage now-d '() '(+ 1 (+ 2 (+ 3 4))) 2 100)))
  (assert-equal "3.1 Fuel exhaustion triggers CSP error" #t (stage-csp-error? res))
  (assert-equal "3.1 Error rule is ctfe-fuel-exhausted" 'ctfe-fuel-exhausted (cadr res)))

;; 3.2 Depth Overflow Guard
(let ((res (eval-in-stage now-d '() '(+ 1 (+ 2 (+ 3 4))) 1000 1)))
  (assert-equal "3.2 Depth overflow triggers CSP error" #t (stage-csp-error? res))
  (assert-equal "3.2 Error rule is ctfe-depth-overflow" 'ctfe-depth-overflow (cadr res)))

;;; -----------------------------------------------------------------------
;;; Group 4: Relative Stage-Level Transition (Fractal Metacircular Tower)
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Relative Stage-Level Transitions ---\n")

;; 4.1 stage-level = 2 -> Now evaluation
(let ((res (stage-eval-level now-d later-d '() '(+ 10 32) 1000 100 2)))
  (assert-equal "4.1 Stage-level 2 evaluates via Now dict" 42 (stage-val-payload res)))

;; 4.2 stage-level = 1 -> Now evaluation
(let ((res (stage-eval-level now-d later-d '() '(* 7 6) 1000 100 1)))
  (assert-equal "4.2 Stage-level 1 evaluates via Now dict" 42 (stage-val-payload res)))

;; 4.3 stage-level = 0 -> Later evaluation (Residualization)
(let ((res (stage-eval-level now-d later-d '() '(+ x 10) 1000 100 0)))
  (assert-equal "4.3 Stage-level 0 transitions to Later dict" '(+ x 10) (stage-val-payload res)))

;; 4.4 stage-level < 0 -> CSP Error
(let ((res (stage-eval-level now-d later-d '() '(+ x 10) 1000 100 -1)))
  (assert-equal "4.4 Negative stage-level is blocked as CSP error" #t (stage-csp-error? res))
  (assert-equal "4.4 Error rule is invalid-negative-stage-level" 'invalid-negative-stage-level (cadr res)))

;; End of tests
