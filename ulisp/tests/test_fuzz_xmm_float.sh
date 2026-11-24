#!/usr/bin/env bash
# ==============================================================================
# ULisp 4-Way Floating-Point & SysV XMM ABI Differential Fuzzer (#924)
# Compares canonicalized IEEE 754 bit patterns & 64-bit FNV-1a hashes across:
#   Arm 1: Reference LIR VM (lir_interpreter.scm via fuzz_xmm_float_gen.scm)
#   Arm 2: Host GCC Oracle (gcc -std=c99 -O2 -fno-fast-math -ffp-contract=off)
#   Arm 3: Native x86-64 ELF (-O0, -O2 via Pass 144a/144, AND -S + GNU as + gcc)
#   Arm 4: Portable C99 (--target=c -O2, plus strict -Werror -pedantic)
# Configurable: FUZZ_SEED (default 20261122), FUZZ_COUNT (default 120)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$ULISP_DIR")"
FUZZ_SEED="${FUZZ_SEED:-20261122}"
FUZZ_COUNT="${FUZZ_COUNT:-120}"
BUILD_DIR="$ULISP_DIR/build/fuzz_xmm_float"
DRIVER_RUNNER="$ULISP_DIR/build/c_driver_runner.scm"
RUNNER_SCM="$ULISP_DIR/build/fuzz_xmm_float_runner.scm"

if [ -x "$ROOT_DIR/.venv/bin/python" ]; then
    PYTHON="$ROOT_DIR/.venv/bin/python"
else
    PYTHON="python3"
fi

run_scheme() {
    if [ "${USE_GOSH:-0}" = "1" ] && command -v gosh >/dev/null 2>&1; then
        gosh -usrfi.9 -ugauche.uvector -ugauche.process -uscheme.file -uscheme.bitwise -uscheme.process-context -I "$ULISP_DIR" -I "$ROOT_DIR" "$@"
    else
        PYTHONPATH="$ROOT_DIR" "$PYTHON" -m ilisp "$@"
    fi
}

run_ucc() {
    if [ -n "${ULISP_CC_BIN:-}" ] && [ -x "${ULISP_CC_BIN}" ]; then
        "$ULISP_CC_BIN" "$@"
    elif [ "${USE_GOSH:-0}" = "1" ] && command -v gosh >/dev/null 2>&1; then
        gosh -usrfi.9 -ugauche.uvector -ugauche.process -uscheme.file -uscheme.bitwise -uscheme.process-context -I "$ULISP_DIR" -I "$ROOT_DIR" "$DRIVER_RUNNER" "$@"
    else
        PYTHONPATH="$ROOT_DIR" "$PYTHON" -m ilisp "$DRIVER_RUNNER" -- "$@"
    fi
}

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

export FUZZ_SEED
export FUZZ_COUNT
export FUZZ_OUT_DIR="$BUILD_DIR"

echo "========================================================================"
echo " 4-Way Floating-Point & SysV XMM ABI Differential Fuzzer (#924)"
echo "  FUZZ_SEED=$FUZZ_SEED  FUZZ_COUNT=$FUZZ_COUNT"
echo "========================================================================"

run_scheme "$RUNNER_SCM"

SRC="$BUILD_DIR/fuzz_suite.c"
VM_OUT="$BUILD_DIR/out_vm.txt"

if [ ! -f "$SRC" ] || [ ! -f "$VM_OUT" ]; then
    echo "ERROR: Fuzzer generator did not produce $SRC / $VM_OUT"
    exit 1
fi

compare_outputs() {
    local arm_name="$1"
    local arm_out="$2"
    if ! diff -u "$BUILD_DIR/out_gcc.txt" "$arm_out" > "$BUILD_DIR/diff_${arm_name}.txt"; then
        echo "  [FAIL] DIVERGENCE DETECTED in arm: $arm_name (FUZZ_SEED=$FUZZ_SEED FUZZ_COUNT=$FUZZ_COUNT)"
        echo "  Reproducer C source: $SRC"
        head -n 40 "$BUILD_DIR/diff_${arm_name}.txt"
        exit 1
    fi
}

