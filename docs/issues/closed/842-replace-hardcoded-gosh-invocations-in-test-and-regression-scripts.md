---
ID: 842
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] テストおよび回帰検証スクリプトにおける gosh 直書き呼出のネイティブ ulisp / ilisp 置換 (ID: 842)

## 1. 概要 / Summary
現在、AArch64 QEMU 回帰テストスクリプト（`test_aarch64_qemu_regression.sh`, `test_aarch64_qemu_smoke.sh`）や GC/プロファイラ計測スクリプト（`test_gc_stats.sh`, `test_pass_profiler.sh`）において、Scheme コンパイラの実行コマンドとして `gosh` がハードコード（直書き）されている。
このため、ホストに Gauche が存在しないミニマル環境や、純粋なセルフホストテスト環境において、これらスクリプトが即座にエラーとなってしまう。

本 Issue では、各スクリプトにおけるコンパイラ呼び出し処理を共通ヘルパーまたは適切な環境変数（`ULISP_COMPILER`, `ULISP_BOOT`, `ILISP`）による抽象化を行い、Gauche 未インストール環境下でもネイティブバイナリ（`./bin/ulisp-boot` / `./ulisp`）または Python 参照実装（`ilisp`）で完全に動作するよう改修する。

---

## 2. トレーサビリティ / Traceability
- **関連仕様・ドキュメント**:
  - `ulisp/docs/spec_pipeline.md` (自己完結型ツールチェイン・ゼロ外部依存仕様)
  - `ulisp/tests/test_pure_bootstrap.sh` (外部ツール完全マスキングテスト仕様)
- **依存関係**:
  - Issue 841 (ソースコード側の標準化) 完了後に実施することが推奨される。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/scripts/test_aarch64_qemu_regression.sh](../../ulisp/scripts/test_aarch64_qemu_regression.sh) (行 92, 206, 215, 265, 300: `gosh -I "${ULISP_DIR}" ...` の呼び出し箇所)
- [x] [ulisp/scripts/test_aarch64_qemu_smoke.sh](../../ulisp/scripts/test_aarch64_qemu_smoke.sh) (行 60: `gosh -I "${ULISP_DIR}" ...` の呼び出し箇所)
- [x] [ulisp/tests/test_gc_stats.sh](../../ulisp/tests/test_gc_stats.sh) (行 35〜37: `command -v gosh` の優先判定見直し)
- [x] [ulisp/tests/test_pass_profiler.sh](../../ulisp/tests/test_pass_profiler.sh) (行 39〜41: `command -v gosh` の優先判定見直し)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/842-replace-hardcoded-gosh-invocations`

1. **スクリプト共通のコンパイラ解決ロジック導入**:
   - `test_aarch64_qemu_regression.sh` および `test_aarch64_qemu_smoke.sh` の先頭に以下の解決関数を導入：
     ```bash
     resolve_compiler_cmd() {
         if [ -n "${ULISP_COMPILER:-}" ]; then
             echo "${ULISP_COMPILER}"
         elif [ -x "${ULISP_DIR}/bin/ulisp-boot" ]; then
             echo "${ULISP_DIR}/bin/ulisp-boot"
         elif [ -x "${ULISP_DIR}/ulisp" ]; then
             echo "${ULISP_DIR}/ulisp"
         elif [ -f "${ROOT_DIR}/.venv/bin/python" ]; then
             echo "${ROOT_DIR}/.venv/bin/python -m ilisp"
         elif command -v gosh >/dev/null 2>&1; then
             echo "gosh -I ${ULISP_DIR} ${ULISP_DIR}/compiler.scm"
         else
             echo "python3 -m ilisp"
         fi
     }
     ```
2. **ハードコード箇所の置換**:
   - `gosh -I "${ULISP_DIR}" "${ULISP_DIR}/compiler.scm" --target=aarch64 < "${src_file}" > "${asm_file}"` 形式の呼び出しを、上記で解決したコンパイラコマンド（標準入力を受け取り標準出力にアセンブリを出力）を使用する形へ変更。
3. **`test_gc_stats.sh` & `test_pass_profiler.sh` の整理**:
   - ネイティブバイナリの存在チェックを最優先とし、`gosh` への依存は補助的な第三候補へ降格。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `git grep "gosh" ulisp/scripts/` で直書きされたハードコード呼出が 0 件であること。
- [x] `gosh` を意図的に PATH から隠蔽した環境（スタブ環境または `PATH` 制限）で `./ulisp/scripts/test_aarch64_qemu_smoke.sh` が PASS すること。
- [x] `./ulisp/tests/test_gc_stats.sh` および `./ulisp/tests/test_pass_profiler.sh` がエラーなく実行できること。
