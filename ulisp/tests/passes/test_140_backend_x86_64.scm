;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 140 (x86-64 Backend Code Generator)
;;; Conforms to Issue #572 & Nanopass Architecture Quality Standard
;;; =======================================================================




(test-begin "Pass 140 (x86-64 Backend)")

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
(assert-equal "disp op numeric" "[rsp - 8]" (operand->str '(%disp -8 %rsp)))
(assert-equal "disp op register" "[r12 + rdx]" (operand->str '(%disp %rdx %r12)))

;; 4. String escaping
(assert-equal "escape normal" "hello" (escape-gas-string "hello"))

;; 5. Instruction Selection (LIR -> L_asm_x86)
(let* ((lir-inst '(%mov %rax 42))
       (asm-insts (lower-lir-instruction lir-inst)))
  (assert-equal "lower mov imm" '((mov rax (%imm 42))) asm-insts))

(let* ((lir-inst '(%add %rax (%stack -8)))
       (asm-insts (lower-lir-instruction lir-inst)))
  (assert-equal "lower add stack" '((add rax (%disp -8 rsp))) asm-insts))

(let* ((lir-prog '(%lir-program
                   (strings ())
                   (stackmaps ())
                   (%lir-functions)
                   (%lir-main
                    (frame-size 16)
                    (body (%mov %rax 42)
                          (%add %rax 10)
                          (%return %rax)))))
       (asm-prog (select-instructions-x86 lir-prog)))
  (assert-true "selected asm program satisfies L_asm_x86 schema"
               (L_asm_x86? asm-prog))
  (let ((main-body (cdr (assq 'body (cdr (assq '%asm-main (cdr asm-prog)))))))
    (assert-equal "main body contains selected instructions"
                  '((mov rax (%imm 42))
                    (add rax (%imm 10))
                    (%raw-asm "    lea r11, [rip + ulisp_final_r12]")
                    (%raw-asm "    mov [r11], r12")
                    (add rsp 8)
                    (pop r12)
                    (ret))
                  main-body)))

;; 6. Symbol table interning and lookup
(intern-symbol 'car)
(intern-symbol 'error-object)
(let ((syms (get-all-symbols)))
  (assert-true "get-all-symbols returns a list" (list? syms))
  (assert-true "get-all-symbols contains car" (pair? (assq 'car syms)))
  (assert-true "get-all-symbols contains error-object" (pair? (assq 'error-object syms))))

(test-end "Pass 140 (x86-64 Backend)")
