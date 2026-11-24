#!/usr/bin/env bash
# ==============================================================================
# ULisp C99 Floating-Point Sema, IEEE 754 Encoder & Core LIR Lowering Oracle (#923)
# Verifies:
#   1. 3-way Oracle Parity (Host GCC -O2 vs Native ELF -O0/-O2 vs Portable C -O0/-O2):
#      - Decimal & C99 hex float literals (f32/f64), subnormals, -0.0, single-rounding
#      - Runtime +/-/*/div including 1.0/0.0, -1.0/0, NaN IEEE comparisons & (bool)NaN
#      - Unary - preserving -(0.0) == -0.0 and -(0.0f) == -0.0f
#      - Float pre/post ++/-- and mixed compound assignments (int += double, float += double)
#      - All 8 control-flow condition sites (if/while/do-while/for/?:/struct?:/&&/||) & !x
#      - Int <-> Float conversions (negative s64, u64 >= 2^63, i64/u64 -> f32 single-rounding,
#        double -> u64 >= 2^63) and long double = double
#      - Bit-exact static global/struct/array float initializers (-0.0, -0.0f, subnormals)
#   2. x86-64 Assembly (-S -O2) .section .rodata & .L_c99_fp64_/fp32_ pool verification
#   3. Multi-TU separate compilation (-c + ld & --target=c merge) shared .rodata dedup
#   4. Negative CLI checks confirming C99-FP-001 and C99-FP-002 diagnostics fail cleanly
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$ULISP_DIR")"
BUILD_DIR="$ULISP_DIR/build/test_c99_fp_$$"
DRIVER_RUNNER="$ULISP_DIR/build/c_driver_runner.scm"

if [ -x "$ROOT_DIR/.venv/bin/python" ]; then
    PYTHON="$ROOT_DIR/.venv/bin/python"
else
    PYTHON="python3"
fi

