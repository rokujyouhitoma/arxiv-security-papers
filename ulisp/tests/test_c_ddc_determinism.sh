#!/usr/bin/env bash
# =======================================================================
# Issue #929: DDC (Diverse Double-Compiling) Determinism & Bit-Identity
# Verification Harness (Tier 1: gosh vs ilisp, Tier 2: gcc vs clang &
# Stage-2 vs Stage-3, Tier 3: Lua 5.4.7 33-TU + musl-1.2.5 Reproducibility)
# =======================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$ULISP_DIR/.." && pwd)"

cd "$ULISP_DIR"

echo "========================================================================"
echo " Starting 3-Tier DDC Determinism & Bit-Identity Verification (#929)"
echo "========================================================================"

# -----------------------------------------------------------------------
# Helpers & Forensic Comparator
# -----------------------------------------------------------------------
assert_sha256_equal() {
  local label="$1"
  local file_a="$2"
  local file_b="$3"
  local sha_a sha_b
  sha_a="$(sha256sum "$file_a" | awk '{print $1}')"
  sha_b="$(sha256sum "$file_b" | awk '{print $1}')"
  if [ "$sha_a" != "$sha_b" ]; then
    echo "  [FAIL] SHA-256 mismatch for $label!" >&2
    echo "         A ($file_a): $sha_a ($(stat -c%s "$file_a")B)" >&2
    echo "         B ($file_b): $sha_b ($(stat -c%s "$file_b")B)" >&2
    echo "         --- Forensic cmp -l (first 30 differing bytes) ---" >&2
    cmp -l "$file_a" "$file_b" | head -n 30 >&2 || true
    echo "         --- Forensic readelf -SW diff ---" >&2
    diff -u <(readelf -SW "$file_a" 2>/dev/null || true) <(readelf -SW "$file_b" 2>/dev/null || true) | head -n 40 >&2 || true
    echo "         --- Forensic objdump -d diff ---" >&2
    diff -u <(objdump -d "$file_a" 2>/dev/null || true) <(objdump -d "$file_b" 2>/dev/null || true) | head -n 40 >&2 || true
    exit 1
  fi
  echo "  [PASS] SHA-256 bit-identical ($sha_a): $label"
}

if [ ! -f "$ULISP_DIR/build/c_driver_runner.scm" ]; then
  make -C "$ULISP_DIR" build/c_driver_runner.scm >/dev/null
fi

if [ -x "$ROOT_DIR/.venv/bin/python" ]; then
  PYTHON_BIN="$ROOT_DIR/.venv/bin/python"
else
  PYTHON_BIN="python3"
fi
export PYTHONPATH="$ROOT_DIR"

if ! command -v gosh >/dev/null 2>&1; then
  echo "ERROR: gosh is required for Tier 1 DDC host comparison" >&2
  exit 1
fi
GOSH_BIN="$(command -v gosh)"
RUN_GOSH=("$GOSH_BIN" -usrfi.9 -ugauche.uvector -ugauche.process -uscheme.file -uscheme.bitwise -uscheme.process-context -I "$ULISP_DIR" -I "$ROOT_DIR" "$ULISP_DIR/build/c_driver_runner.scm" --)
RUN_ILISP=("$PYTHON_BIN" -m ilisp "$ULISP_DIR/build/c_driver_runner.scm" --)

MUSL_DIR="$ULISP_DIR/build/third_party/musl-1.2.5"
MUSL_BUILD_DIR="$ULISP_DIR/build/musl_build/obj"
MUSL_LIB_DIR="$MUSL_BUILD_DIR/lib"
if [ ! -f "$MUSL_LIB_DIR/crt1.o" ] || [ ! -f "$MUSL_LIB_DIR/libc.a" ] || [ ! -f "$MUSL_DIR/crt/crt1.c" ]; then
  echo "  [INFO] Ensuring musl-1.2.5 crt1.o & libc.a via compile_musl ..."
  USE_GOSH=1 bash "$ULISP_DIR/tests/test_compile_musl.sh"
fi

LUA_SRC_ORIG="$ULISP_DIR/build/third_party/lua-5.4.7/src"
if [ ! -f "$LUA_SRC_ORIG/lapi.c" ]; then
  make -C "$ULISP_DIR" compile_lua >/dev/null
