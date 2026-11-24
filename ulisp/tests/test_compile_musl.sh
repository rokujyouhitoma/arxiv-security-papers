#!/usr/bin/env bash
# =======================================================================
# Issue #928: musl-1.2.5 x86-64 Self-Build (crt1.o + libc.a) with ULisp
# C99 Frontend and Standalone Static Linking via Pass 144 ELF64 Linker
# =======================================================================
set -euo pipefail

CALLER_PWD="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$ULISP_DIR/.." && pwd)"

MUSL_VER="1.2.5"
MUSL_TARBALL_NAME="musl-${MUSL_VER}.tar.gz"
MUSL_URL="${MUSL_URL:-https://musl.libc.org/releases/${MUSL_TARBALL_NAME}}"
MUSL_SHA256="a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4"

THIRD_PARTY_DIR="$ULISP_DIR/build/third_party"
TARBALL_PATH="$THIRD_PARTY_DIR/$MUSL_TARBALL_NAME"
EXTRACTED_MUSL_DIR="$THIRD_PARTY_DIR/musl-${MUSL_VER}"

echo "========================================================================"
echo " Starting musl ${MUSL_VER} x86-64 ULisp Compilation & Pass 144 Static Link (#928)"
echo "========================================================================"

# -----------------------------------------------------------------------
# 1. Resolve / Download & Verify musl-1.2.5 Sources (SHA-256 & CWE-22)
# -----------------------------------------------------------------------
MUSL_DIR=""
if [ -n "${MUSL_SRC_DIR:-}" ]; then
  CAND="$MUSL_SRC_DIR"
  if [[ "$CAND" != /* ]]; then
    CAND="$CALLER_PWD/$CAND"
  fi
  if [ -f "$CAND/crt/crt1.c" ]; then
    MUSL_DIR="$(cd "$CAND" && pwd)"
  else
    echo "ERROR: MUSL_SRC_DIR='$MUSL_SRC_DIR' does not contain crt/crt1.c" >&2
    exit 1
  fi
  echo "  [INFO] Using caller-provided MUSL_SRC_DIR: $MUSL_DIR"
else
  mkdir -p "$THIRD_PARTY_DIR"
  if [ ! -f "$EXTRACTED_MUSL_DIR/crt/crt1.c" ]; then
    if [ ! -f "$TARBALL_PATH" ]; then
      echo "  [INFO] Downloading official musl ${MUSL_VER} archive from $MUSL_URL ..."
      if command -v curl >/dev/null 2>&1; then
        if ! curl --fail --location --retry 3 --connect-timeout 15 -o "$TARBALL_PATH.tmp" "$MUSL_URL"; then
          rm -f "$TARBALL_PATH.tmp"
          echo "ERROR: Failed to download $MUSL_URL (offline?)." >&2
          echo "       Provide a pre-fetched archive at $TARBALL_PATH or set MUSL_SRC_DIR=/path/to/musl-${MUSL_VER}" >&2
          exit 1
        fi
        mv -f "$TARBALL_PATH.tmp" "$TARBALL_PATH"
      elif command -v wget >/dev/null 2>&1; then
        if ! wget -q --tries=3 --timeout=15 -O "$TARBALL_PATH.tmp" "$MUSL_URL"; then
          rm -f "$TARBALL_PATH.tmp"
          echo "ERROR: Failed to download $MUSL_URL (offline?)." >&2
          echo "       Provide a pre-fetched archive at $TARBALL_PATH or set MUSL_SRC_DIR=/path/to/musl-${MUSL_VER}" >&2
          exit 1
        fi
        mv -f "$TARBALL_PATH.tmp" "$TARBALL_PATH"
      else
        echo "ERROR: Neither curl nor wget available and $TARBALL_PATH is missing." >&2
        exit 1
      fi
    fi

    ACTUAL_SHA256="$(sha256sum "$TARBALL_PATH" | awk '{print $1}')"
    if [ "$ACTUAL_SHA256" != "$MUSL_SHA256" ]; then
      echo "ERROR: SHA-256 mismatch for $TARBALL_PATH!" >&2
      echo "       Expected: $MUSL_SHA256" >&2
      echo "       Actual:   $ACTUAL_SHA256" >&2
      rm -f "$TARBALL_PATH"
      exit 1
    fi
    echo "  [PASS] Verified SHA-256 digest of $MUSL_TARBALL_NAME"

    if tar -tzf "$TARBALL_PATH" | grep -E '(^/|^\.\./|/\.\./|/\.\.$)'; then
      echo "ERROR: Unsafe path entry (CWE-22) detected in $TARBALL_PATH!" >&2
      exit 1
    fi
    echo "  [PASS] Archive path traversal check (CWE-22) passed"

    tar --no-same-owner -xzf "$TARBALL_PATH" -C "$THIRD_PARTY_DIR"
  fi
  MUSL_DIR="$EXTRACTED_MUSL_DIR"
  echo "  [INFO] Using musl ${MUSL_VER} sources at: $MUSL_DIR"
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
# 3. Generate musl Build Tree Headers (bits/alltypes.h, bits/syscall.h, bits/float.h, version.h)
# -----------------------------------------------------------------------
MUSL_BUILD_DIR="$ULISP_DIR/build/musl_build/obj"
MUSL_OBJ_DIR="$MUSL_BUILD_DIR/obj"
MUSL_LIB_DIR="$MUSL_BUILD_DIR/lib"

mkdir -p "$MUSL_BUILD_DIR/include/bits" "$MUSL_BUILD_DIR/src/internal" "$MUSL_OBJ_DIR" "$MUSL_LIB_DIR"

sed -f "$MUSL_DIR/tools/mkalltypes.sed" \
  "$MUSL_DIR/arch/x86_64/bits/alltypes.h.in" \
  "$MUSL_DIR/include/alltypes.h.in" > "$MUSL_BUILD_DIR/include/bits/alltypes.h"

cp -f "$MUSL_DIR/arch/x86_64/bits/syscall.h.in" "$MUSL_BUILD_DIR/include/bits/syscall.h"
sed -n -e 's/__NR_/SYS_/p' < "$MUSL_DIR/arch/x86_64/bits/syscall.h.in" >> "$MUSL_BUILD_DIR/include/bits/syscall.h"

# ULisp C99 lowers long double as 64-bit IEEE-754 double (LDBL_MANT_DIG == 53, LDBL_MAX_EXP == 1024)
cp -f "$MUSL_DIR/arch/arm/bits/float.h" "$MUSL_BUILD_DIR/include/bits/float.h"
printf '#define VERSION "%s"\n' "$MUSL_VER" > "$MUSL_BUILD_DIR/src/internal/version.h"

# Ensure non-builtin unmapped locales return LOC_MAP_FAILED instead of dummy C locale map
if ! grep -q 'if (!new) return LOC_MAP_FAILED;' "$MUSL_DIR/src/locale/locale_map.c"; then
  sed -i 's/if (!new && (new = malloc(sizeof \*new))) {/if (!new) return LOC_MAP_FAILED;\n\tif (!new \&\& (new = malloc(sizeof *new))) {/' "$MUSL_DIR/src/locale/locale_map.c"
fi
echo "  [PASS] Prepared musl-1.2.5 generated headers (bits/alltypes.h, bits/syscall.h, bits/float.h, version.h)"

# -----------------------------------------------------------------------
# 4. Compile 221 musl-1.2.5 x86-64 Translation Units (.c & .s) with ULisp
# -----------------------------------------------------------------------
MUSL_SRCS=(
  crt/crt1.c
  src/thread/x86_64/syscall_cp.s
  src/stdlib/qsort_nr.c
  src/multibyte/internal.c
  src/exit/_Exit.c
  src/math/__cos.c
  src/env/__environ.c
  src/errno/__errno_location.c
  src/stdio/__fdopen.c
  src/stdio/__fmodeflags.c
  src/math/__fpclassify.c
  src/math/__fpclassifyl.c
  src/env/__init_tls.c
  src/locale/__lctrans.c
  src/env/__libc_start_main.c
  src/thread/__lock.c
  src/stdio/__lockfile.c
  src/time/__map_file.c
  src/math/__math_divzero.c
  src/math/__math_invalid.c
  src/math/__math_oflow.c
  src/math/__math_uflow.c
  src/math/__math_xflow.c
  src/locale/__mo_lookup.c
  src/time/__month_to_secs.c
  src/temp/__randname.c
  src/math/__rem_pio2.c
  src/math/__rem_pio2_large.c
  src/time/__secs_to_tm.c
  src/thread/x86_64/__set_thread_area.s
  src/math/__signbit.c
  src/math/__signbitl.c
  src/math/__sin.c
  src/stdio/__stdio_close.c
  src/stdio/__stdio_exit.c
  src/stdio/__stdio_read.c
  src/stdio/__stdio_seek.c
  src/stdio/__stdio_write.c
  src/stdio/__stdout_write.c
  src/thread/__syscall_cp.c
  src/math/__tan.c
  src/time/__tm_to_secs.c
  src/stdio/__toread.c
  src/stdio/__towrite.c
  src/time/__tz.c
  src/stdio/__uflow.c
  src/thread/__wait.c
  src/time/__year_to_secs.c
  src/unistd/_exit.c
  src/exit/abort.c
  src/exit/abort_lock.c
  src/stdlib/abs.c
  src/math/acos.c
  src/math/asin.c
  src/math/atan.c
  src/math/atan2.c
  src/signal/block.c
  src/locale/c_locale.c
  src/math/ceil.c
  src/stdio/clearerr.c
  src/time/clock.c
  src/time/clock_gettime.c
  src/thread/x86_64/clone.s
  src/unistd/close.c
  src/math/copysign.c
  src/math/copysignl.c
  src/math/cos.c
  src/thread/default_attr.c
  src/internal/defsysinfo.c
  src/time/difftime.c
  src/unistd/dup3.c
  src/process/execve.c
  src/exit/exit.c
  src/math/exp.c
  src/math/exp_data.c
  src/math/fabs.c
  src/math/fabsl.c
  src/stdio/fclose.c
  src/fcntl/fcntl.c
  src/stdio/feof.c
  src/stdio/ferror.c
  src/stdio/fflush.c
  src/stdio/fgets.c
  src/internal/floatscan.c
  src/stdio/flockfile.c
  src/math/floor.c
  src/math/fmod.c
  src/math/fmodl.c
  src/stdio/fopen.c
  src/stdio/fprintf.c
  src/stdio/fputs.c
  src/stdio/fread.c
  src/malloc/free.c
  src/stdio/freopen.c
  src/math/frexp.c
  src/math/frexpl.c
  src/stdio/fseek.c
  src/stat/fstat.c
  src/stat/fstatat.c
  src/stdio/ftell.c
  src/stdio/ftrylockfile.c
  src/stdio/funlockfile.c
  src/stdio/fwrite.c
  src/stdio/getc.c
  src/stdio/getc_unlocked.c
  src/env/getenv.c
  src/time/gmtime_r.c
  src/internal/intscan.c
  src/ctype/isalnum.c
  src/ctype/isalpha.c
  src/unistd/isatty.c
  src/ctype/iscntrl.c
  src/ctype/isdigit.c
  src/ctype/isgraph.c
  src/ctype/islower.c
  src/ctype/ispunct.c
  src/ctype/isspace.c
  src/ctype/isupper.c
  src/ctype/isxdigit.c
  src/locale/langinfo.c
  src/math/ldexp.c
  src/internal/libc.c
  src/malloc/lite_malloc.c
  src/locale/locale_map.c
  src/locale/localeconv.c
  src/time/localtime_r.c
  src/math/log.c
  src/math/log10.c
  src/math/log2.c
  src/math/log2_data.c
  src/math/log_data.c
  src/unistd/lseek.c
  src/mman/madvise.c
  src/malloc/oldmalloc/malloc.c
  src/string/memchr.c
  src/string/memcmp.c
  src/string/memcpy.c
  src/string/memset.c
  src/temp/mkostemps.c
  src/temp/mkstemp.c
  src/time/mktime.c
  src/mman/mmap.c
  src/mman/mremap.c
  src/mman/munmap.c
  src/stdio/ofl.c
  src/stdio/ofl_add.c
  src/fcntl/open.c
  src/stdio/pclose.c
  src/unistd/pipe.c
  src/unistd/pipe2.c
  src/stdio/popen.c
  src/process/posix_spawn.c
  src/process/posix_spawn_file_actions_addclose.c
  src/process/posix_spawn_file_actions_adddup2.c
  src/process/posix_spawn_file_actions_destroy.c
  src/process/posix_spawn_file_actions_init.c
  src/process/posix_spawnattr_destroy.c
  src/process/posix_spawnattr_init.c
  src/process/posix_spawnattr_setflags.c
  src/process/posix_spawnattr_setsigdefault.c
  src/process/posix_spawnattr_setsigmask.c
  src/math/pow.c
  src/math/pow_data.c
  src/internal/procfdname.c
  src/thread/pthread_setcancelstate.c
  src/thread/pthread_sigmask.c
  src/thread/pthread_testcancel.c
  src/signal/raise.c
  src/unistd/read.c
  src/malloc/realloc.c
  src/stdio/remove.c
  src/stdio/rename.c
  src/signal/x86_64/restore.s
  src/math/scalbn.c
  src/math/scalbnl.c
  src/locale/setlocale.c
  src/stdio/setvbuf.c
  src/internal/shgetc.c
  src/signal/sigaction.c
  src/signal/sigaddset.c
  src/signal/sigemptyset.c
  src/signal/sigismember.c
  src/signal/sigprocmask.c
  src/math/sin.c
  src/stdio/snprintf.c
  src/math/sqrt.c
  src/math/sqrt_data.c
  src/stdio/stderr.c
  src/stdio/stdin.c
  src/stdio/stdout.c
  src/string/stpcpy.c
  src/string/strchr.c
  src/string/strchrnul.c
  src/string/strcmp.c
  src/locale/strcoll.c
  src/string/strcpy.c
  src/string/strcspn.c
  src/errno/strerror.c
  src/time/strftime.c
  src/string/strlen.c
  src/string/strncmp.c
  src/string/strnlen.c
  src/string/strpbrk.c
  src/string/strspn.c
  src/string/strstr.c
  src/stdlib/strtod.c
  src/stdlib/strtol.c
  src/internal/syscall_ret.c
  src/process/system.c
  src/math/tan.c
  src/time/time.c
  src/stdio/tmpfile.c
  src/ctype/tolower.c
  src/ctype/toupper.c
  src/stdio/ungetc.c
  src/internal/vdso.c
  src/stdio/vfprintf.c
  src/stdio/vsnprintf.c
  src/process/waitpid.c
  src/multibyte/wcrtomb.c
  src/multibyte/wctomb.c
)

REBUILD_MUSL="${REBUILD_MUSL:-0}"
MISSING_OBJS=()
LIBC_OBJS=()
for rel in "${MUSL_SRCS[@]}"; do
  base="$(basename "$rel")"
  stem="${base%.*}"
  obj="$MUSL_OBJ_DIR/${stem}.o"
  if [ "$stem" != "crt1" ]; then
    LIBC_OBJS+=("$obj")
  fi
  if [ "$REBUILD_MUSL" = "1" ] || [ ! -f "$obj" ]; then
    MISSING_OBJS+=("$rel")
  fi
done

if [ "${#MISSING_OBJS[@]}" -gt 0 ]; then
  JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
  if [ "$JOBS" -lt 1 ]; then
    JOBS=1
  fi
  if [ "$JOBS" -gt 8 ]; then
    JOBS=8
  fi
  echo "  [INFO] Compiling ${#MISSING_OBJS[@]} musl-1.2.5 translation units across $JOBS parallel batch shards ..."
  T0="$(date +%s)"
  PIDS=()
  for ((s = 0; s < JOBS; s++)); do
    SHARD_SRCS=()
    for ((i = s; i < ${#MISSING_OBJS[@]}; i += JOBS)); do
      SHARD_SRCS+=("$MUSL_DIR/${MISSING_OBJS[$i]}")
    done
    if [ "${#SHARD_SRCS[@]}" -gt 0 ]; then
      if [ -n "${ULISP_CC_BIN:-}" ] && [ -x "${ULISP_CC_BIN}" ]; then
        (
          "$ULISP_CC_BIN" -D_XOPEN_SOURCE=700 -nostdinc \
            -I "$MUSL_BUILD_DIR/include" \
            -I "$MUSL_DIR/arch/x86_64" \
            -I "$MUSL_DIR/arch/generic" \
            -I "$MUSL_BUILD_DIR/src/internal" \
            -I "$MUSL_DIR/src/include" \
            -I "$MUSL_DIR/src/internal" \
            -I "$MUSL_DIR/include" \
            ${MUSL_EXTRA_CFLAGS:-} \
            -c -o "$MUSL_OBJ_DIR/" "${SHARD_SRCS[@]}"
        ) > "$MUSL_BUILD_DIR/musl_shard_${s}.log" 2>&1 &
        PIDS+=("$!")
      else
        SHARD_SCM="$MUSL_BUILD_DIR/musl_shard_${s}.scm"
        sed '$d' "$ULISP_DIR/build/c_driver_runner.scm" > "$SHARD_SCM"
        printf '(begin\n  (c-driver-main '\''("-D_XOPEN_SOURCE=700" "-nostdinc" "-I" "%s" "-I" "%s" "-I" "%s" "-I" "%s" "-I" "%s" "-I" "%s" "-I" "%s"' \
          "$MUSL_BUILD_DIR/include" \
          "$MUSL_DIR/arch/x86_64" \
          "$MUSL_DIR/arch/generic" \
          "$MUSL_BUILD_DIR/src/internal" \
          "$MUSL_DIR/src/include" \
          "$MUSL_DIR/src/internal" \
          "$MUSL_DIR/include" >> "$SHARD_SCM"
        for extra_f in ${MUSL_EXTRA_CFLAGS:-}; do
          printf ' "%s"' "$extra_f" >> "$SHARD_SCM"
        done
        printf ' "-c" "-o" "%s"' "$MUSL_OBJ_DIR/" >> "$SHARD_SCM"
        for src in "${SHARD_SRCS[@]}"; do
          printf ' "%s"' "$src" >> "$SHARD_SCM"
        done
        printf '))\n  (exit 0))\n' >> "$SHARD_SCM"
        (
          if [ "${USE_GOSH:-1}" = "1" ] && command -v gosh >/dev/null 2>&1; then
            "$GOSH_BIN" -usrfi.9 -ugauche.uvector -ugauche.process -uscheme.file -uscheme.bitwise -uscheme.process-context -I "$ULISP_DIR" -I "$ROOT_DIR" "$SHARD_SCM"
          else
            "$PYTHON_BIN" -m ilisp "$SHARD_SCM"
          fi
        ) > "$MUSL_BUILD_DIR/musl_shard_${s}.log" 2>&1 &
        PIDS+=("$!")
      fi
    fi
  done

  COMPILE_RC=0
  for idx in "${!PIDS[@]}"; do
    if ! wait "${PIDS[$idx]}"; then
      echo "ERROR: musl compilation shard $idx failed:" >&2
      cat "$MUSL_BUILD_DIR/musl_shard_${idx}.log" >&2 || true
      COMPILE_RC=1
    fi
  done
  rm -f "$MUSL_BUILD_DIR"/musl_shard_*.scm "$MUSL_BUILD_DIR"/musl_shard_*.log
  if [ "$COMPILE_RC" -ne 0 ]; then
    exit 1
  fi
  T1="$(date +%s)"
  echo "  [PASS] Compiled ${#MISSING_OBJS[@]} musl-1.2.5 translation units in $((T1 - T0))s"
else
  echo "  [INFO] Using cached musl-1.2.5 ELF64 objects in $MUSL_OBJ_DIR (set REBUILD_MUSL=1 to force rebuild)"
fi

# -----------------------------------------------------------------------
# 5. Archive build/musl_build/obj/lib/crt1.o and build/musl_build/obj/lib/libc.a
# -----------------------------------------------------------------------
cp -f "$MUSL_OBJ_DIR/crt1.o" "$MUSL_LIB_DIR/crt1.o"
rm -f "$MUSL_LIB_DIR/libc.a"
ar rcsD "$MUSL_LIB_DIR/libc.a" "${LIBC_OBJS[@]}"
echo "  [PASS] Produced musl artifacts: $MUSL_LIB_DIR/crt1.o ($(stat -c%s "$MUSL_LIB_DIR/crt1.o")B) & $MUSL_LIB_DIR/libc.a ($(stat -c%s "$MUSL_LIB_DIR/libc.a")B, ${#LIBC_OBJS[@]} members)"

# -----------------------------------------------------------------------
# 6. Smoke Test: Link & Run Standalone Static Binary against musl via Pass 144 Linker
# -----------------------------------------------------------------------
SMOKE_DIR="$ULISP_DIR/build/musl_smoke_tmp_$$"
mkdir -p "$SMOKE_DIR"
trap 'rm -rf "$SMOKE_DIR"' EXIT

cat > "$SMOKE_DIR/main42.c" << 'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char **argv) {
    char buf[64];
    int x = (int)sqrt(1764.0);
    snprintf(buf, sizeof(buf), "musl_ok=%d", x);
    if (strcmp(buf, "musl_ok=42") != 0) return 1;
    return x;
}
EOF

"${RUN_CC[@]}" -D_XOPEN_SOURCE=700 -nostdinc \
  -I "$MUSL_BUILD_DIR/include" \
  -I "$MUSL_DIR/arch/x86_64" \
  -I "$MUSL_DIR/arch/generic" \
  -I "$MUSL_DIR/include" \
  -c "$SMOKE_DIR/main42.c" -o "$SMOKE_DIR/main42.o"

# Strip ld/cc/gcc from PATH to prove zero host linker invocation
NOHOST_BIN="$SMOKE_DIR/nohostbin"
mkdir -p "$NOHOST_BIN"
for tool in uname env sh bash cat rm mkdir chmod; do
  if command -v "$tool" >/dev/null 2>&1; then
    ln -sf "$(command -v "$tool")" "$NOHOST_BIN/$tool"
  fi
done

PATH="$NOHOST_BIN" "${RUN_CC[@]}" --linker=ulisp -static -nostdlib \
  "$MUSL_LIB_DIR/crt1.o" "$SMOKE_DIR/main42.o" "$MUSL_LIB_DIR/libc.a" \
  -o "$SMOKE_DIR/main42_static"

set +e
"$SMOKE_DIR/main42_static"
RC=$?
set -e
if [ "$RC" -ne 42 ]; then
  echo "ERROR: Expected exit code 42 from musl static smoke binary, got $RC" >&2
  exit 1
fi
echo "  [PASS] Standalone musl static smoke binary (main42_static) executed and returned exit code 42"

FILE_OUT="$(file "$SMOKE_DIR/main42_static")"
if ! echo "$FILE_OUT" | grep -q "statically linked"; then
  echo "ERROR: Expected statically linked ELF64 binary, got: $FILE_OUT" >&2
  exit 1
fi
LDD_OUT="$(ldd "$SMOKE_DIR/main42_static" 2>&1 || true)"
if ! echo "$LDD_OUT" | grep -qE "not a dynamic executable|statically linked"; then
  echo "ERROR: Expected 'not a dynamic executable' from ldd, got: $LDD_OUT" >&2
  exit 1
fi
if ! readelf -l "$SMOKE_DIR/main42_static" | grep -A1 "GNU_STACK" | grep -q "RW "; then
  echo "ERROR: Expected non-executable GNU_STACK (RW) in main42_static" >&2
  exit 1
fi
echo "  [PASS] Verified file ('statically linked'), ldd ('not a dynamic executable'), and W^X GNU_STACK (RW)"
echo "========================================================================"
echo " SUCCESS: musl-${MUSL_VER} x86-64 Self-Build & Pass 144 Linker Verification PASSED!"
echo "========================================================================"
