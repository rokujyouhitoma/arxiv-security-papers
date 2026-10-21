#!/bin/bash
set -euo pipefail

echo "=== ULisp Self-Hosting Bootstrap Verification ==="

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ULISP_DIR="$ROOT_DIR/ulisp"
BUILD_DIR="$ULISP_DIR/build"

mkdir -p "$BUILD_DIR"

# Apply compiler profile for self-hosting compiler execution (Issue #567)
export ULISP_GC_PROFILE=compiler

echo "[0/4] Preparing unified compiler (lib/ + compiler.scm)..."
make -C "$ULISP_DIR" compiler
echo '(!gc none)' > "$BUILD_DIR/ulisp_core.scm"
cat "$ULISP_DIR/lib/posix.scm" \
    "$ULISP_DIR/lib/list.scm" \
    "$ULISP_DIR/lib/string.scm" \
    "$ULISP_DIR/lib/port.scm" \
    "$ULISP_DIR/lib/printer.scm" \
    "$ULISP_DIR/lib/reader.scm" \
    "$ULISP_DIR/lib/equality.scm" \
    "$ULISP_DIR/lib/predicates.scm" \
    "$ULISP_DIR/lib/bytevector.scm" \
    "$ULISP_DIR/lib/vector.scm" \
    "$ULISP_DIR/lib/promise.scm" \
    "$ULISP_DIR/lib/exception.scm" \
    "$ULISP_DIR/lib/values.scm" \
    "$ULISP_DIR/lib/continuation.scm" \
    "$ULISP_DIR/lib/parameter.scm" \
    "$ULISP_DIR/lib/gc.scm" \
    "$ULISP_DIR/runtime/gc.scm" \
    "$ULISP_DIR/runtime/io.scm" \
    "$ULISP_DIR/runtime/printer.scm" \
    "$ULISP_DIR/runtime/entry.scm" \
    "$ULISP_DIR/compiler.scm" >> "$BUILD_DIR/ulisp_core.scm"

PYTHON_BIN="python3"
if [ -x "$ROOT_DIR/.venv/bin/python" ]; then
    PYTHON_BIN="$ROOT_DIR/.venv/bin/python"
fi
BOOT_BIN="$ULISP_DIR/bin/ulisp-boot"
GOSH_BIN="$(command -v gosh 2>/dev/null || true)"

check_asm_output() {
    local stage_name="$1"
    local asm_file="$2"
    if [ ! -s "$asm_file" ]; then
        echo -e "\033[1;31m[ERROR] $stage_name produced an empty assembly file: $asm_file\033[0m" >&2
        exit 1
    fi
    if grep -q "^\*\*\* ERROR:" "$asm_file"; then
        echo -e "\033[1;31m[ERROR] $stage_name failed with Scheme runtime exception:\033[0m" >&2
        cat "$asm_file" >&2
        exit 1
    fi
}

run_stage() {
    local stage_name="$1"
    local asm_file="$2"
    shift 2
    local rc=0
    "$@" < "$BUILD_DIR/ulisp_core.scm" > "$asm_file" 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo -e "\033[1;31m[ERROR] $stage_name execution failed with exit code $rc:\033[0m" >&2
        if [ -s "$asm_file" ]; then
            cat "$asm_file" >&2
        fi
        exit 1
    fi
    check_asm_output "$stage_name" "$asm_file"
}

if [ "${BOOTSTRAP_FAST:-0}" = "1" ] && [ -x "$BUILD_DIR/scheme-stage1" ] && [ "$BUILD_DIR/scheme-stage1" -nt "$BUILD_DIR/ulisp_core.scm" ]; then
    echo "[1/3] Stage 1: Skipping compilation (BOOTSTRAP_FAST=1, reusing existing scheme-stage1)..."
elif [ "${FULL_BOOTSTRAP:-0}" != "1" ] && [ "${BOOTSTRAP_FROM_ILISP:-0}" != "1" ] && [ "${BOOTSTRAP_WITH_GOSH:-0}" != "1" ] && [ -x "$BOOT_BIN" ]; then
    echo "[1/3] Stage 1: Fast compiling ulisp_core.scm using native seed ($BOOT_BIN)..."
    run_stage "Stage 1 ($BOOT_BIN)" "$BUILD_DIR/stage1.s" "$BOOT_BIN" "$BUILD_DIR/ulisp_core.scm"
    gcc -nostdlib -static "$BUILD_DIR/stage1.s" -o "$BUILD_DIR/scheme-stage1"
