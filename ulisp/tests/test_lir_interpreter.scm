;;; =======================================================================
;;; Unit Test Suite: ULisp Canonical LIR Reference Virtual Machine
;;; Conforms to DSN-33 §2, DSN-33-02 §7.1, DSN-38 §2 K3, and Issue #834
;;; =======================================================================

(test-begin "ULisp Canonical LIR Reference Virtual Machine (Issue #834)")

;; Helper to build test LIR programs
(define (make-test-lir-prog funcs main-insts)
  (list '%lir-program
        '(strings ())
        '(stackmaps ())
        (cons '%lir-functions funcs)
        (list '%lir-main
              '(frame-size 64)
              (cons 'body main-insts))))

;;; -----------------------------------------------------------------------
;;; Group 1: Basic ALU & Bitwise Operations
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Basic ALU & Bitwise Operations ---\n")

;; 1.1 %mov immediate and register transfer
(define p-1-1
  (make-test-lir-prog '()
    '((%mov %rax 1234)
      (%mov %rbx %rax)
      (%mov %rax %rbx)
      (%return))))
(assert-equal "1.1 %mov immediate and register" 1234 (eval-lir-program p-1-1))

;; 1.2 %add and %raw-add
(define p-1-2
  (make-test-lir-prog '()
    '((%mov %rax 25)
      (%mov %rbx 17)
      (%add %rax %rbx)
      (%raw-add %rax 8)
      (%return))))
(assert-equal "1.2 %add and %raw-add" 50 (eval-lir-program p-1-2))

;; 1.3 %sub and %raw-sub
(define p-1-3
  (make-test-lir-prog '()
    '((%mov %rax 100)
      (%mov %rbx 35)
      (%sub %rax %rbx)
      (%raw-sub %rax 5)
      (%return))))
(assert-equal "1.3 %sub and %raw-sub" 60 (eval-lir-program p-1-3))

;; 1.4 %imul and %raw-mul
(define p-1-4
  (make-test-lir-prog '()
    '((%mov %rax -7)
      (%mov %rbx 6)
      (%imul %rax %rbx)
      (%return))))
(assert-equal "1.4 %imul signed multiplication" -42 (eval-lir-program p-1-4))

;; 1.5 %neg and %inc
(define p-1-5
  (make-test-lir-prog '()
    '((%mov %rax 41)
      (%inc %rax)
      (%neg %rax)
      (%return))))
(assert-equal "1.5 %neg and %inc" -42 (eval-lir-program p-1-5))

;; 1.6 %cqo and %idiv
(define p-1-6
  (make-test-lir-prog '()
    '((%mov %rax 105)
      (%cqo)
      (%mov %rbx 10)
      (%idiv %rbx)
      (%return))))
(assert-equal "1.6 %idiv quotient in rax" 10 (eval-lir-program p-1-6))

;; 1.7 %idiv remainder in rdx
(define p-1-7
  (make-test-lir-prog '()
    '((%mov %rax 105)
      (%cqo)
      (%mov %rbx 10)
      (%idiv %rbx)
      (%mov %rax %rdx)
      (%return))))
(assert-equal "1.7 %idiv remainder in rdx" 5 (eval-lir-program p-1-7))

;; 1.8 %udiv and %urem
(define p-1-8
  (make-test-lir-prog '()
    '((%mov %rax 250)
      (%mov %rbx 30)
      (%udiv %rbx)
      (%return))))
(assert-equal "1.8 %udiv unsigned division" 8 (eval-lir-program p-1-8))

(define p-1-8b
  (make-test-lir-prog '()
    '((%mov %rax 250)
      (%mov %rbx 30)
      (%urem %rbx)
      (%return))))
(assert-equal "1.8b %urem unsigned modulo" 10 (eval-lir-program p-1-8b))

;; 1.9 %bit-and, %bit-or, %bit-xor, %not
(define p-1-9
  (make-test-lir-prog '()
    '((%mov %rax 12)  ; 1100
      (%mov %rbx 10)  ; 1010
      (%bit-and %rax %rbx) ; 1000 = 8
      (%bit-or %rax 1)     ; 1001 = 9
      (%bit-xor %rax 3)    ; 1001 ^ 0011 = 1010 = 10
      (%return))))
(assert-equal "1.9 bitwise operations" 10 (eval-lir-program p-1-9))

;; 1.10 %shl, %shr, %sar
(define p-1-10
  (make-test-lir-prog '()
    '((%mov %rax 3)
      (%shl %rax 4) ; 3 << 4 = 48
      (%shr %rax 2) ; 48 >> 2 = 12
      (%return))))
