;;; =======================================================================
;;; ULisp C99 Checked LIR VM Interpreter & Differential Harness Tests
;;; Verifies C99/Lua execution parity, weak/alias linking, libc stubs,
;;; memory/sanitizer/fuel traps (CWE-476/125/787/400), and x86-64 vs VM diff.
;;; Conforms to Issue #943 & zero local `set!` (ULisp AOT safe).
;;; =======================================================================

(enable-verifier!)
(set-verifier-level! 3)
(set-verifier-strict! #t)

(test-begin "C99 Checked LIR Reference VM & Differential Harness (Issue #943)")

(define *vm-chk-dir* "build/test_c99_lir_vm_checked_tmp")
(if (not (file-exists? "build")) (sys-mkdir "build" 493))
(if (not (file-exists? *vm-chk-dir*)) (sys-mkdir *vm-chk-dir* 493))

(define (vm-chk-write-c name content)
  (let ((path (string-append *vm-chk-dir* "/" name)))
    (call-with-output-file path (lambda (p) (display content p)))
    path))

(define (vm-chk-compile-eval-str src . maybe-flags)
  (let* ((extra (if (and (pair? maybe-flags) (list? (car maybe-flags))) (car maybe-flags) '()))
         (san? (and (memq 'sanitize-bounds extra) #t))
         (lir (c99-compile-string-to-lir src "vm_chk_inline.c" (list (cons 'sanitize-bounds? san?)))))
    (c99-eval-lir-program-checked lir)))

;;; -----------------------------------------------------------------------
;;; Group 1: Weak Symbols, weak_alias & Multi-TU Resolution on LIR VM
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Weak Symbols, weak_alias & Multi-TU Resolution ---\n")

(let* ((src
        (string-append
         "#define weak __attribute__((__weak__))\n"
         "#define weak_alias(old, new) extern __typeof(old) new __attribute__((__weak__, __alias__(#old)))\n"
         "weak void opt_missing_hook(void);\n"
         "weak int opt_weak_var = 55;\n"
         "int target_add(int a, int b) { return a + b * 2; }\n"
         "weak_alias(target_add, alias_add);\n"
         "int (*fp_alias)(int, int) = alias_add;\n"
         "int main(void) {\n"
         "  if (opt_missing_hook) return 1;\n"
         "  if (opt_weak_var != 55) return 2;\n"
         "  if (alias_add(10, 5) != 20) return 3;\n"
         "  if (fp_alias(7, 3) != 13) return 4;\n"
         "  return 42;\n"
         "}\n"))
       (res (vm-chk-compile-eval-str src)))
  (assert-equal "1.1 single-TU weak/alias evaluates to ok" 'ok (car res))
  (assert-equal "1.2 single-TU weak/alias returns 42" 42 (cadr res)))

(let ((tu1 (vm-chk-write-c
            "g1_tu_weak.c"
            (string-append
             "#define weak __attribute__((__weak__))\n"
             "#define weak_alias(old, new) extern __typeof(old) new __attribute__((__weak__, __alias__(#old)))\n"
             "weak int weak_val(int x) { return x + 1; }\n"
             "int hook_impl(int x) { return x + 10; }\n"
             "weak_alias(hook_impl, hook_fn);\n"
             "int main(void) {\n"
             "  return weak_val(5) + hook_fn(7);\n"
             "}\n")))
      (tu2 (vm-chk-write-c
            "g1_tu_strong.c"
            (string-append
             "int weak_val(int x) { return x * 10; }\n"
             "int hook_fn(int x) { return x * 3 + 2; }\n"))))
  (assert-equal "1.3 multi-TU --target=vm strong overrides weak & alias (50 + 23 = 73)"
                73
                (c-driver-main (list "--target=vm" tu1 tu2))))

;;; -----------------------------------------------------------------------
;;; Group 2: Pure-Scheme C99 / Lua Standard Library Stubs on LIR VM
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: Pure-Scheme C99 / Lua Standard Library Stubs ---\n")

(let* ((src
        (string-append
         "#include <stdlib.h>\n"
         "#include <string.h>\n"
         "#include <stdio.h>\n"
         "#include <stdarg.h>\n"
         "extern int *__errno_location(void);\n"
         "static int my_vsn(char *buf, size_t sz, const char *fmt, ...) {\n"
         "  va_list ap;\n"
         "  va_start(ap, fmt);\n"
         "  int n = vsnprintf(buf, sz, fmt, ap);\n"
         "  va_end(ap);\n"
         "  return n;\n"
         "}\n"
         "static int cmp_int(const void *pa, const void *pb) {\n"
         "  int a = *(const int *)pa;\n"
         "  int b = *(const int *)pb;\n"
         "  return (a > b) - (a < b);\n"
         "}\n"
         "int main(void) {\n"
         "  /* realloc / calloc / malloc */\n"
         "  unsigned char *p = (unsigned char *)calloc(4, 1);\n"
         "  p[0] = 11; p[1] = 22; p[2] = 33; p[3] = 44;\n"
         "  p = (unsigned char *)realloc(p, 8);\n"
         "  if (p[0] != 11 || p[3] != 44) return 1;\n"
         "  free(p);\n"
         "  /* string searching & copy */\n"
         "  char buf[64];\n"
         "  strcpy(buf, \"alpha\");\n"
         "  strcat(buf, \"-beta\");\n"
         "  if (strcmp(buf, \"alpha-beta\") != 0) return 2;\n"
         "  if (strchr(buf, '-') - buf != 5) return 3;\n"
         "  if (strrchr(buf, 'a') - buf != 9) return 4;\n"
         "  if (strstr(buf, \"pha-b\") - buf != 2) return 5;\n"
         "  if ((unsigned char *)memchr(buf, 'b', 10) - (unsigned char *)buf != 6) return 6;\n"
         "  if (strspn(\"1234abc\", \"0123456789\") != 4) return 7;\n"
         "  if (strcspn(\"hello,world\", \",;\") != 5) return 8;\n"
         "  if (strpbrk(\"xyz12\", \"982\") - \"xyz12\" != 0 && *strpbrk(\"xyz12\", \"982\") != '2') return 9;\n"
         "  /* numeric conversions & abs/errno */\n"
         "  char *endp = 0;\n"
         "  long v1 = strtol(\"  -0x1aXYZ\", &endp, 0);\n"
         "  if (v1 != -26 || *endp != 'X') return 10;\n"
         "  unsigned long v2 = strtoul(\"077!\", &endp, 0);\n"
         "  if (v2 != 63 || *endp != '!') return 11;\n"
         "  if (atoi(\"  456\") != 456 || abs(-19) != 19 || labs(-1234567L) != 1234567L) return 12;\n"
         "  *__errno_location() = 22;\n"
         "  if (*__errno_location() != 22) return 13;\n"
         "  /* sprintf / snprintf / vsnprintf */\n"
         "  int full_len = snprintf(0, 0, \"id=%04d,hex=%x\", 7, 255);\n"
         "  if (full_len != 14) return 14;\n"
         "  char fbuf[32];\n"
         "  int n1 = my_vsn(fbuf, sizeof(fbuf), \"%s:%ld:%02X\", \"k\", -5L, 10);\n"
         "  if (n1 != 7 || strcmp(fbuf, \"k:-5:0A\") != 0) return 15;\n"
         "  /* qsort & bsearch callbacks */\n"
         "  int nums[5] = { 42, 7, 19, 1, 88 };\n"
         "  qsort(nums, 5, sizeof(int), cmp_int);\n"
         "  if (nums[0] != 1 || nums[1] != 7 || nums[4] != 88) return 16;\n"
         "  int key = 19;\n"
         "  int *hit = (int *)bsearch(&key, nums, 5, sizeof(int), cmp_int);\n"
         "  if (!hit || (hit - nums) != 2) return 17;\n"
         "  return 0;\n"
         "}\n"))
       (res (vm-chk-compile-eval-str src)))
  (assert-equal "2.1 C99 libc stdlib/string/printf/qsort suite passes on LIR VM" 'ok (car res))
  (assert-equal "2.2 C99 libc stdlib suite returns 0" 0 (cadr res)))

;;; -----------------------------------------------------------------------
;;; Group 3: Checked Memory, Sanitizer, Div-Zero & Fuel Traps (Exit 134)
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Checked Memory, Sanitizer, Div-Zero & Fuel Traps ---\n")

;; 3.1 CWE-476 NULL deref
(let* ((f-null (vm-chk-write-c "g3_null.c" "int main(void) { volatile int *p = 0; return *p; }\n"))
       (chk (vm-chk-compile-eval-str "int main(void) { volatile int *p = 0; return *p; }\n")))
  (assert-equal "3.1 CWE-476 NULL deref traps" 'trap (car chk))
  (assert-equal "3.2 NULL deref trap type is out-of-bounds" 'out-of-bounds (cadr chk))
  (assert-equal "3.3 CLI --target=vm NULL deref returns exit code 134"
                134
                (c-driver-cli-main (list "--target=vm" f-null))))

;; 3.2 CWE-476 NULL in libc stub strlen(NULL) / memcpy(NULL, ...)
(let* ((chk-strlen (vm-chk-compile-eval-str "#include <string.h>\nint main(void) { return (int)strlen((const char *)0); }\n"))
       (chk-memcpy (vm-chk-compile-eval-str "#include <string.h>\nint main(void) { int x = 1; memcpy((void *)0, &x, 4); return 0; }\n")))
  (assert-equal "3.4 strlen(NULL) traps" 'trap (car chk-strlen))
  (assert-equal "3.5 memcpy(NULL, ...) traps" 'trap (car chk-memcpy)))

;; 3.3 CWE-125/787 --sanitize-bounds trap & exit code 134
(let* ((san-c "int main(void) { int a[4] = {1,2,3,4}; int i = 5; return a[i]; }\n")
       (f-san (vm-chk-write-c "g3_san.c" san-c))
       (chk-san (vm-chk-compile-eval-str san-c '(sanitize-bounds))))
  (assert-equal "3.6 --sanitize-bounds OOB traps on VM" 'trap (car chk-san))
  (assert-equal "3.7 --sanitize-bounds trap type is sanitizer-trap" 'sanitizer-trap (cadr chk-san))
  (assert-equal "3.8 CLI --target=vm --sanitize-bounds returns exit code 134"
                134
                (c-driver-cli-main (list "--target=vm" "--sanitize-bounds" f-san))))

;; 3.4 Division by zero
(let* ((f-div (vm-chk-write-c "g3_div0.c" "int main(void) { int x = 100; volatile int z = 0; return x / z; }\n"))
       (chk-div (vm-chk-compile-eval-str "int main(void) { int x = 100; volatile int z = 0; return x / z; }\n")))
  (assert-equal "3.9 div-by-zero traps with division-by-zero" 'division-by-zero (cadr chk-div))
  (assert-equal "3.10 CLI --target=vm div-by-zero returns 134"
                134
                (c-driver-cli-main (list "--target=vm" f-div))))

;; 3.5 Unresolved weak NULL call & abort()
(let* ((chk-wcall (vm-chk-compile-eval-str "#define weak __attribute__((__weak__))\nweak int miss(void);\nint main(void) { return miss(); }\n"))
       (chk-abort (vm-chk-compile-eval-str "extern void abort(void);\nint main(void) { abort(); return 0; }\n")))
  (assert-equal "3.11 unresolved weak call traps invalid-call-target" 'invalid-call-target (cadr chk-wcall))
  (assert-equal "3.12 abort() traps with abort" 'abort (cadr chk-abort)))

;; 3.6 CWE-400 infinite loop bounded by --vm-fuel=5000
(let* ((f-loop (vm-chk-write-c "g3_infloop.c" "int main(void) { volatile int i = 0; while (1) { i = i + 1; } return i; }\n"))
       (lir-loop (c99-compile-string-to-lir "int main(void) { volatile int i = 0; while (1) { i = i + 1; } return i; }\n" "infloop.c"))
       (chk-fuel (c99-eval-lir-program-checked lir-loop 5000)))
  (assert-equal "3.13 bounded fuel traps infinite loop with out-of-fuel" 'out-of-fuel (cadr chk-fuel))
  (assert-equal "3.14 CLI --target=vm --vm-fuel=5000 returns 134"
                134
                (c-driver-cli-main (list "--target=vm" "--vm-fuel=5000" f-loop))))

;;; -----------------------------------------------------------------------
;;; Group 4: x86-64 Native vs LIR Reference VM Differential Diagnostic Harness
;;; -----------------------------------------------------------------------
(display "\n--- Group 4: Native x86-64 vs LIR VM Differential Harness ---\n")

;; 4.1 Integer promotion, shifts & unsigned arithmetic
(let ((f (vm-chk-write-c
          "diff_01_int.c"
          "int main(void) { unsigned int u = 0x80000005u; int s = -12; return (int)(((u >> 2) ^ (unsigned)(s * -3)) & 0xff); }\n")))
  (assert-equal "4.1 diff int/shift/unsigned parity"
                'ok
                (cadr (c99-diff-vm-vs-native f '("-O1")))))

;; 4.2 Struct/Union layout & Bitfields
(let ((f (vm-chk-write-c
          "diff_02_struct.c"
          (string-append
           "struct BF { unsigned a : 5; int b : 7; unsigned c : 4; };\n"
           "union U { unsigned int w; struct BF bf; };\n"
           "int main(void) { struct BF s = { 17, -13, 9 }; union U u; u.bf = s; return (s.a + (s.b & 0xff) + s.c + (u.w & 0x1f)) & 0xff; }\n"))))
  (assert-equal "4.2 diff struct/union/bitfield parity"
                'ok
                (cadr (c99-diff-vm-vs-native f '("-O1")))))

;; 4.3 Pointers, &arr[N] sentinel loop & array indexing
(let ((f (vm-chk-write-c
          "diff_03_ptr.c"
          (string-append
           "static int sum_range(const int *begin, const int *end) {\n"
           "  int acc = 0;\n"
           "  for (const int *p = begin; p < end; p++) acc += *p;\n"
           "  return acc;\n"
           "}\n"
           "int main(void) { int a[5] = { 3, 6, 9, 12, 15 }; return sum_range(&a[0], &a[5]); }\n"))))
  (let ((d (c99-diff-vm-vs-native f)))
    (assert-equal "4.3 diff pointer sentinel loop parity (45)" '(match ok 45 45) d)))

;; 4.4 Switch & Function Pointer Jump Tables
(let ((f (vm-chk-write-c
          "diff_04_switch_fnptr.c"
          (string-append
           "static int f0(int x) { return x + 1; }\n"
           "static int f1(int x) { return x * 3; }\n"
           "static int f2(int x) { return x ^ 7; }\n"
           "int main(void) {\n"
           "  int (*tbl[3])(int) = { f0, f1, f2 };\n"
           "  int acc = 0;\n"
           "  for (int i = 0; i < 6; i++) {\n"
           "    switch (i) {\n"
           "      case 0: acc += tbl[0](i); break;\n"
           "      case 1: case 2: acc += tbl[1](i); break;\n"
           "      case 4: acc += tbl[2](i); break;\n"
           "      default: acc += 5; break;\n"
           "    }\n"
           "  }\n"
           "  return acc & 0xff;\n"
           "}\n"))))
  (assert-equal "4.4 diff switch & fnptr table parity"
                'ok
                (cadr (c99-diff-vm-vs-native f '("-O2")))))

;; 4.5 Variadic stdarg + vsnprintf
(let ((f (vm-chk-write-c
          "diff_05_stdarg.c"
          (string-append
           "#include <stdarg.h>\n"
           "#include <stdio.h>\n"
           "static int sum_fmt(char *out, int count, const char *fmt, ...) {\n"
           "  va_list ap;\n"
           "  va_start(ap, fmt);\n"
           "  int w = vsnprintf(out, 32, fmt, ap);\n"
           "  va_end(ap);\n"
           "  va_start(ap, fmt);\n"
           "  int s = va_arg(ap, int) + va_arg(ap, int) + va_arg(ap, int);\n"
           "  va_end(ap);\n"
           "  return (w + s + count) & 0xff;\n"
           "}\n"
           "int main(void) { char b[32]; return sum_fmt(b, 3, \"%d-%d-%d\", 10, 20, 30); }\n"))))
  (assert-equal "4.5 diff stdarg + vsnprintf parity"
                'ok
                (cadr (c99-diff-vm-vs-native f))))

;; 4.6 setjmp / longjmp non-local jump
(let ((f (vm-chk-write-c
          "diff_06_setjmp.c"
          (string-append
           "#include <setjmp.h>\n"
           "static jmp_buf env;\n"
           "static void boom(int code) { longjmp(env, code); }\n"
           "int main(void) {\n"
           "  volatile int x = 10;\n"
           "  int r = setjmp(env);\n"
           "  if (r == 0) { x = 25; boom(7); return 99; }\n"
           "  return (x + r) & 0xff;\n"
           "}\n"))))
  (let ((d (c99-diff-vm-vs-native f '("-O1"))))
    (assert-equal "4.6 diff setjmp/longjmp parity (32)" '(match ok 32 32) d)))

;; 4.7 IEEE 754 float/double + libm
(let ((f (vm-chk-write-c
          "diff_07_float_libm.c"
          (string-append
           "#include <math.h>\n"
           "int main(void) {\n"
           "  double a = sqrt(144.0) + pow(2.0, 5.0);\n"
           "  float b = sqrtf(9.0f) + floorf(4.8f);\n"
           "  return ((int)a + (int)b) & 0xff;\n"
           "}\n"))))
  (let ((d (c99-diff-vm-vs-native f '("-lm"))))
    (assert-equal "4.7 diff float/double + libm parity (51)" '(match ok 51 51) d)))

;; 4.8 qsort callback
(let ((f (vm-chk-write-c
          "diff_08_qsort.c"
          (string-append
           "#include <stdlib.h>\n"
           "static int cmp_desc(const void *pa, const void *pb) {\n"
           "  int a = *(const int *)pa;\n"
           "  int b = *(const int *)pb;\n"
           "  return (b > a) - (b < a);\n"
           "}\n"
           "int main(void) {\n"
           "  int a[6] = { 5, 2, 9, 1, 7, 3 };\n"
           "  qsort(a, 6, sizeof(int), cmp_desc);\n"
           "  return (a[0] * 10 + a[5]) & 0xff;\n"
           "}\n"))))
  (let ((d (c99-diff-vm-vs-native f)))
    (assert-equal "4.8 diff qsort callback parity (91)" '(match ok 91 91) d)))

;; 4.9 Multi-TU Lua idioms
(let ((f1 (vm-chk-write-c
           "diff_09_tu1.c"
           (string-append
            "#include <string.h>\n"
            "static int h(int x) { return x * 4 + 1; }\n"
            "int call_tu1(int x) { const char *s = \"\\x1bLua\"; return h(x) + (unsigned char)s[0]; }\n")))
      (f2 (vm-chk-write-c
           "diff_09_tu2.c"
           (string-append
            "extern int call_tu1(int x);\n"
            "static int h(int x) { return x + 2; }\n"
            "int main(void) { return (call_tu1(5) + h(6)) & 0xff; }\n"))))
  (let ((d (c99-diff-vm-vs-native (list f1 f2) '("-O1"))))
    (assert-equal "4.9 diff multi-TU Lua idioms parity (56)" '(match ok 56 56) d)))

;; 4.10 Sanitizer trap parity (VM trap vs Native 134)
(let ((f (vm-chk-write-c
          "diff_10_san_trap.c"
          "int main(void) { int a[3] = {10, 20, 30}; volatile int idx = 4; return a[idx]; }\n")))
  (let ((d (c99-diff-vm-vs-native f '("--sanitize-bounds"))))
    (assert-equal "4.10 diff --sanitize-bounds trap parity"
                  '(match trap sanitizer-trap 134)
                  d)))

;;; -----------------------------------------------------------------------
;;; Group 5: Object-Level Shadow Memory Heap Checks (Issue #962)
;;; CWE-122 (Heap OOB), CWE-415 (Double Free), CWE-416 (UAF), CWE-590 (Invalid Free)
;;; -----------------------------------------------------------------------
(display "\n--- Group 5: Shadow Memory Heap Checks (CWE-122/415/416/590) ---\n")

;; 5.1 CWE-122 Heap OOB 1-byte alignment tail overrun on malloc(5)
(let* ((chk-r (vm-chk-compile-eval-str
               "#include <stdlib.h>\nint main(void) { char *p = (char *)malloc(5); p[4] = 'a'; return (unsigned char)p[5]; }\n"))
       (chk-w (vm-chk-compile-eval-str
               "#include <stdlib.h>\nint main(void) { char *p = (char *)malloc(5); p[5] = 'x'; return 0; }\n")))
  (assert-equal "5.1a CWE-122 heap 1-byte tail read OOB traps" '(trap heap-out-of-bounds) (list (car chk-r) (cadr chk-r)))
  (assert-equal "5.1b CWE-122 heap 1-byte tail write OOB traps" '(trap heap-out-of-bounds) (list (car chk-w) (cadr chk-w))))

;; 5.2 CWE-122 Heap underflow into leading redzone (p[-1])
(let ((chk (vm-chk-compile-eval-str
            "#include <stdlib.h>\nint main(void) { int *p = (int *)malloc(16); p[-1] = 42; return p[0]; }\n")))
  (assert-equal "5.2 CWE-122 heap underflow into pre-redzone traps" '(trap heap-out-of-bounds) (list (car chk) (cadr chk))))

;; 5.3 CWE-122 Heap overflow via memcpy / strcpy into malloc(4)
(let ((chk-mc (vm-chk-compile-eval-str
               "#include <stdlib.h>\n#include <string.h>\nint main(void) { char src[8] = \"abcdefg\"; char *dst = (char *)malloc(4); memcpy(dst, src, 5); return 0; }\n"))
      (chk-sc (vm-chk-compile-eval-str
               "#include <stdlib.h>\n#include <string.h>\nint main(void) { char *dst = (char *)malloc(4); strcpy(dst, \"hello\"); return 0; }\n")))
  (assert-equal "5.3a CWE-122 memcpy heap overflow traps" '(trap heap-out-of-bounds) (list (car chk-mc) (cadr chk-mc)))
  (assert-equal "5.3b CWE-122 strcpy heap overflow traps" '(trap heap-out-of-bounds) (list (car chk-sc) (cadr chk-sc))))

;; 5.4 CWE-122 Dereferencing 0-byte allocation malloc(0)
(let ((chk (vm-chk-compile-eval-str
            "#include <stdlib.h>\nint main(void) { volatile char *p = (char *)malloc(0); return *p; }\n")))
  (assert-equal "5.4 CWE-122 dereferencing malloc(0) traps heap-out-of-bounds" '(trap heap-out-of-bounds) (list (car chk) (cadr chk))))

;; 5.5 CWE-416 Use-After-Free after free(p)
(let* ((f-uaf (vm-chk-write-c "g5_uaf.c" "#include <stdlib.h>\nint main(void) { int *p = (int *)malloc(8); *p = 7; free(p); return *p; }\n"))
       (chk-r (vm-chk-compile-eval-str "#include <stdlib.h>\nint main(void) { int *p = (int *)malloc(8); *p = 7; free(p); return *p; }\n"))
       (chk-w (vm-chk-compile-eval-str "#include <stdlib.h>\nint main(void) { int *p = (int *)malloc(8); free(p); *p = 9; return 0; }\n")))
  (assert-equal "5.5a CWE-416 use-after-free read traps" '(trap use-after-free) (list (car chk-r) (cadr chk-r)))
  (assert-equal "5.5b CWE-416 use-after-free write traps" '(trap use-after-free) (list (car chk-w) (cadr chk-w)))
  (assert-equal "5.5c CLI --target=vm use-after-free exits 134" 134 (c-driver-cli-main (list "--target=vm" f-uaf))))

;; 5.6 CWE-416 Use-After-Free of old pointer after realloc(p, 32)
(let ((chk (vm-chk-compile-eval-str
            "#include <stdlib.h>\nint main(void) { char *p = (char *)malloc(8); p[0] = 11; char *q = (char *)realloc(p, 32); (void)q; return p[0]; }\n")))
  (assert-equal "5.6 CWE-416 realloc old pointer UAF traps" '(trap use-after-free) (list (car chk) (cadr chk))))

;; 5.7 CWE-415 Double Free
(let ((chk (vm-chk-compile-eval-str
            "#include <stdlib.h>\nint main(void) { void *p = malloc(16); free(p); free(p); return 0; }\n")))
  (assert-equal "5.7 CWE-415 double free traps" '(trap double-free) (list (car chk) (cadr chk))))

;; 5.8 CWE-590 Invalid Free (stack pointer & mid-chunk interior pointer)
(let ((chk-stack (vm-chk-compile-eval-str
                  "#include <stdlib.h>\nint main(void) { int x = 1; free(&x); return 0; }\n"))
      (chk-mid   (vm-chk-compile-eval-str
                  "#include <stdlib.h>\nint main(void) { char *p = (char *)malloc(16); free(p + 4); return 0; }\n")))
  (assert-equal "5.8a CWE-590 free of stack pointer traps invalid-free" '(trap invalid-free) (list (car chk-stack) (cadr chk-stack)))
  (assert-equal "5.8b CWE-590 free of interior pointer traps invalid-free" '(trap invalid-free) (list (car chk-mid) (cadr chk-mid))))

;; 5.9 Valid heap lifecycle (exact boundaries, calloc, realloc preserve, free(NULL), free(malloc(0)))
(let ((chk (vm-chk-compile-eval-str
            (string-append
             "#include <stdlib.h>\n"
             "int main(void) {\n"
             "  free((void *)0);\n"
             "  void *z = malloc(0); free(z);\n"
             "  unsigned char *c = (unsigned char *)calloc(3, 5);\n"
             "  int sum = c[0] + c[14];\n"
             "  for (int i = 0; i < 5; i++) c[i] = (unsigned char)(i + 1);\n"
             "  unsigned char *r = (unsigned char *)realloc(c, 24);\n"
             "  r[23] = 10;\n"
             "  int ans = sum + r[0] + r[4] + r[23];\n"
             "  free(r);\n"
             "  void *r2 = realloc((void *)0, 8);\n"
             "  void *r3 = realloc(r2, 0);\n"
             "  return ans + (r3 == (void *)0 ? 0 : 100);\n"
             "}\n"))))
  (assert-equal "5.9 valid heap lifecycle (exact bounds/calloc/realloc/free) returns 16" '(ok 16) (list (car chk) (cadr chk))))

(test-end)
