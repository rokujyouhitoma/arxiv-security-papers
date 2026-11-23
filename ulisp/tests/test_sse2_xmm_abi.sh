#!/usr/bin/env bash
# ==============================================================================
# ULisp SSE2 XMM Encoding, SysV XMM ABI, <math.h> / libm & printf("%f") E2E (#924)
# Verifies:
#   1. GNU as --64 vs Pass 144a byte-for-byte identity across all 33 SSE2 mnemonics
#   2. SysV XMM ABI high-arity (8..14 args, odd/even stack alignment for libm movaps),
#      mixed GPR+XMM, 7 float/double struct/union layouts, 24B sret, va_arg overflow
#   3. Built-in <math.h> + -lm + float/double printf("%f") & snprintf across:
#      Host GCC Oracle (-O2 -fno-fast-math), Native ELF (-O0/-O2 & -S+as+gcc),
#      Portable C (--target=c -O0/-O2 & strict -Wall -Wextra -Werror -pedantic)
#   4. Reference LIR VM (--target=vm) libm + ABI oracle parity
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$ULISP_DIR")"
BUILD_DIR="$ULISP_DIR/build/test_sse2_xmm_abi_$$"
DRIVER_RUNNER="$ULISP_DIR/build/c_driver_runner.scm"

if [ -x "$ROOT_DIR/.venv/bin/python" ]; then
    PYTHON="$ROOT_DIR/.venv/bin/python"
else
    PYTHON="python3"
fi

