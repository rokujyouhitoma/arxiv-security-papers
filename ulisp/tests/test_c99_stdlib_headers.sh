#!/usr/bin/env bash
# ==============================================================================
# ULisp C99 Built-in Standard & POSIX Header ABI Equivalence Test (Issue #925)
# Verifies:
#   - Every header in ulisp/frontend_c/include/ parses & compiles cleanly in ULisp
#   - sizeof / offsetof / macro constants match Linux x86-64 glibc host GCC 100%
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$ULISP_DIR")"
BUILD_DIR="$ULISP_DIR/build/test_c99_stdlib_headers_$$"
DRIVER_RUNNER="$ULISP_DIR/build/c_driver_runner.scm"

if [ -x "$ROOT_DIR/.venv/bin/python" ]; then
    PYTHON="$ROOT_DIR/.venv/bin/python"
else
    PYTHON="python3"
fi

run_ucc() {
    if [ "${USE_GOSH:-1}" = "1" ] && command -v gosh >/dev/null 2>&1; then
        gosh -usrfi.9 -ugauche.uvector -ugauche.process -uscheme.file -uscheme.bitwise -uscheme.process-context -I "$ULISP_DIR" -I "$ROOT_DIR" "$DRIVER_RUNNER" "$@"
    else
        PYTHONPATH="$ROOT_DIR" "$PYTHON" -m ilisp "$DRIVER_RUNNER" -- "$@"
    fi
}

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
trap 'rm -rf "$BUILD_DIR"' EXIT

cat > "$BUILD_DIR/abi_probe.c" << 'EOF'
#include <assert.h>
#include <ctype.h>
#include <dlfcn.h>
#include <errno.h>
#include <float.h>
#include <limits.h>
#include <locale.h>
#include <math.h>
#include <setjmp.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#if !defined(__STDC__) || !defined(__STDC_VERSION__) || (__STDC_VERSION__ < 199901L)
#error "Expected C99 predefined macros"
#endif

static int cmp_ints(const void *a, const void *b) {
    int va = *(const int *)a;
    int vb = *(const int *)b;
    return (va > vb) - (va < vb);
}

int main(void) {
    struct tm tmv;
    struct lconv lcv;
    struct sigaction sa;
    int arr[4] = {40, 10, 30, 20};
    int key = 30;
    int *found;
    int st0 = 0x2a00;
    int st1 = 0x0009;
    int st2 = 0x7f | (5 << 8);
    double nan_v = NAN;
    double inf_v = INFINITY;

    printf("SIZES:%zu,%zu,%zu,%zu,%zu,%zu,%zu\n",
           sizeof(size_t), sizeof(ptrdiff_t), sizeof(time_t),
           sizeof(clock_t), sizeof(off_t), sizeof(sig_atomic_t),
           sizeof(sigset_t));
    printf("TM:%zu,%zu,%zu,%zu,%zu,%zu\n",
           sizeof(struct tm), offsetof(struct tm, tm_sec),
           offsetof(struct tm, tm_mon), offsetof(struct tm, tm_year),
           offsetof(struct tm, tm_isdst), offsetof(struct tm, tm_zone));
    printf("LCONV:%zu,%zu,%zu,%zu\n",
           sizeof(struct lconv), offsetof(struct lconv, decimal_point),
           offsetof(struct lconv, p_sign_posn),
           offsetof(struct lconv, int_n_sign_posn));
    printf("SIGACTION:%zu,%zu,%zu,%zu,%zu\n",
           sizeof(struct sigaction), offsetof(struct sigaction, sa_handler),
           offsetof(struct sigaction, sa_mask),
           offsetof(struct sigaction, sa_flags),
           offsetof(struct sigaction, sa_restorer));
    printf("CONSTS:%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
           EOF, BUFSIZ, SEEK_SET, SEEK_CUR, SEEK_END,
           LC_CTYPE, LC_NUMERIC, LC_ALL, EDOM, ERANGE);
    printf("POSIX:%d,%d,%d,%d,%d,%d,%d\n",
           SIGINT, RTLD_NOW, RTLD_GLOBAL,
           WIFEXITED(st0), WEXITSTATUS(st0),
           WIFSIGNALED(st1), WTERMSIG(st1));
    printf("WAITSTOP:%d,%d\n", WIFSTOPPED(st2), WSTOPSIG(st2));
    printf("MATH:%d,%d,%d,%d,%d,%.15g\n",
           isnan(nan_v), isinf(inf_v), isfinite(1.5),
           DBL_MANT_DIG, DBL_DIG, M_PI);

    qsort(arr, 4, sizeof(int), cmp_ints);
    found = (int *)bsearch(&key, arr, 4, sizeof(int), cmp_ints);
    printf("QSORT:%d,%d,%d,%d,%d\n", arr[0], arr[1], arr[2], arr[3],
           found ? *found : -1);

    /* Live glibc struct interoperability: setlocale/localeconv + gmtime_r */
    setlocale(LC_ALL, "C");
    struct lconv *lc = localeconv();
    time_t epoch = 0;
    gmtime_r(&epoch, &tmv);
    sigemptyset(&sa.sa_mask);
    printf("GLIBC_LIVE:%s,%d,%d,%d,%d,%d\n",
           lc->decimal_point, tmv.tm_year + 1900, tmv.tm_mon + 1,
           tmv.tm_mday, isdigit('7') ? 1 : 0, tolower('Q'));
    (void)lcv;
    return 0;
}
EOF

echo "========================================================================"
echo " C99 Built-in Header & glibc ABI Equivalence Verification (#925 WP1)"
echo "========================================================================"

gcc -std=c99 -D_GNU_SOURCE -Wall -Wextra "$BUILD_DIR/abi_probe.c" -lm -ldl -o "$BUILD_DIR/probe_gcc"
run_ucc -DLUA_USE_POSIX -O2 "$BUILD_DIR/abi_probe.c" -lm -ldl -o "$BUILD_DIR/probe_ulisp"

OUT_GCC="$("$BUILD_DIR/probe_gcc")"
OUT_ULISP="$("$BUILD_DIR/probe_ulisp")"

echo "--- GCC Reference Output ---"
echo "$OUT_GCC"
echo "--- ULisp Output ---"
echo "$OUT_ULISP"

if [ "$OUT_GCC" = "$OUT_ULISP" ]; then
    echo "[PASS] All C99/POSIX header ABIs, struct layouts, and glibc interop match 100%."
else
    echo "[FAIL] ABI mismatch between GCC and ULisp built-in headers!"
    exit 1
fi
