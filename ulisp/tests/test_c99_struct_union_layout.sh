#!/usr/bin/env bash
# ==============================================================================
# ULisp C99 Struct/Union/Bitfield Layout & Host GCC Bidirectional ABI Suite (#918)
# Verifies:
#   1. Host GCC Layout Oracle: sizeof, _Alignof, __builtin_offsetof across 21
#      composite shapes (Empty, bitfields, :0, straddling, anon, FAM, union)
#   2. Host GCC <-> ULisp Native ELF Bidirectional SysV AMD64 ABI Cross-Linking:
#      - Empty (0B), ThreeB (3B), SmallF (4B SSE), TwoF (8B SSE), IntFloat (8B GPR),
#        ThreeF (12B SSE+SSE), PairL (16B GPR+GPR), LongDouble (16B GPR+SSE),
#        TwoD (16B SSE+SSE)
#      - All-or-nothing stack spill (5 GPRs + 16B struct -> stack, 7th arg in r9)
#      - MEMORY (>16B) hidden sret pointer in rdi & rax return + stack argument
#      - Shared extern .data / .bss structs with pointer relocations
#   3. Multi-TU Portable C (--target=c) equivalence
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$ULISP_DIR")"
BUILD_DIR="$ULISP_DIR/build/test_c99_layout_$$"
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

echo "========================================================================"
echo " Starting C99 Host GCC Layout Oracle & Bidirectional SysV ABI Suite (#918)"
echo "========================================================================"

# ------------------------------------------------------------------------------
# 1. Host GCC Layout Oracle (sizeof / _Alignof / __builtin_offsetof)
# ------------------------------------------------------------------------------
cat > "$BUILD_DIR/oracle_layout.c" << 'EOF'
int printf(const char *fmt, ...);

struct Empty {};
struct ZeroBF  { char a; int : 0; char b; };
struct ZeroBF2 { char a; int : 3; char b; };
struct ZeroBF3 { char a; long : 0; char b; };
struct ZeroBF4 { int a:4; int : 0; char b; };
struct NamedBF { unsigned a:4; int b:5; unsigned c:24; };
struct MixedBF  { unsigned char a:5; unsigned int b:5; };
struct MixedBF2 { unsigned char a:5; unsigned short b:5; };
struct MixedBF3 { unsigned char a:5; unsigned int b:10; };
struct MixedBF4 { unsigned short a:12; unsigned int b:24; };
struct LongBF  { unsigned long a:40; unsigned long b:30; };
struct LongBF2 { char x; unsigned long a:40; char y; };
struct LongBF3 { unsigned a:4; int : 3; unsigned b:4; };
struct LongBF4 { char a; short : 4; char b; };
struct AnonSU  { int tag; union { long iv; struct { short lo; short hi; }; }; };
struct FAM     { int len; int data[]; };
struct FAM2    { char tag; double data[]; };
union  UnionBF { unsigned a:12; int b:20; char c; };
struct TailBF  { int a; char b:3; };
struct TailBF2 { long a; char b:3; };
struct PackedCheck { unsigned a:1; unsigned b:31; unsigned c:1; };

