#!/usr/bin/env bash
# ==============================================================================
# Issue #930: C99 Bounds & NULL-Pointer Sanitizer (--sanitize-bounds) E2E Suite
# Verifies:
#   1. Zero-overhead guarantee when --sanitize-bounds is omitted (.o SHA-256 & 0 trap symbols)
#   2. Valid accesses, &arr[N] one-past-end, and trailing [1] FAM exit 0 (Pass 144 musl, host ld, --target=c)
#   3. OOB (+, -, &arr[N+1]) trap with exit code 134 and C99-SAN-001 <file>:<line>:<col> on stderr
#   4. NULL deref (*p, p->f, p[0], bitfield p->bf) trap with exit code 134 and C99-SAN-002 on stderr
#   5. Full 33-TU Lua 5.4.7 build with --sanitize-bounds + official all.lua ('final OK !!!', 0 false positives)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$ULISP_DIR")"
BUILD_DIR="$ULISP_DIR/build/test_c99_bounds_sanitizer_$$"
DRIVER_RUNNER="$ULISP_DIR/build/c_driver_runner.scm"

if [ -x "$ROOT_DIR/.venv/bin/python" ]; then
    PYTHON="$ROOT_DIR/.venv/bin/python"
else
    PYTHON="python3"
fi

if [ -n "${ULISP_CC_BIN:-}" ] && [ -x "${ULISP_CC_BIN}" ]; then
    RUN_CC=("$ULISP_CC_BIN")
elif [ "${USE_GOSH:-1}" = "1" ] && command -v gosh >/dev/null 2>&1; then
    GOSH_BIN="$(command -v gosh)"
    RUN_CC=("$GOSH_BIN" -usrfi.9 -ugauche.uvector -ugauche.process -uscheme.file -uscheme.bitwise -uscheme.process-context -I "$ULISP_DIR" -I "$ROOT_DIR" "$DRIVER_RUNNER" --)
else
    export PYTHONPATH="$ROOT_DIR"
    RUN_CC=("$PYTHON" -m ilisp "$DRIVER_RUNNER" --)
fi

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
        echo "  [FAIL] $label (expected '$expected', got '$actual')" >&2
        exit 1
    fi
}

assert_trap_134() {
    local label="$1"
    local code_tag="$2"
    shift 2
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    local err_file="$BUILD_DIR/trap_err.txt"
    local rc=0
    set +e
    "$@" > /dev/null 2> "$err_file"
    rc=$?
    set -e
    if [ "$rc" -ne 134 ]; then
        echo "  [FAIL] $label (expected exit code 134, got $rc)" >&2
        cat "$err_file" >&2 || true
        exit 1
    fi
    if ! grep -q -E "^\[ulisp-sanitizer\] error\[${code_tag}\]: .* at .*:[0-9]+:[0-9]+$" "$err_file"; then
        echo "  [FAIL] $label (stderr did not match expected format for ${code_tag}):" >&2
        cat "$err_file" >&2 || true
        exit 1
    fi
    echo "  [PASS] $label ($(tr -d '\n' < "$err_file"))"
    PASS_COUNT=$((PASS_COUNT + 1))
}

echo "========================================================================"
echo " Starting C99 Bounds & NULL Sanitizer E2E Suite (#930)"
echo "========================================================================"

MUSL_LIB_DIR="$ULISP_DIR/build/musl_build/obj/lib"
if [ ! -f "$MUSL_LIB_DIR/crt1.o" ] || [ ! -f "$MUSL_LIB_DIR/libc.a" ]; then
    echo "  [INFO] Building musl-1.2.5 crt1.o & libc.a via tests/test_compile_musl.sh ..."
    USE_GOSH="${USE_GOSH:-1}" bash "$ULISP_DIR/tests/test_compile_musl.sh"
fi

# ------------------------------------------------------------------------------
# 1. Zero-Overhead Verification (--sanitize-bounds OFF)
# ------------------------------------------------------------------------------
echo "--- Group 1: Zero-Overhead Verification (.o SHA-256 & 0 Trap Symbols) ---"

