#!/usr/bin/env bash
# =======================================================================
# Issue #926: Official Lua 5.4.7 Test Suite E2E Self-Host Verification
# Runs official lua-5.4.7-tests (all.lua, bwcoercion.lua, big.lua) on
# ULisp-compiled lua_ulisp and verifies 100% checkpoint & memory parity
# against reference lua_gcc.
# =======================================================================
set -euo pipefail

CALLER_PWD="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

LUA_VER="5.4.7"
LUA_TESTS_TARBALL_NAME="lua-${LUA_VER}-tests.tar.gz"
LUA_TESTS_URL="${LUA_TESTS_URL:-https://www.lua.org/tests/${LUA_TESTS_TARBALL_NAME}}"
LUA_TESTS_SHA256="8a4898ffe4c7613c8009327a0722db7a41ef861d526c77c5b46114e59ebf811e"

THIRD_PARTY_DIR="$ULISP_DIR/build/third_party"
TESTS_TARBALL_PATH="$THIRD_PARTY_DIR/$LUA_TESTS_TARBALL_NAME"
EXTRACTED_TESTS_DIR="$THIRD_PARTY_DIR/lua-${LUA_VER}-tests"

LUA_ULISP_BIN="$ULISP_DIR/build/lua_ulisp"
LUA_GCC_BIN="$ULISP_DIR/build/lua_gcc"
LUA_DIFF_GCC="${LUA_DIFF_GCC:-1}"
LUA_FULL_BIG="${LUA_FULL_BIG:-1}"

echo "========================================================================"
echo " Starting Official Lua ${LUA_VER} Test Suite E2E Verification (#926)"
echo "========================================================================"

# -----------------------------------------------------------------------
# 1. Ensure lua_ulisp (and lua_gcc) Binaries Are Built
# -----------------------------------------------------------------------
if [ "${REBUILD_LUA:-0}" = "1" ] || [ ! -x "$LUA_ULISP_BIN" ] || { [ "$LUA_DIFF_GCC" = "1" ] && [ ! -x "$LUA_GCC_BIN" ]; }; then
  echo "  [INFO] Building lua_ulisp and lua_gcc via tests/test_compile_lua.sh ..."
  LUA_DIFF_GCC="$LUA_DIFF_GCC" bash "$ULISP_DIR/tests/test_compile_lua.sh"
fi
echo "  [PASS] Verified executable: $LUA_ULISP_BIN"
if [ "$LUA_DIFF_GCC" = "1" ]; then
  echo "  [PASS] Verified reference executable: $LUA_GCC_BIN"
fi

