#!/usr/bin/env bash
# ==============================================================================
# ULisp Pure Self-Contained Bootstrap & Toolchain Isolation Test Suite
# Conforms to DSN-33 Architecture Specification & Issue #617
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ULISP_DIR/build/test_pure_bootstrap"
STUBS_DIR="$BUILD_DIR/isolated_stubs"
COMPILER="$ULISP_DIR/bin/ulisp-boot"

mkdir -p "$BUILD_DIR" "$STUBS_DIR"

echo "========================================================================"
echo " Starting Pure Self-Contained Bootstrap Isolation Suite (#617)"
echo " Environment: gcc, clang, ld, python, gosh completely masked by stubs"
echo "========================================================================"

if [ ! -x "$COMPILER" ]; then
    echo "Bootstrap compiler $COMPILER not found, preparing seed..."
    make -C "$ULISP_DIR" compiler build/ulisp_stdlib.o
fi

# Ensure ulisp_stdlib.o exists before masking toolchains
make -C "$ULISP_DIR" build/ulisp_stdlib.o >/dev/null 2>&1

PASS_COUNT=0
TOTAL_COUNT=0

# ------------------------------------------------------------------------------
# 1. Setup Shadow Stubs (Exit code 99 upon invocation)
# ------------------------------------------------------------------------------
create_failing_stub() {
    local tool_name="$1"
    local stub_path="$STUBS_DIR/$tool_name"
    cat <<EOF > "$stub_path"
#!/bin/sh
echo "FATAL: Host external tool '$tool_name' was unexpectedly invoked in pure bootstrap mode!" >&2
exit 99
EOF
    chmod +x "$stub_path"
}

for tool in gcc clang ld python python3 gosh; do
    create_failing_stub "$tool"
done

# Prepend stubs directory to PATH to completely mask external toolchains
ORIGINAL_PATH="$PATH"
export PATH="$STUBS_DIR:$PATH"

# ------------------------------------------------------------------------------
# 2. Verify Stub Masking
# ------------------------------------------------------------------------------
echo "--- Step 1: Verifying Host Toolchain Shadowing ---"
for tool in gcc clang ld python python3 gosh; do
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    set +e
    "$tool" >/dev/null 2>&1
    tool_rc=$?
    set -e
    if [ "$tool_rc" -ne 99 ]; then
        echo "  [FAIL] Tool '$tool' was not properly masked (exit code: $tool_rc, expected 99)"
        exit 1
    fi
    PASS_COUNT=$((PASS_COUNT + 1))
    printf "  \033[32m[PASS]\033[0m Shadow stub verified for '%s' (exited with code 99)\n" "$tool"
done

# ------------------------------------------------------------------------------
# 3. Direct-to-ELF Mode Isolation Verification
# ------------------------------------------------------------------------------
echo "--- Step 2: Direct-to-ELF (--target-elf) Zero-Host-Tool Verification ---"
TOTAL_COUNT=$((TOTAL_COUNT + 1))
TEST1_BIN="$BUILD_DIR/pure_direct_elf"
"$COMPILER" -e '(display (+ (* 6 7) 0)) (newline)' --target-elf -o "$TEST1_BIN"
OUT1="$("$TEST1_BIN")"
if [ "$OUT1" != "42" ]; then
    echo "  [FAIL] Direct-to-ELF returned unexpected output: '$OUT1'"
    exit 1
fi
PASS_COUNT=$((PASS_COUNT + 1))
printf "  \033[32m[PASS]\033[0m Direct-to-ELF executable generated without external tools (output: %s)\n" "$OUT1"

# ------------------------------------------------------------------------------
# 4. Built-in Relocatable Object (-c) & Linker (--ld) Isolation Verification
# ------------------------------------------------------------------------------
echo "--- Step 3: Built-in Relocatable Object (-c) & Static Linker (--ld) Verification ---"
TOTAL_COUNT=$((TOTAL_COUNT + 1))
TEST2_SCM="$BUILD_DIR/test_pure_obj.scm"
TEST2_OBJ="$BUILD_DIR/test_pure_obj.o"
TEST2_BIN="$BUILD_DIR/test_pure_obj_bin"
cat <<'EOF' > "$TEST2_SCM"
(define (fact n)
  (if (<= n 1)
      1
      (* n (fact (- n 1)))))
