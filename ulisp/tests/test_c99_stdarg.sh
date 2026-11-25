#!/usr/bin/env bash
# ==============================================================================
# ULisp C99 SysV AMD64 <stdarg.h> E2E Oracle & Bidirectional Cross-Link Suite (#921)
# Verifies:
#   1. 3-way Oracle Parity (Host GCC -O2 vs ULisp Native ELF -O0/-O2 vs Portable C -O0/-O2):
#      - Built-in #include <stdarg.h>, sizeof/Alignof(va_list)
#      - 10+ GPR args & 10+ XMM double args (incl. float->double default promotion)
#      - Mixed int/double/ptr args, >6 named params & >16B sret + variadic
#      - <=16B structs: (II), (FF), Mixed (IF)/(FI) + All-or-Nothing boundary, >16B MEMORY
#      - va_copy, va_list helper passing, indirect variadic fn pointer
#      - Host libc vsnprintf/vsprintf interoperability on ints, doubles, strings & stack args
#   2. x86-64 Assembly Verification (-S): and rax, 255 / cmp rax, 0 / movsd
#   3. Bidirectional Host GCC <-> ULisp Native ELF Cross-Linking (default PIE + -no-pie)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$ULISP_DIR")"
BUILD_DIR="$ULISP_DIR/build/test_c99_stdarg_$$"
DRIVER_RUNNER="$ULISP_DIR/build/c_driver_runner.scm"

if [ -x "$ROOT_DIR/.venv/bin/python" ]; then
    PYTHON="$ROOT_DIR/.venv/bin/python"
else
    PYTHON="python3"
fi

run_ucc() {
    if [ "${USE_GOSH:-0}" = "1" ] && command -v gosh >/dev/null 2>&1; then
        gosh -ugauche.uvector -ugauche.process -uscheme.file -uscheme.bitwise -uscheme.process-context -I "$ULISP_DIR" -I "$ROOT_DIR" "$DRIVER_RUNNER" "$@"
    else
        PYTHONPATH="$ROOT_DIR" "$PYTHON" -m ilisp "$DRIVER_RUNNER" -- "$@"
    fi
}

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
trap 'rm -rf "$BUILD_DIR"' EXIT

PASS_COUNT=0
TOTAL_COUNT=0

assert_eq() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  [PASS] $label"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  [FAIL] $label"
        echo "         expected: '$expected'"
        echo "         actual:   '$actual'"
        exit 1
    fi
}

assert_grep() {
    local label="$1"
    local pattern="$2"
    local file="$3"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    if grep -q -E "$pattern" "$file"; then
        echo "  [PASS] $label"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  [FAIL] $label (pattern '$pattern' not found in $file)"
        exit 1
    fi
}

echo "========================================================================"
echo " Starting C99 SysV AMD64 <stdarg.h> Oracle & Cross-Link Suite (#921)"
echo "========================================================================"

cat > "$BUILD_DIR/stdarg_oracle.c" << 'EOF'
#include <stdarg.h>

int puts(const char *s);
int printf(const char *fmt, ...);
int vsnprintf(char *buf, unsigned long sz, const char *fmt, va_list ap);
int vsprintf(char *buf, const char *fmt, va_list ap);

struct PairII { long a; long b; };
struct PairFF { double x; double y; };
struct MixedIF { long i; double d; };
struct MixedFI { double d; long i; };
struct BigM { long a; long b; long c; };

static long sum_ints(int n, ...) {
    va_list ap;
    va_start(ap, n);
    long acc = 0;
    for (int i = 0; i < n; i++) acc += va_arg(ap, int);
    va_end(ap);
    return acc;
}

static long sum_doubles_100(int n, ...) {
    va_list ap;
    va_start(ap, n);
    double acc = 0.0;
    for (int i = 0; i < n; i++) acc += va_arg(ap, double);
    va_end(ap);
    return (long)(acc * 100.0 + 0.5);
}

static long helper_vcopy(int n, va_list orig) {
    va_list cp;
    va_copy(cp, orig);
    long s = 0;
    for (int i = 0; i < n; i++) s += (long)(i + 1) * (long)va_arg(cp, int);
    va_end(cp);
    return s;
}

static long test_va_copy_entry(int n, ...) {
    va_list ap;
    va_start(ap, n);
    long r1 = helper_vcopy(n, ap);
    long r2 = 0;
    for (int i = 0; i < n; i++) r2 += va_arg(ap, int);
    va_end(ap);
    return r1 * 1000 + r2;
}