(assert-equal "1.10 %shl and %shr" 12 (eval-lir-program p-1-10))

(define p-1-10b
  (make-test-lir-prog '()
    '((%mov %rax -16)
      (%sar %rax 2) ; -16 >> 2 = -4
      (%return))))
(assert-equal "1.10b %sar arithmetic right shift" -4 (eval-lir-program p-1-10b))

;;; -----------------------------------------------------------------------
;;; Group 2: Overflow-Checked & Unsigned Arithmetic (Issue #828)
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Overflow-Checked & Unsigned Arithmetic ---\n")

;; 2.1 %add-overflow without overflow
(define vm-2-1 (make-lir-vm))
(define p-2-1
  (make-test-lir-prog '()
    '((%mov %rax 100)
      (%mov %rbx 200)
      (%add-overflow %rax %rbx)
      (%return))))
(lir-vm-load! vm-2-1 p-2-1)
(lir-vm-run! vm-2-1)
(assert-equal "2.1 %add-overflow result" 300 (vm-get-reg vm-2-1 '%rax))
(assert-equal "2.1 %add-overflow OF = 0" 0 (vm-flag-of vm-2-1))

;; 2.2 %add-overflow with overflow (exceeding max signed 64-bit)
(define vm-2-2 (make-lir-vm))
(define p-2-2
  (make-test-lir-prog '()
    '((%mov %rax #x7fffffffffffffff)
      (%mov %rbx 1)
      (%add-overflow %rax %rbx)
      (%return))))
(lir-vm-load! vm-2-2 p-2-2)
(lir-vm-run! vm-2-2)
(assert-equal "2.2 %add-overflow OF = 1" 1 (vm-flag-of vm-2-2))

;; 2.3 %sub-overflow without overflow
(define vm-2-3 (make-lir-vm))
(define p-2-3
  (make-test-lir-prog '()
    '((%mov %rax 50)
      (%mov %rbx 20)
      (%sub-overflow %rax %rbx)
      (%return))))
(lir-vm-load! vm-2-3 p-2-3)
(lir-vm-run! vm-2-3)
(assert-equal "2.3 %sub-overflow result" 30 (vm-get-reg vm-2-3 '%rax))
(assert-equal "2.3 %sub-overflow OF = 0" 0 (vm-flag-of vm-2-3))

;; 2.4 %sub-overflow with overflow (underflow below min signed 64-bit)
(define vm-2-4 (make-lir-vm))
(define p-2-4
  (make-test-lir-prog '()
    '((%mov %rax -9223372036854775808)
      (%mov %rbx 1)
      (%sub-overflow %rax %rbx)
      (%return))))
(lir-vm-load! vm-2-4 p-2-4)
(lir-vm-run! vm-2-4)
(assert-equal "2.4 %sub-overflow OF = 1" 1 (vm-flag-of vm-2-4))

;; 2.5 %mul-overflow without overflow
(define vm-2-5 (make-lir-vm))
(define p-2-5
  (make-test-lir-prog '()
    '((%mov %rax 1000)
      (%mov %rbx 2000)
      (%mul-overflow %rax %rbx)
      (%return))))
(lir-vm-load! vm-2-5 p-2-5)
(lir-vm-run! vm-2-5)
(assert-equal "2.5 %mul-overflow result" 2000000 (vm-get-reg vm-2-5 '%rax))
(assert-equal "2.5 %mul-overflow OF = 0" 0 (vm-flag-of vm-2-5))

;; 2.6 %mul-overflow with overflow
(define vm-2-6 (make-lir-vm))
(define p-2-6
  (make-test-lir-prog '()
    '((%mov %rax #x4000000000000000)
      (%mov %rbx 4)
      (%mul-overflow %rax %rbx)
      (%return))))
(lir-vm-load! vm-2-6 p-2-6)
(lir-vm-run! vm-2-6)
(assert-equal "2.6 %mul-overflow OF = 1" 1 (vm-flag-of vm-2-6))

;; 2.7 %uadd without carry
(define vm-2-7 (make-lir-vm))
(define p-2-7
  (make-test-lir-prog '()
    '((%mov %rax 10)
      (%mov %rbx 20)
      (%uadd %rax %rbx)
      (%return))))
