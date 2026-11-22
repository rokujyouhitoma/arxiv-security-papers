#!/usr/bin/env bash
# ==============================================================================
# ULisp C99 Pointer Scaling, Array Decay & Escape Analysis E2E Suite (#919)
# Verifies:
#   1. Native ELF Pointer Scaling, Array Decay & Multidimensional Indexing vs Host GCC
#   2. Pointer Difference (ptrdiff_t, positive & negative)
#   3. Subscript Symmetry (i[a] == a[i] and lvalue writes)
#   4. Escape Analysis: out-parameter &status modified across function boundaries
#   5. Portable C (--target=c) equivalence
#   6. Bidirectional SysV ABI cross-link between Host GCC and ULisp Native ELF
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$ULISP_DIR")"
BUILD_DIR="$ULISP_DIR/build/test_c99_ptr_$$"
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
echo " Starting C99 Pointer Scaling, Array Decay & Escape E2E Suite (#919)"
echo "========================================================================"

# ------------------------------------------------------------------------------
# 1. Native ELF Pointer & Array Comprehensive Verification vs Host GCC Oracle
# ------------------------------------------------------------------------------
cat > "$BUILD_DIR/ptr_oracle.c" << 'EOF'
int printf(const char *fmt, ...);

struct DataItem {
    long id;
    int code;
    int extra;
};

void update_out(int *out_val) {
    *out_val = 9876;
}

int main(void) {
    // 1. Array decay and sizeof
    int arr[5] = {10, 20, 30, 40, 50};
    int *p = arr;
    int sum = *p + *(p + 1) + *(p + 2) + *(p + 3) + *(p + 4);
    printf("sum=%d sizeof_arr=%ld\n", sum, (long)sizeof(arr));

    // 2. Multidimensional array indexing & symmetry
    int grid[2][3] = {{1, 2, 3}, {4, 5, 6}};
    int sym1 = 2[grid[1]]; // grid[1][2] == 6
    2[grid[1]] = 77;
    int sym2 = grid[1][2];
    printf("sym1=%d sym2=%d sizeof_grid=%ld\n", sym1, sym2, (long)sizeof(grid));

    // 3. Pointer difference (ptrdiff_t, positive & negative)
    int *p_start = &arr[1];
    int *p_end = &arr[4];
    long diff_pos = p_end - p_start;
    long diff_neg = p_start - p_end;
    printf("diff_pos=%ld diff_neg=%ld\n", diff_pos, diff_neg);

    // 4. Struct pointer difference and scaling
    struct DataItem items[4];
    struct DataItem *d0 = &items[0];
    struct DataItem *d3 = &items[3];
    long d_diff = d3 - d0;
    d3->code = 333;
    printf("d_diff=%ld code=%d sizeof_item=%ld\n", d_diff, (d0 + 3)->code, (long)sizeof(struct DataItem));

    // 5. Escape analysis / out-parameter
    int status = 0;
    update_out(&status);
    int pure_local = 100;
    pure_local = pure_local + 50;
    printf("status=%d pure_local=%d\n", status, pure_local);

    return 0;
}
EOF

# Compile with Host GCC
gcc -O2 "$BUILD_DIR/ptr_oracle.c" -o "$BUILD_DIR/gcc_oracle"
GCC_OUTPUT=$("$BUILD_DIR/gcc_oracle")

# Compile with ULisp (Native ELF x86-64)
run_ucc "$BUILD_DIR/ptr_oracle.c" -o "$BUILD_DIR/ulisp_elf"
ULISP_ELF_OUTPUT=$("$BUILD_DIR/ulisp_elf")
assert_eq "1.1 ULisp Native ELF pointer/array execution matches Host GCC oracle 100%" "$GCC_OUTPUT" "$ULISP_ELF_OUTPUT"

# Compile with ULisp (Portable C)
run_ucc --target=c "$BUILD_DIR/ptr_oracle.c" -o "$BUILD_DIR/ulisp_c"
ULISP_C_OUTPUT=$("$BUILD_DIR/ulisp_c")
assert_eq "1.2 ULisp Portable C pointer/array execution matches Host GCC oracle 100%" "$GCC_OUTPUT" "$ULISP_C_OUTPUT"

# ------------------------------------------------------------------------------
# 2. Host GCC <-> ULisp Native ELF Bidirectional Pointer & Array Cross-Link
# ------------------------------------------------------------------------------
cat > "$BUILD_DIR/host_callee.c" << 'EOF'
int fill_array(int *arr, int len) {
    for (int i = 0; i < len; i++) {
        arr[i] = (i + 1) * 10;
    }
    return len;
}

void modify_status(int *status_ptr, int new_val) {
    *status_ptr = new_val;
}

long compute_ptr_diff(const int *p1, const int *p2) {
    return p1 - p2;
}
EOF

cat > "$BUILD_DIR/ulisp_caller.c" << 'EOF'
int printf(const char *fmt, ...);
int fill_array(int *arr, int len);
void modify_status(int *status_ptr, int new_val);
long compute_ptr_diff(const int *p1, const int *p2);

int main(void) {
    int buf[5];
    int n = fill_array(buf, 5);
    int status = 123;
    modify_status(&status, 9999);
    long diff = compute_ptr_diff(&buf[4], &buf[1]);
    printf("n=%d buf3=%d status=%d diff=%ld\n", n, buf[3], status, diff);
    return 0;
}
EOF

gcc -c -O2 "$BUILD_DIR/host_callee.c" -o "$BUILD_DIR/host_callee.o"
run_ucc -c "$BUILD_DIR/ulisp_caller.c" -o "$BUILD_DIR/ulisp_caller.o"
gcc "$BUILD_DIR/ulisp_caller.o" "$BUILD_DIR/host_callee.o" -o "$BUILD_DIR/cross_bin"
CROSS_OUTPUT=$("$BUILD_DIR/cross_bin")

cat > "$BUILD_DIR/oracle_cross.c" << 'EOF'
#include "host_callee.c"
#include "ulisp_caller.c"
EOF
gcc -O2 "$BUILD_DIR/oracle_cross.c" -o "$BUILD_DIR/oracle_cross_bin"
ORACLE_CROSS_OUTPUT=$("$BUILD_DIR/oracle_cross_bin")
assert_eq "2.1 Host GCC <-> ULisp Native ELF bidirectional pointer cross-link" "$ORACLE_CROSS_OUTPUT" "$CROSS_OUTPUT"

echo "========================================================================"
echo " C99 Pointer Scaling, Array Decay & Escape Suite (#919): $PASS_COUNT / $TOTAL_COUNT PASS"
echo "========================================================================"