static long test_aggs(int dummy, ...) {
    va_list ap;
    va_start(ap, dummy);
    struct PairII ii = va_arg(ap, struct PairII);
    struct PairFF ff = va_arg(ap, struct PairFF);
    struct MixedIF mi = va_arg(ap, struct MixedIF);
    struct BigM bm = va_arg(ap, struct BigM);
    struct PairFF ff_ovf = va_arg(ap, struct PairFF);
    va_end(ap);
    long fp_term = (long)((ff.x + ff.y + ff_ovf.x + ff_ovf.y) * 10.0 + 0.5);
    return ii.a + ii.b + mi.i + (long)(mi.d * 10.0 + 0.5) + bm.a + bm.b + bm.c + fp_term + dummy;
}

static long test_all_or_nothing(int g1, int g2, int g3, int g4, int g5, int g6, ...) {
    va_list ap;
    va_start(ap, g6);
    struct MixedFI m = va_arg(ap, struct MixedFI);
    double xmm0_d = va_arg(ap, double);
    va_end(ap);
    return g1 + g2 + g3 + g4 + g5 + g6 + m.i + (long)((m.d + xmm0_d) * 10.0 + 0.5);
}

static struct BigM sret_variadic(int base, ...) {
    va_list ap;
    va_start(ap, base);
    int x = va_arg(ap, int);
    double y = va_arg(ap, double);
    struct BigM r;
    r.a = base + x;
    r.b = (long)(y * 10.0 + 0.5);
    r.c = 777;
    va_end(ap);
    return r;
}

static void fmt_via_libc(char *out, char *out2, unsigned long sz, const char *fmt, ...) {
    va_list ap, ap2;
    va_start(ap, fmt);
    va_copy(ap2, ap);
    vsnprintf(out, sz, fmt, ap);
    va_end(ap);
    vsprintf(out2, fmt, ap2);
    va_end(ap2);
}

static void fmt_via_vsnprintf_twice(char *o1, char *o2, const char *fmt, ...) {
    va_list ap, cp;
    va_start(ap, fmt);
    va_copy(cp, ap);
    vsnprintf(o1, 256, fmt, ap);
    vsnprintf(o2, 256, fmt, cp);
    va_end(cp);
    va_end(ap);
}

static int indirect_var_cb(int k, ...) {
    va_list ap;
    va_start(ap, k);
    double a = va_arg(ap, double);
    int b = va_arg(ap, int);
    va_end(ap);
    return k + (int)(a * 10.0 + 0.5) + b;
}

int main(void) {
    float f = 1.25f;
    long si = sum_ints(12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12);
    long sd = sum_doubles_100(10, f, 2.75, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0);
    long svc = test_va_copy_entry(4, 10, 20, 30, 40);

    struct PairII ii = {11, 22};
    struct PairFF ff = {1.5, 2.5};
    struct MixedIF mi = {33, 4.5};
    struct BigM bm = {100, 200, 300};
    struct PairFF ffo = {5.5, 6.5};
    long sa = test_aggs(5, ii, ff, mi, bm, ffo);

    struct MixedFI fi = {88, 3.2};
    long sbn = test_all_or_nothing(1, 2, 3, 4, 5, 6, fi, 9.8);

    struct BigM sr = sret_variadic(10, 32, 4.5);

    int (*vfp)(int, ...) = indirect_var_cb;
    int ind = vfp(7, 2.5, 30);

    char b1[256], b2[256], b3[256], b4[256];
    fmt_via_vsnprintf_twice(b1, b2, "v=%d,%.1f,%s,%d,%d,%d,%d,%.1f",
                            11, 2.5, "ulisp", 33, 44, 55, 66, 7.5);
    fmt_via_libc(b3, b4, sizeof(b3), "sz=%lu,al=%lu", (unsigned long)sizeof(va_list), (unsigned long)_Alignof(va_list));

    printf("si=%ld sd=%ld svc=%ld\n", si, sd, svc);
    printf("sa=%ld sbn=%ld ind=%d\n", sa, sbn, ind);
    printf("sr=%ld,%ld,%ld\n", sr.a, sr.b, sr.c);
    puts(b1);
    puts(b2);
    puts(b3);
    puts(b4);
    return 0;
}
EOF

gcc -O2 "$BUILD_DIR/stdarg_oracle.c" -o "$BUILD_DIR/gcc_oracle"
GCC_OUT=$("$BUILD_DIR/gcc_oracle")

run_ucc -O0 "$BUILD_DIR/stdarg_oracle.c" -o "$BUILD_DIR/ulisp_elf_o0"
ELF_O0_OUT=$("$BUILD_DIR/ulisp_elf_o0")
assert_eq "1.1 ULisp Native ELF (-O0) matches Host GCC oracle" "$GCC_OUT" "$ELF_O0_OUT"

run_ucc -O2 "$BUILD_DIR/stdarg_oracle.c" -o "$BUILD_DIR/ulisp_elf_o2"
ELF_O2_OUT=$("$BUILD_DIR/ulisp_elf_o2")
assert_eq "1.2 ULisp Native ELF (-O2) matches Host GCC oracle" "$GCC_OUT" "$ELF_O2_OUT"

