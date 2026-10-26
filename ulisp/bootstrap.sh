#!/bin/bash
set -euo pipefail

echo "=== ULisp Self-Hosting Bootstrap Verification ==="

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ULISP_DIR="$ROOT_DIR/ulisp"
BUILD_DIR="$ULISP_DIR/build"

mkdir -p "$BUILD_DIR"

# Apply compiler profile for self-hosting compiler execution (Issue #567)
export ULISP_GC_PROFILE=compiler

echo "[0/4] Preparing unified compiler (entry_core.scm)..."
make -C "$ULISP_DIR" -B compiler
cp "$ULISP_DIR/entry_core.scm" "$BUILD_DIR/ulisp_core.scm"

PYTHON_BIN="python3"
if [ -x "$ROOT_DIR/.venv/bin/python" ]; then
    PYTHON_BIN="$ROOT_DIR/.venv/bin/python"
fi
BOOT_BIN="$ULISP_DIR/bin/ulisp-boot"
GOSH_BIN="$(command -v gosh 2>/dev/null || true)"

# Diagnostic mode configuration (Issue #605)
BOOTSTRAP_DIAGNOSE="${BOOTSTRAP_DIAGNOSE:-1}"
_DIAGNOSING=0

diagnose_stage_failure() {
    local stage_name="$1"
    local asm_file="$2"
    local rc="$3"
    local reason="${4:-"Execution failure"}"
    local input_file="${5:-"$BUILD_DIR/ulisp_core.scm"}"

    # Prevent recursive invocation if fallback diagnosis itself fails
    if [ "${_DIAGNOSING:-0}" = "1" ]; then
        return
    fi
    _DIAGNOSING=1

    if [ "${BOOTSTRAP_DIAGNOSE:-1}" = "0" ] || [ "${BOOTSTRAP_DIAGNOSE:-1}" = "false" ] || [ "${BOOTSTRAP_DIAGNOSE:-1}" = "no" ]; then
        return
    fi

    local file_size=0
    if [ -f "$asm_file" ]; then
        file_size=$(wc -c < "$asm_file" 2>/dev/null || stat -c%s "$asm_file" 2>/dev/null || echo 0)
    fi

    # Classify error
    local err_category="Unknown Failure"
    if [ "$rc" -eq 139 ]; then
        err_category="Segmentation fault (SIGSEGV)"
    elif [ "$rc" -eq 134 ]; then
        err_category="Abort / Assertion Failure (SIGABRT)"
    elif [ "$rc" -ne 0 ]; then
        err_category="Non-zero exit code ($rc)"
    elif [ ! -s "$asm_file" ]; then
        err_category="Empty assembly output (0 bytes)"
    elif [ -s "$asm_file" ] && grep -q "^\*\*\* ERROR:" "$asm_file" 2>/dev/null; then
        err_category="Scheme runtime exception"
    fi

    echo >&2
    echo -e "\033[1;35m======================================================================\033[0m" >&2
    echo -e "\033[1;35m[DIAGNOSTIC ADVISORY] Bootstrap Stage Failure Detected!\033[0m" >&2
    echo -e "  \033[1mStage:\033[0m       $stage_name" >&2
    echo -e "  \033[1mExit Code:\033[0m   $rc" >&2
    echo -e "  \033[1mCategory:\033[0m    $err_category" >&2
    echo -e "  \033[1mReason:\033[0m      $reason" >&2
    echo -e "  \033[1mOutput File:\033[0m $asm_file (${file_size} bytes)" >&2
    echo -e "\033[1;35m======================================================================\033[0m" >&2

    # If the output file contained an error message, highlight it
    if [ -s "$asm_file" ] && grep -q "^\*\*\* ERROR:" "$asm_file" 2>/dev/null; then
        echo -e "\033[1;33m>>> Extracted Runtime Error Messages from Output:\033[0m" >&2
        grep -n "^\*\*\* ERROR:" "$asm_file" | head -n 10 >&2 || true
        echo -e "\033[1;35m----------------------------------------------------------------------\033[0m" >&2
    fi

    # Secondary diagnostic trace execution
    local diag_input="$BUILD_DIR/diag_input.scm"
    local diag_output="$BUILD_DIR/diag_trace.log"
    rm -f "$diag_output"

    # Prepend (!debug #t) to activate Issue #604 call stack tracking
    echo '(!debug #t)' > "$diag_input"
    if [ -f "$input_file" ]; then
        cat "$input_file" >> "$diag_input"
    fi

    if [ -n "$GOSH_BIN" ]; then
        echo -e "\033[1;36m>>> Executing Secondary Diagnostic Fallback Trace via Gauche ($GOSH_BIN)...\033[0m" >&2
        echo -e "\033[1;36m----------------------------------------------------------------------\033[0m" >&2
        local diag_rc=0
        if command -v timeout >/dev/null 2>&1; then
            timeout 30s "$GOSH_BIN" "$ULISP_DIR/compiler.scm" < "$diag_input" > "$diag_output" 2>&1 || diag_rc=$?
        else
            "$GOSH_BIN" "$ULISP_DIR/compiler.scm" < "$diag_input" > "$diag_output" 2>&1 || diag_rc=$?
        fi

        if [ -s "$diag_output" ]; then
            if grep -E -q "(\*\*\* ERROR|Stack Trace:|Compiler Pass:|\[[0-9]+\] \(pass-)" "$diag_output"; then
                grep -E -C 3 "(\*\*\* ERROR|Stack Trace:|Compiler Pass:|\[[0-9]+\] \(pass-)" "$diag_output" | head -n 50 >&2
            else
                tail -n 30 "$diag_output" >&2
            fi
        else
            echo "  (Fallback trace completed with no output, exit code: $diag_rc)" >&2
        fi
        echo -e "\033[1;36m----------------------------------------------------------------------\033[0m" >&2
        echo -e "\033[1m>>> Direct Reproduction Command (Gauche):\033[0m" >&2
        echo -e "    gosh $ULISP_DIR/compiler.scm < $input_file" >&2
    elif [ -x "$PYTHON_BIN" ]; then
        echo -e "\033[1;36m>>> Executing Secondary Diagnostic Fallback Trace via ILisp ($PYTHON_BIN)...\033[0m" >&2
        echo -e "\033[1;36m----------------------------------------------------------------------\033[0m" >&2
        local diag_rc=0
        if command -v timeout >/dev/null 2>&1; then
            timeout 30s env PYTHONPATH="$ROOT_DIR" "$PYTHON_BIN" -m ilisp "$ULISP_DIR/compiler.scm" < "$diag_input" > "$diag_output" 2>&1 || diag_rc=$?
        else
            env PYTHONPATH="$ROOT_DIR" "$PYTHON_BIN" -m ilisp "$ULISP_DIR/compiler.scm" < "$diag_input" > "$diag_output" 2>&1 || diag_rc=$?
        fi

        if [ -s "$diag_output" ]; then
            if grep -E -q "(Traceback|\*\*\* ERROR|Exception|Compiler Pass:|\[[0-9]+\] \(pass-)" "$diag_output"; then
                grep -E -C 3 "(Traceback|\*\*\* ERROR|Exception|Compiler Pass:|\[[0-9]+\] \(pass-)" "$diag_output" | head -n 50 >&2
            else
                tail -n 30 "$diag_output" >&2
            fi
        else
            echo "  (Fallback trace completed with no output, exit code: $diag_rc)" >&2
        fi
        echo -e "\033[1;36m----------------------------------------------------------------------\033[0m" >&2
        echo -e "\033[1m>>> Direct Reproduction Command (ILisp):\033[0m" >&2
        echo -e "    PYTHONPATH=$ROOT_DIR $PYTHON_BIN -m ilisp $ULISP_DIR/compiler.scm < $input_file" >&2
    fi

    rm -f "$diag_input" "$diag_output"
    echo -e "\033[1;35m======================================================================\033[0m" >&2
    echo >&2
}

