#!/usr/bin/env bash
# ==============================================================================
# ULisp Differential Testing & Fuzzing: x86-64 vs C99 Backends (Issue #831)
# Conforms to DSN-33 Architecture Specification & DSN-38 Section 2 E10 / K3
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ULISP_DIR"
BUILD_DIR="$ULISP_DIR/build/diff_fuzz"

mkdir -p "$BUILD_DIR"

echo "========================================================================"
echo " Starting Differential LIR Testing & Fuzzing Suite (Issue #831)"
echo " Comparing: x86-64 (Pass 140: as+ld) vs Portable C99 (Pass 160: gcc -O2)"
echo "========================================================================"

# Determine Scheme runner
PYTHON="${PYTHON:-python3}"
ROOT_DIR="$(dirname "$ULISP_DIR")"
if [ -x "$ROOT_DIR/.venv/bin/python" ]; then
    PYTHON="$ROOT_DIR/.venv/bin/python"
fi
RUN_SCHEME="env PYTHONPATH=$ROOT_DIR $PYTHON -m ilisp"

# Step 1: Ensure compiler passes are generated
make -C "$ULISP_DIR" build/compiler_passes.scm

# Step 2: Generate test cases
cat "$ULISP_DIR/build/compiler_passes.scm" \
    "$ULISP_DIR/tests/passes/common.scm" \
    "$ULISP_DIR/tests/fuzz_lir_differential.scm" > "$ULISP_DIR/build/fuzz_generator_runner.scm"

$RUN_SCHEME "$ULISP_DIR/build/fuzz_generator_runner.scm"

MANIFEST="$BUILD_DIR/manifest.txt"
if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: Manifest $MANIFEST not generated!"
    exit 1
fi

PASS_COUNT=0
TOTAL_COUNT=0

while IFS= read -r test_name || [ -n "$test_name" ]; do
    [ -z "$test_name" ] && continue
    TOTAL_COUNT=$((TOTAL_COUNT + 1))

    s_file="$BUILD_DIR/${test_name}.s"
    o_file="$BUILD_DIR/${test_name}.o"
    bin_x86="$BUILD_DIR/${test_name}_x86"

    c_file="$BUILD_DIR/${test_name}.c"
    bin_c="$BUILD_DIR/${test_name}_c"

    # 1. Compile x86-64
    as --64 "$s_file" -o "$o_file"
    ld -m elf_x86_64 -static "$o_file" -o "$bin_x86"

    # 2. Compile C99 with strict flags
    gcc -std=c99 -O2 -Wall -Wextra -Werror -pedantic "$c_file" -o "$bin_c"

    # 3. Execute x86-64
    out_x86=""
    exit_x86=0
    out_x86=$(ULISP_PRINT_RESULT=1 "$bin_x86" 2>&1) || exit_x86=$?

    # 4. Execute C99
    out_c=""
    exit_c=0
    out_c=$(ULISP_PRINT_RESULT=1 "$bin_c" 2>&1) || exit_c=$?

    # 5. Differential assertion
    if [ "$out_x86" != "$out_c" ] || [ "$exit_x86" != "$exit_c" ]; then
        echo "  [FAIL] $test_name"
        echo "    x86-64 -> exit: $exit_x86, stdout: '$out_x86'"
        echo "    C99    -> exit: $exit_c, stdout: '$out_c'"
        exit 1
    fi

    PASS_COUNT=$((PASS_COUNT + 1))
    printf "  \033[32m[PASS]\033[0m %-28s (exit: %d, out: %s)\n" "$test_name" "$exit_x86" "$out_x86"

done < "$MANIFEST"

echo "========================================================================"
echo " All $PASS_COUNT / $TOTAL_COUNT Differential Fuzzing Tests PASSED Successfully!"
echo " 100% equivalence verified between x86-64 and C99."
echo "========================================================================"