run_ucc --target=c -O0 "$BUILD_DIR/stdarg_oracle.c" -o "$BUILD_DIR/ulisp_c_o0"
C_O0_OUT=$("$BUILD_DIR/ulisp_c_o0")
assert_eq "1.3 ULisp Portable C (-O0) matches Host GCC oracle" "$GCC_OUT" "$C_O0_OUT"

run_ucc --target=c -O2 "$BUILD_DIR/stdarg_oracle.c" -o "$BUILD_DIR/ulisp_c_o2"
C_O2_OUT=$("$BUILD_DIR/ulisp_c_o2")
assert_eq "1.4 ULisp Portable C (-O2) matches Host GCC oracle" "$GCC_OUT" "$C_O2_OUT"

# ------------------------------------------------------------------------------
# 2. x86-64 Assembly Verification (-S)
# ------------------------------------------------------------------------------
run_ucc -S -O2 "$BUILD_DIR/stdarg_oracle.c" -o "$BUILD_DIR/stdarg_oracle.s"
assert_grep "2.1 Variadic prologue masks %al (and rax, 255)" '^\s*and\s+rax,\s*255\s*$' "$BUILD_DIR/stdarg_oracle.s"
assert_grep "2.2 Variadic prologue guards XMM spill (je va_skip_xmm)" '^\s*(cmp\s+rax,\s*0|je\s+\.L_c99_va_skip_xmm)' "$BUILD_DIR/stdarg_oracle.s"
assert_grep "2.3 Variadic prologue spills XMM registers (movsd)" 'movsd\s+qword ptr \[rsp' "$BUILD_DIR/stdarg_oracle.s"

# ------------------------------------------------------------------------------
# 3. Bidirectional Host GCC <-> ULisp Native ELF Cross-Linking (PIE & -no-pie)
# ------------------------------------------------------------------------------
cat > "$BUILD_DIR/ulisp_va_side.c" << 'EOF'
#include <stdarg.h>

extern int host_vsnprintf_wrap(char *buf, unsigned long sz, const char *fmt, va_list ap);
extern long host_collect_varargs(int count_i, int count_d, ...);

struct PairFF { double x; double y; };
struct MixedIF { long i; double d; };
struct BigM { long a; long b; long c; };

long ulisp_sum_ints(int n, ...) {
    va_list ap;
    va_start(ap, n);
    long s = 0;
    for (int i = 0; i < n; i++) s += va_arg(ap, int);
    va_end(ap);
    return s;
}

long ulisp_sum_mixed(int ni, int nd, ...) {
    va_list ap;
    va_start(ap, nd);
    long isum = 0;
    for (int i = 0; i < ni; i++) isum += va_arg(ap, int);
    double dsum = 0.0;
    for (int j = 0; j < nd; j++) dsum += va_arg(ap, double);
    va_end(ap);
    return isum * 100 + (long)(dsum * 10.0 + 0.5);
}

long ulisp_va_structs(int dummy, ...) {
    va_list ap;
    va_start(ap, dummy);
    struct PairFF ff = va_arg(ap, struct PairFF);
    struct MixedIF mi = va_arg(ap, struct MixedIF);
    struct BigM bm = va_arg(ap, struct BigM);
    va_end(ap);
    return dummy + mi.i + bm.a + bm.b + bm.c + (long)((ff.x + ff.y + mi.d) * 10.0 + 0.5);
}

int ulisp_format_via_host(char *buf, unsigned long sz, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int r = host_vsnprintf_wrap(buf, sz, fmt, ap);
    va_end(ap);
    return r;
}

long ulisp_call_host_varargs(void) {
    struct PairFF pf = {1.5, 2.5};
    struct MixedIF mi = {50, 3.5};
    struct BigM bm = {10, 20, 30};
    return host_collect_varargs(9, 10,
                                1, 2, 3, 4, 5, 6, 7, 8, 9,
                                0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5, 8.5, 9.5,
                                pf, mi, bm);
}
EOF

cat > "$BUILD_DIR/host_va_main.c" << 'EOF'
#include <stdarg.h>
#include <stdio.h>

struct PairFF { double x; double y; };
struct MixedIF { long i; double d; };
struct BigM { long a; long b; long c; };

extern long ulisp_sum_ints(int n, ...);
extern long ulisp_sum_mixed(int ni, int nd, ...);
extern long ulisp_va_structs(int dummy, ...);
extern int ulisp_format_via_host(char *buf, unsigned long sz, const char *fmt, ...);
extern long ulisp_call_host_varargs(void);

