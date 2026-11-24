#!/usr/bin/env bash
# ==============================================================================
# Native AOT C99 Compiler Driver (ulisp/bin/ulisp-cc) Parity, E2E & Speed Suite
# Conforms to Issue #932 WP4 / Definition of Done
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$ULISP_DIR")"
ULISP_CC="$ULISP_DIR/bin/ulisp-cc"
DRIVER_RUNNER="$ULISP_DIR/build/c_driver_runner.scm"
GOSH_BIN="${GOSH_BIN:-$(command -v gosh 2>/dev/null || true)}"

if [ ! -x "$ULISP_CC" ]; then
  echo "ERROR: Missing native binary: $ULISP_CC" >&2
  exit 1
fi
if [ -z "$GOSH_BIN" ] || [ ! -x "$GOSH_BIN" ]; then
  echo "ERROR: Gauche (gosh) is required for SHA-256 parity and benchmark comparison" >&2
  exit 1
fi
if [ ! -f "$DRIVER_RUNNER" ]; then
  make -C "$ULISP_DIR" build/c_driver_runner.scm
fi

run_gosh_cc() {
  "$GOSH_BIN" -usrfi.9 -ugauche.uvector -ugauche.process \
    -uscheme.file -uscheme.bitwise -uscheme.process-context \
    -I "$ULISP_DIR" -I "$ROOT_DIR" "$DRIVER_RUNNER" "$@"
}

# Helper for invoking gosh c-driver-main across multiple args cleanly
run_gosh_driver_args() {
  local tmp_scm
  tmp_scm="$(mktemp --tmpdir="$WORK_DIR" gosh_drv_XXXXXX.scm)"
  sed '$d' "$DRIVER_RUNNER" > "$tmp_scm"
  printf '(begin\n  (c-driver-main (list' >> "$tmp_scm"
  for a in "$@"; do
    printf ' %s' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$a")" >> "$tmp_scm"
  done
  printf '))\n  (exit 0))\n' >> "$tmp_scm"
  "$GOSH_BIN" -usrfi.9 -ugauche.uvector -ugauche.process \
    -uscheme.file -uscheme.bitwise -uscheme.process-context \
    -I "$ULISP_DIR" -I "$ROOT_DIR" "$tmp_scm"
}

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

MUSL_DIR="$ULISP_DIR/build/third_party/musl-1.2.5"
MUSL_BUILD_DIR="$ULISP_DIR/build/musl_build"
MUSL_LIB_DIR="$MUSL_BUILD_DIR/obj/lib"
if [ ! -f "$MUSL_LIB_DIR/crt1.o" ] || [ ! -f "$MUSL_LIB_DIR/libc.a" ]; then
  echo "  [INFO] Ensuring musl-1.2.5 sysroot via tests/test_compile_musl.sh ..."
  USE_GOSH=1 bash "$ULISP_DIR/tests/test_compile_musl.sh"
fi

echo "========================================================================"
echo " Issue #932: Native AOT ulisp-cc Verification & Parity Suite"
echo "========================================================================"

# ------------------------------------------------------------------------------
# Section 1: Arbitrary CWD (/tmp) + env -u ULISP_GC_PROFILE Across All Modes
# ------------------------------------------------------------------------------
echo "[Section 1] Arbitrary CWD (/tmp) + env -u ULISP_GC_PROFILE driver smoke checks"
SEC1_DIR="$WORK_DIR/sec1"
mkdir -p "$SEC1_DIR"

cat > "$SEC1_DIR/hello.c" << 'EOF'
#include <stdio.h>
int main(void) {
  printf("hi:%d\n", 40 + 2);
  return 42;
}
EOF
cat > "$SEC1_DIR/pch_hdr.h" << 'EOF'
#define VAL_A 40
static int helper(int x) { return x + 2; }
EOF
cat > "$SEC1_DIR/pch_use.c" << 'EOF'
int main(void) { return helper(VAL_A); }
EOF
cat > "$SEC1_DIR/ret42.c" << 'EOF'
int main(void) { return 42; }
EOF