cat > "$BUILD_DIR/zero_ovh.c" << 'EOF'
struct Item { int id; char name[1]; };
int sum_arr(int *p, struct Item *it, int n) {
    int arr[8] = {1,2,3,4,5,6,7,8};
    int *endp = &arr[8];
    int s = 0;
    for (int *q = &arr[0]; q < endp; q++) s += *q;
    return s + p[0] + it->id + it->name[n];
}
int main(void) {
    int x = 3;
    struct Item it = {4, {'a'}};
    return sum_arr(&x, &it, 0) == 43 ? 0 : 1;
}
EOF

"${RUN_CC[@]}" -O2 -c "$BUILD_DIR/zero_ovh.c" -o "$BUILD_DIR/zero_ovh_a.o"
"${RUN_CC[@]}" -O2 -c "$BUILD_DIR/zero_ovh.c" -o "$BUILD_DIR/zero_ovh_b.o"
SHA_A="$(sha256sum "$BUILD_DIR/zero_ovh_a.o" | awk '{print $1}')"
SHA_B="$(sha256sum "$BUILD_DIR/zero_ovh_b.o" | awk '{print $1}')"
assert_eq "1.1 Unsanitized .o compilation is SHA-256 deterministic" "$SHA_A" "$SHA_B"

TOTAL_COUNT=$((TOTAL_COUNT + 1))
if readelf -sW "$BUILD_DIR/zero_ovh_a.o" | grep -q "__ulisp_san_trap"; then
    echo "  [FAIL] 1.2 Unexpected __ulisp_san_trap symbol in unsanitized .o" >&2
    exit 1
else
    echo "  [PASS] 1.2 Zero __ulisp_san_trap symbols in unsanitized .o"
    PASS_COUNT=$((PASS_COUNT + 1))
fi

# ------------------------------------------------------------------------------
# 2. Multi-Mode Trap & Valid-Access Matrix (Pass 144 musl, Host ld, Portable C)
# ------------------------------------------------------------------------------
echo "--- Group 2: Native Pass 144 / Host ld / Portable C Trap Matrix ---"

cat > "$BUILD_DIR/san_cases.c" << 'EOF'
struct Node {
    int tag;
    unsigned int bf : 5;
    int val;
};

struct DynBuf {
    int cap;
    char contents[1];
};

static int run_valid(void) {
    int a[4] = {10, 20, 30, 40};
    int *p = &a[0];
    int *endp = &a[4];
    int sum = 0;
    while (p < endp) {
        sum += *p;
        p++;
    }
    struct {
        struct DynBuf hdr;
        char extra[8];
    } storage;
    storage.hdr.cap = 8;
    for (int i = 0; i < 6; i++) {
        storage.hdr.contents[i] = (char)('a' + i);
    }
    if (sum != 100 || storage.hdr.contents[5] != 'f') return 1;
    return 0;
}

static int trigger_oob_pos(int idx) {
    int a[4] = {1, 2, 3, 4};
    return a[idx];
}

static int trigger_oob_neg(int idx) {
    int a[4] = {1, 2, 3, 4};
    return a[idx];
}

static int trigger_oob_one_past_plus1(int idx) {
    int a[4] = {1, 2, 3, 4};
    int *p = &a[idx];
    return p != 0 ? 0 : 1;
}

static int trigger_null_deref(int *p) {
    return *p;
}

static int trigger_null_member(struct Node *n) {
    return n->val;
}

static int trigger_null_bitfield(struct Node *n) {
    return (int)n->bf;
}

static int trigger_null_subscript(int *p) {
    return p[0];
}

int main(int argc, char **argv) {
#ifdef SAN_FIXED_MODE
    int mode = SAN_FIXED_MODE;
#else
    if (argc < 2) return 2;
    int mode = argv[1][0] - '0';
#endif
    switch (mode) {
        case 0: return run_valid();
        case 1: return trigger_oob_pos(4);
        case 2: return trigger_oob_pos(9);
        case 3: return trigger_oob_neg(-1);
        case 4: return trigger_oob_one_past_plus1(5);
        case 5: return trigger_null_deref((int *)0);
        case 6: return trigger_null_member((struct Node *)0);
        case 7: return trigger_null_bitfield((struct Node *)0);
        case 8: return trigger_null_subscript((int *)0);
        default: return 3;
    }
}
EOF