int host_vsnprintf_wrap(char *buf, unsigned long sz, const char *fmt, va_list ap) {
    return vsnprintf(buf, sz, fmt, ap);
}

long host_collect_varargs(int count_i, int count_d, ...) {
    va_list ap;
    va_start(ap, count_d);
    long si = 0;
    for (int i = 0; i < count_i; i++) si += va_arg(ap, int);
    double sd = 0.0;
    for (int j = 0; j < count_d; j++) sd += va_arg(ap, double);
    struct PairFF pf = va_arg(ap, struct PairFF);
    struct MixedIF mi = va_arg(ap, struct MixedIF);
    struct BigM bm = va_arg(ap, struct BigM);
    va_end(ap);
    return si + (long)((sd + pf.x + pf.y + mi.d) * 10.0 + 0.5) + mi.i + bm.a + bm.b + bm.c;
}

/* Force upper 56 bits of %rax non-zero while %al == 0 to verify RSA prologue mask */
extern long call_with_dirty_rax_al0(long (*fn)(int, ...));
__asm__(
".text\n"
".globl call_with_dirty_rax_al0\n"
".type call_with_dirty_rax_al0, @function\n"
"call_with_dirty_rax_al0:\n"
"    pushq %rbx\n"
"    movq %rdi, %rbx\n"
"    pushq $9\n"
"    pushq $8\n"
"    pushq $7\n"
"    pushq $6\n"
"    movl $9, %edi\n"
"    movl $1, %esi\n"
"    movl $2, %edx\n"
"    movl $3, %ecx\n"
"    movl $4, %r8d\n"
"    movl $5, %r9d\n"
"    movabsq $0xDEADBEEF12345600, %rax\n"
"    call *%rbx\n"
"    addq $32, %rsp\n"
"    popq %rbx\n"
"    ret\n"
".size call_with_dirty_rax_al0, .-call_with_dirty_rax_al0\n"
);

int main(void) {
    long r_dirty = call_with_dirty_rax_al0(ulisp_sum_ints);
    long r_mix = ulisp_sum_mixed(8, 10,
                                 1, 2, 3, 4, 5, 6, 7, 8,
                                 1.1, 2.2, 3.3, 4.4, 5.5, 6.6, 7.7, 8.8, 9.9, 0.5);
    struct PairFF pf = {2.5, 3.5};
    struct MixedIF mi = {17, 4.5};
    struct BigM bm = {100, 200, 300};
    long r_st = ulisp_va_structs(1, pf, mi, bm);
    char buf[128];
    int r_fmt = ulisp_format_via_host(buf, sizeof(buf), "cross:%d:%.1f:%s:%d:%d:%d",
                                      10, 2.5, "ok", 4, 5, 6);
    long r_host_cb = ulisp_call_host_varargs();
    printf("dirty=%ld mix=%ld st=%ld fmt=%d host_cb=%ld str=%s\n",
           r_dirty, r_mix, r_st, r_fmt, r_host_cb, buf);
    return 0;
}
EOF

run_ucc -c -O2 "$BUILD_DIR/ulisp_va_side.c" -o "$BUILD_DIR/ulisp_va_side.o"
gcc -c -O2 "$BUILD_DIR/host_va_main.c" -o "$BUILD_DIR/host_va_main_pie.o"
gcc -c -O2 -fno-pie "$BUILD_DIR/host_va_main.c" -o "$BUILD_DIR/host_va_main_nopie.o"

# Reference pure-GCC oracle
gcc -O2 "$BUILD_DIR/ulisp_va_side.c" "$BUILD_DIR/host_va_main.c" -o "$BUILD_DIR/cross_va_ref"
CROSS_REF=$("$BUILD_DIR/cross_va_ref")

# Default PIE cross-link
gcc "$BUILD_DIR/ulisp_va_side.o" "$BUILD_DIR/host_va_main_pie.o" -o "$BUILD_DIR/cross_va_pie"
CROSS_PIE=$("$BUILD_DIR/cross_va_pie")
assert_eq "3.1 Bidirectional Host GCC <-> ULisp stdarg cross-link (default PIE)" "$CROSS_REF" "$CROSS_PIE"

# -no-pie cross-link
gcc -no-pie "$BUILD_DIR/ulisp_va_side.o" "$BUILD_DIR/host_va_main_nopie.o" -o "$BUILD_DIR/cross_va_nopie"
CROSS_NOPIE=$("$BUILD_DIR/cross_va_nopie")
assert_eq "3.2 Bidirectional Host GCC <-> ULisp stdarg cross-link (-no-pie)" "$CROSS_REF" "$CROSS_NOPIE"

echo "========================================================================"
echo " C99 SysV AMD64 <stdarg.h> Oracle Suite (#921): $PASS_COUNT / $TOTAL_COUNT PASS"
echo "========================================================================"