(
  cd "$SEC1_DIR"
  env -u ULISP_GC_PROFILE "$ULISP_CC" -E hello.c -o hello.i
  test -s hello.i

  env -u ULISP_GC_PROFILE "$ULISP_CC" -S hello.c -o hello.s
  test -s hello.s

  env -u ULISP_GC_PROFILE "$ULISP_CC" -c hello.c -o hello.o
  readelf -h hello.o | grep -q "REL (Relocatable file)"

  env -u ULISP_GC_PROFILE "$ULISP_CC" hello.c -o hello_host
  test -x hello_host
  set +e; ./hello_host > host.out; rc_h=$?; set -e
  [ "$rc_h" -eq 42 ]
  grep -q '^hi:42$' host.out

  env -u ULISP_GC_PROFILE "$ULISP_CC" -emit-pch pch_hdr.h -o pch_hdr.pch
  env -u ULISP_GC_PROFILE "$ULISP_CC" -include-pch pch_hdr.pch -c pch_use.c -o pch_use.o
  env -u ULISP_GC_PROFILE "$ULISP_CC" pch_use.o -o pch_bin
  set +e; ./pch_bin; rc_pch=$?; set -e
  [ "$rc_pch" -eq 42 ]

  env -u ULISP_GC_PROFILE "$ULISP_CC" --target=c hello.c -o hello_c
  set +e; ./hello_c > ctgt.out; rc_c=$?; set -e
  [ "$rc_c" -eq 42 ]
  grep -q '^hi:42$' ctgt.out

  set +e; env -u ULISP_GC_PROFILE "$ULISP_CC" --target=vm ret42.c; rc_vm=$?; set -e
  [ "$rc_vm" -eq 42 ]

  env -u ULISP_GC_PROFILE "$ULISP_CC" --linker=ulisp -static -nostdlib \
    -L "$MUSL_LIB_DIR" "$MUSL_LIB_DIR/crt1.o" ret42.c -lc -o ret42_ulisp
  test -x ret42_ulisp
  set +e; ./ret42_ulisp; rc_u=$?; set -e
  [ "$rc_u" -eq 42 ]

  if ULISP_C99_GRAMMAR="../etc/passwd" "$ULISP_CC" -S hello.c -o bad.s 2>/dev/null; then
    echo "ERROR: Unsafe ULISP_C99_GRAMMAR path was accepted!" >&2
    exit 1
  fi
)
echo "  [PASS] Section 1: All CWD=/tmp modes + unsafe grammar guard passed"

# Issue #952: Verify release binary is stripped while preserving runtime symtab and split .debug
CC_SECTIONS="$(readelf -S -W "$ULISP_CC")"
if printf '%s\n' "$CC_SECTIONS" | grep -q '\.symtab'; then
  echo "ERROR: $ULISP_CC still contains .symtab after strip!" >&2
  exit 1
fi
printf '%s\n' "$CC_SECTIONS" | grep -q 'ulisp_symtab_sec' || { echo "ERROR: Missing ulisp_symtab_sec in $ULISP_CC" >&2; exit 1; }
printf '%s\n' "$CC_SECTIONS" | grep -q 'ulisp_globals_sec' || { echo "ERROR: Missing ulisp_globals_sec in $ULISP_CC" >&2; exit 1; }
printf '%s\n' "$CC_SECTIONS" | grep -q '\.gnu_debuglink' || { echo "ERROR: Missing .gnu_debuglink in $ULISP_CC" >&2; exit 1; }
test -s "${ULISP_CC}.debug" || { echo "ERROR: Missing split debug file ${ULISP_CC}.debug" >&2; exit 1; }
[ "$(nm "${ULISP_CC}.debug" | grep -c 'ulisp_fn_')" -gt 0 ] || { echo "ERROR: ${ULISP_CC}.debug missing symbols" >&2; exit 1; }
echo "  [PASS] Section 1b: Stripped binary + split .debug + runtime symtab verified (#952)"

# ------------------------------------------------------------------------------
# Section 2: 100% SHA-256 Bit-Exact Parity vs gosh c_driver_runner.scm
# ------------------------------------------------------------------------------
echo "[Section 2] SHA-256 bit-exact parity vs gosh (C99 TU, musl TU, Lua 33 TUs + Pass 144 static lua)"
SEC2_DIR="$WORK_DIR/sec2"
mkdir -p "$SEC2_DIR"

cat > "$SEC2_DIR/parity_tu.c" << 'EOF'
int accum(int n) {
  int s = 0;
  for (int i = 1; i <= n; i++) s += i * 3;
  return s;
}
int main(void) { return accum(10) - 123; }
EOF

