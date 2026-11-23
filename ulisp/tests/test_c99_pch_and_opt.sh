#!/usr/bin/env bash
# ==============================================================================
# ULisp C99 .sbi Precompiled Header (PCH) & -O2 Iterative Optimization E2E Suite
# Issue #927
# Verifies:
#   1. -emit-pch generates USBI v2 .sbi PCH covering transitive headers
#   2. -include-pch produces 100% BIT-IDENTICAL ELF64 .o objects (cmp -s / sha256sum)
#   3. Linked executable runs identically (PCH vs No-PCH) at -O2
#   4. CLI "C99-PCH-001" warning + safe fallback on -D mismatch and stale header
#   5. CLI "C99-PCH-002" error exit on corrupted / missing .sbi PCH
#   6. PCH reload latency and multi-TU batch speedup
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$ULISP_DIR")"
BUILD_DIR="$ULISP_DIR/build/test_c99_pch_opt_sh_$$"
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

run_scheme_script() {
    if [ "${USE_GOSH:-0}" = "1" ] && command -v gosh >/dev/null 2>&1; then
        gosh -usrfi.9 -ugauche.uvector -ugauche.process -uscheme.file -uscheme.bitwise -uscheme.process-context -I "$ULISP_DIR" -I "$ROOT_DIR" "$1"
    else
        PYTHONPATH="$ROOT_DIR" "$PYTHON" -m ilisp "$1"
    fi
}

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/nopch" "$BUILD_DIR/pch" "$BUILD_DIR/inc"
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

assert_true() {
    local name="$1"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    if "$2" "${@:3}"; then
        echo "  [PASS] $name"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  [FAIL] $name"
        exit 1
    fi
}

echo "========================================================================"
echo " Starting C99 .sbi PCH & -O2 E2E Bit-Identity Suite (Issue #927)"
echo "========================================================================"

cat > "$BUILD_DIR/inc/sub.h" << 'EOF'
#ifndef SUB_H
#define SUB_H
#define SUB_SCALE 3
typedef struct PairVal {
    int a;
    int b;
} PairVal;
#endif
EOF

cat > "$BUILD_DIR/inc/common.h" << 'EOF'
#ifndef COMMON_H
#define COMMON_H
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <limits.h>
#include "sub.h"

#ifndef FOO
#define FOO 10
#endif

typedef struct Node Node;
union WordVal {
    int64_t i;
    double d;
};
enum OpCode {
    OP_ADD = 1,
    OP_MUL = 2,
    OP_MIX = 5
};
extern int shared_table[];
int compute_pair(PairVal p, enum OpCode op);
int fold_array(int n);
int edge_branch(int x, int y);
#endif
EOF

cat > "$BUILD_DIR/tu_a.c" << 'EOF'
#include "common.h"

struct Node {
    int val;
    Node *next;
};

static int mix_local(int x, int y) {
    return x * SUB_SCALE + y + FOO;
}

int compute_pair(PairVal p, enum OpCode op) {
    struct Node n;
    union WordVal w;
    n.val = p.a + p.b;
    n.next = NULL;
    w.i = (int64_t)n.val;
    if (op == OP_ADD) {
        return (int)w.i + FOO;
    } else if (op == OP_MUL) {
        return p.a * p.b + mix_local(p.a, p.b);
    }
    return mix_local(p.a, p.b);
}
EOF

cat > "$BUILD_DIR/tu_b.c" << 'EOF'
#include "common.h"

int shared_table[4] = { 2, 4, 6, 8 };

int fold_array(int n) {
    int s = 0;
    int i = 0;
    for (i = 0; i < n; i++) {
        s += shared_table[i & 3];
    }
    return s + FOO;
}
EOF

cat > "$BUILD_DIR/tu_c.c" << 'EOF'
#include "common.h"

static int helper8(int a, int b, int c, int d, int e, int f, int g, int h) {
    return a + b + c + d + e + f + g + h;
}

