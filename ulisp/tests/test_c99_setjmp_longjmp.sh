#!/usr/bin/env bash
# ==============================================================================
# ULisp C99 <setjmp.h> %inline-asm & Spill Protection Oracle Suite (#922)
# Verifies:
#   1. 3-way Oracle Parity (Host GCC -O2 vs ULisp Native ELF -O0/-O2 vs Portable C -O0/-O2):
#      - Basic setjmp(0), longjmp(env, val), longjmp(env, 0)->1, negative return
#      - _setjmp/_longjmp, sigsetjmp/siglongjmp
#      - Deep recursion unwind (depth 15)
#      - Lua luaD_rawrunprotected / struct lua_longjmp 3-level nested recovery
#      - 2000-iteration loop re-entry & function pointer to longjmp
#   2. Non-volatile local & parameter survival across longjmp (Native ELF & Portable C -O0/-O2)
#   3. x86-64 Assembly (-S -O2) & ELF symbol verification (.weak __ulisp_setjmp, no glibc setjmp)
#   4. Multi-TU separate compilation (-c + ld STB_WEAK, and --target=c multi-file merge)
#   5. Bidirectional Host GCC <-> ULisp cross-boundary unwind (default PIE & -no-pie)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$ULISP_DIR")"
BUILD_DIR="$ULISP_DIR/build/test_c99_setjmp_$$"
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

assert_not_grep() {
    local label="$1"
    local pattern="$2"
    local file="$3"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    if ! grep -q -E "$pattern" "$file"; then
        echo "  [PASS] $label"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  [FAIL] $label (unexpected pattern '$pattern' found in $file)"
        exit 1
    fi
}

echo "========================================================================"
echo " Starting C99 <setjmp.h> %inline-asm & Spill Protection Suite (#922)"
echo "========================================================================"

# ------------------------------------------------------------------------------
# 1. 3-Way Oracle Parity (Host GCC -O2 vs Native ELF -O0/-O2 vs Portable C -O0/-O2)
# ------------------------------------------------------------------------------
cat > "$BUILD_DIR/setjmp_oracle.c" << 'EOF'
#include <setjmp.h>

int printf(const char *fmt, ...);

struct lua_longjmp {
    struct lua_longjmp *previous;
    jmp_buf b;
    volatile int status;
};

struct lua_State {
    struct lua_longjmp *errorJmp;
    int trace;
};

static void luaD_throw(struct lua_State *L, int errcode) {
    if (L->errorJmp) {
        L->errorJmp->status = errcode;
        longjmp(L->errorJmp->b, 1);
    }
}

static int luaD_rawrunprotected(struct lua_State *L, void (*f)(struct lua_State *, void *), void *ud) {
    struct lua_longjmp lj;
    lj.status = 0;
    lj.previous = L->errorJmp;
    L->errorJmp = &lj;
    if (setjmp(lj.b) == 0) {
        f(L, ud);
    }
    L->errorJmp = lj.previous;
    return lj.status;
}

static void level3_cb(struct lua_State *L, void *ud) {
    int *flag = (int *)ud;
    L->trace += 4;
    if (*flag > 0) luaD_throw(L, 200);
}

static void level2_cb(struct lua_State *L, void *ud) {
    L->trace += 30;
    int st = luaD_rawrunprotected(L, level3_cb, ud);
    L->trace += st * 5;
    luaD_throw(L, 1);
}

static void level1_cb(struct lua_State *L, void *ud) {
    L->trace += 200;
    int st = luaD_rawrunprotected(L, level2_cb, ud);
    if (st == 1) L->trace += 10;
}

static int recurse_throw(jmp_buf env, int depth, int target) {
    int pad = depth * 10;
    if (depth == target) {
        longjmp(env, pad + 7);
    }
    return recurse_throw(env, depth + 1, target) + 1000;
}

static void call_via_fp(jmp_buf env, void (*lj)(jmp_buf, int), int v) {
    lj(env, v);
}

