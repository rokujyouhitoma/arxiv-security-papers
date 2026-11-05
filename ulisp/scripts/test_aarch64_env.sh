#!/usr/bin/env bash
# ==============================================================================
# test_aarch64_env.sh - Verification script for AArch64 Cross-Toolchain & QEMU
# ==============================================================================
set -euo pipefail

CROSS_AS_AARCH64="${CROSS_AS_AARCH64:-aarch64-linux-gnu-as}"
CROSS_LD_AARCH64="${CROSS_LD_AARCH64:-aarch64-linux-gnu-ld}"
CROSS_CC_AARCH64="${CROSS_CC_AARCH64:-aarch64-linux-gnu-gcc}"
QEMU_AARCH64="${QEMU_AARCH64:-$(command -v qemu-aarch64 2>/dev/null || command -v qemu-aarch64-static 2>/dev/null || true)}"

echo "=== Verifying AArch64 Cross-Toolchain & QEMU User Emulation ==="
echo "AS:   ${CROSS_AS_AARCH64}"
echo "LD:   ${CROSS_LD_AARCH64}"
echo "CC:   ${CROSS_CC_AARCH64}"
echo "QEMU: ${QEMU_AARCH64}"

# Verify tool availability
if ! command -v "${CROSS_AS_AARCH64}" >/dev/null 2>&1; then
    echo "ERROR: AArch64 assembler '${CROSS_AS_AARCH64}' not found in PATH." >&2
    exit 1
fi
if ! command -v "${CROSS_LD_AARCH64}" >/dev/null 2>&1; then
    echo "ERROR: AArch64 linker '${CROSS_LD_AARCH64}' not found in PATH." >&2
    exit 1
fi
if [ -z "${QEMU_AARCH64}" ] || ! command -v "${QEMU_AARCH64}" >/dev/null 2>&1; then
    echo "ERROR: QEMU AArch64 emulator ('qemu-aarch64' or 'qemu-aarch64-static') not found in PATH." >&2
    exit 1
fi

TMP_DIR=$(mktemp -d /tmp/test_aarch64_env.XXXXXX)
cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo "--> [1/2] Testing minimal exit(42) binary..."
cat << 'EOF' > "${TMP_DIR}/test_exit42.s"
.global _start
.text
_start:
    mov x0, #42
    mov x8, #93
    svc #0
EOF

"${CROSS_AS_AARCH64}" "${TMP_DIR}/test_exit42.s" -o "${TMP_DIR}/test_exit42.o"
"${CROSS_LD_AARCH64}" -static "${TMP_DIR}/test_exit42.o" -o "${TMP_DIR}/test_exit42"

set +e
"${QEMU_AARCH64}" "${TMP_DIR}/test_exit42"
EXIT_CODE=$?
set -euo pipefail

if [ "${EXIT_CODE}" -ne 42 ]; then
    echo "FAIL: Expected exit code 42, got ${EXIT_CODE}" >&2
    exit 1
fi
echo "    Exit code 42 verified."

echo "--> [2/2] Testing write(1, msg, 16) and exit(0)..."
cat << 'EOF' > "${TMP_DIR}/test_write.s"
.global _start
.text
_start:
    mov x0, #1
    ldr x1, =msg
    mov x2, #16
    mov x8, #64
    svc #0

    mov x0, #0
    mov x8, #93
    svc #0

.data
msg:
    .ascii "AArch64 QEMU OK\n"
EOF

"${CROSS_AS_AARCH64}" "${TMP_DIR}/test_write.s" -o "${TMP_DIR}/test_write.o"
"${CROSS_LD_AARCH64}" -static "${TMP_DIR}/test_write.o" -o "${TMP_DIR}/test_write"

OUTPUT=$("${QEMU_AARCH64}" "${TMP_DIR}/test_write")
if [ "${OUTPUT}" != "AArch64 QEMU OK" ]; then
    echo "FAIL: Expected output 'AArch64 QEMU OK', got '${OUTPUT}'" >&2
    exit 1
fi
echo "    Stdout write and exit(0) verified: '${OUTPUT}'"

echo "=== [AArch64 Toolchain & QEMU Verification: PASS] ==="
exit 0

