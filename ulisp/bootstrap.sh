#!/bin/bash
set -euo pipefail

echo "=== ULisp Self-Hosting Bootstrap Verification ==="

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ULISP_DIR="$ROOT_DIR/ulisp"
BUILD_DIR="$ULISP_DIR/build"

# Configuration Flags (Issue #776 & Issue #777)
BOOTSTRAP_QUICK="${BOOTSTRAP_QUICK:-0}"
BOOTSTRAP_RUN_TESTS="${BOOTSTRAP_RUN_TESTS:-0}"
BOOTSTRAP_FAST="${BOOTSTRAP_FAST:-0}"
FULL_BOOTSTRAP="${FULL_BOOTSTRAP:-0}"
BOOTSTRAP_FROM_ILISP="${BOOTSTRAP_FROM_ILISP:-0}"
BOOTSTRAP_WITH_GOSH="${BOOTSTRAP_WITH_GOSH:-0}"
BOOTSTRAP_SPLIT_LINK="${BOOTSTRAP_SPLIT_LINK:-1}"

while [ $# -gt 0 ]; do
    case "$1" in
        --quick|-q|--stage1-only)
            BOOTSTRAP_QUICK=1
            shift
            ;;
        --full)
            FULL_BOOTSTRAP=1
            BOOTSTRAP_QUICK=0
            shift
            ;;
        --split-link)
            BOOTSTRAP_SPLIT_LINK=1
            shift
            ;;
        --monolithic)
            BOOTSTRAP_SPLIT_LINK=0
            shift
            ;;
        --test)
            BOOTSTRAP_RUN_TESTS=1
            shift
            ;;
        --no-test)
            BOOTSTRAP_RUN_TESTS=0
            shift
            ;;
        --fast)
            BOOTSTRAP_FAST=1
            shift
            ;;
        --with-gosh)
            BOOTSTRAP_WITH_GOSH=1
            shift
            ;;
        --from-ilisp)
            BOOTSTRAP_FROM_ILISP=1
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --quick, -q, --stage1-only  Stop after Stage 1 smoke test (fast dev cycle)"
            echo "  --full                      Run full 3-stage bootstrap fixed-point verification"
            echo "  --split-link                Bootstrap compiler_entry.scm linked with ulisp_stdlib.o (default)"
            echo "  --monolithic                Bootstrap monolithic ulisp_core.scm (stdlib + runtime + compiler)"
            echo "  --test                      Run post-bootstrap test suite (test_incremental)"
            echo "  --no-test                   Skip post-bootstrap test suite (default)"
            echo "  --fast                      Reuse existing scheme-stage1 if newer than sources"
            echo "  --with-gosh                 Force using Gauche for Stage 1 compilation"
            echo "  --from-ilisp                Force using Python ILisp for Stage 1 compilation"
            echo "  --help, -h                  Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage information." >&2
            exit 1
            ;;
    esac
done

mkdir -p "$BUILD_DIR"

# Apply compiler profile for self-hosting compiler execution (Issue #567)
export ULISP_GC_PROFILE=compiler

if [ "${BOOTSTRAP_SPLIT_LINK:-1}" = "1" ]; then
    echo "[0/4] Preparing split-linked bootstrap (compiler_entry.scm + build/ulisp_stdlib.o)..."
    make -C "$ULISP_DIR" compiler build/ulisp_stdlib.o
    echo "(!gc none) (!allow-extern #t)" > "$BUILD_DIR/compiler_input.scm"
    cat "$ULISP_DIR/compiler_entry.scm" >> "$BUILD_DIR/compiler_input.scm"
    BOOTSTRAP_INPUT="$BUILD_DIR/compiler_input.scm"
    BOOTSTRAP_TARGET_NAME="compiler_entry.scm"
    STAGE1_ASM="$BUILD_DIR/stage1_compiler.s"
    STAGE2_ASM="$BUILD_DIR/stage2_compiler.s"
    STAGE3_ASM="$BUILD_DIR/stage3_compiler.s"
    STAGE4_ASM="$BUILD_DIR/stage4_compiler.s"
else
    echo "[0/4] Preparing unified monolithic compiler (entry_core.scm)..."
    make -C "$ULISP_DIR" compiler
    if [ ! -f "$BUILD_DIR/ulisp_core.scm" ] || ! cmp -s "$ULISP_DIR/entry_core.scm" "$BUILD_DIR/ulisp_core.scm"; then
        cp "$ULISP_DIR/entry_core.scm" "$BUILD_DIR/ulisp_core.scm"
    fi
    BOOTSTRAP_INPUT="$BUILD_DIR/ulisp_core.scm"
    BOOTSTRAP_TARGET_NAME="ulisp_core.scm"
    STAGE1_ASM="$BUILD_DIR/stage1.s"
    STAGE2_ASM="$BUILD_DIR/stage2.s"
    STAGE3_ASM="$BUILD_DIR/stage3.s"
    STAGE4_ASM="$BUILD_DIR/stage4.s"
