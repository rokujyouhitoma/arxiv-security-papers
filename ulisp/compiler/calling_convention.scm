;;; =======================================================================
;;; ULisp Compiler - Calling Convention Abstraction & ABI Layout Planner
;;; Conforms to DSN-38 §2 (C2/E5/E6), DSN-33 §3.3, DSN-33-02 §5.1 & Issue #829
;;; =======================================================================
;;; Provides modular calling convention specifications, register mapping,
;;; typed argument placement planning (GPR / XMM / Stack), 16-byte stack
;;; alignment guarantees, and zero-overhead C-FFI / System V ABI support.
;;; =======================================================================

;;; -----------------------------------------------------------------------
;;; 1. Calling Convention Identifiers & Predicates
;;; -----------------------------------------------------------------------

(define *calling-conventions*
  '(scheme-fast
    sysv-abi
    aapcs64
    cdecl))

(define (calling-convention? x)
  (and (symbol? x) (memq x *calling-conventions*) #t))

(define (default-calling-convention) 'scheme-fast)

;;; -----------------------------------------------------------------------
;;; 2. Type Classification for ABI Placement
;;; -----------------------------------------------------------------------

(define *abi-float-types* '(f32 f64 float double single-float double-float))
(define *abi-integer-types* '(i8 u8 i16 u16 i32 u32 i64 u64 int unsigned-int long unsigned-long size_t intptr_t uintptr_t ptr any obj fixnum))

(define (arg-type-float? t)
  (and (symbol? t) (memq t *abi-float-types*) #t))

(define (arg-type-integer? t)
  (or (not (symbol? t))
      (memq t *abi-integer-types*)
      (not (arg-type-float? t))))

;;; -----------------------------------------------------------------------
;;; 3. Machine Register Definitions by Convention
;;; -----------------------------------------------------------------------

;; System V AMD64 ABI (x86-64)
(define *sysv-gpr-arg-registers* '(%rdi %rsi %rdx %rcx %r8 %r9))
(define *sysv-xmm-arg-registers* '(%xmm0 %xmm1 %xmm2 %xmm3 %xmm4 %xmm5 %xmm6 %xmm7))
(define *sysv-callee-saved-gprs* '(%rbx %rsp %rbp %r12 %r13 %r14 %r15))
(define *sysv-caller-saved-gprs* '(%rax %rcx %rdx %rsi %rdi %r8 %r9 %r10 %r11))
(define *sysv-return-gpr* '%rax)
(define *sysv-return-xmm* '%xmm0)

;; System V AMD64 psABI §3.5.7 Variable Argument List & Register Save Area Constants
(define *sysv-va-reg-save-area-size* 176) ; 6 GPRs * 8B (0..47) + 8 XMMs * 16B (48..175)
(define *sysv-va-gp-limit* 48)            ; Max gp_offset before overflowing to stack
(define *sysv-va-fp-base* 48)             ; Byte offset where XMM save slots begin
(define *sysv-va-fp-limit* 176)           ; Max fp_offset before overflowing to stack
(define *sysv-va-list-size* 24)           ; sizeof(struct __va_list_tag[1]) == 24 bytes

;; Scheme Internal Fast Convention (x86-64)
;; All arguments passed in GPRs as tagged pointers or unboxed values
(define *scheme-fast-arg-registers* '(%rdi %rsi %rdx %rcx %r8 %r9))
(define *scheme-fast-count-reg* '%rax)
(define *scheme-fast-closure-reg* '%r10)
(define *scheme-fast-temp-reg* '%r11)
(define *scheme-fast-nursery-reg* '%r12)
(define *scheme-fast-callee-saved* '(%rbx %rsp %rbp %r12 %r13 %r14 %r15))

;; ARM64 AAPCS64 ABI
(define *aapcs64-gpr-arg-registers* '(%x0 %x1 %x2 %x3 %x4 %x5 %x6 %x7))
(define *aapcs64-fp-arg-registers* '(%v0 %v1 %v2 %v3 %v4 %v5 %v6 %v7))
(define *aapcs64-return-gpr* '%x0)
(define *aapcs64-return-fp* '%v0)

(define (convention-gpr-arg-registers conv)
  (case conv
    ((sysv-abi cdecl) *sysv-gpr-arg-registers*)
    ((scheme-fast)    *scheme-fast-arg-registers*)
    ((aapcs64)        *aapcs64-gpr-arg-registers*)
    (else *sysv-gpr-arg-registers*)))

(define (convention-xmm-arg-registers conv)
  (case conv
    ((sysv-abi) *sysv-xmm-arg-registers*)
    ((aapcs64)  *aapcs64-fp-arg-registers*)
    (else '())))

(define (convention-stack-alignment conv)
  (case conv
    ((sysv-abi aapcs64) 16)
    ((scheme-fast)      16)
    ((cdecl)             8)
    (else 16)))

;;; -----------------------------------------------------------------------
;;; 4. ABI Argument Location Record
;;; -----------------------------------------------------------------------

;; kind: 'gpr | 'xmm | 'stack
(define (make-abi-arg-loc index type kind target offset)
  (list 'abi-arg-loc index type kind target offset))

(define (abi-arg-loc? x)
  (and (pair? x) (eq? (car x) 'abi-arg-loc)))

(define (abi-arg-loc-index loc)  (list-ref loc 1))
(define (abi-arg-loc-type loc)   (list-ref loc 2))
(define (abi-arg-loc-kind loc)   (list-ref loc 3))
(define (abi-arg-loc-target loc) (list-ref loc 4))
(define (abi-arg-loc-offset loc) (list-ref loc 5))

;;; -----------------------------------------------------------------------
;;; 5. Layout Result Structure
;;; -----------------------------------------------------------------------

(define (make-abi-layout conv locations num-gpr num-xmm stack-bytes padding-bytes total-shift al-val)
  (list 'abi-layout
        (cons 'convention conv)
        (cons 'locations locations)
        (cons 'num-gpr num-gpr)
        (cons 'num-xmm num-xmm)
        (cons 'stack-bytes stack-bytes)
        (cons 'padding-bytes padding-bytes)
        (cons 'total-shift total-shift)
        (cons 'al-val al-val)))

(define (abi-layout-ref layout key)
  (let ((entry (assq key (cdr layout))))
    (if entry (cdr entry) #f)))

(define (abi-layout-locations layout)     (abi-layout-ref layout 'locations))
(define (abi-layout-num-gpr layout)       (abi-layout-ref layout 'num-gpr))
(define (abi-layout-num-xmm layout)       (abi-layout-ref layout 'num-xmm))
(define (abi-layout-stack-bytes layout)   (abi-layout-ref layout 'stack-bytes))
(define (abi-layout-padding-bytes layout) (abi-layout-ref layout 'padding-bytes))
(define (abi-layout-total-shift layout)   (abi-layout-ref layout 'total-shift))
(define (abi-layout-al-val layout)        (abi-layout-ref layout 'al-val))

;;; -----------------------------------------------------------------------
;;; 6. ABI Layout Planner
;;; -----------------------------------------------------------------------
;;; Computes the physical location (register or stack slot) for each argument
;;; according to the chosen calling convention.
;;;
;;; Inputs:
;;;   conv:       'sysv-abi | 'scheme-fast | 'aapcs64
;;;   arg-types:  list of type symbols, e.g. '(ptr i64 f64) or list of #f/any
;;;   varargs?:   #t if callee is a C variadic function (e.g. printf)
;;;
;;; Output:
;;;   abi-layout structure containing detailed placement and stack alignment

(define (compute-call-abi-layout conv arg-types varargs?)
  (let ((gpr-regs (convention-gpr-arg-registers conv))
        (xmm-regs (convention-xmm-arg-registers conv)))
    (let loop ((types arg-types)
               (idx 0)
               (available-gprs gpr-regs)
               (available-xmms xmm-regs)
               (stack-offset 0)
               (used-gpr 0)
               (used-xmm 0)
               (rev-locs '()))
      (if (null? types)
          (let* ((locs (reverse rev-locs))
                 (stack-bytes stack-offset)
                 ;; In System V AMD64 ABI, stack arguments must preserve 16-byte alignment
                 (padding-bytes (if (= (modulo stack-bytes 16) 0) 0 (- 16 (modulo stack-bytes 16))))
                 (total-shift (+ stack-bytes padding-bytes))
                 ;; For SysV varargs, %al must hold number of XMM registers used
                 (al-val (if (and (eq? conv 'sysv-abi) varargs?)
                             used-xmm
                             #f)))
            (make-abi-layout conv locs used-gpr used-xmm stack-bytes padding-bytes total-shift al-val))
          (let* ((t (car types))
                 (is-float? (arg-type-float? t)))
            (cond
              ;; Case 1: Floating-point argument and XMM register is available
              ((and is-float? (pair? available-xmms))
               (let ((reg (car available-xmms)))
                 (loop (cdr types)
                       (+ idx 1)
                       available-gprs
                       (cdr available-xmms)
                       stack-offset
                       used-gpr
                       (+ used-xmm 1)
                       (cons (make-abi-arg-loc idx t 'xmm reg #f) rev-locs))))

              ;; Case 2: Integer/pointer/any argument and GPR register is available
              ((and (not is-float?) (pair? available-gprs))
               (let ((reg (car available-gprs)))
                 (loop (cdr types)
                       (+ idx 1)
                       (cdr available-gprs)
                       available-xmms
                       stack-offset
                       (+ used-gpr 1)
                       used-xmm
                       (cons (make-abi-arg-loc idx t 'gpr reg #f) rev-locs))))

              ;; Case 3: Stack spill (registers exhausted)
              (else
               (let ((loc-offset stack-offset))
                 (loop (cdr types)
                       (+ idx 1)
                       available-gprs
                       available-xmms
                       (+ stack-offset 8)
                       used-gpr
                       used-xmm
                       (cons (make-abi-arg-loc idx t 'stack #f loc-offset) rev-locs))))))))))

;;; -----------------------------------------------------------------------
;;; 7. Frame Shift Alignment Calculator
;;; -----------------------------------------------------------------------
;;; Ensures that prior to executing 'call <func>', the stack pointer rsp
;;; satisfies (rsp + 8) % 16 == 0, guaranteeing that immediately after
;;; call pushes the return address, callee sees rsp % 16 == 0.

(define (compute-sysv-call-frame-shift current-si outgoing-stack-bytes)
  (let* ((raw-needed (+ (- 0 current-si) outgoing-stack-bytes))
         (shift (align-frame-shift raw-needed)))
    shift))

;;; -----------------------------------------------------------------------
;;; 8. Function Definition Calling Convention Attributes
;;; -----------------------------------------------------------------------

(define (extract-func-calling-convention attrs)
  (cond
    ((not (pair? attrs)) (default-calling-convention))
    ((assq ':calling-convention attrs)
     => (lambda (entry)
          (if (calling-convention? (cadr entry))
              (cadr entry)
              (default-calling-convention))))
    (else (default-calling-convention))))

(define (extract-func-varargs? attrs)
  (cond
    ((not (pair? attrs)) #f)
    ((assq ':varargs attrs)
     => (lambda (entry) (and (cadr entry) #t)))
    (else #f)))

(define (extract-func-return-type attrs)
  (cond
    ((not (pair? attrs)) 'any)
    ((assq ':return-type attrs)
     => (lambda (entry) (cadr entry)))
    (else 'any)))
