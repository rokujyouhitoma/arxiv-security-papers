---
ID: 516
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] libc/C依存完全排除と 100% Pure Scheme ベアメタル Linux ランタイム (%syscall・_start) の実装 (ID: 516)

## 1. 概要 / Summary

ULisp における C 言語ランタイム (`runtime.c`) および libc (glibc / musl) への依存を完全に排除し、Linux カーネルの Raw Syscall を直接叩く **完全自己完結型ベアメタル Linux ランタイム (Freestanding / Zero-libc)** を構築する。
コンパイラに低レベルシステムコール命令 `(%syscall ...)` およびカーネル直結エントリポイント `_start` を追加し、メモリ獲得 (`mmap`)、文字入出力 (`read`/`write`)、プロセス終了 (`exit`) を 100% Pure Scheme (`ulisp/lib/posix.scm`) で記述することで、外部依存ゼロの単一静的 ELF バイナリを直接出力可能にする。

---

## 2. トレーサビリティ / Traceability

- 関連設計文書:
  - [DSN-33 (ULisp 包括設計仕様書)](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-35 (継続的性能評価基盤 設計仕様書)](../../designs/DSN-35-ilisp_ulisp_aot_jit_continuous_benchmarking_framework.md)
  - [DSN-36 (Zero-libc Pure Scheme Bare-Metal Runtime 設計仕様書)](../../designs/DSN-36-zero_libc_pure_scheme_bare_metal_runtime.md)
- 関連Issue:
  - [Issue #515 (ILisp・ULisp AOT・ULisp JIT 3種実行系性能評価)](515-ilisp-ulisp-aot-jit-performance-benchmark-framework.md)
  - [Issue #501 (ULisp 2空間 Copying GC 実装)](501-implement-ulisp-target-garbage-collector.md)
  - [Issue #494 (ULisp 標準ライブラリと薄層ランタイム刷新)](494-modularize-ulisp-stdlib-and-minimal-c-runtime.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/passes/00_helpers.scm](file:///workspace/arxiv-security-papers/ulisp/passes/00_helpers.scm) (プリミティブ定義に `%raw-syscall`, `%to-raw`, `%to-fixnum` を追加)
- [x] [ulisp/passes/02_analysis.scm](file:///workspace/arxiv-security-papers/ulisp/passes/02_analysis.scm) (`septop-prim?` のスコープ解析)
- [x] [ulisp/passes/06_lir.scm](file:///workspace/arxiv-security-papers/ulisp/passes/06_lir.scm) (`lir-compile-raw-syscall`, `%to-raw`, `%to-fixnum`, `eof-object` の LIR 変換)
- [x] [ulisp/passes/07_backend_x86_64.scm](file:///workspace/arxiv-security-papers/ulisp/passes/07_backend_x86_64.scm) (`syscall` 命令の機械語出力、`.weak _start`、`.bss` 初期ヒープ領域出力)
- [x] [ulisp/lib/posix.scm](file:///workspace/arxiv-security-papers/ulisp/lib/posix.scm) (新規: 100% Pure Scheme による Raw Linux Syscall & I/O & Heap 初期化ライブラリ)
- [x] [ulisp/Makefile](file:///workspace/arxiv-security-papers/ulisp/Makefile) (`test_freestanding` ターゲット、`-nostdlib -static` リンク設定)
- [x] [tests/test_bare_metal_ulisp.py](file:///workspace/arxiv-security-papers/tests/test_bare_metal_ulisp.py) (新規: Zero-libc 静的バイナリの検証テスト)
- [x] [docs/designs/DSN-36-zero_libc_pure_scheme_bare_metal_runtime.md](file:///workspace/arxiv-security-papers/docs/designs/DSN-36-zero_libc_pure_scheme_bare_metal_runtime.md) (包括設計仕様書)
- [x] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md) (Issue台帳更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/516-zero-libc-pure-scheme-bare-metal-runtime`

1. **コンパイラ拡張 (%raw-syscall プリミティブ)**:
   - Linux x86-64 システムコール呼出規約 (`RAX`: 番号, `RDI`: a1, `RSI`: a2, `RDX`: a3, `R10`: a4, `R8`: a5, `R9`: a6) に準拠した `%raw-syscall` を実装。
2. **ベアメタルエントリポイント (`_start`) と初期ヒープ**:
   - カーネル直結の `.weak _start` ラベルを出力。
   - `.bss` セクションに 16MB のゼロ初期化ヒープ `ulisp_initial_heap` を配置し、`_start` 起動時に `RDI` にロードして `scheme_entry` を起動。
3. **100% Pure Scheme POSIX ライブラリ (`ulisp/lib/posix.scm`)**:
   - `sys-read` (syscall 0), `sys-write` (syscall 1), `sys-mmap` (syscall 9), `sys-exit` (syscall 60) を完全 Scheme で実装。
   - `sys-write-char`, `sys-write-string`, `sys-write-fixnum`, `sys-read-char` を自前実装。
4. **Zero-libc 静的バイナリ生成と検証**:
   - `gcc -nostdlib -static` で C ランタイム非依存の ELF バイナリを生成。
   - `ldd <binary>` で「`not a dynamic executable`（動的ライブラリ依存ゼロ）」であることを確認。
   - 算術計算・Fibonacci 再帰計算・文字列出力が正常に動作し exit code 0 で終了することを検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] コンパイラが `%raw-syscall` 構文を解釈し、Linux x86-64 `syscall` 命令を出力できること
- [x] `ulisp/lib/posix.scm` により、C言語ゼロで `sys-mmap`, `sys-read`, `sys-write`, `sys-exit` が Scheme 側で動作すること
- [x] `-nostdlib -static` でリンクしたバイナリが libc なしで正常に実行・終了（exit code 0）できること
- [x] `ldd` コマンドで外部共有ライブラリ依存が 0 件（静的自己完結）であること
- [x] 新規テスト `tests/test_bare_metal_ulisp.py` が PASS すること (2/2 PASS)
- [x] `make py_compile`, `flake8` 等の品質ゲートを通過すること