# 2A: Pass 144 static musl binary
"${RUN_CC[@]}" --sanitize-bounds -O2 -c "$BUILD_DIR/san_cases.c" -o "$BUILD_DIR/san_cases.o"
"${RUN_CC[@]}" --linker=ulisp -static -nostdlib \
    "$MUSL_LIB_DIR/crt1.o" "$BUILD_DIR/san_cases.o" "$MUSL_LIB_DIR/libc.a" \
    -o "$BUILD_DIR/san_cases_musl"

set +e
"$BUILD_DIR/san_cases_musl" 0
VALID_RC=$?
set -e
assert_eq "2A.0 Pass 144 musl valid bounds / &arr[N] / trailing [1] FAM exits 0" "0" "$VALID_RC"
assert_trap_134 "2A.1 Pass 144 musl arr[N] OOB traps 134" "C99-SAN-001" "$BUILD_DIR/san_cases_musl" 1
assert_trap_134 "2A.2 Pass 144 musl arr[N+5] OOB traps 134" "C99-SAN-001" "$BUILD_DIR/san_cases_musl" 2
assert_trap_134 "2A.3 Pass 144 musl arr[-1] negative index traps 134" "C99-SAN-001" "$BUILD_DIR/san_cases_musl" 3
assert_trap_134 "2A.4 Pass 144 musl &arr[N+1] traps 134" "C99-SAN-001" "$BUILD_DIR/san_cases_musl" 4
assert_trap_134 "2A.5 Pass 144 musl NULL *p traps 134" "C99-SAN-002" "$BUILD_DIR/san_cases_musl" 5
assert_trap_134 "2A.6 Pass 144 musl NULL p->val traps 134" "C99-SAN-002" "$BUILD_DIR/san_cases_musl" 6
assert_trap_134 "2A.7 Pass 144 musl NULL p->bf bitfield traps 134" "C99-SAN-002" "$BUILD_DIR/san_cases_musl" 7
assert_trap_134 "2A.8 Pass 144 musl NULL p[0] traps 134" "C99-SAN-002" "$BUILD_DIR/san_cases_musl" 8

# 2B: Host linker binary
"${RUN_CC[@]}" --sanitize-bounds --linker=host -O2 "$BUILD_DIR/san_cases.c" -o "$BUILD_DIR/san_cases_host"
set +e
"$BUILD_DIR/san_cases_host" 0
HOST_VALID_RC=$?
set -e
assert_eq "2B.0 Host linker valid bounds exits 0" "0" "$HOST_VALID_RC"
assert_trap_134 "2B.1 Host linker arr[N] OOB traps 134" "C99-SAN-001" "$BUILD_DIR/san_cases_host" 1
assert_trap_134 "2B.2 Host linker NULL *p traps 134" "C99-SAN-002" "$BUILD_DIR/san_cases_host" 5

# 2C: Portable C backend (--target=c)
"${RUN_CC[@]}" --sanitize-bounds --target=c -DSAN_FIXED_MODE=0 -O2 "$BUILD_DIR/san_cases.c" -o "$BUILD_DIR/san_cases_c_0"
set +e
"$BUILD_DIR/san_cases_c_0"
C_VALID_RC=$?
set -e
assert_eq "2C.0 Portable C valid bounds exits 0" "0" "$C_VALID_RC"
"${RUN_CC[@]}" --sanitize-bounds --target=c -DSAN_FIXED_MODE=1 -O2 "$BUILD_DIR/san_cases.c" -o "$BUILD_DIR/san_cases_c_1"
assert_trap_134 "2C.1 Portable C arr[N] OOB traps 134" "C99-SAN-001" "$BUILD_DIR/san_cases_c_1"
"${RUN_CC[@]}" --sanitize-bounds --target=c -DSAN_FIXED_MODE=3 -O2 "$BUILD_DIR/san_cases.c" -o "$BUILD_DIR/san_cases_c_3"
assert_trap_134 "2C.2 Portable C arr[-1] traps 134" "C99-SAN-001" "$BUILD_DIR/san_cases_c_3"
"${RUN_CC[@]}" --sanitize-bounds --target=c -DSAN_FIXED_MODE=6 -O2 "$BUILD_DIR/san_cases.c" -o "$BUILD_DIR/san_cases_c_6"
assert_trap_134 "2C.3 Portable C NULL p->val traps 134" "C99-SAN-002" "$BUILD_DIR/san_cases_c_6"