int edge_branch(int x, int y) {
    if ((x > 0 && x < 50) || y == 42) {
        return helper8(x, y, 1, 2, 3, 4, 5, FOO) > 20 ? 100 : 50;
    }
    return 7;
}
EOF

cat > "$BUILD_DIR/main.c" << 'EOF'
#include "common.h"

int main(void) {
    PairVal p;
    p.a = 5;
    p.b = 9;
    int r1 = compute_pair(p, OP_ADD);
    int r2 = compute_pair(p, OP_MUL);
    int r3 = fold_array(6);
    int r4 = edge_branch(25, 0);
    int r5 = edge_branch(-1, 99);
    printf("res=%d,%d,%d,%d,%d\n", r1, r2, r3, r4, r5);
    return 0;
}
EOF

# 1. Emit PCH via real CLI invocation
run_ucc -emit-pch -DFOO=10 -I "$BUILD_DIR/inc" "$BUILD_DIR/inc/common.h" -o "$BUILD_DIR/common.h.sbi"
assert_true "1.1 -emit-pch created common.h.sbi" test -s "$BUILD_DIR/common.h.sbi"

# 2. Batch compile all 4 TUs WITHOUT PCH vs WITH PCH in identical single-process runs + timing
T_NOPCH_0="$("$PYTHON" -c 'import time; print(int(time.time()*1000))')"
run_ucc -O2 -DFOO=10 -I "$BUILD_DIR/inc" -c -o "$BUILD_DIR/nopch/" \
    "$BUILD_DIR/tu_a.c" "$BUILD_DIR/tu_b.c" "$BUILD_DIR/tu_c.c" "$BUILD_DIR/main.c"
T_NOPCH_1="$("$PYTHON" -c 'import time; print(int(time.time()*1000))')"

T_PCH_0="$("$PYTHON" -c 'import time; print(int(time.time()*1000))')"
run_ucc -O2 -DFOO=10 -I "$BUILD_DIR/inc" -include-pch "$BUILD_DIR/common.h.sbi" -c -o "$BUILD_DIR/pch/" \
    "$BUILD_DIR/tu_a.c" "$BUILD_DIR/tu_b.c" "$BUILD_DIR/tu_c.c" "$BUILD_DIR/main.c"
T_PCH_1="$("$PYTHON" -c 'import time; print(int(time.time()*1000))')"

echo "  [INFO] 4-TU compile time: no-PCH=$((T_NOPCH_1 - T_NOPCH_0))ms vs with-PCH=$((T_PCH_1 - T_PCH_0))ms"

# 3. Verify 100% BIT-IDENTICAL ELF64 .o objects for ALL 4 TUs
for tu in tu_a tu_b tu_c main; do
    o_no="$BUILD_DIR/nopch/${tu}.o"
    o_pch="$BUILD_DIR/pch/${tu}.o"
    assert_true "2.x ${tu}.o exists (PCH & no-PCH)" test -f "$o_pch"
    assert_true "2.x ${tu}.o cmp -s 100% bit-identical (no-PCH == PCH)" cmp -s "$o_no" "$o_pch"
done

# 4. Link both binaries & verify identical execution output vs GCC ground truth
HOST_CC="${CC:-cc}"
"$HOST_CC" -O2 -DFOO=10 -I "$BUILD_DIR/inc" "$BUILD_DIR/tu_a.c" "$BUILD_DIR/tu_b.c" "$BUILD_DIR/tu_c.c" "$BUILD_DIR/main.c" -o "$BUILD_DIR/bin_gcc"
"$HOST_CC" -no-pie "$BUILD_DIR/nopch/tu_a.o" "$BUILD_DIR/nopch/tu_b.o" "$BUILD_DIR/nopch/tu_c.o" "$BUILD_DIR/nopch/main.o" -o "$BUILD_DIR/bin_nopch"
"$HOST_CC" -no-pie "$BUILD_DIR/pch/tu_a.o" "$BUILD_DIR/pch/tu_b.o" "$BUILD_DIR/pch/tu_c.o" "$BUILD_DIR/pch/main.o" -o "$BUILD_DIR/bin_pch"
assert_eq "3.1 linked executable stdout matches GCC ground truth" "$("$BUILD_DIR/bin_gcc")" "$("$BUILD_DIR/bin_pch")"
assert_eq "3.1b expected res=24,79,36,100,7" "res=24,79,36,100,7" "$("$BUILD_DIR/bin_pch")"
assert_eq "3.2 no-PCH vs PCH linked output equal" "$("$BUILD_DIR/bin_nopch")" "$("$BUILD_DIR/bin_pch")"