fi

DDC_TMP="$ULISP_DIR/build/test_c_ddc_e2e_$$"
mkdir -p "$DDC_TMP"
trap 'rm -rf "$DDC_TMP"' EXIT

# -----------------------------------------------------------------------
# Tier 1: Diverse Independent Scheme Hosts (gosh vs python3 -m ilisp)
# -----------------------------------------------------------------------
echo ""
echo "--- Tier 1: Diverse Scheme Hosts (Gauche gosh vs Python ilisp) ---"

mkdir -p "$DDC_TMP/t1_a/src" "$DDC_TMP/t1_b/src" "$DDC_TMP/t1_out_gosh" "$DDC_TMP/t1_out_ilisp"

cat > "$DDC_TMP/t1_a/src/common.h" << 'EOF'
#ifndef DDC_COMMON_H
#define DDC_COMMON_H
#include <stdio.h>
#include <string.h>
#include <math.h>
int compute_part(int k, double scale);
#endif
EOF

cat > "$DDC_TMP/t1_a/src/mod_a.c" << 'EOF'
#include "common.h"

static int impl_part(int k, double scale) {
    int acc = 0;
    switch (k & 3) {
        case 0: acc = 10; break;
        case 1: acc = 20; break;
        case 2: acc = (int)sqrt(441.0); break;
        default: acc = 5; break;
    }
    return acc + (int)(scale * 2.0);
}

int compute_part_weak(int k, double scale) __attribute__((weak, alias("impl_part")));

int compute_part(int k, double scale) {
    return impl_part(k, scale);
}

const char *mod_a_meta(void) {
    return __FILE__ " " __DATE__ " " __TIME__;
}
EOF

cat > "$DDC_TMP/t1_a/src/mod_b.c" << 'EOF'
#include "common.h"
extern int compute_part_weak(int k, double scale);
extern const char *mod_a_meta(void);

int main(void) {
    char buf[128];
    int v = compute_part(2, 10.5);
    int w = compute_part_weak(0, 1.0);
    snprintf(buf, sizeof(buf), "%s|%d|%d", mod_a_meta(), v, w);
    if (strstr(buf, "src/mod_a.c Jan  1 1970 00:00:00|42|12") == NULL) {
        return 1;
    }
    return v;
}
EOF

cp -f "$DDC_TMP/t1_a/src/common.h" "$DDC_TMP/t1_b/src/common.h"
cp -f "$DDC_TMP/t1_a/src/mod_a.c"  "$DDC_TMP/t1_b/src/mod_a.c"
cp -f "$DDC_TMP/t1_a/src/mod_b.c"  "$DDC_TMP/t1_b/src/mod_b.c"

MUSL_INCS=(
  -D_XOPEN_SOURCE=700 -nostdinc
  -I "$MUSL_BUILD_DIR/include"
  -I "$MUSL_DIR/arch/x86_64"
  -I "$MUSL_DIR/arch/generic"
  -I "$MUSL_DIR/include"
)

# Chain A: gosh
GOSH_PREFIX_ARG="-ffile-prefix-map=$DDC_TMP/t1_a=ddc_virt"
"${RUN_GOSH[@]}" "${MUSL_INCS[@]}" "$GOSH_PREFIX_ARG" -I "$DDC_TMP/t1_a/src" -emit-pch "$DDC_TMP/t1_a/src/common.h" -o "$DDC_TMP/t1_out_gosh/common.h.sbi"
"${RUN_GOSH[@]}" "${MUSL_INCS[@]}" "$GOSH_PREFIX_ARG" -O2 -I "$DDC_TMP/t1_a/src" -include-pch "$DDC_TMP/t1_out_gosh/common.h.sbi" -c "$DDC_TMP/t1_a/src/mod_a.c" -o "$DDC_TMP/t1_out_gosh/mod_a.o"
"${RUN_GOSH[@]}" "${MUSL_INCS[@]}" "$GOSH_PREFIX_ARG" -O2 -I "$DDC_TMP/t1_a/src" -include-pch "$DDC_TMP/t1_out_gosh/common.h.sbi" -c "$DDC_TMP/t1_a/src/mod_b.c" -o "$DDC_TMP/t1_out_gosh/mod_b.o"
"${RUN_GOSH[@]}" --linker=ulisp -static -nostdlib \
  "$MUSL_LIB_DIR/crt1.o" "$DDC_TMP/t1_out_gosh/mod_a.o" "$DDC_TMP/t1_out_gosh/mod_b.o" "$MUSL_LIB_DIR/libc.a" \
  -o "$DDC_TMP/t1_out_gosh/ddc_app_static"

