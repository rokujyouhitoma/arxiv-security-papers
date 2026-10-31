;;; =======================================================================
;;; ULisp Runtime Concurrency: System V AMD64 Native Context Switch (context.scm)
;;; Conforms to DSN-37 Section 5, Section 7.3 & Section 14.4 (Phase 2 Task 2.1), Issue #634
;;;
;;; Implements ultra-lightweight (15-instruction) System V AMD64 callee-saved
;;; register context switching (swap_context), 4KB-16KB micro-stacks with
;;; 16-byte ABI alignment and stack overflow canaries (CWE-787), and coroutine
;;; execution contexts.
;;; =======================================================================

;; -----------------------------------------------------------------------
;; 1. Stack & ABI Configuration Constants
;; -----------------------------------------------------------------------

(define *context-min-stack-size* 4096)        ; 4KB minimum stack size
(define *context-default-stack-size* 8192)    ; 8KB default stack size
(define *context-max-stack-size* 65536)       ; 64KB maximum micro-stack size
(define *context-stack-align* 16)             ; System V AMD64 16-byte stack alignment
(define *context-tcb-header-size* 64)         ; 64-byte TCB header at stack top
(define *context-frame-size* 64)              ; 64-byte initial swap_context frame (8 slots)
(define *context-stack-canary* 21130214873854) ; 0x1337BEEFCAFE (45-bit fixnum-safe canary)

;; -----------------------------------------------------------------------
;; 2. Low-Level Assembly Entrypoint Stubs (Overridden by context.s)
;; -----------------------------------------------------------------------

(define (%asm-get-trampoline-addr which)
  (if (not (integer? which)) 0 0))

(define (%asm-swap-context! old-sp-ptr new-sp)
  (and (integer? old-sp-ptr) (integer? new-sp)))

