#!/bin/bash
set -euo pipefail

echo "=== ULisp Self-Hosting Bootstrap Verification ==="

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ULISP_DIR="$ROOT_DIR/ulisp"
BUILD_DIR="$ULISP_DIR/build"

mkdir -p "$BUILD_DIR"

echo "[0/4] Preparing unified compiler (lib/ + compiler.scm)..."
cat "$ULISP_DIR/lib/string.scm" \
    "$ULISP_DIR/lib/printer.scm" \
    "$ULISP_DIR/lib/reader.scm" \
    "$ULISP_DIR/compiler.scm" > "$BUILD_DIR/ulisp_core.scm"

echo "[1/4] Compiling runtime.c (Thin Debug Runtime)..."
gcc -O2 -c "$ULISP_DIR/runtime.c" -o "$BUILD_DIR/runtime.o"

echo "[2/4] Stage 1: Compiling ulisp_core.scm with ILisp (Python)..."
PYTHONPATH="$ROOT_DIR" python3 -m ilisp "$ULISP_DIR/compiler.scm" < "$BUILD_DIR/ulisp_core.scm" > "$BUILD_DIR/stage1.s"
gcc -no-pie "$BUILD_DIR/stage1.s" "$BUILD_DIR/runtime.o" -o "$BUILD_DIR/scheme-stage1"

echo "[3/4] Stage 2: Compiling ulisp_core.scm with Stage 1 compiler..."
"$BUILD_DIR/scheme-stage1" "$BUILD_DIR/ulisp_core.scm" > "$BUILD_DIR/stage2.s"
gcc -no-pie "$BUILD_DIR/stage2.s" "$BUILD_DIR/runtime.o" -o "$BUILD_DIR/scheme-stage2"

echo "[4/4] Stage 3: Compiling ulisp_core.scm with Stage 2 compiler..."
"$BUILD_DIR/scheme-stage2" "$BUILD_DIR/ulisp_core.scm" > "$BUILD_DIR/stage3.s"

echo "=== Verifying Fixed Point (diff stage2.s stage3.s) ==="
if cmp -s "$BUILD_DIR/stage2.s" "$BUILD_DIR/stage3.s"; then
    echo "SUCCESS: Stage 2 and Stage 3 outputs are bit-for-bit IDENTICAL!"
    echo "Fixed-point bootstrap verified successfully with Thin Debug Runtime & Scheme stdlib."
    exit 0
else
    echo "FAILURE: Discrepancy detected between stage2.s and stage3.s"
    diff -u "$BUILD_DIR/stage2.s" "$BUILD_DIR/stage3.s" | head -n 50
    exit 1
fi