# Chain B: python3 -m ilisp (single batch process for speed & batch-vs-separate determinism)
# Emit common.h.sbi from the same physical common.h path (deps section hashes disk paths),
# while compiling mod_a.c & mod_b.c from distinct t1_b/src with -ffile-prefix-map.
ILISP_PREFIX_ARG="-ffile-prefix-map=$DDC_TMP/t1_b=ddc_virt"
GOSH_PCH_MAP="-ffile-prefix-map=$DDC_TMP/t1_a=ddc_virt"
ILISP_BATCH_SCM="$DDC_TMP/t1_ilisp_batch.scm"
sed '$d' "$ULISP_DIR/build/c_driver_runner.scm" > "$ILISP_BATCH_SCM"
cat >> "$ILISP_BATCH_SCM" << EOF
(begin
  (c-driver-main '("-D_XOPEN_SOURCE=700" "-nostdinc"
                   "-I" "$MUSL_BUILD_DIR/include"
                   "-I" "$MUSL_DIR/arch/x86_64"
                   "-I" "$MUSL_DIR/arch/generic"
                   "-I" "$MUSL_DIR/include"
                   "$GOSH_PCH_MAP" "-I" "$DDC_TMP/t1_a/src"
                   "-emit-pch" "$DDC_TMP/t1_a/src/common.h"
                   "-o" "$DDC_TMP/t1_out_ilisp/common.h.sbi"))
  (c-driver-main '("-D_XOPEN_SOURCE=700" "-nostdinc"
                   "-I" "$MUSL_BUILD_DIR/include"
                   "-I" "$MUSL_DIR/arch/x86_64"
                   "-I" "$MUSL_DIR/arch/generic"
                   "-I" "$MUSL_DIR/include"
                   "$ILISP_PREFIX_ARG" "-O2" "-I" "$DDC_TMP/t1_b/src"
                   "-include-pch" "$DDC_TMP/t1_out_ilisp/common.h.sbi"
                   "-c" "-o" "$DDC_TMP/t1_out_ilisp/"
                   "$DDC_TMP/t1_b/src/mod_a.c" "$DDC_TMP/t1_b/src/mod_b.c"))
  (c-driver-main '("--linker=ulisp" "-static" "-nostdlib"
                   "$MUSL_LIB_DIR/crt1.o"
                   "$DDC_TMP/t1_out_ilisp/mod_a.o"
                   "$DDC_TMP/t1_out_ilisp/mod_b.o"
                   "$MUSL_LIB_DIR/libc.a"
                   "-o" "$DDC_TMP/t1_out_ilisp/ddc_app_static"))
  (exit 0))
EOF
"$PYTHON_BIN" -m ilisp "$ILISP_BATCH_SCM"

assert_sha256_equal "Tier 1 .sbi PCH (gosh vs ilisp)" "$DDC_TMP/t1_out_gosh/common.h.sbi" "$DDC_TMP/t1_out_ilisp/common.h.sbi"
assert_sha256_equal "Tier 1 mod_a.o (gosh vs ilisp)" "$DDC_TMP/t1_out_gosh/mod_a.o" "$DDC_TMP/t1_out_ilisp/mod_a.o"
assert_sha256_equal "Tier 1 mod_b.o (gosh vs ilisp)" "$DDC_TMP/t1_out_gosh/mod_b.o" "$DDC_TMP/t1_out_ilisp/mod_b.o"
assert_sha256_equal "Tier 1 ddc_app_static ELF64 (gosh vs ilisp)" "$DDC_TMP/t1_out_gosh/ddc_app_static" "$DDC_TMP/t1_out_ilisp/ddc_app_static"

set +e
"$DDC_TMP/t1_out_gosh/ddc_app_static"
RC_A=$?
"$DDC_TMP/t1_out_ilisp/ddc_app_static"
RC_B=$?
set -e
if [ "$RC_A" -ne 42 ] || [ "$RC_B" -ne 42 ]; then
  echo "  [FAIL] Tier 1 ddc_app_static expected exit 42, got A=$RC_A B=$RC_B" >&2
  exit 1
