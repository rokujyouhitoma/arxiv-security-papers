;;; =======================================================================
;;; Unit Test Suite: 4-Valued BTA Lattice & Inference (Issue #874)
;;; Conforms to DSN-33-03 §4.1
;;; =======================================================================

(test-begin "4-Valued BTA Lattice & Inference (Issue #874)")

;;; -----------------------------------------------------------------------
;;; Group 1: 4-Valued Lattice Axioms & Predicates
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Lattice Order, Join & Meet Axioms ---\n")

;; Elements check
(assert-equal "1.1 'bot is bta-elem?" #t (bta-elem? 'bot))
(assert-equal "1.2 'static is bta-elem?" #t (bta-elem? 'static))
(assert-equal "1.3 'psds is bta-elem?" #t (bta-elem? 'psds))
(assert-equal "1.4 'dynamic is bta-elem?" #t (bta-elem? 'dynamic))
(assert-equal "1.5 'top is bta-elem?" #t (bta-elem? 'top))
(assert-equal "1.6 'unknown is not bta-elem?" #f (bta-elem? 'unknown))

;; Lattice Ordering (bot <= static <= psds <= dynamic <= top)
(assert-equal "1.7 bot <= static" #t (bta-leq? 'bot 'static))
(assert-equal "1.8 static <= psds" #t (bta-leq? 'static 'psds))
(assert-equal "1.9 psds <= dynamic" #t (bta-leq? 'psds 'dynamic))
(assert-equal "1.10 dynamic <= top" #t (bta-leq? 'dynamic 'top))
(assert-equal "1.11 dynamic <= static is false" #f (bta-leq? 'dynamic 'static))
(assert-equal "1.12 Reflexivity static <= static" #t (bta-leq? 'static 'static))

;; Join Operations (LUB)
(assert-equal "1.13 bot join static = static" 'static (bta-join 'bot 'static))
(assert-equal "1.14 static join psds = psds" 'psds (bta-join 'static 'psds))
(assert-equal "1.15 static join dynamic = dynamic" 'dynamic (bta-join 'static 'dynamic))
(assert-equal "1.16 psds join dynamic = dynamic" 'dynamic (bta-join 'psds 'dynamic))
(assert-equal "1.17 dynamic join top = top" 'top (bta-join 'dynamic 'top))

;; Meet Operations (GLB)
(assert-equal "1.18 dynamic meet static = static" 'static (bta-meet 'dynamic 'static))
(assert-equal "1.19 psds meet static = static" 'static (bta-meet 'psds 'static))
(assert-equal "1.20 top meet psds = psds" 'psds (bta-meet 'top 'psds))

;;; -----------------------------------------------------------------------
;;; Group 2: Expression BTA Inference (Static vs Dynamic vs PSDS)
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Expression BTA Inference ---\n")

;; Literals & Constants
(assert-equal "2.1 Number is static" 'static (bta-infer-expr 42 (bta-env-empty)))
(assert-equal "2.2 Boolean is static" 'static (bta-infer-expr #t (bta-env-empty)))
(assert-equal "2.3 String is static" 'static (bta-infer-expr "hello" (bta-env-empty)))
(assert-equal "2.4 Quoted datum is static" 'static (bta-infer-expr '(quote (a b c)) (bta-env-empty)))

;; Variables
(define env1 (bta-env-extend (bta-env-extend (bta-env-empty) 's 'static) 'd 'dynamic))
(assert-equal "2.5 Static variable lookup" 'static (bta-infer-expr 's env1))
(assert-equal "2.6 Dynamic variable lookup" 'dynamic (bta-infer-expr 'd env1))
(assert-equal "2.7 Unbound variable defaults to dynamic" 'dynamic (bta-infer-expr 'unbound env1))

;; Pure Primitives
(assert-equal "2.8 Static arithmetic (+ 10 32)" 'static (bta-infer-expr '(+ 10 32) (bta-env-empty)))
(assert-equal "2.9 Dynamic arithmetic (+ s d)" 'dynamic (bta-infer-expr '(+ s d) env1))
(assert-equal "2.10 Nested static arithmetic" 'static (bta-infer-expr '(* (+ 1 2) (- 10 3)) (bta-env-empty)))

;;; -----------------------------------------------------------------------
;;; Group 3: Pairs & Partially Static Data Structures (PSDS)
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Pairs & PSDS Construction ---\n")

;; Cons
(assert-equal "3.1 Static cons (cons 1 2)" 'static (bta-infer-expr '(cons 1 2) (bta-env-empty)))
(assert-equal "3.2 Partially static cons (cons 1 d)" 'psds (bta-infer-expr '(cons 1 d) env1))
(assert-equal "3.3 Both dynamic cons (cons d1 d2)" 'psds (bta-infer-expr '(cons d d) env1))

;; Car / Cdr
(assert-equal "3.4 Car on static pair" 'static (bta-infer-expr '(car (cons 1 2)) (bta-env-empty)))
(assert-equal "3.5 Car on PSDS pair defaults safely to dynamic" 'dynamic (bta-infer-expr '(car (cons 1 d)) env1))

;;; -----------------------------------------------------------------------
;;; Group 4: Local Bindings (let) & Conditionals (if)
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Local Bindings & Conditionals ---\n")

;; Let
(assert-equal "4.1 Static let" 'static (bta-infer-expr '(let ((x 10) (y 20)) (+ x y)) (bta-env-empty)))
(assert-equal "4.2 Dynamic let with dynamic rhs" 'dynamic (bta-infer-expr '(let ((y (+ d 1))) (* y 2)) env1))

;; Conditionals
(assert-equal "4.3 Static if with static branches" 'static (bta-infer-expr '(if (< 1 2) 10 20) (bta-env-empty)))
(assert-equal "4.4 Static if with dynamic branch joins to dynamic" 'dynamic (bta-infer-expr '(if (< 1 2) 10 d) env1))
(assert-equal "4.5 Dynamic if forces dynamic" 'dynamic (bta-infer-expr '(if (< d 0) 10 20) env1))

;;; -----------------------------------------------------------------------
;;; Group 5: AST Annotation Wrapper
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: AST Annotation Wrapper ---\n")

(define ann (bta-annotate-ast '(+ 1 2) (bta-env-empty)))
(assert-equal "5.1 Annotation node predicate" #t (bta-annotated? ann))
(assert-equal "5.2 Annotation type is static" 'static (bta-annotation-type ann))
(assert-equal "5.3 Annotation expr is (+ 1 2)" '(+ 1 2) (bta-annotation-expr ann))

;; End of tests