# Arm 2: Host GCC Reference Oracle
gcc -std=c99 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror "$SRC" -lm -o "$BUILD_DIR/fuzz_gcc"
"$BUILD_DIR/fuzz_gcc" > "$BUILD_DIR/out_gcc.txt"
compare_outputs "Reference_VM" "$VM_OUT"
echo "  [PASS] Arm 1 (Reference LIR VM) == Host GCC Oracle ($FUZZ_COUNT cases)"

# Arms 3 & 4: Run all 4 compilation & execution arms concurrently
(
    run_ucc -O0 "$SRC" -lm -o "$BUILD_DIR/fuzz_elf_-O0" &&
    "$BUILD_DIR/fuzz_elf_-O0" > "$BUILD_DIR/out_elf_-O0.txt"
) > "$BUILD_DIR/log_elf_-O0.txt" 2>&1 &
PID_O0=$!

(
    run_ucc -O2 "$SRC" -lm -o "$BUILD_DIR/fuzz_elf_-O2" &&
    "$BUILD_DIR/fuzz_elf_-O2" > "$BUILD_DIR/out_elf_-O2.txt"
) > "$BUILD_DIR/log_elf_-O2.txt" 2>&1 &
PID_O2=$!

(
    run_ucc -S -O2 "$SRC" -o "$BUILD_DIR/fuzz_elf.s" &&
    as --64 "$BUILD_DIR/fuzz_elf.s" -o "$BUILD_DIR/fuzz_as.o" &&
    gcc -no-pie "$BUILD_DIR/fuzz_as.o" -lm -o "$BUILD_DIR/fuzz_as_gcc" &&
    "$BUILD_DIR/fuzz_as_gcc" > "$BUILD_DIR/out_as.txt"
) > "$BUILD_DIR/log_as.txt" 2>&1 &
PID_AS=$!

(
    run_ucc -S --target=c -O2 "$SRC" -o "$BUILD_DIR/fuzz_portable.c" &&
    gcc -std=c99 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror -pedantic "$BUILD_DIR/fuzz_portable.c" -lm -o "$BUILD_DIR/fuzz_c" &&
    "$BUILD_DIR/fuzz_c" > "$BUILD_DIR/out_c.txt"
) > "$BUILD_DIR/log_c.txt" 2>&1 &
PID_C=$!

wait_arm() {
    local name="$1"
    local pid="$2"
    local log="$3"
    if ! wait "$pid"; then
        echo "  [FAIL] Build/execution failed in arm: $name"
        cat "$log"
        exit 1
    fi
}

wait_arm "Native_ELF_-O0" "$PID_O0" "$BUILD_DIR/log_elf_-O0.txt"
compare_outputs "Native_ELF_-O0" "$BUILD_DIR/out_elf_-O0.txt"
echo "  [PASS] Arm 3a (Native ELF -O0) == Host GCC Oracle ($FUZZ_COUNT cases)"

wait_arm "Native_ELF_-O2" "$PID_O2" "$BUILD_DIR/log_elf_-O2.txt"
compare_outputs "Native_ELF_-O2" "$BUILD_DIR/out_elf_-O2.txt"
echo "  [PASS] Arm 3a (Native ELF -O2) == Host GCC Oracle ($FUZZ_COUNT cases)"

wait_arm "Native_ASM_GNU_as" "$PID_AS" "$BUILD_DIR/log_as.txt"
compare_outputs "Native_ASM_GNU_as" "$BUILD_DIR/out_as.txt"
echo "  [PASS] Arm 3b (Native -S + GNU as) == Host GCC Oracle ($FUZZ_COUNT cases)"

wait_arm "Portable_C99_Strict" "$PID_C" "$BUILD_DIR/log_c.txt"
compare_outputs "Portable_C99_Strict" "$BUILD_DIR/out_c.txt"
echo "  [PASS] Arm 4 (Portable C99 -std=c99 -Werror -pedantic) == Host GCC Oracle ($FUZZ_COUNT cases)"

FINAL_HASH="$(grep '^HASH ' "$BUILD_DIR/out_gcc.txt" | awk '{print $2}')"
echo "========================================================================"
echo " All $FUZZ_COUNT / $FUZZ_COUNT Fuzz Cases PASSED with 0 Divergences across 4 Engines!"
echo " Canonical Final Hash (FNV-1a 64-bit): $FINAL_HASH"
echo "========================================================================"
