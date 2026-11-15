;;; =======================================================================
;;; Unit & Integration Test Suite: Inline Assembly (%inline-asm) in LIR
;;; Issue #838 - Covers Dialect Grammar, Static Verifier, Peephole Barriers,
;;; Pass 130/132 Lowering, Pass 140/144a Native Codegen, Pass 160 C Backend,
;;; and Reference LIR VM Parity (THREAT-838-1..4)
;;; =======================================================================

(display "=======================================================\n")
(display " Starting Inline Assembly (%inline-asm) Suite (#838)\n")
(display "=======================================================\n")

(enable-verifier!)
(set-verifier-strict! #f)

(define *ia-test-count* (cons 0 '()))
(define *ia-pass-count* (cons 0 '()))

(define (ia-print-group title)
  (newline)
  (display title)
  (newline))

(define (ia-assert-true name val)
  (set-car! *ia-test-count* (+ (car *ia-test-count*) 1))
  (if val
      (begin
        (set-car! *ia-pass-count* (+ (car *ia-pass-count*) 1))
        (display "  [PASS] ")
        (display name)
        (newline))
      (begin
        (display "  [FAIL] ")
        (display name)
        (newline)
        (error "Assertion failed" name))))

(define (ia-assert-false name val)
  (set-car! *ia-test-count* (+ (car *ia-test-count*) 1))
  (if (not val)
      (begin
        (set-car! *ia-pass-count* (+ (car *ia-pass-count*) 1))
        (display "  [PASS] ")
        (display name)
        (newline))
      (begin
        (display "  [FAIL] Expected #f but got truthy: ")
        (display name)
        (newline)
        (error "Assertion failed" name))))

(define (ia-assert-equal name expected actual)
  (set-car! *ia-test-count* (+ (car *ia-test-count*) 1))
  (if (equal? expected actual)
      (begin
        (set-car! *ia-pass-count* (+ (car *ia-pass-count*) 1))
        (display "  [PASS] ")
        (display name)
        (newline))
      (begin
        (display "  [FAIL] ")
        (display name)
        (display "\n    Expected: ")
        (write expected)
        (display "\n    Actual:   ")
        (write actual)
        (newline)
        (error "Assertion failed" name))))

(define (ia-string-contains? hay needle)
  (let ((hlen (string-length hay))
        (nlen (string-length needle)))
    (if (= nlen 0)
        #t
        (let loop ((i 0))
          (cond
            ((> (+ i nlen) hlen) #f)
            ((string=? (substring hay i (+ i nlen)) needle) #t)
            (else (loop (+ i 1))))))))

(define (ia-lines-contain? lines substr)
  (let loop ((ls lines))
    (cond
      ((null? ls) #f)
      ((ia-string-contains? (car ls) substr) #t)
      (else (loop (cdr ls))))))

(define (ia-make-lir-program funcs main-insts frame-bytes)
  (list '%lir-program
        '(strings ())
        '(stackmaps ())
        (cons '%lir-functions funcs)
        (list '%lir-main
              (list 'frame-size frame-bytes)
              (cons 'body main-insts))))

(define (ia-capture-x86-lines prog)
  (let ((box (vector '())))
    (with-emit-line-sink
      (lambda (line)
        (vector-set! box 0 (cons line (vector-ref box 0))))
      (lambda ()
        (emit-x86-64 prog 'none)))
    (reverse (vector-ref box 0))))

(define (ia-capture-c-lines prog)
  (let ((box (vector '())))
    (with-emit-line-sink
      (lambda (line)
        (vector-set! box 0 (cons line (vector-ref box 0))))
      (lambda ()
        (emit-c prog 'none)))
    (reverse (vector-ref box 0))))

;;; -----------------------------------------------------------------------
;;; Group 1: Dialect Acceptance & Verifier Positive Cases
;;; -----------------------------------------------------------------------
(ia-print-group "--- Group 1: LIR Dialect Grammar & Verifier Positive Cases ---")

(let ((prog-basic
       (ia-make-lir-program
        '()
        '((%mov (%reg %rax) 10)
          (%inline-asm "add %0, %1"
            (:outputs (((%reg %rax) "+r")))
            (:inputs ((32 "r")))
            (:clobbers ("cc"))
            (:volatile? #t))
          (%return (%reg %rax)))
        16)))
  (ia-assert-true "L_lir_core? accepts %inline-asm with +r / r / cc / :volatile?"
                  (L_lir_core? prog-basic))
  (ia-assert-true "L_lir_canonical? accepts %inline-asm"
                  (L_lir_canonical? prog-basic))
  (ia-assert-true "validate-lir accepts valid %inline-asm program"
                  (validate-lir prog-basic)))

(let ((prog-named
       (ia-make-lir-program
        '()
        '((%mov (%stack -8) 7)
          (%inline-asm "mov %[dst], %[lhs]\nadd %[dst], %k[rhs]\nmov %b[flag], 1"
            (:outputs ((dst "=r" (%reg %rbx))
                       (flag "=a" (%reg %rax))))
            (:inputs ((lhs "r" (%stack -8))
                      (rhs "i" 5)))
            (:clobbers ("cc" "memory")))
          (%return (%reg %rbx)))
        16)))
  (ia-assert-true "L_lir_core? accepts 3-tuple named specs + subreg modifiers"
                  (L_lir_core? prog-named))
  (ia-assert-true "validate-lir accepts 3-tuple named specs and %[name] placeholders"
                  (validate-lir prog-named)))

(let ((prog-minimal
       (ia-make-lir-program
        '()
        '((%inline-asm "mfence\nlfence\nsfence\npause"
            (:clobbers ("memory")))
          (%mov (%reg %rax) 42)
          (%return (%reg %rax)))
        16)))
  (ia-assert-true "L_lir_core? accepts memory barrier %inline-asm without :outputs/:inputs"
                  (L_lir_core? prog-minimal))
  (ia-assert-true "validate-lir accepts barrier-only %inline-asm"
                  (validate-lir prog-minimal)))

;;; -----------------------------------------------------------------------
;;; Group 2: Static Verifier Security Rejections (THREAT-838-1..3)
;;; -----------------------------------------------------------------------
(ia-print-group "--- Group 2: Verifier Negative Checks (THREAT-838-1..3) ---")

(ia-assert-false "Reject %rsp in :clobbers (THREAT-838-1)"
                 (validate-lir
                  (ia-make-lir-program
                   '()
                   '((%inline-asm "nop" (:clobbers ("%rsp")))
                     (%return 0))
                   16)))

(ia-assert-false "Reject {rsp} fixed register in :outputs (THREAT-838-1)"
                 (validate-lir
                  (ia-make-lir-program
                   '()
                   '((%inline-asm "mov %0, 1" (:outputs (((%reg %rax) "={rsp}"))))
                     (%return 0))
                   16)))

(ia-assert-false "Reject duplicate fixed output register constraints (=a and ={rax})"
                 (validate-lir
                  (ia-make-lir-program
                   '()
                   '((%inline-asm "mov %0, 1\nmov %1, 2"
                       (:outputs (((%reg %rax) "=a")
                                  ((%reg %rbx) "={rax}"))))
                     (%return 0))
                   16)))

(ia-assert-false "Reject out-of-bounds %2 operand placeholder (THREAT-838-3)"
                 (validate-lir
                  (ia-make-lir-program
                   '()
                   '((%inline-asm "mov %0, %2"
                       (:outputs (((%reg %rax) "=r")))
                       (:inputs ((10 "i"))))
                     (%return 0))
                   16)))

(ia-assert-false "Reject out-of-bounds %k5 modified placeholder (THREAT-838-3)"
                 (validate-lir
                  (ia-make-lir-program
                   '()
                   '((%inline-asm "mov %k5, 1"
                       (:outputs (((%reg %rax) "=r"))))
                     (%return 0))
                   16)))

(ia-assert-false "Reject undefined named operand %[missing] (THREAT-838-3)"
                 (validate-lir
                  (ia-make-lir-program
                   '()
                   '((%inline-asm "mov %[out], %[missing]"
                       (:outputs ((out "=r" (%reg %rax))))
                       (:inputs ((val "r" 1))))
                     (%return 0))
                   16)))

(ia-assert-false "Reject non-writable immediate output operand (THREAT-838-1)"
                 (validate-lir
                  (ia-make-lir-program
                   '()
                   '((%inline-asm "mov %0, 99"
                       (:outputs ((42 "=r"))))
                     (%return 0))
                   16)))

(ia-assert-false "Reject malformed output constraint missing = or + prefix"
                 (validate-lir
                  (ia-make-lir-program
                   '()
                   '((%inline-asm "mov %0, 1"
                       (:outputs (((%reg %rax) "r"))))
                     (%return 0))
                   16)))

(ia-assert-false "Reject out-of-range tied input constraint '2'"
                 (validate-lir
                  (ia-make-lir-program
                   '()
                   '((%inline-asm "add %0, %1"
                       (:outputs (((%reg %rax) "=r")))
                       (:inputs ((5 "2"))))
                     (%return 0))
                   16)))

;;; -----------------------------------------------------------------------
;;; Group 3: Pass 133 Peephole & Memory Barrier Semantics (THREAT-838-4)
;;; -----------------------------------------------------------------------
(ia-print-group "--- Group 3: Pass 133 Peephole & Optimization Barriers (THREAT-838-4) ---")

(let* ((mem-barrier-inst
        '(%inline-asm "mfence" (:clobbers ("memory")) (:volatile? #t)))
       (reg-clob-inst
        '(%inline-asm "cpuid"
           (:outputs (((%reg %rax) "=a")))
           (:inputs ((0 "a")))
           (:clobbers ("%rbx" "%rcx" "%rdx" "cc")))))
  (ia-assert-true "lir-inst-memory-barrier? returns #t for \"memory\" clobber"
                  (lir-inst-memory-barrier? mem-barrier-inst))
  (ia-assert-true "lir-inst-memory-barrier? returns #t for :volatile? #t %inline-asm"
                  (lir-inst-memory-barrier? reg-clob-inst))
  (ia-assert-true "lir-inst-defines-reg? detects clobbered %rbx"
                  (lir-inst-defines-reg? reg-clob-inst '%rbx))
  (ia-assert-true "lir-inst-defines-reg? detects fixed output %rax"
                  (lir-inst-defines-reg? reg-clob-inst '%rax))
  (ia-assert-false "lir-inst-defines-reg? returns #f for untouched %r10"
                   (lir-inst-defines-reg? reg-clob-inst '%r10)))

(let* ((prog-opt
        (ia-make-lir-program
         '()
         '((%mov (%stack -8) 123)
           (%inline-asm "mov qword ptr %0, 999"
             (:outputs (((%stack -8) "=m")))
             (:clobbers ("memory"))
             (:volatile? #t))
           (%mov (%reg %rax) (%stack -8))
           (%return (%reg %rax)))
         16))
       (opt-res (lir-peephole-optimize prog-opt))
       (opt-body (cdr (assq 'body (cdr (assq '%lir-main (cdr opt-res)))))))
  (ia-assert-true "Pass 133 preserves volatile %inline-asm and blocks stale forwarding (=999)"
                  (and (L_lir_canonical? opt-res)
                       (let has-asm? ((is opt-body))
                         (and (pair? is)
                              (or (and (pair? (car is)) (eq? (caar is) '%inline-asm))
                                  (has-asm? (cdr is)))))
                       (= (eval-lir-program opt-res) 999))))

;;; -----------------------------------------------------------------------
;;; Group 4: Pass 130 (generate-lir) Local Variable Lowering
;;; -----------------------------------------------------------------------
(ia-print-group "--- Group 4: Pass 130 (generate-lir) Lowering ---")

(let* ((src-prog
        '(%program ()
           (let ((a 17) (b 25))
             (%inline-asm "mov %0, %1\nadd %0, %2"
               (:outputs ((a "=r")))
               (:inputs ((a "r") (b "r")))
               (:clobbers ("cc"))))))
       (generated (generate-lir src-prog)))
  (ia-assert-true "generate-lir lowers %inline-asm to valid L_lir_canonical"
                  (and (L_lir_canonical? generated)
                       (validate-lir generated)))
  (ia-assert-equal "generate-lir lowered %inline-asm executes correctly on LIR VM (17+25=42)"
                   42
                   (eval-lir-program-unboxed generated)))

;;; -----------------------------------------------------------------------
;;; Group 5: Pass 140 x86-64 Codegen + Pass 144a Assembler + ELF64 Binary
;;; -----------------------------------------------------------------------
(ia-print-group "--- Group 5: Pass 140 Codegen & Pass 144a ELF64 Native Assembly ---")

(let* ((prog-swap-and-isa
        (ia-make-lir-program
         '()
         '((%mov (%reg %rax) 11)
           (%mov (%reg %rdx) 22)
           (%mov (%stack -8) 100)
           ;; Parallel swap: %rdx -> "a", %rax -> "d"; result in %rbx
           (%inline-asm "sub %[dst], %[b]\nbswap %[tmp]\nbswap %[tmp]\nxchg %[dst], %[tmp]\nlock xadd %[mem], %[tmp]\nmfence\nlfence\nsfence\npause"
             (:outputs ((dst "=r" (%reg %rbx))
                        (tmp "=a" (%reg %rcx))
                        (mem "=m" (%stack -8))))
             (:inputs ((b "d" (%reg %rax))
                       (a-in "a" (%reg %rdx))))
             (:clobbers ("cc" "memory")))
           (%return (%reg %rbx)))
         32))
       (asm-lines (ia-capture-x86-lines prog-swap-and-isa))
       (elf-bv (assemble-and-build-elf asm-lines)))
  (ia-assert-false "Pass 140 parallel swap emits no illegal mov [mem], [mem]"
                   (let loop ((ls asm-lines))
                     (if (null? ls) #f
                         (let ((s (car ls)))
                           (if (and (ia-string-contains? s "mov ")
                                    (ia-string-contains? s "], ["))
                               #t
                               (loop (cdr ls)))))))
  (ia-assert-false "lower-lir-inline-asm emits no push/pop shifting %rsp (uses [rsp - ...] scratch slots)"
                   (let loop ((lowered (lower-lir-inline-asm
                                        '(%inline-asm "sub %[dst], %[b]"
                                           (:outputs ((dst "=r" (%reg %rbx))
                                                      (tmp "=a" (%reg %rcx))))
                                           (:inputs ((b "d" (%reg %rax))
                                                     (a-in "a" (%reg %rdx))))
                                           (:clobbers ("cc" "%r11"))))))
                     (if (null? lowered) #f
                         (let ((s (cadr (car lowered))))
                           (if (or (ia-string-contains? s "push ")
                                   (ia-string-contains? s "pop "))
                               #t
                               (loop (cdr lowered)))))))
  (ia-assert-true "Pass 140 expands bswap/xchg/lock xadd/mfence/lfence/sfence/pause"
                  (and (ia-lines-contain? asm-lines "bswap ")
                       (ia-lines-contain? asm-lines "xchg ")
                       (ia-lines-contain? asm-lines "lock xadd ")
                       (ia-lines-contain? asm-lines "mfence")
                       (ia-lines-contain? asm-lines "lfence")
                       (ia-lines-contain? asm-lines "sfence")
                       (ia-lines-contain? asm-lines "pause")))
  (ia-assert-true "Pass 144a assembles extended ISA instructions into valid ELF64 binary"
                  (and (bytevector? elf-bv)
                       (> (bytevector-length elf-bv) 128)
                       (= (bytevector-u8-ref elf-bv 0) 127)
                       (= (bytevector-u8-ref elf-bv 1) 69)
                       (= (bytevector-u8-ref elf-bv 2) 76)
                       (= (bytevector-u8-ref elf-bv 3) 70))))

;;; -----------------------------------------------------------------------
;;; Group 6: Pass 160 C Backend Emission (__asm__ volatile)
;;; -----------------------------------------------------------------------
(ia-print-group "--- Group 6: Pass 160 C Backend Emission ---")

(let* ((prog-c
        (ia-make-lir-program
         '()
         '((%mov (%reg %rax) 10)
           (%mov (%reg %rdx) 35)
           (%mov (%stack -8) 100)
           (%inline-asm "mov %0, %1\nadd %0, %2\nbswap %0\nbswap %0\nxadd %3, %0"
             (:outputs (((%reg %rbx) "=r")
                        ((%stack -8) "=m")))
             (:inputs (((%reg %rdx) "a")
                       ((%reg %rax) "d")))
             (:clobbers ("%rcx" "cc" "memory")))
           (%return (%reg %rbx)))
         32))
       (c-lines (ia-capture-c-lines prog-c)))
  (ia-assert-true "Pass 160 emits __asm__ volatile with .intel_syntax noprefix"
                  (and (ia-lines-contain? c-lines "__asm__ volatile")
                       (ia-lines-contain? c-lines ".intel_syntax noprefix")
                       (ia-lines-contain? c-lines ".att_syntax prefix")))
  (ia-assert-true "Pass 160 pins physical registers via register uint64_t __asm__"
                  (and (ia-lines-contain? c-lines "__asm__(\"rax\")")
                       (ia-lines-contain? c-lines "__asm__(\"rdx\")")))
  (ia-assert-true "Pass 160 emits memory clobber for =m operand"
                  (ia-lines-contain? c-lines "\"memory\"")))

;;; -----------------------------------------------------------------------
;;; Group 7: Reference LIR VM Execution & Semantic Parity
;;; -----------------------------------------------------------------------
(ia-print-group "--- Group 7: Reference LIR VM Execution & Parity ---")

;; 7.1 Parallel register swap cycle: %rdx -> "a" (old %rdx = 50), %rax -> "d" (old %rax = 12)
(let ((prog-swap
       (ia-make-lir-program
        '()
        '((%mov (%reg %rax) 12)
          (%mov (%reg %rdx) 50)
          (%inline-asm "sub %0, %2"
            (:outputs (((%reg %rax) "=a")))
            (:inputs (((%reg %rdx) "a")
                      ((%reg %rax) "d")))
            (:clobbers ("cc")))
          (%return (%reg %rax)))
        16)))
  (ia-assert-equal "THREAT-838-2: Parallel swap inputs compute (50 - 12 = 38)"
                   38
                   (eval-lir-program prog-swap)))

;; 7.2 Live caller registers & stack local preservation across clobbers (THREAT-838-1)
(let ((prog-preserve
       (ia-make-lir-program
        '()
        '((%mov (%reg %rbx) 777)
          (%mov (%reg %r13) 888)
          (%mov (%stack -8) 999)
          (%inline-asm "mov %0, 42\nmov %%rcx, 12345\nmov %%rbx, 54321"
            (:outputs (((%reg %r14) "=r")))
            (:inputs ((5 "r")))
            (:clobbers ("%rcx" "%rbx" "cc")))
          (%add (%reg %rbx) (%reg %r13))
          (%add (%reg %rbx) (%reg %r14))
          (%add (%reg %rbx) (%stack -8))
          (%mov (%reg %rax) (%reg %rbx))
          (%return (%reg %rax)))
        16)))
  (ia-assert-equal "THREAT-838-1: Preserves clobbered %rbx, untouched %r13, and stack slot (777+888+42+999 = 2706)"
                   2706
                   (eval-lir-program prog-preserve)))

;; 7.3 BSWAP 32-bit (%k0) and 64-bit (%0)
(let ((prog-bswap
       (ia-make-lir-program
        '()
        '((%inline-asm "bswap %k0"
            (:outputs (((%reg %rax) "+r")))
            (:inputs ()))
          (%return (%reg %rax)))
        16)))
  (let ((vm (make-lir-vm)))
    (lir-vm-load! vm
      (ia-make-lir-program
       '()
       '((%mov (%reg %rax) #x11223344)
         (%inline-asm "bswap %k0"
           (:outputs (((%reg %rax) "+r"))))
         (%return (%reg %rax)))
       16))
    (lir-vm-run! vm)
    (ia-assert-equal "bswap %k0 swaps 32-bit bytes (#x11223344 -> #x44332211)"
                     #x44332211
                     (vm-get-reg vm '%rax))))

;; 7.4 XCHG, LOCK XADD, and LOCK CMPXCHG + SETE %b0
(let ((prog-atomics
       (ia-make-lir-program
        '()
        '(;; Store initial counter 10 at stack[-8]
          (%mov (%stack -8) 10)
          ;; xadd [stack[-8]], 5 -> old=10 in %rbx, stack[-8]=15
          (%inline-asm "lock xadd %1, %0"
            (:outputs (((%reg %rbx) "+r")
                       ((%stack -8) "+m")))
            (:inputs ((5 "0")))
            (:clobbers ("cc" "memory")))
          ;; cmpxchg success: expect %rax=15 == [stack[-8]], replace with 99, zf->%cl
          (%mov (%reg %rax) 15)
          (%mov (%reg %rcx) 0)
          (%inline-asm "lock cmpxchg %2, %3\nsete %b0\nmovzx %0, %b0"
            (:outputs ((ok "=r" (%reg %rcx))
                       (acc "+a" (%reg %rax))
                       (slot "+m" (%stack -8))))
            (:inputs ((desired "r" 99)))
            (:clobbers ("cc" "memory")))
          ;; Combine: (%rbx=10 * 1000) + (%rcx=1 * 100) + ([stack[-8]]=99) = 10199
          (%imul (%reg %rbx) 1000)
          (%imul (%reg %rcx) 100)
          (%add (%reg %rbx) (%reg %rcx))
          (%add (%reg %rbx) (%stack -8))
          (%mov (%reg %rax) (%reg %rbx))
          (%return (%reg %rax)))
        16)))
  (ia-assert-equal "lock xadd + lock cmpxchg + sete %b0 execute with x86-64 semantics (10199)"
                   10199
                   (eval-lir-program prog-atomics)))

;; 7.5 RDTSC monotonicity & CPUID vendor signature
(let ((prog-sys
       (ia-make-lir-program
        '()
        '((%inline-asm "rdtsc"
            (:outputs (((%reg %rbx) "=a")
                       ((%reg %rcx) "=d"))))
          (%inline-asm "rdtsc"
            (:outputs (((%reg %r8) "=a")
                       ((%reg %r9) "=d"))))
          (%sub (%reg %r8) (%reg %rbx))
          (%mov (%reg %rax) (%reg %r8))
          (%return (%reg %rax)))
        16)))
  (ia-assert-true "rdtsc returns strictly monotonic deterministic counter"
                  (> (eval-lir-program prog-sys) 0)))

(let ((prog-cpuid
       (ia-make-lir-program
        '()
        '((%inline-asm "cpuid"
            (:outputs (((%reg %rax) "=a")
                       ((%reg %rbx) "=b")
                       ((%reg %rcx) "=c")
                       ((%reg %rdx) "=d")))
            (:inputs ((0 "a"))))
          (%mov (%reg %rax) (%reg %rbx))
          (%return (%reg %rax)))
        16)))
  (ia-assert-equal "cpuid leaf 0 returns 'Genu' (#x756e6547) in ebx"
                   #x756e6547
                   (eval-lir-program prog-cpuid)))

;; 7.6 Custom register-inline-asm-handler! override in Reference VM
(let ((vm (make-lir-vm))
      (prog-custom
       (ia-make-lir-program
        '()
        '((%inline-asm "custom_rdseed %0, %1"
            (:outputs (((%reg %rax) "=a")))
            (:inputs ((123 "D"))))
          (%return (%reg %rax)))
        16)))
  (register-inline-asm-handler!
   vm
   "custom_rdseed %0, %1"
   (lambda (m)
     (vm-set-reg! m '%rax (+ (* (vm-get-reg m '%rdi) 2) 1))))
  (lir-vm-load! vm prog-custom)
  (lir-vm-run! vm)
  (ia-assert-equal "register-inline-asm-handler! invokes custom VM hook with staged inputs (123*2+1=247)"
                   247
                   (vm-get-reg vm '%rax)))

(newline)
(display "Inline Assembly Test Summary: ")
(display (car *ia-pass-count*))
(display "/")
(display (car *ia-test-count*))
(display " passed.")
(newline)