"$ULISP_CC" -S -O2 "$SEC2_DIR/parity_tu.c" -o "$SEC2_DIR/native.s"
run_gosh_cc -S -O2 "$SEC2_DIR/parity_tu.c" -o "$SEC2_DIR/gosh.s"
SHA_S_NATIVE="$(sha256sum "$SEC2_DIR/native.s" | awk '{print $1}')"
SHA_S_GOSH="$(sha256sum "$SEC2_DIR/gosh.s" | awk '{print $1}')"
[ "$SHA_S_NATIVE" = "$SHA_S_GOSH" ] || { echo "ERROR: -S asm SHA-256 mismatch ($SHA_S_NATIVE vs $SHA_S_GOSH)" >&2; exit 1; }

"$ULISP_CC" -c -O2 "$SEC2_DIR/parity_tu.c" -o "$SEC2_DIR/native.o"
run_gosh_cc -c -O2 "$SEC2_DIR/parity_tu.c" -o "$SEC2_DIR/gosh.o"
SHA_O_NATIVE="$(sha256sum "$SEC2_DIR/native.o" | awk '{print $1}')"
SHA_O_GOSH="$(sha256sum "$SEC2_DIR/gosh.o" | awk '{print $1}')"
[ "$SHA_O_NATIVE" = "$SHA_O_GOSH" ] || { echo "ERROR: -c obj SHA-256 mismatch ($SHA_O_NATIVE vs $SHA_O_GOSH)" >&2; exit 1; }
echo "  [PASS] C99 TU -S & -c SHA-256 identical ($SHA_O_NATIVE)"

MUSL_GEN_DIR="$SEC2_DIR/musl_gen"
mkdir -p "$MUSL_GEN_DIR/include/bits" "$MUSL_GEN_DIR/src/internal"
sed -f "$MUSL_DIR/tools/mkalltypes.sed" \
  "$MUSL_DIR/arch/x86_64/bits/alltypes.h.in" \
  "$MUSL_DIR/include/alltypes.h.in" > "$MUSL_GEN_DIR/include/bits/alltypes.h"
cp -f "$MUSL_DIR/arch/x86_64/bits/syscall.h.in" "$MUSL_GEN_DIR/include/bits/syscall.h"
sed -n -e 's/__NR_/SYS_/p' < "$MUSL_DIR/arch/x86_64/bits/syscall.h.in" >> "$MUSL_GEN_DIR/include/bits/syscall.h"
cp -f "$MUSL_DIR/arch/arm/bits/float.h" "$MUSL_GEN_DIR/include/bits/float.h"
printf '#define VERSION "1.2.5"\n' > "$MUSL_GEN_DIR/src/internal/version.h"

MUSL_SRC="$MUSL_DIR/src/stdlib/qsort_nr.c"
MUSL_CFLAGS=(
  -D_XOPEN_SOURCE=700 -nostdinc
  -I "$MUSL_GEN_DIR/include"
  -I "$MUSL_DIR/arch/x86_64"
  -I "$MUSL_DIR/arch/generic"
  -I "$MUSL_GEN_DIR/src/internal"
  -I "$MUSL_DIR/src/include"
  -I "$MUSL_DIR/src/internal"
  -I "$MUSL_DIR/include"
)
"$ULISP_CC" "${MUSL_CFLAGS[@]}" -c "$MUSL_SRC" -o "$SEC2_DIR/musl_native.o"
run_gosh_driver_args "${MUSL_CFLAGS[@]}" -c "$MUSL_SRC" -o "$SEC2_DIR/musl_gosh.o"
SHA_MUSL_NATIVE="$(sha256sum "$SEC2_DIR/musl_native.o" | awk '{print $1}')"
SHA_MUSL_GOSH="$(sha256sum "$SEC2_DIR/musl_gosh.o" | awk '{print $1}')"
[ "$SHA_MUSL_NATIVE" = "$SHA_MUSL_GOSH" ] || { echo "ERROR: musl TU SHA-256 mismatch ($SHA_MUSL_NATIVE vs $SHA_MUSL_GOSH)" >&2; exit 1; }
echo "  [PASS] musl TU (qsort_nr.c) SHA-256 identical ($SHA_MUSL_NATIVE)"