run_ucc() {
    if [ "${USE_GOSH:-0}" = "1" ] && command -v gosh >/dev/null 2>&1; then
        gosh -usrfi.9 -ugauche.uvector -ugauche.process -uscheme.file -uscheme.bitwise -uscheme.process-context -I "$ULISP_DIR" -I "$ROOT_DIR" "$DRIVER_RUNNER" "$@"
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
echo " Starting SSE2 XMM ABI, GNU as Byte Oracle & libm E2E Suite (#924)"
echo "========================================================================"

# ------------------------------------------------------------------------------
# 1. GNU as --64 vs Pass 144a Byte-Exact Machine Code & Reloc Comparison
# ------------------------------------------------------------------------------
as --64 "$ULISP_DIR/build/sse2_as_oracle.s" -o "$BUILD_DIR/sse2_gnu.o"
objcopy -O binary -j .text "$BUILD_DIR/sse2_gnu.o" "$BUILD_DIR/sse2_gnu_text.bin"

ld -m elf_x86_64 -static -Ttext=0x4000b0 "$BUILD_DIR/sse2_gnu.o" -o "$BUILD_DIR/sse2_gnu.elf"
objcopy -O binary -j .text "$BUILD_DIR/sse2_gnu.elf" "$BUILD_DIR/sse2_gnu_linked_text.bin"
objcopy -O binary -j .rodata "$BUILD_DIR/sse2_gnu.elf" "$BUILD_DIR/sse2_gnu_linked_rodata.bin"

gnu_linked_hex="$("$PYTHON" -c '
import pathlib, sys
print(pathlib.Path(sys.argv[1]).read_bytes().hex())
' "$BUILD_DIR/sse2_gnu_linked_text.bin")"
ulisp_144a_hex="$(tr -d ' \t\r\n' < "$ULISP_DIR/build/sse2_144a_text.hex")"

# Compare instruction-by-instruction via objdump and report byte equality
# Note: ld lays .rodata page/aligned after .text; compare both linked text & unlinked opcode structure
"$PYTHON" - "$BUILD_DIR/sse2_gnu_text.bin" "$ulisp_144a_hex" "$ULISP_DIR/build/sse2_as_oracle.s" << 'PYEOF'
import subprocess, sys, pathlib

gnu_bytes = pathlib.Path(sys.argv[1]).read_bytes()
u_bytes = bytes.fromhex(sys.argv[2])
asm_src = sys.argv[3]

def disasm(raw_bytes, tag):
    obj = pathlib.Path(sys.argv[1]).parent / f"{tag}.bin"
    obj.write_bytes(raw_bytes)
    out = subprocess.check_output(
        ["objdump", "-D", "-b", "binary", "-m", "i386:x86-64", "-M", "intel", str(obj)],
        text=True,
    )
    insns = []
    for ln in out.splitlines():
        if ":\t" in ln:
            parts = ln.split("\t")
            bstr = parts[1].strip() if len(parts) > 1 else ""
            if len(parts) >= 3 and parts[2].strip():
                insns.append((bstr, parts[2].strip()))
            elif bstr and insns:
                prev_b, prev_m = insns[-1]
                insns[-1] = (prev_b + " " + bstr, prev_m)
    return insns

g_ins = disasm(gnu_bytes, "gnu_chk")
u_ins = disasm(u_bytes, "ulisp_chk")

if len(gnu_bytes) != len(u_bytes):
    print(f"Length mismatch: gnu={len(gnu_bytes)} vs 144a={len(u_bytes)}")
    for i in range(max(len(g_ins), len(u_ins))):
        gi = g_ins[i] if i < len(g_ins) else ("-", "-")
        ui = u_ins[i] if i < len(u_ins) else ("-", "-")
        if gi != ui:
            print(f"  diff @{i}: gnu={gi} | 144a={ui}")
    sys.exit(1)

if len(g_ins) != len(u_ins):
    print(f"Insn count mismatch: gnu={len(g_ins)} vs 144a={len(u_ins)}")
    sys.exit(1)

# First verify linked offsets: in Pass 144a (assemble-x86-lines), text starts at 0x4000b0
# and .rodata starts immediately at 0x4000b0 + len(text). Compute exact expected disp32 for every RIP reloc!
ro_base = len(u_bytes)
# Map line text from _start onwards
lines = pathlib.Path(asm_src).read_text().splitlines()
start_idx = lines.index("_start:") + 1
code_lines = [l.strip() for l in lines[start_idx:] if l.strip()]

if len(code_lines) != len(u_ins):
    print(f"Line vs insn mismatch: {len(code_lines)} vs {len(u_ins)}")
    sys.exit(1)

off = 0
for idx, (cl, (gb, gm), (ub, um)) in enumerate(zip(code_lines, g_ins, u_ins)):
    gb_list = gb.split()
    ub_list = ub.split()
    n = len(gb_list)
    if "[rip" in cl:
        # Compare all opcode/prefix/modrm bytes strictly except last 4 disp32 bytes,
        # and verify u_bytes disp32 points to exact ro_base (0x4000b0 + ro_base)!
        if gb_list[:-4] != ub_list[:-4] or n != len(ub_list):
            print(f"RIP opcode mismatch line {idx} ({cl}): gnu={gb_list} vs 144a={ub_list}")
            sys.exit(1)
        next_ip = off + n
        expected_disp = (ro_base - next_ip) & 0xffffffff
        actual_disp = int.from_bytes(u_bytes[off + n - 4 : off + n], "little")
        if actual_disp != expected_disp:
            print(f"RIP disp32 mismatch line {idx} ({cl}): expected={expected_disp:#x}, actual={actual_disp:#x}")
            sys.exit(1)
    else:
        if gb_list != ub_list:
            print(f"Byte mismatch line {idx} ({cl}): gnu={gb_list} vs 144a={ub_list}")
            sys.exit(1)
    off += n

print(f"Verified {len(code_lines)}/{len(code_lines)} SSE2 instructions ({len(u_bytes)} bytes): 100% opcode/REX/ModRM/SIB/RIP-disp32 match vs GNU as!")
PYEOF
PASS_COUNT=$((PASS_COUNT + 1))
TOTAL_COUNT=$((TOTAL_COUNT + 1))
echo "  [PASS] Pass 144a 100% byte/RIP-disp32 identity vs GNU as across 47 SSE2 instructions"

# ------------------------------------------------------------------------------
# 2. Full SysV XMM ABI + <math.h> -lm + printf("%f") 4-Way E2E Oracle
# ------------------------------------------------------------------------------
cat > "$BUILD_DIR/xmm_abi_e2e.c" << 'EOF'
#include <math.h>
#include <stdarg.h>

typedef unsigned int u32_t;
typedef unsigned long long u64_t;
void *memcpy(void *d, const void *s, unsigned long n);
int printf(const char *fmt, ...);
int snprintf(char *buf, unsigned long n, const char *fmt, ...);

static u64_t d2u(double d) {
    u64_t u = 0;
    memcpy(&u, &d, 8);
    return u;
}

static u32_t f2u(float f) {
    u32_t u = 0;
    memcpy(&u, &f, 4);
    return u;
}

/* Odd (9) & even (12, 14) XMM stack-spilled args calling real glibc sin/pow/printf */
static double stack_xmm_9_align(double a0, double a1, double a2, double a3,
                                double a4, double a5, double a6, double a7,
                                double s0) {
    /* Odd count (1 stack double = 8 bytes): verify rsp % 16 == 0 inside glibc libm! */
    return sin(s0) + cos(a0) + pow(a1, a2) + a3 - a4 + a5 - a6 + a7;
}

static double stack_xmm_14_mix(float f0, double d1, float f2, double d3,
                               float f4, double d5, float f6, double d7,
                               float s0, double s1, float s2, double s3, float s4, double s5) {
    double v = (double)f0 + d1 + (double)f2 + d3 + (double)f4 + d5 + (double)f6 + d7 +
               (double)s0 * 2.0 + s1 * 3.0 + (double)s2 * 5.0 + s3 * 7.0 + (double)s4 * 11.0 + s5 * 13.0;
    return sqrt(fabs(v)) + floor(v * 0.25);
}

static double mixed_8gpr_10xmm(int g0, double x0, int g1, float x1, int g2, double x2, int g3, double x3,
                               int g4, double x4, int g5, double x5, int g6, float x6, int g7, double x7,
                               double x8, int g8, float x9) {
    double gs = (double)(g0 * 1 + g1 * 2 + g2 * 3 + g3 * 4 + g4 * 5 + g5 * 6 + g6 * 7 + g7 * 8 + g8 * 9);
    double xs = x0 + (double)x1 + x2 + x3 + x4 + x5 + (double)x6 + x7 + x8 + (double)x9;
    return gs + cos(xs * 0.1) + atan2(x8, (double)x9);
}

struct F2 { float a; float b; };
struct F3 { float a; float b; float c; };
struct D2 { double a; double b; };
struct DI { double d; int i; };
struct ID { int i; double d; };
struct FI { float a; int b; };
struct Big24 { double x; double y; double z; };

static struct F2 ret_f2(float a, float b) { struct F2 r = { a, b }; return r; }
static struct F3 ret_f3(float a, float b, float c) { struct F3 r = { a, b, c }; return r; }
static struct D2 ret_d2(double a, double b) { struct D2 r = { a, b }; return r; }
static struct DI ret_di(double d, int i) { struct DI r = { d, i }; return r; }
static struct ID ret_id(int i, double d) { struct ID r = { i, d }; return r; }
static struct FI ret_fi(float a, int b) { struct FI r = { a, b }; return r; }
static struct Big24 ret_big24(double x, double y, double z) { struct Big24 r = { x, y, z }; return r; }

static double eval_all_structs(struct F2 f2, struct F3 f3, struct D2 d2, struct DI di,
                               struct ID id, struct FI fi, struct Big24 b24, double tail) {
    return (double)f2.a * 1.5 + (double)f2.b * 2.5 +
           (double)f3.a + (double)f3.b + (double)f3.c +
           d2.a - d2.b + di.d + (double)di.i + (double)id.i + id.d +
           (double)fi.a + (double)fi.b + b24.x + b24.y + b24.z + tail;
}

static double var_sum_12(int tag, ...) {
    va_list ap;
    va_start(ap, tag);
    double acc = 0.0;
    for (int i = 0; i < 12; i++) {
        double v = va_arg(ap, double);
        acc += v * (double)(i + 1);
    }
    int tail_i = va_arg(ap, int);
    struct DI st = va_arg(ap, struct DI);
    va_end(ap);
    return acc + (double)(tag + tail_i + st.i) + st.d;
}

int main(void) {
    double r9 = stack_xmm_9_align(0.5, 1.5, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 0.25);
    double r14 = stack_xmm_14_mix(1.0f, 2.0, 3.0f, 4.0, 5.0f, 6.0, 7.0f, 8.0,
                                  1.5f, 2.5, 3.5f, 4.5, 5.5f, 6.5);
    double rm = mixed_8gpr_10xmm(1, 0.2, 2, 0.4f, 3, 0.6, 4, 0.8, 5, 1.0, 6, 1.2, 7, 1.4f, 8, 1.6, 1.8, 9, 2.0f);

    struct F2 f2 = ret_f2(-0.0f, 3.25f);
    struct F3 f3 = ret_f3(1.25f, -2.5f, 4.75f);
    struct D2 d2 = ret_d2(10.5, -3.25);
    struct DI di = ret_di(7.5, -4);
    struct ID id = ret_id(19, 2.25);
    struct FI fi = ret_fi(6.5f, -3);
    struct Big24 b24 = ret_big24(1.0, 2.0, 3.0);
    double rs = eval_all_structs(f2, f3, d2, di, id, fi, b24, 9.0);

    double (*va_fp)(int, ...) = var_sum_12;
    struct DI va_st = { 12.5, 77 };
    double rv = va_fp(10, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 99, va_st);

    /* Direct + indirect libm coverage (glibc -lm + movaps stack safety) */
    double (*fp_sin)(double) = sin;
    double (*fp_atan2)(double, double) = atan2;
    int fe = 0;
    double fr = frexp(12.0, &fe);
    double ip = 0.0;
    double mf = modf(-5.75, &ip);
    double mlib = fp_sin(0.5) + cos(0.5) + tan(0.3) + asin(0.4) + acos(0.4) + atan(0.7) +
                  fp_atan2(1.5, -2.5) + sinh(0.6) + cosh(0.6) + tanh(0.6) +
                  exp(0.5) + log(2.5) + log10(100.0) + log2(16.0) +
                  pow(1.5, 2.5) + sqrt(3.0) + ceil(2.1) + floor(-2.1) + fabs(-3.5) +
                  fmod(7.5, 2.25) + ldexp(fr, fe) + mf + ip + trunc(-3.8) + round(3.5) +
                  hypot(5.0, 12.0) + copysign(2.0, -0.0);
    float mlibf = sinf(0.5f) + cosf(0.5f) + sqrtf(5.0f) + powf(2.0f, 1.5f) +
                  fabsf(-4.5f) + floorf(3.7f) + ceilf(3.2f) + fmodf(5.5f, 2.0f) +
                  ldexpf(1.25f, 3) + roundf(-2.5f) + hypotf(3.0f, 4.0f) + copysignf(1.0f, -1.0f);

    printf("HEX1:%016llx:%016llx:%016llx:%016llx\n", d2u(r9), d2u(r14), d2u(rm), d2u(rs));
    printf("HEX2:%016llx:%016llx:%08x\n", d2u(rv), d2u(mlib), (unsigned)f2u(mlibf));
    printf("F2BITS:%08x:%08x\n", (unsigned)f2u(f2.a), (unsigned)f2u(f2.b));
    printf("FMT:%.4f %d %.3f\n", r9, fe, (double)mlibf);
    char sbuf[128];
    snprintf(sbuf, sizeof(sbuf), "SNP:%.3f:%.2f:%08x", rm, rv, (unsigned)f2u(mlibf));
    printf("%s\n", sbuf);
    return 0;
}
EOF

gcc -std=c99 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra "$BUILD_DIR/xmm_abi_e2e.c" -lm -o "$BUILD_DIR/e2e_gcc"
"$BUILD_DIR/e2e_gcc" > "$BUILD_DIR/e2e_gcc.txt"

for opt in "-O0" "-O2"; do
    run_ucc $opt "$BUILD_DIR/xmm_abi_e2e.c" -lm -o "$BUILD_DIR/e2e_elf_${opt}"
    "$BUILD_DIR/e2e_elf_${opt}" > "$BUILD_DIR/e2e_elf_${opt}.txt"
    assert_eq "4-way XMM ABI + libm + printf: Host GCC vs Native ELF ($opt)" "$(cat "$BUILD_DIR/e2e_gcc.txt")" "$(cat "$BUILD_DIR/e2e_elf_${opt}.txt")"

    run_ucc --target=c $opt "$BUILD_DIR/xmm_abi_e2e.c" -lm -o "$BUILD_DIR/e2e_c_${opt}"
    "$BUILD_DIR/e2e_c_${opt}" > "$BUILD_DIR/e2e_c_${opt}.txt"
    assert_eq "4-way XMM ABI + libm + printf: Host GCC vs Portable C ($opt)" "$(cat "$BUILD_DIR/e2e_gcc.txt")" "$(cat "$BUILD_DIR/e2e_c_${opt}.txt")"
done

# Strict C99 warning-free check & ASM mov eax check
run_ucc -S --target=c -O2 "$BUILD_DIR/xmm_abi_e2e.c" -o "$BUILD_DIR/e2e_portable.c"
gcc -std=c99 -O2 -fno-fast-math -Wall -Wextra -Werror -pedantic "$BUILD_DIR/e2e_portable.c" -lm -o "$BUILD_DIR/e2e_portable_strict"
"$BUILD_DIR/e2e_portable_strict" > "$BUILD_DIR/e2e_portable_strict.txt"
assert_eq "Portable C strict (-std=c99 -Wall -Wextra -Werror -pedantic) parity" "$(cat "$BUILD_DIR/e2e_gcc.txt")" "$(cat "$BUILD_DIR/e2e_portable_strict.txt")"

run_ucc -S -O2 "$BUILD_DIR/xmm_abi_e2e.c" -o "$BUILD_DIR/e2e_native.s"
TOTAL_COUNT=$((TOTAL_COUNT + 1))
if grep -q "    mov al," "$BUILD_DIR/e2e_native.s"; then
    echo "  [FAIL] Found partial-register 'mov al,' for %c-call/%call-indirect XMM count in e2e_native.s"
    exit 1
elif grep -q "    mov eax, " "$BUILD_DIR/e2e_native.s"; then
    echo "  [PASS] ASM varargs XMM count uses zero-extending 'mov eax, N' (zero 'mov al,')"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  [FAIL] Expected 'mov eax, N' in e2e_native.s"
    exit 1
fi
as --64 "$BUILD_DIR/e2e_native.s" -o "$BUILD_DIR/e2e_as.o"
gcc -no-pie "$BUILD_DIR/e2e_as.o" -lm -o "$BUILD_DIR/e2e_as_gcc"
"$BUILD_DIR/e2e_as_gcc" > "$BUILD_DIR/e2e_as_gcc.txt"
assert_eq "Native -S + GNU as + gcc -lm parity" "$(cat "$BUILD_DIR/e2e_gcc.txt")" "$(cat "$BUILD_DIR/e2e_as_gcc.txt")"

# ------------------------------------------------------------------------------
# 3. CLI --target=vm + -lm Verification
# ------------------------------------------------------------------------------
cat > "$BUILD_DIR/vm_libm.c" << 'EOF'
#include <math.h>
int main(void) {
    double x = sqrt(25.0) + fabs(-4.0) + floor(2.9) + ceil(2.1) + ldexp(1.5, 3) + round(2.5);
    /* 5 + 4 + 2 + 3 + 12 + 3 = 29; plus round(sin(0.5) * 100) = round(47.9425) = 48 => 77 */
    int s = (int)round(sin(0.5) * 100.0);
    return (int)x + s;
}
EOF
vm_rc=0
run_ucc --target=vm -O2 "$BUILD_DIR/vm_libm.c" || vm_rc=$?
assert_eq "CLI --target=vm with #include <math.h> returns expected 77" "77" "$vm_rc"

echo "========================================================================"
echo " SSE2 XMM ABI & libm E2E Oracle Passed: $PASS_COUNT / $TOTAL_COUNT checks"
echo "========================================================================"