int main(void) {
    printf("Empty:%lu,%lu\n", (unsigned long)sizeof(struct Empty), (unsigned long)_Alignof(struct Empty));
    printf("ZeroBF:%lu,%lu,%lu\n", (unsigned long)sizeof(struct ZeroBF), (unsigned long)_Alignof(struct ZeroBF), (unsigned long)__builtin_offsetof(struct ZeroBF, b));
    printf("ZeroBF2:%lu,%lu,%lu\n", (unsigned long)sizeof(struct ZeroBF2), (unsigned long)_Alignof(struct ZeroBF2), (unsigned long)__builtin_offsetof(struct ZeroBF2, b));
    printf("ZeroBF3:%lu,%lu,%lu\n", (unsigned long)sizeof(struct ZeroBF3), (unsigned long)_Alignof(struct ZeroBF3), (unsigned long)__builtin_offsetof(struct ZeroBF3, b));
    printf("ZeroBF4:%lu,%lu,%lu\n", (unsigned long)sizeof(struct ZeroBF4), (unsigned long)_Alignof(struct ZeroBF4), (unsigned long)__builtin_offsetof(struct ZeroBF4, b));
    printf("NamedBF:%lu,%lu\n", (unsigned long)sizeof(struct NamedBF), (unsigned long)_Alignof(struct NamedBF));
    printf("MixedBF:%lu,%lu\n", (unsigned long)sizeof(struct MixedBF), (unsigned long)_Alignof(struct MixedBF));
    printf("MixedBF2:%lu,%lu\n", (unsigned long)sizeof(struct MixedBF2), (unsigned long)_Alignof(struct MixedBF2));
    printf("MixedBF3:%lu,%lu\n", (unsigned long)sizeof(struct MixedBF3), (unsigned long)_Alignof(struct MixedBF3));
    printf("MixedBF4:%lu,%lu\n", (unsigned long)sizeof(struct MixedBF4), (unsigned long)_Alignof(struct MixedBF4));
    printf("LongBF:%lu,%lu\n", (unsigned long)sizeof(struct LongBF), (unsigned long)_Alignof(struct LongBF));
    printf("LongBF2:%lu,%lu,%lu\n", (unsigned long)sizeof(struct LongBF2), (unsigned long)_Alignof(struct LongBF2), (unsigned long)__builtin_offsetof(struct LongBF2, y));
    printf("LongBF3:%lu,%lu\n", (unsigned long)sizeof(struct LongBF3), (unsigned long)_Alignof(struct LongBF3));
    printf("LongBF4:%lu,%lu,%lu\n", (unsigned long)sizeof(struct LongBF4), (unsigned long)_Alignof(struct LongBF4), (unsigned long)__builtin_offsetof(struct LongBF4, b));
    printf("AnonSU:%lu,%lu,%lu,%lu,%lu\n",
           (unsigned long)sizeof(struct AnonSU),
           (unsigned long)_Alignof(struct AnonSU),
           (unsigned long)__builtin_offsetof(struct AnonSU, iv),
           (unsigned long)__builtin_offsetof(struct AnonSU, lo),
           (unsigned long)__builtin_offsetof(struct AnonSU, hi));
    printf("FAM:%lu,%lu,%lu\n", (unsigned long)sizeof(struct FAM), (unsigned long)_Alignof(struct FAM), (unsigned long)__builtin_offsetof(struct FAM, data));
    printf("FAM2:%lu,%lu,%lu\n", (unsigned long)sizeof(struct FAM2), (unsigned long)_Alignof(struct FAM2), (unsigned long)__builtin_offsetof(struct FAM2, data));
    printf("UnionBF:%lu,%lu\n", (unsigned long)sizeof(union UnionBF), (unsigned long)_Alignof(union UnionBF));
    printf("TailBF:%lu,%lu\n", (unsigned long)sizeof(struct TailBF), (unsigned long)_Alignof(struct TailBF));
    printf("TailBF2:%lu,%lu\n", (unsigned long)sizeof(struct TailBF2), (unsigned long)_Alignof(struct TailBF2));
    printf("PackedCheck:%lu,%lu\n", (unsigned long)sizeof(struct PackedCheck), (unsigned long)_Alignof(struct PackedCheck));
    return 0;
}
EOF

gcc -std=gnu99 -O2 "$BUILD_DIR/oracle_layout.c" -o "$BUILD_DIR/oracle_gcc"
run_ucc "$BUILD_DIR/oracle_layout.c" -o "$BUILD_DIR/oracle_ulisp_elf"
run_ucc --target=c "$BUILD_DIR/oracle_layout.c" -o "$BUILD_DIR/oracle_ulisp_c"

out_oracle_gcc=$("$BUILD_DIR/oracle_gcc")
out_oracle_elf=$("$BUILD_DIR/oracle_ulisp_elf")
out_oracle_c=$("$BUILD_DIR/oracle_ulisp_c")

assert_eq "1.1 ULisp Native ELF layout matches Host GCC oracle 100%" "$out_oracle_gcc" "$out_oracle_elf"
assert_eq "1.2 ULisp Portable C layout matches Host GCC oracle 100%" "$out_oracle_gcc" "$out_oracle_c"

# ------------------------------------------------------------------------------
# 2. Host GCC <-> ULisp Native ELF Bidirectional SysV AMD64 ABI Cross-Linking
# ------------------------------------------------------------------------------
cat > "$BUILD_DIR/abi_shared.h" << 'EOF'
struct Empty {};
struct ThreeB { unsigned char a; unsigned char b; unsigned char c; };
struct SmallF { float f; };
struct TwoF   { float x; float y; };
struct IntFloat { int i; float f; };
struct ThreeF { float x; float y; float z; };
struct PairL  { long x; long y; };
struct LongDouble { long a; double d; };
struct TwoD   { double a; double b; };
struct Big24  { long a; long b; long c; };
struct Big40  { long a; long b; long c; long d; long e; };

