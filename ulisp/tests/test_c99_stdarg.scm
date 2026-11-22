;;; =======================================================================
;;; test_c99_stdarg.scm
;;; System V AMD64 <stdarg.h> (va_list, va_start, va_arg, va_end, va_copy)
;;; Conforms to ISO C99 §7.15, System V AMD64 psABI §3.5.7 & Issue #921
;;; Zero local `set!` (ULisp AOT safe).
;;; =======================================================================

(define *tests-passed* (cons 0 '()))
(define *tests-failed* (cons 0 '()))

(define (assert-true desc val)
  (if val
      (begin
        (set-car! *tests-passed* (+ (car *tests-passed*) 1))
        (display "  [PASS] ") (display desc) (newline))
      (begin
        (set-car! *tests-failed* (+ (car *tests-failed*) 1))
        (display "  [FAIL] ") (display desc) (newline)
        (error "Assertion failed: expected #t" desc))))

(define (assert-equal desc expected actual)
  (if (equal? expected actual)
      (begin
        (set-car! *tests-passed* (+ (car *tests-passed*) 1))
        (display "  [PASS] ") (display desc) (newline))
      (begin
        (set-car! *tests-failed* (+ (car *tests-failed*) 1))
        (display "  [FAIL] ") (display desc)
        (display " (expected ") (write expected)
        (display ", got ") (write actual) (display ")") (newline)
        (error "Assertion failed: values not equal" desc))))

(define (c99-run-code src)
  (let ((lir (c99-compile-string-to-lir src "<test-stdarg>")))
    (eval-lir-program lir)))

(define (c99-expect-error err-code src)
  (guard (ex
          ((and (pair? ex) (pair? (cdr ex)) (equal? (cadr ex) err-code))
           #t)
          (else
           (display "  [UNEXPECTED ERROR] Expected ") (display err-code)
           (display ", got: ") (write ex) (newline)
           #f))
    (let* ((ast (parse-c99-preprocessed-string src "<test-va-err>"))
           (typed (c99-analyze-program ast)))
      (c99-lower-to-lir typed)
      #f)))

(display "=== [Test Suite: C99 SysV AMD64 <stdarg.h> Lowering (Issue #921)] ===\n\n")

;;; -----------------------------------------------------------------------
;;; Group 1: Built-in <stdarg.h> Resolution, Layout & -isystem Override
;;; -----------------------------------------------------------------------
(display "--- Group 1: Built-in <stdarg.h>, sizeof/Alignof(va_list) & Override ---\n")

(assert-equal "1.1 sizeof(va_list) == 24 and _Alignof(va_list) == 8 + idempotent include"
  2408
  (c99-run-code "
#include <stdarg.h>
#include <stdarg.h>
int main(void) {
    va_list ap;
    return (int)(sizeof(va_list) * 100 + _Alignof(va_list) + (sizeof(ap) - 24));
}"))

(let* ((ctx (make-default-cpp-context))
       (toks (cpp-preprocess-string "#include <stdarg.h>\nva_list x;\n" "<builtin-v>" ctx))
       (txt (c-tokens->source-string toks)))
  (assert-true "1.2 Default CPP resolves #include <stdarg.h> to typedef __builtin_va_list"
               (and (string? txt) (> (string-length txt) 10))))

(let ((ctx (make-default-cpp-context)))
  (cpp-register-virtual-file! ctx "/tmp/custom_inc/stdarg.h" "#define CUSTOM_VA_OVERRIDE 777\n")
  (cpp-add-include-path! ctx "/tmp/custom_inc" #t)
  (let* ((toks (cpp-preprocess-string "#include <stdarg.h>\nint v = CUSTOM_VA_OVERRIDE;\n" "<override>" ctx))
         (ast (parse-c99-tokens toks))
         (typed (c99-analyze-program ast))
         (lir (c99-lower-to-lir typed)))
    (assert-true "1.3 User -isystem path overrides built-in <stdarg.h>"
                 (L_lir_core? lir))))

;;; -----------------------------------------------------------------------
;;; Group 2: Scalar GPR Register Save Area & Stack Overflow (>6 GPRs)
;;; -----------------------------------------------------------------------
(display "--- Group 2: Scalar GPR RSA & Overflow Stack Args ---\n")

(assert-equal "2.1 sum_ints across 5 GPR RSA slots + 5 stack overflow args"
  55
  (c99-run-code "
#include <stdarg.h>
int sum_ints(int count, ...) {
    va_list ap;
    va_start(ap, count);
    int total = 0;
    for (int i = 0; i < count; i++) {
        total += va_arg(ap, int);
    }
    va_end(ap);
    return total;
}
int main(void) {
    return sum_ints(10, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
}"))

(assert-equal "2.2 longs, unsigned ints & pointers via va_arg"
  412
  (c99-run-code "
#include <stdarg.h>
long accum_mixed_gpr(int tag, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    long a = va_arg(ap, long);
    int *p = va_arg(ap, int *);
    unsigned int u = va_arg(ap, unsigned int);
    long s1 = va_arg(ap, long);
    long s2 = va_arg(ap, long);
    long s3 = va_arg(ap, long);
    va_end(ap);
    return tag + a + *p + (long)u + s1 + s2 + s3 + (fmt[0] == 'X' ? 10 : 0);
}
int main(void) {
    int x = 42;
    return (int)accum_mixed_gpr(2, \"X\", 100L, &x, 8U, 50L, 100L, 100L);
}"))

;;; -----------------------------------------------------------------------
;;; Group 3: XMM Float Register Save Area & Overflow (>8 XMMs + Promotion)
;;; -----------------------------------------------------------------------
(display "--- Group 3: XMM RSA, Overflow & float->double Promotion ---\n")

(assert-equal "3.1 sum_doubles across all 8 XMM RSA slots + 3 stack overflow doubles"
  670
  (c99-run-code "
#include <stdarg.h>
long sum_doubles_x10(int n, ...) {
    va_list ap;
    va_start(ap, n);
    double acc = 0.0;
    for (int i = 0; i < n; i++) {
        acc += va_arg(ap, double);
    }
    va_end(ap);
    return (long)(acc * 10.0 + 0.5);
}
int main(void) {
    float f1 = 1.5f;
    float f2 = 2.5f;
    return (int)sum_doubles_x10(11, f1, f2, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0);
}"))

;;; -----------------------------------------------------------------------
;;; Group 4: Interleaved Scalar + Named Stack Overflow + sret
;;; -----------------------------------------------------------------------
(display "--- Group 4: Mixed GP/XMM, Named Stack Overflow & sret + Variadic ---\n")

(assert-equal "4.1 Named >6 stack params + interleaved ints/doubles + sret >16B return"
  2142
  (c99-run-code "
#include <stdarg.h>
struct BigRes { long sum_i; long sum_d10; long extra; };
struct BigRes compute_big(int n1, int n2, int n3, int n4, int n5, int n6, int n7, ...) {
    va_list ap;
    va_start(ap, n7);
    int vi1 = va_arg(ap, int);
    double vd1 = va_arg(ap, double);
    int vi2 = va_arg(ap, int);
    double vd2 = va_arg(ap, double);
    va_end(ap);
    struct BigRes r;
    r.sum_i = n1 + n2 + n3 + n4 + n5 + n6 + n7 + vi1 + vi2;
    r.sum_d10 = (long)(vd1 * 10.0 + vd2 * 10.0 + 0.5);
    r.extra = 2000;
    return r;
}
int main(void) {
    struct BigRes r = compute_big(1, 2, 3, 4, 5, 6, 7, 10, 3.5, 20, 4.9);
    return (int)(r.extra + r.sum_i + r.sum_d10);
}"))

;;; -----------------------------------------------------------------------
;;; Group 5: Aggregate va_arg (All 4 SysV Classes, All-or-Nothing & Braun SSA)
;;; -----------------------------------------------------------------------
(display "--- Group 5: Aggregate va_arg (II, FF, Mixed All-or-Nothing, MEMORY, SSA) ---\n")

(assert-equal "5.1 <=16B (II), (FF) stride-16/overflow, and >16B MEMORY struct va_arg + postfix"
  2770
  (c99-run-code "
#include <stdarg.h>
struct PairII { long a; long b; };
struct PairFF { double x; double y; };
struct BigM { long a; long b; long c; };
long test_aggs(int mode, ...) {
    va_list ap;
    va_start(ap, mode);
    struct PairII ii1 = va_arg(ap, struct PairII);
    struct PairFF ff1 = va_arg(ap, struct PairFF);
    struct BigM   bm1 = va_arg(ap, struct BigM);
    struct PairII ii2 = va_arg(ap, struct PairII);
    struct PairII ii3 = va_arg(ap, struct PairII);
    long postfix_b = va_arg(ap, struct PairII).b;
    va_end(ap);
    long f10 = (long)((ff1.x + ff1.y) * 10.0 + 0.5);
    return ii1.a + ii1.b + f10 + bm1.a + bm1.b + bm1.c + ii2.a + ii2.b + ii3.a + ii3.b + postfix_b + mode;
}
int main(void) {
    struct PairII p1 = {10, 20};
    struct PairFF f1 = {1.5, 2.5};
    struct BigM   b1 = {100, 200, 300};
    struct PairII p2 = {30, 40};
    struct PairII p3 = {50, 60};
    struct PairII p4 = {999, 1920};
    return (int)test_aggs(0, p1, f1, b1, p2, p3, p4);
}"))

(assert-equal "5.2 SysV psABI §3.5.7 All-or-Nothing boundary (no partial GP/FP mutation on overflow)"
  450
  (c99-run-code "
#include <stdarg.h>
struct MixedIF { long i; double d; };
struct MixedFI { double d; long i; };

/* Caller uses 6 named GPRs (g1..g6) -> gp_offset=48, fp_offset=48.
 * Next arg is struct MixedFI (SSE, INTEGER). Even though XMM0 is available,
 * GPRs are exhausted so MixedFI MUST overflow to stack WITHOUT consuming XMM0.
 * Following double MUST still read XMM0! */
long boundary_gpr_exhausted(int g1, int g2, int g3, int g4, int g5, int g6, ...) {
    va_list ap;
    va_start(ap, g6);
    struct MixedFI m = va_arg(ap, struct MixedFI);
    double d_from_xmm0 = va_arg(ap, double);
    va_end(ap);
    return g1 + g6 + m.i + (long)(m.d * 10.0 + 0.5) + (long)(d_from_xmm0 * 10.0 + 0.5);
}

/* Caller consumes all 8 XMMs via f1..f8 -> gp_offset=8 (only g0 used), fp_offset=176.
 * Next arg is struct MixedIF (INTEGER, SSE). Even though RSI is free,
 * SSEs are exhausted so MixedIF MUST overflow WITHOUT consuming RSI.
 * Following int MUST still read RSI! */
long boundary_sse_exhausted(int g0, double f1, double f2, double f3, double f4,
                            double f5, double f6, double f7, double f8, ...) {
    va_list ap;
    va_start(ap, f8);
    struct MixedIF m = va_arg(ap, struct MixedIF);
    int i_from_rsi = va_arg(ap, int);
    va_end(ap);
    return g0 + (long)f8 + m.i + (long)(m.d * 10.0 + 0.5) + i_from_rsi;
}

int main(void) {
    struct MixedFI fi = {3.5, 100};
    struct MixedIF ifv = {200, 4.5};
    long r1 = boundary_gpr_exhausted(1, 2, 3, 4, 5, 9, fi, 2.5);
    long r2 = boundary_sse_exhausted(2, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, ifv, 25);
    return (int)(r1 + r2);
}"))

(let* ((va-ssa-src "
#include <stdarg.h>
struct PairFF { double a; double b; };
struct MixedIF { long k; double v; };
long va_ssa_fn(int mode, ...) {
    va_list ap, cp;
    va_start(ap, mode);
    va_copy(cp, ap);
    struct PairFF pf = va_arg(ap, struct PairFF);
    struct MixedIF mi = va_arg(ap, struct MixedIF);
    long x = va_arg(cp, struct PairFF).a > 0 ? va_arg(cp, struct MixedIF).k : 0;
    va_end(cp);
    va_end(ap);
    return (long)(pf.a + pf.b + mi.v) + mi.k + x + mode;
}
int main(void) {
    struct PairFF pf = {2.0, 3.0};
    struct MixedIF mi = {40, 5.0};
    return (int)va_ssa_fn(7, pf, mi);
}")
       (ast (parse-c99-preprocessed-string va-ssa-src "<va-ssa>"))
       (typed (c99-analyze-program ast))
       (funcs (list-ref typed 2))
       (va-ast (car funcs))
       (lir-prog (c99-lower-to-lir typed))
       (fns-clause (assq '%lir-functions (cdr lir-prog)))
       (va-lir (cadr fns-clause))
       (cand-offsets (c99-function-candidate-mem2reg-offsets va-ast '()))
       (cfg (c99-lir-fn->braun-cfg va-lir cand-offsets))
       (ssa-fn (c99-braun-ssa-transform-fn va-lir cand-offsets))
       (new-fns-clause (cons '%lir-functions
                             (map (lambda (f) (if (eq? (list-ref f 1) 'va_ssa_fn) ssa-fn f))
                                  (cdr fns-clause))))
       (ssa-prog (map (lambda (item)
                        (if (and (pair? item) (eq? (car item) '%lir-functions))
                            new-fns-clause
                            item))
                      lir-prog)))
  (assert-true "5.3 Pass 132 Braun SSA CFG seals, verifies & passes L_lir_core on variadic RSA + va_arg diamonds"
               (and (braun-verify-cfg cfg)
                    (L_lir_core? ssa-prog)
                    (validate-core-lir ssa-prog)))
  (assert-equal "5.4 Braun SSA-transformed variadic function executes accurately on VM"
                97
                (eval-lir-program ssa-prog)))

;;; -----------------------------------------------------------------------
;;; Group 6: va_copy, Helper Passing, Indirect Variadic Calls & Mini Formatter
;;; -----------------------------------------------------------------------
(display "--- Group 6: va_copy, va_list Parameter Passing, Indirect & Mini Formatter ---\n")

(assert-equal "6.1 va_copy, va_list passed to helper & indirect variadic function pointer"
  735
  (c99-run-code "
#include <stdarg.h>
int helper_sum(int n, va_list ap) {
    int s = 0;
    for (int i = 0; i < n; i++) s += va_arg(ap, int);
    return s;
}
int var_entry(int n, ...) {
    va_list ap, ap2;
    va_start(ap, n);
    va_copy(ap2, ap);
    int r1 = helper_sum(n, ap);
    int first = va_arg(ap2, int);
    int second = va_arg(ap2, int);
    va_end(ap2);
    va_end(ap);
    return r1 + first * 10 + second;
}
int mixed_cb(int n, ...) {
    va_list ap;
    va_start(ap, n);
    double d = va_arg(ap, double);
    int k = va_arg(ap, int);
    va_end(ap);
    return (int)(d * 10.0 + 0.5) + k + n;
}
int main(void) {
    int (*fp)(int, ...) = var_entry;
    int (*mfp)(int, ...) = mixed_cb;
    int a = fp(4, 10, 20, 30, 40);
    int b = (*mfp)(1, 5.5, 459);
    return a + b;
}"))

(assert-equal "6.2 Pure-C lua_pushfstring-style variadic formatter on Reference VM"
  1
  (c99-run-code "
#include <stdarg.h>
int mini_format(char *out, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int pos = 0;
    for (int i = 0; fmt[i] != 0; i++) {
        if (fmt[i] != '%') {
            out[pos++] = fmt[i];
        } else {
            i++;
            char spec = fmt[i];
            if (spec == 's') {
                const char *s = va_arg(ap, const char *);
                while (*s) out[pos++] = *s++;
            } else if (spec == 'c') {
                out[pos++] = (char)va_arg(ap, int);
            } else if (spec == 'd') {
                int v = va_arg(ap, int);
                if (v < 0) { out[pos++] = '-'; v = -v; }
                char tmp[16];
                int k = 0;
                do { tmp[k++] = (char)('0' + (v % 10)); v /= 10; } while (v > 0);
                while (k > 0) out[pos++] = tmp[--k];
            } else if (spec == 'f') {
                double d = va_arg(ap, double);
                int iv = (int)(d * 10.0 + 0.5);
                out[pos++] = (char)('0' + (iv / 10));
                out[pos++] = '.';
                out[pos++] = (char)('0' + (iv % 10));
            } else if (spec == '%') {
                out[pos++] = '%';
            }
        }
    }
    out[pos] = 0;
    va_end(ap);
    return pos;
}
int str_eq(const char *a, const char *b) {
    while (*a && *b) { if (*a != *b) return 0; a++; b++; }
    return *a == *b;
}
int main(void) {
    char buf[128];
    mini_format(buf, \"%s:%d:%c:%f%%\", \"lua\", -42, 'Z', 3.5);
    return str_eq(buf, \"lua:-42:Z:3.5%\");
}"))

;;; -----------------------------------------------------------------------
;;; Group 7: Diagnostics C99-VA-001 & C99-VA-002
;;; -----------------------------------------------------------------------
(display "--- Group 7: Diagnostics (C99-VA-001 & C99-VA-002) ---\n")

(assert-true "7.1 C99-VA-001 on va_start in non-variadic function"
  (c99-expect-error "C99-VA-001" "
#include <stdarg.h>
void f(int x) { va_list ap; va_start(ap, x); va_end(ap); }
int main(void) { return 0; }"))

(assert-true "7.2 C99-VA-001 on va_start with wrong last parameter"
  (c99-expect-error "C99-VA-001" "
#include <stdarg.h>
void f(int a, int b, ...) { va_list ap; va_start(ap, a); va_end(ap); }
int main(void) { return 0; }"))

(assert-true "7.3 C99-VA-001 on non-va_list argument to va_start/va_arg"
  (c99-expect-error "C99-VA-001" "
#include <stdarg.h>
int f(int a, ...) { void *p = &a; return va_arg(p, int); }
int main(void) { return 0; }"))

(assert-true "7.4 C99-VA-001 on va_arg with void or array type"
  (c99-expect-error "C99-VA-001" "
#include <stdarg.h>
void f(int a, ...) { va_list ap; va_start(ap, a); va_arg(ap, int[4]); va_end(ap); }
int main(void) { return 0; }"))

(assert-true "7.5 C99-VA-002 on unpromoted narrow types (char, short, float, _Bool)"
  (and
    (c99-expect-error "C99-VA-002" "
#include <stdarg.h>
int f(int a, ...) { va_list ap; va_start(ap, a); int r = va_arg(ap, char); va_end(ap); return r; }")
    (c99-expect-error "C99-VA-002" "
#include <stdarg.h>
int f(int a, ...) { va_list ap; va_start(ap, a); int r = va_arg(ap, short); va_end(ap); return r; }")
    (c99-expect-error "C99-VA-002" "
#include <stdarg.h>
double f(int a, ...) { va_list ap; va_start(ap, a); double r = va_arg(ap, float); va_end(ap); return r; }")
    (c99-expect-error "C99-VA-002" "
#include <stdarg.h>
int f(int a, ...) { va_list ap; va_start(ap, a); int r = va_arg(ap, _Bool); va_end(ap); return r; }")))

(display "\n=== [Summary: ")
(display (car *tests-passed*))
(display " passed, ")
(display (car *tests-failed*))
(display " failed] ===\n")
(if (> (car *tests-failed*) 0)
    (exit 1))
