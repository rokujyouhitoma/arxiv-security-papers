;;; =======================================================================
;;; ULisp Compiler Pass 7: Native x86-64 Backend Code Generator
;;; Conforms to DSN-33 Architecture Specification & ulisp/docs/lir_specification.md
;;; Consumes Pass 6 %lir-program and emits pure GNU x86-64 Intel-syntax assembly.
;;; =======================================================================

(define (emit line)
  (write-string line)
  (write-char #\newline))

(define (emit-boolean-from-set set-inst)
  (emit (string-append "    " set-inst " al"))
  (emit "    movzx eax, al")
  (emit "    shl rax, 6")
  (emit "    add rax, 0x2F"))

(define (reg->str reg)
  (case reg
    ((%rax) "rax")
    ((%rbx) "rbx")
    ((%rcx) "rcx")
    ((%rdx) "rdx")
    ((%rsi) "rsi")
    ((%rdi) "rdi")
    ((%rbp) "rbp")
    ((%rsp) "rsp")
    ((%r8)  "r8")
    ((%r9)  "r9")
    ((%r10) "r10")
    ((%r11) "r11")
    ((%r12) "r12")
    ((%r13) "r13")
    ((%r14) "r14")
    ((%r15) "r15")
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
         ((%reg)
          (reg->str (cadr opnd)))
         ((%stack)
          (string-append "[rsp " (offset->string (cadr opnd)) "]"))
         ((%mem)
          (mem-op->str (cadr opnd) (caddr opnd)))
         (else
          (error "Unknown operand in x86-64 backend:" opnd)))))
    (else
     (error "Invalid operand type in x86-64 backend:" opnd))))

