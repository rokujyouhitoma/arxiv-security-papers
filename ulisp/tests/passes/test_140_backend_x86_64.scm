;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 140 (x86-64 Backend Code Generator)
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
(display " Starting Pass 140 (x86-64 Backend) Unit Test Suite") (newline)
(display "=======================================================") (newline)

;; 1. Register formatting
(assert-equal "reg rax" "rax" (reg->str '%rax))
(assert-equal "reg r12" "r12" (reg->str '%r12))
(assert-equal "reg rsp" "rsp" (reg->str '%rsp))
(assert-equal "reg rdi" "rdi" (reg->str '%rdi))
(assert-equal "reg rsi" "rsi" (reg->str '%rsi))

;; 2. Operand formatting
(assert-equal "integer operand" "42" (operand->str 42))
(assert-equal "stack operand" "[rsp - 8]" (operand->str '(%stack -8)))
(assert-equal "stack operand pos" "[rsp + 16]" (operand->str '(%stack 16)))
(assert-equal "reg operand" "rax" (operand->str '(%reg %rax)))

;; 3. Memory operand formatting
(assert-equal "mem op rsp" "[rsp - 8]" (mem-op->str '%rsp -8))
(assert-equal "mem op reg" "[rax + 7]" (mem-op->str '%rax 7))

;; 4. String escaping
(assert-equal "escape normal" "hello" (escape-gas-string "hello"))

(display "=======================================================") (newline)
(display " Pass 140: All ") (display *pass-tests-passed*) (display " tests passed!") (newline)
(display "=======================================================") (newline)
