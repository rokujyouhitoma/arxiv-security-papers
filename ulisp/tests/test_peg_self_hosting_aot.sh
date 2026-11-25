#!/usr/bin/env bash
set -euo pipefail

ULISP_COMPILER_CMD="${ULISP_COMPILER_CMD:-./bin/ulisp-boot <}"
AS="${AS:-as}"
ASFLAGS="${ASFLAGS:---64}"
LD="${LD:-ld}"
LDFLAGS="${LDFLAGS:--m elf_x86_64 -static}"
RUN_SCHEME="${RUN_SCHEME:-gosh -usrfi.9 -ugauche.uvector -ugauche.process -uscheme.file -uscheme.bitwise -uscheme.process-context -I . -I ..}"
PYTHON="${PYTHON:-python3}"

echo "=== [Test Suite: PEG Self-Hosting & Native AOT Verification (Issue #948)] ==="

# 1. Verify Stage 1 == Stage 2 SHA-256 identical fixed-point
SHA1=$(sha256sum build/peg_meta_stage1.scm | awk '{print $1}')
SHA2=$(sha256sum build/peg_meta_stage2.scm | awk '{print $1}')
echo "Stage 1 SHA-256: ${SHA1}"
echo "Stage 2 SHA-256: ${SHA2}"
if [ "${SHA1}" != "${SHA2}" ]; then
  echo "[FAIL] Stage 1 .scm != Stage 2 .scm"
  exit 1
fi
echo "[PASS] Stage 1 .scm == Stage 2 .scm SHA-256 byte-identical fixed point verified."

