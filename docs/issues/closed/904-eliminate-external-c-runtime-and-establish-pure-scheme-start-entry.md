---
ID: 904
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] Eliminate External C Runtime and Establish Pure Scheme _start Entry (ID: 904)

## 1. 概要 / Summary

[[DSN-33-07]](../designs/DSN-33-07-ulisp_zero_libc_pure_scheme_bare_metal_runtime.md) 第 2 章・第 3 章に基づき、C 言語ランタイム（`runtime.c`）および libc への依存を完全に排除し、Pure Scheme アセンブリ `_start` エントリポイントおよび Linux x86-64 Raw Syscall（`sys-exit`, `sys-write`, `sys-read`, `sys-mmap`）直結アーキテクチャを確立する。

本基盤により、ULisp AOT コンパイラは `-nostdlib -static` フラグのみでリンク可能な極小・静的 ELF バイナリを直接出力可能となり、動的リンカ（`ld-linux.so`）や外部 C スタートアップコード（`crt1.o`, `crti.o`, `crtn.o`）が存在しない極限環境（ベアメタル、組み込み、Unikernel、セキュアコンテナ）において 100% 自給自足・自立走行（Freestanding）できる実行環境を確立する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-07] ULisp Zero-libc / Freestanding Pure Scheme ベアメタルランタイム包括設計書 (第2章・第3章)](../designs/DSN-33-07-ulisp_zero_libc_pure_scheme_bare_metal_runtime.md)
  - [[DSN-33] ULISP 包括設計仕様書 (第2章 ハードウェア・ABI 整合)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [[DSN-33-06] ILisp・ULisp AOT・ULisp JIT 3種実行系 継続的性能評価基盤 設計仕様書](../designs/DSN-33-06-ulisp_ilisp_aot_jit_continuous_benchmarking_framework.md)
- 先行 Issue:
  - [Issue #903: 統計的性能退行（Regression Detector）自動検知器および日本語ベンチマークレポート自動生成](closed/903-implement-performance-regression-detector-and-automated-markdown-reporting.md)
  - [Issue #902: 3種実行系（ILisp / AOT / JIT）自動ベンチマークハーネスおよび Mytkowicz バイアス排除の実装](closed/902-implement-automated-continuous-benchmarking-harness-and-mytkowicz-bias-elimination.md)
- 後続 Issue:
  - [Issue #905: ベアメタル自立型 Demand-Paged BSS バンプアロケータおよび Zero-libc 2-Space GC の実装](905-implement-freestanding-demand-paged-bss-bump-allocator-and-gc.md)
  - [Issue #906: 完全自立型静的 ELF (-nostdlib -static) の E2E 実行可能性および動的依存ゼロの検証](906-verify-freestanding-static-nostdlib-elf-e2e-execution.md)

---

## 3. 脅威モデルとセキュリティ要件 (Threat Model & Security Requirements)

| 脅威 ID | 分類 (STRIDE) | 脆弱性・リスク事象 | 対策方針・緩和策 |
| :--- | :--- | :--- | :--- |
| **TM-904-01** | Denial of Service (DoS) | スタック境界アライメント不整合による一般保護違反クラッシュ（CWE-119 / System V ABI） | Linux x86-64 カーネルから制御を受け取る `_start` エントリ直後において、`mov rbp, rsp` および `and rsp, -16` を実行し、任意の後続関数呼出前に 16 バイト境界スタックアライメントを保証する。 |
| **TM-904-02** | Information Disclosure / Crash | `argc`, `argv`, `envp` の境界外読み出し（CWE-125） | カーネルスタック上の引数ポインタ走査時、`argc >= 0` の検証および NULL ポインタ終端（`argv[argc] == 0`）の明示的境界チェックを実施。 |
| **TM-904-03** | Tampering / Crash | 不正ポインタまたは未整列アドレスに対するシステムコール発行（CWE-119） | `sys-write` および `sys-read` 発行時、Scheme 文字列・バッファポインタのアンタグ（`%ptr-untag`）を徹底し、カーネル空間への不正ポインタ受け渡しを防止。 |
| **TM-904-04** | Denial of Service (DoS) | `sys-mmap` 失敗時（`MAP_FAILED = -1`）の未検査参照による Null Pointer / OOM パニック（CWE-476 / CWE-400） | `sys-mmap` 戻り値の負値判定（`test rax, rax; js .L_start_exit`）を行い、メモリ獲得失敗時は libc に依存せず Raw Syscall `sys_exit(1)` で安全に緊急終了する。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

### 修正対象ファイル
- [`ulisp/runtime/entry.scm`](../../ulisp/runtime/entry.scm)
  - Pure Scheme レベルでのエントリポイント統合、コマンドライン引数（`command-line`）および環境変数（`get-environment-variable`）アクセス基盤。
- [`ulisp/lib/posix.scm`](../../ulisp/lib/posix.scm)
  - Raw Linux Syscall プリミティブ（`sys-exit`, `sys-write`, `sys-read`, `sys-mmap`, `sys-munmap`, `sys-open`, `sys-close`, `sys-lseek`, `sys-clock-gettime`）の配線およびゼロ外部依存バッファリング出力ルーチン。
- [`ulisp/backend/142_backend_x86_freestanding.scm`](../../ulisp/backend/142_backend_x86_freestanding.scm)
  - `-nostdlib -static` リンク時における libc 非依存 I/O（`ulisp_read_char`, `ulisp_peek_char`, `ulisp_flush`）、シンボル印字ルーチン、未処理例外ハンドラ、および OOM パニックルーチンの完全供給。
- [`ulisp/backend/elf64_builder.scm`](../../ulisp/backend/elf64_builder.scm)
  - 自立型静的 ELF 生成における `_start` シンボル解決とプログラムヘッダ（PT_LOAD, PT_GNU_STACK）整合。
- [`ulisp/Makefile`](../../ulisp/Makefile)
  - `test_freestanding_syscall` ターゲットの追加。
- [`tests/test_bare_metal_ulisp.py`](../../tests/test_bare_metal_ulisp.py)
  - Raw Syscall 単体実行および外部 C ランタイム完全排除の自動検証テストケース追加。

### 新規作成ファイル
- [`ulisp/tests/test_freestanding_syscall.scm`](../../ulisp/tests/test_freestanding_syscall.scm)
  - libc を一切リンクしない Pure Scheme ソースコードによる、Raw Syscall（`sys-write`, `sys-exit`, `sys-mmap`）およびフォーマット印字の E2E 検証スイート。

---

## 5. 詳細実装方針 / Detailed Implementation Plan

Target Branch: `feat/904-eliminate-external-c-runtime-and-establish-pure-scheme-start-entry`

### 5.1 Pure Scheme `_start` エントリポイント設計
1. **カーネルスタックレイアウト**:
   ```
   [rsp]                : argc (引数の個数)
   [rsp + 8]            : argv[0] (プログラム実行パス)
   ...
   [rsp + 8*argc]       : argv[argc-1]
   [rsp + 8*(argc+1)]   : NULL (0x0)
   [rsp + 8*(argc+2)]   : envp[0] (環境変数 "KEY=VAL")
   ...
   ```
2. **`_start` による初期化シーケンス (`140_backend_x86_64.scm`)**:
   - `mov rbp, rsp` および `and rsp, -16` でスタックアライメントを確立。
   - `argc`, `argv`, `envp` をそれぞれグローバルシンボル `ulisp_argc`, `ulisp_argv`, `ulisp_environ` に格納。
   - BSS 初期ヒープ領域または初期 `sys_mmap` により実行可能ヒープを獲得。
   - `scheme_entry` を呼び出し、Scheme 評価を開始。
   - 評価結果取得後、`ulisp_flush` でバッファをフラッシュし、戻り値ステータスで `mov rax, 60; syscall` を発行。

### 5.2 Linux x86-64 Raw Syscall 呼出規約 (`ulisp/lib/posix.scm`)
1. **x86-64 システムコール規約**:
   - レジスタ割当: `rax` (Syscall No), `rdi` (arg1), `rsi` (arg2), `rdx` (arg3), `r10` (arg4), `r8` (arg5), `r9` (arg6)。
   - ※ System V C 呼出規約の第 4 引数 `rcx` は `syscall` 命令によって戻り先 RIP の退避用としてカーネルに破壊されるため、必ず `r10` を使用。
2. **主要システムコールの番号定数マッピング**:
   - `sys-read` (0)
   - `sys-write` (1)
   - `sys-open` (2) / `sys-openat` (257)
   - `sys-close` (3)
   - `sys-lseek` (8)
   - `sys-mmap` (9)
   - `sys-munmap` (11)
   - `sys-exit` (60)
   - `sys-clock-gettime` (228)
3. **Pure Scheme バッファリング出力**:
   - `sys-write-char`, `sys-write-string`, `sys-write-fixnum`, `sys-newline` を libc なしで動作可能に整備。

### 5.3 Freestanding ランタイム生成 (`ulisp/backend/142_backend_x86_freestanding.scm`)
1. libc の `printf`, `malloc`, `exit`, `getchar`, `putchar` を一切参照せず、すべて直接インライン展開されたシステムコールまたは自前の固定バッファルーチン（`ulisp_io_buf`, `ulisp_peek_buf`, `ulisp_out_buf`）に委譲。
2. スタックマップメタデータテーブル（`__ulisp_stackmap_table`）およびシンボルテーブルを `.rodata` セクションに出力。

### 5.4 テスト計画
1. **`ulisp/tests/test_freestanding_syscall.scm`**:
   - `sys-write` で stdout (fd=1) に `"FREESTANDING_RAW_SYSCALL_OK\n"` を直接出力。
   - `sys-write-fixnum` で整数のフォーマット出力を検証。
   - `sys-mmap` で 4KB ページを動的確保し、メモリ読み書きを検証。
   - `sys-exit 0` でプロセス終了。
2. **`tests/test_bare_metal_ulisp.py`**:
   - `gcc -nostdlib -static`（または `as` + `ld -static`）でコンパイル・リンクし、外部依存ゼロ（`readelf -d` で NEEDED ライブラリ 0 件、`file` で `statically linked`）を検証。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `_start` エントリポイントが Pure Scheme コンパイル結果に正しく配置され、外部 C ランタイム（`runtime.c`）なしで起動できること。
- [x] Linux x86-64 Raw Syscall 呼出規約（`rax, rdi, rsi, rdx, r10, r8, r9`）に基づき、`sys-exit`, `sys-write`, `sys-read`, `sys-mmap` が正常動作すること。
- [x] `ulisp/tests/test_freestanding_syscall.scm` が作成され、外部 libc リンクなしで標準出力および正常終了が確認できること。
- [x] `make -C ulisp test_freestanding_syscall` および `pytest tests/test_bare_metal_ulisp.py` が 100% PASS すること。
- [x] 生成された静的バイナリにおいて動的ライブラリ依存が 0 件（`readelf` / `ldd` 検証）であること。
- [x] `make py_compile && make static_analysis` がエラー 0 件で合格すること。

---

## 7. 検証手順 / Verification Steps

```bash
# 1. 単体テスト実行 (Zero-libc Freestanding テスト)
pytest -v tests/test_bare_metal_ulisp.py

# 2. Scheme レベルの Raw Syscall テスト
make -C ulisp test_freestanding_syscall

# 3. 独立した静的バイナリの動的依存検証
readelf -d /tmp/test_freestanding_bin | grep NEEDED || echo "Zero external dependencies verified!"

# 4. コンパイラ全体の整合性検証
make -C ulisp test_passes

# 5. 静的解析とコンパイル検証
make py_compile && make static_analysis
```
