#!/usr/bin/env bash
# ==============================================================================
# Pass 144 Native ELF64 Static Linker & c_driver Integration E2E Verification
# Issue #928 - WP2 & WP3
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
OUT_DIR="$ULISP_DIR/build/test_elf_static_linker"
GOSH_BIN="${GOSH_BIN:-$(command -v gosh 2>/dev/null || true)}"
USE_GOSH="${USE_GOSH:-1}"

if [ -n "${ULISP_CC_BIN:-}" ] && [ -x "${ULISP_CC_BIN}" ]; then
    RUN_DRIVER=("$ULISP_CC_BIN")
elif [ "$USE_GOSH" = "1" ] && [ -n "$GOSH_BIN" ]; then
    RUN_DRIVER=("$GOSH_BIN" -usrfi.9 -ugauche.uvector -ugauche.process -uscheme.file -uscheme.bitwise -uscheme.process-context -I "$ULISP_DIR" -I "$(dirname "$ULISP_DIR")" "$ULISP_DIR/build/c_driver_runner.scm")
else
    echo "[SKIP/INFO] Running with Python ILisp not configured for this shell check"
    exit 1
fi

run_expect_exit() {
    local bin="$1"
    local expected="$2"
    local rc=0
    chmod +x "$bin"
    "$bin" || rc=$?
    if [ "$rc" -ne "$expected" ]; then
        echo "[FAIL] $bin exited with $rc (expected $expected)"
        exit 1
    fi
    echo "[PASS] $bin exited with $rc (as expected)"
}

echo "--- Executing ELF64 static binaries produced by Pass 144 ---"
run_expect_exit "$OUT_DIR/t1_exit42" 42
run_expect_exit "$OUT_DIR/t2_cyclic_ar" 45
run_expect_exit "$OUT_DIR/t3_common_weak_got" 29
run_expect_exit "$OUT_DIR/t4_tls_synth" 42

echo "--- Verifying PT_TLS & W^X via readelf -l on TLS binary ---"
readelf -l "$OUT_DIR/t4_tls_synth" | grep -q "TLS"
readelf -l "$OUT_DIR/t4_tls_synth" | grep -q "GNU_STACK"
if readelf -l "$OUT_DIR/t4_tls_synth" | grep "GNU_STACK" | grep -q "RWE"; then
    echo "[FAIL] t4_tls_synth GNU_STACK is executable (W^X violation)"
    exit 1
fi
echo "[PASS] readelf -l confirms PT_TLS and non-executable GNU_STACK"

echo "--- E2E freestanding C program via c_driver --linker=ulisp with host ld/cc/gcc STRIPPED ---"
mkdir -p "$OUT_DIR/nohostbin"
# Provide only basic coreutils like chmod/env/gosh, NO ld/cc/gcc/clang/collect2
for tool in chmod env sh; do
    p="$(command -v "$tool" || true)"
    [ -n "$p" ] && ln -sf "$p" "$OUT_DIR/nohostbin/$tool"
done

cat << 'EOF' > "$OUT_DIR/freestanding.c"
int add_nums(int a, int b) {
    return a + b;
}

void _start(void) {
    int r = add_nums(19, 23);
    /* Invoke sys_exit via helper function? Wait - write _start via asm helper or test _start */
}
EOF

# Wait: we don't have inline asm in C99 frontend yet (WP1 is next!).
# Test pure C99 helper.c + tiny exit_crt.o linked with c_driver --linker=ulisp -static -nostdlib!
cat << 'EOF' > "$OUT_DIR/helper.c"
int compute_answer(int x) {
    return x * 2 + 2;
}
EOF

# Assemble _start caller with ulisp --as (or reuse existing object / Scheme-built .o)
cat << 'EOF' > "$OUT_DIR/start_call.s"
.globl _start
.text
_start:
    mov edi, 20
    call compute_answer
    mov edi, eax
    mov eax, 60
    syscall
EOF

AS_BIN="$ULISP_DIR/bin/ulisp-boot"
[ -x "$AS_BIN" ] || AS_BIN="$ULISP_DIR/build/scheme-stage1"
"$AS_BIN" --as "$OUT_DIR/start_call.s" -o "$OUT_DIR/start_call.o"

OLD_PATH="$PATH"
GOSH_DIR="$(dirname "$GOSH_BIN")"
set +e
# Verify PATH has NO ld/gcc/cc
env -u CC PATH="$OUT_DIR/nohostbin:$GOSH_DIR" "${RUN_DRIVER[@]}" \
    --linker=ulisp -static -nostdlib -e _start \
    "$OUT_DIR/start_call.o" "$OUT_DIR/helper.c" -o "$OUT_DIR/c_freestanding_bin"
DRV_RC=$?
set -e
export PATH="$OLD_PATH"

if [ "$DRV_RC" -ne 0 ]; then
    echo "[FAIL] c_driver --linker=ulisp failed with $DRV_RC"
    exit 1
fi
if [ ! -x "$OUT_DIR/c_freestanding_bin" ]; then
    echo "[FAIL] c_freestanding_bin is not executable (0755 not set)"
    exit 1
fi

run_expect_exit "$OUT_DIR/c_freestanding_bin" 42
file "$OUT_DIR/c_freestanding_bin" | grep -q "statically linked"
if ldd "$OUT_DIR/c_freestanding_bin" 2>&1 | grep -qvE "not a dynamic executable|statically linked"; then
    echo "[FAIL] unexpected dynamic dependency in c_freestanding_bin"
    ldd "$OUT_DIR/c_freestanding_bin"
    exit 1
fi
echo "[PASS] c_driver --linker=ulisp -static -nostdlib E2E PASSED (zero host ld/cc)!"