(lir-vm-load! vm-2-7 p-2-7)
(lir-vm-run! vm-2-7)
(assert-equal "2.7 %uadd result" 30 (vm-get-reg vm-2-7 '%rax))
(assert-equal "2.7 %uadd CF = 0" 0 (vm-flag-cf vm-2-7))

;; 2.8 %uadd with carry
(define vm-2-8 (make-lir-vm))
(define p-2-8
  (make-test-lir-prog '()
    '((%mov %rax #xffffffffffffffff)
      (%mov %rbx 5)
      (%uadd %rax %rbx)
      (%return))))
(lir-vm-load! vm-2-8 p-2-8)
(lir-vm-run! vm-2-8)
(assert-equal "2.8 %uadd CF = 1" 1 (vm-flag-cf vm-2-8))
(assert-equal "2.8 %uadd wrapped result" 4 (vm-get-reg vm-2-8 '%rax))

;; 2.9 %usub with borrow
(define vm-2-9 (make-lir-vm))
(define p-2-9
  (make-test-lir-prog '()
    '((%mov %rax 5)
      (%mov %rbx 10)
      (%usub %rax %rbx)
      (%return))))
(lir-vm-load! vm-2-9 p-2-9)
(lir-vm-run! vm-2-9)
(assert-equal "2.9 %usub CF = 1" 1 (vm-flag-cf vm-2-9))

;; 2.10 %umul with carry
(define vm-2-10 (make-lir-vm))
(define p-2-10
  (make-test-lir-prog '()
    '((%mov %rax #xffffffffffffffff)
      (%mov %rbx 2)
      (%umul %rax %rbx)
      (%return))))
(lir-vm-load! vm-2-10 p-2-10)
(lir-vm-run! vm-2-10)
(assert-equal "2.10 %umul CF = 1" 1 (vm-flag-cf vm-2-10))

;;; -----------------------------------------------------------------------
;;; Group 3: Memory Operations & Typed Access (Issue #826)
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Memory Operations & Typed Access ---\n")

;; 3.1 64-bit store and load
(define p-3-1
  (make-test-lir-prog '()
    '((%mov %rax 9876543210)
      (%store %rsp -8 %rax)
      (%load %rbx %rsp -8)
      (%mov %rax %rbx)
      (%return))))
(assert-equal "3.1 64-bit store and load" 9876543210 (eval-lir-program p-3-1))

;; 3.2 8-bit byte store and zero-extended load
(define p-3-2
  (make-test-lir-prog '()
    '((%mov %rax 250)
      (%store-byte %rsp -8 %rax)
      (%load-byte-zx %rbx %rsp -8)
      (%mov %rax %rbx)
      (%return))))
(assert-equal "3.2 byte store and load-byte-zx" 250 (eval-lir-program p-3-2))

;; 3.3 Typed load/store signed vs unsigned 8-bit
(define p-3-3
  (make-test-lir-prog '()
    '((%mov %rax -20)
      (%store-typed i8 %rsp -8 %rax)
      (%load-typed i8 %rax %rsp -8)
      (%return))))
(assert-equal "3.3 %load-typed i8 sign preserves" -20 (eval-lir-program p-3-3))

(define p-3-3b
  (make-test-lir-prog '()
    '((%mov %rax -20)
      (%store-typed u8 %rsp -8 %rax)
      (%load-typed u8 %rax %rsp -8)
      (%return))))
(assert-equal "3.3b %load-typed u8 zero-extends" 236 (eval-lir-program p-3-3b))

;; 3.4 Typed 16-bit and 32-bit access
(define p-3-4
  (make-test-lir-prog '()
    '((%mov %rax -1000)
      (%store-typed i16 %rsp -16 %rax)
      (%load-typed i16 %rax %rsp -16)
      (%return))))
(assert-equal "3.4 %load-typed i16" -1000 (eval-lir-program p-3-4))

(define p-3-4b
  (make-test-lir-prog '()
    '((%mov %rax -500000)
      (%store-typed i32 %rsp -24 %rax)
      (%load-typed i32 %rax %rsp -24)
      (%return))))
(assert-equal "3.4b %load-typed i32" -500000 (eval-lir-program p-3-4b))

;; 3.5 SIB offset addressing (%sib idx scale disp)
(define p-3-5
  (make-test-lir-prog '()
    '((%mov %rax 100)
      (%mov %rcx 2) ; index = 2
      ;; store 100 at rsp - 32 + (rcx * 8 + 0) = rsp - 16
      (%store %rsp (%sib %rcx 8 -32) %rax)
      ;; load from rsp - 16 directly
      (%load %rbx %rsp -16)
      (%mov %rax %rbx)
      (%return))))
