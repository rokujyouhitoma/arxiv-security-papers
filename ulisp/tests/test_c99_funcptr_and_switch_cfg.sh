#!/usr/bin/env bash
# ==============================================================================
# ULisp C99 Function Pointers, %call-indirect & Switch/Goto CFG E2E Suite (#920)
# Verifies:
#   1. 3-way Oracle Parity (Host GCC -O2 vs ULisp Native ELF -O0/-O2 vs Portable C -O0/-O2):
#      - Function pointer arrays, lua_CFunction struct callbacks, funcptr-returning fn
#      - Indirect >16B sret struct return & float/stack ABI
#      - 85-branch dense switch (.rodata PC-rel jump table) + out-of-range default
#      - 12-branch sparse switch (balanced BST tier)
#      - Duff's device, mutual goto loops & &status escaped variable coherence
#   2. x86-64 Assembly Verification (-S): .L_jt_, bounds check ja, call r11
#   3. Bidirectional Host GCC <-> ULisp Native ELF Callback Cross-Linking (PIE + -no-pie)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$ULISP_DIR")"
BUILD_DIR="$ULISP_DIR/build/test_c99_cfg_$$"
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
echo " Starting C99 Function Pointers & Switch/Goto CFG Oracle Suite (#920)"
echo "========================================================================"

# Generate comprehensive C99 oracle test with 85-branch dense switch + callbacks
cat > "$BUILD_DIR/cfg_oracle.c" << 'EOF_HEAD'
int printf(const char *fmt, ...);
unsigned long strlen(const char *s);

struct lua_State {
    int acc;
    int status;
};

typedef int (*lua_CFunction)(struct lua_State *L);

struct BigVec {
    long x;
    long y;
    long z;
};

int cb_add10(struct lua_State *L) {
    L->status += 1;
    return L->acc + 10;
}

int cb_mul3(struct lua_State *L) {
    L->status += 2;
    return L->acc * 3;
}

static int op_add(int a, int b) { return a + b; }
static int op_sub(int a, int b) { return a - b; }
static int op_mul(int a, int b) { return a * b; }

static int (*g_vtable[3])(int, int) = { op_add, op_sub, op_mul };

int (*select_vop(int idx))(int, int) {
    return (idx >= 0 && idx < 3) ? g_vtable[idx] : 0;
}

struct BigVec make_big(long a, long b, long c, double scale) {
    struct BigVec v;
    v.x = a * 2;
    v.y = b + (long)(scale * 10.0);
    v.z = c - a;
    return v;
}

void update_status_via_cb(int *st, void (*writer)(int *, int), int delta) {
    writer(st, delta);
}

void write_delta(int *p, int d) {
    *p += d;
}

int lua_vm_switch85(int *ops, int n) {
    int acc = 0;
    for (int i = 0; i < n; i++) {
        switch (ops[i]) {
EOF_HEAD

# Append 85 dense switch arms cleanly
for i in $(seq 0 84); do
    printf '            case %d: acc += %d; break;\n' "$i" "$((i * 5 + 3))" >> "$BUILD_DIR/cfg_oracle.c"
done

cat >> "$BUILD_DIR/cfg_oracle.c" << 'EOF_TAIL'
            default: acc += 777; break;
        }
    }
    return acc;
}

int sparse_switch_eval(long k) {
    switch (k) {
        case -1000000: return 11;
        case -42: return 22;
        case 0: return 33;
        case 7: return 44;
        case 4097: return 55;
        case 50000: return 66;
        case 100000: return 77;
        case 200000: return 88;
        case 400000: return 99;
        case 800000: return 110;
        case 1600000: return 121;
        case 3200000: return 132;
        default: return 999;
    }
}

void duff_sum_copy(int *dst, const int *src, int cnt) {
    int n = (cnt + 3) / 4;
    switch (cnt % 4) {
        case 0: do { *dst++ = *src++;
        case 3:      *dst++ = *src++;
        case 2:      *dst++ = *src++;
        case 1:      *dst++ = *src++;
                } while (--n > 0);
    }
}