int main(void) {
    jmp_buf e1;
    int r1 = setjmp(e1);
    if (r1 == 0) longjmp(e1, 0);

    jmp_buf e2;
    int r2 = setjmp(e2);
    if (r2 == 0) longjmp(e2, -7);

    jmp_buf e3;
    int r3 = setjmp(e3);
    if (r3 == 0) recurse_throw(e3, 0, 15);

    jmp_buf e4;
    int r4 = _setjmp(e4);
    if (r4 == 0) _longjmp(e4, 77);

    sigjmp_buf s1;
    int r5 = sigsetjmp(s1, 1);
    if (r5 == 0) siglongjmp(s1, 88);

    struct lua_State L;
    L.errorJmp = 0;
    L.trace = 0;
    int flag = 1;
    int st = luaD_rawrunprotected(&L, level1_cb, &flag);

    volatile int loop_sum = 0;
    jmp_buf arr[2];
    for (int i = 0; i < 2000; i++) {
        int r = setjmp(arr[i & 1]);
        if (r == 0) {
            if ((i % 200) == 199) longjmp(arr[i & 1], 1);
            loop_sum += 1;
        } else {
            loop_sum += 10;
        }
    }

    jmp_buf e_fp;
    void (*lj_ptr)(jmp_buf, int) = longjmp;
    int r_fp = setjmp(e_fp);
    if (r_fp == 0) call_via_fp(e_fp, lj_ptr, 321);

    printf("r1=%d r2=%d r3=%d r4=%d r5=%d ", r1, r2, r3, r4, r5);
    printf("lua=%d,%d loop=%d fp=%d\n", L.trace, st, loop_sum, r_fp);
    return 0;
}
EOF

gcc -O2 "$BUILD_DIR/setjmp_oracle.c" -o "$BUILD_DIR/gcc_oracle"
GCC_OUT=$("$BUILD_DIR/gcc_oracle")

run_ucc -O0 "$BUILD_DIR/setjmp_oracle.c" -o "$BUILD_DIR/ulisp_elf_o0"
ELF_O0_OUT=$("$BUILD_DIR/ulisp_elf_o0")
assert_eq "1.1 ULisp Native ELF (-O0) matches Host GCC oracle" "$GCC_OUT" "$ELF_O0_OUT"

run_ucc -O2 "$BUILD_DIR/setjmp_oracle.c" -o "$BUILD_DIR/ulisp_elf_o2"
ELF_O2_OUT=$("$BUILD_DIR/ulisp_elf_o2")
assert_eq "1.2 ULisp Native ELF (-O2) matches Host GCC oracle" "$GCC_OUT" "$ELF_O2_OUT"

run_ucc --target=c -O0 "$BUILD_DIR/setjmp_oracle.c" -o "$BUILD_DIR/ulisp_c_o0"
C_O0_OUT=$("$BUILD_DIR/ulisp_c_o0")
assert_eq "1.3 ULisp Portable C (-O0) matches Host GCC oracle" "$GCC_OUT" "$C_O0_OUT"

run_ucc --target=c -O2 "$BUILD_DIR/setjmp_oracle.c" -o "$BUILD_DIR/ulisp_c_o2"
C_O2_OUT=$("$BUILD_DIR/ulisp_c_o2")
assert_eq "1.4 ULisp Portable C (-O2) matches Host GCC oracle" "$GCC_OUT" "$C_O2_OUT"

# ------------------------------------------------------------------------------
# 2. ULisp Non-Volatile Local & Parameter Survival Across longjmp (-O0/-O2)
# ------------------------------------------------------------------------------
cat > "$BUILD_DIR/spill_protect.c" << 'EOF'
#include <setjmp.h>

int printf(const char *fmt, ...);

static void do_jump(jmp_buf env, int code) {
    longjmp(env, code);
}

static int test_nonvolatile_spill(int param_x) {
    int a = param_x + 1;
    int b = 10;
    int c = 20;
    int d = 30;
    jmp_buf env;
    int r = setjmp(env);
    if (r == 0) {
        param_x += 5;
        a += 100;
        b += 200;
        c += 300;
        d += 400;
        do_jump(env, 9);
        return -999;
    }
    return param_x + a + b + c + d + r;
}

int main(void) {
    int res = test_nonvolatile_spill(4);
    /* (4+5) + (5+100) + 210 + 320 + 430 + 9 = 1083 */
    printf("spill=%d\n", res);
    return 0;
}
EOF

EXPECTED_SPILL="spill=1083"
run_ucc -O0 "$BUILD_DIR/spill_protect.c" -o "$BUILD_DIR/spill_elf_o0"
assert_eq "2.1 Non-volatile locals & param survive longjmp in Native ELF (-O0)" "$EXPECTED_SPILL" "$("$BUILD_DIR/spill_elf_o0")"
run_ucc -O2 "$BUILD_DIR/spill_protect.c" -o "$BUILD_DIR/spill_elf_o2"
assert_eq "2.2 Non-volatile locals & param survive longjmp in Native ELF (-O2)" "$EXPECTED_SPILL" "$("$BUILD_DIR/spill_elf_o2")"
run_ucc --target=c -O0 "$BUILD_DIR/spill_protect.c" -o "$BUILD_DIR/spill_c_o0"
assert_eq "2.3 Non-volatile locals & param survive longjmp in Portable C (-O0)" "$EXPECTED_SPILL" "$("$BUILD_DIR/spill_c_o0")"
run_ucc --target=c -O2 "$BUILD_DIR/spill_protect.c" -o "$BUILD_DIR/spill_c_o2"
assert_eq "2.4 Non-volatile locals & param survive longjmp in Portable C (-O2)" "$EXPECTED_SPILL" "$("$BUILD_DIR/spill_c_o2")"