elif [ "${BOOTSTRAP_WITH_GOSH:-0}" = "1" ] && [ -n "$GOSH_BIN" ]; then
    echo "[1/3] Stage 1: Fast compiling ulisp_core.scm using Gauche ($GOSH_BIN)..."
    run_stage "Stage 1 (Gauche)" "$BUILD_DIR/stage1.s" "$GOSH_BIN" "$ULISP_DIR/compiler.scm"
    gcc -nostdlib -static "$BUILD_DIR/stage1.s" -o "$BUILD_DIR/scheme-stage1"
else
    echo "[1/3] Stage 1: Compiling ulisp_core.scm with ILisp ($PYTHON_BIN)..."
    run_stage "Stage 1 (ILisp)" "$BUILD_DIR/stage1.s" env PYTHONPATH="$ROOT_DIR" "$PYTHON_BIN" -m ilisp "$ULISP_DIR/compiler.scm"
    gcc -nostdlib -static "$BUILD_DIR/stage1.s" -o "$BUILD_DIR/scheme-stage1"
fi

echo "[2/3] Stage 2: Compiling ulisp_core.scm with Stage 1 compiler..."
run_stage "Stage 2 (scheme-stage1)" "$BUILD_DIR/stage2.s" "$BUILD_DIR/scheme-stage1" "$BUILD_DIR/ulisp_core.scm"
gcc -nostdlib -static "$BUILD_DIR/stage2.s" -o "$BUILD_DIR/scheme-stage2"

echo "[3/3] Stage 3: Compiling ulisp_core.scm with Stage 2 compiler..."
run_stage "Stage 3 (scheme-stage2)" "$BUILD_DIR/stage3.s" "$BUILD_DIR/scheme-stage2" "$BUILD_DIR/ulisp_core.scm"
gcc -nostdlib -static "$BUILD_DIR/stage3.s" -o "$BUILD_DIR/scheme-stage3"

echo "=== Verifying Fixed Point (diff stage2.s stage3.s) ==="
if cmp -s "$BUILD_DIR/stage2.s" "$BUILD_DIR/stage3.s"; then
    echo -e "\033[1;32mSUCCESS: Stage 2 and Stage 3 outputs are bit-for-bit IDENTICAL!\033[0m"
    echo "Fixed-point bootstrap verified successfully with Thin Debug Runtime & Scheme stdlib."
    
    # Smoke test Stage 3 binary
    echo "=== Running Smoke Test on Stage 3 Binary ==="
    echo "42" | ULISP_QUIET=1 "$BUILD_DIR/scheme-stage3" > "$BUILD_DIR/smoke_test.s" 2>/dev/null
    gcc -nostdlib -static "$BUILD_DIR/smoke_test.s" -o "$BUILD_DIR/smoke_test"
    SMOKE_OUT="$("$BUILD_DIR/smoke_test" 2>/dev/null || true)"
    if [ "$SMOKE_OUT" = "42" ]; then
        echo -e "\033[1;32mPASS: Stage 3 binary produced functional executable (output: 42).\033[0m"
    else
        echo -e "\033[1;31mFAIL: Stage 3 smoke test returned unexpected output: '$SMOKE_OUT'\033[0m" >&2
        exit 1
    fi

    mkdir -p "$ULISP_DIR/bin"
    cp -f "$BUILD_DIR/scheme-stage3" "$BOOT_BIN"
    chmod +x "$BOOT_BIN"
    echo "Updated local bootstrap seed cache ($BOOT_BIN) with verified Stage 3 compiler."
    exit 0
else
    echo -e "\033[1;31mFAILURE: Discrepancy detected between stage2.s and stage3.s\033[0m" >&2
    diff -u "$BUILD_DIR/stage2.s" "$BUILD_DIR/stage3.s" | head -n 50
    exit 1
fi