;;; Block Arguments tracking and parallel copy for SSA LIR
(define *x86-block-params* (cons '() '()))
(define *backend-gc-mode* (cons 'all '()))
(define *alloc-counter* (cons 0 '()))
(define (new-alloc-id!)
  (let ((cnt (+ (car *alloc-counter*) 1)))
    (set-car! *alloc-counter* cnt)
    cnt))

(define (reset-x86-block-params!)
  (set-car! *x86-block-params* '()))

(define (record-x86-block-params! lbl params)
  (let ((entry (assq lbl (car *x86-block-params*))))
    (if entry
        (set-cdr! entry params)
        (set-car! *x86-block-params* (cons (cons lbl params) (car *x86-block-params*))))))

(define (get-x86-block-params lbl)
  (let ((entry (assq lbl (car *x86-block-params*))))
    (if entry (cdr entry) '())))

(define (scan-x86-blocks! insts)
  (reset-x86-block-params!)
  (for-each
   (lambda (inst)
     (if (and (pair? inst) (eq? (car inst) '%block))
         (let ((lbl (cadr inst))
               (params (caddr inst)))
           (record-x86-block-params! lbl params))))
   insts))

(define (x86-param-location idx param)
  (cond
    ((memq param '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15))
     param)
    ((and (pair? param) (eq? (car param) '%reg))
     (cadr param))
    ((and (pair? param) (eq? (car param) '%stack)) param)
    (else
     (list '%stack (* -8 (+ idx 2))))))

(define (emit-x86-parallel-copy target-lbl args)
  (let ((params (get-x86-block-params target-lbl)))
    (let loop ((ps params) (as args) (i 0))
      (if (and (pair? ps) (pair? as))
          (let* ((param (car ps))
                 (arg (car as))
                 (loc (x86-param-location i param)))
            (cond
              ((equal? loc arg) #f)
              ((eq? loc '%rax)
               (emit (string-append "    mov rax, " (operand->str arg))))
              ((and (pair? loc) (eq? (car loc) '%stack))
               (cond
                 ((pair? arg)
                  (emit (string-append "    mov r10, " (operand->str arg)))
                  (emit (string-append "    mov " (operand->str loc) ", r10")))
                 ((integer? arg)
                  (emit (string-append "    mov qword ptr " (operand->str loc) ", " (number->string arg))))
                 (else
                  (emit (string-append "    mov " (operand->str loc) ", " (operand->str arg))))))
              (else
               (emit (string-append "    mov " (operand->str loc) ", " (operand->str arg)))))
            (loop (cdr ps) (cdr as) (+ i 1)))))))

;;; Emits a single LIR instruction to x86-64 assembly
(define (emit-lir-instruction inst)
  (let ((op (car inst)))
    (case op
      ((%label)
       (let ((lbl (cadr inst)))
         (emit "    .p2align 4")
         (emit (string-append (if (symbol? lbl) (symbol->string lbl) lbl) ":"))))

      ((%block)
       (let ((lbl (cadr inst))
             (params (caddr inst))
             (body (cdddr inst)))
         (record-x86-block-params! lbl params)
         (emit "    .p2align 4")
         (emit (string-append (if (symbol? lbl) (symbol->string lbl) lbl) ":"))
         (for-each emit-lir-instruction body)))

      ((%jump)
       (let* ((lbl (cadr inst))
              (args (if (pair? (cddr inst)) (caddr inst) '())))
         (if (pair? args)
             (emit-x86-parallel-copy lbl args))
         (emit (string-append "    jmp " (reg->str lbl)))))

      ((%jump-if-false)
       (let* ((reg (cadr inst))
              (lbl (caddr inst))
              (args (if (pair? (cdddr inst)) (cadddr inst) '())))
         (if (null? args)
             (begin
               (emit (string-append "    cmp " (reg->str reg) ", 0x2F"))
               (emit (string-append "    je " (if (symbol? lbl) (symbol->string lbl) lbl))))
             (let ((cont-lbl (unique-label-sym "L_cont_")))
               (emit (string-append "    cmp " (reg->str reg) ", 0x2F"))
               (emit (string-append "    jne " (symbol->string cont-lbl)))
               (emit-x86-parallel-copy lbl args)
               (emit (string-append "    jmp " (reg->str lbl)))
               (emit (string-append (symbol->string cont-lbl) ":"))))))

      ((%jump-cond)
       (let ((jmp-op (cadr inst))
             (lbl (caddr inst)))
         (emit (string-append "    " jmp-op " " (if (symbol? lbl) (symbol->string lbl) (reg->str lbl))))))

      ((%jump-if)
       (let* ((reg (cadr inst))
              (then-lbl (caddr inst))
              (then-args (cadddr inst))
              (rest-else (cdr (cdddr inst)))
              (else-lbl (car rest-else))
              (else-args (cadr rest-else))
              (else-tramline (unique-label-sym "L_else_tramline_")))
         (emit (string-append "    cmp " (reg->str reg) ", 0x2F"))
         (emit (string-append "    je " (symbol->string else-tramline)))
         (if (pair? then-args)
             (emit-x86-parallel-copy then-lbl then-args))
         (emit (string-append "    jmp " (reg->str then-lbl)))
         (emit (string-append (symbol->string else-tramline) ":"))
         (if (pair? else-args)
             (emit-x86-parallel-copy else-lbl else-args))
         (emit (string-append "    jmp " (reg->str else-lbl)))))

      ((%jump-if-zero)
       (let ((lbl (cadr inst)))
         (emit (string-append "    je " (if (symbol? lbl) (symbol->string lbl) lbl)))))

      ((%return)
       (emit "    ret"))

      ((%push)
       (let ((src (cadr inst)))
         (emit (string-append "    push " (reg->str src)))))

      ((%pop)
       (let ((dst (cadr inst)))
         (emit (string-append "    pop " (reg->str dst)))))

      ((%syscall)
       (emit "    syscall"))

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
         (if (integer? src)
             (emit (string-append "    mov qword ptr " (mem-op->str base offset) ", " (number->string src)))
             (emit (string-append "    mov " (mem-op->str base offset) ", " (operand->str src))))))

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

      ((%raw-add)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    add " (operand->str dst) ", " (operand->str src)))))

      ((%sub)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    sub " (operand->str dst) ", " (operand->str src)))))

      ((%raw-sub)
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

      ((%raw-mul)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (emit (string-append "    imul " (operand->str dst) ", " (operand->str src)))))

      ((%box-fixnum)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (not (eq? dst src))
             (emit (string-append "    mov " (operand->str dst) ", " (operand->str src))))
         (emit (string-append "    shl " (operand->str dst) ", 2"))))

      ((%unbox-fixnum)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (not (eq? dst src))
             (emit (string-append "    mov " (operand->str dst) ", " (operand->str src))))
         (emit (string-append "    sar " (operand->str dst) ", 2"))))

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

      ((%cmp %raw-cmp)
       (let ((s1 (cadr inst))
             (s2 (caddr inst)))
         (emit (string-append "    cmp " (operand->str s1) ", " (operand->str s2)))))

      ((%set-boolean)
       (let ((cc (caddr inst)))
         (emit-boolean-from-set cc)))

      ((%alloc)
       (let* ((dst (cadr inst))
              (bytes (caddr inst))
              (tag (cadddr inst))
              (si (if (pair? (cddddr inst)) (car (cddddr inst)) -128))
              (pos-si (if (< si 0) (- 0 si) si))
              (shift (let* ((needed (+ pos-si 96))
                            (rem (modulo needed 16)))
                       (if (= rem 0) needed (+ needed (- 16 rem))))))
         (cond
           ((eq? (car *backend-gc-mode*) 'none)
            (emit (string-append "    lea " (operand->str dst) ", [r12 + " (number->string tag) "]"))
            (emit (string-append "    add r12, " (number->string bytes)))
            (emit "    cmp r12, [rip + ulisp_heap_limit]")
            (emit "    ja ulisp_oom_panic"))
           ((eq? (car *backend-gc-mode*) 'stress)
            ;; Stress mode: unconditionally invoke GC slow trampoline on every allocation
            (emit (string-append "    sub rsp, " (number->string shift)))
            (emit "    call ulisp_alloc_slow_trampoline")
            (emit (string-append "    add rsp, " (number->string shift)))
            (emit (string-append "    lea " (operand->str dst) ", [r12 + " (number->string tag) "]"))
            (emit (string-append "    add r12, " (number->string bytes)))
            (emit "    cmp r12, [rip + ulisp_heap_limit]")
            (emit "    ja ulisp_oom_panic"))
           (else
            (let ((lbl-fast (string-append ".L_alloc_fast_" (number->string (new-alloc-id!))))
                  (lbl-slow (string-append ".L_alloc_slow_" (number->string (car *alloc-counter*)))))
              (emit "    cmp byte ptr [rip + ulisp_gc_stress_mode], 0")
              (emit (string-append "    jne " lbl-slow))
              (emit (string-append "    lea r11, [r12 + " (number->string bytes) "]"))
              (emit "    cmp r11, [rip + ulisp_heap_limit]")
              (emit (string-append "    jbe " lbl-fast))
              (emit (string-append lbl-slow ":"))
              ;; Slow path: shift rsp past active frame variables and invoke common trampoline
              (emit (string-append "    sub rsp, " (number->string shift)))
              (emit "    call ulisp_alloc_slow_trampoline")
              (emit (string-append "    add rsp, " (number->string shift)))
              (emit (string-append lbl-fast ":"))
              (emit (string-append "    lea " (operand->str dst) ", [r12 + " (number->string tag) "]"))
              (emit (string-append "    add r12, " (number->string bytes)))
              (emit "    cmp r12, [rip + ulisp_heap_limit]")
              (emit "    ja ulisp_oom_panic"))))))

      ((%alloc-stack)
       (let ((dst (cadr inst))
             (offset (caddr inst))
             (tag (cadddr inst)))
         (let ((disp (+ offset tag)))
           (if (>= disp 0)
               (emit (string-append "    lea " (operand->str dst) ", [rsp + " (number->string disp) "]"))
               (emit (string-append "    lea " (operand->str dst) ", [rsp - " (number->string (- 0 disp)) "]"))))))

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
         (let ((fname (if (symbol? func) (symbol->raw-name func) func)))
           (emit (string-append "    sub rsp, " (number->string frame-shift)))
           (emit (string-append "    call " fname))
           (emit (string-append "    add rsp, " (number->string frame-shift))))))

      ((%call-closure)
       (let ((frame-shift (cadr inst))
             (safepoint (if (pair? (cddr inst)) (caddr inst) #f)))
         (if (> frame-shift 0)
             (emit (string-append "    sub rsp, " (number->string frame-shift))))
         (emit "    mov rdx, [r10 - 1]")
         (emit "    call rdx")
         (if safepoint
             (emit (string-append (if (symbol? safepoint) (symbol->string safepoint) safepoint) ":")))
         (if (> frame-shift 0)
             (emit (string-append "    add rsp, " (number->string frame-shift))))))

      ((%direct-call)
       (let ((label (cadr inst))
             (frame-shift (caddr inst))
             (safepoint (if (pair? (cdddr inst)) (cadddr inst) #f)))
         (let ((lbl-str (if (symbol? label) (symbol->string label) label)))
           (if (> frame-shift 0)
               (emit (string-append "    sub rsp, " (number->string frame-shift))))
           (emit "    xor r10, r10")
           (emit (string-append "    call " lbl-str))
           (if safepoint
               (emit (string-append (if (symbol? safepoint) (symbol->string safepoint) safepoint) ":")))
           (if (> frame-shift 0)
               (emit (string-append "    add rsp, " (number->string frame-shift)))))))

      ((%direct-jump)
       (let ((label (cadr inst)))
         (emit "    xor r10, r10")
         (emit (string-append "    jmp " (if (symbol? label) (symbol->string label) label)))))

      ((%global-ref)
       (let ((reg (cadr inst))
             (var (caddr inst)))
         (let ((g-lbl (string-append "ulisp_gvar_" (sanitize-label-str (symbol->string var)))))
           (emit (string-append "    lea r11, [rip + " g-lbl "]"))
           (emit (string-append "    mov " (reg->str reg) ", [r11]")))))

      ((%global-set!)
       (let ((var (cadr inst))
             (reg (caddr inst)))
         (let ((g-lbl (string-append "ulisp_gvar_" (sanitize-label-str (symbol->string var)))))
           (emit (string-append "    lea r11, [rip + " g-lbl "]"))
           (emit (string-append "    mov [r11], " (reg->str reg))))))

      ((%push-handler)
       (let ((catch-lbl (cadr inst))
             (frame-si (caddr inst))
             (handler-si (cadddr inst)))
         (let ((lbl-str (if (symbol? catch-lbl) (symbol->string catch-lbl) catch-lbl)))
           (emit (string-append "    lea rax, [rip + " lbl-str "]"))
           (emit (string-append "    mov [rsp " (offset->string (+ frame-si 24)) "], rax"))
           (emit "    lea rdx, [rip + ulisp_handler_chain]")
           (emit "    mov rcx, [rdx]")
           (emit (string-append "    mov [rsp " (offset->string frame-si) "], rcx"))
           (emit (string-append "    mov [rsp " (offset->string (+ frame-si 8)) "], rsp"))
           (emit (string-append "    mov [rsp " (offset->string (+ frame-si 16)) "], rbp"))
           (emit (string-append "    mov rax, [rsp " (offset->string handler-si) "]"))
           (emit (string-append "    mov [rsp " (offset->string (+ frame-si 32)) "], rax"))
           (emit (string-append "    lea rax, [rsp " (offset->string frame-si) "]"))
           (emit "    mov [rdx], rax"))))

      ((%pop-handler)
       (let ((frame-si (cadr inst)))
         (emit "    lea rdx, [rip + ulisp_handler_chain]")
         (emit (string-append "    mov rcx, [rsp " (offset->string frame-si) "]"))
         (emit "    mov [rdx], rcx")))

      ((%raise)
       (emit "    lea rdx, [rip + ulisp_handler_chain]")
       (emit "    mov rbx, [rdx]")
       (emit "    test rbx, rbx")
       (emit "    jz .L_unhandled_exn")
       (emit "    mov rcx, [rbx]")
       (emit "    mov [rdx], rcx")
       (emit "    mov rdi, rax")
       (emit "    mov rsp, [rbx + 8]")
       (emit "    mov rbp, [rbx + 16]")
       (emit "    mov r10, [rbx + 24]")
       (emit "    mov rax, [rbx + 32]")
       (emit "    jmp r10"))

      ((%set-values-count)
       (let ((cnt (cadr inst)))
         (emit "    lea rdx, [rip + ulisp_values_count]")
         (emit (string-append "    mov qword ptr [rdx], " (number->string cnt)))))

      ((%store-values-buf)
       (let ((base-si (cadr inst))
             (count (caddr inst)))
         (emit "    lea rbx, [rip + ulisp_values_buf]")
         (let loop ((i 0))
           (if (< i count)
               (let ((offset (+ base-si (* -8 i)))
                     (buf-disp (* 8 i)))
                 (emit (string-append "    mov rax, [rsp " (offset->string offset) "]"))
                 (emit (string-append "    mov [rbx + " (number->string buf-disp) "], rax"))
                 (loop (+ i 1)))))))

      ((%dispatch-consumer)
       (let* ((consumer-si (cadr inst))
              (aligned-si (caddr inst))
              (frame-shift (cadddr inst))
              (exit-lbl (unique-label-sym "L_cwv_exit_"))
              (call-0-lbl (unique-label-sym "L_cwv_call_0_"))
              (call-1-lbl (unique-label-sym "L_cwv_call_1_"))
              (call-2-lbl (unique-label-sym "L_cwv_call_2_"))
              (call-3-lbl (unique-label-sym "L_cwv_call_3_"))
              (call-4-lbl (unique-label-sym "L_cwv_call_4_"))
              (exit-str (symbol->string exit-lbl)))
         (emit "    lea rdx, [rip + ulisp_values_count]")
         (emit "    mov rcx, [rdx]")
         (emit "    mov qword ptr [rdx], 1")
         (emit (string-append "    mov r10, [rsp " (offset->string consumer-si) "]"))
         (emit "    lea rbx, [rip + ulisp_values_buf]")
         (emit "    cmp rcx, 1")
         (emit (string-append "    je " (symbol->string call-1-lbl)))
         (emit "    cmp rcx, 2")
         (emit (string-append "    je " (symbol->string call-2-lbl)))
         (emit "    cmp rcx, 0")
         (emit (string-append "    je " (symbol->string call-0-lbl)))
         (emit "    cmp rcx, 3")
         (emit (string-append "    je " (symbol->string call-3-lbl)))
         (emit "    cmp rcx, 4")
         (emit (string-append "    je " (symbol->string call-4-lbl)))
         ;; 0 args
         (emit (string-append (symbol->string call-0-lbl) ":"))
         (if (> frame-shift 0)
             (emit (string-append "    sub rsp, " (number->string frame-shift))))
         (emit "    mov rdx, [r10 - 1]")
         (emit "    mov rax, 0")
         (emit "    call rdx")
         (if (> frame-shift 0)
             (emit (string-append "    add rsp, " (number->string frame-shift))))
         (emit (string-append "    jmp " exit-str))
         ;; 1 arg (rax already has the value)
         (emit (string-append (symbol->string call-1-lbl) ":"))
         (emit (string-append "    mov [rsp " (offset->string aligned-si) "], rax"))
         (if (> frame-shift 0)
             (emit (string-append "    sub rsp, " (number->string frame-shift))))
         (emit "    mov rdx, [r10 - 1]")
         (emit "    mov rax, 4")
         (emit "    call rdx")
         (if (> frame-shift 0)
             (emit (string-append "    add rsp, " (number->string frame-shift))))
         (emit (string-append "    jmp " exit-str))
         ;; 2 args
         (emit (string-append (symbol->string call-2-lbl) ":"))
         (emit "    mov rax, [rbx]")
         (emit (string-append "    mov [rsp " (offset->string (+ aligned-si 8)) "], rax"))
         (emit "    mov rax, [rbx + 8]")
         (emit (string-append "    mov [rsp " (offset->string aligned-si) "], rax"))
         (if (> frame-shift 0)
             (emit (string-append "    sub rsp, " (number->string frame-shift))))
         (emit "    mov rdx, [r10 - 1]")
         (emit "    mov rax, 8")
         (emit "    call rdx")
         (if (> frame-shift 0)
             (emit (string-append "    add rsp, " (number->string frame-shift))))
         (emit (string-append "    jmp " exit-str))
         ;; 3 args
         (emit (string-append (symbol->string call-3-lbl) ":"))
         (emit "    mov rax, [rbx]")
         (emit (string-append "    mov [rsp " (offset->string (+ aligned-si 16)) "], rax"))
         (emit "    mov rax, [rbx + 8]")
         (emit (string-append "    mov [rsp " (offset->string (+ aligned-si 8)) "], rax"))
         (emit "    mov rax, [rbx + 16]")
         (emit (string-append "    mov [rsp " (offset->string aligned-si) "], rax"))
         (if (> frame-shift 0)
             (emit (string-append "    sub rsp, " (number->string frame-shift))))
         (emit "    mov rdx, [r10 - 1]")
         (emit "    mov rax, 12")
         (emit "    call rdx")
         (if (> frame-shift 0)
             (emit (string-append "    add rsp, " (number->string frame-shift))))
         (emit (string-append "    jmp " exit-str))
         ;; 4 args
         (emit (string-append (symbol->string call-4-lbl) ":"))
         (emit "    mov rax, [rbx]")
         (emit (string-append "    mov [rsp " (offset->string (+ aligned-si 24)) "], rax"))
         (emit "    mov rax, [rbx + 8]")
         (emit (string-append "    mov [rsp " (offset->string (+ aligned-si 16)) "], rax"))
         (emit "    mov rax, [rbx + 16]")
         (emit (string-append "    mov [rsp " (offset->string (+ aligned-si 8)) "], rax"))
         (emit "    mov rax, [rbx + 24]")
         (emit (string-append "    mov [rsp " (offset->string aligned-si) "], rax"))
         (if (> frame-shift 0)
             (emit (string-append "    sub rsp, " (number->string frame-shift))))
         (emit "    mov rdx, [r10 - 1]")
         (emit "    mov rax, 16")
         (emit "    call rdx")
         (if (> frame-shift 0)
             (emit (string-append "    add rsp, " (number->string frame-shift))))
         (emit (string-append "    jmp " exit-str))
         (emit (string-append exit-str ":"))))

      ((%capture-cc)
       (let* ((ret-lbl (cadr inst))
              (k-si (caddr inst))
              (lbl-str (if (symbol? ret-lbl) (symbol->string ret-lbl) ret-lbl)))
         (emit "    lea rcx, [rip + ulisp_stack_base]")
         (emit "    mov rcx, [rcx]")
         (emit "    sub rcx, rsp")
         (emit "    test rcx, rcx")
         (emit "    jle .L_cap_fallback_size")
         (emit "    cmp rcx, 8388608")
         (emit "    jbe .L_cap_size_ok")
         (emit ".L_cap_fallback_size:")
         (emit "    mov rcx, 65536")
         (emit ".L_cap_size_ok:")
         (emit "    mov r8, rcx")
         (emit "    add r8, 111")
         (emit "    and r8, -16")
         (emit "    mov rax, r12")
         (emit "    add r12, r8")
         (emit "    lea r9, [rip + ulisp_continuation_invoke]")
         (emit "    mov [rax], r9")
         (emit "    mov [rax + 8], rcx")
         (emit "    mov [rax + 16], rsp")
         (emit "    mov [rax + 24], rbp")
         (emit "    mov [rax + 32], rbx")
         (emit "    mov [rax + 40], r12")
         (emit "    mov [rax + 48], r13")
         (emit "    mov [rax + 56], r14")
         (emit "    mov [rax + 64], r15")
         (emit (string-append "    lea r9, [rip + " lbl-str "]"))
         (emit "    mov [rax + 72], r9")
         (emit "    lea r9, [rip + ulisp_handler_chain]")
         (emit "    mov r8, [r9]")
         (emit "    mov [rax + 80], r8")
         ;; Store continuation object to stack BEFORE copying to heap!
         (emit "    lea rdx, [rax + 1]")
         (emit (string-append "    mov [rsp " (offset->string k-si) "], rdx"))
         ;; Now copy stack bytes to heap
         (emit "    lea rdi, [rax + 96]")
         (emit "    mov rsi, rsp")
         (emit "    cld")
         (emit "    rep movsb")
         (emit "    mov rax, rdx")))

      (else
       (error (string-append "Unknown LIR opcode in x86-64 backend: "
                             (if (symbol? (car inst)) (symbol->string (car inst)) "?"))
              inst)))))

;;; Emits assembly for a single %lir-function
(define (emit-x86-function fn)
  (let* ((label (cadr fn))
         (label-str (if (symbol? label) (symbol->string label) label))
         (body (cdr (assq 'body (cddr fn)))))
    (scan-x86-blocks! body)
    (emit "    .p2align 4")
    (emit (string-append label-str ":"))
    ;; Callee prologue: self closure pointer was in r10
    ;; Store self closure pointer at [rsp - 8]
    (emit "    mov [rsp - 8], r10")
    (for-each emit-lir-instruction body)))

;;; Pass 7 Entrypoint: Takes %lir-program and emits complete GNU x86-64 assembly
(define (emit-x86-64 prog gc-mode)
  (set-car! *backend-gc-mode* gc-mode)
  (set-car! *alloc-counter* 0)
  (let* ((funcs-clause (assq '%lir-functions (cdr prog)))
         (funcs (if funcs-clause (cdr funcs-clause) '()))
         (main-clause (assq '%lir-main (cdr prog)))
         (main-body (cdr (assq 'body (cdr main-clause)))))
    (emit "    .intel_syntax noprefix")
    (emit "    .text")
    (emit "    .globl _start")
    (emit "    .weak _start")
    (emit "    .type _start, @function")
    (emit "    .p2align 4")
    (emit "_start:")
    (emit "    mov r14, [rsp]")                ; argc
    (emit "    cmp r14, 1")
    (emit "    jle .L_start_no_args")
    (emit "    mov rdi, [rsp + 16]")           ; argv[1]
    (emit "    xor rsi, rsi")                  ; O_RDONLY = 0
    (emit "    xor rdx, rdx")
    (emit "    mov rax, 2")                    ; sys_open
    (emit "    syscall")
    (emit "    test rax, rax")
    (emit "    js .L_start_no_args")
    (emit "    mov rdi, rax")
    (emit "    xor rsi, rsi")                  ; stdin (0)
    (emit "    mov rax, 33")                   ; sys_dup2
    (emit "    syscall")
    (emit ".L_start_no_args:")
    (emit "    mov rbp, rsp")
    (emit "    and rsp, -16")
    (cond
      ((eq? gc-mode 'none)
       (emit "    mov rax, 9")                     ; sys_mmap
       (emit "    xor rdi, rdi")                   ; addr = NULL
       (emit "    mov rsi, 12884901888")           ; 12GB heap (0x300000000)
       (emit "    mov rdx, 3")                     ; PROT_READ|PROT_WRITE
       (emit "    mov r10, 34")                    ; MAP_PRIVATE|MAP_ANONYMOUS
       (emit "    mov r8, -1")                     ; fd = -1
       (emit "    xor r9, r9")                     ; offset = 0
       (emit "    syscall")
       (emit "    test rax, rax")
       (emit "    js .L_start_exit")
       (emit "    mov rdi, rax")                   ; rdi = heap_base
       (emit "    mov rcx, rax")
       (emit "    mov rdx, 12884901888")
       (emit "    add rcx, rdx")
       (emit "    lea rdx, [rip + ulisp_heap_limit]")
       (emit "    mov [rdx], rcx"))
      ((or (eq? gc-mode 'dual-space) (eq? gc-mode 'stress))
       (emit "    mov rax, 9")                     ; sys_mmap
       (emit "    xor rdi, rdi")                   ; addr = NULL
       (emit "    mov rsi, 134217728")             ; 128MB (2 x 64MB)
       (emit "    mov rdx, 3")                     ; PROT_READ|PROT_WRITE
       (emit "    mov r10, 34")                    ; MAP_PRIVATE|MAP_ANONYMOUS
       (emit "    mov r8, -1")                     ; fd = -1
       (emit "    xor r9, r9")                     ; offset = 0
       (emit "    syscall")
       (emit "    test rax, rax")
       (emit "    js .L_start_exit")
       (emit "    lea rbx, [rip + ulisp_gc_state]")
       (emit "    mov [rbx + 0], rax")             ; from
       (emit "    mov rdi, rax")                   ; rdi = from
       (emit "    lea rcx, [rax + 67108864]")
       (emit "    mov [rbx + 8], rcx")             ; to
       (emit "    mov qword ptr [rbx + 16], 67108864") ; size = 64MB
       (emit "    mov [rbx + 24], rbp")            ; bottom
       (emit "    mov qword ptr [rbx + 32], 0")    ; count = 0
       (emit "    mov [rbx + 40], rcx")            ; free_ptr = to
       (emit "    mov qword ptr [rbx + 88], 0")    ; gen_mode = 0
       (emit "    mov qword ptr [rbx + 112], 4")   ; profile_id = 4 (dual-space)
       (emit "    lea rdx, [rip + ulisp_heap_limit]")
       (emit "    mov [rdx], rcx")                 ; limit = from + 64MB
       (if (eq? gc-mode 'stress)
           (begin
             (emit "    mov qword ptr [rbx + 128], 1") ; stress_mode = 1
             (emit "    lea rax, [rip + ulisp_gc_stress_mode]")
             (emit "    mov byte ptr [rax], 1"))))
      (else
       ;; Generational GC with Execution Profiles (Issue #567)
       ;; Scan envp for ULISP_GC_PROFILE (precedence over compile-time default)
       (emit "    mov r8, [rbp]")                  ; argc
       (emit "    lea r9, [rbp + r8*8 + 16]")      ; envp = argv + argc + 1
       (emit "    xor r10, r10")                   ; r10 = 0 (unset / standard)
       (emit ".L_env_scan_loop:")
       (emit "    mov rsi, [r9]")
       (emit "    test rsi, rsi")
       (emit "    jz .L_env_scan_done")
       (emit "    add r9, 8")
       (emit "    mov rax, [rsi]")
       (emit "    mov r11, 0x43475f5053494c55")    ; "ULISP_GC"
       (emit "    cmp rax, r11")
       (emit "    jne .L_env_scan_loop")
       (emit "    mov rax, [rsi + 8]")
       (emit "    mov r11, 0x3d5353455254535f")    ; "_STRESS="
       (emit "    cmp rax, r11")
       (emit "    jne .L_env_check_profile")
       (emit "    cmp byte ptr [rsi + 16], '0'")
       (emit "    je .L_env_scan_loop")
       (emit "    cmp byte ptr [rsi + 16], 0")
       (emit "    je .L_env_scan_loop")
       (emit "    lea rax, [rip + ulisp_gc_stress_mode]")
       (emit "    mov byte ptr [rax], 1")
       (emit "    lea rax, [rip + ulisp_gc_state]")
       (emit "    mov qword ptr [rax + 128], 1")
       (emit "    mov r10, 4")                     ; profile_id = 4 (stress mode)
       (emit "    jmp .L_env_scan_done")
       (emit ".L_env_check_profile:")
       (emit "    mov r11, 0x454c49464f52505f")    ; "_PROFILE"
       (emit "    cmp rax, r11")
       (emit "    jne .L_env_scan_loop")
       (emit "    cmp byte ptr [rsi + 16], 0x3d")  ; '='
       (emit "    jne .L_env_scan_loop")
       (emit "    movzx eax, byte ptr [rsi + 17]")
       (emit "    cmp al, 'c'")                    ; compiler
       (emit "    je .L_env_set_compiler")
       (emit "    cmp al, 'C'")
       (emit "    je .L_env_set_compiler")
       (emit "    cmp al, 's'")                    ; server
       (emit "    je .L_env_set_server")
       (emit "    cmp al, 'S'")
       (emit "    je .L_env_set_server")
       (emit "    cmp al, 'd'")                    ; default / standard
       (emit "    je .L_env_set_standard")
       (emit "    cmp al, 'D'")
       (emit "    je .L_env_set_standard")
       (emit "    jmp .L_env_scan_loop")
       (emit ".L_env_set_compiler:")
       (emit "    mov r10, 1")
       (emit "    jmp .L_env_scan_done")
       (emit ".L_env_set_server:")
       (emit "    mov r10, 2")
       (emit "    jmp .L_env_scan_done")
       (emit ".L_env_set_standard:")
       (emit "    mov r10, 0")
       (emit "    jmp .L_env_scan_done")
       (emit ".L_env_scan_done:")
       (cond
         ((eq? gc-mode 'compiler)
          (emit "    test r10, r10")
          (emit "    jnz .L_profile_decided")
          (emit "    mov r10, 1")                  ; compile-time default: compiler
          (emit ".L_profile_decided:"))
         ((eq? gc-mode 'server)
          (emit "    test r10, r10")
          (emit "    jnz .L_profile_decided")
          (emit "    mov r10, 2")                  ; compile-time default: server
          (emit ".L_profile_decided:"))
         (else
          (emit ".L_profile_decided:")))
       (emit "    cmp r10, 4")
       (emit "    je .L_profile_stress")
       (emit "    cmp r10, 1")
       (emit "    je .L_profile_compiler")
       (emit "    cmp r10, 2")
       (emit "    je .L_profile_server")
       ;; Standard Profile (4MB Nursery, 64MB Mature, 1GB Max)
       (emit "    mov r12, 4194304")               ; nursery_size = 4MB
       (emit "    mov r13, 67108864")              ; mature_size = 64MB
       (emit "    mov rsi, 138444800")             ; total_mmap = ~132MB
       (emit "    mov r8, 1073741824")             ; max_mature = 1GB
       (emit "    xor r10, r10")                   ; profile_id = 0
       (emit "    jmp .L_profile_setup")
       ;; Stress Profile (Dual-Space Semi-Space 64MB + 64MB = 128MB)
       (emit ".L_profile_stress:")
       (emit "    mov r12, 67108864")              ; size = 64MB
       (emit "    mov r13, 67108864")              ; size = 64MB
       (emit "    mov rsi, 134217728")             ; total_mmap = 128MB
       (emit "    mov r8, 134217728")
       (emit "    mov r10, 4")                     ; profile_id = 4
       (emit "    jmp .L_profile_setup")
       ;; Compiler Profile (256MB Nursery, 256MB Mature, 4GB Max)
       (emit ".L_profile_compiler:")
       (emit "    mov r12, 268435456")             ; nursery_size = 256MB
       (emit "    mov r13, 268435456")             ; mature_size = 256MB
       (emit "    mov rsi, 805371904")             ; total_mmap = ~768MB
       (emit "    mov r8, 4294967296")             ; max_mature = 4GB
       (emit "    mov r10, 1")                     ; profile_id = 1
       (emit "    jmp .L_profile_setup")
       ;; Server Profile (16MB Nursery, 256MB Mature, 4GB Max)
       (emit ".L_profile_server:")
       (emit "    mov r12, 16777216")              ; nursery_size = 16MB
       (emit "    mov r13, 268435456")             ; mature_size = 256MB
       (emit "    mov rsi, 553713664")             ; total_mmap = ~528MB
       (emit "    mov r8, 4294967296")             ; max_mature = 4GB
       (emit "    mov r10, 2")                     ; profile_id = 2
       (emit "    jmp .L_profile_setup")
       (emit ".L_profile_setup:")
       (emit "    push r10")                       ; save profile_id
       (emit "    push r8")                        ; save max_mature
       (emit "    push r13")                       ; save mature_size
       (emit "    push r12")                       ; save nursery_size
       (emit "    mov rax, 9")                     ; sys_mmap
       (emit "    xor rdi, rdi")                   ; addr = NULL
       (emit "    mov rdx, 3")                     ; PROT_READ|PROT_WRITE
       (emit "    mov r10, 34")                    ; MAP_PRIVATE|MAP_ANONYMOUS
       (emit "    mov r8, -1")                     ; fd = -1
       (emit "    xor r9, r9")                     ; offset = 0
       (emit "    syscall")
       (emit "    pop r12")                        ; restore nursery_size
       (emit "    pop r13")                        ; restore mature_size
       (emit "    pop r8")                         ; restore max_mature
       (emit "    pop r10")                        ; restore profile_id
       (emit "    test rax, rax")
       (emit "    js .L_start_exit")
       (emit "    lea rbx, [rip + ulisp_gc_state]")
       (emit "    cmp r10, 4")
       (emit "    je .L_gc_state_stress_setup")
       (emit "    mov [rbx + 0], rax")             ; nursery_base
       (emit "    mov [rbx + 8], r12")             ; nursery_size
       (emit "    lea rcx, [rax + r12]")
       (emit "    mov [rbx + 16], rcx")            ; mature_from
       (emit "    lea rdx, [rcx + r13]")
       (emit "    mov [rbx + 24], rdx")            ; mature_to
       (emit "    mov [rbx + 32], r13")            ; mature_size
       (emit "    mov [rbx + 40], rcx")            ; mature_free = mature_from
       (emit "    mov [rbx + 48], rbp")            ; stack_bottom
       (emit "    mov qword ptr [rbx + 56], 0")    ; minor_count = 0
       (emit "    mov qword ptr [rbx + 64], 0")    ; major_count = 0
       (emit "    lea r9, [rdx + r13]")
       (emit "    mov [rbx + 72], r9")             ; remset_ptr
       (emit "    mov qword ptr [rbx + 80], 0")    ; remset_count = 0
       (emit "    mov qword ptr [rbx + 88], 1")    ; gen_mode = 1
       (emit "    mov [rbx + 96], r8")             ; max_size
       (emit "    mov qword ptr [rbx + 104], 0")   ; growth_count = 0
       (emit "    mov [rbx + 112], r10")           ; profile_id (0: standard, 1: compiler, 2: server)
       (emit "    mov rdi, rax")                   ; rdi = nursery_base
       (emit "    lea rcx, [rax + r12]")
       (emit "    lea rdx, [rip + ulisp_heap_limit]")
       (emit "    mov [rdx], rcx")                 ; limit = nursery_base + nursery_size
       (emit "    jmp .L_gc_state_setup_done")
       (emit ".L_gc_state_stress_setup:")
       (emit "    mov [rbx + 0], rax")             ; from
       (emit "    mov rdi, rax")                   ; rdi = from
       (emit "    lea rcx, [rax + 67108864]")
       (emit "    mov [rbx + 8], rcx")             ; to
       (emit "    mov qword ptr [rbx + 16], 67108864") ; size = 64MB
       (emit "    mov [rbx + 24], rbp")            ; bottom
       (emit "    mov qword ptr [rbx + 32], 0")    ; count = 0
       (emit "    mov [rbx + 40], rcx")            ; free_ptr = to
       (emit "    mov qword ptr [rbx + 88], 0")    ; gen_mode = 0
       (emit "    mov qword ptr [rbx + 112], 4")   ; profile_id = 4
       (emit "    mov qword ptr [rbx + 128], 1")   ; stress_mode = 1
       (emit "    lea rdx, [rip + ulisp_heap_limit]")
       (emit "    mov [rdx], rcx")                 ; limit = from + 64MB
       (emit ".L_gc_state_setup_done:")))
    (emit "    call scheme_entry")
    (emit "    mov r15, rax")
    (emit "    cmp r14, 1")
    (emit "    jg .L_start_exit")
    (emit "    mov rdi, r15")
    (emit "    call ulisp_print_value")
    (emit "    mov dil, 10")
    (emit "    call ulisp_emit_byte")
    (emit ".L_start_exit:")
    (emit "    call ulisp_flush")
    (emit "    xor rdi, rdi")
    (emit "    mov rax, 60")
    (emit "    syscall")
    (emit "")
    (emit "    .globl scheme_entry")
    (emit "    .type scheme_entry, @function")
    (emit "    .p2align 4")
    (emit "scheme_entry:")
    (emit "    push r12")
    (emit "    sub rsp, 8")
    (emit "    lea rax, [rip + ulisp_stack_base]")
    (emit "    mov rcx, [rax]")
    (emit "    test rcx, rcx")
    (emit "    jnz .L_stack_base_init_done")
    (emit "    mov [rax], rsp")
    (emit ".L_stack_base_init_done:")
    (emit "    mov r12, rdi")          ; rdi contains heap_base
    (scan-x86-blocks! main-body)
    (for-each (lambda (inst)
                (if (not (eq? (car inst) '%return))
                    (emit-lir-instruction inst)))
              main-body)
    (emit "    add rsp, 8")
    (emit "    pop r12")
    (emit "    ret")
    ;; Emit all lifted procedure definitions in sequence
    (for-each emit-x86-function funcs)
    ;; Emit freestanding zero-libc runtime routines
    (emit-freestanding-runtime)
    (emit-oom-panic)
    (emit-gc-collector)
    ;; Emit stackmap metadata table in .rodata section
    (let* ((stackmaps-clause (assq 'stackmaps (cdr prog)))
           (safepoints (if stackmaps-clause (cadr stackmaps-clause) '())))
      (emit "    .section .rodata")
      (emit "    .p2align 3")
      (emit "    .globl __ulisp_stackmap_table")
      (emit "__ulisp_stackmap_table:")
      (emit (string-append "    .quad " (number->string (length safepoints))))
      (for-each (lambda (sp)
                  (let ((lbl (car sp))
                        (frame-size (cadr sp))
                        (bitmap (caddr sp)))
                    (emit (string-append "    .quad " (if (symbol? lbl) (symbol->string lbl) lbl)))
                    (emit (string-append "    .quad " (number->string frame-size)))
                    (emit (string-append "    .quad " (number->string bitmap)))))
                safepoints))
    ;; Emit globals metadata table in .rodata section
    (let ((gvs (car *top-level-vars*)))
      (emit "    .section .rodata")
      (emit "    .p2align 3")
      (emit "    .globl ulisp_globals_table")
      (emit "ulisp_globals_table:")
      (emit (string-append "    .quad " (number->string (length gvs))))
      (for-each (lambda (v)
                  (let ((g-lbl (string-append "ulisp_gvar_" (sanitize-label-str (symbol->string v)))))
                    (emit (string-append "    .quad " g-lbl))))
                gvs))
    ;; Emit all string literals in .rodata section
    (if (not (null? (car *strings*)))
        (let loop ((ss (reverse (car *strings*))))
          (if (not (null? ss))
              (let ((entry (car ss)))
                (emit "    .p2align 3")
                (emit (string-append (car entry) ":"))
                (emit (string-append "    .asciz \"" (escape-gas-string (cdr entry)) "\""))
                (loop (cdr ss))))))
    (emit "    .bss")
    (emit "    .align 8")
    (emit "    .globl ulisp_heap_limit")
    (emit "    .weak ulisp_heap_limit")
    (emit "ulisp_heap_limit:")
    (emit "    .quad 0")
    (emit "    .align 8")
    (emit "    .globl ulisp_stack_base")
    (emit "    .weak ulisp_stack_base")
    (emit "ulisp_stack_base:")
    (emit "    .quad 0")
    (emit "    .align 8")
    (emit "    .globl ulisp_handler_chain")
    (emit "    .weak ulisp_handler_chain")
    (emit "ulisp_handler_chain:")
    (emit "    .quad 0")
    (emit "    .align 8")
    (emit "    .globl ulisp_values_count")
    (emit "    .weak ulisp_values_count")
    (emit "ulisp_values_count:")
    (emit "    .quad 0")
    (emit "    .align 8")
    (emit "    .globl ulisp_values_buf")
    (emit "    .weak ulisp_values_buf")
    (emit "ulisp_values_buf:")
    (emit "    .zero 512")
    (let loop ((gvs (car *top-level-vars*)))
      (if (pair? gvs)
          (let ((v (car gvs)))
            (let ((g-lbl (string-append "ulisp_gvar_" (sanitize-label-str (symbol->string v)))))
              (emit "    .align 8")
              (emit (string-append "    .globl " g-lbl))
              (emit (string-append "    .weak " g-lbl))
              (emit (string-append g-lbl ":"))
              (emit "    .quad 0")
              (loop (cdr gvs))))))
    (emit "    .align 8")
    (emit "    .globl ulisp_gc_stress_mode")
    (emit "    .type ulisp_gc_stress_mode, @object")
    (emit "ulisp_gc_stress_mode:")
    (emit "    .byte 0")
    (emit "    .align 8")
    (emit "    .globl ulisp_gc_state")
    (emit "    .weak ulisp_gc_state")
    (cond
      ((eq? gc-mode 'none)
       (emit "ulisp_gc_state:"))
      (else
       (emit "ulisp_gc_state:")
       (emit "    .space 256")))
    (emit "ulisp_peek_buf:")
    (emit "    .byte 0")
    (emit "ulisp_has_peek:")
    (emit "    .byte 0")
    (emit "    .align 8")
    (emit "ulisp_out_buf_len:")
    (emit "    .quad 0")
    (emit "ulisp_out_buf:")
    (emit "    .space 4096")
    (emit "ulisp_io_buf:")
    (emit "    .space 32")
    (emit "    .section .note.GNU-stack,\"\",@progbits")))