fi

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
    local in_file="${3:-"$BOOTSTRAP_INPUT"}"
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
    "$@" < "$BOOTSTRAP_INPUT" > "$asm_file" 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo -e "\033[1;31m[ERROR] $stage_name execution failed with exit code $rc:\033[0m" >&2
        if [ -s "$asm_file" ]; then
            cat "$asm_file" >&2
        fi
        diagnose_stage_failure "$stage_name" "$asm_file" "$rc" "Execution returned non-zero exit code ($rc)" "$BOOTSTRAP_INPUT"
        exit 1
    fi
    check_asm_output "$stage_name" "$asm_file" "$BOOTSTRAP_INPUT"
}

compile_asm() {
    local stage_name="$1"
    local asm_file="$2"
    local bin_file="$3"
    local in_file="${4:-"$BOOTSTRAP_INPUT"}"
    local obj_file="${asm_file%.s}.o"
    local tool_err="$BUILD_DIR/as_ld_err.log"
    local rc=0
    as --64 "$asm_file" -o "$obj_file" > "$tool_err" 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo -e "\033[1;31m[ERROR] $stage_name: as (assembler) failed with exit code $rc:\033[0m" >&2
        cat "$tool_err" >&2
        diagnose_stage_failure "$stage_name (as)" "$asm_file" "$rc" "Assembler failed to compile generated .s file" "$in_file"
        rm -f "$tool_err"
        exit 1
    fi
    if [ "${BOOTSTRAP_SPLIT_LINK:-1}" = "1" ]; then
        ld -m elf_x86_64 -static "$BUILD_DIR/ulisp_stdlib.o" "$obj_file" -o "$bin_file" > "$tool_err" 2>&1 || rc=$?
    else
        ld -m elf_x86_64 -static "$obj_file" -o "$bin_file" > "$tool_err" 2>&1 || rc=$?
    fi
    if [ "$rc" -ne 0 ]; then
        echo -e "\033[1;31m[ERROR] $stage_name: ld (linker) failed with exit code $rc:\033[0m" >&2
        cat "$tool_err" >&2
        diagnose_stage_failure "$stage_name (ld)" "$asm_file" "$rc" "Linker failed to link generated .o file" "$in_file"
        rm -f "$tool_err"
        exit 1
    fi
    rm -f "$tool_err"
}

run_stage_try() {
    local stage_name="$1"
    local asm_file="$2"
    shift 2
    local rc=0
    local stage_timeout="${BOOTSTRAP_STAGE_TIMEOUT:-600s}"
    timeout "$stage_timeout" "$@" < "$BOOTSTRAP_INPUT" > "$asm_file" 2>&1 || rc=$?
    if [ "$rc" -eq 124 ]; then
        echo -e "\033[1;33m[WARN] $stage_name timed out after $stage_timeout.\033[0m" >&2
        return 1
    elif [ "$rc" -ne 0 ] || grep -q "^\*\*\* ERROR:" "$asm_file" || [ ! -s "$asm_file" ]; then
        return 1
    fi
    return 0
}

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
    local should_promote="${3:-1}"

    echo "=== Running Smoke Test on $final_stage_name Binary ==="
    rm -f "$BUILD_DIR/smoke_test.s" "$BUILD_DIR/smoke_test"
    echo "42" | "$final_compiler" > "$BUILD_DIR/smoke_test.s" 2>/dev/null
    if [ ! -s "$BUILD_DIR/smoke_test.s" ]; then
        echo "42" > "$BUILD_DIR/smoke_in.scm"
        "$final_compiler" "$BUILD_DIR/smoke_in.scm" > "$BUILD_DIR/smoke_test.s" 2>/dev/null
        rm -f "$BUILD_DIR/smoke_in.scm"
    fi
    as --64 "$BUILD_DIR/smoke_test.s" -o "$BUILD_DIR/smoke_test.o"
    ld -m elf_x86_64 -static "$BUILD_DIR/smoke_test.o" -o "$BUILD_DIR/smoke_test"
    local smoke_out
    smoke_out="$(ULISP_PRINT_RESULT=1 "$BUILD_DIR/smoke_test" 2>/dev/null || true)"
    if [ "$smoke_out" = "42" ]; then
        echo -e "\033[1;32mPASS: $final_stage_name binary produced functional executable (output: 42).\033[0m"
    else
        echo -e "\033[1;31mFAIL: $final_stage_name smoke test returned unexpected output: '$smoke_out'\033[0m" >&2
        exit 1
    fi

    if [ "${BOOTSTRAP_SPLIT_LINK:-1}" = "1" ]; then
        cp -f "$final_compiler" "$BUILD_DIR/ulisp-fast"
        chmod +x "$BUILD_DIR/ulisp-fast"
    fi

    if [ "$should_promote" = "1" ]; then
        mkdir -p "$ULISP_DIR/bin"
        cp -f "$final_compiler" "$BOOT_BIN"
        chmod +x "$BOOT_BIN"
        echo "Updated local bootstrap seed cache ($BOOT_BIN) with verified $final_stage_name compiler."
    else
        echo "Quick mode: Built $final_stage_name successfully ($final_compiler). Preserving stable bootstrap seed ($BOOT_BIN)."
    fi

    if [ "${BOOTSTRAP_RUN_TESTS:-0}" = "1" ]; then
        echo "=== Running Modular Separate Compilation & Incremental Verification (Issue #608) ==="
        make -C "$ULISP_DIR" test_incremental
    else
        echo "Skipping post-bootstrap incremental test (enable with --test or BOOTSTRAP_RUN_TESTS=1)."
    fi
    exit 0
}