(assert-equal "3.5 SIB addressing store and load" 100 (eval-lir-program p-3-5))

;; 3.6 %push and %pop
(define p-3-6
  (make-test-lir-prog '()
    '((%mov %rax 777)
      (%push %rax)
      (%mov %rax 0)
      (%pop %rax)
      (%return))))
(assert-equal "3.6 %push and %pop" 777 (eval-lir-program p-3-6))

;; 3.7 String literal (%str-ref)
(define p-3-7
  (list '%lir-program
        '(strings ((msg "Hello, LIR!")))
        '(stackmaps ())
        '(%lir-functions)
        (list '%lir-main
              '(frame-size 16)
              '(body
                (%str-ref %rax msg)
                (%load %rbx %rax -11) ; String length header is at ptr - 3 - 8 = ptr - 11
                (%mov %rax %rbx)
                (%return)))))
(assert-equal "3.7 %str-ref length header" 11 (eval-lir-program p-3-7))

;;; -----------------------------------------------------------------------
;;; Group 4: SSA Block Arguments & Parallel Assignment (Issue #827)
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: SSA Block Arguments & Parallel Assignment ---\n")

;; 4.1 Simple block jump with parameter
(define p-4-1
  (make-test-lir-prog '()
    '((%jump target (99))
      (%block target (x)
        (%mov %rax x)
        (%return)))))
(assert-equal "4.1 SSA single parameter jump" 99 (eval-lir-program p-4-1))

;; 4.2 SSA Parallel Swap (%jump swap (y x))
(define p-4-2
  (make-test-lir-prog '()
    '((%jump swap_blk (10 20))
      (%block swap_blk (x y)
        (%cmp x 20)
        (%jump-cond e done)
        ;; Swap x and y in parallel
        (%jump swap_blk (y x)))
      (%label done)
      (%mov %rax x)
      (%return))))
(assert-equal "4.2 SSA parallel swap argument passing" 20 (eval-lir-program p-4-2))

;; 4.3 SSA Loop: Sum of 1..10 = 55
(define p-4-3
  (make-test-lir-prog '()
    '((%jump loop_header (0 1))
      (%block loop_header (sum i)
        (%cmp i 10)
        (%jump-cond g loop_exit)
        (%add sum i)
        (%add i 1)
        (%jump loop_header (sum i)))
      (%label loop_exit)
      (%mov %rax sum)
      (%return))))
(assert-equal "4.3 SSA loop sum 1..10" 55 (eval-lir-program p-4-3))

;;; -----------------------------------------------------------------------
;;; Group 5: Control Flow & Conditional Branches
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Control Flow & Conditional Branches ---\n")

;; 5.1 %jump-if branch (then/else)
(define p-5-1
  (make-test-lir-prog '()
    '((%mov %rax 111) ; #t (0x6F)
      (%jump-if %rax t_path (10) e_path (20))
      (%block t_path (v)
        (%mov %rax v)
        (%return))
      (%block e_path (v)
        (%mov %rax v)
        (%return)))))
(assert-equal "5.1 %jump-if true branch" 10 (eval-lir-program p-5-1))

(define p-5-1b
  (make-test-lir-prog '()
    '((%mov %rax 47) ; #f (0x2F)
      (%jump-if %rax t_path (10) e_path (20))
      (%block t_path (v)
        (%mov %rax v)
        (%return))
      (%block e_path (v)
        (%mov %rax v)
        (%return)))))
(assert-equal "5.1b %jump-if false branch" 20 (eval-lir-program p-5-1b))

;; 5.2 %jump-if-false branch
(define p-5-2
  (make-test-lir-prog '()
    '((%mov %rax 47) ; #f
      (%jump-if-false %rax false_path (77))
      (%mov %rax 0)
      (%return)
      (%block false_path (res)
        (%mov %rax res)
        (%return)))))
(assert-equal "5.2 %jump-if-false branch" 77 (eval-lir-program p-5-2))

;; 5.3 %set-boolean condition evaluation
(define p-5-3
  (make-test-lir-prog '()
    '((%mov %rax 42)
      (%cmp %rax 42)
      (%set-boolean %rbx e)
      (%mov %rax %rbx)
      (%return))))
(assert-equal "5.3 %set-boolean equal -> #t (111)" 111 (eval-lir-program p-5-3))

(define p-5-3b
  (make-test-lir-prog '()
    '((%mov %rax 42)
      (%cmp %rax 100)
      (%set-boolean %rbx e)
      (%mov %rax %rbx)
      (%return))))