# ------------------------------------------------------------------------------
# 3. Full 33-TU Lua 5.4.7 --sanitize-bounds Build & Official all.lua E2E
# ------------------------------------------------------------------------------
echo "--- Group 3: Lua 5.4.7 Full 33-TU --sanitize-bounds + Official all.lua ---"

LUA_SRC_DIR="$ULISP_DIR/build/third_party/lua-5.4.7/src"
LUA_TESTS_DIR="$ULISP_DIR/build/third_party/lua-5.4.7-tests"

if [ ! -f "$LUA_SRC_DIR/lapi.c" ]; then
    echo "  [INFO] Fetching Lua 5.4.7 sources via tests/test_compile_lua.sh ..."
    LUA_DIFF_GCC=0 USE_GOSH="${USE_GOSH:-1}" bash "$ULISP_DIR/tests/test_compile_lua.sh"
fi
if [ ! -f "$LUA_TESTS_DIR/all.lua" ]; then
    echo "  [INFO] Fetching Lua 5.4.7 test suite via tests/test_lua_selfhost_e2e.sh ..."
    LUA_DIFF_GCC=0 LUA_FULL_BIG=0 USE_GOSH="${USE_GOSH:-1}" bash "$ULISP_DIR/tests/test_lua_selfhost_e2e.sh"
fi

LUA_SAN_OBJ="$BUILD_DIR/lua_san_obj"
mkdir -p "$LUA_SAN_OBJ"

CORE_PCH_HDR="$LUA_SAN_OBJ/lua_core_pch.h"
LIB_PCH_HDR="$LUA_SAN_OBJ/lua_lib_pch.h"
CORE_PCH_SBI="$LUA_SAN_OBJ/lua_core_pch.h.sbi"
LIB_PCH_SBI="$LUA_SAN_OBJ/lua_lib_pch.h.sbi"

cat > "$CORE_PCH_HDR" << 'EOF'
#ifndef LUA_CORE
#define LUA_CORE
#endif
#include "lprefix.h"
#include <ctype.h>
#include <errno.h>
#include <float.h>
#include <limits.h>
#include <locale.h>
#include <math.h>
#include <setjmp.h>
#include <signal.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "lua.h"
#include "llimits.h"
#include "lobject.h"
#include "lstate.h"
#include "ltm.h"
#include "lzio.h"
#include "lmem.h"
#include "lgc.h"
#include "lfunc.h"
#include "lstring.h"
#include "ltable.h"
#include "ldo.h"
#include "ldebug.h"
#include "lvm.h"
#include "lundump.h"
#include "lapi.h"
#include "lparser.h"
#include "llex.h"
#include "lcode.h"
#include "lopcodes.h"
#include "lctype.h"
EOF

cat > "$LIB_PCH_HDR" << 'EOF'
#ifndef LUA_LIB
#define LUA_LIB
#endif
#include "lprefix.h"
#include <ctype.h>
#include <errno.h>
#include <float.h>
#include <limits.h>
#include <locale.h>
#include <math.h>
#include <setjmp.h>
#include <signal.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
EOF

"${RUN_CC[@]}" -emit-pch -DLUA_USE_POSIX -I "$LUA_SRC_DIR" "$CORE_PCH_HDR" -o "$CORE_PCH_SBI" > "$LUA_SAN_OBJ/pch_core.log" 2>&1 &
PCH_PID1="$!"
"${RUN_CC[@]}" -emit-pch -DLUA_USE_POSIX -I "$LUA_SRC_DIR" "$LIB_PCH_HDR" -o "$LIB_PCH_SBI" > "$LUA_SAN_OBJ/pch_lib.log" 2>&1 &
PCH_PID2="$!"
wait "$PCH_PID1"
wait "$PCH_PID2"