# 2. Verify S-expression structural lint on Stage 1/2 and all 14 emitted grammars
${PYTHON} scripts/lint_sexpr.py build/peg_meta_stage1.scm build/peg_meta_stage2.scm build/test_emit_scm/*.peg.scm
echo "[PASS] lint_sexpr passed for Stage 1, Stage 2, and all 14 emitted grammar .scm files."

# 3. Audit zero CPS combinators and zero local set!
for f in build/peg_meta_stage1.scm build/test_emit_scm/*.peg.scm; do
  if grep -qE 'peg:(seq|alt|star|plus|opt|and|not|gather|rule)|rule-cells|\(set! ' "$f"; then
    echo "[FAIL] Found forbidden CPS combinator or local set! in $f"
    exit 1
  fi
done
echo "[PASS] Zero CPS combinators and zero local set! verified across all emitted .scm files."

# 4. Native x86-64 AOT compile & execute calc.peg Direct-Style parser via ulisp-boot
CALC_BIN="build/test_peg_calc_aot"
CALC_INPUT="build/test_peg_calc_aot_input.scm"
cat > "${CALC_INPUT}" << 'EOF'
(!gc none) (!allow-extern #t) (!disable-pass pass-synapse-inject-safepoints)
EOF
cat lib/stdlib_macros.scm peg/runtime.scm build/test_emit_scm/calc.peg.scm >> "${CALC_INPUT}"
cat >> "${CALC_INPUT}" << 'EOF'

(define (aot-main)
  (let* ((r1 (g_calc-parse-partial "10 + 20 * 3"))
         (r2 (g_calc-parse-partial "(10 + 20) * 3"))
         (r3 (g_calc-parse-partial "42"))
         (r4 (g_calc-parse-partial "bad")))
    (if (and (pair? r1) (= (cdr r1) 11)
             (pair? r2) (= (cdr r2) 13)
             (pair? r3) (= (cdr r3) 2)
             (not r4))
        (begin
          (display "CALC_AOT_OK ")
          (display (cdr r1)) (display " ")
          (display (cdr r2)) (display " ")
          (display (cdr r3))
          (newline)
          0)
        (begin
          (display "CALC_AOT_FAIL\n")
          1))))

(exit (aot-main))
EOF

eval "${ULISP_COMPILER_CMD} ${CALC_INPUT}" > "${CALC_BIN}.s"
${AS} ${ASFLAGS} "${CALC_BIN}.s" -o "${CALC_BIN}.o"
${LD} ${LDFLAGS} "${CALC_BIN}.o" build/ulisp_stdlib.o -o "${CALC_BIN}"
CALC_AOT_OUT=$("./${CALC_BIN}" < /dev/null)
echo "calc.peg Native AOT output: ${CALC_AOT_OUT}"
if [ "${CALC_AOT_OUT}" != "CALC_AOT_OK 11 13 2" ]; then
  echo "[FAIL] Unexpected calc.peg AOT output: ${CALC_AOT_OUT}"
  exit 1
fi
echo "[PASS] calc.peg native x86-64 AOT parser compiled and verified."

# 5. Native x86-64 AOT compile & execute peg_meta_stage1.scm on calc.peg and peg_meta.peg
META_BIN="build/test_peg_meta_aot"
META_INPUT="build/test_peg_meta_aot_input.scm"
cat > "${META_INPUT}" << 'EOF'
(!gc none) (!allow-extern #t) (!disable-pass pass-synapse-inject-safepoints)
EOF
cat lib/stdlib_macros.scm peg/runtime.scm build/peg_meta_stage1.scm >> "${META_INPUT}"
cat >> "${META_INPUT}" << 'EOF'

(define (%aot-read-text path)
  (call-with-input-file path
    (lambda (port)
      (let loop ((chunks '()))
        (let ((chunk (read-string 65536 port)))
          (if (or (eof-object? chunk) (= (string-length chunk) 0))
              (cond
                ((null? chunks) "")
                ((null? (cdr chunks)) (car chunks))
                (else (apply string-append (reverse chunks))))
              (loop (cons chunk chunks))))))))

(define (aot-meta-main)
  (let* ((calc-txt (%aot-read-text "../tools/grammars/calc.peg"))
         (meta-txt (%aot-read-text "../tools/grammars/peg_meta.peg"))
         (r-calc (peg-meta-parse-partial calc-txt))
         (r-meta (peg-meta-parse-partial meta-txt)))
    (if (and (pair? r-calc) (= (cdr r-calc) (string-length calc-txt))
             (pair? r-meta) (= (cdr r-meta) (string-length meta-txt)))
        (let ((calc-rules (cdr (assq 'rules (car r-calc))))
              (meta-rules (cdr (assq 'rules (car r-meta)))))
          (display "META_AOT_OK ")
          (display (length calc-rules))
          (display " ")
          (display (length meta-rules))
          (display " ")
          (display (cdr r-meta))
          (newline)
          0)
        (begin
          (display "META_AOT_FAIL\n")
          1))))

(exit (aot-meta-main))
EOF

eval "${ULISP_COMPILER_CMD} ${META_INPUT}" > "${META_BIN}.s"
${AS} ${ASFLAGS} "${META_BIN}.s" -o "${META_BIN}.o"
${LD} ${LDFLAGS} "${META_BIN}.o" build/ulisp_stdlib.o -o "${META_BIN}"
META_AOT_OUT=$("./${META_BIN}" < /dev/null)
echo "peg_meta_stage1.scm Native AOT output: ${META_AOT_OUT}"
META_LEN=$(wc -c < ../tools/grammars/peg_meta.peg)
if [ "${META_AOT_OUT}" != "META_AOT_OK 7 37 ${META_LEN}" ]; then
  echo "[FAIL] Unexpected peg_meta Native AOT output: ${META_AOT_OUT} (expected META_AOT_OK 7 37 ${META_LEN})"
  exit 1
fi
echo "[PASS] peg_meta_stage1.scm native x86-64 AOT binary parsed calc.peg (7 rules) and peg_meta.peg (37 rules, ${META_LEN} bytes)."
echo "[PASS] All PEG Self-Hosting & AOT tests passed."