struct SharedGlobal {
    int magic;
    int *ptr;
    struct PairL pair;
};

extern int g_shared_target;
extern struct SharedGlobal g_shared_data;
extern struct SharedGlobal g_shared_bss;

/* Defined in abi_gcc.c, called from abi_ulisp.c */
int gcc_take_empty(struct Empty e, int x);
struct ThreeB gcc_step_3b(struct ThreeB s);
struct SmallF gcc_scale_smallf(struct SmallF s, float k);
struct TwoF gcc_add_twof(struct TwoF a, struct TwoF b);
struct IntFloat gcc_step_intfloat(struct IntFloat s);
struct ThreeF gcc_step_threef(struct ThreeF s);
struct PairL gcc_swap_pairl(struct PairL p);
struct LongDouble gcc_step_longdouble(struct LongDouble s);
struct TwoD gcc_step_twod(struct TwoD s);
long gcc_check_spill(long a, long b, long c, long d, long e, struct PairL p, long z);
struct Big24 gcc_make_big24(long a, long b, long c);
long gcc_consume_big40(int factor, struct Big40 b, int tail);

/* Defined in abi_ulisp.c, called from abi_gcc.c */
int ulisp_take_empty(struct Empty e, int x);
struct ThreeB ulisp_step_3b(struct ThreeB s);
struct SmallF ulisp_scale_smallf(struct SmallF s, float k);
struct TwoF ulisp_add_twof(struct TwoF a, struct TwoF b);
struct IntFloat ulisp_step_intfloat(struct IntFloat s);
struct ThreeF ulisp_step_threef(struct ThreeF s);
struct PairL ulisp_swap_pairl(struct PairL p);
struct LongDouble ulisp_step_longdouble(struct LongDouble s);
struct TwoD ulisp_step_twod(struct TwoD s);
long ulisp_check_spill(long a, long b, long c, long d, long e, struct PairL p, long z);
struct Big24 ulisp_make_big24(long a, long b, long c);
long ulisp_consume_big40(int factor, struct Big40 b, int tail);
int ulisp_verify_from_ulisp_side(void);
EOF

cat > "$BUILD_DIR/abi_ulisp.c" << 'EOF'
#include "abi_shared.h"

int g_shared_target = 77;
struct SharedGlobal g_shared_data = {
    .magic = 123,
    .ptr = &g_shared_target,
    .pair = { .x = 10, .y = 20 }
};
struct SharedGlobal g_shared_bss;

int ulisp_take_empty(struct Empty e, int x) {
    return x + 5;
}

struct ThreeB ulisp_step_3b(struct ThreeB s) {
    struct ThreeB r = { s.a + 1, s.b + 2, s.c + 3 };
    return r;
}

struct SmallF ulisp_scale_smallf(struct SmallF s, float k) {
    struct SmallF r = { s.f * k };
    return r;
}

struct TwoF ulisp_add_twof(struct TwoF a, struct TwoF b) {
    struct TwoF r = { a.x + b.x, a.y + b.y };
    return r;
}

struct IntFloat ulisp_step_intfloat(struct IntFloat s) {
    struct IntFloat r = { s.i + 10, s.f + 2.5f };
    return r;
}

struct ThreeF ulisp_step_threef(struct ThreeF s) {
    struct ThreeF r = { s.x + 1.0f, s.y + 2.0f, s.z + 3.0f };
    return r;
}

struct PairL ulisp_swap_pairl(struct PairL p) {
    struct PairL r = { p.y + 1, p.x + 2 };
    return r;
}

struct LongDouble ulisp_step_longdouble(struct LongDouble s) {
    struct LongDouble r = { s.a + 100, s.d * 2.0 };
    return r;
}

struct TwoD ulisp_step_twod(struct TwoD s) {
    struct TwoD r = { s.a + 1.5, s.b + 2.5 };
    return r;
}

long ulisp_check_spill(long a, long b, long c, long d, long e, struct PairL p, long z) {
    return a + b + c + d + e + (p.x * 10) + p.y + (z * 100);
}

struct Big24 ulisp_make_big24(long a, long b, long c) {
    struct Big24 r = { a + 1, b + 2, c + 3 };
    return r;
}

long ulisp_consume_big40(int factor, struct Big40 b, int tail) {
    return (long)factor * (b.a + b.b + b.c + b.d + b.e) + (long)tail;
}

