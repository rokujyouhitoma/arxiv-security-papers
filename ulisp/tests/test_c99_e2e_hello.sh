#!/usr/bin/env bash
# ==============================================================================
# ULisp C99 Compiler Driver E2E Verification Suite (Issue #917)
# Verifies:
#   - printf("%d\n", 42) & exit code linking against host libc
#   - 3-way equivalence: Pass 140/144a Native ELF vs Pass 160 Portable C (--target=c)
#   - Split compilation (-c -> ET_REL .o -> host ld/cc link)
#   - -E (CPP), -S (x86-64 .s / Portable C), -I, -isystem, -D, -U, -O1/-O2
#   - Narrow signed/unsigned widths (signed char, unsigned short, int, long)
#   - Host linker error diagnostic C99-DRV-003
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$ULISP_DIR")"
BUILD_DIR="$ULISP_DIR/build/test_c99_e2e_$$"
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

run_scheme_script() {
    if [ "${USE_GOSH:-0}" = "1" ] && command -v gosh >/dev/null 2>&1; then
        gosh -ugauche.uvector -ugauche.process -uscheme.file -uscheme.bitwise -uscheme.process-context -I "$ULISP_DIR" -I "$ROOT_DIR" "$1"
    else
        PYTHONPATH="$ROOT_DIR" "$PYTHON" -m ilisp "$1"
    fi
}

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/inc" "$BUILD_DIR/sysinc"
trap 'rm -rf "$BUILD_DIR"' EXIT

PASS_COUNT=0
TOTAL_COUNT=0

assert_eq() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  [PASS] $name"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  [FAIL] $name"
        echo "    Expected: [$expected]"
        echo "    Actual:   [$actual]"
        exit 1
    fi
}

echo "========================================================================"
echo " Starting C99 E2E Compilation & Host Linker Suite (Issue #917)"
echo "========================================================================"

# Prepare all C test sources and headers upfront
cat > "$BUILD_DIR/hello.c" << 'EOF'
int printf(const char *fmt, ...);

int fib(int n) {
    if (n <= 1) return n;
    return fib(n - 1) + fib(n - 2);
}

int main(void) {
    printf("%d\n", 42);
    printf("fib10=%d\n", fib(10));
    return 7;
}
EOF

cat > "$BUILD_DIR/inc/cfg.h" << 'EOF'
#define ADD_CONST 100
#ifdef DROP_ME
#error "DROP_ME should have been undefined by -U"
#endif
EOF

cat > "$BUILD_DIR/sysinc/sys_vals.h" << 'EOF'
#ifndef MUL_SCALE
#define MUL_SCALE 1
#endif
EOF

cat > "$BUILD_DIR/widths.c" << 'EOF'
#include "cfg.h"
#include <sys_vals.h>

int printf(const char *fmt, ...);

int g_seed = 15;

int test_widths(signed char sc, unsigned char uc, short s16, unsigned short u16, int i32) {
    long total = (long)sc + (long)uc + (long)s16 + (long)u16 + (long)i32;
    return (int)total;
}

int main(void) {
    int w = test_widths((signed char)-5, (unsigned char)250, (short)-100, (unsigned short)50000, -100000);
    int val = (w + g_seed + ADD_CONST) * MUL_SCALE;
    printf("w=%d val=%d\n", w, val);
    return 0;
}
EOF

cat > "$BUILD_DIR/mod_math.c" << 'EOF'
int sum8(int a, int b, int c, int d, int e, int f, int g, int h) {
    return a + b + c + d + e + f + g + h;
}
EOF

cat > "$BUILD_DIR/mod_main.c" << 'EOF'
int sum8(int a, int b, int c, int d, int e, int f, int g, int h);
int printf(const char *fmt, ...);

int main(void) {
    int s = sum8(1, 2, 3, 4, 5, 6, 7, 8);
    printf("sum8=%d\n", s);
    return s;
}
EOF

# 1. Real CLI invocation for hello_native
run_ucc "$BUILD_DIR/hello.c" -o "$BUILD_DIR/hello_native"