check_asm_output() {
    local stage_name="$1"
    local asm_file="$2"
    local in_file="${3:-"$BUILD_DIR/ulisp_core.scm"}"
    if [ ! -s "$asm_file" ]; then
        echo -e "\033[1;31m[ERROR] $stage_name produced an empty assembly file: $asm_file\033[0m" >&2
        diagnose_stage_failure "$stage_name" "$asm_file" 0 "Empty assembly output produced" "$in_file"
        exit 1
    fi
    if grep -q "^\*\*\* ERROR:" "$asm_file"; then
        echo -e "\033[1;31m[ERROR] $stage_name failed with Scheme runtime exception:\033[0m" >&2
        cat "$asm_file" >&2
        diagnose_stage_failure "$stage_name" "$asm_file" 0 "Scheme runtime exception detected in output" "$in_file"
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
        diagnose_stage_failure "$stage_name" "$asm_file" "$rc" "Execution returned non-zero exit code ($rc)" "$BUILD_DIR/ulisp_core.scm"
        exit 1
    fi
    check_asm_output "$stage_name" "$asm_file" "$BUILD_DIR/ulisp_core.scm"
}

compile_asm() {
    local stage_name="$1"
    local asm_file="$2"
    local bin_file="$3"
    local in_file="${4:-"$BUILD_DIR/ulisp_core.scm"}"
    local gcc_err="$BUILD_DIR/gcc_err.log"
    local rc=0
    gcc -nostdlib -static "$asm_file" -o "$bin_file" > "$gcc_err" 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo -e "\033[1;31m[ERROR] $stage_name: gcc assembly/link failed with exit code $rc:\033[0m" >&2
        cat "$gcc_err" >&2
        diagnose_stage_failure "$stage_name (gcc)" "$asm_file" "$rc" "Assembler/Linker failed to compile generated .s file" "$in_file"
        rm -f "$gcc_err"
        exit 1
    fi
    rm -f "$gcc_err"
}