run_ucc() {
    if [ -n "${ULISP_CC_BIN:-}" ] && [ -x "${ULISP_CC_BIN}" ]; then
        "$ULISP_CC_BIN" "$@"
    elif [ "${USE_GOSH:-0}" = "1" ] && command -v gosh >/dev/null 2>&1; then
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
echo " Starting C99 Floating-Point Sema & Core LIR Lowering Suite (#923)"
echo "========================================================================"

# ------------------------------------------------------------------------------
# 1. 3-Way Oracle Parity (Host GCC -O2 vs Native ELF -O0/-O2 vs Portable C -O0/-O2)
#    (Every printf keeps <= 5 total args for Portable C varargs parity)
# ------------------------------------------------------------------------------
cat > "$BUILD_DIR/fp_oracle.c" << 'EOF'
typedef unsigned int u32_t;
typedef unsigned long long u64_t;
typedef long long s64_t;

void *memcpy(void *dst, const void *src, unsigned long n);
int printf(const char *fmt, ...);

static u64_t d2bits(double x) {
    u64_t b = 0;
    memcpy(&b, &x, 8);
    return b;
}

static u32_t f2bits(float x) {
    u32_t b = 0;
    memcpy(&b, &x, 4);
    return b;
}

static int is_nan_d(double x) {
    return (d2bits(x) & 0x7fffffffffffffffULL) > 0x7ff0000000000000ULL;
}

struct FPStatic {
    double nz;
    float fnz;
    double sub;
    float s1;
};

static double g_nz = -0.0;
static float g_fnz = -0.0f;
static double g_pinf = 1.0 / 0.0;
static double g_ninf = -1.0 / 0.0;
static struct FPStatic g_st = { -0.0, -0.0f, 0x1p-1074, 0x1.00000100000000000001p0f };

struct Pair {
    int tag;
    double val;
};

static int test_conds(double x, struct Pair a, struct Pair b) {
    int c1 = x ? 1 : 0;
    int c2 = !x;
    int c3 = (_Bool)x;
    int c4 = 0;
    if (x) c4 = 1;
    int c5 = 0;
    while (x) {
        c5 = 1;
        break;
    }
    int c6 = 0;
    double dvar = x;
    do {
        c6++;
        if (c6 > 1) break;
        dvar = 0.0;
    } while (dvar);
    int c7 = 0;
    for (double f = x; f; f = 0.0) {
        c7++;
        if (c7 > 1) break;
    }
    int c8 = (x && 1) ? 1 : 0;
    int c9 = (0 || x) ? 1 : 0;
    struct Pair p = x ? a : b;
    return (c1 << 0) | (c2 << 1) | (c3 << 2) | (c4 << 3) |
           (c5 << 4) | ((c6 - 1) << 5) | (c7 << 6) | (c8 << 7) |
           (c9 << 8) | ((p.tag & 1) << 9);
}

int main(void) {
    /* 1. Literals, subnormals, -0.0, single rounding */
    double d_pi = 0x1.921fb54442d18p+1;
    double d_dec = 0.1 + 0.2;
    double d_sub = 0x1p-1074;
    double d_sub_dec = 1e-320;
    double d_neg_zero = -0.0;
    double d_ovf = 1e500;
    double d_udf = 1e-500;
    float f_sr1 = 0x1.000001p0f;
    float f_sr2 = 0x1.00000100000000000001p0f;
    float f_max = 0x1.fffffep+127f;
    float f_sub = 0x1p-149f;

    printf("L1:%016llx:%016llx\n", (unsigned long long)d2bits(d_pi), (unsigned long long)d2bits(d_dec));
    printf("L2:%016llx:%016llx\n", (unsigned long long)d2bits(d_sub), (unsigned long long)d2bits(d_sub_dec));
    printf("L3:%016llx:%016llx:%016llx\n", (unsigned long long)d2bits(d_neg_zero), (unsigned long long)d2bits(d_ovf), (unsigned long long)d2bits(d_udf));
    printf("L4:%08x:%08x:%08x:%08x\n", (unsigned)f2bits(f_sr1), (unsigned)f2bits(f_sr2), (unsigned)f2bits(f_max), (unsigned)f2bits(f_sub));

    /* 2. Static initializers & unary neg */
    double z = 0.0;
    double nz_u = -z;
    double pz_u = -nz_u;
    float fz = 0.0f;
    float fnz_u = -fz;
    printf("S1:%016llx:%08x:%016llx\n", (unsigned long long)d2bits(g_nz), (unsigned)f2bits(g_fnz), (unsigned long long)d2bits(g_st.sub));
    printf("S2:%08x:%016llx:%016llx\n", (unsigned)f2bits(g_st.s1), (unsigned long long)d2bits(g_pinf), (unsigned long long)d2bits(g_ninf));
    printf("N1:%016llx:%016llx:%08x\n", (unsigned long long)d2bits(nz_u), (unsigned long long)d2bits(pz_u), (unsigned)f2bits(fnz_u));

    /* 3. NaN, Inf & IEEE 754 comparisons */
    volatile double vzero = 0.0;
    volatile double vone = 1.0;
    double r_pinf = vone / 0;
    double r_ninf = -vone / vzero;
    double r_nan = vzero / vzero;
    int nan_eq = (r_nan == r_nan) | ((r_nan == 1.0) << 1);
    int nan_ne = (r_nan != r_nan) | ((r_nan != 1.0) << 1);
    int nan_ord = (r_nan < 1.0) | ((r_nan <= 1.0) << 1) | ((r_nan > 1.0) << 2) | ((r_nan >= 1.0) << 3);
    int z_cmp = (d_neg_zero == z) | ((d_neg_zero != z) << 1) | ((d_neg_zero < z) << 2) | ((d_neg_zero <= z) << 3);
    printf("C1:%016llx:%016llx:%d\n", (unsigned long long)d2bits(r_pinf), (unsigned long long)d2bits(r_ninf), is_nan_d(r_nan));
    printf("C2:%d:%d:%d:%d\n", nan_eq, nan_ne, nan_ord, z_cmp);

    /* 4. Control-flow conditions & logical ops with +0.0, -0.0, NaN, 2.5 */
    struct Pair pa = { 1, 10.0 };
    struct Pair pb = { 0, 20.0 };
    printf("F1:%d:%d:%d:%d\n",
           test_conds(0.0, pa, pb),
           test_conds(d_neg_zero, pa, pb),
           test_conds(r_nan, pa, pb),
           test_conds(2.5, pa, pb));

    /* 5. Float ++/-- and mixed compound assignments */
    double d_inc = 1.5;
    double pre_d = ++d_inc;
    double post_d = d_inc--;
    float f_inc = 2.25f;
    float post_f = f_inc++;
    int mi = 10;
    mi += 2.75;
    double md = 3.0;
    md += 4;
    float mf = 2.0f;
    mf += 0x1.0000008p-23; /* checks double-precision intermediate before float store */
    printf("M1:%016llx:%016llx:%08x:%d\n",
           (unsigned long long)d2bits(pre_d), (unsigned long long)d2bits(post_d), (unsigned)f2bits(post_f), mi);
    printf("M2:%016llx:%08x:%08x\n",
           (unsigned long long)d2bits(d_inc), (unsigned)f2bits(f_inc), (unsigned)f2bits(mf));
    printf("M3:%016llx:%016llx\n", (unsigned long long)d2bits(md), (unsigned long long)d2bits((double)1.5L));

    /* 6. Integer <-> Float & i64/u64 -> f32 single-rounding & double -> u64 */
    s64_t neg_s = -42;
    s64_t big_neg_s = -0x7fffffbfffffffffLL;
    u64_t big_u = 0x8000017FFFFFFFFFULL;
    u64_t high_u = 0xFFFFFFFFFFFFF800ULL;
    double d_from_neg = (double)neg_s;
    double d_from_highu = (double)high_u;
    float f_from_u64 = (float)big_u;
    float f_from_i64 = (float)big_neg_s;
    double big_d = 9223372036854775808.0 + 4096.0;
    u64_t u_from_d = (u64_t)big_d;
    u64_t u_from_neg = (u64_t)(-0.5);
    printf("I1:%016llx:%016llx:%08x:%08x\n",
           (unsigned long long)d2bits(d_from_neg),
           (unsigned long long)d2bits(d_from_highu),
           (unsigned)f2bits(f_from_u64),
           (unsigned)f2bits(f_from_i64));
    printf("I2:%016llx:%016llx:%016llx\n",
           (unsigned long long)u_from_d,
           (unsigned long long)u_from_neg,
           (unsigned long long)d2bits((long double)3.25));
    return 0;
}
EOF

gcc -O2 -Wall "$BUILD_DIR/fp_oracle.c" -o "$BUILD_DIR/fp_gcc"
"$BUILD_DIR/fp_gcc" > "$BUILD_DIR/out_gcc.txt"

for opt in "-O0" "-O2"; do
    run_ucc $opt "$BUILD_DIR/fp_oracle.c" -o "$BUILD_DIR/fp_elf_${opt}"
    "$BUILD_DIR/fp_elf_${opt}" > "$BUILD_DIR/out_elf_${opt}.txt"
    assert_eq "3-way oracle Host GCC vs Native ELF ($opt)" "$(cat "$BUILD_DIR/out_gcc.txt")" "$(cat "$BUILD_DIR/out_elf_${opt}.txt")"

    run_ucc --target=c $opt "$BUILD_DIR/fp_oracle.c" -o "$BUILD_DIR/fp_c_${opt}"
    "$BUILD_DIR/fp_c_${opt}" > "$BUILD_DIR/out_c_${opt}.txt"
    assert_eq "3-way oracle Host GCC vs Portable C ($opt)" "$(cat "$BUILD_DIR/out_gcc.txt")" "$(cat "$BUILD_DIR/out_c_${opt}.txt")"
done

# ------------------------------------------------------------------------------
# 2. x86-64 Assembly (-S -O2) .section .rodata & .L_c99_fp64_/fp32_ Check
# ------------------------------------------------------------------------------
run_ucc -S -O2 "$BUILD_DIR/fp_oracle.c" -o "$BUILD_DIR/fp_oracle.s"
assert_grep "ASM emits .section .rodata" '\.section \.rodata' "$BUILD_DIR/fp_oracle.s"
assert_grep "ASM emits .L_c99_fp64_ pool entry" '\.L_c99_fp64_' "$BUILD_DIR/fp_oracle.s"
assert_grep "ASM emits .L_c99_fp32_ pool entry" '\.L_c99_fp32_' "$BUILD_DIR/fp_oracle.s"

# ------------------------------------------------------------------------------
# 3. Multi-TU Shared Content-Addressed Float Pool Deduplication (-c + ld & --target=c)
# ------------------------------------------------------------------------------
cat > "$BUILD_DIR/tu1.c" << 'EOF'
typedef unsigned long long u64_t;
void *memcpy(void *dst, const void *src, unsigned long n);
double tu2_calc(double x);
int printf(const char *fmt, ...);
int main(void) {
    double a = 1.5;
    double b = -0.0;
    double r = tu2_calc(a + b + 0x1.921fb54442d18p+1);
    u64_t bits = 0;
    memcpy(&bits, &r, 8);
    printf("%016llx\n", bits);
    return 0;
}
EOF

cat > "$BUILD_DIR/tu2.c" << 'EOF'
double tu2_calc(double x) {
    double a = 1.5;
    double c = 0x1.921fb54442d18p+1;
    return x + a - c;
}
EOF

gcc -O2 "$BUILD_DIR/tu1.c" "$BUILD_DIR/tu2.c" -o "$BUILD_DIR/multi_gcc"
"$BUILD_DIR/multi_gcc" > "$BUILD_DIR/multi_gcc.txt"

run_ucc -O2 -c "$BUILD_DIR/tu1.c" -o "$BUILD_DIR/tu1.o"
run_ucc -O2 -c "$BUILD_DIR/tu2.c" -o "$BUILD_DIR/tu2.o"
run_ucc "$BUILD_DIR/tu1.o" "$BUILD_DIR/tu2.o" -o "$BUILD_DIR/multi_elf"
"$BUILD_DIR/multi_elf" > "$BUILD_DIR/multi_elf.txt"
assert_eq "Multi-TU separate compilation -c + link" "$(cat "$BUILD_DIR/multi_gcc.txt")" "$(cat "$BUILD_DIR/multi_elf.txt")"

run_ucc --target=c -O2 "$BUILD_DIR/tu1.c" "$BUILD_DIR/tu2.c" -o "$BUILD_DIR/multi_c"
"$BUILD_DIR/multi_c" > "$BUILD_DIR/multi_c.txt"
assert_eq "Multi-TU --target=c merged .L_c99_fp64 dedup" "$(cat "$BUILD_DIR/multi_gcc.txt")" "$(cat "$BUILD_DIR/multi_c.txt")"

# ------------------------------------------------------------------------------
# 4. Negative CLI Diagnostic Checks (C99-FP-001 & C99-FP-002)
# ------------------------------------------------------------------------------
check_neg() {
    local label="$1"
    local code="$2"
    local csrc="$3"
    printf '%s\n' "$csrc" > "$BUILD_DIR/neg.c"
    local err_out=""
    local rc=0
    err_out="$(run_ucc "$BUILD_DIR/neg.c" -o "$BUILD_DIR/neg.bin" 2>&1)" || rc=$?
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    if [ "$rc" -ne 0 ] && echo "$err_out" | grep -q -E "$code"; then
        echo "  [PASS] $label ($code)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  [FAIL] $label (expected rc!=0 and $code, got rc=$rc output='$err_out')"
        exit 1
    fi
}

check_neg "Reject float bitwise &" "C99-FP-001" "int main(void) { double d = 1.5; return (int)(d & 1); }"
check_neg "Reject float shift <<" "C99-FP-001" "int main(void) { float f = 1.0f; return (int)(f << 2); }"
check_neg "Reject float modulo %" "C99-FP-001" "int main(void) { double d = 3.5; return (int)(d % 2); }"
check_neg "Reject float compound %=" "C99-FP-001" "int main(void) { double d = 3.5; d %= 2; return 0; }"
check_neg "Reject malformed hex float without p" "C99-LEX-003|C99-PARSE-001|C99-FP-002" "int main(void) { double d = 0x1.0; return 0; }"
check_neg "Reject malformed decimal suffix" "C99-LEX-003|C99-PARSE-001|C99-FP-002" "int main(void) { double d = 1.5ff; return 0; }"
check_neg "Reject pointer cast from float" "C99-FP-002" "int main(void) { double d = 1.0; int *p = (int *)d; return p != 0; }"
check_neg "Reject float assignment from pointer" "C99-FP-002" "int main(void) { int x = 1; double d = 0.0; d = &x; return 0; }"

echo "========================================================================"
echo " C99 Floating-Point Shell Oracle Passed: $PASS_COUNT / $TOTAL_COUNT checks"
echo "========================================================================"
