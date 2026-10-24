;;; =======================================================================
;;; ULisp Compiler: Backend Architecture Intermediate Languages
;;; Conforms to DSN-33 Architecture Specification & Issue #596
;;; =======================================================================
;;; Formal intermediate language definition for Target Machine Assembly (L_asm_x86)
;;; using Nanopass DSL (define-language). Serves as the declarative contract
;;; between instruction selection (LIR -> L_asm) and code emission (L_asm -> text).
;;; =======================================================================

(define-language L_asm_x86
  (entry Program)
  (terminals
    (symbol (lbl var op cc align))
    (integer (n disp imm scale bitmap frame_size bytes))
    (string (str)))
  (Register (reg)
    rax rbx rcx rdx rsi rdi rbp rsp
    r8  r9  r10 r11 r12 r13 r14 r15 al
    (%reg var))
  (Memory (mem)
    (%disp disp reg)
    (%index reg reg scale disp)
    (%mem reg disp))
  (Operand (opnd)
    reg
    mem
    (%imm imm)
    imm
    lbl)
  (Inst (inst)
    (%label lbl)
    (%p2align align)
    (%align align)
    (%raw-asm str)
    (mov opnd1 opnd2)
    (movzx opnd1 opnd2)
    (lea opnd1 opnd2)
    (add opnd1 opnd2)
    (sub opnd1 opnd2)
    (imul opnd1 opnd2)
    (and opnd1 opnd2)
    (or opnd1 opnd2)
    (xor opnd1 opnd2)
    (shl opnd1 opnd2)
    (shr opnd1 opnd2)
    (sar opnd1 opnd2)
    (neg opnd)
    (not opnd)
    (cmp opnd1 opnd2)
    (test opnd1 opnd2)
    (set cc opnd)
    (jmp lbl)
    (jcc cc lbl)
    (call opnd)
    (ret)
    (push opnd)
    (pop opnd)
    (cqo)
    (idiv opnd)
    (inc opnd)
    (syscall)
    (cld)
    (rep-movsb))
  (StringEntry (se)
    (lbl str))
  (SafepointEntry (sm)
    (lbl frame_size bitmap))
  (FunctionDecl (f)
    (%asm-function lbl (frame-size n) (body inst ...)))
  (MainDecl (m)
    (%asm-main (frame-size n) (body inst ...)))
  (Program (p)
    (%asm-program (strings (se ...)) (stackmaps (sm ...)) (%asm-functions f ...) m)))