# ------------------------------------------------------------------------------
# 3. x86-64 Assembly (-S -O2) & ELF Symbol Isolation Verification
# ------------------------------------------------------------------------------
run_ucc -S -O2 "$BUILD_DIR/setjmp_oracle.c" -o "$BUILD_DIR/setjmp_oracle.s"
assert_grep "3.1 Assembly emits __ulisp_setjmp label" '^__ulisp_setjmp:' "$BUILD_DIR/setjmp_oracle.s"
assert_grep "3.2 Assembly marks __ulisp_setjmp as .weak" '^\s*\.weak\s+__ulisp_setjmp\s*$' "$BUILD_DIR/setjmp_oracle.s"
assert_grep "3.3 Assembly marks __ulisp_longjmp as .weak" '^\s*\.weak\s+__ulisp_longjmp\s*$' "$BUILD_DIR/setjmp_oracle.s"
assert_grep "3.4 __ulisp_setjmp saves rbx to [rdi + 0]" 'mov \[rdi \+ 0\], rbx' "$BUILD_DIR/setjmp_oracle.s"
assert_grep "3.5 __ulisp_setjmp captures caller rsp via lea rdx, \[rsp \+ 8\]" 'lea rdx, \[rsp \+ 8\]' "$BUILD_DIR/setjmp_oracle.s"
assert_grep "3.6 __ulisp_setjmp captures return rip via mov rdx, \[rsp\]" 'mov rdx, \[rsp\]' "$BUILD_DIR/setjmp_oracle.s"
assert_grep "3.7 __ulisp_longjmp normalizes val==0 via cmove rax, rcx" 'cmove rax, rcx' "$BUILD_DIR/setjmp_oracle.s"
assert_grep "3.8 __ulisp_longjmp transfers via jmp rdx" 'jmp rdx' "$BUILD_DIR/setjmp_oracle.s"

run_ucc -c -O2 "$BUILD_DIR/setjmp_oracle.c" -o "$BUILD_DIR/setjmp_oracle.o"
nm -u "$BUILD_DIR/setjmp_oracle.o" > "$BUILD_DIR/undef_syms.txt"
assert_not_grep "3.9 Object does NOT import glibc setjmp/longjmp" '(^|\s)(_?setjmp|_?longjmp|sigsetjmp|siglongjmp)($|\s)' "$BUILD_DIR/undef_syms.txt"
readelf -Ws "$BUILD_DIR/setjmp_oracle.o" > "$BUILD_DIR/elf_syms.txt"
assert_grep "3.10 ELF symbol table exports __ulisp_setjmp as WEAK FUNC" 'FUNC\s+WEAK\s+.*__ulisp_setjmp' "$BUILD_DIR/elf_syms.txt"
assert_grep "3.11 ELF symbol table exports __ulisp_longjmp as WEAK FUNC" 'FUNC\s+WEAK\s+.*__ulisp_longjmp' "$BUILD_DIR/elf_syms.txt"

# ------------------------------------------------------------------------------
# 4. Multi-TU Separate Compilation (-c Weak Linking & --target=c Merge)
# ------------------------------------------------------------------------------
cat > "$BUILD_DIR/tu_a.c" << 'EOF'
#include <setjmp.h>

static void jump_helper(jmp_buf env, int code) {
    longjmp(env, code);
}

int run_tu_a(int seed) {
    jmp_buf env;
    int acc = seed;
    int r = setjmp(env);
    if (r == 0) {
        acc += 15;
        jump_helper(env, 50);
    }
    return acc + r;
}
EOF

cat > "$BUILD_DIR/tu_b.c" << 'EOF'
#include <setjmp.h>

int printf(const char *fmt, ...);
extern int run_tu_a(int seed);

static void jump_b(jmp_buf env) {
    longjmp(env, 0);
}

int main(void) {
    jmp_buf env;
    int a = run_tu_a(10);
    int b = 100;
    int r = setjmp(env);
    if (r == 0) {
        b += 25;
        jump_b(env);
    }
    printf("multi_tu=%d,%d,%d\n", a, b, r);
    return 0;
}
EOF