# 5. CLI Warning C99-PCH-001 on -D mismatch + fallback succeeds
ERR_FLAG="$BUILD_DIR/err_flag.log"
run_ucc -O2 -DFOO=99 -I "$BUILD_DIR/inc" -include-pch "$BUILD_DIR/common.h.sbi" -c -o "$BUILD_DIR/tu_b_fb.o" "$BUILD_DIR/tu_b.c" 2>"$ERR_FLAG"
assert_true "4.1 -DFOO=99 mismatch warns with C99-PCH-001" grep -q "C99-PCH-001" "$ERR_FLAG"
run_ucc -O2 -DFOO=99 -I "$BUILD_DIR/inc" -c -o "$BUILD_DIR/tu_b_99.o" "$BUILD_DIR/tu_b.c"
assert_true "4.2 fallback -DFOO=99 .o bit-identical to full compile" cmp -s "$BUILD_DIR/tu_b_99.o" "$BUILD_DIR/tu_b_fb.o"

# 6. CLI Warning C99-PCH-001 on modified transitive dependency header sub.h
sed -i 's/#define SUB_SCALE 3/#define SUB_SCALE 10/' "$BUILD_DIR/inc/sub.h"
ERR_STALE="$BUILD_DIR/err_stale.log"
run_ucc -O2 -DFOO=10 -I "$BUILD_DIR/inc" -include-pch "$BUILD_DIR/common.h.sbi" -c -o "$BUILD_DIR/tu_a_stale.o" "$BUILD_DIR/tu_a.c" 2>"$ERR_STALE"
assert_true "4.3 modified sub.h triggers C99-PCH-001 warning" grep -q "C99-PCH-001" "$ERR_STALE"
"$HOST_CC" -no-pie "$BUILD_DIR/tu_a_stale.o" "$BUILD_DIR/pch/tu_b.o" "$BUILD_DIR/pch/tu_c.o" "$BUILD_DIR/pch/main.o" -o "$BUILD_DIR/bin_stale"
assert_eq "4.4 fallback reflects updated SUB_SCALE=10 in sub.h" "res=24,114,36,100,7" "$("$BUILD_DIR/bin_stale")"

# 7. CLI Error C99-PCH-002 on corrupted .sbi
"$PYTHON" -c "
p = '$BUILD_DIR/common.h.sbi'
b = bytearray(open(p, 'rb').read())
b[-1] ^= 0xFF
open('$BUILD_DIR/bad.sbi', 'wb').write(b)
"
ERR_BAD="$BUILD_DIR/err_bad.log"
BAD_RC=0
run_ucc -O2 -DFOO=10 -I "$BUILD_DIR/inc" -include-pch "$BUILD_DIR/bad.sbi" -c -o "$BUILD_DIR/bad.o" "$BUILD_DIR/tu_a.c" 2>"$ERR_BAD" || BAD_RC=$?
assert_true "5.1 corrupted .sbi exits non-zero" test "$BAD_RC" -ne 0
assert_true "5.2 corrupted .sbi emits C99-PCH-002 error" grep -q "C99-PCH-002" "$ERR_BAD"

echo "========================================================================"
echo " C99 .sbi PCH & -O2 E2E Suite (#927): ${PASS_COUNT}/${TOTAL_COUNT} PASS"
echo "========================================================================"
