---
ID: 552
種別: Bug
優先度: High
ステータス: Closed (Resolved)
---

# [BUG/SEC] ULisp自己ホストブートストラップにおけるLIR内car未束縛変数例外の修正 (ID: 552)

## 1. 概要 / Summary
`./test.sh` および `./bootstrap.sh` を実行した際、ブートストラップ検証がステージ 1 またはステージ 2 の自己ホストコンパイル（`scheme-stage1` または `ulisp-boot` による `ulisp_core.scm` の AOT コンパイル）途中で終了コード 1 となり、ステージ 3 や固定点検証（Fixed-point verification）が呼ばれずに異常終了する不具合が発生していた。

### 再現手順 / Steps to Reproduce
1. `./bootstrap.sh` を実行する。
2. `[1/3] Stage 1: Fast compiling ulisp_core.scm using native seed (/workspace/arxiv-security-papers/ulisp/bin/ulisp-boot)...` で停止し、ステージ 2・3 が実行されない。
3. また、`./test.sh` を実行した場合は、`[2/3] Stage 2: Compiling ulisp_core.scm with Stage 1 compiler...` で停止する。

### エラー内容 / Observed Error
```
*** ERROR: unhandled exception: (#<symbol> "Unbound variable in LIR: car" #<symbol>)
```

### 再現環境 / Environment
- OS / Env: Linux x86-64 / GCC Freestanding Zero-libc
- Files:
  - `ulisp/passes/06_lir.scm`
  - `ulisp/passes/07_backend_x86_64.scm`
  - `ulisp/lib/string.scm`
  - `ulisp/compiler.scm`
  - `ulisp/build/ulisp_core.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/06_lir.scm](../../ulisp/passes/06_lir.scm)
- [x] [ulisp/passes/07_backend_x86_64.scm](../../ulisp/passes/07_backend_x86_64.scm)
- [x] [ulisp/lib/string.scm](../../ulisp/lib/string.scm)
- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm)
- [x] [ulisp/test.sh](../../ulisp/test.sh)
- [x] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **Intrinsic 手続きの高階関数渡し規約違反**:
   ULisp AOT コンパイラでは、`car` や `cdr` は LIR 生成器において `%load` やインライン展開される組み込みプリミティブであり、一般のファーストクラス関数変数としては実行時環境（`env`）に束縛されていない。
   コミット `2408eab7f`（Issue #546）で `lir-compile-in-place-cont-call` および `lir-compile-let` に `(map car ...)` が混入し、自己ホストブートストラップ実行時に `(assq 'car env)` が `#f` となり `Unbound variable in LIR: car` が発生した。

2. **シンボルのハッシュ・整数変換ビットシフト量の不整合**:
   `ulisp/passes/06_lir.scm` において `integer->symbol` / `symbol->integer` のビットシフト量が誤って `8` に設定されていた。
   ULisp のタグ表現では Fixnum は `val << 2`、Symbol は `id << 8 | 2` であるため、Scheme レベルでの Fixnum から Symbol への変換は `id = fixnum >> 2`（すなわち `fixnum << 6 | 2`）が正しく、シフト量を `8` にすると 4 倍のオフセットが生じ、文字列から生成した動的シンボルとコンパイル時リテラルシンボルのハッシュ ID が一致せず `Unbound variable in LIR: x` が発生していた。

3. **`%cont-fun` ループ引数のレジスタ割り当て破壊**:
   `%cont-fun`（末尾再帰ループ）の引数をレジスタ（`%rbx`, `%r13`, `%r14`）に割り当てる最適化において、ループ本体から外部関数呼び出し（`call`）が発生した際に、ULisp の呼び出し規約上これらのレジスタが被呼出関数によって上書き・破壊されていた。
   安全なスタック渡しに統一し、インプレースシャッフルに `cont-target-all-regs?` ガードを設けることでレジスタ破壊を完全に根絶した。

4. **x86-64 バックエンドでの即値メモリオペランド GAS 構文**:
   `%store` およびスタック代入において、即値（integer）をメモリに直接書き込む際に `mov qword ptr [loc], imm` のサイズ指定子が必要であった点を修正。

---

## 4. 解決策と実装内容 / Resolution & Implementation
1. **`map car*` の適用**:
   `ulisp/passes/06_lir.scm` 内の素の `(map car ...)` をすべて `(map car* ...)` に修正。
2. **シンボルシフト量の復元**:
   `integer->symbol` を `(%bitwise-ior (%shift-left n 6) 2)`、`symbol->integer` を `(%shift-right (%shift-left s 56) 62)`（実質 `s >> 8` を fixnum `(s >> 8) << 2` = `s >> 6` に変換）に修正。
3. **継続関数のレジスタ割り当て保護**:
   `use-reg-alloc?` を安全なスタックパスに倒し、インプレースシャッフルが不正なレジスタアクセスを引き起こさないよう保護。
4. **GAS オペランド `qword ptr` の補正**:
   `ulisp/passes/07_backend_x86_64.scm` で即値メモリストア時に `mov qword ptr` を出力。
5. **自己ホストブートストラップ完全完走・不動点到達**:
   `ulisp/bootstrap.sh` を実行し、Stage 1 → Stage 2 → Stage 3 が完走。
   `cmp -s stage2.s stage3.s` により **Stage 2 と Stage 3 の生成コードが 1 ビットの狂いもなく完全一致（Fixed-point 到達）** を確認。
   最新の自己ホストバイナリが `ulisp/bin/ulisp-boot` に更新された。

---

## 5. 完了条件 (DoD) の検証結果 / Verification Results
- [x] `ulisp/passes/06_lir.scm` 内に素の `(map car ...)` が存在せず、`car*` を使用していること。
- [x] `make -C ulisp compiler` で `compiler.scm` が正常に結合・生成されること。
- [x] `ulisp/bootstrap.sh` が Stage 1〜3 まで完走し、`SUCCESS: Stage 2 and Stage 3 outputs are bit-for-bit IDENTICAL!` が出力されること。
- [x] `ulisp/test.sh` が完走し、全テスト項目（Step 0〜31、Phase 7 ブートストラップ）が正常終了（Exit Code 0）すること。
- [x] `tests/test_bare_metal_ulisp.py` が 9/9 件すべて PASS すること（9 passed in 467s）。
- [x] `make py_compile static_analysis` がエラー 0 件で完全 PASS すること。
