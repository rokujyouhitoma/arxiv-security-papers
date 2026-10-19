;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 160 (Portable C Backend)
;;; Conforms to Issue #572 & Nanopass Architecture Quality Standard
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
(display " Starting Pass 160 (Portable C Backend) Unit Test Suite") (newline)
(display "=======================================================") (newline)

;; 1. Label sanitization
(assert-equal "c sanitize leading dot" "ulisp_L_else_1" (c-sanitize-label ".L_else_1"))
(assert-equal "c sanitize normal" "scheme_entry" (c-sanitize-label "scheme_entry"))

;; 2. Register formatting
(assert-equal "c reg rax" "reg_rax" (c-reg->str '%rax))
(assert-equal "c reg r12" "reg_r12" (c-reg->str '%r12))
(assert-equal "c reg rsp" "reg_rsp" (c-reg->str '%rsp))

;; 3. Memory reference formatting
(assert-equal "c mem rsp" "(*(uint64_t *)(reg_rsp + (-8)))" (c-mem-ref '%rsp -8))
(assert-equal "c mem reg" "(*(uint64_t *)(((char *)(uintptr_t)reg_rax) + (7)))" (c-mem-ref '%rax 7))
(assert-equal "c mem byte" "(*(uint8_t *)(((char *)(uintptr_t)reg_rdx) + (reg_rax)))" (c-mem-byte-ref '%rdx '%rax))

;; 4. Operand formatting
(assert-equal "c operand int" "42" (c-operand->str 42))
(assert-equal "c operand stack" "(*(uint64_t *)(reg_rsp + (-8)))" (c-operand->str '(%stack -8)))

;; 5. Target directive predicate
(assert-true "c target directive matches" (c-target-directive? '(!target c)))
(assert-true "c target directive rejects x86" (not (c-target-directive? '(!target x86_64))))
(assert-true "c target directive rejects other" (not (c-target-directive? '(+ 1 2))))

;; 6. End-to-end pipeline to LIR verification for C backend
(let* ((core-ast (desugar-all '(let ((x 10)) (+ x 32))))
       (opt-ast (cp0-optimize core-ast))
       (anf-ast (anf-all opt-ast))
       (clos-ast (closure-convert anf-ast))
       (lir (generate-lir clos-ast)))
  (assert-true "lir generated for c backend" (pair? lir))
  (assert-equal "lir tag" '%lir-program (car lir)))

(display "=======================================================") (newline)
(display " Pass 160: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