(fact 5)
EOF
"$COMPILER" -c "$TEST2_SCM" -o "$TEST2_OBJ"
"$COMPILER" --ld "$TEST2_OBJ" -o "$TEST2_BIN"
OUT2="$(ULISP_PRINT_RESULT=1 "$TEST2_BIN")"
if [ "$OUT2" != "120" ]; then
    echo "  [FAIL] Built-in -c and --ld returned unexpected output: '$OUT2'"
    exit 1
fi
PASS_COUNT=$((PASS_COUNT + 1))
printf "  \033[32m[PASS]\033[0m Built-in object compiler & static linker produced working executable (output: %s)\n" "$OUT2"

# ------------------------------------------------------------------------------
# 5. Split-Link Standard Library Integration via Built-in Linker (--ld)
# ------------------------------------------------------------------------------
echo "--- Step 4: Split-Link Runtime Integration with Built-in Linker (--ld) ---"
TOTAL_COUNT=$((TOTAL_COUNT + 1))
TEST3_SCM="$BUILD_DIR/test_pure_split.scm"
TEST3_OBJ="$BUILD_DIR/test_pure_split.o"
TEST3_BIN="$BUILD_DIR/test_pure_split_bin"
cat <<'EOF' > "$TEST3_SCM"
(include "ulisp/lib/stdlib_macros.scm")
(display "PureBootstrap:")
(display (+ 40 2))
(newline)
EOF
"$COMPILER" -I "$ULISP_DIR/.." -c "$TEST3_SCM" -o "$TEST3_OBJ" --allow-extern
"$COMPILER" --ld "$ULISP_DIR/build/ulisp_stdlib.o" "$TEST3_OBJ" -o "$TEST3_BIN"
OUT3="$("$TEST3_BIN")"
if [ "$OUT3" != "PureBootstrap:42" ]; then
    echo "  [FAIL] Split-link built-in static linker returned unexpected output: '$OUT3'"
    exit 1
fi
PASS_COUNT=$((PASS_COUNT + 1))
printf "  \033[32m[PASS]\033[0m Split-link executable linked with builtin --ld (output: %s)\n" "$OUT3"

# ------------------------------------------------------------------------------
# 6. Full 3-Stage Bootstrap Chain Verification Under Toolchain Isolation
# ------------------------------------------------------------------------------
echo "--- Step 5: Full 3-Stage Bootstrap Chain Verification (./bootstrap.sh --pure) ---"
TOTAL_COUNT=$((TOTAL_COUNT + 1))
cd "$ULISP_DIR"
./bootstrap.sh --pure

# Verify bit-for-bit identical fixed point
if ! cmp -s "$ULISP_DIR/build/stage2_compiler.s" "$ULISP_DIR/build/stage3_compiler.s"; then
    echo "  [FAIL] Stage 2 and Stage 3 assembly outputs are not bit-for-bit identical!"
    exit 1
fi
if ! cmp -s "$ULISP_DIR/build/scheme-stage2" "$ULISP_DIR/build/scheme-stage3"; then
    echo "  [FAIL] Stage 2 and Stage 3 binaries are not bit-for-bit identical!"
    exit 1
fi
PASS_COUNT=$((PASS_COUNT + 1))
printf "  \033[32m[PASS]\033[0m Full 3-Stage bootstrap reached bit-for-bit fixed point under tool isolation\n"

# Restore original PATH
export PATH="$ORIGINAL_PATH"

echo "========================================================================"
printf " All %d / %d Pure Self-Contained Bootstrap Tests PASSED!\n" "$PASS_COUNT" "$TOTAL_COUNT"
echo "========================================================================"