EXPECTED_MULTI="multi_tu=75,125,1"
run_ucc -c -O2 "$BUILD_DIR/tu_a.c" -o "$BUILD_DIR/tu_a.o"
run_ucc -c -O2 "$BUILD_DIR/tu_b.c" -o "$BUILD_DIR/tu_b.o"
gcc -no-pie "$BUILD_DIR/tu_a.o" "$BUILD_DIR/tu_b.o" -o "$BUILD_DIR/multi_nopie"
assert_eq "4.1 Multi-TU -c weak linking (-no-pie) succeeds" "$EXPECTED_MULTI" "$("$BUILD_DIR/multi_nopie")"
gcc "$BUILD_DIR/tu_a.o" "$BUILD_DIR/tu_b.o" -o "$BUILD_DIR/multi_pie"
assert_eq "4.2 Multi-TU -c weak linking (PIE) succeeds" "$EXPECTED_MULTI" "$("$BUILD_DIR/multi_pie")"
run_ucc --target=c -O2 "$BUILD_DIR/tu_a.c" "$BUILD_DIR/tu_b.c" -o "$BUILD_DIR/multi_c"
assert_eq "4.3 Multi-TU Portable C merge (--target=c -O2) succeeds" "$EXPECTED_MULTI" "$("$BUILD_DIR/multi_c")"

# ------------------------------------------------------------------------------
# 5. Bidirectional Host GCC <-> ULisp Cross-Boundary Unwind (PIE & -no-pie)
# ------------------------------------------------------------------------------
cat > "$BUILD_DIR/ulisp_jmp_side.c" << 'EOF'
#include <setjmp.h>

extern void host_clobber_and_callback(jmp_buf *envp, void (*cb)(jmp_buf *, int));

void ulisp_trigger_unwind(jmp_buf *envp, int val) {
    longjmp(*envp, val);
}

long ulisp_cross_unwind(long init_val) {
    jmp_buf env;
    long v1 = init_val + 10;
    long v2 = init_val * 2;
    int r = setjmp(env);
    if (r == 0) {
        v1 += 5;
        v2 += 7;
        host_clobber_and_callback(&env, ulisp_trigger_unwind);
        return -1;
    }
    return v1 * 1000 + v2 * 10 + r;
}
EOF

cat > "$BUILD_DIR/host_jmp_main.c" << 'EOF'
#include <stdio.h>

extern long ulisp_cross_unwind(long init_val);

void host_clobber_and_callback(long (*envp)[8], void (*cb)(long (*)[8], int)) {
    /* Clobber all 6 SysV callee-saved GPRs before unwinding through ULisp longjmp */
    __asm__ volatile (
        "mov $0x1111111111111111, %%rbx\n\t"
        "mov $0x2222222222222222, %%r12\n\t"
        "mov $0x3333333333333333, %%r13\n\t"
        "mov $0x4444444444444444, %%r14\n\t"
        "mov $0x5555555555555555, %%r15\n\t"
        :
        :
        : "rbx", "r12", "r13", "r14", "r15"
    );
    cb(envp, 9);
}

int main(void) {
    long a = 111;
    long b = 222;
    long c = 333;
    long d = 444;
    long res = ulisp_cross_unwind(20);
    /* v1=35, v2=47, r=9 -> 35*1000 + 47*10 + 9 = 35479 */
    printf("cross=%ld host=%ld,%ld,%ld,%ld\n", res, a, b, c, d);
    return 0;
}
EOF

EXPECTED_CROSS="cross=35479 host=111,222,333,444"
run_ucc -c -O2 "$BUILD_DIR/ulisp_jmp_side.c" -o "$BUILD_DIR/ulisp_jmp_side.o"
gcc -c -O2 "$BUILD_DIR/host_jmp_main.c" -o "$BUILD_DIR/host_jmp_main_pie.o"
gcc -c -O2 -fno-pie "$BUILD_DIR/host_jmp_main.c" -o "$BUILD_DIR/host_jmp_main_nopie.o"

gcc "$BUILD_DIR/ulisp_jmp_side.o" "$BUILD_DIR/host_jmp_main_pie.o" -o "$BUILD_DIR/cross_jmp_pie"
assert_eq "5.1 Bidirectional Host GCC <-> ULisp cross-boundary unwind (default PIE)" "$EXPECTED_CROSS" "$("$BUILD_DIR/cross_jmp_pie")"

gcc -no-pie "$BUILD_DIR/ulisp_jmp_side.o" "$BUILD_DIR/host_jmp_main_nopie.o" -o "$BUILD_DIR/cross_jmp_nopie"
assert_eq "5.2 Bidirectional Host GCC <-> ULisp cross-boundary unwind (-no-pie)" "$EXPECTED_CROSS" "$("$BUILD_DIR/cross_jmp_nopie")"

echo "========================================================================"
echo " C99 <setjmp.h> Oracle Suite (#922): $PASS_COUNT / $TOTAL_COUNT PASS"
echo "========================================================================"
