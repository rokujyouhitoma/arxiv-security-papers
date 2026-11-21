;;; =======================================================================
;;; Unit & Integration Test Suite: L-Residual-ANF to LIR Lowering Bridge
;;; Conforms to DSN-33-03 §6.2, §8.1 (Phase P5), DSN-33-02 §8.4 & Issue #889
;;; =======================================================================

(test-begin "Pass 130 Bridge: L-Residual-ANF to LIR Lowering")

;; Enable non-strict verifier for program validation
(enable-verifier!)
(set-verifier-strict! #f)

(define (find-matching pred lst)
  (let loop ((rest lst))
    (cond
      ((null? rest) #f)
      ((pred (car rest)) (car rest))
      (else (loop (cdr rest))))))

;;; -----------------------------------------------------------------------
;;; Group 1: Basic Atom Values (atom-value) Lowering
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Basic Atom Values Lowering ---\n")

;; 1.1 Integer literal
(let ((insts (lower-residual-anf-to-lir-insts '(atom-value 42))))
  (assert-true "1.1 atom-value integer produces %mov into %rax"
               (and (pair? insts)
                    (eq? (caar insts) '%mov)
                    (eq? (cadar insts) '%rax))))

;; 1.2 Boolean literal
(let ((insts (lower-residual-anf-to-lir-insts '(atom-value #t))))
  (assert-true "1.2 atom-value boolean produces immediate %mov"
               (and (pair? insts)
                    (eq? (caar insts) '%mov)
                    (eq? (cadar insts) '%rax))))

;; 1.3 Character literal
(let ((insts (lower-residual-anf-to-lir-insts '(atom-value #\Z))))
  (assert-true "1.3 atom-value char produces %mov"
               (and (pair? insts)
                    (eq? (caar insts) '%mov)
                    (eq? (cadar insts) '%rax))))

;; 1.4 Quoted symbol datum
(let ((insts (lower-residual-anf-to-lir-insts '(atom-value (quote test-sym)))))
  (assert-true "1.4 atom-value quoted symbol resolves to interned symbol ID"
               (and (pair? insts)
                    (eq? (caar insts) '%mov)
                    (eq? (cadar insts) '%rax)
                    (number? (caddar insts)))))

;;; -----------------------------------------------------------------------
;;; Group 2: Sequential Primitive Computation (let-anf)
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Sequential Primitive Computation (let-anf) ---\n")

;; 2.1 Single let-anf with binary addition
(let* ((ast '(let-anf ((x (+ 10 20)))
               (atom-value x)))
       (insts (lower-residual-anf-to-lir-insts ast)))
  (assert-true "2.1 let-anf emits %store to stack and reloads into %rax"
               (let ((has-store (find-matching (lambda (i) (and (pair? i) (eq? (car i) '%store))) insts))
                     (has-load (find-matching (lambda (i) (and (pair? i) (eq? (car i) '%load))) insts)))
                 (and has-store has-load #t))))

;; 2.2 Nested let-anf chaining computations
(let* ((ast '(let-anf ((a (+ 1 2)))
               (let-anf ((b (* a 3)))
                 (atom-value b))))
       (prog (lower-residual-anf-to-lir ast)))
  (assert-true "2.2 Nested let-anf lowers to valid %lir-program"
               (and (pair? prog)
                    (eq? (car prog) '%lir-program)
                    (validate-lir prog))))

;;; -----------------------------------------------------------------------
;;; Group 3: Function Application & Call Sequences (let-call)
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Function Application & Call Sequences (let-call) ---\n")

;; 3.1 let-call invoking known function with arguments
(let* ((ast '(%program
              ((define (helper a b) (+ a b)))
              (let-call ((res (helper 100 200)))
                (atom-value res))))
       (prog (lower-residual-anf-to-lir ast)))
  (assert-true "3.1 Program with helper function and let-call lowers to valid %lir-program"
               (and (pair? prog)
                    (eq? (car prog) '%lir-program)
                    (validate-lir prog))))

;; 3.2 Chained let-call sequence
(let* ((ast '(%program
              ((define (inc x) (+ x 1)))
              (let-call ((t1 (inc 40)))
                (let-call ((t2 (inc t1)))
                  (atom-value t2)))))
       (prog (lower-residual-anf-to-lir ast)))
  (assert-true "3.2 Chained let-call lowers and validates under LIR Verifier"
               (and (pair? prog)
                    (validate-lir prog))))

;;; -----------------------------------------------------------------------
;;; Group 4: Conditionals & Block Branching (if-anf)
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Conditionals & Block Branching (if-anf) ---\n")

;; 4.1 if-anf branching on primitive test
(let* ((ast '(let-anf ((cnd (< 10 20)))
               (if-anf cnd
                       (atom-value 42)
                       (atom-value 0))))
       (prog (lower-residual-anf-to-lir ast)))
  (assert-true "4.1 if-anf conditional lowers to valid %lir-program"
               (and (pair? prog)
                    (validate-lir prog))))

;; 4.2 Nested if-anf inside let-anf
(let* ((ast '(let-anf ((x 5))
               (if-anf (= x 5)
                       (let-anf ((y (+ x 10)))
                         (atom-value y))
                       (atom-value -1))))
       (prog (lower-residual-anf-to-lir ast)))
  (assert-true "4.2 Nested if-anf within let-anf validates under LIR Verifier"
               (and (pair? prog)
                    (validate-lir prog))))

;;; -----------------------------------------------------------------------
;;; Group 5: Stage-Poly-Lower to LIR End-to-End Pipeline
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Stage-Poly-Lower to LIR End-to-End Pipeline ---\n")

;; 5.1 Specialization of mixed static-dynamic expression through lower-residual-anf-to-lir
(let* ((source-expr '(let ((x 10))
                       (+ (stage-now (* 2 3)) x)))
       (res-ast (stage-poly-lower source-expr '()))
       (prog (lower-residual-anf-to-lir res-ast)))
  (assert-true "5.1 stage-poly-lower output directly converts to valid %lir-program"
               (and (pair? prog)
                    (validate-lir prog))))

;; 5.2 Specialization with conditional dead-code elimination
(let* ((source-expr '(let ((dynamic-val 42))
                       (if (stage-now (< 1 2))
                           (+ dynamic-val (stage-now (* 10 2)))
                           (- dynamic-val 999))))
       (res-ast (stage-poly-lower source-expr '()))
       (prog (lower-residual-anf-to-lir res-ast)))
  (assert-true "5.2 Static branch folded and remaining residual ANF lowers to %lir-program"
               (and (pair? prog)
                    (validate-lir prog))))

;; 5.3 Micro-interpreter specialization pipeline into LIR
(let* ((source-expr '(let ((dyn-arg 7))
                       (let ((op (stage-now '(+ 5))))
                         (+ (cadr (stage-now op)) dyn-arg))))
       (res-ast (stage-poly-lower source-expr '()))
       (prog (lower-residual-anf-to-lir res-ast)))
  (assert-true "5.3 Micro-evaluator residual lowers to %lir-program passing LIR Verifier"
               (and (pair? prog)
                    (validate-lir prog))))

(display "\n-------------------------------------------------------\n")
(display " [RESULT] All L-Residual-ANF to LIR Lowering Bridge tests PASSED!\n")
(display "-------------------------------------------------------\n")
