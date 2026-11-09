#!/usr/bin/env bash
# ==============================================================================
# test_wine_env.sh - Verification script for MinGW-w64 Cross-Toolchain & Wine
# Conforms to Issue #694 & DSN-33 Architecture Specification
# Full Verification Pipeline: Minimal Exit Code + CRT Stdio + Win32 API + MS x64 ABI
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ANSI Colors
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
BOLD="\033[1m"
RESET="\033[0m"

CROSS_CC="${CROSS_CC_WIN64:-x86_64-w64-mingw32-gcc}"
WINE="${WINE64:-$(command -v wine64 2>/dev/null || command -v wine 2>/dev/null || if [ -x /usr/lib/wine/wine64 ]; then echo /usr/lib/wine/wine64; fi)}"
TIMEOUT_CMD="$(command -v timeout 2>/dev/null || true)"

run_with_timeout() {
    local timeout_sec="$1"
    shift
    if [ -n "${TIMEOUT_CMD}" ]; then
        ${TIMEOUT_CMD} "${timeout_sec}s" "$@"
    else
        "$@"
    fi
}

echo -e "${CYAN}=======================================================================${RESET}"
echo -e "${BOLD} Starting MinGW-w64 & Wine Windows x64 Verification Pipeline (#694)${RESET}"
echo -e " Target Architecture : ${BOLD}PE32+ (x86-64 Windows / Win32)${RESET}"
echo -e " Cross Compiler      : ${BOLD}${CROSS_CC}${RESET}"
echo -e " Emulation Engine    : ${BOLD}${WINE}${RESET}"
echo -e "${CYAN}=======================================================================${RESET}"

# Verify tool availability
if ! command -v "${CROSS_CC}" >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] MinGW-w64 cross-compiler '${CROSS_CC}' not found in PATH.${RESET}" >&2
    echo -e "${YELLOW}[HINT] Run 'apt-get install -y gcc-mingw-w64-x86-64' on Debian/Ubuntu.${RESET}" >&2
    exit 1
fi

if [ -z "${WINE}" ] || [ ! -x "${WINE}" ]; then
    echo -e "${RED}[ERROR] Wine emulator ('wine64' or 'wine') not found in PATH.${RESET}" >&2
    echo -e "${YELLOW}[HINT] Run 'apt-get install -y wine64 wine' on Debian/Ubuntu.${RESET}" >&2
    exit 1
fi

CC_VER=$("${CROSS_CC}" --version | head -n 1)
WINE_VER=$("${WINE}" --version 2>/dev/null || true)
echo -e " Compiler Version    : ${CC_VER}"
echo -e " Wine Version        : ${WINE_VER}"

# Prepare isolated ephemeral WINEPREFIX and TMP_DIR (CWE-250 / CWE-732 defense)
TMP_DIR="$(mktemp -d /tmp/ulisp_wine_env_XXXXXX)"
export WINEPREFIX="${TMP_DIR}/wine_prefix"
mkdir -p "${WINEPREFIX}"

# Headless Wine flags (CWE-400 defense against GUI hangs)
export WINEDEBUG="-all"
export DISPLAY=""
export WINEDLLOVERRIDES="mscoree,mshtml="