(assert-equal "5.3b %set-boolean not-equal -> #f (47)" 47 (eval-lir-program p-5-3b))

;;; -----------------------------------------------------------------------
;;; Group 6: Procedure Calls & Recursion
;;; -----------------------------------------------------------------------
(display "\n--- Group 6: Procedure Calls & Recursion ---\n")

;; 6.1 Direct function call
(define p-6-1
  (make-test-lir-prog
    '((%lir-function add_double
        (params (x))
        (frame-size 16)
        (body
          (%mov %rax %rdi)
          (%add %rax %rdi)
          (%return))))
    '((%mov %rdi 21)
      (%direct-call add_double 0)
      (%return))))
(assert-equal "6.1 %direct-call leaf function" 42 (eval-lir-program p-6-1))

;; 6.2 Recursive factorial: fact(6) = 720
(define p-6-2
  (make-test-lir-prog
    '((%lir-function fact
        (params (n))
        (frame-size 16)
        (body
          (%cmp %rdi 1)
          (%jump-cond le base_case)
          (%push %rdi)
          (%sub %rdi 1)
          (%direct-call fact 0)
          (%pop %rdi)
          (%imul %rax %rdi)
          (%return)
          (%label base_case)
          (%mov %rax 1)
          (%return))))
    '((%mov %rdi 6)
      (%direct-call fact 0)
      (%return))))
(assert-equal "6.2 %direct-call recursive fact(6)" 720 (eval-lir-program p-6-2))

;; 6.3 Recursive fibonacci: fib(7) = 13
(define p-6-3
  (make-test-lir-prog
    '((%lir-function fib
        (params (n))
        (frame-size 32)
        (body
          (%cmp %rdi 1)
          (%jump-cond le base_fib)
          (%push %rdi)
          (%sub %rdi 1)
          (%direct-call fib 0)
          (%pop %rdi)
          (%push %rax) ; save fib(n-1)
          (%push %rdi)
          (%sub %rdi 2)
          (%direct-call fib 0)
          (%pop %rdi)
          (%pop %rbx) ; restore fib(n-1)
          (%add %rax %rbx)
          (%return)
          (%label base_fib)
          (%mov %rax %rdi)
          (%return))))
    '((%mov %rdi 7)
      (%direct-call fib 0)
      (%return))))
(assert-equal "6.3 %direct-call recursive fib(7)" 13 (eval-lir-program p-6-3))

;;; -----------------------------------------------------------------------
;;; Group 7: Floating-Point Operations (XMM)
;;; -----------------------------------------------------------------------
(display "\n--- Group 7: Floating-Point Operations (XMM) ---\n")

;; 7.1 %sitofp, %fadd, %fptosi
(define p-7-1
  (make-test-lir-prog '()
    '((%mov %rax 50)
      (%sitofp %xmm0 %rax)
      (%mov %rax 25)
      (%sitofp %xmm1 %rax)
      (%fadd %xmm0 %xmm1)
      (%fptosi %rax %xmm0)
      (%return))))
(assert-equal "7.1 %sitofp, %fadd, %fptosi" 75 (eval-lir-program p-7-1))

;; 7.2 %fsub, %fmul, %fdiv
(define p-7-2
  (make-test-lir-prog '()
    '((%mov %rax 100)
      (%sitofp %xmm0 %rax)
      (%mov %rax 20)
      (%sitofp %xmm1 %rax)
      (%fsub %xmm0 %xmm1) ; 80.0
      (%mov %rax 2)
      (%sitofp %xmm2 %rax)
      (%fdiv %xmm0 %xmm2) ; 40.0
      (%fptosi %rax %xmm0)
      (%return))))
(assert-equal "7.2 %fsub and %fdiv" 40 (eval-lir-program p-7-2))

;; 7.3 Float memory round-trip
(define p-7-3
  (make-test-lir-prog '()
    '((%mov %rax 123)
      (%sitofp %xmm0 %rax)
      (%store-typed f64 %rsp -8 %xmm0)
      (%load-typed f64 %xmm5 %rsp -8)
      (%fptosi %rax %xmm5)
      (%return))))
(assert-equal "7.3 float store and load typed f64" 123 (eval-lir-program p-7-3))

;;; -----------------------------------------------------------------------
;;; Group 8: Safety Traps & Defensive Mitigations (THREAT-834-1..4)
;;; -----------------------------------------------------------------------
(display "\n--- Group 8: Safety Traps & Defensive Mitigations ---\n")