(define (%asm-resume-task! top-addr send-val)
  (if (integer? top-addr) send-val #f))

(define (%asm-yield-task! yield-val)
  yield-val)

(define (%asm-switch-task! from-top-addr to-top-addr send-val)
  (if (and (integer? from-top-addr) (integer? to-top-addr)) send-val #f))

(define (%asm-verify-swap-context-regs! stack1-top stack2-top)
  (and (integer? stack1-top) (integer? stack2-top)))

(define (%asm-bench-swap-context! stack1-top stack2-top total-switches)
  (if (and (integer? stack1-top) (integer? stack2-top)) total-switches 0))

;; -----------------------------------------------------------------------
;; 3. Raw Memory & Alignment Helpers
;; -----------------------------------------------------------------------

(define (%context-bitwise-not x)
  (- -1 x))

(define (%context-align-up val align)
  (let ((mask (- align 1)))
    (bitwise-and (+ val mask) (%context-bitwise-not mask))))

(define (%context-align-down val align)
  (let ((mask (- align 1)))
    (bitwise-and val (%context-bitwise-not mask))))

(define (%context-raw-u64-ref addr offset)
  (%to-fixnum (%raw-load (%to-raw addr) offset)))

(define (%context-raw-u64-set! addr offset val)
  (%raw-store! (%to-raw addr) offset (%to-raw val)))

(define (%context-raw-obj-ref addr offset)
  (%raw-load (%to-raw addr) offset))

(define (%context-raw-obj-set! addr offset obj)
  (%raw-store! (%to-raw addr) offset obj))

(define (%context-sys-munmap addr length)
  (%to-fixnum (%raw-syscall (%to-raw 11) (%to-raw addr) (%to-raw length) 0 0 0 0)))

;; -----------------------------------------------------------------------
;; 4. <task-stack> Record & Stack Frame Setup
;; -----------------------------------------------------------------------

(define-record-type <task-stack>
  (%make-task-stack base size top initial-sp freed?)
  task-stack?
  (base       task-stack-base)
  (size       task-stack-size)
  (top        task-stack-top)
  (initial-sp task-stack-initial-sp %task-stack-initial-sp-set!)
  (freed?     task-stack-freed?     %task-stack-freed-set!))

(define make-task-stack
  (case-lambda
    (()
     (make-task-stack *context-default-stack-size*))
    ((requested-size)
     (if (or (not (integer? requested-size))
             (< requested-size *context-min-stack-size*)
             (> requested-size *context-max-stack-size*))
         (error "make-task-stack: stack size must be an integer in [4096, 65536] (CWE-787)" requested-size)
         (let* ((aligned-size (%context-align-up requested-size *context-stack-align*))
                (raw-base (sys-mmap aligned-size))
                (base (%to-fixnum raw-base)))
           (if (<= base 0)
               (error "make-task-stack: sys-mmap failed" aligned-size)
               (let* ((top (%context-align-down (+ base aligned-size) *context-stack-align*))
                      (init-sp (- top (+ *context-tcb-header-size* *context-frame-size*))))
                 ;; Write bottom and top stack overflow canaries
                 (%context-raw-u64-set! base 0 *context-stack-canary*)
                 (%context-raw-u64-set! top -64 *context-stack-canary*)
                 ;; Initialize TCB header slots [top - 56 .. top - 8]
                 (%context-raw-u64-set! top -56 0)   ; switch_count = 0
                 (%context-raw-u64-set! top -48 0)   ; prev_task_top = 0
                 (%context-raw-obj-set! top -40 #f)  ; task_value_slot = #f
                 (%context-raw-obj-set! top -32 #f)  ; task_closure_slot = #f
                 (%context-raw-u64-set! top -24 0)   ; task_state = 0 ('ready)
                 (%context-raw-u64-set! top -16 init-sp) ; task_sp_slot
                 (%context-raw-u64-set! top -8 0)    ; parent_sp_slot = 0
                 (%make-task-stack base aligned-size top init-sp #f))))))))

(define (free-task-stack! stack)
  (if (not (task-stack? stack))
      (error "free-task-stack!: expected <task-stack>" stack)
      (if (task-stack-freed? stack)
          #f
          (let ((base (task-stack-base stack))
                (size (task-stack-size stack))
                (top (task-stack-top stack)))
            ;; Scrub canaries before unmapping (CWE-212 / CWE-416)
            (%context-raw-u64-set! base 0 0)
            (%context-raw-u64-set! top -64 0)
            (%task-stack-freed-set! stack #t)
            (%context-sys-munmap base size)
            #t))))

(define (task-stack-check-canary stack)
  (if (not (task-stack? stack))
      (error "task-stack-check-canary: expected <task-stack>" stack)
      (if (task-stack-freed? stack)
          #f
          (let ((base (task-stack-base stack))
                (top (task-stack-top stack)))
            (and (= (%context-raw-u64-ref base 0) *context-stack-canary*)
                 (= (%context-raw-u64-ref top -64) *context-stack-canary*))))))

(define (task-stack-sp stack)
  (if (not (task-stack? stack))
      (error "task-stack-sp: expected <task-stack>" stack)
      (if (task-stack-freed? stack)
          (error "task-stack-sp: stack has been freed (CWE-416)" stack)
          (%context-raw-u64-ref (task-stack-top stack) -16))))

;; Build initial System V AMD64 context frame on [stack-base, stack-base + stack-size)
;; Layout at frame_top = top - 64:
;;   [frame_top -  8] ([top -  72]) : ulisp_task_exit_trampoline (return address when entry_rip returns)
;;   [frame_top - 16] ([top -  80]) : entry_rip (popped by swap_context's ret; at entry rsp = top - 72, rsp % 16 == 8)
;;   [frame_top - 24] ([top -  88]) : initial rbp (frame_top)
;;   [frame_top - 32] ([top -  96]) : initial rbx (top)
;;   [frame_top - 40] ([top - 104]) : initial r12 (0, inherited from caller %r12 via %r11)
;;   [frame_top - 48] ([top - 112]) : initial r13 (entry-fn closure or 0)
;;   [frame_top - 56] ([top - 120]) : initial r14 (0)
;;   [frame_top - 64] ([top - 128]) : initial r15 (0) <-- initial_sp (16-byte aligned)
(define (%setup-task-stack-raw! base size entry-fn)
  (if (or (not (integer? base)) (<= base 0))
      (error "setup-task-stack: invalid stack-base" base)
      (if (or (not (integer? size)) (< size *context-min-stack-size*) (> size *context-max-stack-size*))
          (error "setup-task-stack: invalid stack-size" size)
          (if (not (or (procedure? entry-fn) (integer? entry-fn)))
              (error "setup-task-stack: entry-fn must be a procedure or integer code address" entry-fn)
              (let* ((top (%context-align-down (+ base size) *context-stack-align*))
                     (frame-top (- top *context-tcb-header-size*))
                     (init-sp (- frame-top *context-frame-size*))
                     (entry-tramp (%asm-get-trampoline-addr 0))
                     (exit-tramp (%asm-get-trampoline-addr 1))
                     (entry-rip (if (procedure? entry-fn) entry-tramp entry-fn)))
                ;; Write bottom and top stack overflow canaries
                (%context-raw-u64-set! base 0 *context-stack-canary*)
                (%context-raw-u64-set! top -64 *context-stack-canary*)
                ;; Initialize TCB header at [top - 56 .. top - 8]
                (%context-raw-u64-set! top -56 0)
                (%context-raw-u64-set! top -48 0)
                (%context-raw-obj-set! top -40 #f)
                (if (procedure? entry-fn)
                    (%context-raw-obj-set! top -32 entry-fn)
                    (%context-raw-u64-set! top -32 entry-fn))
                (%context-raw-u64-set! top -24 0)
                (%context-raw-u64-set! top -16 init-sp)
                (%context-raw-u64-set! top -8 0)
                ;; Initialize swap_context frame at [frame-top - 64 .. frame-top - 8]
                (%context-raw-u64-set! frame-top -8 exit-tramp)
                (%context-raw-u64-set! frame-top -16 entry-rip)
                (%context-raw-u64-set! frame-top -24 frame-top)
                (%context-raw-u64-set! frame-top -32 top)
                (%context-raw-u64-set! frame-top -40 0)
                (if (procedure? entry-fn)
                    (%context-raw-obj-set! frame-top -48 entry-fn)
                    (%context-raw-u64-set! frame-top -48 0))
                (%context-raw-u64-set! frame-top -56 0)
                (%context-raw-u64-set! frame-top -64 0)
                init-sp)))))

(define setup-task-stack
  (case-lambda
    ((stack entry-fn)
     (if (not (task-stack? stack))
         (error "setup-task-stack: expected <task-stack>" stack)
         (if (task-stack-freed? stack)
             (error "setup-task-stack: cannot setup freed <task-stack> (CWE-416)" stack)
             (let ((sp (%setup-task-stack-raw! (task-stack-base stack)
                                               (task-stack-size stack)
                                               entry-fn)))
               (%task-stack-initial-sp-set! stack sp)
               sp))))
    ((stack-base stack-size entry-fn)
     (%setup-task-stack-raw! stack-base stack-size entry-fn))))

;; -----------------------------------------------------------------------
;; 5. <coroutine-context> & High-Level Context Switch API
;; -----------------------------------------------------------------------

(define *coroutine-next-id* (vector 1))

(define-record-type <coroutine-context>
  (%make-coroutine-context id stack entry-fn owns-stack?)
  coroutine-context?
  (id          coroutine-id)
  (stack       coroutine-stack)
  (entry-fn    coroutine-entry-fn)
  (owns-stack? coroutine-owns-stack?))

(define make-coroutine-context
  (case-lambda
    ((entry-fn)
     (make-coroutine-context entry-fn *context-default-stack-size*))
    ((entry-fn stack-or-size)
     (if (not (procedure? entry-fn))
         (error "make-coroutine-context: entry-fn must be a procedure (CWE-843)" entry-fn)
         (let* ((owns? (not (task-stack? stack-or-size)))
                (stk (if (task-stack? stack-or-size)
                         stack-or-size
                         (make-task-stack stack-or-size)))
                (cid (vector-ref *coroutine-next-id* 0)))
           (vector-set! *coroutine-next-id* 0 (+ cid 1))
           (setup-task-stack stk entry-fn)
           (%make-coroutine-context cid stk entry-fn owns?))))))

(define (free-coroutine-context! ctx)
  (if (not (coroutine-context? ctx))
      (error "free-coroutine-context!: expected <coroutine-context>" ctx)
      (free-task-stack! (coroutine-stack ctx))))

(define (coroutine-state ctx)
  (if (not (coroutine-context? ctx))
      (error "coroutine-state: expected <coroutine-context>" ctx)
      (let ((stk (coroutine-stack ctx)))
        (if (task-stack-freed? stk)
            'freed
            (let ((code (%context-raw-u64-ref (task-stack-top stk) -24)))
              (cond
                ((= code 0) 'ready)
                ((= code 1) 'running)
                ((= code 2) 'suspended)
                ((= code 3) 'terminated)
                (else 'unknown)))))))

(define (coroutine-terminated? ctx)
  (eq? (coroutine-state ctx) 'terminated))

(define (coroutine-switch-count ctx)
  (if (not (coroutine-context? ctx))
      (error "coroutine-switch-count: expected <coroutine-context>" ctx)
      (let ((stk (coroutine-stack ctx)))
        (if (task-stack-freed? stk)
            0
            (%context-raw-u64-ref (task-stack-top stk) -56)))))

(define (coroutine-stack-pointer ctx)
  (if (not (coroutine-context? ctx))
      (error "coroutine-stack-pointer: expected <coroutine-context>" ctx)
      (task-stack-sp (coroutine-stack ctx))))

(define (%validate-resumable-coroutine! caller-name ctx)
  (if (not (coroutine-context? ctx))
      (error (string-append caller-name ": expected <coroutine-context> (CWE-843)") ctx)
      (let ((stk (coroutine-stack ctx)))
        (if (task-stack-freed? stk)
            (error (string-append caller-name ": stack has been freed (CWE-416)") ctx)
            (if (not (task-stack-check-canary stk))
                (error (string-append caller-name ": stack overflow canary corrupted (CWE-787)") ctx)
                (if (eq? (coroutine-state ctx) 'terminated)
                    (error (string-append caller-name ": cannot switch into terminated coroutine (CWE-416)") ctx)
                    stk))))))

(define context-resume!
  (case-lambda
    ((ctx)
     (context-resume! ctx #f))
    ((ctx send-val)
     (let* ((stk (%validate-resumable-coroutine! "context-resume!" ctx))
            (top (task-stack-top stk))
            (res (%asm-resume-task! top send-val)))
       (if (not (task-stack-check-canary stk))
           (error "context-resume!: stack overflow canary corrupted during execution (CWE-787)" ctx)
           res)))))

(define context-yield!
  (case-lambda
    (()
     (%asm-yield-task! #f))
    ((yield-val)
     (%asm-yield-task! yield-val))))

(define context-switch!
  (case-lambda
    ((from-ctx to-ctx)
     (context-switch! from-ctx to-ctx #f))
    ((from-ctx to-ctx send-val)
     (if (not (coroutine-context? from-ctx))
         (error "context-switch!: from-ctx must be <coroutine-context> (CWE-843)" from-ctx)
         (let ((from-stk (coroutine-stack from-ctx))
               (to-stk (%validate-resumable-coroutine! "context-switch!" to-ctx)))
           (if (task-stack-freed? from-stk)
               (error "context-switch!: from-ctx stack has been freed (CWE-416)" from-ctx)
               (if (not (task-stack-check-canary from-stk))
                   (error "context-switch!: from-ctx stack canary corrupted (CWE-787)" from-ctx)
                   (let ((res (%asm-switch-task! (task-stack-top from-stk)
                                                 (task-stack-top to-stk)
                                                 send-val)))
                     (if (not (task-stack-check-canary from-stk))
                         (error "context-switch!: stack canary corrupted upon resume (CWE-787)" from-ctx)
                         res)))))))))

(define (swap-context! old-sp-ptr new-sp)
  (if (or (not (integer? old-sp-ptr)) (<= old-sp-ptr 0))
      (error "swap-context!: old-sp-ptr must be a positive integer address" old-sp-ptr)
      (if (or (not (integer? new-sp)) (<= new-sp 0))
          (error "swap-context!: new-sp must be a positive integer address" new-sp)
          (%asm-swap-context! old-sp-ptr new-sp))))

;; -----------------------------------------------------------------------
;; 6. ABI Register Preservation, Alignment & 10M Endurance Verification
;; -----------------------------------------------------------------------

(define verify-swap-context-abi!
  (case-lambda
    (()
     (let* ((s1 (make-task-stack *context-default-stack-size*))
            (s2 (make-task-stack *context-default-stack-size*))
            (ok (verify-swap-context-abi! s1 s2)))
       (free-task-stack! s1)
       (free-task-stack! s2)
       ok))
    ((s1 s2)
     (if (or (not (task-stack? s1)) (not (task-stack? s2)))
         (error "verify-swap-context-abi!: expected two <task-stack> arguments" (cons s1 s2))
         (if (or (task-stack-freed? s1) (task-stack-freed? s2))
             (error "verify-swap-context-abi!: stack is freed" (cons s1 s2))
             (let ((ok (%asm-verify-swap-context-regs! (task-stack-top s1) (task-stack-top s2))))
               (and ok
                    (task-stack-check-canary s1)
                    (task-stack-check-canary s2))))))))

(define bench-swap-context!
  (case-lambda
    ((total-switches)
     (let* ((s1 (make-task-stack *context-default-stack-size*))
            (s2 (make-task-stack *context-default-stack-size*))
            (completed (bench-swap-context! total-switches s1 s2)))
       (free-task-stack! s1)
       (free-task-stack! s2)
       completed))
    ((total-switches s1 s2)
     (if (or (not (integer? total-switches)) (<= total-switches 0))
         (error "bench-swap-context!: total-switches must be a positive integer" total-switches)
         (if (or (not (task-stack? s1)) (not (task-stack? s2)))
             (error "bench-swap-context!: expected two <task-stack> arguments" (cons s1 s2))
             (let ((completed (%asm-bench-swap-context! (task-stack-top s1)
                                                        (task-stack-top s2)
                                                        total-switches)))
               (if (not (and (task-stack-check-canary s1) (task-stack-check-canary s2)))
                   (error "bench-swap-context!: stack canary corrupted during benchmark" completed)
                   completed)))))))

(define (context-stats)
  (list (cons 'total-switches (%asm-get-trampoline-addr 3))
        (cons 'active-task-top (%asm-get-trampoline-addr 4))
        (cons 'entry-trampoline (%asm-get-trampoline-addr 0))
        (cons 'exit-trampoline (%asm-get-trampoline-addr 1))
        (cons 'swap-context-addr (%asm-get-trampoline-addr 2))))

