;;; =======================================================================
;;; ULisp Compiler Pass 7: Native x86-64 Backend Code Generator
;;; Conforms to DSN-33 Architecture Specification & ulisp/docs/lir_specification.md
;;; Consumes Pass 6 %lir-program and emits pure GNU x86-64 Intel-syntax assembly.
;;; =======================================================================

(define (emit line)
  (display line)
  (newline))

(define (emit-boolean-from-set set-inst)
  (emit (string-append "    " set-inst " al"))
  (emit "    movzx eax, al")
  (emit "    shl rax, 6")
  (emit "    add rax, 0x2F"))

(define (reg->str reg)
  (case reg
    ((%rax) "rax")
    ((%rdx) "rdx")
    ((%rcx) "rcx")
    ((%r10) "r10")
    ((%rdi) "rdi")
    ((%r12) "r12")
    ((%rsp) "rsp")
    ((%al)  "al")
    (else (symbol->string reg))))

(define (mem-op->str base offset)
  (let ((base-str (reg->str base)))
    (if (symbol? offset)
        (string-append "[" base-str " + " (reg->str offset) "]")
        (string-append "[" base-str " " (offset->string offset) "]"))))

(define (operand->str opnd)
  (cond
    ((symbol? opnd)
     (reg->str opnd))
    ((integer? opnd)
     (number->string opnd))
    ((pair? opnd)
     (let ((tag (car opnd)))
       (case tag
         ((%stack)
          (string-append "[rsp " (offset->string (cadr opnd)) "]"))
         ((%mem)
          (mem-op->str (cadr opnd) (caddr opnd)))
         (else
          (error "Unknown operand in x86-64 backend:" opnd)))))
    (else
     (error "Invalid operand type in x86-64 backend:" opnd))))