run_stage_try() {
    local stage_name="$1"
    local asm_file="$2"
    shift 2
    local rc=0
    "$@" < "$BUILD_DIR/ulisp_core.scm" > "$asm_file" 2>&1 || rc=$?
    if [ "$rc" -ne 0 ] || grep -q "^\*\*\* ERROR:" "$asm_file" || [ ! -s "$asm_file" ]; then
        return 1
    fi
    return 0
}

if [ "${BOOTSTRAP_FAST:-0}" = "1" ] && [ -x "$BUILD_DIR/scheme-stage1" ] && [ "$BUILD_DIR/scheme-stage1" -nt "$BUILD_DIR/ulisp_core.scm" ]; then
    echo "[1/3] Stage 1: Skipping compilation (BOOTSTRAP_FAST=1, reusing existing scheme-stage1)..."
elif [ "${FULL_BOOTSTRAP:-0}" != "1" ] && [ "${BOOTSTRAP_FROM_ILISP:-0}" != "1" ] && [ "${BOOTSTRAP_WITH_GOSH:-0}" != "1" ] && [ -x "$BOOT_BIN" ]; then
    echo "[1/3] Stage 1: Fast compiling ulisp_core.scm using native seed ($BOOT_BIN)..."
    if run_stage_try "Stage 1 ($BOOT_BIN)" "$BUILD_DIR/stage1.s" "$BOOT_BIN" "$BUILD_DIR/ulisp_core.scm" && gcc -nostdlib -static "$BUILD_DIR/stage1.s" -o "$BUILD_DIR/scheme-stage1" 2>/dev/null; then
        echo "  -> Stage 1 successfully compiled with native seed."
    elif [ -n "$GOSH_BIN" ]; then
        echo -e "\033[1;33m[WARN] Native seed ($BOOT_BIN) failed (e.g. exit code 139 / ABI drift). Automatically falling back to Gauche ($GOSH_BIN)...\033[0m"
        run_stage "Stage 1 (Gauche)" "$BUILD_DIR/stage1.s" "$GOSH_BIN" "$ULISP_DIR/compiler.scm"
        compile_asm "Stage 1 (Gauche)" "$BUILD_DIR/stage1.s" "$BUILD_DIR/scheme-stage1"
    else
        echo -e "\033[1;33m[WARN] Native seed ($BOOT_BIN) failed. Automatically falling back to ILisp ($PYTHON_BIN)...\033[0m"
        run_stage "Stage 1 (ILisp)" "$BUILD_DIR/stage1.s" env PYTHONPATH="$ROOT_DIR" "$PYTHON_BIN" -m ilisp "$ULISP_DIR/compiler.scm"
        compile_asm "Stage 1 (ILisp)" "$BUILD_DIR/stage1.s" "$BUILD_DIR/scheme-stage1"
    fi