int main(void) {
    struct lua_State L = { 12, 0 };
    lua_CFunction fns[2] = { cb_add10, cb_mul3 };
    int r_cb = fns[0](&L) + (*fns[1])(&L);
    int r_sel = select_vop(2)(9, 7) + (select_vop(99) == 0 ? 1 : 0);

    struct BigVec (*big_fn)(long, long, long, double) = make_big;
    struct BigVec bv = big_fn(5, 10, 40, 2.5);

    unsigned long (*slen)(const char *) = strlen;
    int sl = (int)slen("ulisp-c99-cfg");

    int vm_ops[9] = {0, 1, 20, 42, 83, 84, -1, 85, 500};
    int vm_res = lua_vm_switch85(vm_ops, 9);

    int sp_res = sparse_switch_eval(-1000000) + sparse_switch_eval(4097) +
                 sparse_switch_eval(1600000) + sparse_switch_eval(42);

    int duff_in[7] = {3, 5, 7, 11, 13, 17, 19};
    int duff_out[7] = {0, 0, 0, 0, 0, 0, 0};
    duff_sum_copy(duff_out, duff_in, 7);
    int dsum = 0;
    for (int i = 0; i < 7; i++) dsum += duff_out[i];

    int st = 10;
    int loop_cnt = 0;
    goto phase_one;
phase_two:
    update_status_via_cb(&st, write_delta, 15);
    loop_cnt++;
    if (loop_cnt < 4) goto phase_one;
    goto end_phases;
phase_one:
    update_status_via_cb(&st, write_delta, 25);
    goto phase_two;
end_phases:

    printf("cb=%d stL=%d sel=%d big=%ld,%ld\n", r_cb, L.status, r_sel, bv.x, bv.y);
    printf("bigz=%ld sl=%d vm=%d sp=%d dsum=%d\n", bv.z, sl, vm_res, sp_res, dsum);
    printf("gst=%d\n", st);
    return 0;
}
EOF_TAIL

gcc -O2 "$BUILD_DIR/cfg_oracle.c" -o "$BUILD_DIR/gcc_oracle"
GCC_OUT=$("$BUILD_DIR/gcc_oracle")

run_ucc -O0 "$BUILD_DIR/cfg_oracle.c" -o "$BUILD_DIR/ulisp_elf_o0"
ELF_O0_OUT=$("$BUILD_DIR/ulisp_elf_o0")
assert_eq "1.1 ULisp Native ELF (-O0) matches Host GCC oracle" "$GCC_OUT" "$ELF_O0_OUT"

run_ucc -O2 "$BUILD_DIR/cfg_oracle.c" -o "$BUILD_DIR/ulisp_elf_o2"
ELF_O2_OUT=$("$BUILD_DIR/ulisp_elf_o2")
assert_eq "1.2 ULisp Native ELF (-O2) matches Host GCC oracle" "$GCC_OUT" "$ELF_O2_OUT"

run_ucc --target=c -O0 "$BUILD_DIR/cfg_oracle.c" -o "$BUILD_DIR/ulisp_c_o0"
C_O0_OUT=$("$BUILD_DIR/ulisp_c_o0")
assert_eq "1.3 ULisp Portable C (-O0) matches Host GCC oracle" "$GCC_OUT" "$C_O0_OUT"

run_ucc --target=c -O2 "$BUILD_DIR/cfg_oracle.c" -o "$BUILD_DIR/ulisp_c_o2"
C_O2_OUT=$("$BUILD_DIR/ulisp_c_o2")
assert_eq "1.4 ULisp Portable C (-O2) matches Host GCC oracle" "$GCC_OUT" "$C_O2_OUT"

# ------------------------------------------------------------------------------
# 2. Assembly Codegen Inspection (-S): Jump Table, Unsigned ja Bounds & call r11
# ------------------------------------------------------------------------------
run_ucc -S -O2 "$BUILD_DIR/cfg_oracle.c" -o "$BUILD_DIR/cfg_oracle.s"
assert_grep "2.1 Native x86-64 -S emits .rodata PC-rel jump table (.L_jt_)" '\.L_jt_' "$BUILD_DIR/cfg_oracle.s"
assert_grep "2.2 Native x86-64 -S emits unsigned bounds check (ja)" '^\s*ja\s+' "$BUILD_DIR/cfg_oracle.s"
assert_grep "2.3 Native x86-64 -S emits indirect call (call r11)" '^\s*call\s+r11\s*$' "$BUILD_DIR/cfg_oracle.s"

