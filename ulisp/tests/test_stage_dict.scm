;;; =======================================================================
;;; Unit Test Suite: Stage-Polymorphic Dictionaries (Issue #870)
;;; Conforms to DSN-33-03 §3.1, §3.2, §3.3, §3.7
;;; =======================================================================

(test-begin "Stage-Polymorphic Dictionaries (Issue #870)")

;;; -----------------------------------------------------------------------
;;; Group 1: Dictionary Instantiation & Record Inspection
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Dictionary Instantiation & Predicates ---\n")

(define now-d (make-now-dict))
(define later-d (make-later-dict))

(assert-equal "1.1 now-d is stage-dict?" #t (stage-dict? now-d))
(assert-equal "1.2 later-d is stage-dict?" #t (stage-dict? later-d))
(assert-equal "1.3 now-d is stage-dict-now?" #t (stage-dict-now? now-d))
(assert-equal "1.4 now-d is not stage-dict-later?" #f (stage-dict-later? now-d))
(assert-equal "1.5 later-d is stage-dict-later?" #t (stage-dict-later? later-d))
(assert-equal "1.6 later-d is not stage-dict-now?" #f (stage-dict-now? later-d))
(assert-equal "1.7 now-d stage-level is 1" 1 (stage-dict-stage-level now-d))
(assert-equal "1.8 later-d stage-level is 0" 0 (stage-dict-stage-level later-d))

;;; -----------------------------------------------------------------------
;;; Group 2: Now Dictionary Immediate Primitive Execution
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Now Dictionary Immediate Primitives ---\n")

(assert-equal "2.1 Now addition (+ 10 32)" 42 (stage-apply-prim-2 now-d '+ 10 32))
(assert-equal "2.2 Now subtraction (- 100 58)" 42 (stage-apply-prim-2 now-d '- 100 58))
(assert-equal "2.3 Now multiplication (* 6 7)" 42 (stage-apply-prim-2 now-d '* 6 7))
(assert-equal "2.4 Now division quotient (quotient 85 2)" 42 (stage-apply-prim-2 now-d 'quotient 85 2))
(assert-equal "2.5 Now unary abs (abs -42)" 42 (stage-apply-prim-1 now-d 'abs -42))
(assert-equal "2.6 Now unary not (not #f)" #t (stage-apply-prim-1 now-d 'not #f))
(assert-equal "2.7 Now unary not on truthy (not 42)" #f (stage-apply-prim-1 now-d 'not 42))
(assert-equal "2.8 Now cons (cons 1 2)" '(1 . 2) (stage-apply-prim-2 now-d 'cons 1 2))
(assert-equal "2.9 Now car (car (cons 42 '()))" 42 (stage-apply-prim-1 now-d 'car '(42)))
(assert-equal "2.10 Now cdr (cdr (cons 1 42))" 42 (stage-apply-prim-1 now-d 'cdr '(1 . 42)))
(assert-equal "2.11 Now bitwise-and (bitwise-and 12 10)" 8 (stage-apply-prim-2 now-d 'bitwise-and 12 10))
(assert-equal "2.12 Now comparison (< 10 20)" #t (stage-apply-prim-2 now-d '< 10 20))
(assert-equal "2.13 Now comparison (> 10 20)" #f (stage-apply-prim-2 now-d '> 10 20))

;;; -----------------------------------------------------------------------
;;; Group 3: Now Dictionary Control Flow & Branch Selection
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Now Dictionary Branch Pruning ---\n")

;; True branch taken, false branch with division by zero is never executed!
(assert-equal "3.1 Truthy if branch taken"
              42
              (stage-emit-if now-d #t
                             (lambda () 42)
                             (lambda () (/ 1 0))))

;; False branch taken, true branch with division by zero is never executed!
(assert-equal "3.2 Falsy if branch taken"
              99
              (stage-emit-if now-d #f
                             (lambda () (/ 1 0))
                             (lambda () 99)))

;; Now lift-val is identity
(assert-equal "3.3 Now lift-val number" 42 (stage-lift-val now-d 42 #f))
(assert-equal "3.4 Now lift-val symbol" 'foo (stage-lift-val now-d 'foo #f))

;;; -----------------------------------------------------------------------
;;; Group 4: Later Dictionary Residual Node Emission
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Later Dictionary Residual ANF Emission ---\n")

(assert-equal "4.1 Later primitive (+ x y)"
              '(+ x y)
              (stage-apply-prim-2 later-d '+ 'x 'y))

(assert-equal "4.2 Later unary (abs z)"
              '(abs z)
              (stage-apply-prim-1 later-d 'abs 'z))

(assert-equal "4.3 Later let binding (let-anf ((t0 (+ x 1))) t0)"
              '(let-anf ((t0 (+ x 1))) t0)
              (stage-bind-let later-d 't0 '(+ x 1) (lambda () 't0)))

(assert-equal "4.4 Later conditional emission (if-anf cond then else)"
              '(if-anf (< x 0) (- 0 x) x)
              (stage-emit-if later-d '(< x 0)
                             (lambda () '(- 0 x))
                             (lambda () 'x)))

(assert-equal "4.5 Later call emission (call-anf fn a b)"
              '(call-anf my-fn a b)
              (stage-emit-call later-d 'my-fn '(a b)))

;; Later lift-val wraps symbols and lists into quoted literals
(assert-equal "4.6 Later lift-val number" 42 (stage-lift-val later-d 42 #f))
(assert-equal "4.7 Later lift-val symbol" '(quote foo) (stage-lift-val later-d 'foo #f))
(assert-equal "4.8 Later lift-val empty list" '(quote ()) (stage-lift-val later-d '() #f))
(assert-equal "4.9 Later lift-val pair" '(quote (1 2)) (stage-lift-val later-d '(1 2) #f))

;;; -----------------------------------------------------------------------
;;; Group 5: Temporary Variable Generator (No-set! cons Box)
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Temporary Variable Generator ---\n")

(define gen-t (make-temp-var-generator "t_"))
(assert-equal "5.1 First temp var" 't_0 (gen-t))
(assert-equal "5.2 Second temp var" 't_1 (gen-t))
(assert-equal "5.3 Third temp var" 't_2 (gen-t))

;; End of tests
