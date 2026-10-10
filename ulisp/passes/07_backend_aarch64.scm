;;; =======================================================================
;;; ULisp Compiler Pass 7: Native AArch64 (ARM64) Backend Code Generator
;;; Conforms to DSN-33 Architecture Specification & Issue #503
;;; Consumes Pass 6 %lir-program and emits pure GNU AArch64 assembly.
;;; =======================================================================

(define (arm-reg->str reg)
  (case reg
    ((%rax) "x0")
    ((%rdx) "x1")
    ((%rcx) "x2")
    ((%rbx) "x3")
    ((%rdi) "x0")
    ((%rsi) "x1")
    ((%r10) "x10")
    ((%r12) "x19")
    ((%rsp) "sp")
    ((%al)  "w0")
    (else (symbol->string reg))))

(define (arm-w-reg->str reg)
  (case reg
    ((%rax x0) "w0")
    ((%rdx x1) "w1")
    ((%rcx x2) "w2")
    ((%rbx x3) "w3")
    ((%r10 x10) "w10")
    ((%r12 x19) "w19")
    ((%al)  "w0")
    (else
     (let ((s (if (symbol? reg) (symbol->string reg) reg)))
       (if (and (> (string-length s) 1) (char=? (string-ref s 0) #\x))
           (string-append "w" (substring s 1 (string-length s)))
           s)))))

(define (arm-mem-op->str base offset)
  (let ((base-str (arm-reg->str base)))
    (if (symbol? offset)
        (string-append "[" base-str ", " (arm-reg->str offset) "]")
        (string-append "[" base-str ", #" (number->string offset) "]"))))

(define (arm-operand->str opnd)
  (cond
    ((symbol? opnd)
     (arm-reg->str opnd))
    ((integer? opnd)
     (string-append "#" (number->string opnd)))
    ((pair? opnd)
     (let ((tag (car opnd)))
       (case tag
         ((%stack)
          (string-append "[sp, #" (number->string (cadr opnd)) "]"))
         ((%mem)
          (arm-mem-op->str (cadr opnd) (caddr opnd)))
         (else
          (error "Unknown operand in AArch64 backend:" opnd)))))
    (else
     (error "Invalid operand type in AArch64 backend:" opnd))))

(define (arm-condition-code set-inst)
  (cond
    ((string=? set-inst "sete")  "eq")
    ((string=? set-inst "setl")  "lt")
    ((string=? set-inst "setle") "le")
    ((string=? set-inst "setg")  "gt")
    ((string=? set-inst "setge") "ge")
    ((string=? set-inst "setne") "ne")
    (else (error "Unknown set-cc in AArch64 backend:" set-inst))))

(define (emit-arm-boolean-from-set set-inst)
  (let ((cond (arm-condition-code set-inst)))
    (emit (string-append "    cset x0, " cond))
    (emit "    lsl x0, x0, 6")
    (emit "    add x0, x0, 0x2F")))

;;; Emits a single LIR instruction to AArch64 assembly
(define (emit-arm-lir-instruction inst)
  (let ((op (car inst)))
    (case op
      ((%label)
       (let ((lbl (cadr inst)))
         (emit (string-append (if (symbol? lbl) (symbol->string lbl) lbl) ":"))))

      ((%jump)
       (let ((lbl (cadr inst)))
         (if (and (symbol? lbl)
                  (memq lbl '(%rax %rdx %rcx %rbx %r10 %r12 x0 x1 x2 x3 x10 x19)))
             (emit (string-append "    br " (arm-reg->str lbl)))
             (emit (string-append "    b " (if (symbol? lbl) (symbol->string lbl) lbl))))))

      ((%jump-if-false)
       (let ((reg (cadr inst))
             (lbl (caddr inst)))
         (emit (string-append "    cmp " (arm-reg->str reg) ", #0x2F"))
         (emit (string-append "    b.eq " (if (symbol? lbl) (symbol->string lbl) lbl)))))

      ((%jump-if-zero)
       (let ((lbl (cadr inst)))
         (emit (string-append "    b.eq " (if (symbol? lbl) (symbol->string lbl) lbl)))))

      ((%return)
       (emit "    ret"))

      ((%mov)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (cond
           ((integer? src)
            (if (and (>= src -65535) (<= src 65535))
                (emit (string-append "    mov " (arm-reg->str dst) ", #" (number->string src)))
                (emit (string-append "    ldr " (arm-reg->str dst) ", =" (number->string src)))))
           ((pair? src)
            (emit (string-append "    ldr " (arm-reg->str dst) ", " (arm-operand->str src))))
           (else
            (emit (string-append "    mov " (arm-reg->str dst) ", " (arm-reg->str src)))))))

      ((%load)
       (let ((dst (cadr inst))
             (base (caddr inst))
             (offset (cadddr inst)))
         (emit (string-append "    ldr " (arm-reg->str dst) ", " (arm-mem-op->str base offset)))))

      ((%store)
       (let ((base (cadr inst))
             (offset (caddr inst))
             (src (cadddr inst)))
         (emit (string-append "    str " (arm-reg->str src) ", " (arm-mem-op->str base offset)))))

      ((%store-byte)
       (let ((base (cadr inst))
             (offset (caddr inst))
             (src (cadddr inst)))
         (cond
           ((and (number? src) (= src 0))
            (emit (string-append "    strb wzr, " (arm-mem-op->str base offset))))
           ((number? src)
            (emit (string-append "    mov w9, #" (number->string src)))
            (emit (string-append "    strb w9, " (arm-mem-op->str base offset))))
           (else
            (emit (string-append "    strb " (arm-w-reg->str src) ", " (arm-mem-op->str base offset)))))))

      ((%load-byte-zx)
       (let ((dst (cadr inst))
             (base (caddr inst))
             (offset (cadddr inst)))
         (emit (string-append "    ldrb " (arm-w-reg->str dst) ", " (arm-mem-op->str base offset)))))

      ((%add)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (number? src)
             (if (and (>= src 0) (<= src 4095))
                 (emit (string-append "    add " (arm-reg->str dst) ", " (arm-reg->str dst) ", #" (number->string src)))
                 (begin
                   (emit (string-append "    ldr x9, =" (number->string src)))
                   (emit (string-append "    add " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9"))))
             (emit (string-append "    add " (arm-reg->str dst) ", " (arm-reg->str dst) ", " (arm-operand->str src))))))

      ((%sub)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (number? src)
             (if (and (>= src 0) (<= src 4095))
                 (emit (string-append "    sub " (arm-reg->str dst) ", " (arm-reg->str dst) ", #" (number->string src)))
                 (begin
                   (emit (string-append "    ldr x9, =" (number->string src)))
                   (emit (string-append "    sub " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9"))))
             (emit (string-append "    sub " (arm-reg->str dst) ", " (arm-reg->str dst) ", " (arm-operand->str src))))))

      ((%neg)
       (let ((dst (cadr inst)))
         (emit (string-append "    neg " (arm-reg->str dst) ", " (arm-reg->str dst)))))

      ((%imul)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (cond
           ((pair? src)
            (emit (string-append "    ldr x9, " (arm-operand->str src)))
            (emit (string-append "    mul " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9")))
           ((number? src)
            (emit (string-append "    ldr x9, =" (number->string src)))
            (emit (string-append "    mul " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9")))
           (else
            (emit (string-append "    mul " (arm-reg->str dst) ", " (arm-reg->str dst) ", " (arm-reg->str src)))))))

      ((%cqo)
       ;; In AArch64, 64-bit sdiv does not require cqo sign extension; no-op.
       #f)

      ((%idiv)
       (let ((src (cadr inst)))
         (let ((src-str (arm-operand->str src)))
           (emit (string-append "    sdiv x9, x0, " src-str))
           (emit (string-append "    msub x1, x9, " src-str ", x0"))
           (emit "    mov x0, x9"))))

      ((%inc)
       (let ((dst (cadr inst)))
         (emit (string-append "    add " (arm-reg->str dst) ", " (arm-reg->str dst) ", #1"))))

      ((%shl)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    lsl " (arm-reg->str dst) ", " (arm-reg->str dst) ", #" (number->string count)))))

      ((%shr)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    lsr " (arm-reg->str dst) ", " (arm-reg->str dst) ", #" (number->string count)))))

      ((%sar)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    asr " (arm-reg->str dst) ", " (arm-reg->str dst) ", #" (number->string count)))))

      ((%bit-and)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (number? src)
             (begin
               (emit (string-append "    ldr x9, =" (number->string src)))
               (emit (string-append "    and " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9")))
             (emit (string-append "    and " (arm-reg->str dst) ", " (arm-reg->str dst) ", " (arm-reg->str src))))))

      ((%bit-or)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (number? src)
             (begin
               (emit (string-append "    ldr x9, =" (number->string src)))
               (emit (string-append "    orr " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9")))
             (emit (string-append "    orr " (arm-reg->str dst) ", " (arm-reg->str dst) ", " (arm-reg->str src))))))

      ((%bit-xor)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (number? src)
             (begin
               (emit (string-append "    ldr x9, =" (number->string src)))
               (emit (string-append "    eor " (arm-reg->str dst) ", " (arm-reg->str dst) ", x9")))
             (emit (string-append "    eor " (arm-reg->str dst) ", " (arm-reg->str dst) ", " (arm-reg->str src))))))

      ((%cmp)
       (let ((s1 (cadr inst))
             (s2 (caddr inst)))
         (if (number? s2)
             (if (and (>= s2 0) (<= s2 4095))
                 (emit (string-append "    cmp " (arm-reg->str s1) ", #" (number->string s2)))
                 (begin
                   (emit (string-append "    ldr x9, =" (number->string s2)))
                   (emit (string-append "    cmp " (arm-reg->str s1) ", x9"))))
             (emit (string-append "    cmp " (arm-reg->str s1) ", " (arm-operand->str s2))))))

      ((%set-boolean)
       (let ((cc (caddr inst)))
         (emit-arm-boolean-from-set cc)))

      ((%alloc)
       (let ((dst (cadr inst))
             (bytes (caddr inst))
             (tag (cadddr inst)))
         (if (= tag 0)
             (emit (string-append "    mov " (arm-reg->str dst) ", x19"))
             (emit (string-append "    add " (arm-reg->str dst) ", x19, #" (number->string tag))))
         (emit (string-append "    add x19, x19, #" (number->string bytes)))))

      ((%code-ref)
       (let ((dst (cadr inst))
             (lbl (caddr inst)))
         (let ((lbl-str (if (symbol? lbl) (symbol->string lbl) lbl))
               (dst-str (arm-reg->str dst)))
           (emit (string-append "    adrp " dst-str ", " lbl-str))
           (emit (string-append "    add " dst-str ", " dst-str ", :lo12:" lbl-str)))))

      ((%str-ref)
       (let ((dst (cadr inst))
             (lbl (caddr inst)))
         (let ((lbl-str (if (symbol? lbl) (symbol->string lbl) lbl))
               (dst-str (arm-reg->str dst)))
           (emit (string-append "    adrp " dst-str ", " lbl-str))
           (emit (string-append "    add " dst-str ", " dst-str ", :lo12:" lbl-str))
           (emit (string-append "    add " dst-str ", " dst-str ", #3")))))

      ((%c-call)
       (let* ((func (cadr inst))
              (frame-shift (caddr inst))
              (total-shift (+ frame-shift 8)))
         (emit (string-append "    sub sp, sp, #" (number->string total-shift)))
         (emit "    str x30, [sp]")
         (emit (string-append "    bl " (symbol->string func)))
         (emit "    ldr x30, [sp]")
         (emit (string-append "    add sp, sp, #" (number->string total-shift)))))

      ((%call-closure)
       (let* ((frame-shift (cadr inst))
              (total-shift (+ frame-shift 8)))
         (emit (string-append "    sub sp, sp, #" (number->string total-shift)))
         (emit "    str x30, [sp]")
         (emit "    ldr x1, [x10, #-1]")
         (emit "    blr x1")
         (emit "    ldr x30, [sp]")
         (emit (string-append "    add sp, sp, #" (number->string total-shift)))))

      (else
       (error "Unknown LIR opcode in AArch64 backend:" inst)))))

;;; Emits assembly for a single %lir-function
(define (emit-arm-function fn)
  (let* ((label (cadr fn))
         (label-str (if (symbol? label) (symbol->string label) label))
         (body (cdr (assq 'body (cddr fn)))))
    (emit "    .p2align 2")
    (emit (string-append label-str ":"))
    ;; Callee prologue: self closure pointer was in x10
    ;; Store self closure pointer at [sp, #-8]
    (emit "    str x10, [sp, #-8]")
    (for-each emit-arm-lir-instruction body)))

;;; Pass 7 Entrypoint: Takes %lir-program and emits complete GNU AArch64 assembly
(define (emit-aarch64 prog)
  (let* ((funcs-clause (assq '%lir-functions (cdr prog)))
         (funcs (if funcs-clause (cdr funcs-clause) '()))
         (main-clause (assq '%lir-main (cdr prog)))
         (main-body (cdr (assq 'body (cdr main-clause)))))
    (emit "    .text")
    (emit "    .globl scheme_entry")
    (emit "    .type scheme_entry, @function")
    (emit "scheme_entry:")
    (emit "    stp x29, x30, [sp, #-32]!")
    (emit "    mov x29, sp")
    (emit "    str x19, [sp, #16]")
    (emit "    mov x19, x0")          ; x0 contains heap_base from C runtime
    (for-each (lambda (inst)
                (if (not (eq? (car inst) '%return))
                    (emit-arm-lir-instruction inst)))
              main-body)
    (emit "    ldr x19, [sp, #16]")
    (emit "    ldp x29, x30, [sp], #32")
    (emit "    ret")
    ;; Emit all lifted procedure definitions in sequence
    (for-each emit-arm-function funcs)
    ;; Emit all string literals in .rodata section
    (if (not (null? (car *strings*)))
        (begin
          (emit "    .section .rodata")
          (let loop ((ss (reverse (car *strings*))))
            (if (not (null? ss))
                (let ((entry (car ss)))
                  (emit "    .p2align 3")
                  (emit (string-append (car entry) ":"))
                  (emit (string-append "    .asciz \"" (escape-gas-string (cdr entry)) "\""))
                  (loop (cdr ss)))))))
    (emit "    .section .note.GNU-stack,\"\",@progbits")))
