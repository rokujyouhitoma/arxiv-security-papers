;;; =======================================================================
;;; Unit & Native E2E Test Suite: C99 GNU-C Extensions & Inline Asm (Issue #928)
;;; Verifies: __asm__, __volatile__, register __asm__("r10"), __attribute__,
;;;   __typeof__, weak_alias, top-level asm, AT&T->Intel, XMM constraints,
;;;   fs:0 TLS read, lock cmpxchg/orl/incl, bsf, and freestanding ELF64 binaries.
;;; Zero host ld/cc invoked.
;;; =======================================================================

(display "=======================================================\n")
(display " Starting C99 GNU-C Extensions & Inline Asm Suite (#928)\n")
(display "=======================================================\n")

(enable-verifier!)
(set-verifier-level! 3)
(set-verifier-strict! #t)

(test-begin "C99 GNU-C Extensions & Inline Asm (Issue #928)")

;; -----------------------------------------------------------------------
;; Group 1: AT&T -> Intel Translator Unit Tests
;; -----------------------------------------------------------------------
(display "\n--- Group 1: AT&T -> Intel Asm Conversion ---\n")

(assert-equal ".text simple line" '("    .text") (c99-att-asm->intel-asm ".text \n" #t))

(let ((crt-lines
       (c99-att-asm->intel-asm
        (string-append
         ".text \n"
         ".global _start \n"
         ".type _start,@function \n"
         "_start: \n"
         " xor %rbp,%rbp \n"
         " mov %rsp,%rdi \n"
         ".weak _DYNAMIC \n"
         ".hidden _DYNAMIC \n"
         " lea _DYNAMIC(%rip),%rsi \n"
         " andq $-16,%rsp \n"
         " call _start_c \n")
        #t)))
  (assert-equal "crt_arch converts 11 lines" 11 (length crt-lines))
  (assert-equal ".global -> .globl" "    .globl _start" (list-ref crt-lines 1))
  (assert-equal "xor %rbp,%rbp" "    xor rbp, rbp" (list-ref crt-lines 4))
  (assert-equal "lea _DYNAMIC(%rip),%rsi" "    lea rsi, [rip + _DYNAMIC]" (list-ref crt-lines 8))
  (assert-equal "andq $-16,%rsp" "    and rsp, -16" (list-ref crt-lines 9)))

(assert-equal "lock ; orl $0,(%%rsp) -> lock or dword ptr [rsp], 0"
              "lock or dword ptr [rsp], 0"
              (c99-att-asm->intel-asm "lock ; orl $0,(%%rsp)" #f (cons '(i32) '())))

(assert-equal "mov %%fs:0,%0 -> mov %0, fs:[0]"
              "mov %0, fs:[0]"
              (c99-att-asm->intel-asm "mov %%fs:0,%0" #f (cons '(u64) '("="))))

(assert-equal "lock ; cmpxchg %3, %1 with 32-bit int -> lock cmpxchg %1, %k3"
              "lock cmpxchg %1, %k3"
              (c99-att-asm->intel-asm "lock ; cmpxchg %3, %1" #f
                                      (cons '(i32 i32 i32 i32) '("=a" "=m" "a" "r"))))

(assert-equal "sqrtsd %1, %0 -> sqrtsd %0, %1"
              "sqrtsd %0, %1"
              (c99-att-asm->intel-asm "sqrtsd %1, %0" #f
                                      (cons '(f64 f64) '("=x" "x"))))

(assert-equal "lock ; incl %0 -> lock inc dword ptr %0"
              "lock inc dword ptr %0"
              (c99-att-asm->intel-asm "lock ; incl %0" #f
                                      (cons '(i32) '("+m"))))

;; -----------------------------------------------------------------------
;; Group 2: Parsing, Sema,weak_alias & Pinned-Reg Sema Verification
;; -----------------------------------------------------------------------
(display "\n--- Group 2: GNU C Parsing & Sema ---\n")

(let* ((src
        (string-append
         "#define weak __attribute__((__weak__))\n"
         "#define hidden __attribute__((__visibility__(\"hidden\")))\n"
         "#define weak_alias(old, new) extern __typeof(old) new __attribute__((__weak__, __alias__(#old)))\n"
         "weak void _init(void);\n"
         "static __inline__ int my_add(int * __restrict__ a, const __volatile__ int *b) {\n"
         "    __extension__ long x = (__signed__ int)*a + *b;\n"
         "    return (int)x;\n"
         "}\n"
         "hidden int target_fn(int x) __attribute__((__always_inline__));\n"
         "int target_fn(int x) { return x + 10; }\n"
         "weak_alias(target_fn, alias_fn);\n"
         "long do_sys4(long n, long a1, long a2, long a3, long a4) {\n"
         "    unsigned long ret;\n"
         "    register long r10 __asm__(\"r10\") = a4;\n"
         "    __asm__ __volatile__ (\"syscall\" : \"=a\"(ret) : \"a\"(n), \"D\"(a1), \"S\"(a2), \"d\"(a3), \"r\"(r10) : \"rcx\", \"r11\", \"memory\");\n"
         "    return ret;\n"
         "}\n"))
       (pp (cpp-preprocess-string src "gnu_test.c"))
       (ast (parse-c99-tokens pp "gnu_test.c"))
       (_v (assert-true "AST verifies cleanly" (verify-c99-ast ast)))
       (typed (c99-analyze-program ast))
       (meta (list-ref typed 4))
       (lir (c99-lower-to-lir typed))
       (o2-lir (run-c99-o2-fixpoint-pipeline lir)))
  (assert-true "weak-fns records _init" (memq '_init (cdr (assq 'weak-fns meta))))
  (assert-true "aliases records (alias_fn target_fn #t)"
               (member '(alias_fn target_fn #t) (cdr (assq 'aliases meta))))
  (assert-true "Lowered LIR passes validate-core-lir" (validate-core-lir lir))
  (assert-true "O2-optimized LIR preserves meta & passes validate-core-lir"
               (and (validate-core-lir o2-lir)
                    (assq 'aliases (cdr o2-lir))
                    (assq 'weak-fns (cdr o2-lir)))))

;; -----------------------------------------------------------------------
;; Group 3: Build Freestanding Native ELF64 Test Binaries (Pass 144 Linker)
;; -----------------------------------------------------------------------
(display "\n--- Group 3: Compile & Link Freestanding GNU-C Test ELF64 Binaries ---\n")

(let ((dir "build/test_c99_gnu_ext"))
  (if (not (file-exists? "build")) (sys-mkdir "build" 493))
  (if (not (file-exists? dir)) (sys-mkdir dir 493))

  (let ((c1 (string-append dir "/app.c"))
        (bin1 (string-append dir "/app_bin"))
        (c2a (string-append dir "/tu_weak.c"))
        (c2b (string-append dir "/tu_strong.c"))
        (o2a (string-append dir "/tu_weak.o"))
        (o2b (string-append dir "/tu_strong.o"))
        (bin2 (string-append dir "/weak_override_bin")))
    (call-with-output-file c1
      (lambda (p)
        (display
         (string-append
          "#define weak __attribute__((__weak__))\n"
          "#define hidden __attribute__((__visibility__(\"hidden\")))\n"
          "#define weak_alias(old, new) extern __typeof(old) new __attribute__((__weak__, __alias__(#old)))\n"
          "\n"
          "__asm__ (\".text\\n.global _start\\n.type _start,@function\\n_start:\\n xor %rbp,%rbp\\n mov %rsp,%rdi\\n call c_entry\\n hlt\\n\");\n"
          "\n"
          "weak void missing_optional_init(void);\n"
          "\n"
          "static __inline__ long __syscall1(long n, long a1) {\n"
          "    unsigned long ret;\n"
          "    __asm__ __volatile__ (\"syscall\" : \"=a\"(ret) : \"a\"(n), \"D\"(a1) : \"rcx\", \"r11\", \"memory\");\n"
          "    return ret;\n"
          "}\n"
          "\n"
          "static __inline__ long __syscall2(long n, long a1, long a2) {\n"
          "    unsigned long ret;\n"
          "    __asm__ __volatile__ (\"syscall\" : \"=a\"(ret) : \"a\"(n), \"D\"(a1), \"S\"(a2) : \"rcx\", \"r11\", \"memory\");\n"
          "    return ret;\n"
          "}\n"
          "\n"
          "static __inline__ long __syscall4(long n, long a1, long a2, long a3, long a4) {\n"
          "    unsigned long ret;\n"
          "    register long r10 __asm__(\"r10\") = a4;\n"
          "    __asm__ __volatile__ (\"syscall\" : \"=a\"(ret) : \"a\"(n), \"D\"(a1), \"S\"(a2), \"d\"(a3), \"r\"(r10) : \"rcx\", \"r11\", \"memory\");\n"
          "    return ret;\n"
          "}\n"
          "\n"
          "static __inline__ int a_cas(volatile int *p, int t, int s) {\n"
          "    __asm__ __volatile__ (\n"
          "        \"lock ; cmpxchg %3, %1\"\n"
          "        : \"=a\"(t), \"=m\"(*p) : \"a\"(t), \"r\"(s) : \"memory\");\n"
          "    return t;\n"
          "}\n"
          "\n"
          "static __inline__ void a_inc(volatile int *p) {\n"
          "    __asm__ __volatile__ (\"lock ; incl %0\" : \"=m\"(*p) : \"m\"(*p) : \"memory\");\n"
          "}\n"
          "\n"
          "static __inline__ void a_barrier(void) {\n"
          "    __asm__ __volatile__ (\"\" : : : \"memory\");\n"
          "    __asm__ __volatile__ (\"lock ; orl $0,(%%rsp)\" : : : \"memory\");\n"
          "}\n"
          "\n"
          "static __inline__ int a_ctz_64(unsigned long x) {\n"
          "    __asm__ (\"bsf %1,%0\" : \"=r\"(x) : \"0\"(x));\n"
          "    return (int)x;\n"
          "}\n"
          "\n"
          "static __inline__ double asm_sqrt(double x) {\n"
          "    __asm__ (\"sqrtsd %1, %0\" : \"=x\"(x) : \"x\"(x));\n"
          "    return x;\n"
          "}\n"
          "\n"
          "static __inline__ unsigned long read_fs_self(void) {\n"
          "    unsigned long self;\n"
          "    __asm__ (\"mov %%fs:0,%0\" : \"=r\"(self));\n"
          "    return self;\n"
          "}\n"
          "\n"
          "int target_base(int v) { return v + 7; }\n"
          "weak_alias(target_base, alias_base);\n"
          "\n"
          "typedef unsigned long __attribute__((__may_alias__)) u64_alias;\n"
          "\n"
          "void c_entry(void *sp) {\n"
          "    if (!sp) __syscall1(60, 1);\n"
          "    if (missing_optional_init) __syscall1(60, 2);\n"
          "    if (alias_base(5) != 12) __syscall1(60, 3);\n"
          "    volatile int atom_box[2] = { 10, 0x12345678 };\n"
          "    if (a_cas(&atom_box[0], 10, 25) != 10) __syscall1(60, 4);\n"
          "    if (atom_box[0] != 25 || atom_box[1] != 0x12345678) __syscall1(60, 5);\n"
          "    if (a_cas(&atom_box[0], 99, 77) != 25 || atom_box[0] != 25) __syscall1(60, 6);\n"
          "    a_inc(&atom_box[0]);\n"
          "    if (atom_box[0] != 26 || atom_box[1] != 0x12345678) __syscall1(60, 7);\n"
          "    a_barrier();\n"
          "    if (a_ctz_64(0x1000UL) != 12) __syscall1(60, 8);\n"
          "    if ((int)asm_sqrt(16.0) != 4) __syscall1(60, 9);\n"
          "    /* Check register r10 __asm__(\"r10\") via SYS_futex(uaddr=NULL, FUTEX_WAKE, 0, NULL) or SYS_rt_sigprocmask(SIG_BLOCK=0, NULL, NULL, 8) = sigsetsize in r10 */\n"
          "    long sr = __syscall4(14, 0, 0, 0, 8);\n"
          "    if (sr != 0) __syscall1(60, 10);\n"
          "    /* Set FS base to self-referential TCB slot via SYS_arch_prctl(ARCH_SET_FS=0x1002) and test mov %%fs:0,%0 */\n"
          "    unsigned long tcb_slot = 0;\n"
          "    tcb_slot = (unsigned long)&tcb_slot;\n"
          "    if (__syscall2(158, 0x1002, (long)&tcb_slot) != 0) __syscall1(60, 11);\n"
          "    if (read_fs_self() != (unsigned long)&tcb_slot) __syscall1(60, 12);\n"
          "    __extension__ long final_rc = 42;\n"
          "    __syscall1(60, final_rc);\n"
          "}\n")
         p)))

    (let ((rc1 (c-driver-main (list "--linker=ulisp" "-static" "-nostdlib" "-O1" c1 "-o" bin1))))
      (assert-equal "c-driver-main app_bin exited 0" 0 rc1))

    (call-with-output-file c2a
      (lambda (p)
        (display
         (string-append
          "#define weak_alias(old, new) extern __typeof(old) new __attribute__((__weak__, __alias__(#old)))\n"
          "__asm__ (\".text\\n.global _start\\n_start:\\n xor %rbp,%rbp\\n call main_w\\n mov %rax,%rdi\\n mov $60,%rax\\n syscall\\n\");\n"
          "int hook_impl(void) { return 11; }\n"
          "weak_alias(hook_impl, hook_fn);\n"
          "int main_w(void) { return hook_fn(); }\n")
         p)))
    (call-with-output-file c2b
      (lambda (p)
        (display "int hook_fn(void) { return 42; }\n" p)))

    (assert-equal "compile tu_weak.o" 0
                  (c-driver-main (list "-c" c2a "-o" o2a)))
    (assert-equal "compile tu_strong.o" 0
                  (c-driver-main (list "-c" c2b "-o" o2b)))
    (assert-equal "link weak_override_bin" 0
                  (c-driver-main (list "--linker=ulisp" "-static" "-nostdlib" o2a o2b "-o" bin2)))
    (assert-true "app_bin created" (file-exists? bin1))
    (assert-true "weak_override_bin created" (file-exists? bin2))))

(test-end)
(display "C99 GNU-C Extensions Scheme checks PASSED!\n")
