;;; =======================================================================
;;; ULisp Lightweight IR Verifier & Invariant Pass Checker Test Suite
;;; Conforms to Issue #576 & DSN-33 Architecture Specification
;;; =======================================================================

(display "=======================================================\n")
(display " Starting Lightweight IR Verifier Unit Test Suite\n")
(display "=======================================================\n")

;; Ensure verifier is enabled in non-strict mode for asserting returns
(enable-verifier!)
(set-verifier-strict! #f)

(define *test-count* (cons 0 '()))
(define *pass-count* (cons 0 '()))

(define (assert-true name expr-result)
  (set-car! *test-count* (+ (car *test-count*) 1))
  (if expr-result
      (begin
        (set-car! *pass-count* (+ (car *pass-count*) 1))
        (display "  [PASS] ")
        (display name)
        (newline))
      (begin
        (display "  [FAIL] ")
        (display name)
        (newline)
        (error "Assertion failed" name))))

(define (assert-false name expr-result)
  (set-car! *test-count* (+ (car *test-count*) 1))
  (if (not expr-result)
      (begin
        (set-car! *pass-count* (+ (car *pass-count*) 1))
        (display "  [PASS] ")
        (display name)
        (newline))
      (begin
        (display "  [FAIL] Expected failure/rejection: ")
        (display name)
        (newline)
        (error "Assertion failed" name))))

;;; -----------------------------------------------------------------------
;;; Group 1: Pass 030 Desugar Output Invariant Verification
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Pass 030 Desugar Output Verifier ---\n")

;; 1.1 Valid desugared forms
(assert-true "valid desugared let and if"
             (verify-desugared-ast '(let ((x 10) (y 20)) (if x y 0))))

(assert-true "valid desugared lambda and begin"
             (verify-desugared-ast '(lambda (a b) (begin (set! a 1) (+ a b)))))

;; 1.2 Invalid forms: prohibited sugar keywords
(assert-false "reject remaining cond"
              (verify-desugared-ast '(cond ((= x 1) 10) (else 20))))

(assert-false "reject remaining let*"
              (verify-desugared-ast '(let* ((a 1) (b 2)) (+ a b))))

(assert-false "reject remaining and"
              (verify-desugared-ast '(if (and x y) 1 0)))

(assert-false "reject remaining or"
              (verify-desugared-ast '(if (or x y) 1 0)))

(assert-false "reject remaining named-let"
              (verify-desugared-ast '(let loop ((i 0)) (loop (+ i 1)))))

(assert-false "reject remaining let-values"
              (verify-desugared-ast '(let-values (((a b) (values 1 2))) (+ a b))))

;;; -----------------------------------------------------------------------
;;; Group 2: Pass 070 ANF Output Invariant Verification
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Pass 070 ANF Output Verifier ---\n")

;; 2.1 Valid ANF: all arguments are atomic
(assert-true "valid ANF flat addition"
             (verify-anf-ast '(let ((t0 (+ a b))) (let ((t1 (+ t0 c))) t1))))

(assert-true "valid ANF if with atomic condition"
             (verify-anf-ast '(let ((t0 (< x 10))) (if t0 1 2))))

;; 2.2 Invalid ANF: nested compound expressions in argument positions
(assert-false "reject nested binary operator in argument"
              (verify-anf-ast '(+ a (+ b c))))

(assert-false "reject nested call in function argument"
              (verify-anf-ast '(f (g x))))

(assert-false "reject non-atomic if-condition"
              (verify-anf-ast '(if (< x 10) 1 2)))

;;; -----------------------------------------------------------------------
;;; Group 3: Pass 110 Closure Convert Output Invariant Verification
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Pass 110 Closure Convert Output Verifier ---\n")

;; 3.1 Valid closure forms
(assert-true "valid %make-closure with symbol label and atomic free vars"
             (verify-closure-ast '(%make-closure .L_lambda_1 env_x env_y)))

;; 3.2 Invalid closure forms
(assert-false "reject %make-closure with non-symbol label"
              (verify-closure-ast '(%make-closure 12345 env_x)))

(assert-false "reject %make-closure with non-atomic environment variable"
              (verify-closure-ast '(%make-closure .L_lambda_1 (+ a b))))

;;; -----------------------------------------------------------------------
;;; Group 4: Pass 131 Safepoint / Stackmap Invariant Verification
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Pass 131 Safepoint / Stackmap Verifier ---\n")

;; 4.1 Valid stackmap table
(assert-true "valid %lir-program with 8-byte aligned stackmap entries"
             (verify-lir-safepoint
              '(%lir-program
                (functions)
                (main)
                (stackmaps
                 ((__safepoint_1 16 3)
                  (__safepoint_2 24 0))))))

;; 4.2 Invalid stackmap table
(assert-false "reject missing stackmaps clause"
              (verify-lir-safepoint '(%lir-program (functions) (main))))

(assert-false "reject unaligned frame size (not multiple of 8)"
              (verify-lir-safepoint
               '(%lir-program (functions) (main) (stackmaps ((sp1 12 3))))))

(assert-false "reject negative bitmap"
              (verify-lir-safepoint
               '(%lir-program (functions) (main) (stackmaps ((sp1 16 -1))))))

;;; -----------------------------------------------------------------------
;;; Group 5: Pass 132 Braun SSA Invariant Verification
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Pass 132 Braun SSA Verifier ---\n")

;; 5.1 Valid SSA blocks and jumps
(assert-true "valid %block with parameters and %jump with atomic args"
             (verify-ssa-ast
              '(%block .L_b0 (p0 p1)
                 (%mov %rax p0)
                 (%jump .L_b1 p0 42))))

;; 5.2 Invalid SSA blocks
(assert-false "reject %block with non-list parameters"
              (verify-ssa-ast '(%block .L_b0 not_a_list (%ret))))

(assert-false "reject %jump with non-atomic arguments"
              (verify-ssa-ast '(%jump .L_b1 (+ a b))))

;;; -----------------------------------------------------------------------
;;; Group 6: Unified Verifier Dispatcher & Configuration
;;; -----------------------------------------------------------------------
(display "\n--- Group 6: Unified Verifier Dispatcher ---\n")

(assert-true "dispatch desugar phase"
             (verify-pass-output 'desugar '(let ((x 1)) x)))

(assert-true "dispatch anf phase"
             (verify-pass-output 'anf '(let ((t0 1)) t0)))

(assert-false "dispatch rejection on invalid desugar"
              (verify-pass-output 'desugar '(cond (else 1))))

(disable-verifier!)
(assert-true "disabled verifier bypasses checks"
             (verify-pass-output 'desugar '(cond (else 1))))
(enable-verifier!)

(display "\n=======================================================\n")
(display " All IR Verifier Tests PASSED: ")
(display (car *pass-count*))
(display "/")
(display (car *test-count*))
(newline)
(display "=======================================================\n")
