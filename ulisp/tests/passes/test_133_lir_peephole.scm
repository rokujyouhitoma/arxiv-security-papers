;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 133 (LIR Peephole & DCE)
;;; Conforms to Issue #595 & Nanopass Architecture Quality Standard
;;; =======================================================================

(define *pass-tests-passed* 0)
(define *pass-tests-failed* 0)

(define (assert-equal label expected actual)
  (if (equal? expected actual)
      (begin
        (set! *pass-tests-passed* (+ *pass-tests-passed* 1))
        (display "  [PASS] ") (display label) (newline))
      (begin
        (set! *pass-tests-failed* (+ *pass-tests-failed* 1))
        (display "  [FAIL] ") (display label)
        (display " -> Expected: ") (write expected)
        (display " but got: ") (write actual) (newline)
        (error "Assertion failed:" label))))

(define (assert-true label cond)
  (assert-equal label #t (if cond #t #f)))

(display "=======================================================") (newline)
(display " Starting Pass 133 (LIR Peephole & DCE) Unit Test Suite") (newline)
(display "=======================================================") (newline)

;; Helper to wrap instruction list in a canonical program
(define (make-test-program insts)
  (list '%lir-program
        '(strings ())
        '(stackmaps ())
        '(%lir-functions)
        (list '%lir-main
              '(frame-size 0)
              (cons 'body insts))))

(define (extract-main-body prog)
  (cdr (assq 'body (cdr (assq '%lir-main (cdr prog))))))

;; 1. Redundant self-move elimination: (%mov %rax %rax)
(let* ((in-insts '((%mov %rax %rax) (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "redundant self-move eliminated"
                '((%return))
                out))

;; 2. Round-trip register move elimination: (%mov %rax %rbx) followed by (%mov %rbx %rax)
(let* ((in-insts '((%mov %rax %rbx) (%mov %rbx %rax) (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "round-trip move eliminated"
                '((%mov %rax %rbx) (%return))
                out))

;; 3. Redundant jump to immediate next label: (%jump L1) followed by (%label L1)
(let* ((in-insts '((%jump L1) (%label L1) (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "jump to immediate next label eliminated"
                '((%label L1) (%return))
                out))

;; 4. Identity addition simplification: (%add %rax 0)
(let* ((in-insts '((%add %rax 0) (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "identity add zero eliminated"
                '((%return))
                out))

;; 5. Identity subtraction simplification: (%sub %rcx 0)
(let* ((in-insts '((%sub %rcx 0) (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "identity sub zero eliminated"
                '((%return))
                out))

;; 6. Identity multiplication simplification: (%imul %rdx 1)
(let* ((in-insts '((%imul %rdx 1) (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "identity imul one eliminated"
                '((%return))
                out))

;; 7. Unreachable code elimination after unconditional jump (jump to distant label)
(let* ((in-insts '((%jump L2) (%mov %rax 42) (%add %rax 10) (%label L1) (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  (assert-equal "dead code after jump eliminated"
                '((%jump L2) (%label L1) (%return))
                out))

;; 8. Multi-pass cascading optimization: DCE exposing redundant jump to next label
(let* ((in-insts '((%jump L1) (%mov %rax 42) (%label L1) (%return)))
       (out (optimize-peephole-fixpoint in-insts)))
  ;; Pass 1 drops (%mov %rax 42) -> (%jump L1) (%label L1)
  ;; Pass 2 drops (%jump L1) -> (%label L1) (%return)
  (assert-equal "cascading DCE and jump-elimination"
                '((%label L1) (%return))
                out))

;; 9. Full define-pass integration with L_lir_canonical schema validation
(let* ((orig (make-test-program '((%mov %rax %rax)
                                  (%add %rax 0)
                                  (%jump L1)
                                  (%mov %rbx 99)
                                  (%label L1)
                                  (%return))))
       (opt (lir-peephole-optimize orig))
       (body (extract-main-body opt)))
  (assert-equal "full pass optimizes main body"
                '((%label L1) (%return))
                body)
  (assert-true "optimized program satisfies L_lir_canonical schema"
               (L_lir_canonical? opt)))

;; 10. Verification of peephole optimization on functions
(let* ((fn (list '%lir-function
                 'foo
                 '(params (x))
                 '(frame-size 16)
                 '(body (%mov %rax %rax)
                        (%sub %rcx 0)
                        (%return))))
       (orig (list '%lir-program
                   '(strings ())
                   '(stackmaps ())
                   (list '%lir-functions fn)
                   (list '%lir-main '(frame-size 0) '(body (%return)))))
       (opt (lir-peephole-optimize orig))
       (funcs (cadr (assq '%lir-functions (cdr opt))))
       (fn-body (cdr (assq 'body (cdddr funcs)))))
  (assert-equal "function body optimized with peephole"
                '((%return))
                fn-body)
  (assert-true "function optimization satisfies L_lir_canonical schema"
               (L_lir_canonical? opt)))

(display "=======================================================") (newline)
(display " Pass 133: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