# -----------------------------------------------------------------------
# 2. Resolve Official Lua 5.4.7 Test Suite Directory (Read-Only Cache)
# -----------------------------------------------------------------------
TESTS_SRC_DIR=""
if [ -n "${LUA_TESTS_DIR:-}" ]; then
  CAND="$LUA_TESTS_DIR"
  if [[ "$CAND" != /* ]]; then
    CAND="$CALLER_PWD/$CAND"
  fi
  if [ -f "$CAND/all.lua" ]; then
    TESTS_SRC_DIR="$(cd "$CAND" && pwd)"
  else
    echo "ERROR: LUA_TESTS_DIR='$LUA_TESTS_DIR' does not contain all.lua" >&2
    exit 1
  fi
  echo "  [INFO] Using caller-provided LUA_TESTS_DIR: $TESTS_SRC_DIR"
else
  mkdir -p "$THIRD_PARTY_DIR"
  if [ ! -f "$EXTRACTED_TESTS_DIR/all.lua" ]; then
    if [ ! -f "$TESTS_TARBALL_PATH" ]; then
      echo "  [INFO] Downloading official Lua ${LUA_VER} test suite from $LUA_TESTS_URL ..."
      if command -v curl >/dev/null 2>&1; then
        if ! curl --fail --location --retry 3 --connect-timeout 15 -o "$TESTS_TARBALL_PATH.tmp" "$LUA_TESTS_URL"; then
          rm -f "$TESTS_TARBALL_PATH.tmp"
          echo "ERROR: Failed to download $LUA_TESTS_URL (offline?)." >&2
          echo "       Provide $TESTS_TARBALL_PATH or set LUA_TESTS_DIR=/path/to/lua-${LUA_VER}-tests" >&2
          exit 1
        fi
        mv -f "$TESTS_TARBALL_PATH.tmp" "$TESTS_TARBALL_PATH"
      elif command -v wget >/dev/null 2>&1; then
        if ! wget -q --tries=3 --timeout=15 -O "$TESTS_TARBALL_PATH.tmp" "$LUA_TESTS_URL"; then
          rm -f "$TESTS_TARBALL_PATH.tmp"
          echo "ERROR: Failed to download $LUA_TESTS_URL (offline?)." >&2
          echo "       Provide $TESTS_TARBALL_PATH or set LUA_TESTS_DIR=/path/to/lua-${LUA_VER}-tests" >&2
          exit 1
        fi
        mv -f "$TESTS_TARBALL_PATH.tmp" "$TESTS_TARBALL_PATH"
      else
        echo "ERROR: Neither curl nor wget available and $TESTS_TARBALL_PATH is missing." >&2
        echo "       Set LUA_TESTS_DIR=/path/to/lua-${LUA_VER}-tests" >&2
        exit 1
      fi
    fi

    ACTUAL_SHA256="$(sha256sum "$TESTS_TARBALL_PATH" | awk '{print $1}')"
    if [ "$ACTUAL_SHA256" != "$LUA_TESTS_SHA256" ]; then
      echo "ERROR: SHA-256 mismatch for $TESTS_TARBALL_PATH!" >&2
      echo "       Expected: $LUA_TESTS_SHA256" >&2
      echo "       Actual:   $ACTUAL_SHA256" >&2
      rm -f "$TESTS_TARBALL_PATH"
      exit 1
    fi
    echo "  [PASS] Verified SHA-256 digest of $LUA_TESTS_TARBALL_NAME"

    if tar -tzf "$TESTS_TARBALL_PATH" | grep -E '(^/|^\.\./|/\.\./|/\.\.$)'; then
      echo "ERROR: Unsafe path entry (CWE-22) detected in $TESTS_TARBALL_PATH!" >&2
      exit 1
    fi
    echo "  [PASS] Archive path traversal check (CWE-22) passed"

    tar --no-same-owner -xzf "$TESTS_TARBALL_PATH" -C "$THIRD_PARTY_DIR"
  fi
  TESTS_SRC_DIR="$EXTRACTED_TESTS_DIR"
  echo "  [INFO] Using official Lua ${LUA_VER} test suite at: $TESTS_SRC_DIR"
fi

# -----------------------------------------------------------------------
# 3. Create Isolated Scratch Workspace for Test Execution
# -----------------------------------------------------------------------
RUN_WS="$ULISP_DIR/build/lua_tests_run_$$"
rm -rf "$RUN_WS"
mkdir -p "$RUN_WS/ulisp_run" "$RUN_WS/gcc_run"
trap 'rm -rf "$RUN_WS"' EXIT

cp -r "$TESTS_SRC_DIR/." "$RUN_WS/ulisp_run/"
if [ "$LUA_DIFF_GCC" = "1" ]; then
  cp -r "$TESTS_SRC_DIR/." "$RUN_WS/gcc_run/"
fi

# -----------------------------------------------------------------------
# 4. Phase 1: Standalone Official Auxiliary Script (bwcoercion.lua)
# -----------------------------------------------------------------------
echo "  [INFO] Phase 1: Running standalone bwcoercion.lua ..."
(
  cd "$RUN_WS/ulisp_run"
  timeout 30 "$LUA_ULISP_BIN" bwcoercion.lua > "$RUN_WS/bw_ulisp.out" 2>&1
)
if [ "$LUA_DIFF_GCC" = "1" ]; then
  (
    cd "$RUN_WS/gcc_run"
    timeout 30 "$LUA_GCC_BIN" bwcoercion.lua > "$RUN_WS/bw_gcc.out" 2>&1
  )
  diff -u "$RUN_WS/bw_gcc.out" "$RUN_WS/bw_ulisp.out"
fi
echo "  [PASS] Phase 1: bwcoercion.lua passed and matched reference"

# -----------------------------------------------------------------------
# 5. Phase 2: Full Official Test Suite (all.lua with _U=true & deterministic PRNG seed)
# -----------------------------------------------------------------------
DET_INIT='_U=true; do local r=math.randomseed; math.randomseed=function(a,b) if a==nil then return r(12345678,87654321) else return r(a,b) end end end'
echo "  [INFO] Phase 2: Running official all.lua (_U=true) across 26 modules ..."
(
  cd "$RUN_WS/ulisp_run"
  timeout 120 "$LUA_ULISP_BIN" -e "$DET_INIT" all.lua > "$RUN_WS/all_ulisp.out" 2>&1
)

EXPECTED_MODULES=(
  main.lua gc.lua db.lua calls.lua tpack.lua attrib.lua gengc.lua
  locals.lua constructs.lua code.lua cstack.lua nextvar.lua pm.lua
  utf8.lua api.lua events.lua vararg.lua closure.lua coroutine.lua
  goto.lua errors.lua math.lua sort.lua bitwise.lua verybig.lua files.lua
)
for mod in "${EXPECTED_MODULES[@]}"; do
  if ! grep -q "FILE '${mod}'" "$RUN_WS/all_ulisp.out"; then
    echo "ERROR: Missing expected test module banner FILE '${mod}' in all.lua output!" >&2
    exit 1
  fi
done

if ! grep -q "final OK !!!" "$RUN_WS/all_ulisp.out"; then
  echo "ERROR: 'final OK !!!' not reached in lua_ulisp all.lua output!" >&2
  tail -n 40 "$RUN_WS/all_ulisp.out" >&2
  exit 1
fi
if ! grep -q ">>> closing state <<<" "$RUN_WS/all_ulisp.out"; then
  echo "ERROR: '>>> closing state <<<' not reached in lua_ulisp all.lua output!" >&2
  exit 1
fi
echo "  [PASS] Phase 2: all.lua (26 modules + strings.lua/literals.lua) completed with 'final OK !!!'"

# -----------------------------------------------------------------------
# 6. Phase 3: Checkpoint & Memory Convergence Parity vs lua_gcc
# -----------------------------------------------------------------------
normalize_all_output() {
  sed -E '
    s/^[.+]+//;
    s/[.+]+$//;
    s/\+time:/time:/g;
    s/\.testing/testing/g;
    s/\.\.\.to-be-closed/to-be-closed/g;
    s/\.\.\.\+//g;
    s/\.\.\.OK/OK/g;
    s/\.\.OK/OK/g;
    s/\.OK/OK/g;
    s/^\.+//;
    s/^\++//;
    s/---- total memory: [0-9.]+[KM], max memory: ([0-9.]+[KM]) ----/---- total memory: <MEM>, max memory: \1 ----/g;
  ' "$1" | grep -v -E '^(random seeds:|time: |total time: |sorting 5000|re-sorting 5000|Invert-sorting|float random range|integer random range|test done on |[.+[:space:]]*$)' | sed -E 's/^[.+]+//; s/[.+]+$//'
}

if [ "$LUA_DIFF_GCC" = "1" ]; then
  echo "  [INFO] Phase 3: Running reference lua_gcc on all.lua and comparing checkpoints ..."
  (
    cd "$RUN_WS/gcc_run"
    timeout 120 "$LUA_GCC_BIN" -e "$DET_INIT" all.lua > "$RUN_WS/all_gcc.out" 2>&1
  )
  normalize_all_output "$RUN_WS/all_ulisp.out" > "$RUN_WS/norm_ulisp.out"
  normalize_all_output "$RUN_WS/all_gcc.out" > "$RUN_WS/norm_gcc.out"

  if ! diff -u "$RUN_WS/norm_gcc.out" "$RUN_WS/norm_ulisp.out"; then
    echo "ERROR: Normalized checkpoint/memory diff mismatch between lua_gcc and lua_ulisp!" >&2
    exit 1
  fi
  CHECKPOINT_LINES="$(wc -l < "$RUN_WS/norm_ulisp.out")"
  echo "  [PASS] Phase 3: 100% checkpoint & GC memory convergence match vs lua_gcc (${CHECKPOINT_LINES} lines)"
fi

# -----------------------------------------------------------------------
# 7. Phase 4: Heavy Non-Soft Large Table & Coroutine Suite (big.lua)
# -----------------------------------------------------------------------
BIG_TIME_U="N/A"
BIG_TIME_G="N/A"
if [ "$LUA_FULL_BIG" = "1" ]; then
  echo "  [INFO] Phase 4: Running heavy non-soft big.lua coroutine/table stress test ..."
  BIG_EXPR="local t0 = os.clock(); local f = coroutine.wrap(assert(loadfile('big.lua'))); assert(f() == 'b'); assert(f() == 'a'); collectgarbage(); local dt = os.clock() - t0; io.stderr:write(string.format('BIG_SEC=%.4f\n', dt)); print('big.lua: OK')"
  (
    cd "$RUN_WS/ulisp_run"
    timeout 60 "$LUA_ULISP_BIN" -e "$BIG_EXPR" > "$RUN_WS/big_ulisp.out" 2> "$RUN_WS/big_ulisp.err"
  )
  BIG_TIME_U="$(sed -n 's/^BIG_SEC=//p' "$RUN_WS/big_ulisp.err" | head -n 1)"
  if [ "$LUA_DIFF_GCC" = "1" ]; then
    (
      cd "$RUN_WS/gcc_run"
      timeout 60 "$LUA_GCC_BIN" -e "$BIG_EXPR" > "$RUN_WS/big_gcc.out" 2> "$RUN_WS/big_gcc.err"
    )
    BIG_TIME_G="$(sed -n 's/^BIG_SEC=//p' "$RUN_WS/big_gcc.err" | head -n 1)"
    diff -u "$RUN_WS/big_gcc.out" "$RUN_WS/big_ulisp.out"
  fi
  echo "  [PASS] Phase 4: Heavy big.lua stress test passed (GCC: ${BIG_TIME_G}s vs ULisp: ${BIG_TIME_U}s)"
fi

# -----------------------------------------------------------------------
# 8. Phase 5: Performance & Binary Size Comparison (lua_gcc vs lua_ulisp)
# -----------------------------------------------------------------------
if [ "$LUA_DIFF_GCC" = "1" ]; then
  echo "  [INFO] Phase 5: Running deterministic VM performance benchmark comparison (lua_gcc vs lua_ulisp) ..."
  cat > "$RUN_WS/bench_suite.lua" << 'EOF'
local function run_bench(name, fn)
  collectgarbage("collect")
  local t0 = os.clock()
  local checksum = fn()
  local dt = os.clock() - t0
  print(string.format("BENCH|%s|%.6f|%s", name, dt, tostring(checksum)))
end

-- 1. Tight integer & float arithmetic loop (5,000,000 iterations)
run_bench("vm_arith_loop", function()
  local s = 0
  local f = 1.5
  for i = 1, 5000000 do
    s = (s + i * 3) ~ (i >> 2)
    f = f + 0.25 - 0.125
  end
  return string.format("%d:%.2f", s, f)
end)

-- 2. Recursive call overhead (fib(31))
run_bench("fib_recursion", function()
  local function fib(n)
    if n < 2 then return n end
    return fib(n - 1) + fib(n - 2)
  end
  return fib(31)
end)

-- 3. Table array & hash insertion/lookup (250,000 entries)
run_bench("table_hash_array", function()
  local t = {}
  for i = 1, 250000 do
    t[i] = i * 2
  end
  local h = {}
  for i = 1, 100000 do
    h["k" .. i] = i
  end
  local sum = 0
  for i = 1, 250000 do
    sum = sum + t[i]
  end
  for i = 1, 100000 do
    sum = sum + h["k" .. i]
  end
  return sum
end)

-- 4. String format, pattern matching & binary pack/unpack (100,000 iterations)
run_bench("string_pattern_pack", function()
  local acc = 0
  for i = 1, 100000 do
    local s = string.format("id=%d,val=%.2f", i, i * 0.5)
    local m = string.match(s, "id=(%d+)")
    local p = string.pack("<i4d", i, i * 1.25)
    local a, b = string.unpack("<i4d", p)
    acc = acc + tonumber(m) + a + math.floor(b)
  end
  return acc
end)

-- 5. Coroutine resume/yield & GC object allocation churn (200,000 iterations)
run_bench("coroutine_gc_churn", function()
  local co = coroutine.create(function()
    local acc = 0
    for i = 1, 200000 do
      local obj = { i, i + 1, i + 2 }
      acc = acc + obj[1] + obj[3]
      if i % 4 == 0 then
        coroutine.yield(acc)
      end
    end
    return acc
  end)
  local last = 0
  while coroutine.status(co) ~= "dead" do
    local ok, v = coroutine.resume(co)
    assert(ok)
    last = v
  end
  return last
end)
EOF

  timeout 120 "$LUA_GCC_BIN" "$RUN_WS/bench_suite.lua" > "$RUN_WS/bench_gcc.out"
  timeout 120 "$LUA_ULISP_BIN" "$RUN_WS/bench_suite.lua" > "$RUN_WS/bench_ulisp.out"

  # Verify benchmark checksums match 100% between lua_gcc and lua_ulisp
  awk -F'|' '{print $2 "|" $4}' "$RUN_WS/bench_gcc.out" > "$RUN_WS/bench_gcc.chk"
  awk -F'|' '{print $2 "|" $4}' "$RUN_WS/bench_ulisp.out" > "$RUN_WS/bench_ulisp.chk"
  diff -u "$RUN_WS/bench_gcc.chk" "$RUN_WS/bench_ulisp.chk"

  if [ -x "$ULISP_DIR/../.venv/bin/python" ]; then
    PY_REPORT="$ULISP_DIR/../.venv/bin/python"
  else
    PY_REPORT="python3"
  fi

  "$PY_REPORT" - "$LUA_GCC_BIN" "$LUA_ULISP_BIN" "$RUN_WS/all_gcc.out" "$RUN_WS/all_ulisp.out" "$RUN_WS/bench_gcc.out" "$RUN_WS/bench_ulisp.out" "$BIG_TIME_G" "$BIG_TIME_U" "$ULISP_DIR/build/lua_perf_comparison.md" "$ULISP_DIR/build/lua_perf_comparison.json" << 'PY'
import json, os, re, subprocess, sys

gcc_bin, ulisp_bin, all_g, all_u, bench_g, bench_u, big_g, big_u, out_md, out_json = sys.argv[1:11]

def get_sizes(path):
    fsize = os.path.getsize(path)
    out = subprocess.check_output(["size", "-B", path], text=True).splitlines()[1].split()
    return {
        "file_bytes": fsize,
        "text_bytes": int(out[0]),
        "data_bytes": int(out[1]),
        "bss_bytes": int(out[2]),
    }

def parse_all_total(path):
    txt = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r"total time:\s*([0-9.]+)s", txt)
    return float(m.group(1)) if m else 0.0

def parse_all_modules(path):
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    times = []
    cur_dt = None
    for ln in lines:
        mt = re.search(r"time:\s*[0-9.]+\s*\(\+([0-9.]+)\)", ln)
        if mt:
            cur_dt = float(mt.group(1))
        mf = re.search(r"\*\*\*\*\* FILE '([^']+)'\*\*\*\*\*", ln)
        if mf and cur_dt is not None:
            times.append((mf.group(1), cur_dt))
            cur_dt = None
    # Each time: (+dt) precedes the NEXT FILE banner, so shift by 1 to attribute dt to the previous file
    mod_dt = {}
    for idx in range(len(times) - 1):
        mod_dt[times[idx][0]] = times[idx + 1][1]
    return mod_dt

def parse_bench(path):
    res = {}
    for ln in open(path, encoding="utf-8").read().splitlines():
        parts = ln.strip().split("|")
        if len(parts) == 4 and parts[0] == "BENCH":
            res[parts[1]] = (float(parts[2]), parts[3])
    return res

sg = get_sizes(gcc_bin)
su = get_sizes(ulisp_bin)
all_tot_g = parse_all_total(all_g)
all_tot_u = parse_all_total(all_u)
mods_g = parse_all_modules(all_g)
mods_u = parse_all_modules(all_u)
bg = parse_bench(bench_g)
bu = parse_bench(bench_u)

def ratio_str(u, g):
    if g <= 0:
        return "N/A"
    return f"{u / g:.2f}x"

md = []
md.append("# Lua 5.4.7 Performance & Binary Size Comparison: `lua_gcc` (GCC -O2) vs `lua_ulisp` (ULisp -O2)\n")
md.append("## 1. Binary & ELF Section Size Comparison\n")
md.append("| Metric | `lua_gcc` (GCC 13.3 -O2) | `lua_ulisp` (ULisp -O2) | Ratio (`ULisp / GCC`) |")
md.append("| :--- | ---: | ---: | ---: |")
md.append(f"| **Total ELF File Size** | {sg['file_bytes']:,} B | {su['file_bytes']:,} B | **{ratio_str(su['file_bytes'], sg['file_bytes'])}** |")
md.append(f"| **`.text` (Machine Code)** | {sg['text_bytes']:,} B | {su['text_bytes']:,} B | **{ratio_str(su['text_bytes'], sg['text_bytes'])}** |")
md.append(f"| **`.data` (Initialized Data)** | {sg['data_bytes']:,} B | {su['data_bytes']:,} B | {ratio_str(su['data_bytes'], sg['data_bytes'])} |")
md.append(f"| **`.bss` (Zero-Init Data)** | {sg['bss_bytes']:,} B | {su['bss_bytes']:,} B | {ratio_str(su['bss_bytes'], sg['bss_bytes'])} |")
md.append("")
md.append("## 2. Official Test Suite (`all.lua` & `big.lua`) Execution Time Comparison\n")
md.append("| Suite / Workload | `lua_gcc` (s) | `lua_ulisp` (s) | Ratio (`ULisp / GCC`) | Status |")
md.append("| :--- | ---: | ---: | ---: | :---: |")
md.append(f"| **Official `all.lua` (`_U=true`, 26 modules)** | {all_tot_g:.3f} s | {all_tot_u:.3f} s | **{ratio_str(all_tot_u, all_tot_g)}** | PASS (`final OK !!!`) |")
if big_g != "N/A" and big_u != "N/A":
    fg, fu = float(big_g), float(big_u)
    md.append(f"| **Heavy `big.lua` (Non-Soft Large Table/Coroutine)** | {fg:.3f} s | {fu:.3f} s | **{ratio_str(fu, fg)}** | PASS |")
for mod in ["calls.lua", "locals.lua", "cstack.lua", "db.lua", "constructs.lua", "math.lua", "sort.lua", "nextvar.lua", "errors.lua"]:
    if mod in mods_g and mod in mods_u:
        md.append(f"| `all.lua` module: `{mod}` | {mods_g[mod]:.4f} s | {mods_u[mod]:.4f} s | {ratio_str(mods_u[mod], mods_g[mod])} | PASS |")
md.append("")
md.append("## 3. Deterministic VM Micro-Benchmark Comparison (`os.clock()`)\n")
md.append("| Benchmark Workload | `lua_gcc` (s) | `lua_ulisp` (s) | Ratio (`ULisp / GCC`) | Checksum Parity |")
md.append("| :--- | ---: | ---: | ---: | :---: |")
bench_json = {}
for k in ["vm_arith_loop", "fib_recursion", "table_hash_array", "string_pattern_pack", "coroutine_gc_churn"]:
    tg, cg = bg[k]
    tu, cu = bu[k]
    assert cg == cu
    bench_json[k] = {"gcc_sec": tg, "ulisp_sec": tu, "ratio": round(tu / tg, 3) if tg > 0 else None, "checksum": cu}
    md.append(f"| **`{k}`** | {tg:.4f} s | {tu:.4f} s | **{ratio_str(tu, tg)}** | Exact Match (`{cu}`) |")

report_text = "\n".join(md) + "\n"
open(out_md, "w", encoding="utf-8").write(report_text)
open(out_json, "w", encoding="utf-8").write(json.dumps({
    "sizes": {"gcc": sg, "ulisp": su},
    "all_lua_sec": {"gcc": all_tot_g, "ulisp": all_tot_u, "ratio": round(all_tot_u / all_tot_g, 3) if all_tot_g > 0 else None},
    "big_lua_sec": {"gcc": float(big_g) if big_g != "N/A" else None, "ulisp": float(big_u) if big_u != "N/A" else None},
    "module_sec": {"gcc": mods_g, "ulisp": mods_u},
    "microbenchmarks": bench_json,
}, indent=2))
print("\n" + report_text)
PY
  echo "  [PASS] Phase 5: Performance & binary size comparison saved to build/lua_perf_comparison.md and build/lua_perf_comparison.json"
fi

echo "========================================================================"
echo " Official Lua ${LUA_VER} Test Suite E2E Self-Host Verification: ALL PASS"
echo "========================================================================"