elif [ "${BOOTSTRAP_WITH_GOSH:-0}" = "1" ] && [ -n "$GOSH_BIN" ]; then
    echo "[1/3] Stage 1: Fast compiling ulisp_core.scm using Gauche ($GOSH_BIN)..."
    run_stage "Stage 1 (Gauche)" "$BUILD_DIR/stage1.s" "$GOSH_BIN" "$ULISP_DIR/compiler.scm"
    compile_asm "Stage 1 (Gauche)" "$BUILD_DIR/stage1.s" "$BUILD_DIR/scheme-stage1"
else
    echo "[1/3] Stage 1: Compiling ulisp_core.scm with ILisp ($PYTHON_BIN)..."
    run_stage "Stage 1 (ILisp)" "$BUILD_DIR/stage1.s" env PYTHONPATH="$ROOT_DIR" "$PYTHON_BIN" -m ilisp "$ULISP_DIR/compiler.scm"
    compile_asm "Stage 1 (ILisp)" "$BUILD_DIR/stage1.s" "$BUILD_DIR/scheme-stage1"
fi

echo "[2/3] Stage 2: Compiling ulisp_core.scm with Stage 1 compiler..."
run_stage "Stage 2 (scheme-stage1)" "$BUILD_DIR/stage2.s" "$BUILD_DIR/scheme-stage1" "$BUILD_DIR/ulisp_core.scm"
compile_asm "Stage 2 (scheme-stage1)" "$BUILD_DIR/stage2.s" "$BUILD_DIR/scheme-stage2"

echo "[3/3] Stage 3: Compiling ulisp_core.scm with Stage 2 compiler..."
run_stage "Stage 3 (scheme-stage2)" "$BUILD_DIR/stage3.s" "$BUILD_DIR/scheme-stage2" "$BUILD_DIR/ulisp_core.scm"
compile_asm "Stage 3 (scheme-stage2)" "$BUILD_DIR/stage3.s" "$BUILD_DIR/scheme-stage3"

check_label_only_diff() {
    local file1="$1"
    local file2="$2"
    "$PYTHON_BIN" -c '
import re, sys
def norm(t):
    t = re.sub(r"\.L_([a-zA-Z0-9_]+)_[0-9]+", r".L_\1_#", t)
    t = re.sub(r"__safepoint_[0-9]+", r"__safepoint_#", t)
    return t
with open(sys.argv[1]) as f1, open(sys.argv[2]) as f2:
    if norm(f1.read()) == norm(f2.read()):
        sys.exit(0)
    sys.exit(1)
' "$file1" "$file2" 2>/dev/null
}

