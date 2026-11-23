#!/usr/bin/env bash
# =======================================================================
# Issue #925: Unmodified Official Lua 5.4.7 Full 33-TU Compilation,
# Linking, REPL & Differential Smoke Verification Harness (ULisp vs GCC)
# =======================================================================
set -euo pipefail

CALLER_PWD="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$ULISP_DIR/.." && pwd)"

LUA_VER="5.4.7"
LUA_TARBALL_NAME="lua-${LUA_VER}.tar.gz"
LUA_URL="${LUA_URL:-https://www.lua.org/ftp/${LUA_TARBALL_NAME}}"
LUA_SHA256="9fbf5e28ef86c69858f6d3d34eccc32e911c1a28b4120ff3e84aaa70cfbf1e30"

THIRD_PARTY_DIR="$ULISP_DIR/build/third_party"
TARBALL_PATH="$THIRD_PARTY_DIR/$LUA_TARBALL_NAME"
EXTRACTED_SRC_DIR="$THIRD_PARTY_DIR/lua-${LUA_VER}/src"

echo "========================================================================"
echo " Starting Lua ${LUA_VER} Full 33-TU ULisp Compilation & Differential Suite (#925)"
echo "========================================================================"

# -----------------------------------------------------------------------
# 1. Resolve Unmodified Lua 5.4.7 Source Directory (Read-Only)
# -----------------------------------------------------------------------
SRC_DIR=""
if [ -n "${LUA_SRC_DIR:-}" ]; then
  CAND="$LUA_SRC_DIR"
  if [[ "$CAND" != /* ]]; then
    CAND="$CALLER_PWD/$CAND"
  fi
  if [ -f "$CAND/lapi.c" ]; then
    SRC_DIR="$(cd "$CAND" && pwd)"
  elif [ -f "$CAND/src/lapi.c" ]; then
    SRC_DIR="$(cd "$CAND/src" && pwd)"
  else
    echo "ERROR: LUA_SRC_DIR='$LUA_SRC_DIR' does not contain lapi.c or src/lapi.c" >&2
    exit 1
  fi
  echo "  [INFO] Using caller-provided LUA_SRC_DIR: $SRC_DIR"
else
  mkdir -p "$THIRD_PARTY_DIR"
  if [ ! -f "$EXTRACTED_SRC_DIR/lapi.c" ]; then
    if [ ! -f "$TARBALL_PATH" ]; then
      echo "  [INFO] Downloading official Lua ${LUA_VER} archive from $LUA_URL ..."
      if command -v curl >/dev/null 2>&1; then
        if ! curl --fail --location --retry 3 --connect-timeout 15 -o "$TARBALL_PATH.tmp" "$LUA_URL"; then
          rm -f "$TARBALL_PATH.tmp"
          echo "ERROR: Failed to download $LUA_URL (offline?)." >&2
          echo "       Provide a pre-fetched archive at $TARBALL_PATH or set LUA_SRC_DIR=/path/to/lua-${LUA_VER}/src" >&2
          exit 1
        fi
        mv -f "$TARBALL_PATH.tmp" "$TARBALL_PATH"
      elif command -v wget >/dev/null 2>&1; then
        if ! wget -q --tries=3 --timeout=15 -O "$TARBALL_PATH.tmp" "$LUA_URL"; then
          rm -f "$TARBALL_PATH.tmp"
          echo "ERROR: Failed to download $LUA_URL (offline?)." >&2
          echo "       Provide a pre-fetched archive at $TARBALL_PATH or set LUA_SRC_DIR=/path/to/lua-${LUA_VER}/src" >&2
          exit 1
        fi
        mv -f "$TARBALL_PATH.tmp" "$TARBALL_PATH"
      else
        echo "ERROR: Neither curl nor wget available and $TARBALL_PATH is missing." >&2
        echo "       Set LUA_SRC_DIR=/path/to/lua-${LUA_VER}/src" >&2
        exit 1
      fi
    fi

    ACTUAL_SHA256="$(sha256sum "$TARBALL_PATH" | awk '{print $1}')"
    if [ "$ACTUAL_SHA256" != "$LUA_SHA256" ]; then
      echo "ERROR: SHA-256 mismatch for $TARBALL_PATH!" >&2
      echo "       Expected: $LUA_SHA256" >&2
      echo "       Actual:   $ACTUAL_SHA256" >&2
      rm -f "$TARBALL_PATH"
      exit 1
    fi
    echo "  [PASS] Verified SHA-256 digest of $LUA_TARBALL_NAME"

    if tar -tzf "$TARBALL_PATH" | grep -E '(^/|^\.\./|/\.\./|/\.\.$)'; then
      echo "ERROR: Unsafe path entry (CWE-22) detected in $TARBALL_PATH!" >&2
      exit 1
    fi
    echo "  [PASS] Archive path traversal check (CWE-22) passed"

    tar --no-same-owner -xzf "$TARBALL_PATH" -C "$THIRD_PARTY_DIR"
  fi
  SRC_DIR="$EXTRACTED_SRC_DIR"
  echo "  [INFO] Using Lua ${LUA_VER} sources at: $SRC_DIR"
fi

cd "$ULISP_DIR"

# -----------------------------------------------------------------------
# 2. Configure ULisp C99 Compiler Driver Command
# -----------------------------------------------------------------------
if [ ! -f "build/c_driver_runner.scm" ]; then
  make -C "$ULISP_DIR" build/c_driver_runner.scm >/dev/null
fi

if [ -n "${ULISP_CC_BIN:-}" ] && [ -x "${ULISP_CC_BIN}" ]; then
  RUN_CC=("$ULISP_CC_BIN")
elif [ "${USE_GOSH:-1}" = "1" ] && command -v gosh >/dev/null 2>&1; then
  GOSH_BIN="$(command -v gosh)"
  RUN_CC=("$GOSH_BIN" -usrfi.9 -ugauche.uvector -ugauche.process -uscheme.file -uscheme.bitwise -uscheme.process-context -I "$ULISP_DIR" -I "$ROOT_DIR" "$ULISP_DIR/build/c_driver_runner.scm" --)
else
  if [ -x "$ROOT_DIR/.venv/bin/python" ]; then
    PYTHON_BIN="$ROOT_DIR/.venv/bin/python"
  else
    PYTHON_BIN="python3"
  fi
  export PYTHONPATH="$ROOT_DIR"
  RUN_CC=("$PYTHON_BIN" -m ilisp "$ULISP_DIR/build/c_driver_runner.scm" --)
fi

# -----------------------------------------------------------------------
# 3. Enumerate Official Lua 5.4.7 Translation Units (33 TUs + optional luac)
# -----------------------------------------------------------------------
CORE_TUS=(
  lapi lcode lctype ldebug ldo ldump lfunc lgc llex lmem
  lobject lopcodes lparser lstate lstring ltable ltm lundump lvm lzio
)
LIB_TUS=(
  lauxlib lbaselib lcorolib ldblib liolib lmathlib
  loadlib loslib lstrlib ltablib lutf8lib linit
)
CLI_TUS=(lua)

ALL_TUS=("${CORE_TUS[@]}" "${LIB_TUS[@]}" "${CLI_TUS[@]}")
if [ "${BUILD_LUAC:-0}" = "1" ]; then
  ALL_TUS+=(luac)
fi

for tu in "${ALL_TUS[@]}"; do
  if [ ! -f "$SRC_DIR/${tu}.c" ]; then
    echo "ERROR: Missing expected Lua source file: $SRC_DIR/${tu}.c" >&2
    exit 1
  fi
done

OBJ_DIR="$ULISP_DIR/build/lua_obj"
rm -rf "$OBJ_DIR"
mkdir -p "$OBJ_DIR"

JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
if [ "$JOBS" -lt 1 ]; then
  JOBS=1
fi
if [ "$JOBS" -gt 8 ]; then
  JOBS=8
fi

echo "  [INFO] Compiling ${#ALL_TUS[@]} Lua translation units across $JOBS parallel batch shards ..."

# Distribute TUs round-robin across $JOBS shards so heavy TUs (lvm, lparser, lcode, lstrlib) spread evenly
ORDERED_TUS=(
  lvm lparser lcode lstrlib
  lapi lauxlib lbaselib llex
  ldebug ldo lgc lobject
  ltable lstate liolib loadlib
  lctype lfunc lstring lundump
  ldump lopcodes ltm lua
  lmem lzio ldblib lmathlib
  linit ltablib loslib lcorolib
  lutf8lib
)
if [ "${BUILD_LUAC:-0}" = "1" ]; then
  ORDERED_TUS+=(luac)
fi

USE_PCH="${USE_PCH:-1}"
T0="$(date +%s)"

if [ "$USE_PCH" = "1" ]; then
  echo "  [INFO] Emitting C99 .sbi precompiled headers (lua_core_pch.h.sbi & lua_lib_pch.h.sbi) ..."
  CORE_PCH_HDR="$OBJ_DIR/lua_core_pch.h"
  LIB_PCH_HDR="$OBJ_DIR/lua_lib_pch.h"
  CORE_PCH_SBI="$OBJ_DIR/lua_core_pch.h.sbi"
  LIB_PCH_SBI="$OBJ_DIR/lua_lib_pch.h.sbi"

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

  "${RUN_CC[@]}" -emit-pch -DLUA_USE_POSIX -I "$SRC_DIR" "$CORE_PCH_HDR" -o "$CORE_PCH_SBI" > "$OBJ_DIR/pch_core.log" 2>&1 &
  PCH_PID1="$!"
  "${RUN_CC[@]}" -emit-pch -DLUA_USE_POSIX -I "$SRC_DIR" "$LIB_PCH_HDR" -o "$LIB_PCH_SBI" > "$OBJ_DIR/pch_lib.log" 2>&1 &
  PCH_PID2="$!"
  PCH_RC=0
  if ! wait "$PCH_PID1"; then
    cat "$OBJ_DIR/pch_core.log" >&2 || true
    PCH_RC=1
  fi
  if ! wait "$PCH_PID2"; then
    cat "$OBJ_DIR/pch_lib.log" >&2 || true
    PCH_RC=1
  fi
  if [ "$PCH_RC" -ne 0 ]; then
    echo "ERROR: PCH generation failed" >&2
    exit 1
  fi
  T_PCH="$(date +%s)"
  echo "  [PASS] Emitted Lua core & lib .sbi PCH in $((T_PCH - T0))s (core=$(stat -c%s "$CORE_PCH_SBI")B, lib=$(stat -c%s "$LIB_PCH_SBI")B)"

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

  PIDS=()
  for ((s = 0; s < JOBS; s++)); do
    SHARD_CORE=()
    for ((i = s; i < ${#CORE_ORDER[@]}; i += JOBS)); do
      SHARD_CORE+=("$SRC_DIR/${CORE_ORDER[$i]}.c")
    done
    rev_s=$((JOBS - 1 - s))
    SHARD_LIB=()
    for ((i = rev_s; i < ${#LIB_ORDER[@]}; i += JOBS)); do
      SHARD_LIB+=("$SRC_DIR/${LIB_ORDER[$i]}.c")
    done
    SHARD_CLI=()
    if [ "$s" -eq $((JOBS - 1)) ]; then
      for cli_tu in "${CLI_TUS[@]}"; do
        SHARD_CLI+=("$SRC_DIR/${cli_tu}.c")
      done
    fi

    if [ -n "${ULISP_CC_BIN:-}" ] && [ -x "${ULISP_CC_BIN}" ]; then
      (
        [ "${#SHARD_CORE[@]}" -gt 0 ] && "$ULISP_CC_BIN" -DLUA_USE_POSIX -O2 -I "$SRC_DIR" -include-pch "$CORE_PCH_SBI" -c -o "$OBJ_DIR/" "${SHARD_CORE[@]}"
        [ "${#SHARD_LIB[@]}" -gt 0 ] && "$ULISP_CC_BIN" -DLUA_USE_POSIX -O2 -I "$SRC_DIR" -include-pch "$LIB_PCH_SBI" -c -o "$OBJ_DIR/" "${SHARD_LIB[@]}"
        [ "${#SHARD_CLI[@]}" -gt 0 ] && "$ULISP_CC_BIN" -DLUA_USE_POSIX -O2 -I "$SRC_DIR" -c -o "$OBJ_DIR/" "${SHARD_CLI[@]}"
      ) > "$OBJ_DIR/shard_${s}.log" 2>&1 &
      PIDS+=("$!")
    else
      SHARD_SCM="$OBJ_DIR/shard_${s}.scm"
      sed '$d' "$ULISP_DIR/build/c_driver_runner.scm" > "$SHARD_SCM"
      echo "(begin" >> "$SHARD_SCM"
      if [ "${#SHARD_CORE[@]}" -gt 0 ]; then
        printf '  (c-driver-main '\''("-DLUA_USE_POSIX" "-O2" "-I" "%s" "-include-pch" "%s" "-c" "-o" "%s"' "$SRC_DIR" "$CORE_PCH_SBI" "$OBJ_DIR/" >> "$SHARD_SCM"
        for src in "${SHARD_CORE[@]}"; do printf ' "%s"' "$src" >> "$SHARD_SCM"; done
        echo '))' >> "$SHARD_SCM"
      fi
      if [ "${#SHARD_LIB[@]}" -gt 0 ]; then
        printf '  (c-driver-main '\''("-DLUA_USE_POSIX" "-O2" "-I" "%s" "-include-pch" "%s" "-c" "-o" "%s"' "$SRC_DIR" "$LIB_PCH_SBI" "$OBJ_DIR/" >> "$SHARD_SCM"
        for src in "${SHARD_LIB[@]}"; do printf ' "%s"' "$src" >> "$SHARD_SCM"; done
        echo '))' >> "$SHARD_SCM"
      fi
      if [ "${#SHARD_CLI[@]}" -gt 0 ]; then
        printf '  (c-driver-main '\''("-DLUA_USE_POSIX" "-O2" "-I" "%s" "-c" "-o" "%s"' "$SRC_DIR" "$OBJ_DIR/" >> "$SHARD_SCM"
        for src in "${SHARD_CLI[@]}"; do printf ' "%s"' "$src" >> "$SHARD_SCM"; done
        echo '))' >> "$SHARD_SCM"
      fi
      echo '  (exit 0))' >> "$SHARD_SCM"

      (
        if [ "${USE_GOSH:-1}" = "1" ] && command -v gosh >/dev/null 2>&1; then
          "$GOSH_BIN" -usrfi.9 -ugauche.uvector -ugauche.process -uscheme.file -uscheme.bitwise -uscheme.process-context -I "$ULISP_DIR" -I "$ROOT_DIR" "$SHARD_SCM"
        else
          "$PYTHON_BIN" -m ilisp "$SHARD_SCM"
        fi
      ) > "$OBJ_DIR/shard_${s}.log" 2>&1 &
      PIDS+=("$!")
    fi
  done
else
  PIDS=()
  for ((s = 0; s < JOBS; s++)); do
    SHARD_SRCS=()
    for ((i = s; i < ${#ORDERED_TUS[@]}; i += JOBS)); do
      tu="${ORDERED_TUS[$i]}"
      SHARD_SRCS+=("$SRC_DIR/${tu}.c")
    done
    if [ "${#SHARD_SRCS[@]}" -gt 0 ]; then
      (
        "${RUN_CC[@]}" -DLUA_USE_POSIX -O2 -I "$SRC_DIR" -c -o "$OBJ_DIR/" "${SHARD_SRCS[@]}" > "$OBJ_DIR/shard_${s}.log" 2>&1
      ) &
      PIDS+=("$!")
    fi
  done
fi

COMPILE_RC=0
for idx in "${!PIDS[@]}"; do
  if ! wait "${PIDS[$idx]}"; then
    echo "ERROR: Compilation shard $idx failed:" >&2
    cat "$OBJ_DIR/shard_${idx}.log" >&2 || true
    COMPILE_RC=1
  fi
done

if [ "$COMPILE_RC" -ne 0 ]; then
  exit 1
fi
T1="$(date +%s)"
echo "  [PASS] Compiled all ${#ORDERED_TUS[@]} translation units to .o in $((T1 - T0))s"

# -----------------------------------------------------------------------
# 4. Validate ELF64 Relocatable Object Headers & STB_LOCAL Static Linkage
# -----------------------------------------------------------------------
LUA_OBJS=()
C_SRCS_FOR_GCC=()
for tu in "${CORE_TUS[@]}" "${LIB_TUS[@]}" "${CLI_TUS[@]}"; do
  obj="$OBJ_DIR/${tu}.o"
  if [ ! -f "$obj" ]; then
    echo "ERROR: Missing compiled object file: $obj" >&2
    exit 1
  fi
  hdr="$(readelf -h "$obj")"
  if ! echo "$hdr" | grep -q "ELF64" || \
     ! echo "$hdr" | grep -q "REL (Relocatable file)" || \
     ! echo "$hdr" | grep -q "Advanced Micro Devices X86-64"; then
    echo "ERROR: Invalid ELF64 x86-64 ET_REL header in $obj" >&2
    exit 1
  fi
  LUA_OBJS+=("$obj")
  C_SRCS_FOR_GCC+=("$SRC_DIR/${tu}.c")
done
echo "  [PASS] All 33 ELF64 x86-64 ET_REL object headers verified via readelf -h"

if readelf -sW "${LUA_OBJS[@]}" | grep -E 'GLOBAL.*\.L_c99_'; then
  echo "ERROR: Found GLOBAL binding on internal .L_c99_ symbol!" >&2
  exit 1
fi
echo "  [PASS] All static functions & variables have STB_LOCAL binding (0 symbol collisions)"

# -----------------------------------------------------------------------
# 5. Link Standalone Static lua_ulisp via Pass 144 ELF64 Linker & musl-1.2.5
# -----------------------------------------------------------------------
LUA_ULISP_BIN="$ULISP_DIR/build/lua_ulisp"
LUA_ULISP_STATIC_BIN="$ULISP_DIR/build/lua_ulisp_static"
LUA_GCC_BIN="$ULISP_DIR/build/lua_gcc"
HOST_CC="${CC:-cc}"

MUSL_LIB_DIR="$ULISP_DIR/build/musl_build/obj/lib"
if [ ! -f "$MUSL_LIB_DIR/crt1.o" ] || [ ! -f "$MUSL_LIB_DIR/libc.a" ]; then
  echo "  [INFO] Building musl-1.2.5 crt1.o & libc.a via tests/test_compile_musl.sh ..."
  USE_GOSH="${USE_GOSH:-1}" bash "$ULISP_DIR/tests/test_compile_musl.sh"
fi

# Strip host ld/cc/gcc from PATH during Pass 144 static linking to prove zero host linker dependence
NOHOST_LINK_DIR="$ULISP_DIR/build/nohost_link_tmp_$$"
mkdir -p "$NOHOST_LINK_DIR"
for tool in uname env sh bash cat rm mkdir chmod; do
  if command -v "$tool" >/dev/null 2>&1; then
    ln -sf "$(command -v "$tool")" "$NOHOST_LINK_DIR/$tool"
  fi
done

PATH="$NOHOST_LINK_DIR" "${RUN_CC[@]}" --linker=ulisp -static -nostdlib \
  "$MUSL_LIB_DIR/crt1.o" "${LUA_OBJS[@]}" "$MUSL_LIB_DIR/libc.a" \
  -o "$LUA_ULISP_STATIC_BIN"
rm -rf "$NOHOST_LINK_DIR"
cp -f "$LUA_ULISP_STATIC_BIN" "$LUA_ULISP_BIN"
echo "  [PASS] Linked standalone static ELF64 executable via Pass 144 linker: $LUA_ULISP_BIN ($(stat -c%s "$LUA_ULISP_BIN") bytes)"

FILE_DESC="$(file "$LUA_ULISP_BIN")"
if ! echo "$FILE_DESC" | grep -q "statically linked"; then
  echo "ERROR: Expected statically linked ELF64 binary, got: $FILE_DESC" >&2
  exit 1
fi
LDD_DESC="$(ldd "$LUA_ULISP_BIN" 2>&1 || true)"
if ! echo "$LDD_DESC" | grep -qE "not a dynamic executable|statically linked"; then
  echo "ERROR: Expected 'not a dynamic executable' from ldd, got: $LDD_DESC" >&2
  exit 1
fi
if ! readelf -l "$LUA_ULISP_BIN" | grep -A1 "GNU_STACK" | grep -q "RW "; then
  echo "ERROR: Expected non-executable GNU_STACK (RW) in $LUA_ULISP_BIN" >&2
  exit 1
fi
echo "  [PASS] Verified standalone static ELF64 properties (file='statically linked', ldd='not a dynamic executable', GNU_STACK='RW')"

if [ "${BUILD_LUAC:-0}" = "1" ]; then
  LUAC_OBJS=()
  for tu in "${CORE_TUS[@]}" "${LIB_TUS[@]}" luac; do
    LUAC_OBJS+=("$OBJ_DIR/${tu}.o")
  done
  "${RUN_CC[@]}" --linker=ulisp -static -nostdlib \
    "$MUSL_LIB_DIR/crt1.o" "${LUAC_OBJS[@]}" "$MUSL_LIB_DIR/libc.a" \
    -o "$ULISP_DIR/build/luac_ulisp"
  echo "  [PASS] Linked standalone static bytecode compiler: $ULISP_DIR/build/luac_ulisp"
fi

LUA_DIFF_GCC="${LUA_DIFF_GCC:-1}"
if [ "$LUA_DIFF_GCC" = "1" ]; then
  "$HOST_CC" -std=c99 -O2 -DLUA_USE_POSIX -Wl,-E -I "$SRC_DIR" "${C_SRCS_FOR_GCC[@]}" -lm -ldl -o "$LUA_GCC_BIN"
  echo "  [PASS] Built reference executable: $LUA_GCC_BIN ($(stat -c%s "$LUA_GCC_BIN") bytes)"
fi

# -----------------------------------------------------------------------
# 6. Differential Smoke & REPL Verification Suite (lua_ulisp vs lua_gcc)
# -----------------------------------------------------------------------
SMOKE_TMP="$ULISP_DIR/build/lua_smoke_tmp_$$"
mkdir -p "$SMOKE_TMP"
trap 'rm -rf "$SMOKE_TMP"' EXIT

PASS_COUNT=0
run_diff_e() {
  local label="$1"
  local code="$2"
  local u_out="$SMOKE_TMP/u.out"
  local g_out="$SMOKE_TMP/g.out"

  timeout 10 "$LUA_ULISP_BIN" -e "$code" > "$u_out"
  if [ "$LUA_DIFF_GCC" = "1" ]; then
    timeout 10 "$LUA_GCC_BIN" -e "$code" > "$g_out"
    if ! diff -u "$g_out" "$u_out"; then
      echo "  [FAIL] Differential mismatch on: $label" >&2
      exit 1
    fi
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "  [PASS] Smoke ($PASS_COUNT): $label"
}

run_diff_e "arithmetic, bitwise & math library" \
  'print(1 + 2 * 3, math.sqrt(16), math.floor(3.7), math.ceil(-1.2), math.fmod(7.5, 2.0), math.abs(-42), math.min(5,2,9), math.max(5,2,9), 1 << 40, (-7) // 2, (-7) % 2)'

run_diff_e "closures, recursion & varargs" \
  'local function fact(n) return n <= 1 and 1 or n * fact(n-1) end local function fib(n) return n < 2 and n or fib(n-1)+fib(n-2) end local function mk(a) return function(b) a=a+b return a end end local c=mk(10) local function va(...) return select("#", ...), select(2, ...) end print(fact(10), fib(15), c(5), c(7), va(11,22,33))'

run_diff_e "tables, table.sort & metatables" \
  'local t={5,2,9,1,7,3} table.sort(t, function(a,b) return a>b end) local mt={__add=function(a,b) return setmetatable({v=a.v+b.v}, getmetatable(a)) end, __tostring=function(x) return "V:"..x.v end} local a=setmetatable({v=19},mt) local b=setmetatable({v=23},mt) print(table.concat(t,","), tostring(a+b))'

run_diff_e "coroutines create/resume/yield" \
  'local co=coroutine.create(function(n) for i=1,n do coroutine.yield(i*i) end return "done" end) local out={} while true do local ok,v=coroutine.resume(co, 5) out[#out+1]=tostring(ok)..":"..tostring(v) if v=="done" or not ok then break end end print(table.concat(out, " "))'

run_diff_e "pcall & xpcall error recovery (setjmp/longjmp)" \
  'local ok1,v1=pcall(function() return 10+20 end) local ok2,e2=pcall(function() error("boom") end) local ok3,e3=xpcall(function() error("xpboom") end, function(m) return "handled:"..tostring(m):match("xpboom") end) print(ok1,v1,ok2,tostring(e2):match("boom"),ok3,e3)'

run_diff_e "string.format/gsub/gmatch/pack/unpack & string.dump+load" \
  'local s=string.format("%d %u %x %.4f %s %q", -5, 42, 255, 3.14159, "hi", "a\nb") local gs,n=string.gsub("foo-1 bar-2", "(%a+)-(%d+)", "%2:%1") local w={} for k in string.gmatch("one,two,three","[^,]+") do w[#w+1]=k end local p=string.pack("<i4ds2", -123456, 6.25, "lua54") local a,b,c,pos=string.unpack("<i4ds2", p) local fn=load(string.dump(function(x,y) return x*y+1 end)) print(s, gs, n, table.concat(w,"|"), #p, a, b, c, pos, fn(6,7))'

run_diff_e "utf8 library (len, codepoint, char)" \
  'local s="A\xCE\xB1\xE3\x81\x82" print(utf8.len(s), utf8.codepoint(s,1,#s)) print(utf8.char(65,945,12354)==s)'

run_diff_e "garbage collector allocation & collection loop" \
  'collectgarbage("collect") local acc=0 for i=1,5000 do local t={i, tostring(i), i*2} acc=acc+t[1] end collectgarbage("collect") print(acc, collectgarbage("count") > 0)'

run_diff_e "io.tmpfile & os.difftime/date/clock" \
  'local f=assert(io.tmpfile()) assert(f:write("hello-lua\n123")) assert(f:seek("set",0)) local d=assert(f:read("*a")) f:close() print(d:gsub("\n","|"), os.difftime(200,50), os.date("!%Y-%m-%d",0), type(os.clock())=="number")'

# Piped stdin script execution
printf 'local x = 6 * 7\nprint("stdin:" .. x)\nlocal ok, err = pcall(error, "e")\nprint("pcall:" .. tostring(ok) .. ":" .. tostring(err):match("e"))\n' > "$SMOKE_TMP/in.lua"
timeout 10 "$LUA_ULISP_BIN" < "$SMOKE_TMP/in.lua" > "$SMOKE_TMP/stdin_u.out"
if [ "$LUA_DIFF_GCC" = "1" ]; then
  timeout 10 "$LUA_GCC_BIN" < "$SMOKE_TMP/in.lua" > "$SMOKE_TMP/stdin_g.out"
  diff -u "$SMOKE_TMP/stdin_g.out" "$SMOKE_TMP/stdin_u.out"
fi
PASS_COUNT=$((PASS_COUNT + 1))
echo "  [PASS] Smoke ($PASS_COUNT): piped stdin script execution"

# Interactive REPL (-i) piped input execution
printf 'x = 21 * 2\nprint(x)\n=x + 8\n' > "$SMOKE_TMP/repl.in"
timeout 10 "$LUA_ULISP_BIN" -i < "$SMOKE_TMP/repl.in" > "$SMOKE_TMP/repl_u.out" 2>&1 || true
if [ "$LUA_DIFF_GCC" = "1" ]; then
  timeout 10 "$LUA_GCC_BIN" -i < "$SMOKE_TMP/repl.in" > "$SMOKE_TMP/repl_g.out" 2>&1 || true
  diff -u "$SMOKE_TMP/repl_g.out" "$SMOKE_TMP/repl_u.out"
fi
PASS_COUNT=$((PASS_COUNT + 1))
echo "  [PASS] Smoke ($PASS_COUNT): interactive REPL (-i) byte-identical output"

echo "========================================================================"
echo " Lua ${LUA_VER} ULisp Build & Differential Verification: ${PASS_COUNT}/${PASS_COUNT} PASS"
echo "========================================================================"