int ulisp_verify_from_ulisp_side(void) {
    struct Empty e = {};
    if (gcc_take_empty(e, 10) != 17) return 101;

    struct ThreeB tb = { 3, 4, 5 };
    struct ThreeB tb2 = gcc_step_3b(tb);
    if (tb2.a != 13 || tb2.b != 24 || tb2.c != 35) return 102;

    struct SmallF sf = { 3.5f };
    struct SmallF sf2 = gcc_scale_smallf(sf, 4.0f);
    if ((int)sf2.f != 14) return 103;

    struct TwoF tf1 = { 1.5f, 2.5f };
    struct TwoF tf2 = { 3.5f, 4.5f };
    struct TwoF tf3 = gcc_add_twof(tf1, tf2);
    if ((int)tf3.x != 5 || (int)tf3.y != 7) return 104;

    struct IntFloat inf0 = { 22, 1.25f };
    struct IntFloat inf1 = gcc_step_intfloat(inf0);
    if (inf1.i != 25 || (int)(inf1.f * 4.0f) != 15) return 105;

    struct ThreeF th0 = { 1.0f, 2.0f, 3.0f };
    struct ThreeF th1 = gcc_step_threef(th0);
    if ((int)(th1.x + th1.y + th1.z) != 36) return 106;

    struct PairL pl0 = { 40, 50 };
    struct PairL pl1 = gcc_swap_pairl(pl0);
    if (pl1.x != 55 || pl1.y != 46) return 107;

    struct LongDouble ld0 = { 7, 3.25 };
    struct LongDouble ld1 = gcc_step_longdouble(ld0);
    if (ld1.a != 14 || (int)(ld1.d * 4.0) != 29) return 108;

    struct TwoD td0 = { 10.25, 20.75 };
    struct TwoD td1 = gcc_step_twod(td0);
    if ((int)(td1.a + td1.b) != 41) return 109;

    struct PairL sp = { 8, 9 };
    if (gcc_check_spill(1, 2, 3, 4, 5, sp, 6) != 704) return 110;

    struct Big24 b24 = gcc_make_big24(10, 20, 30);
    if (b24.a != 100 || b24.b != 200 || b24.c != 300) return 111;

    struct Big40 b40 = { 1, 2, 3, 4, 5 };
    if (gcc_consume_big40(3, b40, 7) != 52) return 112;

    return 0;
}
EOF

cat > "$BUILD_DIR/abi_gcc.c" << 'EOF'
#include "abi_shared.h"

int printf(const char *fmt, ...);

int gcc_take_empty(struct Empty e, int x) {
    (void)e;
    return x + 7;
}

struct ThreeB gcc_step_3b(struct ThreeB s) {
    struct ThreeB r = { (unsigned char)(s.a + 10), (unsigned char)(s.b + 20), (unsigned char)(s.c + 30) };
    return r;
}

struct SmallF gcc_scale_smallf(struct SmallF s, float k) {
    struct SmallF r = { s.f * k };
    return r;
}

struct TwoF gcc_add_twof(struct TwoF a, struct TwoF b) {
    struct TwoF r = { a.x + b.x, a.y + b.y };
    return r;
}

struct IntFloat gcc_step_intfloat(struct IntFloat s) {
    struct IntFloat r = { s.i + 3, s.f + 2.5f };
    return r;
}

struct ThreeF gcc_step_threef(struct ThreeF s) {
    struct ThreeF r = { s.x + 10.0f, s.y + 10.0f, s.z + 10.0f };
    return r;
}

struct PairL gcc_swap_pairl(struct PairL p) {
    struct PairL r = { p.y + 5, p.x + 6 };
    return r;
}

struct LongDouble gcc_step_longdouble(struct LongDouble s) {
    struct LongDouble r = { s.a * 2, s.d + 4.0 };
    return r;
}

struct TwoD gcc_step_twod(struct TwoD s) {
    struct TwoD r = { s.a + 5.0, s.b + 5.0 };
    return r;
}

long gcc_check_spill(long a, long b, long c, long d, long e, struct PairL p, long z) {
    return a + b + c + d + e + (p.x * 10) + p.y + (z * 100);
}

struct Big24 gcc_make_big24(long a, long b, long c) {
    struct Big24 r = { a * 10, b * 10, c * 10 };
    return r;
}

long gcc_consume_big40(int factor, struct Big40 b, int tail) {
    return (long)factor * (b.a + b.b + b.c + b.d + b.e) + (long)tail;
}