verify_and_promote() {
    local final_compiler="$1"
    local final_stage_name="$2"

    echo "=== Running Smoke Test on $final_stage_name Binary ==="
    rm -f "$BUILD_DIR/smoke_test.s" "$BUILD_DIR/smoke_test"
    echo "42" | ULISP_QUIET=1 "$final_compiler" > "$BUILD_DIR/smoke_test.s" 2>/dev/null
    if [ ! -s "$BUILD_DIR/smoke_test.s" ]; then
        echo "42" > "$BUILD_DIR/smoke_in.scm"
        ULISP_QUIET=1 "$final_compiler" "$BUILD_DIR/smoke_in.scm" > "$BUILD_DIR/smoke_test.s" 2>/dev/null
        rm -f "$BUILD_DIR/smoke_in.scm"
    fi
    gcc -nostdlib -static "$BUILD_DIR/smoke_test.s" -o "$BUILD_DIR/smoke_test"
    local smoke_out
    smoke_out="$("$BUILD_DIR/smoke_test" 2>/dev/null || true)"
    if [ "$smoke_out" = "42" ]; then
        echo -e "\033[1;32mPASS: $final_stage_name binary produced functional executable (output: 42).\033[0m"
    else
        echo -e "\033[1;31mFAIL: $final_stage_name smoke test returned unexpected output: '$smoke_out'\033[0m" >&2
        exit 1
    fi

    mkdir -p "$ULISP_DIR/bin"
    cp -f "$final_compiler" "$BOOT_BIN"
    chmod +x "$BOOT_BIN"
    echo "Updated local bootstrap seed cache ($BOOT_BIN) with verified $final_stage_name compiler."

    echo "=== Running Modular Separate Compilation & Incremental Verification (Issue #608) ==="
    make -C "$ULISP_DIR" test_incremental
    exit 0
}

echo "=== Verifying Fixed Point (diff stage2.s stage3.s) ==="
if cmp -s "$BUILD_DIR/stage2.s" "$BUILD_DIR/stage3.s"; then
    echo -e "\033[1;32mSUCCESS: Stage 2 and Stage 3 outputs are bit-for-bit IDENTICAL!\033[0m"
    echo "Fixed-point bootstrap verified successfully with Thin Debug Runtime & Scheme stdlib."
    verify_and_promote "$BUILD_DIR/scheme-stage3" "Stage 3"
elif check_label_only_diff "$BUILD_DIR/stage2.s" "$BUILD_DIR/stage3.s"; then
    echo -e "\033[1;33m[INFO] Stage 2 and Stage 3 differ ONLY in auto-incremented label counters (1-generation bootstrap lag).\033[0m"
    echo "[INFO] Running Stage 4 to verify convergence at Fixed Point..."

    echo "[4/4] Stage 4: Compiling ulisp_core.scm with Stage 3 compiler..."
    run_stage "Stage 4 (scheme-stage3)" "$BUILD_DIR/stage4.s" "$BUILD_DIR/scheme-stage3" "$BUILD_DIR/ulisp_core.scm"
    compile_asm "Stage 4 (scheme-stage3)" "$BUILD_DIR/stage4.s" "$BUILD_DIR/scheme-stage4"

    echo "=== Verifying Fixed Point (diff stage3.s stage4.s) ==="
    if cmp -s "$BUILD_DIR/stage3.s" "$BUILD_DIR/stage4.s"; then
        echo -e "\033[1;32mSUCCESS: Stage 3 and Stage 4 outputs are bit-for-bit IDENTICAL!\033[0m"
        echo "Fixed-point bootstrap verified successfully after 1-generation seed optimization convergence."
        verify_and_promote "$BUILD_DIR/scheme-stage4" "Stage 4"
    else
        echo -e "\033[1;31mFAILURE: Discrepancy detected between stage3.s and stage4.s\033[0m" >&2
        diff -u "$BUILD_DIR/stage3.s" "$BUILD_DIR/stage4.s" | head -n 50
        exit 1
    fi
else
    echo -e "\033[1;31mFAILURE: Semantic discrepancy detected between stage2.s and stage3.s\033[0m" >&2
    diff -u "$BUILD_DIR/stage2.s" "$BUILD_DIR/stage3.s" | head -n 50
    exit 1
fi