fi
echo "  [PASS] Tier 1 execution verified: both ddc_app_static binaries exited with 42"

# -----------------------------------------------------------------------
# Tier 2: Diverse C Compiler Lineage (gcc vs clang on --target=c) & Self-Host
# -----------------------------------------------------------------------
echo ""
echo "--- Tier 2: Diverse C Compilers (gcc vs clang --target=c) & Stage-2/Stage-3 ---"

mkdir -p "$DDC_TMP/t2"
cat > "$DDC_TMP/t2/c_lineage.c" << 'EOF'
#include <stdio.h>
static int fold(int n) {
    int s = 0;
    int i;
    for (i = 1; i <= n; i++) s += i;
    return s;
}
int main(void) {
    int r = fold(8) + 6;
    printf("lineage=%d\n", r);
    return r;
}
EOF

"${RUN_GOSH[@]}" --target=c -S -O2 "$DDC_TMP/t2/c_lineage.c" -o "$DDC_TMP/t2/c_lineage_ulisp.c"
for cc_bin in gcc clang; do
  if command -v "$cc_bin" >/dev/null 2>&1; then
    "$cc_bin" -O2 "$DDC_TMP/t2/c_lineage_ulisp.c" -lm -o "$DDC_TMP/t2/bin_${cc_bin}"
    set +e
    out="$("$DDC_TMP/t2/bin_${cc_bin}")"
    rc=$?
    set -e
    if [ "$rc" -ne 42 ] || [ "$out" != "lineage=42" ]; then
      echo "  [FAIL] Tier 2 Portable C ($cc_bin) mismatch: rc=$rc out='$out'" >&2
      exit 1
    fi
    echo "  [PASS] Tier 2 Portable C ($cc_bin): out='$out' rc=$rc"
  fi
done

if ls "$ULISP_DIR"/build/stage2_*.s >/dev/null 2>&1 && ls "$ULISP_DIR"/build/stage3_*.s >/dev/null 2>&1; then
  for mod in compiler_base frontend_passes lir_passes backend_passes compiler_driver; do
    if [ -f "$ULISP_DIR/build/stage2_${mod}.s" ] && [ -f "$ULISP_DIR/build/stage3_${mod}.s" ]; then
      assert_sha256_equal "Tier 2 ULisp bootstrap stage2 vs stage3 ($mod.s)" \
        "$ULISP_DIR/build/stage2_${mod}.s" "$ULISP_DIR/build/stage3_${mod}.s"
    fi
  done
fi

# -----------------------------------------------------------------------
# Tier 3: Full Lua 5.4.7 33-TU + musl-1.2.5 Reproducibility (dir_a JOBS=1 vs dir_b JOBS=4)
# -----------------------------------------------------------------------
echo ""
echo "--- Tier 3: Lua 5.4.7 33-TU + musl-1.2.5 Reproducibility (dirA JOBS=1 vs dirB JOBS=4) ---"