CORE_ORDER=(
    lvm lparser lcode lapi
    lgc ldo lobject ltable
    llex ldebug lstate lfunc
    lstring lundump ldump lopcodes
    ltm lmem lzio lctype
)
LIB_ORDER=(
    lstrlib lauxlib lbaselib liolib
    loadlib ldblib lmathlib ltablib
    loslib lcorolib lutf8lib linit
)
CLI_TUS=(lua)

JOBS="$(nproc 2>/dev/null || echo 4)"
if [ "$JOBS" -gt 8 ]; then JOBS=8; fi

PIDS=()
for ((s = 0; s < JOBS; s++)); do
    SHARD_CORE=()
    for ((i = s; i < ${#CORE_ORDER[@]}; i += JOBS)); do
        SHARD_CORE+=("$LUA_SRC_DIR/${CORE_ORDER[$i]}.c")
    done
    rev_s=$((JOBS - 1 - s))
    SHARD_LIB=()
    for ((i = rev_s; i < ${#LIB_ORDER[@]}; i += JOBS)); do
        SHARD_LIB+=("$LUA_SRC_DIR/${LIB_ORDER[$i]}.c")
    done
    SHARD_CLI=()
    if [ "$s" -eq $((JOBS - 1)) ]; then
        SHARD_CLI+=("$LUA_SRC_DIR/lua.c")
    fi

    if [ -n "${ULISP_CC_BIN:-}" ] && [ -x "${ULISP_CC_BIN}" ]; then
        (
            [ "${#SHARD_CORE[@]}" -gt 0 ] && "$ULISP_CC_BIN" --sanitize-bounds -DLUA_USE_POSIX -O2 -I "$LUA_SRC_DIR" -include-pch "$CORE_PCH_SBI" -c -o "$LUA_SAN_OBJ/" "${SHARD_CORE[@]}"
            [ "${#SHARD_LIB[@]}" -gt 0 ] && "$ULISP_CC_BIN" --sanitize-bounds -DLUA_USE_POSIX -O2 -I "$LUA_SRC_DIR" -include-pch "$LIB_PCH_SBI" -c -o "$LUA_SAN_OBJ/" "${SHARD_LIB[@]}"
            [ "${#SHARD_CLI[@]}" -gt 0 ] && "$ULISP_CC_BIN" --sanitize-bounds -DLUA_USE_POSIX -O2 -I "$LUA_SRC_DIR" -c -o "$LUA_SAN_OBJ/" "${SHARD_CLI[@]}"
        ) > "$LUA_SAN_OBJ/shard_${s}.log" 2>&1 &
        PIDS+=("$!")
    else
        SHARD_SCM="$LUA_SAN_OBJ/shard_${s}.scm"
        sed '$d' "$DRIVER_RUNNER" > "$SHARD_SCM"
        echo "(begin" >> "$SHARD_SCM"
        if [ "${#SHARD_CORE[@]}" -gt 0 ]; then
            printf '  (c-driver-main '\''("--sanitize-bounds" "-DLUA_USE_POSIX" "-O2" "-I" "%s" "-include-pch" "%s" "-c" "-o" "%s"' "$LUA_SRC_DIR" "$CORE_PCH_SBI" "$LUA_SAN_OBJ/" >> "$SHARD_SCM"
            for src in "${SHARD_CORE[@]}"; do printf ' "%s"' "$src" >> "$SHARD_SCM"; done
            echo '))' >> "$SHARD_SCM"
        fi
        if [ "${#SHARD_LIB[@]}" -gt 0 ]; then
            printf '  (c-driver-main '\''("--sanitize-bounds" "-DLUA_USE_POSIX" "-O2" "-I" "%s" "-include-pch" "%s" "-c" "-o" "%s"' "$LUA_SRC_DIR" "$LIB_PCH_SBI" "$LUA_SAN_OBJ/" >> "$SHARD_SCM"
            for src in "${SHARD_LIB[@]}"; do printf ' "%s"' "$src" >> "$SHARD_SCM"; done
            echo '))' >> "$SHARD_SCM"
        fi
        if [ "${#SHARD_CLI[@]}" -gt 0 ]; then
            printf '  (c-driver-main '\''("--sanitize-bounds" "-DLUA_USE_POSIX" "-O2" "-I" "%s" "-c" "-o" "%s"' "$LUA_SRC_DIR" "$LUA_SAN_OBJ/" >> "$SHARD_SCM"
            for src in "${SHARD_CLI[@]}"; do printf ' "%s"' "$src" >> "$SHARD_SCM"; done
            echo '))' >> "$SHARD_SCM"
        fi
        echo '  (exit 0))' >> "$SHARD_SCM"

        (
            if [ "${USE_GOSH:-1}" = "1" ] && command -v gosh >/dev/null 2>&1; then
                gosh -usrfi.9 -ugauche.uvector -ugauche.process -uscheme.file -uscheme.bitwise -uscheme.process-context -I "$ULISP_DIR" -I "$ROOT_DIR" "$SHARD_SCM"
            else
                PYTHONPATH="$ROOT_DIR" "$PYTHON" -m ilisp "$SHARD_SCM"
            fi
        ) > "$LUA_SAN_OBJ/shard_${s}.log" 2>&1 &
        PIDS+=("$!")
    fi
done

for idx in "${!PIDS[@]}"; do
    if ! wait "${PIDS[$idx]}"; then
        echo "ERROR: Sanitized Lua shard $idx failed:" >&2
        cat "$LUA_SAN_OBJ/shard_${idx}.log" >&2 || true
        exit 1
    fi
done

LUA_SAN_OBJS=()
for tu in "${CORE_ORDER[@]}" "${LIB_ORDER[@]}" "${CLI_TUS[@]}"; do
    LUA_SAN_OBJS+=("$LUA_SAN_OBJ/${tu}.o")
done

LUA_SAN_BIN="$BUILD_DIR/lua_ulisp_san"
"${RUN_CC[@]}" --linker=ulisp -static -nostdlib \
    "$MUSL_LIB_DIR/crt1.o" "${LUA_SAN_OBJS[@]}" "$MUSL_LIB_DIR/libc.a" \
    -o "$LUA_SAN_BIN"

TOTAL_COUNT=$((TOTAL_COUNT + 1))
readelf -sW "$LUA_SAN_OBJ/lvm.o" > "$BUILD_DIR/lvm_san.syms"
if grep -Fq "__ulisp_san_trap" "$BUILD_DIR/lvm_san.syms" && grep -Fqa "[ulisp-sanitizer]" "$LUA_SAN_BIN"; then
    echo "  [PASS] 3.1 Built sanitized static Lua 5.4.7 binary with __ulisp_san_trap & [ulisp-sanitizer] diagnostics"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  [FAIL] 3.1 Expected __ulisp_san_trap in lvm.o and [ulisp-sanitizer] in $LUA_SAN_BIN" >&2
    exit 1
fi

LUA_RUN_WS="$BUILD_DIR/lua_tests_run"
mkdir -p "$LUA_RUN_WS"
cp -r "$LUA_TESTS_DIR/." "$LUA_RUN_WS/"
DET_INIT='_U=true; do local r=math.randomseed; math.randomseed=function(a,b) if a==nil then return r(12345678,87654321) else return r(a,b) end end end'

TOTAL_COUNT=$((TOTAL_COUNT + 1))
(
    cd "$LUA_RUN_WS"
    timeout 180 "$LUA_SAN_BIN" -e "$DET_INIT" all.lua > "$BUILD_DIR/lua_san_all.out" 2>&1
)
if grep -q "final OK !!!" "$BUILD_DIR/lua_san_all.out" && ! grep -q "\[ulisp-sanitizer\]" "$BUILD_DIR/lua_san_all.out"; then
    echo "  [PASS] 3.2 Sanitized Lua 5.4.7 completed official all.lua ('final OK !!!', 0 false positives)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  [FAIL] 3.2 Sanitized Lua 5.4.7 all.lua failed or triggered unexpected trap:" >&2
    tail -n 40 "$BUILD_DIR/lua_san_all.out" >&2 || true
    exit 1
fi

echo "========================================================================"
echo " C99 Bounds & NULL Sanitizer E2E Suite (#930): $PASS_COUNT / $TOTAL_COUNT PASS"
echo "========================================================================"