;;; Emits a single LIR instruction to x86-64 assembly
(define (emit-lir-instruction inst)
  (let ((op (car inst)))
    (case op
      ((%label)
       (let ((lbl (cadr inst)))
         (emit (string-append (if (symbol? lbl) (symbol->string lbl) lbl) ":"))))

      ((%jump)
       (let ((lbl (cadr inst)))
         (emit (string-append "    jmp " (reg->str lbl)))))

      ((%jump-if-false)
       (let ((reg (cadr inst))
             (lbl (caddr inst)))
         (emit (string-append "    cmp " (reg->str reg) ", 0x2F"))
         (emit (string-append "    je " (if (symbol? lbl) (symbol->string lbl) lbl)))))

      ((%jump-if-zero)
       (let ((lbl (cadr inst)))
         (emit (string-append "    je " (if (symbol? lbl) (symbol->string lbl) lbl)))))

      ((%return)
       (emit "    ret"))

      ((%mov)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    mov " (operand->str dst) ", " (operand->str src)))))

      ((%load)
       (let ((dst (cadr inst))
             (base (caddr inst))
             (offset (cadddr inst)))
         (emit (string-append "    mov " (reg->str dst) ", " (mem-op->str base offset)))))

      ((%store)
       (let ((base (cadr inst))
             (offset (caddr inst))
             (src (cadddr inst)))
         (emit (string-append "    mov " (mem-op->str base offset) ", " (operand->str src)))))

      ((%store-byte)
       (let ((base (cadr inst))
             (offset (caddr inst))
             (src (cadddr inst)))
         (let ((src-str (if (number? src) (number->string src) (reg->str src))))
           (emit (string-append "    mov byte ptr " (mem-op->str base offset) ", " src-str)))))

      ((%load-byte-zx)
       (let ((dst (cadr inst))
             (base (caddr inst))
             (offset (cadddr inst)))
         (emit (string-append "    movzx " (reg->str dst) ", byte ptr " (mem-op->str base offset)))))

      ((%add)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    add " (operand->str dst) ", " (operand->str src)))))

      ((%sub)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    sub " (operand->str dst) ", " (operand->str src)))))

      ((%neg)
       (let ((dst (cadr inst)))
         (emit (string-append "    neg " (operand->str dst)))))

      ((%imul)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    imul " (operand->str dst) ", " (operand->str src)))))

      ((%cqo)
       (emit "    cqo"))

      ((%idiv)
       (let ((src (cadr inst)))
         (emit (string-append "    idiv " (operand->str src)))))

      ((%inc)
       (let ((dst (cadr inst)))
         (emit (string-append "    inc " (operand->str dst)))))

      ((%shl)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    shl " (operand->str dst) ", " (number->string count)))))

      ((%shr)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    shr " (operand->str dst) ", " (number->string count)))))

      ((%sar)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (emit (string-append "    sar " (operand->str dst) ", " (number->string count)))))

      ((%bit-and)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    and " (operand->str dst) ", " (operand->str src)))))

      ((%bit-or)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    or " (operand->str dst) ", " (operand->str src)))))

      ((%bit-xor)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    xor " (operand->str dst) ", " (operand->str src)))))

      ((%cmp)
       (let ((s1 (cadr inst))
             (s2 (caddr inst)))
         (emit (string-append "    cmp " (operand->str s1) ", " (operand->str s2)))))

      ((%set-boolean)
       (let ((cc (caddr inst)))
         (emit-boolean-from-set cc)))

      ((%alloc)
       (let ((dst (cadr inst))
             (bytes (caddr inst))
             (tag (cadddr inst)))
         (emit (string-append "    lea " (operand->str dst) ", [r12 + " (number->string tag) "]"))
         (emit (string-append "    add r12, " (number->string bytes)))))

      ((%code-ref)
       (let ((dst (cadr inst))
             (lbl (caddr inst)))
         (let ((lbl-str (if (symbol? lbl) (symbol->string lbl) lbl)))
           (emit (string-append "    lea " (operand->str dst) ", [rip + " lbl-str "]")))))

      ((%str-ref)
       (let ((dst (cadr inst))
             (lbl (caddr inst)))
         (let ((lbl-str (if (symbol? lbl) (symbol->string lbl) lbl)))
           (emit (string-append "    lea " (operand->str dst) ", [rip + " lbl-str "]"))
           (emit (string-append "    add " (operand->str dst) ", 3")))))

      ((%c-call)
       (let ((func (cadr inst))
             (frame-shift (caddr inst)))
         (emit (string-append "    sub rsp, " (number->string frame-shift)))
         (emit (string-append "    call " (symbol->string func)))
         (emit (string-append "    add rsp, " (number->string frame-shift)))))

      ((%call-closure)
       (let ((frame-shift (cadr inst)))
         (if (> frame-shift 0)
             (emit (string-append "    sub rsp, " (number->string frame-shift))))
         (emit "    mov rdx, [r10 - 1]")
         (emit "    call rdx")
         (if (> frame-shift 0)
             (emit (string-append "    add rsp, " (number->string frame-shift))))))

      (else
       (error "Unknown LIR opcode in x86-64 backend:" inst)))))

;;; Emits assembly for a single %lir-function
(define (emit-x86-function fn)
  (let* ((label (cadr fn))
         (label-str (if (symbol? label) (symbol->string label) label))
         (body (cdr (assq 'body (cddr fn)))))
    (emit "    .p2align 3")
    (emit (string-append label-str ":"))
    ;; Callee prologue: self closure pointer was in r10
    ;; Store self closure pointer at [rsp - 8]
    (emit "    mov [rsp - 8], r10")
    (for-each emit-lir-instruction body)))

;;; Pass 7 Entrypoint: Takes %lir-program and emits complete GNU x86-64 assembly
(define (emit-x86-64 prog)
  (let* ((funcs-clause (assq '%lir-functions (cdr prog)))
         (funcs (if funcs-clause (cdr funcs-clause) '()))
         (main-clause (assq '%lir-main (cdr prog)))
         (main-body (cdr (assq 'body (cdr main-clause)))))
    (emit "    .intel_syntax noprefix")
    (emit "    .text")
    (emit "    .globl scheme_entry")
    (emit "    .type scheme_entry, @function")
    (emit "scheme_entry:")
    (emit "    push r12")
    (emit "    sub rsp, 8")
    (emit "    mov r12, rdi")          ; rdi contains heap_base from C runtime
    (for-each (lambda (inst)
                (if (not (eq? (car inst) '%return))
                    (emit-lir-instruction inst)))
              main-body)
    (emit "    add rsp, 8")
    (emit "    pop r12")
    (emit "    ret")
    ;; Emit all lifted procedure definitions in sequence
    (for-each emit-x86-function funcs)
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
