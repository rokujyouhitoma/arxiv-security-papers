;;; =======================================================================
;;; Unit Test Suite: Speculative Trap Protection & Later Demotion (Issue #875)
;;; Conforms to DSN-33-03 §4.2
;;; =======================================================================

(test-begin "Speculative Trap Protection & Later Demotion (Issue #875)")

(define later-d (make-later-dict))
(define now-d (make-now-dict))

;;; -----------------------------------------------------------------------
;;; Group 1: Purity & Trapping Predicates
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Purity & Trapping Predicates ---\n")

(assert-equal "1.1 Addition is pure" #t (stage-pure-effect-free? '+))
(assert-equal "1.2 Multiplication is pure" #t (stage-pure-effect-free? '*))
(assert-equal "1.3 Not is pure" #t (stage-pure-effect-free? 'not))
(assert-equal "1.4 Cons is pure" #t (stage-pure-effect-free? 'cons))

(assert-equal "1.5 Division is potentially trapping" #t (stage-potentially-trapping-prim? '/))
(assert-equal "1.6 Modulo is potentially trapping" #t (stage-potentially-trapping-prim? 'modulo))
(assert-equal "1.7 Remainder is potentially trapping" #t (stage-potentially-trapping-prim? 'remainder))
(assert-equal "1.8 Car is potentially trapping" #t (stage-potentially-trapping-prim? 'car))

(assert-equal "1.9 Display is impure" #t (stage-impure-primitive? 'display))
(assert-equal "1.10 Write is impure" #t (stage-impure-primitive? 'write))
(assert-equal "1.11 Addition is not impure" #f (stage-impure-primitive? '+))

;;; -----------------------------------------------------------------------
;;; Group 2: Speculative Trap Prevention (Division by Zero in Dynamic If)
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Speculative Trap Demotion in Dynamic If ---\n")

;; Division by zero under dynamic if does NOT crash compiler at compile-time!
;; It is cleanly demoted to residual call (/ 10 0).
(let ((res (eval-in-stage later-d '() '(if (< x 0) (/ 10 0) 42) 1000 100)))
  (assert-equal "2.1 Speculative division by zero cleanly demoted"
                '(if-anf (< x 0) (/ 10 0) 42)
                (stage-val-payload res)))

(let ((res (eval-in-stage later-d '() '(if (< x 0) (modulo 10 0) 42) 1000 100)))
  (assert-equal "2.2 Speculative modulo by zero cleanly demoted"
                '(if-anf (< x 0) (modulo 10 0) 42)
                (stage-val-payload res)))

(let ((res (eval-in-stage later-d '() '(if (< x 0) (remainder 10 0) 42) 1000 100)))
  (assert-equal "2.3 Speculative remainder by zero cleanly demoted"
                '(if-anf (< x 0) (remainder 10 0) 42)
                (stage-val-payload res)))

;;; -----------------------------------------------------------------------
;;; Group 3: Safe Static Folding Under Dynamic If
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Safe Static Folding Under Dynamic If ---\n")

;; Pure and safe static expressions under dynamic if ARE correctly folded to constants!
(let ((res (eval-in-stage later-d '() '(if (< x 0) (+ 10 20) 42) 1000 100)))
  (assert-equal "3.1 Safe static addition folded under dynamic if"
                '(if-anf (< x 0) 30 42)
                (stage-val-payload res)))

(let ((res (eval-in-stage later-d '() '(if (< x 0) (* 6 7) (- 50 8)) 1000 100)))
  (assert-equal "3.2 Both branches folded to constants under dynamic if"
                '(if-anf (< x 0) 42 42)
                (stage-val-payload res)))

;;; -----------------------------------------------------------------------
;;; Group 4: Side-Effect Protection Under Dynamic If
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Side-Effect Protection Under Dynamic If ---\n")

;; Impure operations (display) under dynamic if are NOT executed speculatively at compile time!
(let ((res (eval-in-stage later-d '() '(if (< x 0) (display "alert") 42) 1000 100)))
  (assert-equal "4.1 Impure display demoted to residual call"
                '(if-anf (< x 0) (display "alert") 42)
                (stage-val-payload res)))

;;; -----------------------------------------------------------------------
;;; Group 5: Dead-Branch Elimination in Static If
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Dead-Branch Elimination in Static If ---\n")

;; In static if with truthy condition, dead branch with division by zero is 100% eliminated!
(let ((res (eval-in-stage later-d '() '(if #t 42 (/ 10 0)) 1000 100)))
  (assert-equal "5.1 Truthy static if: dead division-by-zero eliminated"
                42
                (stage-val-payload res)))

;; In static if with falsy condition, dead branch with division by zero is 100% eliminated!
(let ((res (eval-in-stage later-d '() '(if #f (/ 10 0) 99) 1000 100)))
  (assert-equal "5.2 Falsy static if: dead division-by-zero eliminated"
                99
                (stage-val-payload res)))

;; End of tests