if [ "${BOOTSTRAP_FAST:-0}" = "1" ] && [ -x "$BUILD_DIR/scheme-stage1" ] && [ "$BUILD_DIR/scheme-stage1" -nt "$BOOTSTRAP_INPUT" ]; then
    echo "[1/3] Stage 1: Skipping compilation (BOOTSTRAP_FAST=1, reusing existing scheme-stage1)..."
elif [ "${FULL_BOOTSTRAP:-0}" != "1" ] && [ "${BOOTSTRAP_FROM_ILISP:-0}" != "1" ] && [ "${BOOTSTRAP_WITH_GOSH:-0}" != "1" ] && [ -x "$BOOT_BIN" ]; then
    echo "[1/3] Stage 1: Fast compiling $BOOTSTRAP_TARGET_NAME using native seed ($BOOT_BIN)..."
    if run_stage_try "Stage 1 ($BOOT_BIN)" "$STAGE1_ASM" "$BOOT_BIN" "$BOOTSTRAP_INPUT" && compile_asm "Stage 1 ($BOOT_BIN)" "$STAGE1_ASM" "$BUILD_DIR/scheme-stage1" "$BOOTSTRAP_INPUT"; then
        echo "  -> Stage 1 successfully compiled with native seed."
    elif [ -n "$GOSH_BIN" ]; then
        echo -e "\033[1;33m[WARN] Native seed ($BOOT_BIN) failed (e.g. exit code 139 / timeout / ABI drift). Automatically falling back to Gauche ($GOSH_BIN)...\033[0m"
        run_stage "Stage 1 (Gauche)" "$STAGE1_ASM" "$GOSH_BIN" "$ULISP_DIR/compiler.scm"
        compile_asm "Stage 1 (Gauche)" "$STAGE1_ASM" "$BUILD_DIR/scheme-stage1" "$BOOTSTRAP_INPUT"
    else
        echo -e "\033[1;33m[WARN] Native seed ($BOOT_BIN) failed. Automatically falling back to ILisp ($PYTHON_BIN)...\033[0m"
        run_stage "Stage 1 (ILisp)" "$STAGE1_ASM" env PYTHONPATH="$ROOT_DIR" "$PYTHON_BIN" -m ilisp "$ULISP_DIR/compiler.scm"
        compile_asm "Stage 1 (ILisp)" "$STAGE1_ASM" "$BUILD_DIR/scheme-stage1" "$BOOTSTRAP_INPUT"
    fi
elif [ "${BOOTSTRAP_WITH_GOSH:-0}" = "1" ] && [ -n "$GOSH_BIN" ]; then
    echo "[1/3] Stage 1: Fast compiling $BOOTSTRAP_TARGET_NAME using Gauche ($GOSH_BIN)..."
    run_stage "Stage 1 (Gauche)" "$STAGE1_ASM" "$GOSH_BIN" "$ULISP_DIR/compiler.scm"
    compile_asm "Stage 1 (Gauche)" "$STAGE1_ASM" "$BUILD_DIR/scheme-stage1" "$BOOTSTRAP_INPUT"
else
    echo "[1/3] Stage 1: Compiling $BOOTSTRAP_TARGET_NAME with ILisp ($PYTHON_BIN)..."
    run_stage "Stage 1 (ILisp)" "$STAGE1_ASM" env PYTHONPATH="$ROOT_DIR" "$PYTHON_BIN" -m ilisp "$ULISP_DIR/compiler.scm"
    compile_asm "Stage 1 (ILisp)" "$STAGE1_ASM" "$BUILD_DIR/scheme-stage1" "$BOOTSTRAP_INPUT"
