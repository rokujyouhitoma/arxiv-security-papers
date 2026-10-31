#!/usr/bin/env bash
# ==============================================================================
# ULisp Minimal DWARF Debug Info Verification (GDB / readelf / nm)
# Conforms to DSN-33 Architecture Specification & Issue #619
# Verifies both Pass 140 (.loc/.file -> GNU as) and Pass 144 (Direct-to-ELF).
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ULISP_DIR/build/dwarf_debug"
COMPILER="${ULISP_COMPILER_BIN:-$ULISP_DIR/build/ulisp-modular}"

mkdir -p "$BUILD_DIR"

PASS=0
FAIL=0
check() {
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "  [PASS] $name"; PASS=$((PASS + 1))
    else
        echo "  [FAIL] $name"; FAIL=$((FAIL + 1))
    fi
}

if [ ! -x "$COMPILER" ]; then
    echo "Compiler $COMPILER not found, building..."
    make -C "$ULISP_DIR" build/ulisp-modular
fi

SRC="$BUILD_DIR/debug_sample.scm"
cat > "$SRC" <<'EOF'
(define (add2 x)
  (+ x 2))

(define (main-fn)
  (let ((val (add2 40)))
    val))

(main-fn)
EOF

echo "=== Issue #619: DWARF debug info tests ==="

# --- 1. Pass 140: -g -S -> as -> ld --------------------------------------
echo "--- 1. Pass 140 (GNU as .loc/.file) ---"
cd "$BUILD_DIR"
"$COMPILER" -g -S < "$SRC" > dbg.s
check "1.1 .file directive emitted" grep -q '\.file 1 "' dbg.s
check "1.2 .loc directive emitted"  grep -q '\.loc 1 ' dbg.s
as --64 dbg.s -o dbg.o
ld -m elf_x86_64 -static dbg.o -o dbg_as
check "1.3 .debug_line present (as/ld)" bash -c "readelf -S dbg_as | grep -q '\.debug_line'"
check "1.4 .debug_info present (as/ld)" bash -c "readelf -S dbg_as | grep -q '\.debug_info'"
if command -v gdb >/dev/null 2>&1; then
    check "1.5 gdb breakpoint at add2 line 1 (as/ld)" \
        bash -c "gdb --batch -ex 'b stdin.scm:1' -ex 'info break' ./dbg_as 2>&1 | grep -q 'stdin.scm, line 1'"
    check "1.6 gdb breakpoint at main line 8 (as/ld)" \
        bash -c "gdb --batch -ex 'b stdin.scm:8' -ex 'info break' ./dbg_as 2>&1 | grep -q 'stdin.scm, line 8'"
fi

# --- 2. Zero overhead without -g -----------------------------------------
echo "--- 2. Zero overhead without -g ---"
"$COMPILER" -S < "$SRC" > nodbg.s
check "2.1 no .loc without -g"  bash -c "! grep -q '\.loc ' nodbg.s"
check "2.2 no .file without -g" bash -c "! grep -q '\.file ' nodbg.s"
"$COMPILER" --target-elf < "$SRC" > nodbg.elf
chmod +x nodbg.elf
check "2.3 no .debug_* sections without -g (direct ELF)" \
    bash -c "! readelf -S nodbg.elf | grep -q '\.debug_'"

# --- 3. Pass 144: Direct-to-ELF -----------------------------------------
echo "--- 3. Pass 144 (Direct-to-ELF) ---"
"$COMPILER" -g --target-elf < "$SRC" > dbg.elf
chmod +x dbg.elf
for sec in .debug_line .debug_info .debug_abbrev .debug_str .symtab .strtab; do
    check "3.x $sec present (direct ELF)" bash -c "readelf -S dbg.elf | grep -q '$sec'"
done
check "3.7 readelf decodedline lists stdin.scm" \
    bash -c "readelf --debug-dump=decodedline dbg.elf | grep -q 'stdin.scm'"
check "3.8 _start symbol resolved" bash -c "readelf -s dbg.elf | grep -q '_start'"
if command -v gdb >/dev/null 2>&1; then
    check "3.9 gdb breakpoint at add2 line 1 (direct ELF)" \
        bash -c "gdb --batch -ex 'b stdin.scm:1' -ex 'info break' ./dbg.elf 2>&1 | grep -q 'stdin.scm, line 1'"
    check "3.10 gdb breakpoint at main line 8 (direct ELF)" \
        bash -c "gdb --batch -ex 'b stdin.scm:8' -ex 'info break' ./dbg.elf 2>&1 | grep -q 'stdin.scm, line 8'"
fi
check "3.11 debug ELF still executes" bash -c "ULISP_PRINT_RESULT=1 ./dbg.elf | grep -q 42"

echo "========================================================================"
echo " DWARF Debug Tests Summary: Passed: $PASS, Failed: $FAIL"
echo "========================================================================"
[ "$FAIL" -eq 0 ]

