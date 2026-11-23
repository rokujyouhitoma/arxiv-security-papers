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

;; 7. Issue #933: Intraprocedural %label / %block .p2align 4 suppression in c-tu mode
(let ((saved-mode (car *backend-gc-mode*)))
  (set-car! *backend-gc-mode* 'managed)
  (assert-equal "managed mode %label emits %p2align 4"
                '((%p2align 4) (%label .L_test_managed))
                (lower-lir-instruction '(%label .L_test_managed)))
  (set-car! *backend-gc-mode* 'c-tu)
  (assert-equal "c-tu mode %label omits %p2align 4"
                '((%label .L_test_ctu))
                (lower-lir-instruction '(%label .L_test_ctu)))
  (assert-equal "c-tu mode %block omits %p2align 4"
                '((%label .L_blk_ctu) (mov rax (%imm 7)))
                (lower-lir-instruction '(%block .L_blk_ctu () (%mov %rax 7))))
  (set-car! *backend-gc-mode* saved-mode))

;; 8. Issue #935: Variable %rcx register shift lowering & cl emission
(let ((captured '()))
  (assert-equal "%shl %rax %rcx lowers to (shl rax cl)"
                '((shl rax cl))
                (lower-lir-instruction '(%shl %rax %rcx)))
  (assert-equal "%shr %rax %rcx lowers to (shr rax cl)"
                '((shr rax cl))
                (lower-lir-instruction '(%shr %rax %rcx)))
  (assert-equal "%shr %rbx %rax %rcx lowers to mov+shr cl"
                '((mov rbx rax) (shr rbx cl))
                (lower-lir-instruction '(%shr %rbx %rax %rcx)))
  (assert-equal "%sar %rax %rcx lowers to (sar rax cl)"
                '((sar rax cl))
                (lower-lir-instruction '(%sar %rax %rcx)))
  (let* ((prog (list '%lir-program
                     '(strings ())
                     '(stackmaps ())
                     '(%lir-functions)
                     (list '%lir-main
                           '(frame-size 16)
                           '(body (%mov %rax 1)
                                  (%mov %rcx 3)
                                  (%shl %rax %rcx)
                                  (%shr %rax %rcx)
                                  (%sar %rax %rcx)
                                  (%return %rax)))))
         (asm-prog (select-instructions-x86 prog)))
    (assert-true "program with %rcx shifts satisfies L_asm_x86?"
                 (L_asm_x86? asm-prog))
    (set-emit-line-sink! (lambda (line) (set! captured (cons line captured))))
    (emit-x86-asm-inst '(shl rax cl))
    (emit-x86-asm-inst '(shr rax cl))
    (emit-x86-asm-inst '(sar rax cl))
    (set-emit-line-sink! #f)
    (assert-equal "emit-x86-asm-inst emits Intel 'cl' operand"
                  '("    shl rax, cl" "    shr rax, cl" "    sar rax, cl")
                  (reverse captured))))

;; 9. Issue #936 WP1: c-tu omits Managed GC xor r10,r10 on %direct-call while managed keeps it
(let ((saved-mode (car *backend-gc-mode*)))
  (set-car! *backend-gc-mode* 'managed)
  (let ((mg-insts (lower-lir-instruction '(%direct-call helper_fn 8))))
    (assert-true "managed mode %direct-call keeps xor r10, r10"
                 (and (member '(%raw-asm "    xor r10, r10") mg-insts) #t)))
  (set-car! *backend-gc-mode* 'c-tu)
  (let ((ctu-insts (lower-lir-instruction '(%direct-call helper_fn 8))))
    (assert-false "c-tu mode %direct-call omits xor r10, r10"
                  (member '(%raw-asm "    xor r10, r10") ctu-insts))
    (assert-true "c-tu unhoisted %direct-call still calls target"
                 (and (member '(%raw-asm "    call helper_fn") ctu-insts) #t)))
  (set-car! *backend-gc-mode* saved-mode))

;; 10. Issue #936 WP2: c-tu stack frame hoisting, +F shift, lea [rsp+F], opt-outs & stack-arg deltas
(let ((saved-mode (car *backend-gc-mode*)))
  (set-car! *backend-gc-mode* 'c-tu)
  (let* ((hoist-fn
          '(%lir-function hoisted_fn
            (params (a))
            (frame-size 32)
            (body (%store %rsp -16 %rdi)
                  (%direct-call ext1 24)
                  (%load %rdx %rsp -16)
                  (%load-typed i32 %rcx %rsp 8)
                  (%mov %rsi %rsp)
                  (%add %rsi -16)
                  (%c-call "ext2" 40)
                  (%return))))
         (leaf-fn
          '(%lir-function leaf_fn
            (params ())
            (frame-size 16)
            (body (%mov %rax 7)
                  (%return))))
         (asm-fn
          '(%lir-function inline_asm_fn
            (params ())
            (frame-size 16)
            (body (%inline-asm "nop" "" () () ())
                  (%direct-call ext1 24)
                  (%return))))
         (tail-fn
          '(%lir-function tail_jump_fn
            (params ())
            (frame-size 16)
            (body (%direct-call ext1 24)
                  (%direct-jump other_fn))))
         (multi-fn
          '(%lir-function multi_stack_fn
            (params ())
            (frame-size 48)
            (body (%mov %rax 99)
                  (%store %rsp -40 %rax)
                  (%c-call "many_args" 40)
                  (%c-call "normal_call" 72)
                  (%return))))
         (lir-prog (list '%lir-program
                         '(strings ())
                         '(stackmaps ())
                         (list '%lir-functions hoist-fn leaf-fn asm-fn tail-fn multi-fn)
                         '(%lir-main (frame-size 16) (body (%return %rax)))))
         (asm-prog (select-instructions-x86 lir-prog))
         (opt-prog (optimize-x86-peephole asm-prog))
         (get-fn-body
          (lambda (prog name)
            (let loop ((fs (cdr (assq '%asm-functions (cdr prog)))))
              (cond
                ((null? fs) '())
                ((eq? (cadar fs) name) (cdr (assq 'body (cddr (car fs)))))
                (else (loop (cdr fs)))))))
         (hb (get-fn-body asm-prog 'hoisted_fn))
         (hb-opt (get-fn-body opt-prog 'hoisted_fn))
         (lb (get-fn-body asm-prog 'leaf_fn))
         (ab (get-fn-body asm-prog 'inline_asm_fn))
         (tb (get-fn-body asm-prog 'tail_jump_fn))
         (mb (get-fn-body asm-prog 'multi_stack_fn)))
    (assert-true "hoisted c-tu program satisfies L_asm_x86?" (L_asm_x86? asm-prog))
    (assert-true "peepholed hoisted c-tu program satisfies L_asm_x86?" (L_asm_x86? opt-prog))
    (assert-true "hoisted_fn emits prologue (sub rsp (%imm 40))"
                 (and (member '(sub rsp (%imm 40)) hb) #t))
    (assert-true "hoisted_fn emits epilogue (add rsp (%imm 40)) before ret"
                 (let loop ((xs hb))
                   (cond
                     ((null? xs) #f)
                     ((and (equal? (car xs) '(add rsp (%imm 40)))
                           (pair? (cdr xs))
                           (equal? (cadr xs) '(ret)))
                      #t)
                     (else (loop (cdr xs))))))
    (assert-false "hoisted_fn omits per-call sub rsp, 24"
                  (member '(%raw-asm "    sub rsp, 24") hb))
    (assert-false "hoisted_fn omits per-call add rsp, 40"
                  (member '(%raw-asm "    add rsp, 40") hb))
    (assert-true "hoisted_fn shifts %store -16 by +40 to disp 24"
                 (and (member '(mov (%disp 24 rsp) rdi) hb) #t))
    (assert-true "hoisted_fn shifts %load -16 by +40 to disp 24"
                 (and (member '(mov rdx (%disp 24 rsp)) hb) #t))
    (assert-true "hoisted_fn shifts %load-typed +8 by +40 to [rsp + 48]"
                 (and (member '(%raw-asm "    movsxd rcx, dword ptr [rsp + 48]") hb) #t))
    (assert-true "hoisted_fn lowers %mov %rsi %rsp to (lea rsi (%disp 40 rsp))"
                 (and (member '(lea rsi (%disp 40 rsp)) hb) #t))
    (assert-true "peephole folds (lea rsi (%disp 40 rsp)) + (add rsi (%imm -16)) to disp 24"
                 (and (member '(lea rsi (%disp 24 rsp)) hb-opt) #t))
    (assert-false "leaf_fn with 0 calls does not hoist sub rsp"
                  (member '(sub rsp (%imm 8)) lb))
    (assert-true "inline_asm_fn opts out and retains per-call sub rsp, 24"
                 (and (member '(%raw-asm "    sub rsp, 24") ab) #t))
    (assert-true "tail_jump_fn opts out and retains per-call sub rsp, 24"
                 (and (member '(%raw-asm "    sub rsp, 24") tb) #t))
    (assert-true "multi_stack_fn hoists F=72 and emits +32/-32 delta ONLY around shift=40 stack-arg call"
                 (and (member '(sub rsp (%imm 72)) mb)
                      (member '(mov (%disp 32 rsp) rax) mb)
                      (member '(add rsp (%imm 32)) mb)
                      (member '(sub rsp (%imm 32)) mb)
                      (not (member '(%raw-asm "    sub rsp, 72") mb))
                      (not (member '(%raw-asm "    add rsp, 72") mb)))))
  (set-car! *backend-gc-mode* saved-mode))

(test-end "Pass 140 (x86-64 Backend)")
