#!/usr/bin/env bash
set -euo pipefail

DIR="build/test_c99_gnu_ext"
APP="${DIR}/app_bin"
WEAK="${DIR}/weak_override_bin"

if [[ ! -x "$APP" ]] || [[ ! -x "$WEAK" ]]; then
  echo "FAIL: expected executables missing ($APP, $WEAK)"
  exit 1
fi

set +e
"$APP"
rc1=$?
"$WEAK"
rc2=$?
set -e

if [[ "$rc1" -ne 42 ]]; then
  echo "FAIL: $APP exited with $rc1 (expected 42)"
  exit 1
fi
if [[ "$rc2" -ne 42 ]]; then
  echo "FAIL: $WEAK exited with $rc2 (expected 42)"
  exit 1
fi

echo "[PASS] Native freestanding GNU-C binary $APP exited 42"
echo "[PASS] Native weak_alias override binary $WEAK exited 42"
