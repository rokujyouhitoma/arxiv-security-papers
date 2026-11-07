;;; =======================================================================
;;; ULisp Compiler: Low-Level IR (LIR) Language Specifications
;;; (L_lir_raw -> L_lir_canonical)
;;; Conforms to DSN-33, DSN-33-01 Architecture Specification & Issues #593, #753
;;; =======================================================================
;;; Formal intermediate language definitions for Raw LIR and Canonical LIR
;;; using Nanopass DSL (define-language):
;;; - L_lir_raw:       Initial LIR emitted by Pass 130 before branch fusion and
;;;                    peephole normalization.
;;; - L_lir_canonical: Canonical LIR after Pass 128 (branch fusion) and Pass 133
;;;                    (peephole optimization / dead code elimination), serving
;;;                    as the contract for low-level code generation backends.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. L_lir_raw: Raw Low-Level Intermediate Representation
;;; -----------------------------------------------------------------------
(define-language L_lir_raw
  (entry Program)
  (terminals
    (symbol (x lbl var cond_op sp_lbl))
    (integer (n offset shift frame_size bytes tag si cnt bitmap line col))
    (string (str fn_name)))
  (Register (reg)
    %rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp
    %r8  %r9  %r10 %r11 %r12 %r13 %r14 %r15 %al
    (%reg x))
  (StackSlot (stk)
    (%stack offset))
  (MemRef (mem)
    (%mem reg offset)
    (%mem reg reg))
  (LValue (lval)
    reg
    stk
    mem)
  (Operand (opnd)
    lval
    n
    lbl)
  (Inst (inst)
    ;; Pseudo / Raw-Only Instructions
    (%nop)

    ;; Debug & Source Location
    (%loc n line col)

    ;; Control Flow
    (%label lbl)
    (%block lbl (x ...) inst ...)
    (%jump lbl)
    (%jump lbl (opnd ...))
    (%jump-if-false reg lbl)
    (%jump-if-false reg lbl (opnd ...))
    (%jump-if reg lbl1 (opnd1 ...) lbl2 (opnd2 ...))
    (%jump-cond cond_op lbl)
    (%jump-cond str lbl)
    (%jump-if-zero lbl)
    (%direct-jump lbl)
    (%return)
    (%return opnd)

    ;; Calls & ABI
    (%c-call fn_name shift)
    (%call-closure shift)
    (%call-closure shift sp_lbl)
    (%call-closure shift str)
    (%direct-call lbl shift)
    (%direct-call lbl shift sp_lbl)
    (%direct-call lbl shift str)
    (%dispatch-consumer si1 si2 shift)

    ;; Memory & Data Transfer
    (%mov lval opnd)
    (%load reg1 reg2 offset)
    (%store reg1 offset opnd)
    (%load-byte-zx reg1 reg2 offset)
    (%store-byte reg1 offset opnd)
    (%push reg)
    (%pop reg)
    (%code-ref reg lbl)
    (%str-ref reg lbl)
    (%global-ref reg var)
    (%global-set! var reg)

    ;; Arithmetic / Logic / Primitives
    (%add opnd1 opnd2)
    (%raw-add opnd1 opnd2)
    (%sub opnd1 opnd2)
    (%raw-sub opnd1 opnd2)
    (%imul opnd1 opnd2)
    (%raw-mul opnd1 opnd2)
    (%neg opnd)
    (%inc opnd)
    (%cqo)
    (%idiv opnd)
    (%shl opnd shift)
    (%shr opnd shift)
    (%sar opnd shift)
    (%bit-and opnd1 opnd2)
    (%bit-or opnd1 opnd2)
    (%bit-xor opnd1 opnd2)
    (%cmp opnd1 opnd2)
    (%raw-cmp opnd1 opnd2)
    (%set-boolean opnd cond_op)
    (%box-fixnum opnd1 opnd2)
    (%unbox-fixnum opnd1 opnd2)
    (%syscall)
    (%syscall si)
    (%memory-fence)
    (%atomic-cas! reg1 reg2 reg3)

    ;; Runtime / GC / CC / Values
    (%alloc opnd bytes tag)
    (%alloc opnd bytes tag si)
    (%alloc-stack opnd offset tag)
    (%capture-cc lbl si)
    (%push-handler lbl si1 si2)
    (%pop-handler si)
    (%raise)
    (%set-values-count cnt)
    (%store-values-buf si cnt))
  (StringEntry (se)
    (lbl str)
    (str1 str2))
  (SafepointEntry (sm)
    (lbl frame_size bitmap)
    (str frame_size bitmap))
  (FunctionDecl (f)
    (%lir-function lbl (params (x ...)) (frame-size frame_size) (body inst ...)))
  (MainDecl (m)
    (%lir-main (frame-size frame_size) (body inst ...)))
  (Program (p)
    (%lir-program (strings (se ...)) (stackmaps (sm ...)) (%lir-functions f ...) m)))

;;; -----------------------------------------------------------------------
;;; 2. L_lir_canonical: Canonical LIR (Post-Branch Fusion & Peephole)
;;; -----------------------------------------------------------------------
(define-language L_lir_canonical
  (extends L_lir_raw)
  (entry Program)
  (Inst (inst)
    (- (%nop))))
