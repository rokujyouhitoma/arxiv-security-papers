;;; =======================================================================
;;; ULisp Compiler Pass 140: Native x86-64 Backend Code Generator
;;; Conforms to DSN-33 Architecture Specification & Issue #596
;;; Implements 2-stage backend: Instruction Selection (LIR -> L_asm_x86)
;;; and Assembly Code Emission (L_asm_x86 -> GNU x86-64 Intel Syntax).
;;; =======================================================================

(define (emit line)
  (write-string line)
  (write-char #\newline))

(define (backend-append-2 l1 l2)
  (if (null? l1)
      l2
      (cons (car l1) (backend-append-2 (cdr l1) l2))))

(define (backend-concat lists)
  (let loop ((rest lists))
    (cond
      ((null? rest) '())
      ((null? (cdr rest)) (car rest))
      (else (backend-append-2 (car rest) (loop (cdr rest)))))))

(define (reg->str reg)
  (case reg
    ((%rax rax) "rax")
    ((%rbx rbx) "rbx")
    ((%rcx rcx) "rcx")
    ((%rdx rdx) "rdx")
    ((%rsi rsi) "rsi")
    ((%rdi rdi) "rdi")
    ((%rbp rbp) "rbp")
    ((%rsp rsp) "rsp")
    ((%r8  r8)  "r8")
    ((%r9  r9)  "r9")
    ((%r10 r10) "r10")
    ((%r11 r11) "r11")
    ((%r12 r12) "r12")
    ((%r13 r13) "r13")
    ((%r14 r14) "r14")
    ((%r15 r15) "r15")
    ((%al  al)  "al")
    (else (if (symbol? reg) (symbol->string reg) reg))))

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
         ((%disp)
          (string-append "[" (reg->str (caddr opnd)) " " (offset->string (cadr opnd)) "]"))
         ((%imm)
          (number->string (cadr opnd)))
         ((%mem)
          (mem-op->str (cadr opnd) (caddr opnd)))
         (else
          (error "Unknown operand in x86-64 backend:" opnd)))))
    (else
     (error "Invalid operand type in x86-64 backend:" opnd))))