# Batch remaining valid compilations in one Scheme process to amortize compiler_passes load time
sed '$d' "$DRIVER_RUNNER" > "$BUILD_DIR/batch_e2e.scm"
cat >> "$BUILD_DIR/batch_e2e.scm" << EOF
(begin
  (c-driver-main '("--target=c" "-O1" "$BUILD_DIR/hello.c" "-o" "$BUILD_DIR/hello_c"))
  (c-driver-main '("-E" "-I" "$BUILD_DIR/inc" "-isystem" "$BUILD_DIR/sysinc" "-DMUL_SCALE=2" "-DDROP_ME=1" "-UDROP_ME" "$BUILD_DIR/widths.c" "-o" "$BUILD_DIR/widths.i"))
  (c-driver-main '("-I" "$BUILD_DIR/inc" "-isystem" "$BUILD_DIR/sysinc" "-DMUL_SCALE=2" "-DDROP_ME=1" "-UDROP_ME" "-O1" "$BUILD_DIR/widths.c" "-o" "$BUILD_DIR/widths_native"))
  (c-driver-main '("--target=c" "-I" "$BUILD_DIR/inc" "-isystem" "$BUILD_DIR/sysinc" "-DMUL_SCALE=2" "-DDROP_ME=1" "-UDROP_ME" "-O1" "$BUILD_DIR/widths.c" "-o" "$BUILD_DIR/widths_c"))
  (c-driver-main '("-c" "-O1" "$BUILD_DIR/mod_math.c" "-o" "$BUILD_DIR/mod_math.o"))
  (c-driver-main '("-c" "$BUILD_DIR/mod_main.c" "-o" "$BUILD_DIR/mod_main.o"))
  (c-driver-main '("$BUILD_DIR/mod_math.o" "$BUILD_DIR/mod_main.o" "-o" "$BUILD_DIR/split_nat"))
  (c-driver-main '("--target=c" "$BUILD_DIR/mod_math.c" "$BUILD_DIR/mod_main.c" "-o" "$BUILD_DIR/split_c"))
  (c-driver-main '("-S" "$BUILD_DIR/mod_math.c" "-o" "$BUILD_DIR/mod_math.s"))
  (c-driver-main '("-S" "--target=c" "$BUILD_DIR/mod_math.c" "-o" "$BUILD_DIR/mod_math_out.c"))
  (exit 0))
EOF
run_scheme_script "$BUILD_DIR/batch_e2e.scm"

out_nat=""
rc_nat=0
out_nat=$("$BUILD_DIR/hello_native") || rc_nat=$?

out_c=""
rc_c=0
out_c=$("$BUILD_DIR/hello_c") || rc_c=$?

expected_hello=$'42\nfib10=55'
assert_eq "1.1 native ELF stdout matches expected" "$expected_hello" "$out_nat"
assert_eq "1.2 native ELF exit code == 7" "7" "$rc_nat"
assert_eq "1.3 Portable C stdout matches native ELF" "$out_nat" "$out_c"
assert_eq "1.4 Portable C exit code matches native ELF" "$rc_nat" "$rc_c"

# 2. Preprocessor (-I, -isystem, -D, -U, -E) & Globals (.init_array) & Narrow Widths
if ! grep -q "100" "$BUILD_DIR/widths.i"; then
    echo "  [FAIL] -E preprocessed output missing ADD_CONST expansion"
    exit 1
fi
PASS_COUNT=$((PASS_COUNT + 1))
TOTAL_COUNT=$((TOTAL_COUNT + 1))
echo "  [PASS] 2.1 -E preprocessing with -I/-isystem/-D/-U verified"

out_w_nat=$("$BUILD_DIR/widths_native")
out_w_c=$("$BUILD_DIR/widths_c")
assert_eq "2.2 narrow widths + global .init_array + macros native output" "w=-49855 val=-99480" "$out_w_nat"
assert_eq "2.3 Portable C matches native ELF on narrow widths & globals" "$out_w_nat" "$out_w_c"

# 3. Split Compilation (-c -> ET_REL .o -> host linking) & 7+ args SysV Stack Passing
if ! readelf -h "$BUILD_DIR/mod_math.o" | grep -q "REL (Relocatable file)"; then
    echo "  [FAIL] mod_math.o is not ELF64 ET_REL"
    exit 1
fi
PASS_COUNT=$((PASS_COUNT + 1))
TOTAL_COUNT=$((TOTAL_COUNT + 1))
echo "  [PASS] 3.1 -c produces valid ELF64 ET_REL object file"

out_sp_nat=""
rc_sp_nat=0
out_sp_nat=$("$BUILD_DIR/split_nat") || rc_sp_nat=$?

out_sp_c=""
rc_sp_c=0
out_sp_c=$("$BUILD_DIR/split_c") || rc_sp_c=$?

assert_eq "3.2 split .o link + 8-arg SysV ABI stdout" "sum8=36" "$out_sp_nat"
assert_eq "3.3 split .o link exit code == 36" "36" "$rc_sp_nat"
assert_eq "3.4 Portable C split build matches native ELF" "$out_sp_nat" "$out_sp_c"
assert_eq "3.5 Portable C split exit code == 36" "$rc_sp_nat" "$rc_sp_c"

# 4. -S Emission (x86-64 .s and Portable C)
if ! grep -q "\.globl sum8" "$BUILD_DIR/mod_math.s"; then
    echo "  [FAIL] -S x86-64 assembly missing .globl sum8"
    exit 1
fi
if ! grep -q "ulisp_c99_fn_sum8" "$BUILD_DIR/mod_math_out.c"; then
    echo "  [FAIL] -S --target=c missing ulisp_c99_fn_sum8"
    exit 1
fi
PASS_COUNT=$((PASS_COUNT + 1))
TOTAL_COUNT=$((TOTAL_COUNT + 1))
echo "  [PASS] 4.1 -S emits valid x86-64 .s and Portable C source"

# 5. Real CLI invocation for host linker failure -> C99-DRV-003 and non-zero exit
cat > "$BUILD_DIR/bad_link.c" << 'EOF'
int undefined_external_symbol_917(void);
int main(void) { return undefined_external_symbol_917(); }
EOF

err_out=""
err_rc=0
err_out=$(run_ucc "$BUILD_DIR/bad_link.c" -o "$BUILD_DIR/bad_bin" 2>&1) || err_rc=$?
if [ "$err_rc" -eq 0 ]; then
    echo "  [FAIL] expected non-zero exit for C99-DRV-003"
    exit 1
fi
if ! echo "$err_out" | grep -q "C99-DRV-003"; then
    echo "  [FAIL] expected C99-DRV-003 diagnostic, got: $err_out"
    exit 1
fi
PASS_COUNT=$((PASS_COUNT + 1))
TOTAL_COUNT=$((TOTAL_COUNT + 1))
echo "  [PASS] 5.1 host linker failure emits C99-DRV-003 diagnostic"

rm -rf "$BUILD_DIR"

echo "========================================================================"
echo " C99 E2E Compilation & Host Linker Suite (#917): $PASS_COUNT / $TOTAL_COUNT PASS"
echo "========================================================================"
exit 0