# Ensure Lua 5.4.7 sources are present
LUA_SRC_DIR="$ULISP_DIR/build/third_party/lua-5.4.7/src"
if [ ! -f "$LUA_SRC_DIR/lvm.c" ]; then
  USE_GOSH=1 bash "$ULISP_DIR/tests/test_compile_lua.sh"
fi

LUA_TUS=(
  lapi lcode lctype ldebug ldo ldump lfunc lgc llex lmem
  lobject lopcodes lparser lstate lstring ltable ltm lundump lvm lzio
  lauxlib lbaselib lcorolib ldblib liolib lmathlib
  loadlib loslib lstrlib ltablib lutf8lib linit lua
)
CORE_ORDER=(lvm lparser lcode lapi lgc ldo lobject ltable llex ldebug lstate lfunc lstring lundump ldump lopcodes ltm lmem lzio lctype)
LIB_ORDER=(lstrlib lauxlib lbaselib liolib loadlib ldblib lmathlib ltablib loslib lcorolib lutf8lib linit)

build_lua_tree() {
  local mode="$1"
  local out_dir="$2"
  local bin_out="$3"
  local jobs=4
  rm -rf "$out_dir"
  mkdir -p "$out_dir"

  local core_hdr="$out_dir/lua_core_pch.h"
  local lib_hdr="$out_dir/lua_lib_pch.h"
  local core_pch="$out_dir/lua_core_pch.h.sbi"
  local lib_pch="$out_dir/lua_lib_pch.h.sbi"
  cat > "$core_hdr" << 'EOF'
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
  cat > "$lib_hdr" << 'EOF'
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

  if [ "$mode" = "native" ]; then
    "$ULISP_CC" -emit-pch -DLUA_USE_POSIX -I "$LUA_SRC_DIR" "$core_hdr" -o "$core_pch" &
    local p1=$!
    "$ULISP_CC" -emit-pch -DLUA_USE_POSIX -I "$LUA_SRC_DIR" "$lib_hdr" -o "$lib_pch" &
    local p2=$!
    wait "$p1" "$p2"
  else
    run_gosh_driver_args -emit-pch -DLUA_USE_POSIX -I "$LUA_SRC_DIR" "$core_hdr" -o "$core_pch" &
    local p1=$!
    run_gosh_driver_args -emit-pch -DLUA_USE_POSIX -I "$LUA_SRC_DIR" "$lib_hdr" -o "$lib_pch" &
    local p2=$!
    wait "$p1" "$p2"
  fi

  local pids=()
  for ((s = 0; s < jobs; s++)); do
    local sc=() sl=() scli=()
    for ((i = s; i < ${#CORE_ORDER[@]}; i += jobs)); do sc+=("$LUA_SRC_DIR/${CORE_ORDER[$i]}.c"); done
    local rev_s=$((jobs - 1 - s))
    for ((i = rev_s; i < ${#LIB_ORDER[@]}; i += jobs)); do sl+=("$LUA_SRC_DIR/${LIB_ORDER[$i]}.c"); done
    if [ "$s" -eq $((jobs - 1)) ]; then scli+=("$LUA_SRC_DIR/lua.c"); fi

    if [ "$mode" = "native" ]; then
      (
        if [ "${#sc[@]}" -gt 0 ]; then "$ULISP_CC" -DLUA_USE_POSIX -O2 -I "$LUA_SRC_DIR" -include-pch "$core_pch" -c -o "$out_dir/" "${sc[@]}"; fi
        if [ "${#sl[@]}" -gt 0 ]; then "$ULISP_CC" -DLUA_USE_POSIX -O2 -I "$LUA_SRC_DIR" -include-pch "$lib_pch" -c -o "$out_dir/" "${sl[@]}"; fi
        if [ "${#scli[@]}" -gt 0 ]; then "$ULISP_CC" -DLUA_USE_POSIX -O2 -I "$LUA_SRC_DIR" -c -o "$out_dir/" "${scli[@]}"; fi
      ) &
      pids+=("$!")
    else
      local scm="$out_dir/gosh_shard_${s}.scm"
      sed '$d' "$DRIVER_RUNNER" > "$scm"
      printf '(begin\n' >> "$scm"
      if [ "${#sc[@]}" -gt 0 ]; then
        printf '  (c-driver-main (list "-DLUA_USE_POSIX" "-O2" "-I" "%s" "-include-pch" "%s" "-c" "-o" "%s"' "$LUA_SRC_DIR" "$core_pch" "$out_dir/" >> "$scm"
        for f in "${sc[@]}"; do printf ' "%s"' "$f" >> "$scm"; done
        printf '))\n' >> "$scm"
      fi
      if [ "${#sl[@]}" -gt 0 ]; then
        printf '  (c-driver-main (list "-DLUA_USE_POSIX" "-O2" "-I" "%s" "-include-pch" "%s" "-c" "-o" "%s"' "$LUA_SRC_DIR" "$lib_pch" "$out_dir/" >> "$scm"
        for f in "${sl[@]}"; do printf ' "%s"' "$f" >> "$scm"; done
        printf '))\n' >> "$scm"
      fi
      if [ "${#scli[@]}" -gt 0 ]; then
        printf '  (c-driver-main (list "-DLUA_USE_POSIX" "-O2" "-I" "%s" "-c" "-o" "%s"' "$LUA_SRC_DIR" "$out_dir/" >> "$scm"
        for f in "${scli[@]}"; do printf ' "%s"' "$f" >> "$scm"; done
        printf '))\n' >> "$scm"
      fi
      printf '  (exit 0))\n' >> "$scm"
      "$GOSH_BIN" -usrfi.9 -ugauche.uvector -ugauche.process -uscheme.file -uscheme.bitwise -uscheme.process-context -I "$ULISP_DIR" -I "$ROOT_DIR" "$scm" &
      pids+=("$!")
    fi
  done
  for p in "${pids[@]}"; do wait "$p"; done

  local objs=()
  for tu in "${LUA_TUS[@]}"; do objs+=("$out_dir/${tu}.o"); done
  if [ "$mode" = "native" ]; then
    "$ULISP_CC" --linker=ulisp -static -nostdlib "$MUSL_LIB_DIR/crt1.o" "${objs[@]}" "$MUSL_LIB_DIR/libc.a" -o "$bin_out"
  else
    run_gosh_driver_args --linker=ulisp -static -nostdlib "$MUSL_LIB_DIR/crt1.o" "${objs[@]}" "$MUSL_LIB_DIR/libc.a" -o "$bin_out"
  fi
}

T_LUA_NATIVE_0="$(date +%s%N)"
build_lua_tree native "$SEC2_DIR/lua_native" "$SEC2_DIR/lua_native_bin"
T_LUA_NATIVE_1="$(date +%s%N)"

T_LUA_GOSH_0="$(date +%s%N)"
build_lua_tree gosh "$SEC2_DIR/lua_gosh" "$SEC2_DIR/lua_gosh_bin"
T_LUA_GOSH_1="$(date +%s%N)"

for tu in "${LUA_TUS[@]}"; do
  s1="$(sha256sum "$SEC2_DIR/lua_native/${tu}.o" | awk '{print $1}')"
  s2="$(sha256sum "$SEC2_DIR/lua_gosh/${tu}.o" | awk '{print $1}')"
  if [ "$s1" != "$s2" ]; then
    echo "ERROR: Lua TU ${tu}.o SHA-256 mismatch ($s1 vs $s2)" >&2
    exit 1
  fi
done
echo "  [PASS] All 33 Lua 5.4.7 .o objects are 100% SHA-256 bit-identical"

SHA_LUA_NATIVE="$(sha256sum "$SEC2_DIR/lua_native_bin" | awk '{print $1}')"
SHA_LUA_GOSH="$(sha256sum "$SEC2_DIR/lua_gosh_bin" | awk '{print $1}')"
[ "$SHA_LUA_NATIVE" = "$SHA_LUA_GOSH" ] || { echo "ERROR: Pass 144 static lua binary SHA-256 mismatch ($SHA_LUA_NATIVE vs $SHA_LUA_GOSH)" >&2; exit 1; }
echo "  [PASS] Pass 144 static ELF64 lua binary 100% SHA-256 identical ($SHA_LUA_NATIVE)"

# ------------------------------------------------------------------------------
# Section 3: Full E2E Regression Suite with ULISP_CC_BIN=ulisp/bin/ulisp-cc
# ------------------------------------------------------------------------------
echo "[Section 3] Full E2E regression suite under ULISP_CC_BIN=$ULISP_CC"
export ULISP_CC_BIN="$ULISP_CC"
make -C "$ULISP_DIR" build/fuzz_xmm_float_runner.scm test_elf_static_linker

USE_GOSH=1 bash "$ULISP_DIR/tests/test_c99_e2e_hello.sh"
USE_GOSH=1 bash "$ULISP_DIR/tests/test_c99_floating_point.sh"
USE_GOSH=1 bash "$ULISP_DIR/tests/test_sse2_xmm_abi.sh"
USE_GOSH=1 FUZZ_COUNT=120 bash "$ULISP_DIR/tests/test_fuzz_xmm_float.sh"
USE_GOSH=1 bash "$ULISP_DIR/tests/test_elf_static_linker.sh"
REBUILD_LUA=1 bash "$ULISP_DIR/tests/test_compile_lua.sh"
bash "$ULISP_DIR/tests/test_lua_selfhost_e2e.sh"

# ------------------------------------------------------------------------------
# Section 4: Performance Benchmark (>= 5.0x speedup vs gosh)
# ------------------------------------------------------------------------------
echo "[Section 4] Performance benchmarks: gosh vs native bin/ulisp-cc"
FUZZ_BENCH_DIR="$WORK_DIR/fuzz500"
mkdir -p "$FUZZ_BENCH_DIR"
FUZZ_SEED=20261122 FUZZ_COUNT=500 FUZZ_OUT_DIR="$FUZZ_BENCH_DIR" \
  "$GOSH_BIN" -usrfi.9 -ugauche.uvector -ugauche.process -uscheme.file -uscheme.bitwise -uscheme.process-context \
  -I "$ULISP_DIR" -I "$ROOT_DIR" "$ULISP_DIR/build/fuzz_xmm_float_runner.scm" >/dev/null

T_FZ_G0="$(date +%s%N)"
run_gosh_cc -O2 -c "$FUZZ_BENCH_DIR/fuzz_suite.c" -o "$FUZZ_BENCH_DIR/fuzz_gosh.o"
T_FZ_G1="$(date +%s%N)"

T_FZ_N0="$(date +%s%N)"
"$ULISP_CC" -O2 -c "$FUZZ_BENCH_DIR/fuzz_suite.c" -o "$FUZZ_BENCH_DIR/fuzz_native.o"
T_FZ_N1="$(date +%s%N)"

[ "$(sha256sum "$FUZZ_BENCH_DIR/fuzz_gosh.o" | awk '{print $1}')" = "$(sha256sum "$FUZZ_BENCH_DIR/fuzz_native.o" | awk '{print $1}')" ] || {
  echo "ERROR: FUZZ_COUNT=500 .o SHA-256 mismatch" >&2; exit 1;
}

python3 - "$T_FZ_G0" "$T_FZ_G1" "$T_FZ_N0" "$T_FZ_N1" "$T_LUA_GOSH_0" "$T_LUA_GOSH_1" "$T_LUA_NATIVE_0" "$T_LUA_NATIVE_1" << 'PYEOF'
import sys
fg0, fg1, fn0, fn1, lg0, lg1, ln0, ln1 = [int(x) for x in sys.argv[1:]]
fuzz_gosh = (fg1 - fg0) / 1e9
fuzz_native = (fn1 - fn0) / 1e9
fuzz_ratio = fuzz_gosh / fuzz_native
lua_gosh = (lg1 - lg0) / 1e9
lua_native = (ln1 - ln0) / 1e9
lua_ratio = lua_gosh / lua_native
print(f"  [BENCH] FUZZ_COUNT=500 (-O2 -c): gosh={fuzz_gosh:.3f}s vs ulisp-cc={fuzz_native:.3f}s => {fuzz_ratio:.2f}x speedup")
print(f"  [BENCH] Lua 5.4.7 (33 TUs + link): gosh={lua_gosh:.3f}s vs ulisp-cc={lua_native:.3f}s => {lua_ratio:.2f}x speedup")
assert fuzz_ratio >= 5.0, f"FUZZ_COUNT=500 speedup {fuzz_ratio:.2f}x < 5.0x"
assert lua_ratio >= 5.0, f"Lua 33 TU speedup {lua_ratio:.2f}x < 5.0x"
print("  [PASS] Both benchmarks exceed >= 5.0x speedup target!")
PYEOF

echo "========================================================================"
echo " [RESULT] ALL Issue #932 Native AOT Driver Checks PASSED"
echo "========================================================================"