(define (asm-opnd->str opnd)
  (operand->str opnd))

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
    ((memq param '(%rax %rbx %rcx %rdx %rsi %rdi %rbp %rsp %r8 %r9 %r10 %r11 %r12 %r13 %r14 %r15
                   rax rbx rcx rdx rsi rdi rbp rsp r8 r9 r10 r11 r12 r13 r14 r15))
     param)
    ((and (pair? param) (eq? (car param) '%reg))
     (cadr param))
    ((and (pair? param) (eq? (car param) '%stack)) param)
    (else
     (list '%stack (* -8 (+ idx 2))))))

(define (select-x86-parallel-copy target-lbl args)
  (let ((params (get-x86-block-params target-lbl)))
    (let loop ((ps params) (as args) (i 0) (acc '()))
      (if (and (pair? ps) (pair? as))
          (let* ((param (car ps))
                 (arg (car as))
                 (loc (x86-param-location i param)))
            (cond
              ((equal? loc arg)
               (loop (cdr ps) (cdr as) (+ i 1) acc))
              ((or (eq? loc '%rax) (eq? loc 'rax))
               (loop (cdr ps) (cdr as) (+ i 1)
                     (cons (list 'mov 'rax (lower-lir-opnd arg)) acc)))
              ((and (pair? loc) (eq? (car loc) '%stack))
               (let ((stk-disp (list '%disp (cadr loc) 'rsp)))
                 (cond
                   ((pair? arg)
                    (loop (cdr ps) (cdr as) (+ i 1)
                          (cons (list 'mov stk-disp 'r10)
                                (cons (list 'mov 'r10 (lower-lir-opnd arg)) acc))))
                   ((integer? arg)
                    (loop (cdr ps) (cdr as) (+ i 1)
                          (cons (list '%raw-asm (string-append "    mov qword ptr " (operand->str loc) ", " (number->string arg))) acc)))
                   (else
                    (loop (cdr ps) (cdr as) (+ i 1)
                          (cons (list 'mov stk-disp (lower-lir-opnd arg)) acc))))))
              (else
               (loop (cdr ps) (cdr as) (+ i 1)
                     (cons (list 'mov (lower-lir-opnd loc) (lower-lir-opnd arg)) acc)))))
          (reverse acc)))))

(define (emit-x86-parallel-copy target-lbl args)
  (for-each emit-x86-asm-inst (select-x86-parallel-copy target-lbl args)))

;;; -----------------------------------------------------------------------
;;; Stage 1: Instruction Selection (LIR -> L_asm_x86 AST)
;;; -----------------------------------------------------------------------

(define (lower-lir-reg r)
  (case r
    ((%rax) 'rax) ((%rbx) 'rbx) ((%rcx) 'rcx) ((%rdx) 'rdx)
    ((%rsi) 'rsi) ((%rdi) 'rdi) ((%rbp) 'rbp) ((%rsp) 'rsp)
    ((%r8)  'r8)  ((%r9)  'r9)  ((%r10) 'r10) ((%r11) 'r11)
    ((%r12) 'r12) ((%r13) 'r13) ((%r14) 'r14) ((%r15) 'r15)
    ((%al)  'al)
    (else r)))

(define (lower-lir-opnd opnd)
  (cond
    ((symbol? opnd)
     (lower-lir-reg opnd))
    ((integer? opnd)
     (list '%imm opnd))
    ((pair? opnd)
     (let ((tag (car opnd)))
       (case tag
         ((%reg)
          (lower-lir-reg (cadr opnd)))
         ((%stack)
          (list '%disp (cadr opnd) 'rsp))
         ((%disp)
          opnd)
         ((%imm)
          opnd)
         ((%mem)
          (list '%disp (caddr opnd) (lower-lir-reg (cadr opnd))))
         (else
          opnd))))
    (else opnd)))

(define (canonical-x86-cc cond-op)
  (cond
    ((string? cond-op) (string->symbol cond-op))
    ((eq? cond-op 'equal) 'je)
    ((eq? cond-op 'not-equal) 'jne)
    ((eq? cond-op 'less) 'jl)
    ((eq? cond-op 'less-equal) 'jle)
    ((eq? cond-op 'greater) 'jg)
    ((eq? cond-op 'greater-equal) 'jge)
    ((eq? cond-op 'zero) 'je)
    ((eq? cond-op 'not-zero) 'jne)
    ((symbol? cond-op) cond-op)
    (else 'je)))

(define (lower-lir-instruction inst)
  (let ((op (car inst)))
    (case op
      ((%label)
       (let ((lbl (cadr inst)))
         (list (list '%p2align 4)
               (list '%label lbl))))

      ((%block)
       (let ((lbl (cadr inst))
             (params (caddr inst))
             (body (cdddr inst)))
         (record-x86-block-params! lbl params)
         (let loop ((rest body) (acc (list (list '%label lbl) (list '%p2align 4))))
           (if (null? rest)
               (reverse acc)
               (let ((lowered (lower-lir-instruction (car rest))))
                 (loop (cdr rest) (append (reverse lowered) acc)))))))

      ((%jump)
       (let* ((lbl (cadr inst))
              (args (if (pair? (cddr inst)) (caddr inst) '())))
         (append (select-x86-parallel-copy lbl args)
                 (list (list 'jmp (lower-lir-opnd lbl))))))

      ((%jump-if-false)
       (let* ((reg (cadr inst))
              (lbl (caddr inst))
              (args (if (pair? (cdddr inst)) (cadddr inst) '())))
         (if (null? args)
             (list (list 'cmp (lower-lir-opnd reg) (list '%imm 47))
                   (list 'jcc 'je lbl))
             (let ((cont-lbl (unique-label-sym "L_cont_")))
               (backend-concat
                (list (list (list 'cmp (lower-lir-opnd reg) (list '%imm 47))
                            (list 'jcc 'jne cont-lbl))
                      (select-x86-parallel-copy lbl args)
                      (list (list 'jmp (lower-lir-opnd lbl))
                            (list '%label cont-lbl))))))))

      ((%jump-cond)
       (let* ((cond-op (cadr inst))
              (lbl (caddr inst)))
         (list (list 'jcc (canonical-x86-cc cond-op) lbl))))

      ((%jump-if)
       (let* ((reg (cadr inst))
              (then-lbl (caddr inst))
              (then-args (cadddr inst))
              (rest-else (cdr (cdddr inst)))
              (else-lbl (car rest-else))
              (else-args (cadr rest-else))
              (else-tramline (unique-label-sym "L_else_tramline_")))
         (backend-concat
          (list (list (list 'cmp (lower-lir-opnd reg) (list '%imm 47))
                      (list 'jcc 'je else-tramline))
                (if (pair? then-args) (select-x86-parallel-copy then-lbl then-args) '())
                (list (list 'jmp (lower-lir-opnd then-lbl))
                      (list '%label else-tramline))
                (if (pair? else-args) (select-x86-parallel-copy else-lbl else-args) '())
                (list (list 'jmp (lower-lir-opnd else-lbl)))))))

      ((%jump-if-zero)
       (let ((lbl (cadr inst)))
         (list (list 'jcc 'je lbl))))

      ((%return)
       (list (list 'ret)))

      ((%push)
       (let ((src (cadr inst)))
         (list (list 'push (lower-lir-opnd src)))))

      ((%pop)
       (let ((dst (cadr inst)))
         (list (list 'pop (lower-lir-opnd dst)))))

      ((%syscall)
       (list (list 'syscall)))

      ((%mov)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (list (list 'mov (lower-lir-opnd dst) (lower-lir-opnd src)))))

      ((%load)
       (let ((dst (cadr inst))
             (base (caddr inst))
             (offset (cadddr inst)))
         (list (list 'mov (lower-lir-opnd dst) (list '%disp offset (lower-lir-reg base))))))

      ((%store)
       (let ((base (cadr inst))
             (offset (caddr inst))
             (src (cadddr inst)))
         (if (integer? src)
             (list (list '%raw-asm (string-append "    mov qword ptr " (mem-op->str base offset) ", " (number->string src))))
             (list (list 'mov (list '%disp offset (lower-lir-reg base)) (lower-lir-opnd src))))))

      ((%store-byte)
       (let ((base (cadr inst))
             (offset (caddr inst))
             (src (cadddr inst)))
         (let ((src-str (if (number? src) (number->string src) (reg->str src))))
           (list (list '%raw-asm (string-append "    mov byte ptr " (mem-op->str base offset) ", " src-str))))))

      ((%load-byte-zx)
       (let ((dst (cadr inst))
             (base (caddr inst))
             (offset (cadddr inst)))
         (list (list '%raw-asm (string-append "    movzx " (reg->str dst) ", byte ptr " (mem-op->str base offset))))))

      ((%add %raw-add)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (list (list 'add (lower-lir-opnd dst) (lower-lir-opnd src)))))

      ((%sub %raw-sub)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (list (list 'sub (lower-lir-opnd dst) (lower-lir-opnd src)))))

      ((%neg)
       (let ((dst (cadr inst)))
         (list (list 'neg (lower-lir-opnd dst)))))

      ((%imul %raw-mul)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (list (list 'imul (lower-lir-opnd dst) (lower-lir-opnd src)))))

      ((%box-fixnum)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (equal? dst src)
             (list (list 'shl (lower-lir-opnd dst) 2))
             (list (list 'mov (lower-lir-opnd dst) (lower-lir-opnd src))
                   (list 'shl (lower-lir-opnd dst) 2)))))

      ((%unbox-fixnum)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (if (equal? dst src)
             (list (list 'sar (lower-lir-opnd dst) 2))
             (list (list 'mov (lower-lir-opnd dst) (lower-lir-opnd src))
                   (list 'sar (lower-lir-opnd dst) 2)))))

      ((%cqo)
       (list (list 'cqo)))

      ((%idiv)
       (let ((src (cadr inst)))
         (list (list 'idiv (lower-lir-opnd src)))))

      ((%inc)
       (let ((dst (cadr inst)))
         (list (list 'inc (lower-lir-opnd dst)))))

      ((%shl)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (list (list 'shl (lower-lir-opnd dst) count))))

      ((%shr)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (list (list 'shr (lower-lir-opnd dst) count))))

      ((%sar)
       (let ((dst (cadr inst))
             (count (caddr inst)))
         (list (list 'sar (lower-lir-opnd dst) count))))

      ((%bit-and)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (list (list 'and (lower-lir-opnd dst) (lower-lir-opnd src)))))

      ((%bit-or)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (list (list 'or (lower-lir-opnd dst) (lower-lir-opnd src)))))

      ((%bit-xor)
       (let ((dst (cadr inst))
             (src (caddr inst)))
         (list (list 'xor (lower-lir-opnd dst) (lower-lir-opnd src)))))

      ((%cmp %raw-cmp)
       (let ((s1 (cadr inst))
             (s2 (caddr inst)))
         (list (list 'cmp (lower-lir-opnd s1) (lower-lir-opnd s2)))))

      ((%set-boolean)
       (let ((cc (caddr inst)))
         (list (list '%raw-asm (string-append "    " cc " al"))
               (list '%raw-asm "    movzx eax, al")
               (list '%raw-asm "    shl rax, 6")
               (list '%raw-asm "    add rax, 0x2F"))))

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
            (list (list '%raw-asm (string-append "    lea " (operand->str dst) ", [r12 + " (number->string tag) "]"))
                  (list '%raw-asm (string-append "    add r12, " (number->string bytes)))
                  (list '%raw-asm "    cmp r12, [rip + ulisp_heap_limit]")
                  (list '%raw-asm "    ja ulisp_oom_panic")))
           ((eq? (car *backend-gc-mode*) 'stress)
            (list (list '%raw-asm (string-append "    sub rsp, " (number->string shift)))
                  (list '%raw-asm "    call ulisp_alloc_slow_trampoline")
                  (list '%raw-asm (string-append "    add rsp, " (number->string shift)))
                  (list '%raw-asm (string-append "    lea " (operand->str dst) ", [r12 + " (number->string tag) "]"))
                  (list '%raw-asm (string-append "    add r12, " (number->string bytes)))
                  (list '%raw-asm "    cmp r12, [rip + ulisp_heap_limit]")
                  (list '%raw-asm "    ja ulisp_oom_panic")))
           (else
            (let ((lbl-fast (string-append ".L_alloc_fast_" (number->string (new-alloc-id!))))
                  (lbl-slow (string-append ".L_alloc_slow_" (number->string (car *alloc-counter*)))))
              (list (list '%raw-asm "    cmp byte ptr [rip + ulisp_gc_stress_mode], 0")
                    (list '%raw-asm (string-append "    jne " lbl-slow))
                    (list '%raw-asm (string-append "    lea r11, [r12 + " (number->string bytes) "]"))
                    (list '%raw-asm "    cmp r11, [rip + ulisp_heap_limit]")
                    (list '%raw-asm (string-append "    jbe " lbl-fast))
                    (list '%raw-asm (string-append lbl-slow ":"))
                    (list '%raw-asm (string-append "    sub rsp, " (number->string shift)))
                    (list '%raw-asm "    call ulisp_alloc_slow_trampoline")
                    (list '%raw-asm (string-append "    add rsp, " (number->string shift)))
                    (list '%raw-asm (string-append lbl-fast ":"))
                    (list '%raw-asm (string-append "    lea " (operand->str dst) ", [r12 + " (number->string tag) "]"))
                    (list '%raw-asm (string-append "    add r12, " (number->string bytes)))
                    (list '%raw-asm "    cmp r12, [rip + ulisp_heap_limit]")
                    (list '%raw-asm "    ja ulisp_oom_panic")))))))

      ((%alloc-stack)
       (let ((dst (cadr inst))
             (offset (caddr inst))
             (tag (cadddr inst)))
         (let ((disp (+ offset tag)))
           (if (>= disp 0)
               (list (list '%raw-asm (string-append "    lea " (operand->str dst) ", [rsp + " (number->string disp) "]")))
               (list (list '%raw-asm (string-append "    lea " (operand->str dst) ", [rsp - " (number->string (- 0 disp)) "]")))))))

      ((%code-ref)
       (let ((dst (cadr inst))
             (lbl (caddr inst)))
         (let ((lbl-str (if (symbol? lbl) (symbol->string lbl) lbl)))
           (list (list '%raw-asm (string-append "    lea " (operand->str dst) ", [rip + " lbl-str "]"))))))

      ((%str-ref)
       (let ((dst (cadr inst))
             (lbl (caddr inst)))
         (let ((lbl-str (if (symbol? lbl) (symbol->string lbl) lbl)))
           (list (list '%raw-asm (string-append "    lea " (operand->str dst) ", [rip + " lbl-str "]"))
                 (list '%raw-asm (string-append "    add " (operand->str dst) ", 3"))))))

      ((%c-call)
       (let ((func (cadr inst))
             (frame-shift (caddr inst)))
         (let ((fname (if (symbol? func) (symbol->raw-name func) func)))
           (list (list '%raw-asm (string-append "    sub rsp, " (number->string frame-shift)))
                 (list '%raw-asm (string-append "    call " fname))
                 (list '%raw-asm (string-append "    add rsp, " (number->string frame-shift)))))))

      ((%call-closure)
       (let ((frame-shift (cadr inst))
             (safepoint (if (pair? (cddr inst)) (caddr inst) #f)))
         (backend-concat
          (list (if (> frame-shift 0)
                    (list (list '%raw-asm (string-append "    sub rsp, " (number->string frame-shift))))
                    '())
                (list (list '%raw-asm "    mov rdx, [r10 - 1]")
                      (list '%raw-asm "    call rdx"))
                (if safepoint
                    (list (list '%raw-asm (string-append (if (symbol? safepoint) (symbol->string safepoint) safepoint) ":")))
                    '())
                (if (> frame-shift 0)
                    (list (list '%raw-asm (string-append "    add rsp, " (number->string frame-shift))))
                    '())))))

      ((%direct-call)
       (let ((label (cadr inst))
             (frame-shift (caddr inst))
             (safepoint (if (pair? (cdddr inst)) (cadddr inst) #f)))
         (let ((lbl-str (if (symbol? label) (symbol->string label) label)))
           (backend-concat
            (list (if (> frame-shift 0)
                      (list (list '%raw-asm (string-append "    sub rsp, " (number->string frame-shift))))
                      '())
                  (list (list '%raw-asm "    xor r10, r10")
                        (list '%raw-asm (string-append "    call " lbl-str)))
                  (if safepoint
                      (list (list '%raw-asm (string-append (if (symbol? safepoint) (symbol->string safepoint) safepoint) ":")))
                      '())
                  (if (> frame-shift 0)
                      (list (list '%raw-asm (string-append "    add rsp, " (number->string frame-shift))))
                      '()))))))

      ((%direct-jump)
       (let ((label (cadr inst)))
         (list (list '%raw-asm "    xor r10, r10")
               (list '%raw-asm (string-append "    jmp " (if (symbol? label) (symbol->string label) label))))))

      ((%global-ref)
       (let ((reg (cadr inst))
             (var (caddr inst)))
         (let ((g-lbl (string-append "ulisp_gvar_" (sanitize-label-str (symbol->string var)))))
           (list (list '%raw-asm (string-append "    lea r11, [rip + " g-lbl "]"))
                 (list '%raw-asm (string-append "    mov " (reg->str reg) ", [r11]"))))))

      ((%global-set!)
       (let ((var (cadr inst))
             (reg (caddr inst)))
         (let ((g-lbl (string-append "ulisp_gvar_" (sanitize-label-str (symbol->string var)))))
           (list (list '%raw-asm (string-append "    lea r11, [rip + " g-lbl "]"))
                 (list '%raw-asm (string-append "    mov [r11], " (reg->str reg)))))))

      ((%push-handler)
       (let ((catch-lbl (cadr inst))
             (frame-si (caddr inst))
             (handler-si (cadddr inst)))
         (let ((lbl-str (if (symbol? catch-lbl) (symbol->string catch-lbl) catch-lbl)))
           (list (list '%raw-asm (string-append "    lea rax, [rip + " lbl-str "]"))
                 (list '%raw-asm (string-append "    mov [rsp " (offset->string (+ frame-si 24)) "], rax"))
                 (list '%raw-asm "    lea rdx, [rip + ulisp_handler_chain]")
                 (list '%raw-asm "    mov rcx, [rdx]")
                 (list '%raw-asm (string-append "    mov [rsp " (offset->string frame-si) "], rcx"))
                 (list '%raw-asm (string-append "    mov [rsp " (offset->string (+ frame-si 8)) "], rsp"))
                 (list '%raw-asm (string-append "    mov [rsp " (offset->string (+ frame-si 16)) "], rbp"))
                 (list '%raw-asm (string-append "    mov rax, [rsp " (offset->string handler-si) "]"))
                 (list '%raw-asm (string-append "    mov [rsp " (offset->string (+ frame-si 32)) "], rax"))
                 (list '%raw-asm (string-append "    lea rax, [rsp " (offset->string frame-si) "]"))
                 (list '%raw-asm "    mov [rdx], rax")))))

      ((%pop-handler)
       (let ((frame-si (cadr inst)))
         (list (list '%raw-asm "    lea rdx, [rip + ulisp_handler_chain]")
               (list '%raw-asm (string-append "    mov rcx, [rsp " (offset->string frame-si) "]"))
               (list '%raw-asm "    mov [rdx], rcx"))))

      ((%raise)
       (list (list '%raw-asm "    lea rdx, [rip + ulisp_handler_chain]")
             (list '%raw-asm "    mov rbx, [rdx]")
             (list '%raw-asm "    test rbx, rbx")
             (list '%raw-asm "    jz .L_unhandled_exn")
             (list '%raw-asm "    mov rcx, [rbx]")
             (list '%raw-asm "    mov [rdx], rcx")
             (list '%raw-asm "    mov rdi, rax")
             (list '%raw-asm "    mov rsp, [rbx + 8]")
             (list '%raw-asm "    mov rbp, [rbx + 16]")
             (list '%raw-asm "    mov r10, [rbx + 24]")
             (list '%raw-asm "    mov rax, [rbx + 32]")
             (list '%raw-asm "    jmp r10")))

      ((%set-values-count)
       (let ((cnt (cadr inst)))
         (list (list '%raw-asm "    lea rdx, [rip + ulisp_values_count]")
               (list '%raw-asm (string-append "    mov qword ptr [rdx], " (number->string cnt))))))

      ((%store-values-buf)
       (let ((base-si (cadr inst))
             (count (caddr inst)))
         (let loop ((i 0) (acc (list (list '%raw-asm "    lea rbx, [rip + ulisp_values_buf]"))))
           (if (< i count)
               (let ((offset (+ base-si (* -8 i)))
                     (buf-disp (* 8 i)))
                 (loop (+ i 1)
                       (cons (list '%raw-asm (string-append "    mov [rbx + " (number->string buf-disp) "], rax"))
                             (cons (list '%raw-asm (string-append "    mov rax, [rsp " (offset->string offset) "]"))
                                   acc))))
               (reverse acc)))))

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
         (let ((sub-shift (if (> frame-shift 0) (list (list '%raw-asm (string-append "    sub rsp, " (number->string frame-shift)))) '()))
               (add-shift (if (> frame-shift 0) (list (list '%raw-asm (string-append "    add rsp, " (number->string frame-shift)))) '())))
           (backend-concat
            (list
             (list (list '%raw-asm "    lea rdx, [rip + ulisp_values_count]")
                  (list '%raw-asm "    mov rcx, [rdx]")
                  (list '%raw-asm "    mov qword ptr [rdx], 1")
                  (list '%raw-asm (string-append "    mov r10, [rsp " (offset->string consumer-si) "]"))
                  (list '%raw-asm "    lea rbx, [rip + ulisp_values_buf]")
                  (list '%raw-asm "    cmp rcx, 1")
                  (list '%raw-asm (string-append "    je " (symbol->string call-1-lbl)))
                  (list '%raw-asm "    cmp rcx, 2")
                  (list '%raw-asm (string-append "    je " (symbol->string call-2-lbl)))
                  (list '%raw-asm "    cmp rcx, 0")
                  (list '%raw-asm (string-append "    je " (symbol->string call-0-lbl)))
                  (list '%raw-asm "    cmp rcx, 3")
                  (list '%raw-asm (string-append "    je " (symbol->string call-3-lbl)))
                  (list '%raw-asm "    cmp rcx, 4")
                  (list '%raw-asm (string-append "    je " (symbol->string call-4-lbl)))
                  ;; 0 args
                  (list '%raw-asm (string-append (symbol->string call-0-lbl) ":")))
            sub-shift
            (list (list '%raw-asm "    mov rdx, [r10 - 1]")
                  (list '%raw-asm "    mov rax, 0")
                  (list '%raw-asm "    call rdx"))
            add-shift
            (list (list '%raw-asm (string-append "    jmp " exit-str))
                  ;; 1 arg
                  (list '%raw-asm (string-append (symbol->string call-1-lbl) ":"))
                  (list '%raw-asm (string-append "    mov [rsp " (offset->string aligned-si) "], rax")))
            sub-shift
            (list (list '%raw-asm "    mov rdx, [r10 - 1]")
                  (list '%raw-asm "    mov rax, 4")
                  (list '%raw-asm "    call rdx"))
            add-shift
            (list (list '%raw-asm (string-append "    jmp " exit-str))
                  ;; 2 args
                  (list '%raw-asm (string-append (symbol->string call-2-lbl) ":"))
                  (list '%raw-asm "    mov rax, [rbx]")
                  (list '%raw-asm (string-append "    mov [rsp " (offset->string (+ aligned-si 8)) "], rax"))
                  (list '%raw-asm "    mov rax, [rbx + 8]")
                  (list '%raw-asm (string-append "    mov [rsp " (offset->string aligned-si) "], rax")))
            sub-shift
            (list (list '%raw-asm "    mov rdx, [r10 - 1]")
                  (list '%raw-asm "    mov rax, 8")
                  (list '%raw-asm "    call rdx"))
            add-shift
            (list (list '%raw-asm (string-append "    jmp " exit-str))
                  ;; 3 args
                  (list '%raw-asm (string-append (symbol->string call-3-lbl) ":"))
                  (list '%raw-asm "    mov rax, [rbx]")
                  (list '%raw-asm (string-append "    mov [rsp " (offset->string (+ aligned-si 16)) "], rax"))
                  (list '%raw-asm "    mov rax, [rbx + 8]")
                  (list '%raw-asm (string-append "    mov [rsp " (offset->string (+ aligned-si 8)) "], rax"))
                  (list '%raw-asm "    mov rax, [rbx + 16]")
                  (list '%raw-asm (string-append "    mov [rsp " (offset->string aligned-si) "], rax")))
            sub-shift
            (list (list '%raw-asm "    mov rdx, [r10 - 1]")
                  (list '%raw-asm "    mov rax, 12")
                  (list '%raw-asm "    call rdx"))
            add-shift
            (list (list '%raw-asm (string-append "    jmp " exit-str))
                  ;; 4 args
                  (list '%raw-asm (string-append (symbol->string call-4-lbl) ":"))
                  (list '%raw-asm "    mov rax, [rbx]")
                  (list '%raw-asm (string-append "    mov [rsp " (offset->string (+ aligned-si 24)) "], rax"))
                  (list '%raw-asm "    mov rax, [rbx + 8]")
                  (list '%raw-asm (string-append "    mov [rsp " (offset->string (+ aligned-si 16)) "], rax"))
                  (list '%raw-asm "    mov rax, [rbx + 16]")
                  (list '%raw-asm (string-append "    mov [rsp " (offset->string (+ aligned-si 8)) "], rax"))
                  (list '%raw-asm "    mov rax, [rbx + 24]")
                  (list '%raw-asm (string-append "    mov [rsp " (offset->string aligned-si) "], rax")))
            sub-shift
            (list (list '%raw-asm "    mov rdx, [r10 - 1]")
                  (list '%raw-asm "    mov rax, 16")
                  (list '%raw-asm "    call rdx"))
            add-shift
            (list (list '%raw-asm (string-append "    jmp " exit-str))
                  (list '%raw-asm (string-append exit-str ":"))))))))

      ((%capture-cc)
       (let* ((ret-lbl (cadr inst))
              (k-si (caddr inst))
              (lbl-str (if (symbol? ret-lbl) (symbol->string ret-lbl) ret-lbl)))
         (list (list '%raw-asm "    lea rcx, [rip + ulisp_stack_base]")
               (list '%raw-asm "    mov rcx, [rcx]")
               (list '%raw-asm "    sub rcx, rsp")
               (list '%raw-asm "    test rcx, rcx")
               (list '%raw-asm "    jle .L_cap_fallback_size")
               (list '%raw-asm "    cmp rcx, 8388608")
               (list '%raw-asm "    jbe .L_cap_size_ok")
               (list '%raw-asm ".L_cap_fallback_size:")
               (list '%raw-asm "    mov rcx, 65536")
               (list '%raw-asm ".L_cap_size_ok:")
               (list '%raw-asm "    mov r8, rcx")
               (list '%raw-asm "    add r8, 111")
               (list '%raw-asm "    and r8, -16")
               (list '%raw-asm "    mov rax, r12")
               (list '%raw-asm "    add r12, r8")
               (list '%raw-asm "    lea r9, [rip + ulisp_continuation_invoke]")
               (list '%raw-asm "    mov [rax], r9")
               (list '%raw-asm "    mov [rax + 8], rcx")
               (list '%raw-asm "    mov [rax + 16], rsp")
               (list '%raw-asm "    mov [rax + 24], rbp")
               (list '%raw-asm "    mov [rax + 32], rbx")
               (list '%raw-asm "    mov [rax + 40], r12")
               (list '%raw-asm "    mov [rax + 48], r13")
               (list '%raw-asm "    mov [rax + 56], r14")
               (list '%raw-asm "    mov [rax + 64], r15")
               (list '%raw-asm (string-append "    lea r9, [rip + " lbl-str "]"))
               (list '%raw-asm "    mov [rax + 72], r9")
               (list '%raw-asm "    lea r9, [rip + ulisp_handler_chain]")
               (list '%raw-asm "    mov r8, [r9]")
               (list '%raw-asm "    mov [rax + 80], r8")
               (list '%raw-asm "    lea rdx, [rax + 1]")
               (list '%raw-asm (string-append "    mov [rsp " (offset->string k-si) "], rdx"))
               (list '%raw-asm "    lea rdi, [rax + 96]")
               (list '%raw-asm "    mov rsi, rsp")
               (list '%raw-asm "    cld")
               (list '%raw-asm "    rep movsb")
               (list '%raw-asm "    mov rax, rdx"))))

      (else
       (error (string-append "Unknown LIR opcode in x86-64 backend: "
                             (if (symbol? (car inst)) (symbol->string (car inst)) "?"))
              inst)))))

(define (select-instructions-function fn)
  (let* ((label (cadr fn))
         (frame-size-entry (assq 'frame-size (cddr fn)))
         (frame-size (if frame-size-entry (cadr frame-size-entry) 0))
         (body (cdr (assq 'body (cddr fn)))))
    (scan-x86-blocks! body)
    (let loop ((rest body) (acc (list (list 'mov (list '%disp -8 'rsp) 'r10)
                                      (list '%label label)
                                      (list '%p2align 4))))
      (if (null? rest)
          (list '%asm-function label (list 'frame-size frame-size) (cons 'body (reverse acc)))
          (let ((lowered (lower-lir-instruction (car rest))))
            (loop (cdr rest) (append (reverse lowered) acc)))))))

(define (select-instructions-main main-clause)
  (let* ((frame-size-entry (assq 'frame-size (cdr main-clause)))
         (frame-size (if frame-size-entry (cadr frame-size-entry) 0))
         (main-body (cdr (assq 'body (cdr main-clause)))))
    (scan-x86-blocks! main-body)
    (let loop ((rest main-body) (acc '()))
      (if (null? rest)
          (list '%asm-main
                (list 'frame-size frame-size)
                (cons 'body (append (reverse acc)
                                    (list (list 'add 'rsp 8)
                                          (list 'pop 'r12)
                                          (list 'ret)))))
          (let ((inst (car rest)))
            (if (eq? (car inst) '%return)
                (loop (cdr rest) acc)
                (let ((lowered (lower-lir-instruction inst)))
                  (loop (cdr rest) (append (reverse lowered) acc)))))))))

(define (select-instructions-x86 prog)
  (let* ((strings (assq 'strings (cdr prog)))
         (stackmaps (assq 'stackmaps (cdr prog)))
         (funcs-clause (assq '%lir-functions (cdr prog)))
         (funcs (if funcs-clause (cdr funcs-clause) '()))
         (main-clause (assq '%lir-main (cdr prog))))
    (list '%asm-program
          (if strings strings '(strings ()))
          (if stackmaps stackmaps '(stackmaps ()))
          (cons '%asm-functions (map select-instructions-function funcs))
          (select-instructions-main main-clause))))

;;; -----------------------------------------------------------------------
;;; Stage 2: Code Emission (L_asm_x86 AST -> GNU x86-64 Intel Syntax)
;;; -----------------------------------------------------------------------

(define (emit-x86-asm-inst inst)
  (let ((op (car inst)))
    (case op
      ((%label)
       (let ((lbl (cadr inst)))
         (emit (string-append (if (symbol? lbl) (symbol->string lbl) lbl) ":"))))
      ((%p2align)
       (emit (string-append "    .p2align " (number->string (cadr inst)))))
      ((%align)
       (emit (string-append "    .align " (number->string (cadr inst)))))
      ((%raw-asm)
       (emit (cadr inst)))
      ((mov)
       (emit (string-append "    mov " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((movzx)
       (emit (string-append "    movzx " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((lea)
       (emit (string-append "    lea " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((add)
       (emit (string-append "    add " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((sub)
       (emit (string-append "    sub " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((imul)
       (emit (string-append "    imul " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((and)
       (emit (string-append "    and " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((or)
       (emit (string-append "    or " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((xor)
       (emit (string-append "    xor " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((shl)
       (emit (string-append "    shl " (asm-opnd->str (cadr inst)) ", " (number->string (caddr inst)))))
      ((shr)
       (emit (string-append "    shr " (asm-opnd->str (cadr inst)) ", " (number->string (caddr inst)))))
      ((sar)
       (emit (string-append "    sar " (asm-opnd->str (cadr inst)) ", " (number->string (caddr inst)))))
      ((neg)
       (emit (string-append "    neg " (asm-opnd->str (cadr inst)))))
      ((not)
       (emit (string-append "    not " (asm-opnd->str (cadr inst)))))
      ((cmp)
       (emit (string-append "    cmp " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((test)
       (emit (string-append "    test " (asm-opnd->str (cadr inst)) ", " (asm-opnd->str (caddr inst)))))
      ((set)
       (let ((cc (cadr inst))
             (dst (caddr inst)))
         (emit (string-append "    set" (if (symbol? cc) (symbol->string cc) cc) " " (asm-opnd->str dst)))))
      ((jmp)
       (emit (string-append "    jmp " (asm-opnd->str (cadr inst)))))
      ((jcc)
       (let ((cc (cadr inst))
             (lbl (caddr inst)))
         (emit (string-append "    " (if (symbol? cc) (symbol->string cc) cc) " " (asm-opnd->str lbl)))))
      ((call)
       (emit (string-append "    call " (asm-opnd->str (cadr inst)))))
      ((ret)
       (emit "    ret"))
      ((push)
       (emit (string-append "    push " (asm-opnd->str (cadr inst)))))
      ((pop)
       (emit (string-append "    pop " (asm-opnd->str (cadr inst)))))
      ((cqo)
       (emit "    cqo"))
      ((idiv)
       (emit (string-append "    idiv " (asm-opnd->str (cadr inst)))))
      ((inc)
       (emit (string-append "    inc " (asm-opnd->str (cadr inst)))))
      ((syscall)
       (emit "    syscall"))
      ((cld)
       (emit "    cld"))
      ((rep-movsb)
       (emit "    rep movsb"))
      (else
       (error "Unknown x86 assembly instruction:" inst)))))

(define (emit-lir-instruction inst)
  (for-each emit-x86-asm-inst (lower-lir-instruction inst)))

(define (emit-x86-function fn)
  (let* ((label (cadr fn))
         (label-str (if (symbol? label) (symbol->string label) label))
         (body (cdr (assq 'body (cddr fn)))))
    (scan-x86-blocks! body)
    (emit "    .p2align 4")
    (emit (string-append label-str ":"))
    (emit "    mov [rsp - 8], r10")
    (for-each emit-lir-instruction body)))

(define (emit-x86-asm-function fn)
  (let* ((body-entry (assq 'body (cddr fn)))
         (body (if body-entry (cdr body-entry) '())))
    (for-each emit-x86-asm-inst body)))

(define (emit-x86-asm-program asm-prog gc-mode)
  (let* ((funcs-clause (assq '%asm-functions (cdr asm-prog)))
         (funcs (if funcs-clause (cdr funcs-clause) '()))
         (main-clause (assq '%asm-main (cdr asm-prog)))
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
    ;; Scan env var ULISP_QUIET
    (emit "    mov rcx, [rbp]")                 ; argc
    (emit "    lea rdx, [rbp + 16]")            ; &argv[0]
    (emit "    lea rdx, [rdx + rcx*8]")         ; past argv NULL -> envp
    (emit ".L_quiet_scan_loop:")
    (emit "    mov rsi, [rdx]")
    (emit "    test rsi, rsi")
    (emit "    jz .L_quiet_scan_done")
    (emit "    add rdx, 8")
    ;; Check prefix "ULISP_QUIET=" (12 chars: 8 bytes + 4 bytes)
    (emit "    mov rax, [rsi]")
    (emit "    mov r8, [rip + .L_str_env_quiet]")
    (emit "    cmp rax, r8")
    (emit "    jne .L_quiet_scan_loop")
    (emit "    mov eax, [rsi + 8]")
    (emit "    mov r8d, [rip + .L_str_env_quiet + 8]")
    (emit "    cmp eax, r8d")
    (emit "    jne .L_quiet_scan_loop")
    ;; Matched "ULISP_QUIET="
    (emit "    cmp byte ptr [rsi + 12], 0")
    (emit "    je .L_quiet_scan_loop")
    (emit "    cmp byte ptr [rsi + 12], '0'")
    (emit "    je .L_quiet_scan_loop")
    (emit "    lea rax, [rip + ulisp_quiet_mode]")
    (emit "    mov byte ptr [rax], 1")
    (emit ".L_quiet_scan_done:")
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
       (emit "    mov qword ptr [rbx + 88], 0")    ; gen_mode = 0 (0: dual-space, 1: generational)
       (emit "    mov qword ptr [rbx + 112], 4")   ; profile_id = 4 (stress)
       (emit "    mov qword ptr [rbx + 128], 1")   ; stress_mode = 1
       (emit "    lea rdx, [rip + ulisp_heap_limit]")
       (emit "    mov [rdx], rcx"))
      (else
       ;; Generational Collector initialization (Pass 141)
       (emit "    mov rax, 9")                     ; sys_mmap
       (emit "    xor rdi, rdi")                   ; addr = NULL
       (emit "    mov rsi, 2147483648")            ; 2GB total address space reservation
       (emit "    mov rdx, 3")                     ; PROT_READ|PROT_WRITE
       (emit "    mov r10, 34")                    ; MAP_PRIVATE|MAP_ANONYMOUS
       (emit "    mov r8, -1")                     ; fd = -1
       (emit "    xor r9, r9")                     ; offset = 0
       (emit "    syscall")
       (emit "    test rax, rax")
       (emit "    js .L_start_exit")
       (emit "    lea rbx, [rip + ulisp_gc_state]")
       ;; Scan env var ULISP_GC_PROFILE (Pass 141 Profile Detection)
       (emit "    mov rcx, [rbp]")                 ; argc
       (emit "    lea rdx, [rbp + 16]")            ; &argv[0]
       (emit "    lea rdx, [rdx + rcx*8]")         ; past argv NULL -> envp
       (emit "    xor r10, r10")                   ; r10 = profile_id (0: standard, 1: compiler, 2: server, 4: stress)
       (emit ".L_env_scan_loop:")
       (emit "    mov rsi, [rdx]")
       (emit "    test rsi, rsi")
       (emit "    jz .L_env_scan_done")
       (emit "    add rdx, 8")
       ;; Check prefix "ULISP_GC_PROFILE=" (17 chars)
       (emit "    mov rax, [rsi]")
       (emit "    mov r8, 0x435f5053494c55")       ; "ULISP_C" (reversed little-endian prefix)
       (emit "    mov r8, [rip + .L_str_env_prefix]")
       (emit "    cmp rax, r8")
       (emit "    jne .L_env_scan_loop")
       (emit "    mov rax, [rsi + 8]")
       (emit "    mov r8, [rip + .L_str_env_prefix + 8]")
       (emit "    cmp rax, r8")
       (emit "    jne .L_env_scan_loop")
       (emit "    mov al, [rsi + 16]")
       (emit "    cmp al, 61")                     ; '='
       (emit "    jne .L_env_scan_loop")
       ;; Match profile value
       (emit "    mov al, [rsi + 17]")
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
       (emit "    mov rsi, 134217728")             ; total = 128MB
       (emit "    jmp .L_gc_state_stress_setup")
       ;; Compiler Profile (16MB Nursery, 256MB Mature, 2GB Max)
       (emit ".L_profile_compiler:")
       (emit "    mov r12, 16777216")              ; nursery_size = 16MB
       (emit "    mov r13, 268435456")             ; mature_size = 256MB
       (emit "    mov rsi, 553648128")             ; total_mmap = ~528MB
       (emit "    mov r8, 2147483648")             ; max_mature = 2GB
       (emit "    mov r10, 1")                     ; profile_id = 1
       (emit "    jmp .L_profile_setup")
       ;; Server Profile (32MB Nursery, 512MB Mature, 4GB Max)
       (emit ".L_profile_server:")
       (emit "    mov r12, 33554432")              ; nursery_size = 32MB
       (emit "    mov r13, 536870912")             ; mature_size = 512MB
       (emit "    mov rsi, 1107296256")            ; total_mmap = ~1056MB
       (emit "    mov r8, 4294967296")             ; max_mature = 4GB
       (emit "    mov r10, 2")                     ; profile_id = 2
       (emit ".L_profile_setup:")
       (emit "    mov [rbx + 0], rax")             ; nursery_base
       (emit "    mov [rbx + 8], r12")             ; nursery_size
       (emit "    lea rdx, [rax + r12]")
       (emit "    mov [rbx + 16], rdx")            ; mature_base
       (emit "    mov [rbx + 24], r13")            ; mature_size
       (emit "    mov [rbx + 32], rdx")            ; mature_to = mature_base
       (emit "    lea rcx, [rdx + r13]")
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
    (emit "    lea rax, [rip + ulisp_quiet_mode]")
    (emit "    cmp byte ptr [rax], 0")
    (emit "    jne .L_start_exit")
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
    ;; Emit main body instructions
    (for-each emit-x86-asm-inst main-body)
    ;; Emit all lifted procedure definitions in sequence
    (for-each emit-x86-asm-function funcs)
    ;; Emit freestanding zero-libc runtime routines
    (emit-freestanding-runtime)
    (emit-oom-panic)
    ;; Emit GC routines unless disabled
    (cond
      ((eq? gc-mode 'none) #f)
      (else
       (emit-gc-collector)))
    ;; Emit stackmap metadata table in .rodata section
    (let* ((stackmaps-clause (assq 'stackmaps (cdr asm-prog)))
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
    (emit "    .section .rodata")
    (emit "    .align 8")
    (emit ".L_str_env_prefix:")
    (emit "    .ascii \"ULISP_GC_PROFILE=\"")
    (emit "    .align 8")
    (emit ".L_str_env_quiet:")
    (emit "    .ascii \"ULISP_QUIET=\"")
    (emit "    .section .data")
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
    (emit "    .globl ulisp_quiet_mode")
    (emit "    .type ulisp_quiet_mode, @object")
    (emit "ulisp_quiet_mode:")
    (emit "    .byte 0")
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

;;; -----------------------------------------------------------------------
;;; Pass 140 Entrypoint: Pipeline from LIR to Optimized x86 Assembly
;;; -----------------------------------------------------------------------

(define (emit-x86-64 prog gc-mode)
  (set-car! *backend-gc-mode* gc-mode)
  (set-car! *alloc-counter* 0)
  (let* ((asm-ast (select-instructions-x86 prog))
         (asm-opt (optimize-x86-peephole asm-ast)))
    (emit-x86-asm-program asm-opt gc-mode)
    asm-opt))
