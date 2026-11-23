;;; =======================================================================
;;; test_sse2_xmm_abi.scm
;;; Issue #924: Pass 144a SSE2 Instruction Encodings vs GNU as,
;;; SysV AMD64 XMM ABI, <math.h> / libm Reference VM Built-ins.
;;; Zero local `set!` (ULisp AOT safe).
;;; =======================================================================

(define *xmm-pass* (cons 0 '()))
(define *xmm-fail* (cons 0 '()))

(define (xmm-assert-true desc ok)
  (if ok
      (begin
        (set-car! *xmm-pass* (+ (car *xmm-pass*) 1))
        (display "  [PASS] ") (display desc) (newline))
      (begin
        (set-car! *xmm-fail* (+ (car *xmm-fail*) 1))
        (display "  [FAIL] ") (display desc) (newline)
        (error "Assertion failed" desc))))

(define (xmm-assert-equal desc expected actual)
  (if (equal? expected actual)
      (begin
        (set-car! *xmm-pass* (+ (car *xmm-pass*) 1))
        (display "  [PASS] ") (display desc) (newline))
      (begin
        (set-car! *xmm-fail* (+ (car *xmm-fail*) 1))
        (display "  [FAIL] ") (display desc)
        (display "\n    expected: ") (write expected)
        (display "\n    actual:   ") (write actual) (newline)
        (error "Assertion failed" desc))))

(define (xmm-assert-approx desc expected actual tol)
  (let ((diff (if (> expected actual) (- expected actual) (- actual expected))))
    (if (<= diff tol)
        (begin
          (set-car! *xmm-pass* (+ (car *xmm-pass*) 1))
          (display "  [PASS] ") (display desc) (newline))
        (begin
          (set-car! *xmm-fail* (+ (car *xmm-fail*) 1))
          (display "  [FAIL] ") (display desc)
          (display " expected~=") (write expected)
          (display " actual=") (write actual) (newline)
          (error "Approximate assertion failed" desc)))))

(define (xmm-run-c-vm src)
  (let ((lir (c99-compile-string-to-lir src "<test-xmm-abi>")))
    (if (not (validate-lir lir 'core))
        (error "validate-lir core failed" src))
    (if (not (verify-lir lir))
        (error "verify-lir failed" src))
    (eval-lir-program lir)))

(define (xmm-run-c-vm-f64 src)
  (vm-ieee754-u64->f64 (xmm-run-c-vm src)))

(define (bv->hex-str bv)
  (let* ((hex "0123456789abcdef")
         (n (bytevector-length bv)))
    (let loop ((i 0) (acc '()))
      (if (= i n)
          (apply string-append (reverse acc))
          (let* ((b (bytevector-u8-ref bv i))
                 (hi (quotient b 16))
                 (lo (modulo b 16)))
            (loop (+ i 1)
                  (cons (string (string-ref hex hi) (string-ref hex lo)) acc)))))))

(define (inst-bytes raw-mnem op-strs)
  (car (assemble-inst raw-mnem (map parse-operand-str op-strs) 0)))

(define (inst-reloc raw-mnem op-strs curr-off)
  (cadr (assemble-inst raw-mnem (map parse-operand-str op-strs) curr-off)))

(display "=======================================================================\n")
(display " Starting SSE2 XMM Encoder, SysV ABI & libm VM Suite (#924)\n")
(display "=======================================================================\n")

;;; -----------------------------------------------------------------------
;;; Group 1: Pass 144a SSE2 Machine Code Encodings & RIP Relocations
;;; -----------------------------------------------------------------------
(display "\n--- Group 1: Pass 144a SSE2 Encodings & RIP Relocations ---\n")

(xmm-assert-equal "addss xmm0, xmm1"   '(#xF3 #x0F #x58 #xC1) (inst-bytes "addss" '("xmm0" "xmm1")))
(xmm-assert-equal "subss xmm9, xmm2"   '(#xF3 #x44 #x0F #x5C #xCA) (inst-bytes "subss" '("xmm9" "xmm2")))
(xmm-assert-equal "mulss xmm1, xmm10"  '(#xF3 #x41 #x0F #x59 #xCA) (inst-bytes "mulss" '("xmm1" "xmm10")))
(xmm-assert-equal "divss xmm8, xmm15"  '(#xF3 #x45 #x0F #x5E #xC7) (inst-bytes "divss" '("xmm8" "xmm15")))
(xmm-assert-equal "sqrtss xmm2, xmm3"  '(#xF3 #x0F #x51 #xD3) (inst-bytes "sqrtss" '("xmm2" "xmm3")))
(xmm-assert-equal "sqrtsd xmm8, xmm1"  '(#xF2 #x44 #x0F #x51 #xC1) (inst-bytes "sqrtsd" '("xmm8" "xmm1")))
(xmm-assert-equal "ucomiss xmm0, xmm1" '(#x0F #x2E #xC1) (inst-bytes "ucomiss" '("xmm0" "xmm1")))
(xmm-assert-equal "ucomiss xmm11, xmm7" '(#x44 #x0F #x2E #xDF) (inst-bytes "ucomiss" '("xmm11" "xmm7")))
(xmm-assert-equal "pxor xmm0, xmm0"    '(#x66 #x0F #xEF #xC0) (inst-bytes "pxor" '("xmm0" "xmm0")))
(xmm-assert-equal "xorpd xmm8, xmm9"   '(#x66 #x45 #x0F #x57 #xC1) (inst-bytes "xorpd" '("xmm8" "xmm9")))
(xmm-assert-equal "xorps xmm1, xmm2"   '(#x0F #x57 #xCA) (inst-bytes "xorps" '("xmm1" "xmm2")))
(xmm-assert-equal "andpd xmm3, xmm4"   '(#x66 #x0F #x54 #xDC) (inst-bytes "andpd" '("xmm3" "xmm4")))
(xmm-assert-equal "andps xmm5, xmm6"   '(#x0F #x54 #xEE) (inst-bytes "andps" '("xmm5" "xmm6")))
(xmm-assert-equal "orpd xmm7, xmm0"    '(#x66 #x0F #x56 #xF8) (inst-bytes "orpd" '("xmm7" "xmm0")))
(xmm-assert-equal "orps xmm10, xmm11"  '(#x45 #x0F #x56 #xD3) (inst-bytes "orps" '("xmm10" "xmm11")))
(xmm-assert-equal "movaps xmm8, xmmword ptr [rsp+16]"
                  '(#x44 #x0F #x28 #x44 #x24 #x10)
                  (inst-bytes "movaps" '("xmm8" "xmmword ptr [rsp + 16]")))
(xmm-assert-equal "movaps [rsp+16], xmm8"
                  '(#x44 #x0F #x29 #x44 #x24 #x10)
                  (inst-bytes "movaps" '("[rsp + 16]" "xmm8")))
(xmm-assert-equal "movapd [r12+32], xmm0"
                  '(#x66 #x41 #x0F #x29 #x44 #x24 #x20)
                  (inst-bytes "movapd" '("[r12 + 32]" "xmm0")))
(xmm-assert-equal "movupd xmm0, [rbp-16]"
                  '(#x66 #x0F #x10 #x45 #xF0)
                  (inst-bytes "movupd" '("xmm0" "[rbp - 16]")))
(xmm-assert-equal "movups [r13+0], xmm1"
                  '(#x41 #x0F #x11 #x4D #x00)
                  (inst-bytes "movups" '("[r13 + 0]" "xmm1")))
(xmm-assert-equal "movq xmm0, xmm1"    '(#xF3 #x0F #x7E #xC1) (inst-bytes "movq" '("xmm0" "xmm1")))
(xmm-assert-equal "movq xmm8, r12"     '(#x66 #x4D #x0F #x6E #xC4) (inst-bytes "movq" '("xmm8" "r12")))
(xmm-assert-equal "movd xmm0, eax"     '(#x66 #x0F #x6E #xC0) (inst-bytes "movd" '("xmm0" "eax")))
(xmm-assert-equal "movd r8d, xmm9"     '(#x66 #x45 #x0F #x7E #xC8) (inst-bytes "movd" '("r8d" "xmm9")))
(xmm-assert-equal "cvtsi2ss xmm0, eax" '(#xF3 #x0F #x2A #xC0) (inst-bytes "cvtsi2ss" '("xmm0" "eax")))
(xmm-assert-equal "cvtsi2ss xmm0, rax" '(#xF3 #x48 #x0F #x2A #xC0) (inst-bytes "cvtsi2ss" '("xmm0" "rax")))
(xmm-assert-equal "cvttss2si eax, xmm1" '(#xF3 #x0F #x2C #xC1) (inst-bytes "cvttss2si" '("eax" "xmm1")))
(xmm-assert-equal "cvttss2si r10, xmm9" '(#xF3 #x4D #x0F #x2C #xD1) (inst-bytes "cvttss2si" '("r10" "xmm9")))

;; RIP-relative relocation emission checks (fixing Issue #924 bugs)
(xmm-assert-equal "movq xmm0, [rip + .L_c] reloc"
                  '(rip_disp32 14 ".L_c" 0 0)
                  (inst-reloc "movq" '("xmm0" "[rip + .L_c]") 10))
(xmm-assert-equal "movq [rip + .L_c], xmm8 reloc"
                  '(rip_disp32 25 ".L_c" 8 0)
                  (inst-reloc "movq" '("[rip + .L_c + 8]" "xmm8") 20))
(xmm-assert-equal "movd xmm8, [rip + .L_c] reloc"
                  '(rip_disp32 5 ".L_c" 0 0)
                  (inst-reloc "movd" '("xmm8" "[rip + .L_c]") 0))
(xmm-assert-equal "cvtsi2sd xmm0, qword ptr [rip + .L_c] reloc"
                  '(rip_disp32 5 ".L_c" 0 0)
                  (inst-reloc "cvtsi2sd" '("xmm0" "qword ptr [rip + .L_c]") 0))
(xmm-assert-equal "cvttsd2si rax, qword ptr [rip + .L_c] reloc"
                  '(rip_disp32 5 ".L_c" 0 0)
                  (inst-reloc "cvttsd2si" '("rax" "qword ptr [rip + .L_c]") 0))
(xmm-assert-equal "cvtsi2ss xmm0, dword ptr [rip + .L_c] reloc"
                  '(rip_disp32 4 ".L_c" 0 0)
                  (inst-reloc "cvtsi2ss" '("xmm0" "dword ptr [rip + .L_c]") 0))

;; Write shared GNU as comparison fixture for test_sse2_xmm_abi.sh
(let* ((sse2-test-lines
        '(".intel_syntax noprefix"
          ".section .rodata"
          ".align 16"
          ".L_ro_c:"
          "    .quad 4607182418800017408"
          "    .quad 4611686018427387904"
          ".text"
          ".globl _start"
          "_start:"
          "    movsd xmm0, qword ptr [rip + .L_ro_c]"
          "    movss xmm1, dword ptr [rip + .L_ro_c]"
          "    movq xmm2, qword ptr [rip + .L_ro_c]"
          "    movq qword ptr [rip + .L_ro_c], xmm8"
          "    movd xmm9, dword ptr [rip + .L_ro_c]"
          "    movd dword ptr [rip + .L_ro_c], xmm0"
          "    movaps xmm8, xmmword ptr [rsp + 16]"
          "    movaps xmmword ptr [rsp + 32], xmm9"
          "    movapd xmm0, xmmword ptr [rbp - 16]"
          "    movapd xmmword ptr [r12 + 32], xmm10"
          "    movupd xmm1, xmmword ptr [r13 + 0]"
          "    movups xmmword ptr [r14 + 8], xmm11"
          "    addsd xmm0, xmm1"
          "    addss xmm2, xmm8"
          "    subsd xmm3, xmm9"
          "    subss xmm4, dword ptr [rsp + 8]"
          "    mulsd xmm5, xmm6"
          "    mulss xmm7, xmm15"
          "    divsd xmm8, xmm0"
          "    divss xmm9, xmm1"
          "    sqrtsd xmm10, xmm2"
          "    sqrtss xmm11, xmm3"
          "    ucomisd xmm0, xmm1"
          "    ucomiss xmm12, xmm4"
          "    cvtss2sd xmm0, xmm13"
          "    cvtsd2ss xmm14, xmm0"
          "    cvtsi2sd xmm0, rax"
          "    cvtsi2sd xmm8, qword ptr [rip + .L_ro_c]"
          "    cvttsd2si rbx, xmm0"
          "    cvttsd2si r12, qword ptr [rip + .L_ro_c]"
          "    cvtsi2ss xmm1, ecx"
          "    cvtsi2ss xmm9, r15"
          "    cvttss2si edx, xmm1"
          "    cvttss2si r13, xmm10"
          "    movq xmm0, xmm8"
          "    movq rcx, xmm9"
          "    movq xmm10, rdx"
          "    movd xmm11, edi"
          "    movd esi, xmm12"
          "    pxor xmm0, xmm0"
          "    xorpd xmm8, xmm9"
          "    xorps xmm1, xmm2"
          "    andpd xmm3, xmm4"
          "    andps xmm10, xmm11"
          "    orpd xmm5, xmm6"
          "    orps xmm12, xmm13"
          "    ret"))
       (asm-res (assemble-x86-lines sse2-test-lines))
       (text-bv (car asm-res))
       (ro-bv (cadr asm-res)))
  (with-output-to-file "build/sse2_as_oracle.s"
    (lambda ()
      (for-each (lambda (ln) (display ln) (newline)) sse2-test-lines)))
  (with-output-to-file "build/sse2_144a_text.hex"
    (lambda () (display (bv->hex-str text-bv)) (newline)))
  (with-output-to-file "build/sse2_144a_rodata.hex"
    (lambda () (display (bv->hex-str ro-bv)) (newline)))
  (xmm-assert-true "144a assembled non-empty text bytevector for GNU as diff" (> (bytevector-length text-bv) 150)))

;;; -----------------------------------------------------------------------
;;; Group 2: SysV AMD64 XMM ABI Layout, Aggregates, Stack Spill & va_arg
;;; -----------------------------------------------------------------------
(display "\n--- Group 2: SysV XMM ABI Layout, Lowering & Reference VM ---\n")

(let* ((src "
typedef unsigned long long u64_t;
struct F2 { float a; float b; };
struct F3 { float a; float b; float c; };
struct D2 { double a; double b; };
struct DI { double d; int i; };
struct ID { int i; double d; };
struct FI { float a; int b; };
struct Big { double x; double y; double z; };
union DU { double d; u64_t u; };

u64_t take12x(double a0, float a1, double a2, double a3, double a4, double a5,
              float a6, double a7, double s0, float s1, double s2, float s3) {
    double sum = a0 + (double)a1 + a2 + a3 + a4 + a5 + (double)a6 + a7 +
                 s0 + (double)s1 + s2 + (double)s3;
    return (u64_t)sum;
}

u64_t take_mixed(int g0, double x0, int g1, float x1, int g2, double x2, int g3, double x3,
                 int g4, double x4, int g5, double x5, int g6, double x6, int g7, float x7,
                 double x8, int g8, float x9) {
    double r = (double)(g0 + g1 + g2 + g3 + g4 + g5 + g6 + g7 + g8) +
               x0 + (double)x1 + x2 + x3 + x4 + x5 + x6 + (double)x7 + x8 + (double)x9;
    return (u64_t)r;
}

struct F2 make_f2(float a, float b) { struct F2 s = { a, b }; return s; }
double use_f2(struct F2 s) { return (double)s.a + (double)s.b; }
double use_f3(struct F3 s) { return (double)s.a + (double)s.b + (double)s.c; }
double use_d2(struct D2 s) { return s.a + s.b; }
double use_di(struct DI s) { return s.d + (double)s.i; }
double use_id(struct ID s) { return (double)s.i + s.d; }
double use_fi(struct FI s) { return (double)s.a + (double)s.b; }
struct Big make_big(double x, double y, double z) { struct Big b = { x, y, z }; return b; }
double sum_big(struct Big b, double scale) { return (b.x + b.y + b.z) * scale; }
")
       (ast (parse-c99-preprocessed-string src "<abi-check>"))
       (typed (c99-analyze-program ast))
       (funcs (caddr typed))
       (lenv (list-ref typed 3))
       (param-ty-of (lambda (fn-sym)
                      (let loop ((fs funcs))
                        (if (null? fs)
                            (error "Fn not found" fn-sym)
                            (if (eq? (list-ref (car fs) 1) fn-sym)
                                (caddr (car (list-ref (car fs) 4)))
                                (loop (cdr fs)))))))
       (s-f2 (param-ty-of 'use_f2))
       (s-f3 (param-ty-of 'use_f3))
       (s-d2 (param-ty-of 'use_d2))
       (s-di (param-ty-of 'use_di))
       (s-id (param-ty-of 'use_id))
       (s-fi (param-ty-of 'use_fi))
       (s-big (param-ty-of 'sum_big)))
  (xmm-assert-equal "SysV classify {float, float}" '(SSE) (c99-sysv-type-abi-class lenv s-f2))
  (xmm-assert-equal "SysV classify {float, float, float}" '(SSE SSE) (c99-sysv-type-abi-class lenv s-f3))
  (xmm-assert-equal "SysV classify {double, double}" '(SSE SSE) (c99-sysv-type-abi-class lenv s-d2))
  (xmm-assert-equal "SysV classify {double, int}" '(SSE INTEGER) (c99-sysv-type-abi-class lenv s-di))
  (xmm-assert-equal "SysV classify {int, double}" '(INTEGER SSE) (c99-sysv-type-abi-class lenv s-id))
  (xmm-assert-equal "SysV classify {float, int} -> INTEGER merge" '(INTEGER) (c99-sysv-type-abi-class lenv s-fi))
  (xmm-assert-equal "SysV classify 24B Big -> MEMORY" 'MEMORY (c99-sysv-type-abi-class lenv s-big)))

(xmm-assert-equal "VM 12 XMM args (8 reg + 4 stack float/double)"
                  78
                  (xmm-run-c-vm "
int test_main(double a0, float a1, double a2, double a3, double a4, double a5,
              float a6, double a7, double s0, float s1, double s2, float s3) {
    return (int)(a0 + (double)a1 + a2 + a3 + a4 + a5 + (double)a6 + a7 +
                 s0 + (double)s1 + s2 + (double)s3);
}
int main(void) {
    return test_main(1.0, 2.0f, 3.0, 4.0, 5.0, 6.0, 7.0f, 8.0, 9.0, 10.0f, 11.0, 12.0f);
}"))

(xmm-assert-equal "VM mixed 8 GPR + 10 XMM + structs + sret"
                  137
                  (xmm-run-c-vm "
struct F2 { float a; float b; };
struct F3 { float a; float b; float c; };
struct DI { double d; int i; };
struct ID { int i; double d; };
struct FI { float a; int b; };
struct Big { double x; double y; double z; };

struct F2 make_f2(float a, float b) { struct F2 s = { a, b }; return s; }
struct F3 make_f3(float a, float b, float c) { struct F3 s = { a, b, c }; return s; }
struct Big make_big(double x, double y, double z) { struct Big b = { x, y, z }; return b; }

int sum_structs(struct F2 f2, struct F3 f3, struct DI di, struct ID id, struct FI fi, struct Big big) {
    double total = (double)f2.a + (double)f2.b + (double)f3.a + (double)f3.b + (double)f3.c +
                   di.d + (double)di.i + (double)id.i + id.d + (double)fi.a + (double)fi.b +
                   big.x + big.y + big.z;
    return (int)total;
}

int mix_call(int g0, double x0, int g1, float x1, int g2, double x2, int g3, double x3,
             int g4, double x4, int g5, double x5, int g6, double x6, int g7, float x7,
             double x8, int g8, float x9) {
    return g0 + g1 + g2 + g3 + g4 + g5 + g6 + g7 + g8 +
           (int)(x0 + (double)x1 + x2 + x3 + x4 + x5 + x6 + (double)x7 + x8 + (double)x9);
}

int main(void) {
    struct F2 f2 = make_f2(1.0f, 2.0f);
    struct F3 f3 = make_f3(3.0f, 4.0f, 5.0f);
    struct DI di = { 6.0, 7 };
    struct ID id = { 8, 9.0 };
    struct FI fi = { 10.0f, 11 };
    struct Big big = make_big(12.0, 13.0, 14.0);
    int r1 = sum_structs(f2, f3, di, id, fi, big); /* 1+..+14 = 105 */
    int r2 = mix_call(1, 0.5, 1, 0.5f, 1, 1.0, 1, 1.0, 1, 2.0, 1, 2.0, 1, 3.0, 1, 3.0f, 4.0, 1, 6.0f); /* 9+23 = 32 */
    return r1 + r2; /* 137 */
}"))

(xmm-assert-equal "VM packed {float, float} preserves raw sNaN/-0.0f bits across %fmov"
                  1
                  (xmm-run-c-vm "
typedef unsigned int u32_t;
void *memcpy(void *d, const void *s, unsigned long n);
struct F2 { float a; float b; };
struct F2 id_f2(struct F2 v) { return v; }
int main(void) {
    struct F2 in;
    u32_t ba = 0x80000000U;
    u32_t bb = 0x7f800001U; /* sNaN bit pattern preserved verbatim through GPR/XMM reg move */
    memcpy(&in.a, &ba, 4);
    memcpy(&in.b, &bb, 4);
    struct F2 out = id_f2(in);
    u32_t oa = 0, ob = 0;
    memcpy(&oa, &out.a, 4);
    memcpy(&ob, &out.b, 4);
    return (oa == ba && ob == bb) ? 1 : 0;
}"))

(xmm-assert-equal "VM variadic va_arg crossing 8 XMM RSA boundary into overflow_arg_area"
                  66
                  (xmm-run-c-vm "
#include <stdarg.h>
static double sum_va_dbl(int n, ...) {
    va_list ap;
    va_start(ap, n);
    double acc = 0.0;
    for (int i = 0; i < n; i++) {
        acc += va_arg(ap, double);
    }
    va_end(ap);
    return acc;
}
int main(void) {
    double (*fp)(int, ...) = sum_va_dbl;
    double r = fp(11, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0);
    return (int)r;
}"))

;;; -----------------------------------------------------------------------
;;; Group 3: Built-in <math.h> & libm Reference VM Built-ins
;;; -----------------------------------------------------------------------
(display "\n--- Group 3: Built-in <math.h> & Reference VM libm Suite ---\n")

(xmm-assert-approx "VM libm double suite (sin/cos/tan/sqrt/pow/atan2/exp/log/hypot/copysign)"
                   19.414213562373095
                   (xmm-run-c-vm-f64 "
#include <math.h>
typedef unsigned long long u64_t;
void *memcpy(void *d, const void *s, unsigned long n);
u64_t main(void) {
    double (*fp_sin)(double) = sin;
    double (*fp_atan2)(double, double) = atan2;
    double a = fp_sin(0.0) + cos(0.0) + sqrt(9.0) + pow(2.0, 3.0); /* 12.0 */
    int ex = 0;
    double fr = frexp(6.0, &ex); /* 0.75, ex=3 */
    double ip = 0.0;
    double mf = modf(-3.25, &ip); /* -0.25, ip=-3.0 */
    double misc = atan(0.0) + fp_atan2(0.0, 1.0) + sinh(0.0) + (cosh(0.0) - 1.0) + tanh(0.0) +
                  log(1.0) + (exp(0.0) - 1.0) + log10(1.0) + log2(1.0); /* 0.0 */
    double res = a + hypot(3.0, 4.0) - floor(4.9) + ceil(0.1) + trunc(-2.9) + round(2.5) +
                 fmod(5.5, 2.0) + copysign(2.0, -3.0) + ldexp(0.75, 2) +
                 fr + (double)ex + mf + ip + sqrt(2.0) + misc;
    /* 12 + 5 - 4 + 1 - 2 + 3 + 1.5 - 2 + 3 + 0.75 + 3 - 0.25 - 3 + sqrt(2) = 18.0 + sqrt(2) */
    u64_t bits = 0;
    memcpy(&bits, &res, 8);
    return bits;
}
")
                   1e-12)

(xmm-assert-equal "VM libm edge cases (sqrt(-0.0)==-0.0, sqrt(-1)==NaN, log(0)==-Inf, pow(0,-1)==+Inf, fabs(-0)==+0, fmod(-5,2)==-1, round(-2.5)==-3)"
                  1
                  (xmm-run-c-vm "
#include <math.h>
typedef unsigned long long u64_t;
typedef unsigned int u32_t;
void *memcpy(void *d, const void *s, unsigned long n);
static u64_t d2u(double d) { u64_t u = 0; memcpy(&u, &d, 8); return u; }
static u32_t f2u(float f) { u32_t u = 0; memcpy(&u, &f, 4); return u; }
int main(void) {
    double s_nz = sqrt(-0.0);
    double s_nan = sqrt(-1.0);
    double l_z = log(0.0);
    double p_inf = pow(0.0, -1.0);
    double fa = fabs(-0.0);
    double fm = fmod(-5.5, 2.0);
    double rd = round(-2.5);
    double r49 = round(0.49999999999999994);
    float ff = fabsf(-3.5f);
    float sf = sqrtf(9.0f);
    float cf = copysignf(2.0f, -0.0f);
    int ok = (d2u(s_nz) == 0x8000000000000000ULL) &&
             (s_nan != s_nan) &&
             (d2u(l_z) == 0xfff0000000000000ULL) &&
             (d2u(p_inf) == 0x7ff0000000000000ULL) &&
             (d2u(fa) == 0ULL) &&
             (fm == -1.5) &&
             (rd == -3.0) &&
             (r49 == 0.0) &&
             (f2u(ff) == 0x40600000U) &&
             (f2u(sf) == 0x40400000U) &&
             (f2u(cf) == 0xc0000000U);
    return ok ? 1 : 0;
}"))

(display "=======================================================================\n")
(display " SSE2 XMM Suite Passed: ")
(display (car *xmm-pass*)) (display " / ")
(display (+ (car *xmm-pass*) (car *xmm-fail*))) (display " checks\n")
(display "=======================================================================\n")