fi
[ "$STAGE1_ASM" != "$BUILD_DIR/stage1.s" ] && cp -f "$STAGE1_ASM" "$BUILD_DIR/stage1.s"

# Quick Bootstrap early exit (Issue #776)
if [ "${BOOTSTRAP_QUICK:-0}" = "1" ]; then
    echo -e "\033[1;36m=== [QUICK BOOTSTRAP] Stage 1 built successfully. Skipping Stage 2 & 3 (Issue #776) ===\033[0m"
    verify_and_promote "$BUILD_DIR/scheme-stage1" "Stage 1" 0
    exit 0
fi

echo "[2/3] Stage 2: Compiling $BOOTSTRAP_TARGET_NAME with Stage 1 compiler..."
run_stage "Stage 2 (scheme-stage1)" "$STAGE2_ASM" "$BUILD_DIR/scheme-stage1" "$BOOTSTRAP_INPUT"
compile_asm "Stage 2 (scheme-stage1)" "$STAGE2_ASM" "$BUILD_DIR/scheme-stage2" "$BOOTSTRAP_INPUT"
[ "$STAGE2_ASM" != "$BUILD_DIR/stage2.s" ] && cp -f "$STAGE2_ASM" "$BUILD_DIR/stage2.s"

echo "[3/3] Stage 3: Compiling $BOOTSTRAP_TARGET_NAME with Stage 2 compiler..."
run_stage "Stage 3 (scheme-stage2)" "$STAGE3_ASM" "$BUILD_DIR/scheme-stage2" "$BOOTSTRAP_INPUT"
compile_asm "Stage 3 (scheme-stage2)" "$STAGE3_ASM" "$BUILD_DIR/scheme-stage3" "$BOOTSTRAP_INPUT"
[ "$STAGE3_ASM" != "$BUILD_DIR/stage3.s" ] && cp -f "$STAGE3_ASM" "$BUILD_DIR/stage3.s"

STAGE2_BASE="$(basename "$STAGE2_ASM")"
STAGE3_BASE="$(basename "$STAGE3_ASM")"
echo "=== Verifying Fixed Point (diff $STAGE2_BASE $STAGE3_BASE) ==="
if cmp -s "$STAGE2_ASM" "$STAGE3_ASM"; then
    echo -e "\033[1;32mSUCCESS: Stage 2 and Stage 3 outputs are bit-for-bit IDENTICAL!\033[0m"
    echo "Fixed-point bootstrap verified successfully with Thin Debug Runtime & Scheme stdlib."
    verify_and_promote "$BUILD_DIR/scheme-stage3" "Stage 3"
elif check_label_only_diff "$STAGE2_ASM" "$STAGE3_ASM"; then
    echo -e "\033[1;33m[INFO] Stage 2 and Stage 3 differ ONLY in auto-incremented label counters (1-generation bootstrap lag).\033[0m"
    echo "[INFO] Running Stage 4 to verify convergence at Fixed Point..."

    echo "[4/4] Stage 4: Compiling $BOOTSTRAP_TARGET_NAME with Stage 3 compiler..."
    run_stage "Stage 4 (scheme-stage3)" "$STAGE4_ASM" "$BUILD_DIR/scheme-stage3" "$BOOTSTRAP_INPUT"
    compile_asm "Stage 4 (scheme-stage3)" "$STAGE4_ASM" "$BUILD_DIR/scheme-stage4" "$BOOTSTRAP_INPUT"
    [ "$STAGE4_ASM" != "$BUILD_DIR/stage4.s" ] && cp -f "$STAGE4_ASM" "$BUILD_DIR/stage4.s"

    STAGE4_BASE="$(basename "$STAGE4_ASM")"
    echo "=== Verifying Fixed Point (diff $STAGE3_BASE $STAGE4_BASE) ==="
    if cmp -s "$STAGE3_ASM" "$STAGE4_ASM"; then
        echo -e "\033[1;32mSUCCESS: Stage 3 and Stage 4 outputs are bit-for-bit IDENTICAL!\033[0m"
        echo "Fixed-point bootstrap verified successfully after 1-generation seed optimization convergence."
        verify_and_promote "$BUILD_DIR/scheme-stage4" "Stage 4"
    else
        echo -e "\033[1;31mFAILURE: Discrepancy detected between $STAGE3_BASE and $STAGE4_BASE\033[0m" >&2
        diff -u "$STAGE3_ASM" "$STAGE4_ASM" | head -n 50
        exit 1
    fi
else
    echo -e "\033[1;31mFAILURE: Semantic discrepancy detected between $STAGE2_BASE and $STAGE3_BASE\033[0m" >&2
    diff -u "$STAGE2_ASM" "$STAGE3_ASM" | head -n 50
    exit 1
fi

