;;; =======================================================================
;;; ULisp Canonical LIR Reference Virtual Machine (vm/lir_interpreter.scm)
;;; 100% Pure Scheme Implementation of Low-Level IR Evaluation Engine
;;; Conforms to DSN-33 §2, DSN-33-02 §7.1, DSN-38 §2 K3, and Issue #834
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; §1. Architecture Constants & 64-Bit Integer Arithmetic
;;; -----------------------------------------------------------------------

(define *lir-vm-mask-8*   #xff)
(define *lir-vm-sign-8*   #x80)
(define *lir-vm-mask-16*  #xffff)
(define *lir-vm-sign-16*  #x8000)
(define *lir-vm-mask-32*  #xffffffff)
(define *lir-vm-sign-32*  #x80000000)
(define *lir-vm-mask-64*  #xffffffffffffffff)
(define *lir-vm-sign-64*  #x8000000000000000)
(define *lir-vm-max-s64*  #x7fffffffffffffff)
(define *lir-vm-min-s64*  (- #x8000000000000000))

(define *lir-vm-default-mem-size* 16777216) ; 16MB linear memory
(define *lir-vm-null-page-limit*  4096)     ; 0..4095 protected NULL page
(define *lir-vm-heap-base*        65536)    ; 64KB heap start
(define *lir-vm-heap-limit*       8388608)  ; 8MB heap upper bound
(define *lir-vm-stack-limit*      8388608)  ; 8MB stack lower bound
(define *lir-vm-default-fuel*     10000000) ; 10M instructions limit

(define (lir-vm-u64 n)
  (bitwise-and n *lir-vm-mask-64*))

(define (lir-vm-s64 n)
  (let ((u (bitwise-and n *lir-vm-mask-64*)))
    (if (>= u *lir-vm-sign-64*)
        (- u (+ *lir-vm-mask-64* 1))
        u)))

(define (lir-vm-u32 n)
  (bitwise-and n *lir-vm-mask-32*))

(define (lir-vm-s32 n)
  (let ((u (bitwise-and n *lir-vm-mask-32*)))
    (if (>= u *lir-vm-sign-32*)
        (- u (+ *lir-vm-mask-32* 1))
        u)))

(define (lir-vm-u16 n)
  (bitwise-and n *lir-vm-mask-16*))

(define (lir-vm-s16 n)
  (let ((u (bitwise-and n *lir-vm-mask-16*)))
    (if (>= u *lir-vm-sign-16*)
        (- u (+ *lir-vm-mask-16* 1))
        u)))

(define (lir-vm-u8 n)
  (bitwise-and n *lir-vm-mask-8*))

(define (lir-vm-s8 n)
  (let ((u (bitwise-and n *lir-vm-mask-8*)))
    (if (>= u *lir-vm-sign-8*)
        (- u (+ *lir-vm-mask-8* 1))
        u)))

;;; -----------------------------------------------------------------------
;;; §2. Virtual Machine Data Structures (<lir-vm> & <vm-trap>)
;;; -----------------------------------------------------------------------

(define-record-type <vm-trap>
  (make-vm-trap type message pc details)
  vm-trap?
  (type vm-trap-type)
  (message vm-trap-message)
  (pc vm-trap-pc)
  (details vm-trap-details))

(define-record-type <lir-vm>
  (make-lir-vm-raw registers xmm-registers vregs flags memory heap-ptr
                   strings functions main-func current-fn current-block
                   pc call-stack status fuel step-count tracer last-trap
                   globals foreign-handlers f64-cells)
  lir-vm?
  (registers vm-registers-vector vm-set-registers-vector!)
  (xmm-registers vm-xmm-vector vm-set-xmm-vector!)
  (vregs vm-vregs-table vm-set-vregs-table!)
  (flags vm-flags-record vm-set-flags-record!)
  (memory vm-memory-bytes vm-set-memory-bytes!)
  (heap-ptr vm-heap-ptr vm-set-heap-ptr!)
  (strings vm-strings-table vm-set-strings-table!)
  (functions vm-functions-table vm-set-functions-table!)
  (main-func vm-main-func vm-set-main-func!)
  (current-fn vm-current-fn vm-set-current-fn!)
  (current-block vm-current-block vm-set-current-block!)
  (pc vm-pc vm-set-pc!)
  (call-stack vm-call-stack vm-set-call-stack!)
  (status vm-status vm-set-status!)
  (fuel vm-fuel vm-set-fuel!)
  (step-count vm-step-count vm-set-step-count!)
  (tracer vm-tracer vm-set-tracer!)
  (last-trap vm-last-trap vm-set-last-trap!)
  (globals vm-globals-table vm-set-globals-table!)
  (foreign-handlers vm-foreign-handlers vm-set-foreign-handlers!)
  (f64-cells vm-f64-cells vm-set-f64-cells!))

;;; Constructor
(define (make-lir-vm-with-size mem-size)
  (let* ((actual-size (if (> mem-size 65536) mem-size *lir-vm-default-mem-size*))
         (mem (make-bytevector actual-size 0))
         (regs (make-vector 16 0))
         (xmms (make-vector 16 0.0))
         (flags (vector 0 0 0 0))) ; #(ZF SF OF CF)
    (make-lir-vm-raw regs xmms '() flags mem
                     *lir-vm-heap-base* '() '() #f
                     '%main '%entry 0 '() 'ready
                     *lir-vm-default-fuel* 0 #f #f '() '() '())))

(define (make-lir-vm)
  (make-lir-vm-with-size *lir-vm-default-mem-size*))

;;; Trap Trigger
(define (vm-trigger-trap! vm type msg details)
  (let ((trap (make-vm-trap type msg (cons (vm-current-fn vm) (vm-pc vm)) details)))
    (vm-set-status! vm 'trapped)
    (vm-set-last-trap! vm trap)
    trap))

;;; -----------------------------------------------------------------------
;;; §3. Register Accessors (GPR, XMM, Virtual Registers)
;;; -----------------------------------------------------------------------

(define (gpr-name->index reg)
  (case reg
    ((%rax) 0)
    ((%rcx) 1)
    ((%rdx) 2)
    ((%rbx) 3)
    ((%rsp) 4)
    ((%rbp) 5)
    ((%rsi) 6)
    ((%rdi) 7)
    ((%r8)  8)
    ((%r9)  9)
    ((%r10) 10)
    ((%r11) 11)
    ((%r12) 12)
    ((%r13) 13)
    ((%r14) 14)
    ((%r15) 15)
    (else #f)))

(define (xmm-name->index reg)
  (case reg
    ((%xmm0)  0)
    ((%xmm1)  1)
    ((%xmm2)  2)
    ((%xmm3)  3)
    ((%xmm4)  4)
    ((%xmm5)  5)
    ((%xmm6)  6)
    ((%xmm7)  7)
    ((%xmm8)  8)
    ((%xmm9)  9)
    ((%xmm10) 10)
    ((%xmm11) 11)
    ((%xmm12) 12)
    ((%xmm13) 13)
    ((%xmm14) 14)
    ((%xmm15) 15)
    (else #f)))

(define (vm-get-reg vm reg)
  (let ((idx (gpr-name->index reg)))
    (if idx
        (vector-ref (vm-registers-vector vm) idx)
        (if (eq? reg '%al)
            (bitwise-and (vector-ref (vm-registers-vector vm) 0) #xff)
            (vm-get-vreg vm reg)))))

(define (vm-set-reg! vm reg val)
  (let ((idx (gpr-name->index reg)))
    (if idx
        (vector-set! (vm-registers-vector vm) idx (lir-vm-s64 val))
        (if (eq? reg '%al)
            (let* ((rax (vector-ref (vm-registers-vector vm) 0))
                   (new-rax (bitwise-ior (bitwise-and rax (bitwise-not #xff))
                                         (bitwise-and val #xff))))
              (vector-set! (vm-registers-vector vm) 0 (lir-vm-s64 new-rax)))
            (vm-set-vreg! vm reg val)))))

(define (vm-get-xmm vm reg)
  (let ((idx (xmm-name->index reg)))
    (if idx
        (vector-ref (vm-xmm-vector vm) idx)
        (vm-get-vreg vm reg))))

(define (vm-set-xmm! vm reg val)
  (let ((idx (xmm-name->index reg)))
    (if idx
        (vector-set! (vm-xmm-vector vm) idx (if (number? val) (exact->inexact val) 0.0))
        (vm-set-vreg vm reg val))))

(define (vm-get-vreg vm key)
  (let ((entry (assq key (vm-vregs-table vm))))
    (if entry (cdr entry) 0)))

(define (vm-set-vreg! vm key val)
  (let ((entry (assq key (vm-vregs-table vm))))
    (if entry
        (set-cdr! entry val)
        (vm-set-vregs-table! vm (cons (cons key val) (vm-vregs-table vm))))))

;;; Global variables (%global-ref / %global-set!)
(define (vm-lookup-global vm key)
  (let ((entry (assq key (vm-globals-table vm))))
    (if entry (cdr entry) #f)))

(define (vm-set-global! vm key val)
  (let ((entry (assq key (vm-globals-table vm))))
    (if entry
        (set-cdr! entry val)
        (vm-set-globals-table! vm (cons (cons key val) (vm-globals-table vm))))))

;;; Condition flags accessors
(define (vm-flag-zf vm) (vector-ref (vm-flags-record vm) 0))
(define (vm-flag-sf vm) (vector-ref (vm-flags-record vm) 1))
(define (vm-flag-of vm) (vector-ref (vm-flags-record vm) 2))
(define (vm-flag-cf vm) (vector-ref (vm-flags-record vm) 3))

(define (vm-set-flags! vm zf sf of cf)
  (let ((vec (vm-flags-record vm)))
    (vector-set! vec 0 zf)
    (vector-set! vec 1 sf)
    (vector-set! vec 2 of)
    (vector-set! vec 3 cf)))

;;; -----------------------------------------------------------------------
;;; §4. Memory Accessors & Little-Endian Integer Encoding (THREAT-834-1)
;;; -----------------------------------------------------------------------

(define (vm-mem-read-u8 vm addr)
  (let ((mem (vm-memory-bytes vm)))
    (if (or (< addr *lir-vm-null-page-limit*)
            (>= addr (bytevector-length mem)))
        (begin
          (vm-trigger-trap! vm 'out-of-bounds "Memory read out of bounds" addr)
          0)
        (bytevector-u8-ref mem addr))))

(define (vm-mem-write-u8! vm addr val)
  (let ((mem (vm-memory-bytes vm)))
    (if (or (< addr *lir-vm-null-page-limit*)
            (>= addr (bytevector-length mem)))
        (vm-trigger-trap! vm 'out-of-bounds "Memory write out of bounds" addr)
        (bytevector-u8-set! mem addr (lir-vm-u8 val)))))

(define (vm-mem-read-i8 vm addr)
  (lir-vm-s8 (vm-mem-read-u8 vm addr)))

(define (vm-mem-write-i8! vm addr val)
  (vm-mem-write-u8! vm addr (lir-vm-u8 val)))

(define (vm-mem-read-u16 vm addr)
  (let ((b0 (vm-mem-read-u8 vm addr))
        (b1 (vm-mem-read-u8 vm (+ addr 1))))
    (+ b0 (* b1 256))))

(define (vm-mem-read-i16 vm addr)
  (lir-vm-s16 (vm-mem-read-u16 vm addr)))

(define (vm-mem-write-u16! vm addr val)
  (let ((u (lir-vm-u16 val)))
    (vm-mem-write-u8! vm addr (bitwise-and u #xff))
    (vm-mem-write-u8! vm (+ addr 1) (bitwise-and (quotient u 256) #xff))))

(define (vm-mem-write-i16! vm addr val)
  (vm-mem-write-u16! vm addr (lir-vm-u16 val)))

(define (vm-mem-read-u32 vm addr)
  (let ((b0 (vm-mem-read-u8 vm addr))
        (b1 (vm-mem-read-u8 vm (+ addr 1)))
        (b2 (vm-mem-read-u8 vm (+ addr 2)))
        (b3 (vm-mem-read-u8 vm (+ addr 3))))
    (+ b0 (* b1 256) (* b2 65536) (* b3 16777216))))

(define (vm-mem-read-i32 vm addr)
  (lir-vm-s32 (vm-mem-read-u32 vm addr)))

(define (vm-mem-write-u32! vm addr val)
  (let ((u (lir-vm-u32 val)))
    (vm-mem-write-u8! vm addr (bitwise-and u #xff))
    (vm-mem-write-u8! vm (+ addr 1) (bitwise-and (quotient u 256) #xff))
    (vm-mem-write-u8! vm (+ addr 2) (bitwise-and (quotient u 65536) #xff))
    (vm-mem-write-u8! vm (+ addr 3) (bitwise-and (quotient u 16777216) #xff))))

(define (vm-mem-write-i32! vm addr val)
  (vm-mem-write-u32! vm addr (lir-vm-u32 val)))

(define (vm-mem-read-u64 vm addr)
  (let ((low (vm-mem-read-u32 vm addr))
        (high (vm-mem-read-u32 vm (+ addr 4))))
    (+ low (* high 4294967296))))

(define (vm-mem-read-i64 vm addr)
  (lir-vm-s64 (vm-mem-read-u64 vm addr)))

(define (vm-mem-write-u64! vm addr val)
  (let* ((u (lir-vm-u64 val))
         (low (bitwise-and u *lir-vm-mask-32*))
         (high (bitwise-and (quotient u 4294967296) *lir-vm-mask-32*)))
    (vm-mem-write-u32! vm addr low)
    (vm-mem-write-u32! vm (+ addr 4) high)))

(define (vm-mem-write-i64! vm addr val)
  (vm-mem-write-u64! vm addr (lir-vm-u64 val)))

;;; Float Memory Access (F64 Cells)
(define (vm-mem-read-f64 vm addr)
  (let ((entry (assv addr (vm-f64-cells vm))))
    (if entry
        (cdr entry)
        (exact->inexact (vm-mem-read-i64 vm addr)))))

(define (vm-mem-write-f64! vm addr val)
  (let ((flt (if (number? val) (exact->inexact val) 0.0)))
    (let ((entry (assv addr (vm-f64-cells vm))))
      (if entry
          (set-cdr! entry flt)
          (vm-set-f64-cells! vm (cons (cons addr flt) (vm-f64-cells vm)))))
    ;; Also mirror in linear memory integer representation
    (vm-mem-write-i64! vm addr (exact (truncate flt)))))

;;; -----------------------------------------------------------------------
;;; §5. Operand Evaluation & SIB Address Calculation
;;; -----------------------------------------------------------------------

(define (vm-lookup-string vm key)
  (let ((entry (assq key (vm-strings-table vm))))
    (if entry (cdr entry) #f)))

(define (vm-eval-sib vm sib)
  (let* ((idx-reg (cadr sib))
         (scale (caddr sib))
         (disp (cadddr sib))
         (idx-val (vm-eval-operand vm idx-reg)))
    (+ (* idx-val scale) disp)))

(define (vm-eval-offset vm offset)
  (cond
    ((integer? offset) offset)
    ((and (pair? offset) (eq? (car offset) '%sib))
     (vm-eval-sib vm offset))
    (else
     (vm-eval-operand vm offset))))

(define (vm-eval-operand vm opnd)
  (cond
    ((integer? opnd) opnd)
    ((symbol? opnd)
     (let ((g-idx (gpr-name->index opnd)))
       (if g-idx
           (vector-ref (vm-registers-vector vm) g-idx)
           (if (eq? opnd '%al)
               (bitwise-and (vector-ref (vm-registers-vector vm) 0) #xff)
               (let ((x-idx (xmm-name->index opnd)))
                 (if x-idx
                     (vector-ref (vm-xmm-vector vm) x-idx)
                     (let ((str-addr (vm-lookup-string vm opnd)))
                       (if str-addr
                           (+ str-addr 3) ; String tag is 3 in ULisp
                           (let ((glob (vm-lookup-global vm opnd)))
                             (if glob
                                 glob
                                 (vm-get-vreg vm opnd)))))))))))
    ((pair? opnd)
     (let ((tag (car opnd)))
       (case tag
         ((%reg)
          (if (and (pair? (cdr opnd)) (pair? (cddr opnd)))
              (vm-eval-operand vm (caddr opnd))
              (vm-eval-operand vm (cadr opnd))))
         ((%freg)
          (vm-eval-operand vm (cadr opnd)))
         ((%stack)
          (let* ((offset (cadr opnd))
                 (addr (+ (vm-get-reg vm '%rsp) offset)))
            (vm-mem-read-i64 vm addr)))
         ((%mem)
          (let* ((base (cadr opnd))
                 (offset (caddr opnd))
                 (base-val (vm-eval-operand vm base))
                 (off-val (vm-eval-offset vm offset))
                 (addr (+ base-val off-val)))
            (vm-mem-read-i64 vm addr)))
         (else
          (error "Unknown operand in LIR VM:" opnd)))))
    (else
     (error "Invalid operand type in LIR VM:" opnd))))

(define (vm-set-location! vm loc val)
  (cond
    ((symbol? loc)
     (let ((g-idx (gpr-name->index loc)))
       (if g-idx
           (vector-set! (vm-registers-vector vm) g-idx (lir-vm-s64 val))
           (if (eq? loc '%al)
               (let* ((rax (vector-ref (vm-registers-vector vm) 0))
                      (new-rax (bitwise-ior (bitwise-and rax (bitwise-not #xff))
                                            (bitwise-and val #xff))))
                 (vector-set! (vm-registers-vector vm) 0 (lir-vm-s64 new-rax)))
               (let ((x-idx (xmm-name->index loc)))
                 (if x-idx
                     (vector-set! (vm-xmm-vector vm) x-idx
                                  (if (number? val) (exact->inexact val) 0.0))
                     (vm-set-vreg! vm loc val)))))))
    ((pair? loc)
     (let ((tag (car loc)))
       (case tag
         ((%reg)
          (if (and (pair? (cdr loc)) (pair? (cddr loc)))
              (vm-set-location! vm (caddr loc) val)
              (vm-set-location! vm (cadr loc) val)))
         ((%freg)
          (vm-set-location! vm (cadr loc) val))
         ((%stack)
          (let* ((offset (cadr loc))
                 (addr (+ (vm-get-reg vm '%rsp) offset)))
            (vm-mem-write-i64! vm addr val)))
         ((%mem)
          (let* ((base (cadr loc))
                 (offset (caddr loc))
                 (base-val (vm-eval-operand vm base))
                 (off-val (vm-eval-offset vm offset))
                 (addr (+ base-val off-val)))
            (vm-mem-write-i64! vm addr val)))
         (else
          (error "Unknown destination operand in LIR VM:" loc)))))
    (else
     (error "Invalid destination operand in LIR VM:" loc))))

;;; -----------------------------------------------------------------------
;;; §6. Condition Codes Evaluation
;;; -----------------------------------------------------------------------

(define (vm-eval-condition-code vm cc)
  (let ((zf (= (vm-flag-zf vm) 1))
        (sf (= (vm-flag-sf vm) 1))
        (of (= (vm-flag-of vm) 1))
        (cf (= (vm-flag-cf vm) 1)))
    (case cc
      ((e z eq equal zero je jz) zf)
      ((ne nz not-equal not-zero jne jnz) (not zf))
      ((l less jl) (not (eq? sf of)))
      ((le less-equal jle) (or zf (not (eq? sf of))))
      ((g greater jg) (and (not zf) (eq? sf of)))
      ((ge greater-equal jge) (eq? sf of))
      ((b c carry below jb jc) cf)
      ((be below-equal jbe) (or cf zf))
      ((a above ja) (and (not cf) (not zf)))
      ((ae above-equal jae nc) (not cf))
      ((o overflow jo) of)
      ((no no-overflow jno) (not of))
      ((s sign js) sf)
      ((ns no-sign jns) (not sf))
      (else
       (error "Unknown condition code in LIR VM:" cc)))))

;;; -----------------------------------------------------------------------
;;; §7. Arithmetic Flags Updating Helpers
;;; -----------------------------------------------------------------------

(define (vm-update-cmp-flags! vm val1 val2)
  (let* ((s1 (lir-vm-s64 val1))
         (s2 (lir-vm-s64 val2))
         (diff (- s1 s2))
         (s_diff (lir-vm-s64 diff))
         (u1 (lir-vm-u64 s1))
         (u2 (lir-vm-u64 s2))
         (zf (if (= s1 s2) 1 0))
         (sf (if (< s_diff 0) 1 0))
         (of (if (or (and (not (negative? s1)) (negative? s2) (negative? s_diff))
                     (and (negative? s1) (not (negative? s2)) (not (negative? s_diff))))
                 1 0))
         (cf (if (< u1 u2) 1 0)))
    (vm-set-flags! vm zf sf of cf)))

(define (vm-update-add-flags! vm s1 s2)
  (let* ((sum (+ s1 s2))
         (s_sum (lir-vm-s64 sum))
         (u_sum (+ (lir-vm-u64 s1) (lir-vm-u64 s2)))
         (zf (if (= s_sum 0) 1 0))
         (sf (if (< s_sum 0) 1 0))
         (of (if (or (and (not (negative? s1)) (not (negative? s2)) (negative? s_sum))
                     (and (negative? s1) (negative? s2) (not (negative? s_sum))))
                 1 0))
         (cf (if (> u_sum *lir-vm-mask-64*) 1 0)))
    (vm-set-flags! vm zf sf of cf)))

(define (vm-update-sub-flags! vm s1 s2)
  (let* ((diff (- s1 s2))
         (s_diff (lir-vm-s64 diff))
         (u1 (lir-vm-u64 s1))
         (u2 (lir-vm-u64 s2))
         (zf (if (= s_diff 0) 1 0))
         (sf (if (< s_diff 0) 1 0))
         (of (if (or (and (not (negative? s1)) (negative? s2) (negative? s_diff))
                     (and (negative? s1) (not (negative? s2)) (not (negative? s_diff))))
                 1 0))
         (cf (if (< u1 u2) 1 0)))
    (vm-set-flags! vm zf sf of cf)))

(define (vm-update-logic-flags! vm val)
  (let* ((s (lir-vm-s64 val))
         (zf (if (= s 0) 1 0))
         (sf (if (< s 0) 1 0)))
    (vm-set-flags! vm zf sf 0 0)))

;;; -----------------------------------------------------------------------
;;; §8. Program Loader & Block/Function Table Builder
;;; -----------------------------------------------------------------------

;;; Flatten nested %block forms into a linear instruction sequence
(define (flatten-lir-insts insts)
  (let loop ((is insts) (acc '()))
    (if (null? is)
        (reverse acc)
        (let ((inst (car is)))
          (if (and (pair? inst) (eq? (car inst) '%block) (pair? (cdddr inst)))
              (let* ((lbl (cadr inst))
                     (params (caddr inst))
                     (body (cdddr inst))
                     (header (list '%block lbl params))
                     (flat-body (flatten-lir-insts body)))
                (loop (cdr is) (append (reverse flat-body) (cons header acc))))
              (loop (cdr is) (cons inst acc)))))))

;;; Function Descriptor: (list 'func name params frame-size inst-vec label-map block-params)
(define (make-func-descriptor name params frame-size inst-list)
  (let* ((flat-list (flatten-lir-insts inst-list))
         (inst-vec (list->vector flat-list))
         (len (vector-length inst-vec))
         (label-map '())
         (block-params '()))
    (let loop ((i 0))
      (if (< i len)
          (let ((inst (vector-ref inst-vec i)))
            (if (pair? inst)
                (case (car inst)
                  ((%label)
                   (let ((lbl (cadr inst)))
                     (set! label-map (cons (cons lbl i) label-map))))
                  ((%block)
                   (let ((lbl (cadr inst))
                         (p (caddr inst)))
                     (set! label-map (cons (cons lbl i) label-map))
                     (set! block-params (cons (cons lbl p) block-params))))))
            (loop (+ i 1)))))
    (list 'func name params frame-size inst-vec label-map block-params)))

(define (func-name desc) (cadr desc))
(define (func-params desc) (caddr desc))
(define (func-frame-size desc) (cadddr desc))
(define (func-inst-vec desc) (list-ref desc 4))
(define (func-label-map desc) (list-ref desc 5))
(define (func-block-params desc) (list-ref desc 6))

(define (func-find-label-index desc lbl)
  (let ((entry (assq lbl (func-label-map desc))))
    (if entry (cdr entry) #f)))

(define (func-find-block-params desc lbl)
  (let ((entry (assq lbl (func-block-params desc))))
    (if entry (cdr entry) '())))

;;; Load LIR Program into VM
(define (lir-vm-load! vm prog)
  (if (or (not (pair? prog)) (not (eq? (car prog) '%lir-program)))
      (error "Invalid %lir-program:" prog))
  (let* ((strings-decl (cadr prog))
         (stackmaps-decl (caddr prog))
         (funcs-decl (cadddr prog))
         (main-decl (list-ref prog 4))
         ;; Strings loading
         (str-table '())
         (cur-str-addr *lir-vm-null-page-limit*))
    (if (and (pair? strings-decl) (eq? (car strings-decl) 'strings))
        (for-each
         (lambda (entry)
           (let* ((lbl (car entry))
                  (str (cadr entry))
                  (len (string-length str)))
             ;; Write 8-byte length header followed by string bytes and null terminator
             (vm-mem-write-i64! vm cur-str-addr len)
             (let loop ((i 0))
               (if (< i len)
                   (begin
                     (vm-mem-write-u8! vm (+ cur-str-addr 8 i) (char->integer (string-ref str i)))
                     (loop (+ i 1)))))
             (vm-mem-write-u8! vm (+ cur-str-addr 8 len) 0) ; Null terminator
             (set! str-table (cons (cons lbl (+ cur-str-addr 8)) str-table))
             (set! cur-str-addr (+ cur-str-addr (bitwise-and (+ len 16) -8)))))
         (cadr strings-decl)))
    (vm-set-strings-table! vm str-table)

    ;; Functions loading
    (let ((fn-table '()))
      (if (and (pair? funcs-decl) (eq? (car funcs-decl) '%lir-functions))
          (for-each
           (lambda (fn-form)
             (if (and (pair? fn-form) (eq? (car fn-form) '%lir-function))
                 (let* ((lbl (cadr fn-form))
                        (params-clause (caddr fn-form))
                        (frame-clause (cadddr fn-form))
                        (body-clause (list-ref fn-form 4))
                        (params (if (and (pair? params-clause) (eq? (car params-clause) 'params))
                                    (cadr params-clause)
                                    '()))
                        (frame-sz (if (and (pair? frame-clause) (eq? (car frame-clause) 'frame-size))
                                      (cadr frame-clause)
                                      0))
                        (body-insts (if (and (pair? body-clause) (eq? (car body-clause) 'body))
                                        (cdr body-clause)
                                        '()))
                        (desc (make-func-descriptor lbl params frame-sz body-insts)))
                   (set! fn-table (cons (cons lbl desc) fn-table)))))
           (cdr funcs-decl)))
      (vm-set-functions-table! vm fn-table))

    ;; Main loading
    (if (and (pair? main-decl) (eq? (car main-decl) '%lir-main))
        (let* ((frame-clause (cadr main-decl))
               (body-clause (caddr main-decl))
               (frame-sz (if (and (pair? frame-clause) (eq? (car frame-clause) 'frame-size))
                             (cadr frame-clause)
                             0))
               (body-insts (if (and (pair? body-clause) (eq? (car body-clause) 'body))
                               (cdr body-clause)
                               '()))
               (main-desc (make-func-descriptor '%main '() frame-sz body-insts)))
          (vm-set-main-func! vm main-desc)))

    ;; Initial Register & PC Setup
    (let ((top (- (bytevector-length (vm-memory-bytes vm)) 16)))
      (vm-set-reg! vm '%rsp top)
      (vm-set-reg! vm '%rbp top)
      (vm-set-reg! vm '%r12 *lir-vm-heap-base*) ; Heap pointer
      (vm-set-current-fn! vm '%main)
      (vm-set-current-block! vm '%entry)
      (vm-set-pc! vm 0)
      (vm-set-call-stack! vm '())
      (vm-set-status! vm 'ready)
      (vm-set-step-count! vm 0)
      (vm-set-last-trap! vm #f)
      vm)))

;;; -----------------------------------------------------------------------
;;; §9. Instruction Dispatcher & Execution Engine
;;; -----------------------------------------------------------------------

(define (vm-get-current-desc vm)
  (let ((fn (vm-current-fn vm)))
    (if (eq? fn '%main)
        (vm-main-func vm)
        (let ((entry (assq fn (vm-functions-table vm))))
          (if entry (cdr entry) #f)))))

(define (lir-vm-step! vm)
  (let ((st (vm-status vm)))
    (if (or (eq? st 'halted) (eq? st 'trapped))
        st
        (let ((f (vm-fuel vm)))
          (if (and f (<= f 0))
              (begin
                (vm-trigger-trap! vm 'out-of-fuel "Execution step limit exceeded (Fuel exhausted)" (vm-step-count vm))
                'trapped)
              (begin
                (if f (vm-set-fuel! vm (- f 1)))
                (vm-set-step-count! vm (+ (vm-step-count vm) 1))
                (vm-set-status! vm 'running)
                (let* ((desc (vm-get-current-desc vm)))
                  (if (not desc)
                      (begin
                        (vm-trigger-trap! vm 'undefined-target "Current function not found" (vm-current-fn vm))
                        'trapped)
                      (let* ((inst-vec (func-inst-vec desc))
                             (pc (vm-pc vm))
                             (len (vector-length inst-vec)))
                        (if (>= pc len)
                            ;; End of function instructions -> implicit %return
                            (vm-dispatch-return! vm #f)
                            (let* ((inst (vector-ref inst-vec pc)))
                              ;; Call tracer if registered
                              (if (vm-tracer vm)
                                  ((vm-tracer vm) vm inst))
                              ;; Advance PC past current instruction
                              (vm-set-pc! vm (+ pc 1))
                              ;; Execute instruction
                              (vm-dispatch-inst! vm desc inst)
                              (vm-status vm))))))))))))

(define (vm-dispatch-inst! vm desc inst)
  (if (pair? inst)
      (let ((op (car inst)))
        (case op
          ;; --- Labels & SSA Blocks ---
          ((%label)
           #t) ; No-op during sequential stepping

          ((%block)
           #t) ; Block params assigned on jump

          ;; --- Data Movement & Memory ---
          ((%mov)
           (let ((dst (cadr inst))
                 (src (caddr inst)))
             (let ((val (vm-eval-operand vm src)))
               (vm-set-location! vm dst val))))

          ((%load)
           (let* ((dst (cadr inst))
                  (base (caddr inst))
                  (offset (cadddr inst))
                  (base-val (vm-eval-operand vm base))
                  (off-val (vm-eval-offset vm offset))
                  (addr (+ base-val off-val))
                  (val (vm-mem-read-i64 vm addr)))
             (vm-set-location! vm dst val)))

          ((%store)
           (let* ((base (cadr inst))
                  (offset (caddr inst))
                  (src (cadddr inst))
                  (base-val (vm-eval-operand vm base))
                  (off-val (vm-eval-offset vm offset))
                  (addr (+ base-val off-val))
                  (val (vm-eval-operand vm src)))
             (vm-mem-write-i64! vm addr val)))

          ((%load-byte-zx)
           (let* ((dst (cadr inst))
                  (base (caddr inst))
                  (offset (cadddr inst))
                  (base-val (vm-eval-operand vm base))
                  (off-val (vm-eval-offset vm offset))
                  (addr (+ base-val off-val))
                  (val (vm-mem-read-u8 vm addr)))
             (vm-set-location! vm dst val)))

          ((%store-byte)
           (let* ((base (cadr inst))
                  (offset (caddr inst))
                  (src (cadddr inst))
                  (base-val (vm-eval-operand vm base))
                  (off-val (vm-eval-offset vm offset))
                  (addr (+ base-val off-val))
                  (val (vm-eval-operand vm src)))
             (vm-mem-write-u8! vm addr val)))

          ((%load-typed)
           (let* ((type (cadr inst))
                  (dst (caddr inst))
                  (base (cadddr inst))
                  (offset (list-ref inst 4))
                  (base-val (vm-eval-operand vm base))
                  (off-val (vm-eval-offset vm offset))
                  (addr (+ base-val off-val)))
             (case type
               ((i8)  (vm-set-location! vm dst (vm-mem-read-i8 vm addr)))
               ((u8)  (vm-set-location! vm dst (vm-mem-read-u8 vm addr)))
               ((i16) (vm-set-location! vm dst (vm-mem-read-i16 vm addr)))
               ((u16) (vm-set-location! vm dst (vm-mem-read-u16 vm addr)))
               ((i32) (vm-set-location! vm dst (vm-mem-read-i32 vm addr)))
               ((u32) (vm-set-location! vm dst (vm-mem-read-u32 vm addr)))
               ((i64) (vm-set-location! vm dst (vm-mem-read-i64 vm addr)))
               ((u64) (vm-set-location! vm dst (vm-mem-read-u64 vm addr)))
               ((ptr raw-bits scheme-val) (vm-set-location! vm dst (vm-mem-read-u64 vm addr)))
               ((f64) (vm-set-xmm! vm dst (vm-mem-read-f64 vm addr)))
               (else (error "Unsupported type in %load-typed:" type)))))

          ((%store-typed)
           (let* ((type (cadr inst))
                  (base (caddr inst))
                  (offset (cadddr inst))
                  (src (list-ref inst 4))
                  (base-val (vm-eval-operand vm base))
                  (off-val (vm-eval-offset vm offset))
                  (addr (+ base-val off-val))
                  (val (if (eq? type 'f64)
                           (vm-eval-operand vm src)
                           (vm-eval-operand vm src))))
             (case type
               ((i8)  (vm-mem-write-i8! vm addr val))
               ((u8)  (vm-mem-write-u8! vm addr val))
               ((i16) (vm-mem-write-i16! vm addr val))
               ((u16) (vm-mem-write-u16! vm addr val))
               ((i32) (vm-mem-write-i32! vm addr val))
               ((u32) (vm-mem-write-u32! vm addr val))
               ((i64) (vm-mem-write-i64! vm addr val))
               ((u64) (vm-mem-write-u64! vm addr val))
               ((ptr raw-bits scheme-val) (vm-mem-write-u64! vm addr val))
               ((f64) (vm-mem-write-f64! vm addr val))
               (else (error "Unsupported type in %store-typed:" type)))))

          ((%push)
           (let* ((src (cadr inst))
                  (val (vm-eval-operand vm src))
                  (new-rsp (- (vm-get-reg vm '%rsp) 8)))
             (vm-set-reg! vm '%rsp new-rsp)
             (vm-mem-write-i64! vm new-rsp val)))

          ((%pop)
           (let* ((dst (cadr inst))
                  (rsp (vm-get-reg vm '%rsp))
                  (val (vm-mem-read-i64 vm rsp))
                  (new-rsp (+ rsp 8)))
             (vm-set-location! vm dst val)
             (vm-set-reg! vm '%rsp new-rsp)))

          ((%str-ref)
           (let* ((dst (cadr inst))
                  (lbl (caddr inst))
                  (addr (vm-lookup-string vm lbl)))
             (if addr
                 (vm-set-location! vm dst (+ addr 3)) ; Add String tag 3
                 (vm-trigger-trap! vm 'undefined-target "String label not found" lbl))))

          ((%code-ref)
           (let* ((dst (cadr inst))
                  (lbl (caddr inst)))
             ;; Code address represented as a virtual reference / address
             (vm-set-location! vm dst 4096)))

          ((%global-ref)
           (let* ((dst (cadr inst))
                  (var (caddr inst))
                  (val (vm-lookup-global vm var)))
             (vm-set-location! vm dst (if val val 0))))

          ((%global-set!)
           (let* ((var (cadr inst))
                  (src (caddr inst))
                  (val (vm-eval-operand vm src)))
             (vm-set-global! vm var val)))

          ;; --- Arithmetic & Logic Operations ---
          ((%add %raw-add)
           (let* ((dst (cadr inst))
                  (src (caddr inst))
                  (v-dst (vm-eval-operand vm dst))
                  (v-src (vm-eval-operand vm src))
                  (s-dst (lir-vm-s64 v-dst))
                  (s-src (lir-vm-s64 v-src))
                  (res (+ s-dst s-src)))
             (vm-update-add-flags! vm s-dst s-src)
             (vm-set-location! vm dst (lir-vm-s64 res))))

          ((%sub %raw-sub)
           (let* ((dst (cadr inst))
                  (src (caddr inst))
                  (v-dst (vm-eval-operand vm dst))
                  (v-src (vm-eval-operand vm src))
                  (s-dst (lir-vm-s64 v-dst))
                  (s-src (lir-vm-s64 v-src))
                  (res (- s-dst s-src)))
             (vm-update-sub-flags! vm s-dst s-src)
             (vm-set-location! vm dst (lir-vm-s64 res))))

          ((%imul %raw-mul)
           (let* ((dst (cadr inst))
                  (src (caddr inst))
                  (v-dst (vm-eval-operand vm dst))
                  (v-src (vm-eval-operand vm src))
                  (s-dst (lir-vm-s64 v-dst))
                  (s-src (lir-vm-s64 v-src))
                  (prod (* s-dst s-src))
                  (of (if (or (< prod *lir-vm-min-s64*) (> prod *lir-vm-max-s64*)) 1 0)))
             (vm-set-flags! vm (if (= (lir-vm-s64 prod) 0) 1 0)
                            (if (< (lir-vm-s64 prod) 0) 1 0)
                            of of)
             (vm-set-location! vm dst (lir-vm-s64 prod))))

          ((%neg)
           (let* ((dst (cadr inst))
                  (v (vm-eval-operand vm dst))
                  (s (lir-vm-s64 v))
                  (res (- s)))
             (vm-update-sub-flags! vm 0 s)
             (vm-set-location! vm dst (lir-vm-s64 res))))

          ((%inc)
           (let* ((dst (cadr inst))
                  (v (vm-eval-operand vm dst))
                  (s (lir-vm-s64 v))
                  (res (+ s 1)))
             (vm-update-add-flags! vm s 1)
             (vm-set-location! vm dst (lir-vm-s64 res))))

          ((%cqo)
           (let* ((rax (vm-get-reg vm '%rax))
                  (rdx (if (negative? (lir-vm-s64 rax)) -1 0)))
             (vm-set-reg! vm '%rdx rdx)))

          ((%idiv)
           (let* ((src (cadr inst))
                  (s-src (lir-vm-s64 (vm-eval-operand vm src))))
             (if (= s-src 0)
                 (vm-trigger-trap! vm 'division-by-zero "Integer division by zero" src)
                 (let* ((s-rax (lir-vm-s64 (vm-get-reg vm '%rax)))
                        (q (quotient s-rax s-src))
                        (r (remainder s-rax s-src)))
                   (vm-set-reg! vm '%rax (lir-vm-s64 q))
                   (vm-set-reg! vm '%rdx (lir-vm-s64 r))))))

          ((%udiv)
           (let* ((src (cadr inst))
                  (u-src (lir-vm-u64 (vm-eval-operand vm src))))
             (if (= u-src 0)
                 (vm-trigger-trap! vm 'division-by-zero "Unsigned division by zero" src)
                 (let* ((u-rax (lir-vm-u64 (vm-get-reg vm '%rax)))
                        (q (quotient u-rax u-src))
                        (r (modulo u-rax u-src)))
                   (vm-set-reg! vm '%rax (lir-vm-u64 q))
                   (vm-set-reg! vm '%rdx (lir-vm-u64 r))))))

          ((%urem)
           (let* ((src (cadr inst))
                  (u-src (lir-vm-u64 (vm-eval-operand vm src))))
             (if (= u-src 0)
                 (vm-trigger-trap! vm 'division-by-zero "Unsigned remainder by zero" src)
                 (let* ((u-rax (lir-vm-u64 (vm-get-reg vm '%rax)))
                        (r (modulo u-rax u-src)))
                   (vm-set-reg! vm '%rax (lir-vm-u64 r))))))

          ((%shl)
           (let* ((dst (cadr inst))
                  (cnt-op (caddr inst))
                  (v-dst (vm-eval-operand vm dst))
                  (cnt (bitwise-and (lir-vm-u64 (vm-eval-operand vm cnt-op)) 63))
                  (res (lir-vm-u64 (arithmetic-shift (lir-vm-u64 v-dst) cnt))))
             (vm-update-logic-flags! vm res)
             (vm-set-location! vm dst (lir-vm-s64 res))))

          ((%shr)
           (let* ((dst (cadr inst))
                  (cnt-op (caddr inst))
                  (v-dst (vm-eval-operand vm dst))
                  (cnt (bitwise-and (lir-vm-u64 (vm-eval-operand vm cnt-op)) 63))
                  (res (quotient (lir-vm-u64 v-dst) (arithmetic-shift 1 cnt))))
             (vm-update-logic-flags! vm res)
             (vm-set-location! vm dst (lir-vm-s64 res))))

          ((%sar)
           (let* ((dst (cadr inst))
                  (cnt-op (caddr inst))
                  (v-dst (vm-eval-operand vm dst))
                  (cnt (bitwise-and (lir-vm-u64 (vm-eval-operand vm cnt-op)) 63))
                  (res (lir-vm-s64 (arithmetic-shift (lir-vm-s64 v-dst) (- cnt)))))
             (vm-update-logic-flags! vm res)
             (vm-set-location! vm dst res)))

          ((%bit-and)
           (let* ((dst (cadr inst))
                  (src (caddr inst))
                  (v1 (vm-eval-operand vm dst))
                  (v2 (vm-eval-operand vm src))
                  (res (bitwise-and (lir-vm-u64 v1) (lir-vm-u64 v2))))
             (vm-update-logic-flags! vm res)
             (vm-set-location! vm dst (lir-vm-s64 res))))

          ((%bit-or)
           (let* ((dst (cadr inst))
                  (src (caddr inst))
                  (v1 (vm-eval-operand vm dst))
                  (v2 (vm-eval-operand vm src))
                  (res (bitwise-ior (lir-vm-u64 v1) (lir-vm-u64 v2))))
             (vm-update-logic-flags! vm res)
             (vm-set-location! vm dst (lir-vm-s64 res))))

          ((%bit-xor)
           (let* ((dst (cadr inst))
                  (src (caddr inst))
                  (v1 (vm-eval-operand vm dst))
                  (v2 (vm-eval-operand vm src))
                  (res (bitwise-xor (lir-vm-u64 v1) (lir-vm-u64 v2))))
             (vm-update-logic-flags! vm res)
             (vm-set-location! vm dst (lir-vm-s64 res))))

          ((%not)
           (let* ((dst (cadr inst))
                  (v (vm-eval-operand vm dst))
                  (res (bitwise-xor (lir-vm-u64 v) *lir-vm-mask-64*)))
             (vm-update-logic-flags! vm res)
             (vm-set-location! vm dst (lir-vm-s64 res))))

          ;; --- Issue #828: Overflow-Checked & Unsigned Arithmetic ---
          ((%add-overflow)
           (let* ((dst (cadr inst))
                  (src (caddr inst))
                  (s1 (lir-vm-s64 (vm-eval-operand vm dst)))
                  (s2 (lir-vm-s64 (vm-eval-operand vm src)))
                  (sum (+ s1 s2))
                  (s_sum (lir-vm-s64 sum))
                  (of (if (or (< sum *lir-vm-min-s64*) (> sum *lir-vm-max-s64*)) 1 0)))
             (vm-set-flags! vm (if (= s_sum 0) 1 0) (if (< s_sum 0) 1 0) of 0)
             (vm-set-location! vm dst s_sum)))

          ((%sub-overflow)
           (let* ((dst (cadr inst))
                  (src (caddr inst))
                  (s1 (lir-vm-s64 (vm-eval-operand vm dst)))
                  (s2 (lir-vm-s64 (vm-eval-operand vm src)))
                  (diff (- s1 s2))
                  (s_diff (lir-vm-s64 diff))
                  (of (if (or (< diff *lir-vm-min-s64*) (> diff *lir-vm-max-s64*)) 1 0)))
             (vm-set-flags! vm (if (= s_diff 0) 1 0) (if (< s_diff 0) 1 0) of 0)
             (vm-set-location! vm dst s_diff)))

          ((%mul-overflow)
           (let* ((dst (cadr inst))
                  (src (caddr inst))
                  (s1 (lir-vm-s64 (vm-eval-operand vm dst)))
                  (s2 (lir-vm-s64 (vm-eval-operand vm src)))
                  (prod (* s1 s2))
                  (s_prod (lir-vm-s64 prod))
                  (of (if (or (< prod *lir-vm-min-s64*) (> prod *lir-vm-max-s64*)) 1 0)))
             (vm-set-flags! vm (if (= s_prod 0) 1 0) (if (< s_prod 0) 1 0) of of)
             (vm-set-location! vm dst s_prod)))

          ((%uadd)
           (let* ((dst (cadr inst))
                  (src (caddr inst))
                  (u1 (lir-vm-u64 (vm-eval-operand vm dst)))
                  (u2 (lir-vm-u64 (vm-eval-operand vm src)))
                  (sum (+ u1 u2))
                  (cf (if (> sum *lir-vm-mask-64*) 1 0))
                  (res (lir-vm-u64 sum)))
             (vm-set-flags! vm (if (= res 0) 1 0) 0 0 cf)
             (vm-set-location! vm dst (lir-vm-s64 res))))

          ((%usub)
           (let* ((dst (cadr inst))
                  (src (caddr inst))
                  (u1 (lir-vm-u64 (vm-eval-operand vm dst)))
                  (u2 (lir-vm-u64 (vm-eval-operand vm src)))
                  (cf (if (< u1 u2) 1 0))
                  (res (lir-vm-u64 (- u1 u2))))
             (vm-set-flags! vm (if (= res 0) 1 0) 0 0 cf)
             (vm-set-location! vm dst (lir-vm-s64 res))))

          ((%umul)
           (let* ((dst (cadr inst))
                  (src (caddr inst))
                  (u1 (lir-vm-u64 (vm-eval-operand vm dst)))
                  (u2 (lir-vm-u64 (vm-eval-operand vm src)))
                  (prod (* u1 u2))
                  (cf (if (> prod *lir-vm-mask-64*) 1 0))
                  (res (lir-vm-u64 prod)))
             (vm-set-flags! vm (if (= res 0) 1 0) 0 0 cf)
             (vm-set-location! vm dst (lir-vm-s64 res))))

          ;; --- Type Conversions & Fixnum Boxing ---
          ((%trunc)
           (let* ((type (cadr inst))
                  (dst (caddr inst))
                  (src (cadddr inst))
                  (val (vm-eval-operand vm src)))
             (case type
               ((i8 u8)   (vm-set-location! vm dst (bitwise-and val #xff)))
               ((i16 u16) (vm-set-location! vm dst (bitwise-and val #xffff)))
               ((i32 u32) (vm-set-location! vm dst (bitwise-and val #xffffffff)))
               (else (vm-set-location! vm dst val)))))

          ((%zext)
           (let* ((type (cadr inst))
                  (dst (caddr inst))
                  (src (cadddr inst))
                  (val (vm-eval-operand vm src)))
             (case type
               ((i8 u8)   (vm-set-location! vm dst (bitwise-and val #xff)))
               ((i16 u16) (vm-set-location! vm dst (bitwise-and val #xffff)))
               ((i32 u32) (vm-set-location! vm dst (bitwise-and val #xffffffff)))
               (else (vm-set-location! vm dst (lir-vm-u64 val))))))

          ((%sext)
           (let* ((type (cadr inst))
                  (dst (caddr inst))
                  (src (cadddr inst))
                  (val (vm-eval-operand vm src)))
             (case type
               ((i8)  (vm-set-location! vm dst (lir-vm-s8 (bitwise-and val #xff))))
               ((i16) (vm-set-location! vm dst (lir-vm-s16 (bitwise-and val #xffff))))
               ((i32) (vm-set-location! vm dst (lir-vm-s32 (bitwise-and val #xffffffff))))
               (else (vm-set-location! vm dst (lir-vm-s64 val))))))

          ((%box-fixnum)
           (let* ((dst (cadr inst))
                  (src (caddr inst))
                  (val (vm-eval-operand vm src))
                  (boxed (lir-vm-s64 (* (lir-vm-s64 val) 4)))) ; Shift left 2, tag 0
             (vm-set-location! vm dst boxed)))

          ((%unbox-fixnum)
           (let* ((dst (cadr inst))
                  (src (caddr inst))
                  (val (vm-eval-operand vm src))
                  (unboxed (lir-vm-s64 (quotient (lir-vm-s64 val) 4)))) ; Shift right 2
             (vm-set-location! vm dst unboxed)))

          ;; --- Comparisons & Condition Booleans ---
          ((%cmp %raw-cmp)
           (let* ((s1 (cadr inst))
                  (s2 (caddr inst))
                  (v1 (vm-eval-operand vm s1))
                  (v2 (vm-eval-operand vm s2)))
             (vm-update-cmp-flags! vm v1 v2)))

          ((%set-boolean)
           (let* ((dst (cadr inst))
                  (cc (caddr inst))
                  (res (if (vm-eval-condition-code vm cc) 111 47))) ; 0x6F: #t, 0x2F: #f
             (vm-set-location! vm dst res)))

          ;; --- Floating Point Operations (XMM) ---
          ((%sitofp)
           (let* ((dst (cadr inst))
                  (src (caddr inst))
                  (val (vm-eval-operand vm src)))
             (vm-set-xmm! vm dst (exact->inexact (lir-vm-s64 val)))))

          ((%fptosi)
           (let* ((dst (cadr inst))
                  (src (caddr inst))
                  (flt (vm-get-xmm vm src)))
             (vm-set-location! vm dst (exact (truncate flt)))))

          ((%fadd)
           (let* ((dst (cadr inst))
                  (src (caddr inst))
                  (f1 (vm-get-xmm vm dst))
                  (f2 (vm-get-xmm vm src)))
             (vm-set-xmm! vm dst (+ f1 f2))))

          ((%fsub)
           (let* ((dst (cadr inst))
                  (src (caddr inst))
                  (f1 (vm-get-xmm vm dst))
                  (f2 (vm-get-xmm vm src)))
             (vm-set-xmm! vm dst (- f1 f2))))

          ((%fmul)
           (let* ((dst (cadr inst))
                  (src (caddr inst))
                  (f1 (vm-get-xmm vm dst))
                  (f2 (vm-get-xmm vm src)))
             (vm-set-xmm! vm dst (* f1 f2))))

          ((%fdiv)
           (let* ((dst (cadr inst))
                  (src (caddr inst))
                  (f1 (vm-get-xmm vm dst))
                  (f2 (vm-get-xmm vm src)))
             (vm-set-xmm! vm dst (/ f1 f2))))

          ((%fcmp)
           (let* ((s1 (cadr inst))
                  (s2 (caddr inst))
                  (f1 (vm-get-xmm vm s1))
                  (f2 (vm-get-xmm vm s2))
                  (zf (if (= f1 f2) 1 0))
                  (cf (if (< f1 f2) 1 0)))
             (vm-set-flags! vm zf 0 0 cf)))

          ;; --- Control Flow & SSA Branches ---
          ((%jump)
           (let* ((target-lbl (cadr inst))
                  (args (if (pair? (cddr inst)) (caddr inst) '())))
             (vm-dispatch-jump! vm desc target-lbl args)))

          ((%jump-if)
           (let* ((reg (cadr inst))
                  (t-lbl (caddr inst))
                  (t-args (cadddr inst))
                  (e-lbl (list-ref inst 4))
                  (e-args (list-ref inst 5))
                  (val (vm-eval-operand vm reg)))
             (if (not (= val 47)) ; Not #f (0x2F)
                 (vm-dispatch-jump! vm desc t-lbl t-args)
                 (vm-dispatch-jump! vm desc e-lbl e-args))))

          ((%jump-if-false)
           (let* ((reg (cadr inst))
                  (lbl (caddr inst))
                  (args (if (pair? (cdddr inst)) (cadddr inst) '()))
                  (val (vm-eval-operand vm reg)))
             (if (= val 47) ; Is #f (0x2F)
                 (vm-dispatch-jump! vm desc lbl args))))

          ((%jump-cond)
           (let* ((cc (cadr inst))
                  (lbl (caddr inst)))
             (if (vm-eval-condition-code vm cc)
                 (vm-dispatch-jump! vm desc lbl '()))))

          ((%jump-if-zero)
           (let ((lbl (cadr inst)))
             (if (= (vm-flag-zf vm) 1)
                 (vm-dispatch-jump! vm desc lbl '()))))

          ((%direct-jump)
           (let ((lbl (cadr inst)))
             (let ((idx (func-find-label-index desc lbl)))
               (if idx
                   (vm-set-pc! vm idx)
                   (let ((fn-entry (assq lbl (vm-functions-table vm))))
                     (if fn-entry
                         (begin
                           (vm-set-current-fn! vm lbl)
                           (vm-set-pc! vm 0))
                         (vm-trigger-trap! vm 'undefined-target "Jump target not found" lbl)))))))

          ((%return)
           (let ((val (if (pair? (cdr inst)) (cadr inst) #f)))
             (vm-dispatch-return! vm val)))

          ;; --- Procedure Calls & ABI ---
          ((%direct-call)
           (let* ((func-lbl (cadr inst))
                  (shift (caddr inst))
                  (fn-entry (assq func-lbl (vm-functions-table vm))))
             (if (not fn-entry)
                 (vm-trigger-trap! vm 'undefined-target "Called function not found" func-lbl)
                 (let ((cur-rsp (vm-get-reg vm '%rsp)))
                   ;; Push frame to call stack
                   (vm-set-call-stack! vm (cons (list (vm-current-fn vm) (vm-pc vm) cur-rsp)
                                                (vm-call-stack vm)))
                   ;; Adjust %rsp
                   (vm-set-reg! vm '%rsp (- cur-rsp (+ shift 8)))
                   ;; Set PC to target function
                   (vm-set-current-fn! vm func-lbl)
                   (vm-set-pc! vm 0)))))

          ((%c-call %call-foreign)
           (let* ((fn (cadr inst))
                  (shift (caddr inst)))
             (vm-dispatch-c-call! vm fn shift)))

          ((%alloc)
           (let* ((dst (cadr inst))
                  (bytes (caddr inst))
                  (tag (cadddr inst))
                  (aligned (bitwise-and (+ bytes 7) -8))
                  (raw-ptr (vm-heap-ptr vm))
                  (new-ptr (+ raw-ptr aligned)))
             (if (> new-ptr *lir-vm-heap-limit*)
                 (vm-trigger-trap! vm 'out-of-bounds "Heap memory limit exceeded" new-ptr)
                 (begin
                   (vm-set-heap-ptr! vm new-ptr)
                   (vm-set-location! vm dst (+ raw-ptr tag))))))

          (else
           (error "Unsupported LIR instruction in Reference VM:" inst))))
      (error "Invalid instruction form:" inst)))

;;; Branch & SSA Parallel Assignment Helper
(define (vm-dispatch-jump! vm desc target-lbl args)
  (let ((idx (func-find-label-index desc target-lbl)))
    (if (not idx)
        (vm-trigger-trap! vm 'undefined-target "Jump label not found in function" target-lbl)
        (let ((params (func-find-block-params desc target-lbl)))
          ;; Parallel assignment: evaluate all args before setting any param
          (if (pair? args)
              (let ((vals (map (lambda (a) (vm-eval-operand vm a)) args)))
                (let assign-loop ((ps params) (vs vals))
                  (if (and (pair? ps) (pair? vs))
                      (begin
                        (vm-set-location! vm (car ps) (car vs))
                        (assign-loop (cdr ps) (cdr vs)))))))
          (vm-set-current-block! vm target-lbl)
          (vm-set-pc! vm idx)))))

;;; Return Helper
(define (vm-dispatch-return! vm val-opnd)
  (if val-opnd
      (let ((ret-val (vm-eval-operand vm val-opnd)))
        (vm-set-reg! vm '%rax ret-val)))
  (let ((stack (vm-call-stack vm)))
    (if (null? stack)
        ;; Finished %main -> Halt VM
        (vm-set-status! vm 'halted)
        ;; Pop caller frame
        (let* ((frame (car stack))
               (saved-fn (car frame))
               (saved-pc (cadr frame))
               (saved-rsp (caddr frame)))
          (vm-set-call-stack! vm (cdr stack))
          (vm-set-reg! vm '%rsp saved-rsp)
          (vm-set-current-fn! vm saved-fn)
          (vm-set-pc! vm saved-pc)))))

;;; C Foreign Call Dispatcher
(define (vm-dispatch-c-call! vm fn-name shift)
  ;; Check registered custom handlers first
  (let ((custom (assq fn-name (vm-foreign-handlers vm))))
    (if custom
        ((cdr custom) vm)
        (case fn-name
          ((ulisp_alloc malloc)
           (let* ((bytes (vm-get-reg vm '%rdi))
                  (tag (if (eq? fn-name 'ulisp_alloc) (vm-get-reg vm '%rsi) 0))
                  (aligned (bitwise-and (+ bytes 7) -8))
                  (raw-ptr (vm-heap-ptr vm))
                  (new-ptr (+ raw-ptr aligned)))
             (if (> new-ptr *lir-vm-heap-limit*)
                 (vm-trigger-trap! vm 'out-of-bounds "Heap out of memory" new-ptr)
                 (begin
                   (vm-set-heap-ptr! vm new-ptr)
                   (vm-set-reg! vm '%rax (+ raw-ptr tag))))))

          ((putchar)
           (let ((c (bitwise-and (vm-get-reg vm '%rdi) #xff)))
             (vm-set-reg! vm '%rax c)))

          ((puts printf)
           (vm-set-reg! vm '%rax 0))

          ((exit)
           (vm-set-status! vm 'halted))

          (else
           ;; Default stub: succeed with rax = 0
           (vm-set-reg! vm '%rax 0))))))

(define (register-c-foreign-handler! vm name proc)
  (let ((entry (assq name (vm-foreign-handlers vm))))
    (if entry
        (set-cdr! entry proc)
        (vm-set-foreign-handlers! vm (cons (cons name proc) (vm-foreign-handlers vm))))))

;;; -----------------------------------------------------------------------
;;; §10. Public Execution & Convenience APIs
;;; -----------------------------------------------------------------------

(define (lir-vm-run! vm)
  (let loop ()
    (let ((st (lir-vm-step! vm)))
      (if (or (eq? st 'halted) (eq? st 'trapped))
          st
          (loop)))))

(define (set-lir-vm-tracer! vm proc)
  (vm-set-tracer! vm proc))

(define (eval-lir-program prog)
  (let ((vm (make-lir-vm)))
    (lir-vm-load! vm prog)
    (let ((res (lir-vm-run! vm)))
      (if (eq? res 'trapped)
          (error "LIR VM Trapped during evaluation:" (vm-last-trap vm))
          (vm-get-reg vm '%rax)))))

(define (eval-lir-program-with-fuel prog fuel)
  (let ((vm (make-lir-vm)))
    (vm-set-fuel! vm fuel)
    (lir-vm-load! vm prog)
    (let ((res (lir-vm-run! vm)))
      (if (eq? res 'trapped)
          (vm-last-trap vm)
          (vm-get-reg vm '%rax)))))

(define (eval-lir-program-unboxed prog)
  (let ((val (eval-lir-program prog)))
    (quotient val 4)))