;; 8.1 Memory Out-of-Bounds (NULL page address 0)
(define vm-8-1 (make-lir-vm))
(define p-8-1
  (make-test-lir-prog '()
    '((%mov %rax 0)
      (%load %rbx %rax 0)
      (%return))))
(lir-vm-load! vm-8-1 p-8-1)
(assert-equal "8.1 null-deref returns trapped status" 'trapped (lir-vm-run! vm-8-1))
(assert-equal "8.1 null-deref trap type is out-of-bounds" 'out-of-bounds (vm-trap-type (vm-last-trap vm-8-1)))

;; 8.2 Memory Out-of-Bounds (Beyond memory size)
(define vm-8-2 (make-lir-vm))
(define p-8-2
  (make-test-lir-prog '()
    '((%mov %rax #x7fffffffffffffff)
      (%store %rax 0 42)
      (%return))))
(lir-vm-load! vm-8-2 p-8-2)
(assert-equal "8.2 memory write beyond size is trapped" 'trapped (lir-vm-run! vm-8-2))
(assert-equal "8.2 out-of-bounds trap type" 'out-of-bounds (vm-trap-type (vm-last-trap vm-8-2)))

;; 8.3 Integer Division by Zero (%idiv 0)
(define vm-8-3 (make-lir-vm))
(define p-8-3
  (make-test-lir-prog '()
    '((%mov %rax 100)
      (%cqo)
      (%mov %rbx 0)
      (%idiv %rbx)
      (%return))))
(lir-vm-load! vm-8-3 p-8-3)
(assert-equal "8.3 %idiv zero is trapped" 'trapped (lir-vm-run! vm-8-3))
(assert-equal "8.3 division-by-zero trap type" 'division-by-zero (vm-trap-type (vm-last-trap vm-8-3)))

;; 8.4 Unsigned Division by Zero (%udiv 0)
(define vm-8-4 (make-lir-vm))
(define p-8-4
  (make-test-lir-prog '()
    '((%mov %rax 100)
      (%mov %rbx 0)
      (%udiv %rbx)
      (%return))))
(lir-vm-load! vm-8-4 p-8-4)
(assert-equal "8.4 %udiv zero is trapped" 'trapped (lir-vm-run! vm-8-4))
(assert-equal "8.4 %udiv division-by-zero trap" 'division-by-zero (vm-trap-type (vm-last-trap vm-8-4)))

;; 8.5 Execution Fuel Limit (Infinite loop DoS prevention)
(define vm-8-5 (make-lir-vm))
(vm-set-fuel! vm-8-5 100)
(define p-8-5
  (make-test-lir-prog '()
    '((%label spin)
      (%jump spin ())
      (%return))))
(lir-vm-load! vm-8-5 p-8-5)
(assert-equal "8.5 fuel exhausted is trapped" 'trapped (lir-vm-run! vm-8-5))
(assert-equal "8.5 out-of-fuel trap type" 'out-of-fuel (vm-trap-type (vm-last-trap vm-8-5)))

;; 8.6 Undefined Label Jump Trap
(define vm-8-6 (make-lir-vm))
(define p-8-6
  (make-test-lir-prog '()
    '((%jump non_existent_label ())
      (%return))))
(lir-vm-load! vm-8-6 p-8-6)
(assert-equal "8.6 undefined label is trapped" 'trapped (lir-vm-run! vm-8-6))
(assert-equal "8.6 undefined-target trap type" 'undefined-target (vm-trap-type (vm-last-trap vm-8-6)))

;;; -----------------------------------------------------------------------
;;; Group 9: Existing LIR Fixtures Validation
;;; -----------------------------------------------------------------------
(display "\n--- Group 9: Existing LIR Fixtures Validation ---\n")

(define f1 (with-input-from-file "tests/fixtures/lir/01_const_int.lir" read))
(define f2 (with-input-from-file "tests/fixtures/lir/02_add.lir" read))
(define f3 (with-input-from-file "tests/fixtures/lir/03_branch.lir" read))

(assert-equal "9.1 fixture 01_const_int evaluates to 84" 84 (eval-lir-program f1))
(assert-equal "9.2 fixture 02_add evaluates to 60" 60 (eval-lir-program f2))
(assert-equal "9.3 fixture 03_branch evaluates to 200" 200 (eval-lir-program f3))

(test-end "ULisp Canonical LIR Reference Virtual Machine (Issue #834)")