mkdir -p "$DDC_TMP/t3_a/lua_src" "$DDC_TMP/t3_b/lua_src" "$DDC_TMP/t3_a/obj" "$DDC_TMP/t3_b/obj"
cp -f "$LUA_SRC_ORIG"/*.c "$LUA_SRC_ORIG"/*.h "$DDC_TMP/t3_a/lua_src/"
cp -f "$LUA_SRC_ORIG"/*.c "$LUA_SRC_ORIG"/*.h "$DDC_TMP/t3_b/lua_src/"

LUA_TUS=(
  lapi lcode lctype ldebug ldo ldump lfunc lgc llex lmem
  lobject lopcodes lparser lstate lstring ltable ltm lundump lvm lzio
  lauxlib lbaselib lcorolib ldblib liolib lmathlib
  loadlib loslib lstrlib ltablib lutf8lib linit lua
)

compile_lua_tree_ddc() {
  local src_dir="$1"
  local obj_dir="$2"
  local jobs="$3"
  local prefix_old="$4"

  local pids=()
  for ((s = 0; s < jobs; s++)); do
    local shard_srcs=()
    for ((i = s; i < ${#LUA_TUS[@]}; i += jobs)); do
      shard_srcs+=("$src_dir/${LUA_TUS[$i]}.c")
    done
    if [ "${#shard_srcs[@]}" -gt 0 ]; then
      local shard_scm="$obj_dir/shard_${s}.scm"
      sed '$d' "$ULISP_DIR/build/c_driver_runner.scm" > "$shard_scm"
      printf '(begin\n  (c-driver-main '\''("-DLUA_USE_POSIX" "-O2" "-ffile-prefix-map=%s=lua_ddc_src" "-I" "%s" "-c" "-o" "%s"' \
        "$prefix_old" "$src_dir" "$obj_dir/" >> "$shard_scm"
      for src in "${shard_srcs[@]}"; do
        printf ' "%s"' "$src" >> "$shard_scm"
      done
      printf '))\n  (exit 0))\n' >> "$shard_scm"
      (
        "$GOSH_BIN" -usrfi.9 -ugauche.uvector -ugauche.process -uscheme.file -uscheme.bitwise -uscheme.process-context -I "$ULISP_DIR" -I "$ROOT_DIR" "$shard_scm"
      ) > "$obj_dir/shard_${s}.log" 2>&1 &
      pids+=("$!")
    fi
  done

  for idx in "${!pids[@]}"; do
    if ! wait "${pids[$idx]}"; then
      echo "ERROR: Tier 3 shard $idx failed:" >&2
      cat "$obj_dir/shard_${idx}.log" >&2 || true
      exit 1
    fi
  done
}

echo "  [INFO] Building 33 Lua TUs in Chain A (dir_a, JOBS=1) ..."
compile_lua_tree_ddc "$DDC_TMP/t3_a/lua_src" "$DDC_TMP/t3_a/obj" 1 "$DDC_TMP/t3_a/lua_src"
echo "  [INFO] Building 33 Lua TUs in Chain B (dir_b, JOBS=4) ..."
compile_lua_tree_ddc "$DDC_TMP/t3_b/lua_src" "$DDC_TMP/t3_b/obj" 4 "$DDC_TMP/t3_b/lua_src"

LUA_OBJS_A=()
LUA_OBJS_B=()
for tu in "${LUA_TUS[@]}"; do
  oa="$DDC_TMP/t3_a/obj/${tu}.o"
  ob="$DDC_TMP/t3_b/obj/${tu}.o"
  assert_sha256_equal "Tier 3 Lua TU ${tu}.o (dirA JOBS=1 vs dirB JOBS=4)" "$oa" "$ob"
  LUA_OBJS_A+=("$oa")
  LUA_OBJS_B+=("$ob")
done

# Deterministic musl representative TUs + ar rcsD archive check
mkdir -p "$DDC_TMP/musl_a/src" "$DDC_TMP/musl_b/src" "$DDC_TMP/musl_a/out" "$DDC_TMP/musl_b/out"
cp -r "$MUSL_DIR/crt" "$DDC_TMP/musl_a/src/crt"
cp -r "$MUSL_DIR/crt" "$DDC_TMP/musl_b/src/crt"
mkdir -p "$DDC_TMP/musl_a/src/src/string" "$DDC_TMP/musl_b/src/src/string" "$DDC_TMP/musl_a/src/src/stdio" "$DDC_TMP/musl_b/src/src/stdio"
cp -f "$MUSL_DIR/src/string/strlen.c" "$DDC_TMP/musl_a/src/src/string/strlen.c"
cp -f "$MUSL_DIR/src/string/strlen.c" "$DDC_TMP/musl_b/src/src/string/strlen.c"
cp -f "$MUSL_DIR/src/stdio/snprintf.c" "$DDC_TMP/musl_a/src/src/stdio/snprintf.c"
cp -f "$MUSL_DIR/src/stdio/snprintf.c" "$DDC_TMP/musl_b/src/src/stdio/snprintf.c"

MUSL_DDC_INCS=(
  -D_XOPEN_SOURCE=700 -nostdinc
  -I "$MUSL_BUILD_DIR/include"
  -I "$MUSL_DIR/arch/x86_64"
  -I "$MUSL_DIR/arch/generic"
  -I "$MUSL_BUILD_DIR/src/internal"
  -I "$MUSL_DIR/src/include"
  -I "$MUSL_DIR/src/internal"
  -I "$MUSL_DIR/include"
)

"${RUN_GOSH[@]}" "${MUSL_DDC_INCS[@]}" "-ffile-prefix-map=$DDC_TMP/musl_a/src=musl_ddc" -c -o "$DDC_TMP/musl_a/out/" \
  "$DDC_TMP/musl_a/src/crt/crt1.c" "$DDC_TMP/musl_a/src/src/string/strlen.c" "$DDC_TMP/musl_a/src/src/stdio/snprintf.c"
"${RUN_GOSH[@]}" "${MUSL_DDC_INCS[@]}" "-ffile-prefix-map=$DDC_TMP/musl_b/src=musl_ddc" -c -o "$DDC_TMP/musl_b/out/" \
  "$DDC_TMP/musl_b/src/crt/crt1.c" "$DDC_TMP/musl_b/src/src/string/strlen.c" "$DDC_TMP/musl_b/src/src/stdio/snprintf.c"

assert_sha256_equal "Tier 3 musl crt1.o (dirA vs dirB)" "$DDC_TMP/musl_a/out/crt1.o" "$DDC_TMP/musl_b/out/crt1.o"
assert_sha256_equal "Tier 3 musl strlen.o (dirA vs dirB)" "$DDC_TMP/musl_a/out/strlen.o" "$DDC_TMP/musl_b/out/strlen.o"
assert_sha256_equal "Tier 3 musl snprintf.o (dirA vs dirB)" "$DDC_TMP/musl_a/out/snprintf.o" "$DDC_TMP/musl_b/out/snprintf.o"

# Verify deterministic ar rcsD across distinct timestamps
ar rcsD "$DDC_TMP/musl_a/out/libc_sub.a" "$DDC_TMP/musl_a/out/strlen.o" "$DDC_TMP/musl_a/out/snprintf.o"
sleep 1
ar rcsD "$DDC_TMP/musl_b/out/libc_sub.a" "$DDC_TMP/musl_b/out/strlen.o" "$DDC_TMP/musl_b/out/snprintf.o"
assert_sha256_equal "Tier 3 deterministic ar rcsD archive" "$DDC_TMP/musl_a/out/libc_sub.a" "$DDC_TMP/musl_b/out/libc_sub.a"

# Link full lua_ulisp_static in both chains via Pass 144 with stripped PATH
NOHOST_BIN="$DDC_TMP/nohostbin"
mkdir -p "$NOHOST_BIN"
for tool in uname env sh bash cat rm mkdir chmod; do
  if command -v "$tool" >/dev/null 2>&1; then
    ln -sf "$(command -v "$tool")" "$NOHOST_BIN/$tool"
  fi
done

PATH="$NOHOST_BIN" "${RUN_GOSH[@]}" --linker=ulisp -static -nostdlib \
  "$DDC_TMP/musl_a/out/crt1.o" "${LUA_OBJS_A[@]}" "$MUSL_LIB_DIR/libc.a" \
  -o "$DDC_TMP/t3_a/lua_ulisp_static_a"
PATH="$NOHOST_BIN" "${RUN_GOSH[@]}" --linker=ulisp -static -nostdlib \
  "$DDC_TMP/musl_b/out/crt1.o" "${LUA_OBJS_B[@]}" "$MUSL_LIB_DIR/libc.a" \
  -o "$DDC_TMP/t3_b/lua_ulisp_static_b"

assert_sha256_equal "Tier 3 full lua_ulisp_static ELF64 (dirA JOBS=1 vs dirB JOBS=4)" \
  "$DDC_TMP/t3_a/lua_ulisp_static_a" "$DDC_TMP/t3_b/lua_ulisp_static_b"

LUA_OUT="$("$DDC_TMP/t3_a/lua_ulisp_static_a" -e 'print(6*7)')"
if [ "$LUA_OUT" != "42" ]; then
  echo "  [FAIL] Tier 3 lua_ulisp_static expected '42', got '$LUA_OUT'" >&2
  exit 1
fi
echo "  [PASS] Tier 3 lua_ulisp_static executed cleanly (output: 42)"

echo "========================================================================"
echo " SUCCESS: 3-Tier DDC Determinism & Bit-Identity Suite PASSED (100%)"
echo "========================================================================"
