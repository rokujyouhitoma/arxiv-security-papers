;;; =======================================================================
;;; Test Suite: Triple-Differential Oracle & Metamorphic Fuzzing (Issue #881)
;;; Conforms to DSN-33-03 §3.6 & §4.4
;;; =======================================================================

(display "\n=== [Test Suite: Triple-Differential Oracle & Metamorphic Fuzzing (Issue #881)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; Group 1: Triple-Differential Oracle on Primitive Arithmetic
;;; -----------------------------------------------------------------------
(display "--- Group 1: Triple-Differential Oracle on Arithmetic ---\n")

(let ((res1 (run-triple-differential-oracle '(+ 10 32) '()))
      (res2 (run-triple-differential-oracle '(* 6 7) '()))
      (res3 (run-triple-differential-oracle '(- 100 58) '()))
      (res4 (run-triple-differential-oracle '(bitwise-xor 15 5) '())))
  (assert-equal "1.1 Addition oracle equivalence (V_now == V_residual)" #t (car res1))
  (assert-equal "1.2 Addition result value 42" 42 (cadr res1))
  (assert-equal "1.3 Multiplication oracle equivalence" #t (car res2))
  (assert-equal "1.4 Multiplication result value 42" 42 (cadr res2))
  (assert-equal "1.5 Subtraction oracle equivalence" #t (car res3))
  (assert-equal "1.6 Bitwise-xor oracle equivalence" #t (car res4)))

;;; -----------------------------------------------------------------------
;;; Group 2: Differential Verification on Conditionals and Local Bindings
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Differential Verification on Conditionals and Bindings ---\n")

(let* ((env '((base . 2) (scale . 10)))
       (expr1 '(let ((x (+ base 3))) (* x scale)))
       (res1 (run-triple-differential-oracle expr1 env)))
  (assert-equal "2.1 Let with environment oracle equivalence" #t (car res1))
  (assert-equal "2.2 Evaluation matches: (2+3)*10 = 50" 50 (caddr res1)))

(let* ((expr2 '(if (< 1 2) (+ 40 2) 0))
       (res2 (run-triple-differential-oracle expr2 '())))
  (assert-equal "2.3 Conditional true branch oracle equivalence" #t (car res2))
  (assert-equal "2.4 Conditional true branch value 42" 42 (cadr res2)))

;;; -----------------------------------------------------------------------
;;; Group 3: Metamorphic Binding-Time Perturbation (DSN-33-03 §4.4)
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Metamorphic Binding-Time Perturbation ---\n")

;; Algorithm: Unrolled Power Function power(x, 4) = x * x * x * x
;; We evaluate power(3, 4) under three distinct binding-time partitions:
;; 1. All Static: (stage-now (* 3 (* 3 (* 3 3))))
;; 2. PSDS (Partially Static): exponent unrolled statically, base 'x is dynamic
;; 3. All Dynamic: fully residualized dynamic multiplication

(let* ((base-val 3)
       ;; 1. All Static
       (expr-all-static '(stage-now (* 3 (* 3 (* 3 3)))))
       (val-all-static (eval-with-now-oracle expr-all-static))

       ;; 2. PSDS (Partially Static)
       ;; The loop/unroll is static, but base variable x is dynamic
       (expr-psds '(stage-later (* (stage-lift x) (* (stage-lift x) (* (stage-lift x) (stage-lift x))))))
       (residual-psds (stage-poly-lower expr-psds (list (cons 'x base-val))))
       (val-psds (eval-residual-anf-expr residual-psds (list (cons 'x base-val))))

       ;; 3. All Dynamic
       (expr-all-dynamic '(stage-later (* x (* x (* x x)))))
       (residual-dynamic (stage-poly-lower expr-all-dynamic (list (cons 'x base-val))))
       (val-all-dynamic (eval-residual-anf-expr residual-dynamic (list (cons 'x base-val)))))

  (assert-equal "3.1 All-static power(3, 4) = 81" 81 val-all-static)
  (assert-equal "3.2 PSDS unrolled power(3, 4) = 81" 81 val-psds)
  (assert-equal "3.3 All-dynamic power(3, 4) = 81" 81 val-all-dynamic)
  ;; Metamorphic Soundness Theorem: V_static ≡ V_psds ≡ V_dynamic
  (assert-equal "3.4 Metamorphic Equivalence: V_static == V_psds" #t (= val-all-static val-psds))
  (assert-equal "3.5 Metamorphic Equivalence: V_psds == V_dynamic" #t (= val-psds val-all-dynamic)))

;;; -----------------------------------------------------------------------
;;; Group 4: Metamorphic Dispatch-Table Perturbation
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Metamorphic Dispatch-Table Perturbation ---\n")

;; A dispatch table for opcode: 1 -> (+ a b), 2 -> (- a b), 3 -> (* a b)
;; Evaluate opcode=3, a=7, b=6
(let* ((op 3)
       (a 7)
       (b 6)
       (expected (* 7 6)) ; 42

       ;; 1. All Static
       (expr-static '(stage-now (* 7 6)))
       (v-static (eval-with-now-oracle expr-static))

       ;; 2. PSDS (Opcode known statically, arguments a and b dynamic)
       ;; Partial evaluation prunes op=1 and op=2 branches at compile time!
       (expr-psds-dispatch
        '(stage-later
           (if (= (stage-lift op) 1)
               (+ (stage-lift a) (stage-lift b))
               (if (= (stage-lift op) 2)
                   (- (stage-lift a) (stage-lift b))
                   (* (stage-lift a) (stage-lift b))))))
       (env (list (cons 'op op) (cons 'a a) (cons 'b b)))
       (residual-dispatch (stage-poly-lower expr-psds-dispatch env))
       (v-psds (eval-residual-anf-expr residual-dispatch env)))

  (assert-equal "4.1 Static dispatch matches expected 42" expected v-static)
  (assert-equal "4.2 PSDS pruned dispatch matches expected 42" expected v-psds)
  (assert-equal "4.3 Dispatch Metamorphic Equivalence: V_static == V_psds" #t (= v-static v-psds)))

(display "\n[RESULT] All Triple-Differential Oracle & Metamorphic Fuzzing tests PASSED!\n")
