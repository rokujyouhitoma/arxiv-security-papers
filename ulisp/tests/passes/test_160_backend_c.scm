;;; =======================================================================
;;; Unit Test Suite: ULisp Pass 160 (Portable C Backend)
;;; Conforms to Issue #572 & Nanopass Architecture Quality Standard
;;; =======================================================================




(test-begin "Pass 160 (Portable C Backend)")

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
(assert-equal "c operand int" "42LL" (c-operand->str 42))
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

;; 7. Issue #935: Variable register shift count C emission with unsigned &63 mask
(let ((captured '()))
  (set-emit-line-sink! (lambda (line) (set! captured (cons line captured))))
  (emit-c-instruction '(%shl %rax %rcx))
  (emit-c-instruction '(%shr %rax %rcx))
  (emit-c-instruction '(%shr %rbx %rax %rcx))
  (emit-c-instruction '(%sar %rax %rcx))
  (set-emit-line-sink! #f)
  (assert-equal "emit-c-instruction emits masked uint64_t shifts for %rcx"
                '("    reg_rax = ((uint64_t)reg_rax) << ((uint64_t)reg_rcx & 63);"
                  "    reg_rax = ((uint64_t)reg_rax) >> ((uint64_t)reg_rcx & 63);"
                  "    reg_rbx = ((uint64_t)reg_rax) >> ((uint64_t)reg_rcx & 63);"
                  "    reg_rax = (uint64_t)(((int64_t)reg_rax) >> ((uint64_t)reg_rcx & 63));")
                (reverse captured)))

(test-end "Pass 160 (Portable C Backend)")
