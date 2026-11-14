;;; =======================================================================
;;; Unit & Integration Test Suite: Nanopass AST Constant Evaluator & CTFE
;;; Conforms to DSN-38 §2, DSN-33 §3.1 & Issue #825
;;; =======================================================================

(test-begin "Nanopass AST Constant Evaluator & CTFE")

;;; -----------------------------------------------------------------------
;;; Group 1: Basic Literals & Self-Evaluating Constants
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Basic Literals & Self-Evaluating Constants ---\n")

(assert-equal "1.1 Number literal evaluates to self" 42 (eval-in-language 'L_core 42))
(assert-equal "1.2 Boolean #t evaluates to self" #t (eval-in-language 'L_core #t))
(assert-equal "1.3 Boolean #f evaluates to self" #f (eval-in-language 'L_core #f))
(assert-equal "1.4 Character literal evaluates to self" #\A (eval-in-language 'L_core #\A))
(assert-equal "1.5 String literal evaluates to quoted datum" '(quote "hello") (eval-in-language 'L_core "hello"))
(assert-equal "1.6 Quoted symbol evaluates to quoted datum" '(quote foo) (eval-in-language 'L_core '(quote foo)))
(assert-equal "1.7 Quoted list evaluates to quoted datum" '(quote (1 2 3)) (eval-in-language 'L_core '(quote (1 2 3))))

;;; -----------------------------------------------------------------------
;;; Group 2: Pure Arithmetic & Logical CTFE Reduction
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Pure Arithmetic & Logical CTFE Reduction ---\n")

;; Variadic & binary arithmetic
(assert-equal "2.1 Variadic addition (+ 1 2 3 4)" 10 (eval-in-language 'L_core '(+ 1 2 3 4)))
(assert-equal "2.2 Binary subtraction (- 100 58)" 42 (eval-in-language 'L_core '(- 100 58)))
(assert-equal "2.3 Variadic multiplication (* 2 3 7)" 42 (eval-in-language 'L_core '(* 2 3 7)))
(assert-equal "2.4 Quotient division (quotient 100 7)" 14 (eval-in-language 'L_core '(quotient 100 7)))
(assert-equal "2.5 Modulo operation (modulo 100 7)" 2 (eval-in-language 'L_core '(modulo 100 7)))
(assert-equal "2.6 Remainder operation (remainder -100 7)" -2 (eval-in-language 'L_core '(remainder -100 7)))
(assert-equal "2.7 Absolute value (abs -42)" 42 (eval-in-language 'L_core '(abs -42)))
(assert-equal "2.8 Min of numbers (min 10 3 42 7)" 3 (eval-in-language 'L_core '(min 10 3 42 7)))
(assert-equal "2.9 Max of numbers (max 10 3 42 7)" 42 (eval-in-language 'L_core '(max 10 3 42 7)))

;; Predicates and Booleans
(assert-equal "2.10 Equality predicate (= 42 42)" #t (eval-in-language 'L_core '(= 42 42)))
(assert-equal "2.11 Inequality predicate (< 10 20)" #t (eval-in-language 'L_core '(< 10 20)))
(assert-equal "2.12 False inequality (> 10 20)" #f (eval-in-language 'L_core '(> 10 20)))
(assert-equal "2.13 Logical not (not #f)" #t (eval-in-language 'L_core '(not #f)))
(assert-equal "2.14 Logical not on truthy (not 42)" #f (eval-in-language 'L_core '(not 42)))
(assert-equal "2.15 Number type predicate (number? 42)" #t (eval-in-language 'L_core '(number? 42)))
(assert-equal "2.16 Null predicate (null? '())" #t (eval-in-language 'L_core '(null? '())))

;; Bitwise operations
(assert-equal "2.17 Bitwise and (bitwise-and 12 10)" 8 (eval-in-language 'L_core '(bitwise-and 12 10)))
(assert-equal "2.18 Bitwise or (bitwise-ior 12 3)" 15 (eval-in-language 'L_core '(bitwise-ior 12 3)))
(assert-equal "2.19 Bitwise xor (bitwise-xor 15 5)" 10 (eval-in-language 'L_core '(bitwise-xor 15 5)))
(assert-equal "2.20 Arithmetic shift left (arithmetic-shift 1 4)" 16 (eval-in-language 'L_core '(arithmetic-shift 1 4)))
(assert-equal "2.21 Arithmetic shift right (arithmetic-shift 64 -2)" 16 (eval-in-language 'L_core '(arithmetic-shift 64 -2)))

;;; -----------------------------------------------------------------------
;;; Group 3: Local Bindings (let / let*) and Conditionals (if)
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Local Bindings & Conditionals ---\n")

;; Let expressions
(assert-equal "3.1 Simple let reduction" 30 (eval-in-language 'L_core '(let ((x 10) (y 20)) (+ x y))))
(assert-equal "3.2 Nested let bindings" 42 (eval-in-language 'L_core '(let ((a 2)) (let ((b 3)) (* a (* b 7))))))

;; Let* expressions
(assert-equal "3.3 Let* sequential binding" 20 (eval-in-language 'L_core '(let* ((x 5) (y (* x 2)) (z (+ x y -5))) (+ z 10))))

;; Conditionals and branch dead-code protection
(assert-equal "3.4 Truthy if branch selected" 12 (eval-in-language 'L_core '(if (< 5 10) (* 3 4) (/ 1 0))))
(assert-equal "3.5 Falsy if branch selected" 42 (eval-in-language 'L_core '(if (> 5 10) (/ 1 0) (+ 40 2))))
(assert-equal "3.6 Nested if reduction" 99 (eval-in-language 'L_core '(if (= 1 1) (if (= 2 2) 99 0) -1)))

;; Sequential begin expressions
(assert-equal "3.7 Sequential begin evaluation" 42 (eval-in-language 'L_core '(begin (+ 1 2) (* 3 4) 42)))

;;; -----------------------------------------------------------------------
;;; Group 4: First-Class Closures & Higher-Order Functions
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: First-Class Closures & Higher-Order Functions ---\n")

(assert-equal "4.1 Direct lambda application" 25 (eval-in-language 'L_core '((lambda (x y) (+ (* x x) (* y y))) 3 4)))
(assert-equal "4.2 Curried lambda application" 42 (eval-in-language 'L_core '(((lambda (x) (lambda (y) (+ x y))) 40) 2)))
(assert-equal "4.3 Let-bound pure function application" 20 (eval-in-language 'L_core '(let ((double (lambda (x) (+ x x)))) (double (double 5)))))

;;; -----------------------------------------------------------------------
;;; Group 5: Resource Bounds & Safety Guards (CWE-400 Protection)
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Safety Guards & Resource Bounds (CWE-400) ---\n")

;; Division by zero does not crash, safely returns #f (unreduced)
(assert-false "5.1 Division by zero safely unreduced" (eval-in-language 'L_core '(/ 10 0)))
(assert-false "5.2 Modulo by zero safely unreduced" (eval-in-language 'L_core '(modulo 10 0)))

;; Free / unassigned variables safely fallback to unreduced
(assert-false "5.3 Free variable x safely unreduced" (eval-in-language 'L_core '(+ x 10)))
(assert-false "5.4 Partially bound expression with free var" (eval-in-language 'L_core '(let ((a 5)) (+ a unassigned_var))))

;; Impure / side-effecting operations safely unreduced
(assert-false "5.5 Unknown / side-effecting function unreduced" (eval-in-language 'L_core '(display "hello")))

;; Low step limit exhaustion forces safe timeout fallback
(assert-false "5.6 Step limit exhaustion triggers timeout fallback"
  (eval-in-language-opt 'L_core
    '((lambda (x) (+ x (+ x (+ x (+ x (+ x x)))))) 10)
    '()
    2   ; Very small step limit (2 steps)
    100 ; Depth limit
  ))

;; Low depth limit exhaustion forces safe depth fallback
(assert-false "5.7 Depth limit exhaustion triggers depth fallback"
  (eval-in-language-opt 'L_core
    '(+ (+ (+ (+ 1 2) 3) 4) 5)
    '()
    1000 ; Step limit
    2    ; Very small depth limit (2 levels)
  ))

;; ctfe-try-reduce helper
(assert-equal "5.8 ctfe-try-reduce succeeds on closed pure expr" 42 (ctfe-try-reduce '(+ 40 2)))
(assert-false "5.9 ctfe-try-reduce rejects expression with free variable" (ctfe-try-reduce '(+ y 2)))

;;; -----------------------------------------------------------------------
;;; Group 6: Language-Specific Evaluator Extensibility
;;; -----------------------------------------------------------------------
(display "\n--- Group 6: Language Evaluator Extensibility ---\n")

(register-language-evaluator! 'TestCustomLang
  (lambda (expr env fuel depth)
    (if (and (pair? expr) (eq? (car expr) '%custom-op))
        (val->ast-const (* (cadr expr) 100))
        (ctfe-eval expr env fuel depth))))

(assert-equal "6.1 Custom evaluator registered and executed" 500 (eval-in-language 'TestCustomLang '(%custom-op 5)))
(assert-equal "6.2 Custom evaluator falls back to standard eval" 42 (eval-in-language 'TestCustomLang '(+ 40 2)))

;;; -----------------------------------------------------------------------
;;; Group 7: CP0 Pass Integration Verification
;;; -----------------------------------------------------------------------
(display "\n--- Group 7: CP0 Pass Integration Verification ---\n")

;; Verify that cp0-optimize reduces nested arithmetic via eval-in-language
(define cp0-in-1 '(+ (* 2 3) (- 10 4)))
(define cp0-out-1 (cp0-optimize cp0-in-1))
(assert-equal "7.1 CP0 reduces nested arithmetic to constant" 12 cp0-out-1)

;; Verify that cp0-optimize reduces multi-argument expressions via eval-in-language
(define cp0-in-2 '(+ 1 2 3 4))
(define cp0-out-2 (cp0-optimize cp0-in-2))
(assert-equal "7.2 CP0 reduces multi-arg addition via CTFE" 10 cp0-out-2)

(define cp0-in-2b '(bitwise-and 15 7))
(define cp0-out-2b (cp0-optimize cp0-in-2b))
(assert-equal "7.2b CP0 reduces bitwise-and via CTFE" 7 cp0-out-2b)

;; Verify that expressions with free variables remain unreduced
(define cp0-in-3 '(+ x (* 2 3)))
(define cp0-out-3 (cp0-optimize cp0-in-3))
(assert-equal "7.3 CP0 partially folds constant subtree (+ x 6)" '(+ x 6) cp0-out-3)

(test-end "Nanopass AST Constant Evaluator & CTFE")
