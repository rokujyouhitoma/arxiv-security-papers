;;; =======================================================================
;;; Unit Test Suite: Single-Source Semantic Oracle Regression (Issue #873)
;;; Conforms to DSN-33-03 §3.6 & Issue #825
;;; =======================================================================

(test-begin "Single-Source Semantic Oracle Regression (Issue #873)")

;;; -----------------------------------------------------------------------
;;; Group 1: Basic Literals & Self-Evaluating Constants via Now Oracle
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Basic Literals & Self-Evaluating Constants ---\n")

(assert-equal "1.1 Number literal" 42 (eval-with-now-oracle 42))
(assert-equal "1.2 Boolean #t" #t (eval-with-now-oracle #t))
(assert-equal "1.3 Boolean #f" #f (eval-with-now-oracle #f))
(assert-equal "1.4 Character literal" #\A (eval-with-now-oracle #\A))
(assert-equal "1.5 String literal" '(quote "hello") (eval-with-now-oracle "hello"))
(assert-equal "1.6 Quoted symbol" '(quote foo) (eval-with-now-oracle '(quote foo)))
(assert-equal "1.7 Quoted list" '(quote (1 2 3)) (eval-with-now-oracle '(quote (1 2 3))))

;;; -----------------------------------------------------------------------
;;; Group 2: Pure Arithmetic & Logical CTFE Reduction via Now Oracle
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Pure Arithmetic & Logical CTFE Reduction ---\n")

(assert-equal "2.1 Binary addition (+ 10 32)" 42 (eval-with-now-oracle '(+ 10 32)))
(assert-equal "2.2 Binary subtraction (- 100 58)" 42 (eval-with-now-oracle '(- 100 58)))
(assert-equal "2.3 Binary multiplication (* 6 7)" 42 (eval-with-now-oracle '(* 6 7)))
(assert-equal "2.4 Quotient division (quotient 100 7)" 14 (eval-with-now-oracle '(quotient 100 7)))
(assert-equal "2.5 Modulo operation (modulo 100 7)" 2 (eval-with-now-oracle '(modulo 100 7)))
(assert-equal "2.6 Remainder operation (remainder -100 7)" -2 (eval-with-now-oracle '(remainder -100 7)))
(assert-equal "2.7 Absolute value (abs -42)" 42 (eval-with-now-oracle '(abs -42)))
(assert-equal "2.8 Min of numbers (min 10 3)" 3 (eval-with-now-oracle '(min 10 3)))
(assert-equal "2.9 Max of numbers (max 10 42)" 42 (eval-with-now-oracle '(max 10 42)))

;; Predicates
(assert-equal "2.10 Equality predicate (= 42 42)" #t (eval-with-now-oracle '(= 42 42)))
(assert-equal "2.11 Inequality predicate (< 10 20)" #t (eval-with-now-oracle '(< 10 20)))
(assert-equal "2.12 False inequality (> 10 20)" #f (eval-with-now-oracle '(> 10 20)))
(assert-equal "2.13 Logical not (not #f)" #t (eval-with-now-oracle '(not #f)))
(assert-equal "2.14 Logical not on truthy (not 42)" #f (eval-with-now-oracle '(not 42)))
(assert-equal "2.15 Number type predicate (number? 42)" #t (eval-with-now-oracle '(number? 42)))
(assert-equal "2.16 Null predicate (null? '())" #t (eval-with-now-oracle '(null? '())))

;; Bitwise operations
(assert-equal "2.17 Bitwise and (bitwise-and 12 10)" 8 (eval-with-now-oracle '(bitwise-and 12 10)))
(assert-equal "2.18 Bitwise or (bitwise-ior 12 3)" 15 (eval-with-now-oracle '(bitwise-ior 12 3)))
(assert-equal "2.19 Bitwise xor (bitwise-xor 15 5)" 10 (eval-with-now-oracle '(bitwise-xor 15 5)))
(assert-equal "2.20 Arithmetic shift left (arithmetic-shift 1 4)" 16 (eval-with-now-oracle '(arithmetic-shift 1 4)))
(assert-equal "2.21 Arithmetic shift right (arithmetic-shift 64 -2)" 16 (eval-with-now-oracle '(arithmetic-shift 64 -2)))

;;; -----------------------------------------------------------------------
;;; Group 3: Local Bindings (let) and Conditionals (if) via Now Oracle
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Local Bindings & Conditionals ---\n")

(assert-equal "3.1 Simple let reduction" 30 (eval-with-now-oracle '(let ((x 10) (y 20)) (+ x y))))
(assert-equal "3.2 Nested let bindings" 42 (eval-with-now-oracle '(let ((a 2)) (let ((b 3)) (* a (* b 7))))))
(assert-equal "3.3 Truthy if branch selected" 12 (eval-with-now-oracle '(if (< 5 10) (* 3 4) (/ 1 0))))
(assert-equal "3.4 Falsy if branch selected" 42 (eval-with-now-oracle '(if (> 5 10) (/ 1 0) (+ 40 2))))
(assert-equal "3.5 Nested if reduction" 99 (eval-with-now-oracle '(if (= 1 1) (if (= 2 2) 99 0) -1)))
(assert-equal "3.6 Sequential begin evaluation" 42 (eval-with-now-oracle '(begin (+ 1 2) (* 3 4) 42)))

;;; -----------------------------------------------------------------------
;;; Group 4: Safety Guards & Resource Bounds (CWE-400 Protection)
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Safety Guards & Resource Bounds (CWE-400) ---\n")

;; Division / Modulo by zero safely unreduced (#f)
(assert-false "4.1 Division by zero safely unreduced" (eval-with-now-oracle '(/ 10 0)))
(assert-false "4.2 Modulo by zero safely unreduced" (eval-with-now-oracle '(modulo 10 0)))

;; Free / unassigned variables safely fallback to unreduced (#f)
(assert-false "4.3 Free variable x safely unreduced" (eval-with-now-oracle '(+ x 10)))
(assert-false "4.4 Partially bound expression with free var" (eval-with-now-oracle '(let ((a 5)) (+ a unassigned_var))))

;; Fuel step limit exhaustion forces safe timeout fallback (#f)
(assert-false "4.5 Step limit exhaustion triggers safe timeout fallback"
  (eval-with-now-oracle-opt '(+ 1 (+ 2 (+ 3 4))) '() 2 100))

;; Depth limit exhaustion forces safe depth overflow fallback (#f)
(assert-false "4.6 Depth limit exhaustion triggers safe overflow fallback"
  (eval-with-now-oracle-opt '(+ 1 (+ 2 (+ 3 4))) '() 1000 1))

;;; -----------------------------------------------------------------------
;;; Group 5: Single-Source Semantic Oracle Equivalence (V_Now ≡ V_CTFE)
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Single-Source Semantic Oracle Equivalence (Zero Semantic Drift) ---\n")

;; Verify that eval-in-language via registered 'L_stage_poly produces 100% identical results to 'L_core
(assert-equal "5.1 Oracle equivalence on arithmetic"
              (eval-in-language 'L_core '(* 6 7))
              (eval-in-language 'L_stage_poly '(* 6 7)))

(assert-equal "5.2 Oracle equivalence on let expressions"
              (eval-in-language 'L_core '(let ((x 10) (y 32)) (+ x y)))
              (eval-in-language 'L_stage_poly '(let ((x 10) (y 32)) (+ x y))))

(assert-equal "5.3 Oracle equivalence on nested conditionals"
              (eval-in-language 'L_core '(if (< 1 2) (+ 40 2) (/ 1 0)))
              (eval-in-language 'L_stage_poly '(if (< 1 2) (+ 40 2) (/ 1 0))))

(assert-equal "5.4 Oracle equivalence on bitwise operations"
              (eval-in-language 'L_core '(bitwise-xor 15 5))
              (eval-in-language 'L_stage_poly '(bitwise-xor 15 5)))

(assert-equal "5.5 Oracle equivalence on division by zero safety"
              (eval-in-language 'L_core '(/ 10 0))
              (eval-in-language 'L_stage_poly '(/ 10 0)))

;; End of tests