int main(void) {
    /* 1. Verify shared extern .data and .bss globals emitted by ULisp */
    if (g_shared_data.magic != 123 || *(g_shared_data.ptr) != 77 ||
        g_shared_data.pair.x != 10 || g_shared_data.pair.y != 20) {
        return 1;
    }
    if (g_shared_bss.magic != 0 || g_shared_bss.ptr != 0 ||
        g_shared_bss.pair.x != 0 || g_shared_bss.pair.y != 0) {
        return 2;
    }

    /* 2. Host GCC calling ULisp functions across all SysV aggregate classes */
    struct Empty e = {};
    if (ulisp_take_empty(e, 20) != 25) return 3;

    struct ThreeB tb = { 1, 2, 3 };
    struct ThreeB tb2 = ulisp_step_3b(tb);
    if (tb2.a != 2 || tb2.b != 4 || tb2.c != 6) return 4;

    struct SmallF sf = { 2.5f };
    struct SmallF sf2 = ulisp_scale_smallf(sf, 6.0f);
    if ((int)sf2.f != 15) return 5;

    struct TwoF tf1 = { 10.5f, 20.25f };
    struct TwoF tf2 = { 1.5f, 2.75f };
    struct TwoF tf3 = ulisp_add_twof(tf1, tf2);
    if ((int)tf3.x != 12 || (int)tf3.y != 23) return 6;

    struct IntFloat inf0 = { 5, 1.5f };
    struct IntFloat inf1 = ulisp_step_intfloat(inf0);
    if (inf1.i != 15 || (int)inf1.f != 4) return 7;

    struct ThreeF th0 = { 2.0f, 3.0f, 4.0f };
    struct ThreeF th1 = ulisp_step_threef(th0);
    if ((int)(th1.x + th1.y + th1.z) != 15) return 8;

    struct PairL pl0 = { 10, 20 };
    struct PairL pl1 = ulisp_swap_pairl(pl0);
    if (pl1.x != 21 || pl1.y != 12) return 9;

    struct LongDouble ld0 = { 23, 4.5 };
    struct LongDouble ld1 = ulisp_step_longdouble(ld0);
    if (ld1.a != 123 || (int)ld1.d != 9) return 10;

    struct TwoD td0 = { 3.5, 7.5 };
    struct TwoD td1 = ulisp_step_twod(td0);
    if ((int)(td1.a + td1.b) != 15) return 11;

    struct PairL sp = { 4, 5 };
    if (ulisp_check_spill(1, 2, 3, 4, 5, sp, 7) != 760) return 12;

    struct Big24 b24 = ulisp_make_big24(10, 20, 30);
    if (b24.a != 11 || b24.b != 22 || b24.c != 33) return 13;

    struct Big40 b40 = { 2, 4, 6, 8, 10 };
    if (ulisp_consume_big40(2, b40, 9) != 69) return 14;

    /* 3. ULisp calling Host GCC functions across all SysV aggregate classes */
    int rc = ulisp_verify_from_ulisp_side();
    if (rc != 0) return rc;

    printf("BIDIRECTIONAL_SYSV_ABI_OK\n");
    return 0;
}
EOF

run_ucc -c -I "$BUILD_DIR" "$BUILD_DIR/abi_ulisp.c" -o "$BUILD_DIR/abi_ulisp.o"
gcc -std=gnu99 -O2 -c -I "$BUILD_DIR" "$BUILD_DIR/abi_gcc.c" -o "$BUILD_DIR/abi_gcc.o"
gcc -no-pie "$BUILD_DIR/abi_ulisp.o" "$BUILD_DIR/abi_gcc.o" -o "$BUILD_DIR/abi_cross_bin"

out_cross=$("$BUILD_DIR/abi_cross_bin")
assert_eq "2.1 Host GCC <-> ULisp Native ELF bidirectional SysV ABI cross-link" "BIDIRECTIONAL_SYSV_ABI_OK" "$out_cross"

# ------------------------------------------------------------------------------
# 3. Multi-TU Portable C (--target=c) Equivalence
# ------------------------------------------------------------------------------
run_ucc --target=c -I "$BUILD_DIR" "$BUILD_DIR/abi_ulisp.c" "$BUILD_DIR/abi_gcc.c" -o "$BUILD_DIR/abi_portable_c_bin"
out_portable_c=$("$BUILD_DIR/abi_portable_c_bin")
assert_eq "3.1 Multi-TU Portable C (--target=c) matches native ELF cross-link" "BIDIRECTIONAL_SYSV_ABI_OK" "$out_portable_c"

echo "========================================================================"
echo " C99 Host GCC Layout Oracle & SysV ABI Suite (#918): $PASS_COUNT / $TOTAL_COUNT PASS"
echo "========================================================================"