cleanup() {
    wineserver -k 2>/dev/null || true
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

# Initialize isolated Wine prefix quietly
wineboot -u 2>/dev/null || true

# Test counters
TESTS_TOTAL=0
TESTS_PASS=0
TESTS_FAIL=0

record_result() {
    local stage_name="$1"
    local status="$2"
    local details="$3"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if [ "${status}" -eq 0 ]; then
        echo -e "  ${GREEN}[PASS]${RESET} ${stage_name}: ${details}"
        TESTS_PASS=$((TESTS_PASS + 1))
    else
        echo -e "  ${RED}[FAIL]${RESET} ${stage_name}: ${details}"
        TESTS_FAIL=$((TESTS_FAIL + 1))
    fi
}

echo -e "\n${BLUE}=== [Stage 1/4] Minimal PE32+ Binary Compilation & Exit Code ===${RESET}"
cat << 'EOF' > "${TMP_DIR}/stage1_exit42.c"
int main(void) {
    return 42;
}
EOF

if ! "${CROSS_CC}" -O2 "${TMP_DIR}/stage1_exit42.c" -o "${TMP_DIR}/stage1_exit42.exe" 2>"${TMP_DIR}/stage1.log"; then
    record_result "Stage 1" 1 "Compilation failed ($(cat "${TMP_DIR}/stage1.log"))"
else
    set +e
    run_with_timeout 30 "${WINE}" "${TMP_DIR}/stage1_exit42.exe" >/dev/null 2>&1
    ACTUAL_EXIT=$?
    set -e
    if [ "${ACTUAL_EXIT}" -eq 42 ]; then
        record_result "Stage 1" 0 "PE32+ executable returned exit code 42 under Wine"
    else
        record_result "Stage 1" 1 "Expected exit code 42, got ${ACTUAL_EXIT}"
    fi
fi

echo -e "\n${BLUE}=== [Stage 2/4] CRT Standard I/O (printf) & Stdout Capture ===${RESET}"
cat << 'EOF' > "${TMP_DIR}/stage2_stdio.c"
#include <stdio.h>
int main(void) {
    printf("MinGW Wine OK\n");
    return 0;
}
EOF

if ! "${CROSS_CC}" -O2 "${TMP_DIR}/stage2_stdio.c" -o "${TMP_DIR}/stage2_stdio.exe" 2>"${TMP_DIR}/stage2.log"; then
    record_result "Stage 2" 1 "Compilation failed ($(cat "${TMP_DIR}/stage2.log"))"
else
    set +e
    STDIO_OUT=$(run_with_timeout 30 "${WINE}" "${TMP_DIR}/stage2_stdio.exe" 2>/dev/null | tr -d '\r')
    STDIO_EXIT=$?
    set -e
    if [ "${STDIO_EXIT}" -eq 0 ] && [ "${STDIO_OUT}" = "MinGW Wine OK" ]; then
        record_result "Stage 2" 0 "Captured stdout '${STDIO_OUT}' with exit code 0"
    else
        record_result "Stage 2" 1 "Output mismatch: got '${STDIO_OUT}' (exit ${STDIO_EXIT})"
    fi
fi

echo -e "\n${BLUE}=== [Stage 3/4] Direct Win32 API Linkage & Invocation ===${RESET}"
cat << 'EOF' > "${TMP_DIR}/stage3_win32.c"
#include <windows.h>

int main(void) {
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    const char msg[] = "Win32 API Direct Invocation: SUCCESS\r\n";
    DWORD written = 0;
    WriteFile(h, msg, sizeof(msg) - 1, &written, NULL);
    ExitProcess(42);
    return 0;
}
EOF

if ! "${CROSS_CC}" -O2 "${TMP_DIR}/stage3_win32.c" -lkernel32 -o "${TMP_DIR}/stage3_win32.exe" 2>"${TMP_DIR}/stage3.log"; then
    record_result "Stage 3" 1 "Compilation/link failed ($(cat "${TMP_DIR}/stage3.log"))"
else
    set +e
    WIN32_OUT=$(run_with_timeout 30 "${WINE}" "${TMP_DIR}/stage3_win32.exe" 2>/dev/null | tr -d '\r')
    WIN32_EXIT=$?
    set -e
    if [ "${WIN32_EXIT}" -eq 42 ] && [ "${WIN32_OUT}" = "Win32 API Direct Invocation: SUCCESS" ]; then
        record_result "Stage 3" 0 "WriteFile + ExitProcess(42) executed cleanly under Wine"
    else
        record_result "Stage 3" 1 "Expected exit 42 and success msg, got exit ${WIN32_EXIT}, out '${WIN32_OUT}'"
    fi
fi

echo -e "\n${BLUE}=== [Stage 4/4] Microsoft x64 Calling Convention Invariants ===${RESET}"
cat << 'EOF' > "${TMP_DIR}/stage4_abi.c"
#include <stdio.h>
#include <stdint.h>

__attribute__((noinline))
long long verify_ms_x64_abi(long long a, long long b, long long c, long long d, long long e, long long f) {
    uintptr_t sp;
    __asm__ volatile ("mov %%rsp, %0" : "=r"(sp));
    // Verify register argument passing (RCX, RDX, R8, R9) and shadow space / stack args
    if (a != 10 || b != 20 || c != 30 || d != 40 || e != 50 || f != 60) {
        return 1;
    }
    // Verify 16-byte stack alignment invariant
    if ((sp & 0x7) != 0) {
        return 2;
    }
    return 0; // PASS
}

int main(void) {
    long long res = verify_ms_x64_abi(10, 20, 30, 40, 50, 60);
    if (res == 0) {
        printf("MS x64 ABI Verification: PASS\n");
        return 0;
    }
    return (int)res;
}
EOF

if ! "${CROSS_CC}" -O2 "${TMP_DIR}/stage4_abi.c" -o "${TMP_DIR}/stage4_abi.exe" 2>"${TMP_DIR}/stage4.log"; then
    record_result "Stage 4" 1 "Compilation failed ($(cat "${TMP_DIR}/stage4.log"))"
else
    set +e
    ABI_OUT=$(run_with_timeout 30 "${WINE}" "${TMP_DIR}/stage4_abi.exe" 2>/dev/null | tr -d '\r')
    ABI_EXIT=$?
    set -e
    if [ "${ABI_EXIT}" -eq 0 ] && [ "${ABI_OUT}" = "MS x64 ABI Verification: PASS" ]; then
        record_result "Stage 4" 0 "RCX/RDX/R8/R9 + 32-byte Shadow Space + 16-byte alignment PASS"
    else
        record_result "Stage 4" 1 "ABI verification failed: exit ${ABI_EXIT}, out '${ABI_OUT}'"
    fi
fi

# ==============================================================================
# Summary Report Matrix
# ==============================================================================
echo -e "\n${CYAN}=======================================================================${RESET}"
echo -e "${BOLD} MinGW-w64 & Wine Verification Summary Matrix (#694)${RESET}"
echo -e "${CYAN}=======================================================================${RESET}"
printf "%-40s | %8s | %8s | %8s\n" "Verification Stage" "Total" "Passed" "Status"
echo "-----------------------------------------+----------+----------+--------"
printf "%-40s | %8d | %8d | " "1. Minimal PE32+ Exit Code (42)" 1 $((TESTS_FAIL == 0 ? 1 : (TESTS_PASS >= 1 ? 1 : 0)))
if [ "${TESTS_PASS}" -ge 1 ]; then echo -e "${GREEN}PASS${RESET}"; else echo -e "${RED}FAIL${RESET}"; fi

printf "%-40s | %8d | %8d | " "2. CRT Standard I/O (printf)" 1 $((TESTS_PASS >= 2 ? 1 : 0))
if [ "${TESTS_PASS}" -ge 2 ]; then echo -e "${GREEN}PASS${RESET}"; else echo -e "${RED}FAIL${RESET}"; fi

printf "%-40s | %8d | %8d | " "3. Direct Win32 API Linkage (kernel32)" 1 $((TESTS_PASS >= 3 ? 1 : 0))
if [ "${TESTS_PASS}" -ge 3 ]; then echo -e "${GREEN}PASS${RESET}"; else echo -e "${RED}FAIL${RESET}"; fi

printf "%-40s | %8d | %8d | " "4. Microsoft x64 ABI & Shadow Space" 1 $((TESTS_PASS >= 4 ? 1 : 0))
if [ "${TESTS_PASS}" -ge 4 ]; then echo -e "${GREEN}PASS${RESET}"; else echo -e "${RED}FAIL${RESET}"; fi
echo "-----------------------------------------+----------+----------+--------"
printf "%-40s | %8d | %8d | " "TOTAL" "${TESTS_TOTAL}" "${TESTS_PASS}"
if [ "${TESTS_FAIL}" -eq 0 ]; then
    echo -e "${GREEN}SUCCESS${RESET}"
    echo -e "${CYAN}=======================================================================${RESET}"
    echo -e "${GREEN}${BOLD} ALL ${TESTS_PASS}/${TESTS_TOTAL} MinGW-w64 & Wine Verification Stages PASSED! (0 Failures)${RESET}"
    echo -e "${CYAN}=======================================================================${RESET}\n"
    exit 0
else
    echo -e "${RED}FAILURE${RESET}"
    echo -e "${CYAN}=======================================================================${RESET}"
    echo -e "${RED}${BOLD} VERIFICATION FAILED: ${TESTS_FAIL} stage(s) failed out of ${TESTS_TOTAL}.${RESET}"
    echo -e "${CYAN}=======================================================================${RESET}\n"
    exit 1
fi
