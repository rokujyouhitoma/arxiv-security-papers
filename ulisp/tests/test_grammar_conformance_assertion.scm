;;; =======================================================================
;;; Test Suite: Nanopass Grammar Conformance Assertion (Issue #880)
;;; Conforms to DSN-33-03 §6.3
;;; =======================================================================

(display "\n=== [Test Suite: Nanopass Grammar Conformance Assertion (Issue #880)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; Group 1: Valid L-Residual-ANF AST Verification
;;; -----------------------------------------------------------------------
(display "--- Group 1: Valid L-Residual-ANF AST Verification ---\n")

(let ((valid-anf-ast-1 '(let-anf ((x 42)) (let-call ((y (+ x 1))) y)))
      (valid-anf-ast-2 '(if cond-var
                            (let-call ((r (foo a))) r)
                            (let-anf ((c 100)) c))))
  (assert-equal "1.1 Clean primitive ANF AST conforms"
                #t
                (verify-residual-anf-conformance valid-anf-ast-1))
  (assert-equal "1.2 Clean conditional ANF AST conforms"
                #t
                (verify-residual-anf-conformance valid-anf-ast-2)))

;;; -----------------------------------------------------------------------
;;; Group 2: Meta-Syntax Violation Detection
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Meta-Syntax Violation Detection ---\n")

(let ((invalid-ast-now '(let-anf ((x (stage-now (+ 1 2)))) x))
      (invalid-ast-later '(let-anf ((x 1)) (stage-later (dynamic-fn x))))
      (invalid-ast-lift '(let-call ((res (foo (stage-lift 99)))) res))
      (invalid-ast-qq '(let-anf ((x (stage-quasiquote `(code ,y)))) x)))
  (assert-equal "2.1 stage-now rejected"
                #f
                (verify-residual-anf-conformance invalid-ast-now))
  (assert-equal "2.2 stage-later rejected"
                #f
                (verify-residual-anf-conformance invalid-ast-later))
  (assert-equal "2.3 stage-lift rejected"
                #f
                (verify-residual-anf-conformance invalid-ast-lift))
  (assert-equal "2.4 stage-quasiquote rejected"
                #f
                (verify-residual-anf-conformance invalid-ast-qq)))

;;; -----------------------------------------------------------------------
;;; Group 3: Deeply Nested Meta-Syntax Search
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Deeply Nested Meta-Syntax Search ---\n")

(let ((nested-ast '(let-anf ((a 1))
                     (let-anf ((b 2))
                       (if (eq? a b)
                           (let-call ((k (bar (nested (deep (stage-lift 77)))))) k)
                           42)))))
  (let ((found (find-stage-meta-syntax nested-ast)))
    (assert-equal "3.1 Deeply nested meta-syntax identified"
                  '(stage-lift 77)
                  found)))

;;; -----------------------------------------------------------------------
;;; Group 4: Pass Manager Integration & Failure Guard
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Pass Manager Integration & Failure Guard ---\n")

(let* ((clean-pass-fn (lambda (ast) '(let-anf ((x 10)) x)))
       (dirty-pass-fn (lambda (ast) '(let-anf ((x (stage-now (+ 1 2)))) x)))
       (clean-pass-desc (make-pass-descriptor 'test-clean 'test-clean 'lower 0 clean-pass-fn 'residual-anf 'L-StagePoly 'L-Residual-ANF '() #t))
       (dirty-pass-desc (make-pass-descriptor 'test-dirty 'test-dirty 'lower 0 dirty-pass-fn 'residual-anf 'L-StagePoly 'L-Residual-ANF '() #t)))
  ;; Clean pass should succeed
  (let ((res (run-single-pass clean-pass-desc '(dummy) #t #f)))
    (assert-equal "4.1 Clean pass execution succeeds"
                  '(let-anf ((x 10)) x)
                  res))
  ;; Dirty pass should trigger error
  (let ((orig-abort (car *compiler-abort-on-error*))
        (orig-suppress (car *compiler-suppress-diagnostics*)))
    (set-car! *compiler-abort-on-error* #f)
    (set-car! *compiler-suppress-diagnostics* #t)
    (let ((res (run-single-pass dirty-pass-desc '(dummy) #t #f)))
      (set-car! *compiler-abort-on-error* orig-abort)
      (set-car! *compiler-suppress-diagnostics* orig-suppress)
      (assert-equal "4.2 Dirty pass triggers error handler and returns irritant"
                    'test-dirty
                    res))))

(display "\n[RESULT] All Nanopass Grammar Conformance Assertion tests PASSED!\n")