# ------------------------------------------------------------------------------
# 3. Bidirectional Host GCC <-> ULisp Native ELF Callback Cross-Linking
# ------------------------------------------------------------------------------
cat > "$BUILD_DIR/ulisp_side.c" << 'EOF'
int ulisp_apply_host_cb(int (*host_cb)(int, int), int a, int b) {
    return (*host_cb)(a, b) + 100;
}

static int ulisp_cb_plus(int x) { return x + 5; }
static int ulisp_cb_square(int x) { return x * x; }

static int ulisp_cb_switch(int x) {
    switch (x) {
        case 1: return 111;
        case 2: return 222;
        default: return x * 10;
    }
}

int (*ulisp_get_cb(int mode))(int) {
    switch (mode) {
        case 0: return ulisp_cb_plus;
        case 1: return ulisp_cb_square;
        default: return ulisp_cb_switch;
    }
}

int ulisp_roundtrip(int (*host_tramp)(int (*)(int), int), int mode, int val) {
    int (*cb)(int) = ulisp_get_cb(mode);
    return host_tramp(cb, val);
}
EOF

cat > "$BUILD_DIR/host_main.c" << 'EOF'
#include <stdio.h>

extern int ulisp_apply_host_cb(int (*host_cb)(int, int), int a, int b);
extern int (*ulisp_get_cb(int mode))(int);
extern int ulisp_roundtrip(int (*host_tramp)(int (*)(int), int), int mode, int val);

static int host_arith_cb(int a, int b) {
    return a * 10 + b;
}

static int host_invoke_cb(int (*cb)(int), int v) {
    return cb(v) + 7;
}

int main(void) {
    int r1 = ulisp_apply_host_cb(host_arith_cb, 4, 9);
    int (*u0)(int) = ulisp_get_cb(0);
    int (*u1)(int) = ulisp_get_cb(1);
    int (*u2)(int) = ulisp_get_cb(2);
    int r2 = u0(10) + u1(6) + u2(2);
    int r3 = ulisp_roundtrip(host_invoke_cb, 2, 1);
    printf("r1=%d r2=%d r3=%d\n", r1, r2, r3);
    return 0;
}
EOF

run_ucc -c -O2 "$BUILD_DIR/ulisp_side.c" -o "$BUILD_DIR/ulisp_side.o"
gcc -c -O2 "$BUILD_DIR/host_main.c" -o "$BUILD_DIR/host_main_pie.o"
gcc -c -O2 -fno-pie "$BUILD_DIR/host_main.c" -o "$BUILD_DIR/host_main_nopie.o"

# Reference oracle compiled purely with GCC
gcc -O2 "$BUILD_DIR/ulisp_side.c" "$BUILD_DIR/host_main.c" -o "$BUILD_DIR/cross_ref"
CROSS_REF=$("$BUILD_DIR/cross_ref")

# Default PIE link
gcc "$BUILD_DIR/ulisp_side.o" "$BUILD_DIR/host_main_pie.o" -o "$BUILD_DIR/cross_pie"
CROSS_PIE=$("$BUILD_DIR/cross_pie")
assert_eq "3.1 Bidirectional Host GCC <-> ULisp callback cross-link (default PIE)" "$CROSS_REF" "$CROSS_PIE"

# -no-pie link
gcc -no-pie "$BUILD_DIR/ulisp_side.o" "$BUILD_DIR/host_main_nopie.o" -o "$BUILD_DIR/cross_nopie"
CROSS_NOPIE=$("$BUILD_DIR/cross_nopie")
assert_eq "3.2 Bidirectional Host GCC <-> ULisp callback cross-link (-no-pie)" "$CROSS_REF" "$CROSS_NOPIE"

echo "========================================================================"
echo " C99 Function Pointers & Switch/Goto CFG Oracle (#920): $PASS_COUNT / $TOTAL_COUNT PASS"
echo "========================================================================"
